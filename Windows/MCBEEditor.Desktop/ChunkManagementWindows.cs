using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.World;

namespace MCBEEditor.Desktop;

public enum ChunkBatchAction
{
    SearchReplace,
    LayerReplace,
    SetBiome,
    TickingArea,
    DeleteHardcodedSpawners,
    Clear,
    Regenerate
}

public sealed class ChunkBatchActionWindow : Window
{
    public ChunkBatchAction? SelectedAction { get; private set; }

    public ChunkBatchActionWindow(int count)
    {
        Title = $"批量处理 {count:N0} 个区块";
        Width = 560;
        Height = 500;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi(count);
    }

    private UIElement BuildUi(int count)
    {
        var root = new StackPanel { Margin = new Thickness(18) };
        root.Children.Add(new TextBlock
        {
            Text = $"当前精确选择 {count:N0} 个区块。操作只作用于选中的区块，可跨维度选择；常加载区域要求所选区块位于同一维度。",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12)
        });
        root.Children.Add(ActionButton("方块搜索替换…", ChunkBatchAction.SearchReplace));
        root.Children.Add(ActionButton("批量层 0 / 层 1 替换…", ChunkBatchAction.LayerReplace));
        root.Children.Add(ActionButton("统一修改生物群系…", ChunkBatchAction.SetBiome));
        root.Children.Add(ActionButton("常加载区域编辑…", ChunkBatchAction.TickingArea));
        root.Children.Add(ActionButton("删除 HardcodedSpawners…", ChunkBatchAction.DeleteHardcodedSpawners));
        root.Children.Add(ActionButton("清空所选区块…", ChunkBatchAction.Clear));
        root.Children.Add(ActionButton("重新生成所选区块…", ChunkBatchAction.Regenerate));
        var cancel = new Button
        {
            Content = "取消",
            IsCancel = true,
            Padding = new Thickness(18, 5, 18, 5),
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 12, 0, 0)
        };
        root.Children.Add(cancel);
        return root;
    }

    private Button ActionButton(string text, ChunkBatchAction action)
    {
        var button = new Button
        {
            Content = text,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(14, 8, 14, 8),
            Margin = new Thickness(0, 4, 0, 0)
        };
        button.Click += (_, _) =>
        {
            SelectedAction = action;
            DialogResult = true;
        };
        return button;
    }
}

public sealed class ChunkCopyWindow : Window
{
    private readonly WorldDocument _world;
    private readonly ChunkPosition _source;
    private readonly Func<Task> _prepare;
    private readonly Action<string, ChunkPosition> _complete;
    private readonly ComboBox _dimension = new();
    private readonly TextBox _x = new();
    private readonly TextBox _z = new();

    public ChunkCopyWindow(WorldDocument world, ChunkPosition source, Func<Task> prepare, Action<string, ChunkPosition> complete)
    {
        _world = world;
        _source = source;
        _prepare = prepare;
        _complete = complete;
        Title = "复制区块";
        Width = 620;
        Height = 410;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi();
        foreach (var name in new[] { "主世界", "下界", "末地" }) _dimension.Items.Add(name);
        _dimension.SelectedIndex = source.Dimension is >= 0 and <= 2 ? source.Dimension : 0;
        _x.Text = source.X.ToString(CultureInfo.InvariantCulture);
        _z.Text = source.Z.ToString(CultureInfo.InvariantCulture);
    }

    private UIElement BuildUi()
    {
        var root = new StackPanel { Margin = new Thickness(18) };
        root.Children.Add(new TextBlock
        {
            Text = $"源区块：{_source.DimensionName} ({_source.X}, {_source.Z})",
            FontWeight = FontWeights.SemiBold,
            FontSize = 15
        });
        root.Children.Add(Row("目标维度", _dimension));
        root.Children.Add(Row("目标区块 X", _x));
        root.Children.Add(Row("目标区块 Z", _z));
        root.Children.Add(new TextBlock
        {
            Text = "复制地形、SubChunk、生物群系、方块实体和区块状态。为避免 UniqueID / 调度状态冲突，不复制实体、pending ticks、random ticks 和 HardcodedSpawners。方块实体中的 x/z 与 pairx/pairz 会按目标区块自动平移；目标区块原有可复制记录会直接替换。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 14, 0, 12)
        });
        var copy = new Button
        {
            Content = "复制",
            IsDefault = true,
            Padding = new Thickness(18, 6, 18, 6),
            HorizontalAlignment = HorizontalAlignment.Right
        };
        copy.Click += async (_, _) => await CopyAsync();
        root.Children.Add(copy);
        return root;
    }

    private static UIElement Row(string title, Control control)
    {
        var grid = new Grid { Margin = new Thickness(0, 10, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center });
        Grid.SetColumn(control, 1);
        grid.Children.Add(control);
        return grid;
    }

    private async Task CopyAsync()
    {
        if (!int.TryParse(_x.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var x)
            || !int.TryParse(_z.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var z))
        {
            MessageBox.Show(this, "请输入有效的目标区块 X、Z。", "输入错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var dimension = _dimension.SelectedIndex;
        if (dimension is < 0 or > 2)
        {
            MessageBox.Show(this, "请选择目标维度。", "输入错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var destination = new ChunkPosition(x, z, dimension);
        if (destination == _source)
        {
            MessageBox.Show(this, "源区块与目标区块不能相同。", "输入错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (MessageBox.Show(this,
                $"将 {_source.DimensionName} ({_source.X}, {_source.Z}) 复制到 {destination.DimensionName} ({destination.X}, {destination.Z})？\n\n目标区块原有可复制记录会被替换。修改只写入 Cache 工作副本。",
                "确认复制区块", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        try
        {
            await _prepare();
            var result = await Task.Run(() =>
            {
                using var db = _world.OpenDatabase(false);
                return new BedrockChunkStore(db).CopyChunk(_source, destination);
            });
            var skipped = result.SkippedRecordTypes.Count == 0
                ? string.Empty
                : "；未复制：" + string.Join("、", result.SkippedRecordTypes.Select(item => item.DisplayName()));
            var message = $"已复制 {result.CopiedRecordCount:N0} 条区块记录到 {destination.DimensionName} ({destination.X}, {destination.Z})，替换目标 {result.RemovedDestinationRecordCount:N0} 条可复制记录{skipped}。";
            _complete(message, destination);
            MessageBox.Show(this, message, "复制完成", MessageBoxButton.OK, MessageBoxImage.Information);
            DialogResult = true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "复制区块失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
