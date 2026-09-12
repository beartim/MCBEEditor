using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using MCBEEditor.Core.Chunk;

namespace MCBEEditor.Desktop;

public sealed class LegacyBlockEditWindow : Window
{
    private readonly TextBox _id = new();
    private readonly TextBox _data = new();
    private readonly int _storageIndex;
    public ushort LegacyId { get; private set; }
    public byte LegacyData { get; private set; }

    public LegacyBlockEditWindow(BedrockBlockRecord block, int storageIndex, BedrockBlockState state)
    {
        _storageIndex = storageIndex;
        Title = $"编辑旧版数字方块 · storage {storageIndex}";
        Width = 480;
        Height = 270;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var root = new Grid { Margin = new Thickness(16) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < 5; i++) root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var location = new TextBlock
        {
            Text = $"{BedrockDimensionNames.DisplayName(block.Dimension)} · X={block.X}, Y={block.Y}, Z={block.Z}",
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 0, 0, 12)
        };
        Grid.SetColumnSpan(location, 2); root.Children.Add(location);

        _id.Text = (state.LegacyId ?? 0).ToString(CultureInfo.InvariantCulture);
        _data.Text = (state.LegacyData ?? 0).ToString(CultureInfo.InvariantCulture);
        AddRow(root, 1, "legacy ID", _id);
        AddRow(root, 2, "legacy data", _data);

        var note = new TextBlock
        {
            Text = storageIndex == 1
                ? "storage 1 由 LevelChunkTag 0x34 LegacyBlockExtraData 持久化，data 支持 0…255。"
                : "storage 0 保持旧版数字 ID SubChunk，不会隐式升级成现代 NBT palette；data 支持 0…15。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 10, 0, 10)
        };
        Grid.SetRow(note, 3); Grid.SetColumnSpan(note, 2); root.Children.Add(note);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var save = new Button { Content = "应用", Padding = new Thickness(18, 5, 18, 5), IsDefault = true };
        save.Click += Save_Click;
        buttons.Children.Add(save);
        buttons.Children.Add(new Button { Content = "取消", Padding = new Thickness(18, 5, 18, 5), Margin = new Thickness(8, 0, 0, 0), IsCancel = true });
        Grid.SetRow(buttons, 4); Grid.SetColumnSpan(buttons, 2); root.Children.Add(buttons);
        Content = root;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (!ushort.TryParse(_id.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var id) || id > byte.MaxValue)
        {
            MessageBox.Show(this, "旧版数字方块 ID 必须为 0…255。", "输入错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!byte.TryParse(_data.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var data)
            || (_storageIndex == 0 && data > 15))
        {
            MessageBox.Show(this, _storageIndex == 0 ? "storage 0 的 legacy data 必须为 0…15。" : "storage 1 的 legacy data 必须为 0…255。",
                "输入错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        LegacyId = id;
        LegacyData = data;
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
