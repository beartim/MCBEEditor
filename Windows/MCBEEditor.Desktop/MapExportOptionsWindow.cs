using System;
using System.Linq;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace MCBEEditor.Desktop;

internal enum MapExportAngle
{
    XPositive,
    XNegative,
    YPositive,
    YNegative,
    ZPositive,
    ZNegative
}

internal enum MapUngeneratedExportMode
{
    Transparent,
    Air,
    Texture
}

internal sealed record MapExportOptions(
    MapExportAngle Angle,
    bool DrawGrid,
    int PixelsPerBlock,
    long? MinimumX,
    long? MinimumZ,
    long? MaximumX,
    long? MaximumZ,
    bool Players,
    bool Entities,
    bool BlockEntities,
    bool HardcodedSpawners,
    bool Villages,
    bool SpawnPoints,
    MapUngeneratedExportMode UngeneratedDisplay);

internal sealed class MapExportOptionsWindow : Window
{
    private readonly ComboBox _angle = new();
    private readonly CheckBox _grid = new() { Content = "导出区块/子区块网格（默认关闭）", IsChecked = false };
    private readonly ComboBox _pixels = new();
    private readonly TextBox _minimumX = CoordinateBox();
    private readonly TextBox _minimumZ = CoordinateBox();
    private readonly TextBox _maximumX = CoordinateBox();
    private readonly TextBox _maximumZ = CoordinateBox();
    private readonly CheckBox _players = new() { Content = "玩家" };
    private readonly CheckBox _entities = new() { Content = "实体" };
    private readonly CheckBox _blockEntities = new() { Content = "方块实体" };
    private readonly CheckBox _hardcodedSpawners = new() { Content = "HardcodedSpawners" };
    private readonly CheckBox _villages = new() { Content = "村庄" };
    private readonly CheckBox _spawnPoints = new() { Content = "出生点" };
    private readonly ComboBox _ungenerated = new();

    public MapExportOptions? Options { get; private set; }

