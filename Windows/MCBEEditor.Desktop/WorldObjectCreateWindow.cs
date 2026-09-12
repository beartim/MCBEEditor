using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using MCBEEditor.Core.Entity;

namespace MCBEEditor.Desktop;

public sealed class WorldObjectCreateWindow : Window
{
    private readonly BedrockWorldObjectKind _kind;
    private readonly TextBox _identifier = new();
    private readonly ComboBox _dimension = new();
    private readonly TextBox _x = new();
    private readonly TextBox _y = new();
    private readonly TextBox _z = new();
    private readonly TextBox _uniqueId = new();

    public string Identifier { get; private set; } = string.Empty;
    public BedrockWorldObjectPosition Position { get; private set; } = new(0, 64, 0);
    public int Dimension { get; private set; }
    public long? UniqueId { get; private set; }

    public WorldObjectCreateWindow(BedrockWorldObjectKind kind, BedrockWorldObject? template,
        BedrockWorldObjectPosition defaultPosition, int defaultDimension, long suggestedUniqueId,
        BedrockWorldObjectPosition? selectedPosition = null, int? selectedDimension = null)
    {
        _kind = kind;
        Title = template is null ? $"新建{KindText(kind)}" : $"复制为新{KindText(kind)}";
        Width = 560;
        Height = kind == BedrockWorldObjectKind.Entity ? 430 : 385;
        MinWidth = 500;
        MinHeight = 340;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi(template, defaultPosition, defaultDimension, suggestedUniqueId, selectedPosition, selectedDimension);
    }

