using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace MCBEEditor.Desktop;

public sealed class AboutLicenseWindow : Window
{
    public AboutLicenseWindow()
    {
        Title = "说明与许可证";
        Width = 760;
        Height = 620;
        MinWidth = 600;
        MinHeight = 460;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi();
    }

    private static UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(14) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        root.Children.Add(new TextBlock
        {
            Text = "MCBEEditor 1.0.0",
            FontSize = 20,
            FontWeight = FontWeights.SemiBold
        });

        var description = new TextBlock
        {
            Text = "Windows 10/11 x64 版。支持 Bedrock 世界、NBT/mcstructure/JSON 文件读取修改、Java 结构转换、连续多根 NBT、地图与 LevelDB 编辑。来源世界保持只读，修改发生在 Cache 工作副本中。GNU AGPL-3.0-or-later，无任何担保。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = Brushes.DimGray,
            Margin = new Thickness(0, 8, 0, 12)
        };
        Grid.SetRow(description, 1);
        root.Children.Add(description);

        var license = new TextBox
        {
            Text = ReadLicense(),
            IsReadOnly = true,
            AcceptsReturn = true,
            AcceptsTab = true,
            TextWrapping = TextWrapping.NoWrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            FontFamily = new FontFamily("Consolas")
        };
        Grid.SetRow(license, 2);
        root.Children.Add(license);
        return root;
    }

    private static string ReadLicense()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("MCBEEditor.AGPL-3.0.txt");
        if (stream is null) return "GNU AGPL-3.0-or-later\n\n许可证资源未嵌入。";
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