    public MapExportOptionsWindow(
        MapExportAngle initialAngle,
        long? minimumX,
        long? minimumZ,
        long? maximumX,
        long? maximumZ,
        bool players,
        bool entities,
        bool blockEntities,
        bool hardcodedSpawners,
        bool villages,
        bool spawnPoints,
        MapUngeneratedExportMode ungeneratedDisplay)
    {
        Title = "导出地图 PNG";
        Width = 760;
        Height = 540;
        MinWidth = 680;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;

        _angle.Items.Add(Item("x+", MapExportAngle.XPositive));
        _angle.Items.Add(Item("x-", MapExportAngle.XNegative));
        _angle.Items.Add(Item("y+", MapExportAngle.YPositive));
        _angle.Items.Add(Item("y-", MapExportAngle.YNegative));
        _angle.Items.Add(Item("z+", MapExportAngle.ZPositive));
        _angle.Items.Add(Item("z-", MapExportAngle.ZNegative));
        _angle.SelectedItem = _angle.Items.Cast<ComboBoxItem>().First(item => (MapExportAngle)item.Tag == initialAngle);
        _angle.SelectionChanged += (_, _) => UpdateVillageAvailability();

        _players.IsChecked = players;
        _entities.IsChecked = entities;
        _blockEntities.IsChecked = blockEntities;
        _hardcodedSpawners.IsChecked = hardcodedSpawners;
        _villages.IsChecked = villages;
        _spawnPoints.IsChecked = spawnPoints;

        _ungenerated.Items.Add(UngeneratedItem("透明", MapUngeneratedExportMode.Transparent));
        _ungenerated.Items.Add(UngeneratedItem("空气", MapUngeneratedExportMode.Air));
        _ungenerated.Items.Add(UngeneratedItem("纹理", MapUngeneratedExportMode.Texture));
        _ungenerated.SelectedItem = _ungenerated.Items.Cast<ComboBoxItem>()
            .First(item => (MapUngeneratedExportMode)item.Tag == ungeneratedDisplay);

        foreach (var value in new[] { 1, 2, 4, 8 })
            _pixels.Items.Add(new ComboBoxItem { Content = $"{value} px / 方块", Tag = value });
        _pixels.SelectedIndex = 2;

        _minimumX.Text = minimumX?.ToString(CultureInfo.InvariantCulture) ?? "-∞";
        _minimumZ.Text = minimumZ?.ToString(CultureInfo.InvariantCulture) ?? "-∞";
        _maximumX.Text = maximumX?.ToString(CultureInfo.InvariantCulture) ?? "+∞";
        _maximumZ.Text = maximumZ?.ToString(CultureInfo.InvariantCulture) ?? "+∞";

        var root = new Grid { Margin = new Thickness(18) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var range = new UniformGrid { Columns = 4 };
        range.Children.Add(CoordinateGroup("x1", _minimumX, "-∞", () => _minimumX.Text = "-∞"));
        range.Children.Add(CoordinateGroup("z1", _minimumZ, "-∞", () => _minimumZ.Text = "-∞"));
        range.Children.Add(CoordinateGroup("x2", _maximumX, "+∞", () => _maximumX.Text = "+∞"));
        range.Children.Add(CoordinateGroup("z2", _maximumZ, "+∞", () => _maximumZ.Text = "+∞"));
        Grid.SetRow(range, 0);
        root.Children.Add(range);

        var angleRow = TwoColumnRow("导出方向", _angle);
        angleRow.Margin = new Thickness(0, 12, 0, 0);
        Grid.SetRow(angleRow, 1);
        root.Children.Add(angleRow);

        var pixelsRow = TwoColumnRow("输出分辨率", _pixels);
        pixelsRow.Margin = new Thickness(0, 10, 0, 0);
        Grid.SetRow(pixelsRow, 2);
        root.Children.Add(pixelsRow);

        var layers = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };
        layers.Children.Add(new TextBlock { Text = "导出图层：", VerticalAlignment = VerticalAlignment.Center, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 8, 0) });
        foreach (var toggle in new[] { _players, _entities, _blockEntities, _hardcodedSpawners, _villages, _spawnPoints, _grid })
        {
            toggle.Margin = new Thickness(0, 0, 12, 5);
            layers.Children.Add(toggle);
        }
        Grid.SetRow(layers, 3);
        root.Children.Add(layers);

        var ungeneratedRow = TwoColumnRow("未生成区域", _ungenerated);
        ungeneratedRow.Margin = new Thickness(0, 8, 0, 0);
        Grid.SetRow(ungeneratedRow, 4);
        root.Children.Add(ungeneratedRow);

