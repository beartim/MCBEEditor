using System.Globalization;
using System.Windows;
using System.Windows.Controls;

namespace MCBEEditor.Desktop;

public sealed class RegionFillWindow : Window
{
    private readonly TextBox _minY = new();
    private readonly TextBox _maxY = new();
    private readonly TextBox _block0 = new();
    private readonly TextBox _states0 = new();
    private readonly TextBox _block1 = new();
    private readonly TextBox _states1 = new();

    public int MinimumY { get; private set; }
    public int MaximumY { get; private set; }
    public string Block0 { get; private set; } = string.Empty;
    public string States0 { get; private set; } = "NULL";
    public string? Block1 { get; private set; }
    public string? States1 { get; private set; }

    public RegionFillWindow(MapRegionSelection selection, int suggestedY)
    {
        Title = $"Fill 框选区域 · X={selection.MinimumX}…{selection.MaximumX}, Z={selection.MinimumZ}…{selection.MaximumZ}";
        Width = 680;
        Height = 470;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var root = CreateRoot(10);
        _minY.Text = suggestedY.ToString(CultureInfo.InvariantCulture);
        _maxY.Text = suggestedY.ToString(CultureInfo.InvariantCulture);
        _block0.Text = "minecraft:stone";
        _states0.Text = "NULL";
        _states1.Text = "NULL";
        AddRow(root, 0, "最小 Y", _minY);
        AddRow(root, 1, "最大 Y", _maxY);
        AddRow(root, 2, "storage 0 方块", _block0);
        AddRow(root, 3, "storage 0 states", _states0);
        AddRow(root, 4, "storage 1 方块（可空）", _block1);
        AddRow(root, 5, "storage 1 states", _states1);

        var note = new TextBlock
        {
            Text = "states 使用 NULL 表示空 Compound，或使用与 iOS 命令一致的 typed NBT，例如 'String'\"wood_type\"=\"oak\"。只修改这里提供的 storage；未提供的更高 storage 保留。Fill 会删除覆盖区域内原有 BlockEntity。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 10, 0, 14)
        };
        Grid.SetRow(note, 6); Grid.SetColumnSpan(note, 2); root.Children.Add(note);
        AddButtons(root, 8, "生成并执行 Fill", Commit_Click);
        Content = root;
    }