    private UIElement BuildUi(BedrockWorldObject? template, BedrockWorldObjectPosition defaultPosition,
        int defaultDimension, long suggestedUniqueId, BedrockWorldObjectPosition? selectedPosition, int? selectedDimension)
    {
        var root = new Grid { Margin = new Thickness(16) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < 7; i++) root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        _identifier.Text = template?.Identifier ?? (_kind == BedrockWorldObjectKind.Entity ? "minecraft:pig" : "Chest");
        AddRow(root, 0, _kind == BedrockWorldObjectKind.Entity ? "实体 ID" : "方块实体 ID", _identifier);

        _dimension.Items.Add(new ComboBoxItem { Content = "主世界", Tag = 0 });
        _dimension.Items.Add(new ComboBoxItem { Content = "下界", Tag = 1 });
        _dimension.Items.Add(new ComboBoxItem { Content = "末地", Tag = 2 });
        _dimension.SelectedIndex = defaultDimension is >= 0 and <= 2 ? defaultDimension : 0;
        AddRow(root, 1, "维度", _dimension);

        var position = template?.Position ?? defaultPosition;
        _x.Text = Format(position.X);
        _y.Text = Format(position.Y);
        _z.Text = Format(position.Z);
        var coords = new Grid();
        for (var i = 0; i < 3; i++) coords.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _x.Margin = new Thickness(0, 0, 5, 0); _x.ToolTip = "X";
        _y.Margin = new Thickness(5, 0, 5, 0); _y.ToolTip = "Y";
        _z.Margin = new Thickness(5, 0, 0, 0); _z.ToolTip = "Z";
        Grid.SetColumn(_x, 0); Grid.SetColumn(_y, 1); Grid.SetColumn(_z, 2);
        coords.Children.Add(_x); coords.Children.Add(_y); coords.Children.Add(_z);
        AddRow(root, 2, "坐标 X / Y / Z", coords);

        if (selectedPosition is { } currentSelection && selectedDimension is { } currentDimension)
        {
            var useSelected = new Button
            {
                Content = "使用当前选中位置",
                Padding = new Thickness(10, 4, 10, 4),
                HorizontalAlignment = HorizontalAlignment.Left,
                Margin = new Thickness(0, 2, 0, 4),
                ToolTip = "使用当前在实体列表或地图中选中的坐标和维度"
            };
            useSelected.Click += (_, _) =>
            {
                _x.Text = Format(currentSelection.X);
                _y.Text = Format(currentSelection.Y);
                _z.Text = Format(currentSelection.Z);
                _dimension.SelectedIndex = currentDimension is >= 0 and <= 2 ? currentDimension : 0;
            };
            Grid.SetRow(useSelected, 4);
            Grid.SetColumn(useSelected, 1);
            root.Children.Add(useSelected);
        }

        if (_kind == BedrockWorldObjectKind.Entity)
        {
            _uniqueId.Text = suggestedUniqueId.ToString(CultureInfo.InvariantCulture);
            var uidPanel = new DockPanel();
            var regenerate = new Button { Content = "重新生成", Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(6, 0, 0, 0) };
            regenerate.Click += (_, _) => _uniqueId.Text = Random.Shared.NextInt64(1, long.MaxValue).ToString(CultureInfo.InvariantCulture);
            DockPanel.SetDock(regenerate, Dock.Right);
            uidPanel.Children.Add(regenerate);
            uidPanel.Children.Add(_uniqueId);
            AddRow(root, 3, "UniqueID", uidPanel);
        }

        var notice = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 14, 0, 0),
            Text = template is not null
                ? "将完整复制原对象 NBT，并只替换对象身份/坐标/维度/UniqueID 等创建所需字段；原对象不会被修改。"
                : _kind == BedrockWorldObjectKind.Entity
                    ? "会自动识别旧式区块 Entity(0x32) 或现代 actorprefix/digp 存储格式。空白新建实体使用通用实体 NBT 模板。"
                    : "方块实体只写入 BlockEntity(0x31) 记录，不会自动改变目标坐标的方块。请确保方块类型与方块实体 ID 匹配。"
        };
        Grid.SetRow(notice, 5); Grid.SetColumnSpan(notice, 2); root.Children.Add(notice);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
        var ok = new Button { Content = "创建", Padding = new Thickness(18, 5, 18, 5), IsDefault = true };
        ok.Click += Ok_Click;
        var cancel = new Button { Content = "取消", Padding = new Thickness(18, 5, 18, 5), Margin = new Thickness(8, 0, 0, 0), IsCancel = true };
        buttons.Children.Add(ok); buttons.Children.Add(cancel);
        Grid.SetRow(buttons, 8); Grid.SetColumnSpan(buttons, 2); root.Children.Add(buttons);
        return root;
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        if (!double.TryParse(_x.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var x)
            || !double.TryParse(_y.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var y)
            || !double.TryParse(_z.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var z)
            || !double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(z))
        {
            MessageBox.Show(this, "X、Y、Z 必须是有限数字。", "坐标错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var id = _identifier.Text.Trim();
        if (id.Length == 0)
        {
            MessageBox.Show(this, "对象 ID 不能为空。", "ID 错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        long? uniqueId = null;
        if (_kind == BedrockWorldObjectKind.Entity)
        {
            if (!long.TryParse(_uniqueId.Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed) || parsed == 0)
            {
                MessageBox.Show(this, "UniqueID 必须是非零 Int64。", "UniqueID 错误", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            uniqueId = parsed;
        }
        Identifier = id;
        Position = new BedrockWorldObjectPosition(x, y, z);
        Dimension = _dimension.SelectedItem is ComboBoxItem item && item.Tag is int dimension ? dimension : 0;
        UniqueId = uniqueId;
        DialogResult = true;
    }

    private static void AddRow(Grid grid, int row, string label, UIElement control)
    {
        var text = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 7, 12, 7) };
        Grid.SetRow(text, row); Grid.SetColumn(text, 0); grid.Children.Add(text);
        if (control is FrameworkElement element) element.Margin = new Thickness(element.Margin.Left, 7, element.Margin.Right, 7);
        Grid.SetRow(control, row); Grid.SetColumn(control, 1); grid.Children.Add(control);
    }

    private static string KindText(BedrockWorldObjectKind kind) => kind == BedrockWorldObjectKind.Entity ? "实体" : "方块实体";
    private static string Format(double value) => value.ToString("0.########", CultureInfo.InvariantCulture);
}