        var hint = new TextBlock
        {
            Margin = new Thickness(0, 10, 0, 0),
            TextWrapping = TextWrapping.Wrap,
            Foreground = Brushes.DimGray,
            Text = "两组 (x,z) 表示导出范围的两个角点；四个无穷按钮分别对应 x1、z1、x2、z2。无穷边界会自动使用当前维度全部已加载区块的边界。导出图层与地图页面当前开关互相独立；“透明”写入真实 PNG Alpha，“空气”使用普通背景，“纹理”绘制未生成区块/子区块斜线。x+/z+ 从正方向向负方向看，x-/z- 从负方向向正方向看；y+ 从上向下，y- 从下向上。大范围会自动降低 px/方块，最长边控制在 4096 像素。"
        };
        Grid.SetRow(hint, 6);
        root.Children.Add(hint);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "取消", MinWidth = 80, Padding = new Thickness(10, 5, 10, 5) };
        cancel.Click += (_, _) => DialogResult = false;
        var export = new Button { Content = "导出", MinWidth = 80, Margin = new Thickness(8, 0, 0, 0), Padding = new Thickness(10, 5, 10, 5), IsDefault = true };
        export.Click += (_, _) => Confirm();
        buttons.Children.Add(cancel);
        buttons.Children.Add(export);
        Grid.SetRow(buttons, 7);
        root.Children.Add(buttons);

        Content = root;
        UpdateVillageAvailability();
    }

    private void Confirm()
    {
        if (_angle.SelectedItem is not ComboBoxItem angleItem || angleItem.Tag is not MapExportAngle angle) return;
        if (_pixels.SelectedItem is not ComboBoxItem pixelItem || pixelItem.Tag is not int pixels) return;
        if (_ungenerated.SelectedItem is not ComboBoxItem ungeneratedItem || ungeneratedItem.Tag is not MapUngeneratedExportMode ungeneratedDisplay) return;

        if (!TryParseMinimum(_minimumX.Text, "x1", out var minimumX)
            || !TryParseMinimum(_minimumZ.Text, "z1", out var minimumZ)
            || !TryParseMaximum(_maximumX.Text, "x2", out var maximumX)
            || !TryParseMaximum(_maximumZ.Text, "z2", out var maximumZ))
            return;

        if (minimumX.HasValue && maximumX.HasValue && minimumX.Value > maximumX.Value)
        {
            ShowRangeError("x1 不能大于 x2。");
            return;
        }
        if (minimumZ.HasValue && maximumZ.HasValue && minimumZ.Value > maximumZ.Value)
        {
            ShowRangeError("z1 不能大于 z2。");
            return;
        }

        Options = new MapExportOptions(
            angle, _grid.IsChecked == true, pixels, minimumX, minimumZ, maximumX, maximumZ,
            _players.IsChecked == true, _entities.IsChecked == true, _blockEntities.IsChecked == true,
            _hardcodedSpawners.IsChecked == true, _villages.IsChecked == true, _spawnPoints.IsChecked == true,
            ungeneratedDisplay);
        DialogResult = true;
    }

    private bool TryParseMinimum(string text, string name, out long? value)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed is "-∞" or "-inf" or "-INF")
        {
            value = null;
            return true;
        }
        if (long.TryParse(trimmed, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
        {
            value = parsed;
            return true;
        }
        value = null;
        ShowRangeError($"{name} 不是有效整数或 -∞。");
        return false;
    }

    private bool TryParseMaximum(string text, string name, out long? value)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed is "+∞" or "∞" or "+inf" or "inf" or "+INF" or "INF")
        {
            value = null;
            return true;
        }
        if (long.TryParse(trimmed, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
        {
            value = parsed;
            return true;
        }
        value = null;
        ShowRangeError($"{name} 不是有效整数或 +∞。");
        return false;
    }

    private void ShowRangeError(string message)
        => MessageBox.Show(this, message, "导出范围无效", MessageBoxButton.OK, MessageBoxImage.Warning);

    private static TextBox CoordinateBox() => new()
    {
        MinWidth = 90,
        HorizontalContentAlignment = HorizontalAlignment.Center,
        VerticalContentAlignment = VerticalAlignment.Center,
        Padding = new Thickness(4, 3, 4, 3)
    };

    private static FrameworkElement CoordinateGroup(string label, TextBox box, string infinityText, Action setInfinity)
    {
        var stack = new StackPanel { Margin = new Thickness(4, 0, 4, 0) };
        stack.Children.Add(new TextBlock
        {
            Text = label,
            HorizontalAlignment = HorizontalAlignment.Center,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 4)
        });
        stack.Children.Add(box);
        var button = new Button
        {
            Content = infinityText,
            Margin = new Thickness(0, 5, 0, 0),
            Padding = new Thickness(8, 3, 8, 3),
            Background = Brushes.DodgerBlue,
            Foreground = Brushes.White
        };
        button.Click += (_, _) => setInfinity();
        stack.Children.Add(button);
        return stack;
    }

    private void UpdateVillageAvailability()
    {
        if (_angle.SelectedItem is not ComboBoxItem item || item.Tag is not MapExportAngle angle) return;
        _villages.IsEnabled = angle is MapExportAngle.YPositive or MapExportAngle.YNegative;
    }

    private static ComboBoxItem Item(string text, MapExportAngle angle) => new() { Content = text, Tag = angle };
    private static ComboBoxItem UngeneratedItem(string text, MapUngeneratedExportMode mode) => new() { Content = text, Tag = mode };

    private static Grid TwoColumnRow(string label, Control control)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var text = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(text, 0);
        Grid.SetColumn(control, 1);
        grid.Children.Add(text);
        grid.Children.Add(control);
        return grid;
    }
}