    private void Commit_Click(object sender, RoutedEventArgs e)
    {
        if (!TryInt(_minY.Text, out var y0) || !TryInt(_maxY.Text, out var y1))
        {
            MessageBox.Show(this, "Y 必须是 Int32 整数。", "坐标错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var block0 = _block0.Text.Trim();
        var states0 = _states0.Text.Trim();
        var block1 = _block1.Text.Trim();
        var states1 = _states1.Text.Trim();
        if (block0.Length == 0 || states0.Length == 0)
        {
            MessageBox.Show(this, "storage 0 的方块名和 states 不能为空。", "参数错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (block1.Length > 0 && states1.Length == 0)
        {
            MessageBox.Show(this, "填写 storage 1 方块时也必须填写 states；不需要状态请填写 NULL。", "参数错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        MinimumY = Math.Min(y0, y1);
        MaximumY = Math.Max(y0, y1);
        Block0 = block0;
        States0 = states0;
        Block1 = block1.Length == 0 ? null : block1;
        States1 = Block1 is null ? null : states1;
        DialogResult = true;
    }

    private static bool TryInt(string text, out int value)
        => int.TryParse(text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value);

    internal static Grid CreateRoot(int rows)
    {
        var root = new Grid { Margin = new Thickness(16) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(165) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < rows; i++) root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        return root;
    }

    internal static void AddRow(Grid grid, int row, string label, UIElement control)
    {
        var text = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 6, 12, 6) };
        Grid.SetRow(text, row); Grid.SetColumn(text, 0); grid.Children.Add(text);
        if (control is FrameworkElement element) element.Margin = new Thickness(0, 6, 0, 6);
        Grid.SetRow(control, row); Grid.SetColumn(control, 1); grid.Children.Add(control);
    }

    internal static void AddButtons(Grid root, int row, string acceptText, RoutedEventHandler accept)
    {
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var commit = new Button { Content = acceptText, Padding = new Thickness(18, 5, 18, 5), IsDefault = true };
        commit.Click += accept;
        buttons.Children.Add(commit);
        buttons.Children.Add(new Button { Content = "取消", Padding = new Thickness(18, 5, 18, 5), Margin = new Thickness(8, 0, 0, 0), IsCancel = true });
        Grid.SetRow(buttons, row); Grid.SetColumnSpan(buttons, 2); root.Children.Add(buttons);
    }
}

public sealed class RegionCloneWindow : Window
{
    private readonly TextBox _minY = new();
    private readonly TextBox _maxY = new();
    private readonly ComboBox _dimension = new();
    private readonly TextBox _x = new();
    private readonly TextBox _y = new();
    private readonly TextBox _z = new();

    public int MinimumY { get; private set; }
    public int MaximumY { get; private set; }
    public int TargetDimension { get; private set; }
    public int TargetX { get; private set; }
    public int TargetY { get; private set; }
    public int TargetZ { get; private set; }

    public RegionCloneWindow(MapRegionSelection selection, int suggestedY)
    {
        Title = $"Clone 框选区域 · X={selection.MinimumX}…{selection.MaximumX}, Z={selection.MinimumZ}…{selection.MaximumZ}";
        Width = 620;
        Height = 450;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var root = RegionFillWindow.CreateRoot(10);
        _minY.Text = suggestedY.ToString(CultureInfo.InvariantCulture);
        _maxY.Text = suggestedY.ToString(CultureInfo.InvariantCulture);
        _x.Text = selection.MinimumX.ToString(CultureInfo.InvariantCulture);
        _y.Text = suggestedY.ToString(CultureInfo.InvariantCulture);
        _z.Text = selection.MinimumZ.ToString(CultureInfo.InvariantCulture);
        _dimension.Items.Add(new ComboBoxItem { Content = "主世界", Tag = 0 });
        _dimension.Items.Add(new ComboBoxItem { Content = "下界", Tag = 1 });
        _dimension.Items.Add(new ComboBoxItem { Content = "末地", Tag = 2 });
        _dimension.SelectedIndex = selection.Dimension is >= 0 and <= 2 ? selection.Dimension : 0;

        RegionFillWindow.AddRow(root, 0, "源最小 Y", _minY);
        RegionFillWindow.AddRow(root, 1, "源最大 Y", _maxY);
        RegionFillWindow.AddRow(root, 2, "目标维度", _dimension);
        RegionFillWindow.AddRow(root, 3, "目标起点 X", _x);
        RegionFillWindow.AddRow(root, 4, "目标起点 Y", _y);
        RegionFillWindow.AddRow(root, 5, "目标起点 Z", _z);

        var note = new TextBlock
        {
            Text = "目标起点对应源区域的最小 X/Y/Z。Clone 会在执行前冻结完整源快照，因此重叠区域不会级联复制；所有实际存在的 storage 与 BlockEntity 会一起复制，目标区域多余 storage 会在复制位置清为空气。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 10, 0, 14)
        };
        Grid.SetRow(note, 6); Grid.SetColumnSpan(note, 2); root.Children.Add(note);
        RegionFillWindow.AddButtons(root, 8, "生成并执行 Clone", Commit_Click);
        Content = root;
    }

    private void Commit_Click(object sender, RoutedEventArgs e)
    {
        if (!TryInt(_minY.Text, out var y0) || !TryInt(_maxY.Text, out var y1)
            || !TryInt(_x.Text, out var x) || !TryInt(_y.Text, out var y) || !TryInt(_z.Text, out var z))
        {
            MessageBox.Show(this, "所有坐标必须是 Int32 整数。", "坐标错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        MinimumY = Math.Min(y0, y1);
        MaximumY = Math.Max(y0, y1);
        TargetDimension = _dimension.SelectedItem is ComboBoxItem item && item.Tag is int dimension ? dimension : 0;
        TargetX = x; TargetY = y; TargetZ = z;
        DialogResult = true;
    }

    private static bool TryInt(string text, out int value)
        => int.TryParse(text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value);
}
