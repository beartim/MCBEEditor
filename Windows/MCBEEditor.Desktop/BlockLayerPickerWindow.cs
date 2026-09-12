using System.Windows;
using System.Windows.Controls;
using MCBEEditor.Core.Chunk;

namespace MCBEEditor.Desktop;

public sealed class BlockLayerPickerWindow : Window
{
    private readonly ComboBox _layers = new();
    public int StorageIndex { get; private set; }

    public BlockLayerPickerWindow(BedrockBlockRecord block)
    {
        Title = $"选择方块 storage · ({block.X}, {block.Y}, {block.Z})";
        Width = 500;
        Height = 210;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = $"{BedrockDimensionNames.DisplayName(block.Dimension)} · SubChunk v{block.SubChunkVersion?.ToString() ?? "?"} · {block.Layers.Count} 个 storage",
            TextWrapping = TextWrapping.Wrap
        });
        _layers.Margin = new Thickness(0, 12, 0, 12);
        for (var index = 0; index < block.Layers.Count; index++)
        {
            var state = block.Layers[index];
            _layers.Items.Add(new ComboBoxItem
            {
                Content = $"storage {index} · {state.Name}{(state.IsAir ? " · 空气" : string.Empty)}",
                Tag = index
            });
        }
        var isLegacy = block.Layers.Count > 0 && block.Layers.All(state => state.Nbt is null);
        var canCreateNext = block.BackingKind == BedrockSubChunkBackingKind.SubChunk
            && (isLegacy ? block.Layers.Count < 2 : block.Layers.Count < byte.MaxValue);
        if (canCreateNext)
        {
            _layers.Items.Add(new ComboBoxItem
            {
                Content = $"storage {block.Layers.Count} · 新建为空气",
                Tag = block.Layers.Count
            });
        }
        _layers.SelectedIndex = Math.Clamp(block.PreferredLayerIndex, 0, Math.Max(0, block.Layers.Count - 1));
        panel.Children.Add(_layers);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var ok = new Button { Content = "编辑", Padding = new Thickness(18, 5, 18, 5), IsDefault = true };
        ok.Click += (_, _) =>
        {
            StorageIndex = _layers.SelectedItem is ComboBoxItem item && item.Tag is int value ? value : 0;
            DialogResult = true;
        };
        buttons.Children.Add(ok);
        buttons.Children.Add(new Button { Content = "取消", Padding = new Thickness(18, 5, 18, 5), Margin = new Thickness(8, 0, 0, 0), IsCancel = true });
        panel.Children.Add(buttons);
        Content = panel;
    }
}
