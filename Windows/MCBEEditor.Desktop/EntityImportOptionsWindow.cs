using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using MCBEEditor.Core.Entity;

namespace MCBEEditor.Desktop;

public sealed class EntityImportOptionsWindow : Window
{
    private readonly TextBox _x = new();
    private readonly TextBox _y = new();
    private readonly TextBox _z = new();
    private readonly TextBox _uniqueId = new();

    public BedrockWorldObjectPosition Position { get; private set; } = new(0, 64, 0);
    public long BaseUniqueId { get; private set; }

    public EntityImportOptionsWindow(BedrockWorldObjectPosition defaultPosition, long suggestedUniqueId)
    {
        Title = "导入实体 NBT / JSON";
        Width = 540;
        Height = 330;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi(defaultPosition, suggestedUniqueId);
    }

    private UIElement BuildUi(BedrockWorldObjectPosition defaultPosition, long suggestedUniqueId)
    {
        var root = new Grid { Margin = new Thickness(16) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < 6; i++) root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        _x.Text = Format(defaultPosition.X); _y.Text = Format(defaultPosition.Y); _z.Text = Format(defaultPosition.Z);
        var coords = new Grid();
        for (var i = 0; i < 3; i++) coords.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _x.Margin = new Thickness(0, 0, 5, 0); _x.ToolTip = "X";
        _y.Margin = new Thickness(5, 0, 5, 0); _y.ToolTip = "Y";
        _z.Margin = new Thickness(5, 0, 0, 0); _z.ToolTip = "Z";
        Grid.SetColumn(_x, 0); Grid.SetColumn(_y, 1); Grid.SetColumn(_z, 2);
        coords.Children.Add(_x); coords.Children.Add(_y); coords.Children.Add(_z);
        AddRow(root, 0, "目标 X / Y / Z", coords);

        _uniqueId.Text = suggestedUniqueId.ToString(CultureInfo.InvariantCulture);
        var uidPanel = new DockPanel();
        var regenerate = new Button { Content = "重新生成", Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(6, 0, 0, 0) };
        regenerate.Click += (_, _) => _uniqueId.Text = Random.Shared.NextInt64(1, long.MaxValue).ToString(CultureInfo.InvariantCulture);
        DockPanel.SetDock(regenerate, Dock.Right);
        uidPanel.Children.Add(regenerate);
        uidPanel.Children.Add(_uniqueId);
        AddRow(root, 1, "起始 UniqueID", uidPanel);

        var notice = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 12, 0, 0),
            Text = "导入准备只修改每个根实体的 Pos 和 UniqueID。多个根标签全部使用这里的目标坐标，UniqueID 从起始值依次 +1；不会补充 identifier、definitions、DimensionId 或其他默认标签。缺少 DimensionId 的实体会在“导入全部”时统一选择存储维度。"
        };
        Grid.SetRow(notice, 3); Grid.SetColumnSpan(notice, 2); root.Children.Add(notice);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
        var ok = new Button { Content = "选择文件…", Padding = new Thickness(18, 5, 18, 5), IsDefault = true };
        ok.Click += Ok_Click;
        var cancel = new Button { Content = "取消", Padding = new Thickness(18, 5, 18, 5), Margin = new Thickness(8, 0, 0, 0), IsCancel = true };
        buttons.Children.Add(ok); buttons.Children.Add(cancel);
        Grid.SetRow(buttons, 7); Grid.SetColumnSpan(buttons, 2); root.Children.Add(buttons);
        return root;
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        if (!double.TryParse(_x.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var x)
            || !double.TryParse(_y.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var y)
            || !double.TryParse(_z.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var z)
            || !double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(z))
        {
            MessageBox.Show(this, "X、Y、Z 必须是可写入实体 Pos 的有限数字。", "坐标错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!long.TryParse(_uniqueId.Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var uniqueId) || uniqueId == 0)
        {
            MessageBox.Show(this, "起始 UniqueID 必须是非零 Int64。", "UniqueID 错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        Position = new BedrockWorldObjectPosition(x, y, z);
        BaseUniqueId = uniqueId;
        DialogResult = true;
    }

    private static void AddRow(Grid grid, int row, string label, UIElement control)
    {
        var text = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 7, 12, 7) };
        Grid.SetRow(text, row); Grid.SetColumn(text, 0); grid.Children.Add(text);
        if (control is FrameworkElement element) element.Margin = new Thickness(element.Margin.Left, 7, element.Margin.Right, 7);
        Grid.SetRow(control, row); Grid.SetColumn(control, 1); grid.Children.Add(control);
    }

    private static string Format(double value) => value.ToString("0.########", CultureInfo.InvariantCulture);
}
