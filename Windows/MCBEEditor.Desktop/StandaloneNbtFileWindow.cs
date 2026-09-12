using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;
using Microsoft.Win32;

namespace MCBEEditor.Desktop;

public sealed class StandaloneNbtFileWindow : Window
{
    private sealed record RootRow(int Index, string Name, string Type, string Summary)
    {
        public string DisplayIndex => Index.ToString(CultureInfo.InvariantCulture);
    }

    private readonly StandaloneNbtFile _file;
    private readonly List<NbtDocument> _documents;
    private readonly TextBox _search = new();
    private readonly DataGrid _grid = new();
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.DimGray };
    private bool _dirty;

    public StandaloneNbtFileWindow(StandaloneNbtFile file)
    {
        _file = file ?? throw new ArgumentNullException(nameof(file));
        _documents = file.Documents.Select(document => new NbtDocument(document.RootName, NbtDocumentTools.DeepClone(document.Root))).ToList();
        Title = file.OriginalFilename + " · NBT/mcstructure 工具";
        Width = 980;
        Height = 680;
        MinWidth = 760;
        MinHeight = 500;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi();
        Rebuild();
    }

    private UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(10) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        _search.ToolTip = "搜索根标签名称、NBT 名称、值或类型";
        _search.TextChanged += (_, _) => Rebuild();
        Grid.SetRow(_search, 0);
        root.Children.Add(_search);

        _grid.AutoGenerateColumns = false;
        _grid.IsReadOnly = true;
        _grid.CanUserAddRows = false;
        _grid.RowHeaderWidth = 0;
        _grid.SelectionMode = DataGridSelectionMode.Extended;
        _grid.SelectionUnit = DataGridSelectionUnit.FullRow;
        _grid.Columns.Add(new DataGridTextColumn { Header = "#", Binding = new Binding(nameof(RootRow.DisplayIndex)), Width = 55 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "根名称", Binding = new Binding(nameof(RootRow.Name)), Width = 260 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "类型", Binding = new Binding(nameof(RootRow.Type)), Width = 120 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "摘要", Binding = new Binding(nameof(RootRow.Summary)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        _grid.MouseDoubleClick += (_, e) => { if (e.ChangedButton == MouseButton.Left) EditSelected(); };
        Grid.SetRow(_grid, 1);
        root.Children.Add(_grid);

        var actions = new WrapPanel { Margin = new Thickness(0, 8, 0, 0) };
        actions.Children.Add(Button("打开/编辑", (_, _) => EditSelected()));
        actions.Children.Add(Button("重命名根", (_, _) => RenameSelectedRoot()));
        actions.Children.Add(Button("新增根 Compound", (_, _) => AddRoot()));
        actions.Children.Add(Button("导入根标签", (_, _) => ImportRoots()));
        actions.Children.Add(Button("删除所选根", (_, _) => DeleteSelected()));
        actions.Children.Add(Button("原格式导出", (_, _) => ExportOriginal()));
        actions.Children.Add(Button("JSON", (_, _) => ExportJson()));
        actions.Children.Add(Button("Little Endian", (_, _) => ExportNbt(NbtEncoding.LittleEndian, "-little-endian")));
        actions.Children.Add(Button("VarInt", (_, _) => ExportNbt(NbtEncoding.LittleEndianVarInt, "-little-varint")));
        actions.Children.Add(Button("Big Endian", (_, _) => ExportNbt(NbtEncoding.BigEndian, "-big-endian")));
        actions.Children.Add(Button("转换为 .mcstructure", (_, _) => ExportMcStructure()));
        Grid.SetRow(actions, 2);
        root.Children.Add(actions);

        _status.Margin = new Thickness(0, 7, 0, 0);
        Grid.SetRow(_status, 3);
        root.Children.Add(_status);
        return root;
    }

    private static Button Button(string text, RoutedEventHandler handler)
    {
        var button = new Button { Content = text, Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(0, 0, 6, 0) };
        button.Click += handler;
        return button;
    }

    private void Rebuild()
    {
        var query = _search.Text.Trim();
        var rows = _documents.Select((document, index) => new RootRow(index,
            PrimaryName(document), document.Root.Type.ToString(), document.Root.Summary)).ToArray();
        if (query.Length > 0)
            rows = rows.Where(row => row.Name.Contains(query, StringComparison.OrdinalIgnoreCase)
                || row.Type.Contains(query, StringComparison.OrdinalIgnoreCase)
                || NbtDocumentTools.Search(_documents[row.Index], query, 1).Count > 0).ToArray();
        _grid.ItemsSource = rows;
        if (_grid.SelectedItem is null && rows.Length > 0) _grid.SelectedItem = rows[0];
        _status.Text = $"{_file.FormatDescription} · 根标签 {_documents.Count:N0} 个" + (_dirty ? " · 有未导出的修改" : string.Empty)
            + "。压缩输入导出为未压缩数据；Java 结构转换与 iOS 版一样忽略实体、水层和高级 BlockEntity 数据。";
    }

    private void EditSelected()
    {
        if (_grid.SelectedItem is not RootRow row || (uint)row.Index >= (uint)_documents.Count) return;
        var editor = new NbtEditorWindow($"{Title} · #{row.Index}", _documents[row.Index], edited =>
        {
            _documents[row.Index] = edited;
            _dirty = true;
            Rebuild();
            return Task.CompletedTask;
        }, Array.Empty<string>(), _file.OriginalEncoding) { Owner = this };
        editor.ShowDialog();
        if (editor.DidSave) Rebuild();
    }

    private void RenameSelectedRoot()
    {
        if (_grid.SelectedItem is not RootRow row || (uint)row.Index >= (uint)_documents.Count) return;
        var current = _documents[row.Index];
        var name = NbtTextPromptWindow.Show(this, "重命名 NBT 根标签", "根名称可以为空：", current.RootName);
        if (name is null) return;
        _documents[row.Index] = new NbtDocument(name, current.Root);
        _dirty = true;
        Rebuild();
    }

    private void AddRoot()
    {
        var name = NbtTextPromptWindow.Show(this, "新增 NBT 根标签", "根标签名称可以为空：", string.Empty);
        if (name is null) return;
        _documents.Add(new NbtDocument(name, new NbtCompoundValue(Array.Empty<NbtNamedTag>())));
        _dirty = true;
        _search.Clear();
        Rebuild();
        _grid.SelectedIndex = _documents.Count - 1;
    }

    private void ImportRoots()
    {
        var dialog = new OpenFileDialog
        {
            Title = "导入 NBT 根标签",
            Filter = "NBT / mcstructure / JSON|*.nbt;*.mcstructure;*.json|所有文件|*.*",
            Multiselect = false
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var imported = StandaloneNbtFileCodec.Decode(File.ReadAllBytes(dialog.FileName), dialog.FileName);
            foreach (var document in imported.Documents)
                _documents.Add(new NbtDocument(document.RootName, NbtDocumentTools.DeepClone(document.Root)));
            _dirty = true;
            _search.Clear();
            Rebuild();
            _status.Text = $"已导入 {imported.Documents.Count:N0} 个根标签 · {_file.FormatDescription} · 有未导出的修改。";
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "导入根标签失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void DeleteSelected()
    {
        var indexes = _grid.SelectedItems.Cast<RootRow>().Select(row => row.Index).Distinct().OrderByDescending(index => index).ToArray();
        if (indexes.Length == 0) return;
        if (_documents.Count - indexes.Length < 1)
        {
            MessageBox.Show(this, "NBT 文件至少需要保留一个根标签。", Title, MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (MessageBox.Show(this, $"删除所选 {indexes.Length} 个 NBT 根标签？", "确认删除", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        foreach (var index in indexes) if ((uint)index < (uint)_documents.Count) _documents.RemoveAt(index);
        _dirty = true;
        Rebuild();
    }

    private void ExportOriginal()
    {
        if (_file.OriginalWasJson) { ExportBytes(StandaloneNbtFileCodec.EncodeJson(_documents), BaseFilename() + ".json", "JSON NBT|*.json"); return; }
        var ext = string.Equals(_file.OriginalExtension, "mcstructure", StringComparison.OrdinalIgnoreCase) ? ".mcstructure" : ".nbt";
        ExportBytes(StandaloneNbtFileCodec.Encode(_documents, _file.OriginalEncoding), BaseFilename() + ext, ext == ".mcstructure" ? "Bedrock mcstructure|*.mcstructure" : "NBT 文件|*.nbt");
    }

    private void ExportJson() => ExportBytes(StandaloneNbtFileCodec.EncodeJson(_documents), BaseFilename() + ".json", "JSON NBT|*.json");
    private void ExportNbt(NbtEncoding encoding, string suffix) => ExportBytes(StandaloneNbtFileCodec.Encode(_documents, encoding), BaseFilename() + suffix + ".nbt", "NBT 文件|*.nbt");

    private void ExportMcStructure()
    {
        try
        {
            var converted = StandaloneNbtFileCodec.EncodeAsMcStructure(_documents);
            ExportBytes(converted.Data, BaseFilename() + ".mcstructure", "Bedrock mcstructure|*.mcstructure");
            if (converted.Result.ConvertedFromJava)
            {
                var loss = converted.Result.LossyPaletteEntryCount == 0 ? string.Empty : $"；兼容降级 {converted.Result.LossyPaletteEntryCount} 个调色板条目";
                MessageBox.Show(this, $"Java 结构转换完成：{converted.Result.PlacedBlockCount:N0} 个方块、{converted.Result.PaletteEntryCount:N0} 个调色板条目{loss}。", "mcstructure 转换", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "转换失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void ExportBytes(byte[] data, string fileName, string filter)
    {
        try
        {
            var dialog = new SaveFileDialog { Title = "导出 NBT / mcstructure", Filter = filter + "|所有文件|*.*", FileName = SafeFileName(fileName), AddExtension = true };
            if (dialog.ShowDialog(this) != true) return;
            File.WriteAllBytes(dialog.FileName, data);
            _dirty = false;
            Rebuild();
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "导出失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private static string PrimaryName(NbtDocument document)
    {
        foreach (var key in new[] { "name", "Name", "identifier", "id" })
            if (document.Root.StringValue(key) is { Length: > 0 } value) return value;
        if (!string.IsNullOrEmpty(document.RootName)) return document.RootName;
        return "未命名 " + document.Root.Type;
    }

    private string BaseFilename()
    {
        var value = Path.GetFileNameWithoutExtension(_file.OriginalFilename);
        return string.IsNullOrWhiteSpace(value) ? "document" : value;
    }

    private static string SafeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var result = new string(value.Select(ch => invalid.Contains(ch) ? '_' : ch).ToArray()).Trim();
        return result.Length == 0 ? "document.nbt" : result;
    }
}
