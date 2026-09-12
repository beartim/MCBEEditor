using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Desktop;

internal static class NbtTreeVisuals
{
    public static FrameworkElement CreateHeader(string name, NbtValue value, bool isRoot = false, bool hasChildren = false)
    {
        var grid = new Grid { Height = 28, SnapsToDevicePixels = true };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(isRoot ? 0 : 18) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(26) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        if (!isRoot)
        {
            var connector = new Canvas { Width = 18, Height = 28, IsHitTestVisible = false };
            var brush = new SolidColorBrush(Color.FromArgb(110, 100, 100, 100));
            brush.Freeze();
            connector.Children.Add(new Line
            {
                X1 = 7, X2 = 7, Y1 = 0, Y2 = 14,
                Stroke = brush, StrokeThickness = 1.1,
                SnapsToDevicePixels = true
            });
            connector.Children.Add(new Line
            {
                X1 = 7, X2 = 17, Y1 = 14, Y2 = 14,
                Stroke = brush, StrokeThickness = 1.1,
                SnapsToDevicePixels = true
            });
            if (hasChildren)
            {
                connector.Children.Add(new Line
                {
                    X1 = 7, X2 = 7, Y1 = 14, Y2 = 28,
                    Stroke = brush, StrokeThickness = 1.1,
                    SnapsToDevicePixels = true
                });
            }
            Grid.SetColumn(connector, 0);
            grid.Children.Add(connector);
        }

        var badge = CreateTypeBadge(value.Type);
        badge.Margin = new Thickness(1, 2, 1, 2);
        Grid.SetColumn(badge, 1);
        grid.Children.Add(badge);

        var text = new TextBlock
        {
            Text = $"{name} : {value.Type} {value.Summary}",
            VerticalAlignment = VerticalAlignment.Center,
            FontFamily = new FontFamily("Consolas"),
            Margin = new Thickness(5, 0, 8, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(text, 2);
        grid.Children.Add(text);
        return grid;
    }

    public static TreeViewItem CreateReadOnlyTreeItem(string name, NbtValue value, bool isRoot = false)
    {
        var children = ChildEntries(value).ToArray();
        var item = new TreeViewItem
        {
            Header = CreateHeader(name, value, isRoot, children.Length > 0),
            IsExpanded = isRoot,
            Tag = value
        };
        foreach (var child in children)
            item.Items.Add(CreateReadOnlyTreeItem(child.Name, child.Value));
        return item;
    }

    private static IEnumerable<(string Name, NbtValue Value)> ChildEntries(NbtValue value)
    {
        if (value is NbtCompoundValue compound)
        {
            foreach (var tag in compound.Tags) yield return (tag.Name, tag.Value);
            yield break;
        }
        if (value is NbtListValue list)
        {
            for (var index = 0; index < list.Values.Count; index++)
                yield return ($"[{index}]", list.Values[index]);
        }
    }

    private static Border CreateTypeBadge(NbtTagType type)
    {
        var badge = new Border
        {
            Width = 24,
            Height = 24,
            CornerRadius = new CornerRadius(5),
            Background = new SolidColorBrush(BackgroundColor(type)),
            Child = new TextBlock
            {
                Text = Abbreviation(type),
                Foreground = type == NbtTagType.Int ? Brushes.Black : Brushes.White,
                FontFamily = new FontFamily("Consolas"),
                FontSize = Abbreviation(type).Length switch { 1 => 13, 2 => 11, _ => 8 },
                FontWeight = FontWeights.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        return badge;
    }

    private static string Abbreviation(NbtTagType type) => type switch
    {
        NbtTagType.End => "E",
        NbtTagType.Byte => "B",
        NbtTagType.Short => "S",
        NbtTagType.Int => "I",
        NbtTagType.Long => "L",
        NbtTagType.Float => "F",
        NbtTagType.Double => "D",
        NbtTagType.ByteArray => "B[]",
        NbtTagType.String => "T",
        NbtTagType.List => "[]",
        NbtTagType.Compound => "{}",
        NbtTagType.IntArray => "I[]",
        NbtTagType.LongArray => "L[]",
        _ => "?"
    };

    private static Color BackgroundColor(NbtTagType type) => type switch
    {
        NbtTagType.End => Color.FromRgb(115, 125, 135),
        NbtTagType.Byte => Color.FromRgb(214, 51, 56),
        NbtTagType.Short => Color.FromRgb(232, 99, 26),
        NbtTagType.Int => Color.FromRgb(209, 156, 8),
        NbtTagType.Long => Color.FromRgb(140, 87, 41),
        NbtTagType.Float => Color.FromRgb(41, 153, 79),
        NbtTagType.Double => Color.FromRgb(13, 135, 143),
        NbtTagType.ByteArray => Color.FromRgb(140, 69, 171),
        NbtTagType.String => Color.FromRgb(31, 110, 199),
        NbtTagType.List => Color.FromRgb(87, 87, 209),
        NbtTagType.Compound => Color.FromRgb(194, 48, 130),
        NbtTagType.IntArray => Color.FromRgb(79, 94, 110),
        NbtTagType.LongArray => Color.FromRgb(46, 64, 79),
        _ => Color.FromRgb(100, 100, 100)
    };
}
