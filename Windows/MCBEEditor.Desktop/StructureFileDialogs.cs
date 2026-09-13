using System.IO;
using System.Windows;
using System.Windows.Controls;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;
using Microsoft.Win32;

namespace MCBEEditor.Desktop;

internal static class StructureFileDialogs
{
    private const string ExportFilter = "Bedrock mcstructure|*.mcstructure|NBT · Big Endian|*.nbt|JSON NBT|*.json";
    private static TargetingCommandExecutionResult Cancelled => TargetingCommandExecutionResult.Success("已取消。", false);

    public static async Task<TargetingCommandExecutionResult> ImportAsync(Window owner, WorldDocument world, Func<Task> prepareMutation, string? name = null)
    {
        var open = new OpenFileDialog { Title = "导入结构", Filter = "结构文件|*.mcstructure;*.nbt;*.json|所有文件|*.*", Multiselect = false };
        if (open.ShowDialog(owner) != true) return Cancelled;
        var file = await Task.Run(() => StandaloneNbtFileCodec.Decode(File.ReadAllBytes(open.FileName), open.FileName));
        if (file.Documents.Count != 1) throw new InvalidDataException("结构文件必须只包含一个 NBT 根标签。");
        name ??= NbtTextPromptWindow.Show(owner, "指定结构名称", "可使用 namespace:name 格式：", Path.GetFileNameWithoutExtension(open.FileName));
        if (name is null) return Cancelled;
        name = StructureNbtStore.NormalizeName(name);
        _ = StructureNbtStore.KeyForName(name);
        var exists = await Task.Run(() =>
        {
            using var database = world.OpenDatabase(readOnly: true);
            return new StructureNbtStore(database).Contains(name);
        });
        if (exists && MessageBox.Show(owner, $"世界中已存在“{name}”。继续将覆盖原结构。", "替换同名结构？", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
            return Cancelled;
        await prepareMutation();
        var result = await Task.Run(() =>
        {
            using var database = world.OpenDatabase(readOnly: false);
            return new StructureNbtStore(database).SaveNew(file.Documents[0], name, overwrite: exists);
        });
        var message = $"structure import 完成：{name}";
        if (result.ConvertedFromJava)
            message += $"；Java → Bedrock，{result.PlacedBlockCount} 个方块，{result.LossyPaletteEntryCount} 个调色板条目发生兼容降级；不带入实体、水层及高级方块实体数据。";
        return TargetingCommandExecutionResult.Success(message, true);
    }

    public static async Task<TargetingCommandExecutionResult> ExportAsync(Window owner, WorldDocument world, StructureFileFormat format, string? name)
    {
        var records = await Task.Run(() =>
        {
            using var database = world.OpenDatabase(readOnly: true);
            return new StructureNbtStore(database).Records();
        });
        if (name is null && records.Count == 0) return TargetingCommandExecutionResult.Success("没有已保存的结构。", false);
        StructureNbtRecord? record;
        if (name is null) record = Choose(owner, "选择要导出的结构", records, r => r.DisplayName);
        else
        {
            var key = StructureNbtStore.KeyForName(name);
            record = records.FirstOrDefault(r => r.Key.AsSpan().SequenceEqual(key)) ?? throw new InvalidDataException($"不存在结构：{name}");
        }
        if (record is null) return Cancelled;
        return ExportSingle(owner, record.Document ?? throw new InvalidDataException($"结构 NBT 无法解析：{record.DisplayName}"), record.DisplayName, format);
    }

    public static TargetingCommandExecutionResult ExportSingle(Window owner, NbtDocument document, string name, StructureFileFormat? format = null)
    {
        var extension = Extension(format ?? StructureFileFormat.Mcstructure);
        var save = new SaveFileDialog
        {
            Title = "导出结构", Filter = format.HasValue ? $"{extension} 文件|*.{extension}" : ExportFilter,
            FileName = SafeName(name), DefaultExt = format.HasValue ? "." + extension : string.Empty, AddExtension = true, OverwritePrompt = true
        };
        if (save.ShowDialog(owner) != true) return Cancelled;
        var selectedFormat = format ?? (StructureFileFormat)(save.FilterIndex - 1);
        if (!Path.GetExtension(save.FileName).Equals("." + Extension(selectedFormat), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("文件扩展名与所选导出格式不一致，请重新选择文件类型和文件名。");
        var data = StandaloneNbtFileCodec.EncodeStructure(document, selectedFormat);
        File.WriteAllBytes(save.FileName, data);
        return TargetingCommandExecutionResult.Success($"structure export 完成：{Path.GetFileName(save.FileName)}", false);
    }

    public static void ExportMany(Window owner, IReadOnlyList<StructureNbtRecord> records)
    {
        var choices = Enum.GetValues<StructureFileFormat>();
        var selection = Choose(owner, "选择结构导出格式", choices.Select(f => new FormatChoice(f)).ToArray(), x => x.Format == StructureFileFormat.Nbt ? "NBT · Big Endian (.nbt)" : "." + Extension(x.Format));
        if (selection is null) return;
        var format = selection.Format;
        // Validate all records before writing any selected structure.
        var payloads = records.Select(r => (Name: SafeName(r.DisplayName), Data: StandaloneNbtFileCodec.EncodeStructure(
            r.Document ?? throw new InvalidDataException($"结构 NBT 无法解析：{r.DisplayName}"), format))).ToArray();
        var folder = new OpenFolderDialog { Title = $"选择目录以导出 {records.Count} 个结构", Multiselect = false };
        if (folder.ShowDialog(owner) != true) return;
        var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var payload in payloads)
        {
            var filename = payload.Name + "." + Extension(format);
            for (var suffix = 2; used.Contains(filename) || File.Exists(Path.Combine(folder.FolderName, filename)); suffix++)
                filename = payload.Name + "-" + suffix + "." + Extension(format);
            used.Add(filename);
            File.WriteAllBytes(Path.Combine(folder.FolderName, filename), payload.Data);
        }
    }

    private sealed record FormatChoice(StructureFileFormat Format);
    private static string Extension(StructureFileFormat format) => format.ToString().ToLowerInvariant();
    private static string SafeName(string name)
    {
        foreach (var c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
        name = name.Trim().TrimEnd('.');
        return string.IsNullOrEmpty(name) ? "structure" : name[..Math.Min(120, name.Length)];
    }

    private static T? Choose<T>(Window owner, string title, IReadOnlyList<T> values, Func<T, string> label) where T : class
    {
        var window = new Window { Owner = owner, Title = title, Width = 520, Height = 190, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock { Text = title, Margin = new Thickness(0, 0, 0, 12) });
        var combo = new ComboBox { ItemsSource = values.Select(label).ToArray(), SelectedIndex = 0, IsTextSearchEnabled = true, MaxDropDownHeight = 360 };
        panel.Children.Add(combo);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        var ok = new Button { Content = "选择", IsDefault = true, MinWidth = 75, Padding = new Thickness(10, 4, 10, 4) };
        ok.Click += (_, _) => window.DialogResult = true;
        buttons.Children.Add(ok);
        buttons.Children.Add(new Button { Content = "取消", IsCancel = true, MinWidth = 75, Margin = new Thickness(8, 0, 0, 0) });
        panel.Children.Add(buttons);
        window.Content = panel;
        return window.ShowDialog() == true && combo.SelectedIndex >= 0 ? values[combo.SelectedIndex] : null;
    }
}
