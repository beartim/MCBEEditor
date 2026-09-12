using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;

namespace MCBEEditor.Desktop;

public sealed class BlockEntityMoveWindow : Window
{
    private readonly ComboBox _dimension = new();
    private readonly TextBox _x = new();
    private readonly TextBox _y = new();
    private readonly TextBox _z = new();

    public int Dimension { get; private set; }
    public int X { get; private set; }
    public int Y { get; private set; }
    public int Z { get; private set; }

    public BlockEntityMoveWindow(BedrockWorldObject item)
    {
        if (item.Kind != BedrockWorldObjectKind.BlockEntity || item.Position is null)
            throw new ArgumentException("需要带坐标的方块实体。", nameof(item));
        Title = $"移动方块实体 · {item.DisplayName}";
        Width = 520;
        Height = 330;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var root = new Grid { Margin = new Thickness(16) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < 7; i++) root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        _dimension.Items.Add(new ComboBoxItem { Content = "主世界", Tag = 0 });
        _dimension.Items.Add(new ComboBoxItem { Content = "下界", Tag = 1 });
        _dimension.Items.Add(new ComboBoxItem { Content = "末地", Tag = 2 });
        _dimension.SelectedIndex = item.Dimension is >= 0 and <= 2 ? item.Dimension : 0;
        AddRow(root, 0, "目标维度", _dimension);
        _x.Text = item.Position.BlockX.ToString(CultureInfo.InvariantCulture);
        _y.Text = item.Position.BlockY.ToString(CultureInfo.InvariantCulture);
        _z.Text = item.Position.BlockZ.ToString(CultureInfo.InvariantCulture);
        AddRow(root, 1, "X", _x);
        AddRow(root, 2, "Y", _y);
        AddRow(root, 3, "Z", _z);

        var note = new TextBlock
        {
            Text = "该操作会把源坐标全部 block storage 层复制到目标、源位置置空气，并在同一个 LevelDB WriteBatch 中迁移 BlockEntity NBT。目标已有方块会被覆盖；目标已有方块实体则拒绝执行。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 10, 0, 12)
        };
        Grid.SetRow(note, 4); Grid.SetColumnSpan(note, 2); root.Children.Add(note);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var move = new Button { Content = "移动", Padding = new Thickness(18, 5, 18, 5), IsDefault = true };
        move.Click += Move_Click;
        buttons.Children.Add(move);
        buttons.Children.Add(new Button { Content = "取消", Padding = new Thickness(18, 5, 18, 5), Margin = new Thickness(8, 0, 0, 0), IsCancel = true });
        Grid.SetRow(buttons, 6); Grid.SetColumnSpan(buttons, 2); root.Children.Add(buttons);
        Content = root;
    }

    private void Move_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(_x.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var x)
            || !int.TryParse(_y.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var y)
            || !int.TryParse(_z.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var z))
        {
            MessageBox.Show(this, "X/Y/Z 必须是 Int32 整数。", "坐标错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        X = x; Y = y; Z = z;
        Dimension = _dimension.SelectedItem is ComboBoxItem item && item.Tag is int dimension ? dimension : 0;
        DialogResult = true;
    }

    private static void AddRow(Grid grid, int row, string label, UIElement control)
    {
        var text = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 6, 12, 6) };
        Grid.SetRow(text, row); Grid.SetColumn(text, 0); grid.Children.Add(text);
        if (control is FrameworkElement element) element.Margin = new Thickness(0, 6, 0, 6);
        Grid.SetRow(control, row); Grid.SetColumn(control, 1); grid.Children.Add(control);
    }
}
