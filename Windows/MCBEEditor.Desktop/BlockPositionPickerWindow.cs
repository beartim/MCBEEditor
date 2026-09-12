using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using MCBEEditor.Core.Chunk;

namespace MCBEEditor.Desktop;

public sealed record BlockPickerRow(BedrockBlockRecord Block, string CoordinateText, string Name, string GeneratedText, string DetailText)
{
    public bool IsAir => PreferredState(Block).IsAir;

    private static BedrockBlockState PreferredState(BedrockBlockRecord block)
        => block.Layers.FirstOrDefault(state => !state.IsAir)
           ?? block.Layers.FirstOrDefault()
           ?? BedrockBlockState.EditableAir();
}

public sealed class BlockPositionPickerWindow : Window
{
    private readonly DataGrid _grid;
    private readonly TextBlock _detail;
    private readonly IReadOnlyList<BlockPickerRow> _rows;
    public BedrockBlockRecord? SelectedBlock { get; private set; }

    public BlockPositionPickerWindow(
        IReadOnlyList<BedrockBlockRecord> blocks,
        BedrockMapAxis axis,
        int? initialCoordinate,
        int? automaticMinimumCoordinate = null,
        int? automaticMaximumCoordinate = null,
        bool preferHighlightedOre = false,
        IReadOnlyList<string>? diagnostics = null)
    {
        Title = axis == BedrockMapAxis.Y ? "选择 Y 轴方块" : $"选择 {axis} 轴方块";
        Width = 640;
        Height = 620;
        MinWidth = 500;
        MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        _rows = blocks.Select(block => new BlockPickerRow(
            block,
            axis switch
            {
                BedrockMapAxis.X => $"X={block.X}",
                BedrockMapAxis.Z => $"Z={block.Z}",
                _ => $"Y={block.Y}"
            },
            PreferredState(block).Name,
            block.Generated ? "" : "未生成",
            $"X={block.X} Y={block.Y} Z={block.Z} · storage {block.Layers.Count}"))
            .ToArray();

        var root = new Grid { Margin = new Thickness(12) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var hint = new TextBlock
        {
            Text = axis == BedrockMapAxis.Y
                ? "选择该 X/Z 方块列中的具体 Y 方块。未生成 SubChunk 也可选择，应用到工作副本时会按当前世界格式创建。"
                : $"选择当前 Y 上沿 {axis} 轴的具体方块。自动选中遵循 iOS 的负方向投影规则，仍可手动选择正方向位置。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 0, 0, 8)
        };
        root.Children.Add(hint);

        _grid = new DataGrid
        {
            GridLinesVisibility = DataGridGridLinesVisibility.Horizontal,
            HeadersVisibility = DataGridHeadersVisibility.Column,
            AutoGenerateColumns = false,
            IsReadOnly = true,
            CanUserAddRows = false,
            RowHeaderWidth = 0,
            SelectionMode = DataGridSelectionMode.Single,
            ItemsSource = new ObservableCollection<BlockPickerRow>(_rows)
        };
        _grid.Columns.Add(new DataGridTextColumn { Header = axis.ToString(), Binding = new Binding(nameof(BlockPickerRow.CoordinateText)), Width = 90 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "方块", Binding = new Binding(nameof(BlockPickerRow.Name)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        _grid.Columns.Add(new DataGridTextColumn { Header = "状态", Binding = new Binding(nameof(BlockPickerRow.GeneratedText)), Width = 90 });
        _grid.SelectionChanged += (_, _) => UpdateDetail();
        _grid.MouseDoubleClick += (_, _) => Accept();
        Grid.SetRow(_grid, 1);
        root.Children.Add(_grid);

        _detail = new TextBlock
        {
            Margin = new Thickness(0, 8, 0, 8),
            TextWrapping = TextWrapping.Wrap,
            FontFamily = new System.Windows.Media.FontFamily("Consolas"),
            Foreground = System.Windows.Media.Brushes.DimGray
        };
        Grid.SetRow(_detail, 2);
        root.Children.Add(_detail);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "取消", Padding = new Thickness(16, 5, 16, 5), MinWidth = 88 };
        cancel.Click += (_, _) => { DialogResult = false; Close(); };
        var done = new Button { Content = "选择", Padding = new Thickness(16, 5, 16, 5), Margin = new Thickness(8, 0, 0, 0), MinWidth = 88, IsDefault = true };
        done.Click += (_, _) => Accept();
        buttons.Children.Add(cancel);
        buttons.Children.Add(done);
        Grid.SetRow(buttons, 3);
        root.Children.Add(buttons);
        Content = root;

        Loaded += (_, _) =>
        {
            var initialIndex = FindInitialIndex(axis, initialCoordinate, automaticMinimumCoordinate, automaticMaximumCoordinate, preferHighlightedOre);
            if (_rows.Count > 0)
            {
                _grid.SelectedIndex = Math.Clamp(initialIndex, 0, _rows.Count - 1);
                _grid.ScrollIntoView(_grid.SelectedItem);
            }
            UpdateDetail(diagnostics);
            _grid.Focus();
        };
        KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) { Accept(); e.Handled = true; }
            else if (e.Key == Key.Escape) { DialogResult = false; Close(); e.Handled = true; }
        };
    }

    private int FindInitialIndex(BedrockMapAxis axis, int? initialCoordinate, int? automaticMinimum, int? automaticMaximum, bool preferHighlightedOre)
    {
        if (axis is BedrockMapAxis.X or BedrockMapAxis.Z)
        {
            var lower = automaticMinimum ?? int.MinValue;
            var upper = automaticMaximum ?? int.MaxValue;
            for (var i = 0; i < _rows.Count; i++)
            {
                var block = _rows[i].Block;
                var coordinate = axis == BedrockMapAxis.X ? block.X : block.Z;
                if (coordinate < lower || coordinate > upper) continue;
                var state = PreferredState(block);
                if (preferHighlightedOre ? BedrockBlockMapColorCatalog.IsHighlightedOre(state.Name) : !state.IsAir)
                    return i;
            }
        }

        if (initialCoordinate.HasValue)
        {
            for (var i = 0; i < _rows.Count; i++)
            {
                var block = _rows[i].Block;
                var coordinate = axis switch { BedrockMapAxis.X => block.X, BedrockMapAxis.Z => block.Z, _ => block.Y };
                if (coordinate == initialCoordinate.Value) return i;
            }
        }

        if (axis == BedrockMapAxis.Y)
        {
            for (var i = 0; i < _rows.Count; i++)
                if (!PreferredState(_rows[i].Block).IsAir) return i;
        }
        return 0;
    }

    private void UpdateDetail(IReadOnlyList<string>? diagnostics = null)
    {
        if (_grid.SelectedItem is not BlockPickerRow row)
        {
            _detail.Text = diagnostics is { Count: > 0 } ? $"解析提示：{diagnostics.Count} 条" : string.Empty;
            return;
        }
        var state = PreferredState(row.Block);
        var generated = row.Block.Generated ? "已生成" : "SubChunk 未生成";
        var extra = diagnostics is { Count: > 0 } ? $"\n解析提示：{diagnostics.Count} 条" : string.Empty;
        _detail.Text = $"{row.DetailText}\n{state.Name} · {generated}{extra}";
    }

    private void Accept()
    {
        if (_grid.SelectedItem is not BlockPickerRow row) return;
        SelectedBlock = row.Block;
        DialogResult = true;
        Close();
    }

    private static BedrockBlockState PreferredState(BedrockBlockRecord block)
        => block.Layers.FirstOrDefault(state => !state.IsAir)
           ?? block.Layers.FirstOrDefault()
           ?? BedrockBlockState.EditableAir();
}
