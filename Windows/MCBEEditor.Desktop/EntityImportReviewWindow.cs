using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Desktop;

public sealed record EntityImportReviewRow(int Index, string Identifier, string UniqueId, string Dimension, string Position)
{
    public string Number => (Index + 1).ToString(CultureInfo.InvariantCulture);
}

public sealed class EntityImportReviewWindow : Window
{
    private readonly List<NbtDocument> _documents;
    private readonly Func<IReadOnlyList<NbtDocument>, int?, Task> _importAsync;
    private readonly ObservableCollection<EntityImportReviewRow> _rows = new();
    private readonly DataGrid _grid = new();
    private readonly Button _import = new();
    private readonly TextBlock _status = new();

    public bool DidImport { get; private set; }

    public EntityImportReviewWindow(IEnumerable<NbtDocument> documents, Func<IReadOnlyList<NbtDocument>, int?, Task> importAsync)
    {
        _documents = documents.Select(document => new NbtDocument(document.RootName, NbtDocumentTools.DeepClone(document.Root))).ToList();
        _importAsync = importAsync;
        Title = "检查实体 NBT";
        Width = 920;
        Height = 620;
        MinWidth = 720;
        MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi();
        RefreshRows();
    }

    private UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(12) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var intro = new TextBlock
        {
            Text = "文件中的每个根标签都会创建一个实体。双击可先编辑；导入准备阶段只修改 Pos 和 UniqueID，不补充任何默认实体标签，也不改动 DimensionId。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 0, 0, 8)
        };
        root.Children.Add(intro);

        _grid.ItemsSource = _rows;
        _grid.AutoGenerateColumns = false;
        _grid.IsReadOnly = true;
        _grid.CanUserAddRows = false;
        _grid.HeadersVisibility = DataGridHeadersVisibility.Column;
        _grid.GridLinesVisibility = DataGridGridLinesVisibility.Horizontal;
        _grid.RowHeaderWidth = 0;
        _grid.SelectionMode = DataGridSelectionMode.Single;
        _grid.MouseDoubleClick += Grid_MouseDoubleClick;
        _grid.Columns.Add(new DataGridTextColumn { Header = "#", Binding = new System.Windows.Data.Binding(nameof(EntityImportReviewRow.Number)), Width = 55 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "实体 ID", Binding = new System.Windows.Data.Binding(nameof(EntityImportReviewRow.Identifier)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        _grid.Columns.Add(new DataGridTextColumn { Header = "UniqueID", Binding = new System.Windows.Data.Binding(nameof(EntityImportReviewRow.UniqueId)), Width = 150 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "维度", Binding = new System.Windows.Data.Binding(nameof(EntityImportReviewRow.Dimension)), Width = 100 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Pos", Binding = new System.Windows.Data.Binding(nameof(EntityImportReviewRow.Position)), Width = 220 });
        Grid.SetRow(_grid, 1); root.Children.Add(_grid);

        _status.Margin = new Thickness(0, 8, 0, 0);
        _status.Foreground = System.Windows.Media.Brushes.DimGray;
        _status.Text = $"共 {_documents.Count:N0} 个实体；双击行可修改导入缓冲区。";
        Grid.SetRow(_status, 2); root.Children.Add(_status);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 8, 0, 0) };
        var edit = new Button { Content = "编辑所选 NBT", Padding = new Thickness(14, 5, 14, 5) };
        edit.Click += (_, _) => EditSelected();
        _import.Content = "导入全部";
        _import.Padding = new Thickness(16, 5, 16, 5);
        _import.Margin = new Thickness(6, 0, 0, 0);
        _import.IsDefault = true;
        _import.Click += Import_Click;
        var cancel = new Button { Content = "取消", Padding = new Thickness(16, 5, 16, 5), Margin = new Thickness(6, 0, 0, 0), IsCancel = true };
        buttons.Children.Add(edit); buttons.Children.Add(_import); buttons.Children.Add(cancel);
        Grid.SetRow(buttons, 3); root.Children.Add(buttons);
        return root;
    }

    private void Grid_MouseDoubleClick(object sender, MouseButtonEventArgs e) => EditSelected();

    private void EditSelected()
    {
        if (_grid.SelectedItem is not EntityImportReviewRow row || row.Index < 0 || row.Index >= _documents.Count) return;
        var index = row.Index;
        var editor = new NbtEditorWindow($"导入实体 {index + 1}", _documents[index], edited =>
        {
            _documents[index] = edited;
            RefreshRows();
            return Task.CompletedTask;
        }) { Owner = this };
        editor.ShowDialog();
        if (editor.DidSave) RefreshRows();
    }

    private async void Import_Click(object sender, RoutedEventArgs e)
    {
        int? fallbackDimension = null;
        var missing = _documents.Count(document => BedrockEntityCommonNbt.Dimension(document.Root) is null);
        if (missing > 0)
        {
            var chooser = new DimensionChoiceWindow($"有 {missing} 个实体缺少 DimensionId。请选择这些实体写入数据库时使用的维度；不会向 NBT 中添加 DimensionId。") { Owner = this };
            if (chooser.ShowDialog() != true) return;
            fallbackDimension = chooser.Dimension;
        }

        try
        {
            _import.IsEnabled = false;
            _status.Text = "正在导入全部实体…";
            await _importAsync(_documents, fallbackDimension);
            DidImport = true;
            DialogResult = true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "导入实体失败", MessageBoxButton.OK, MessageBoxImage.Error);
            _status.Text = "导入失败；未完成的写入已由每次 LevelDB 原子批次保护，但请重新扫描确认当前状态。";
        }
        finally
        {
            _import.IsEnabled = true;
        }
    }

    private void RefreshRows()
    {
        _rows.Clear();
        for (var index = 0; index < _documents.Count; index++)
        {
            var document = _documents[index];
            var identifier = BedrockEntityCommonNbt.Identifier(document.Root) ?? "未知实体";
            var uniqueId = BedrockEntityCommonNbt.UniqueId(document.Root)?.ToString(CultureInfo.InvariantCulture) ?? "缺失";
            var dimension = BedrockEntityCommonNbt.Dimension(document.Root) is int dim ? BedrockDimensionNames.DisplayName(dim) : "缺失";
            var position = BedrockEntityCommonNbt.Position(document.Root);
            var positionText = position is null ? "缺失" : $"{Format(position.X)}, {Format(position.Y)}, {Format(position.Z)}";
            _rows.Add(new EntityImportReviewRow(index, identifier, uniqueId, dimension, positionText));
        }
        _status.Text = $"共 {_documents.Count:N0} 个实体；双击行可修改导入缓冲区。";
    }

    private static string Format(double value) => value.ToString("0.##", CultureInfo.InvariantCulture);
}

public sealed class DimensionChoiceWindow : Window
{
    private readonly ComboBox _dimension = new();
    public int Dimension { get; private set; }

    public DimensionChoiceWindow(string message)
    {
        Title = "选择维度";
        Width = 520;
        Height = 220;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var root = new Grid { Margin = new Thickness(16) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var text = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) };
        root.Children.Add(text);
        _dimension.Items.Add(new ComboBoxItem { Content = "主世界", Tag = 0 });
        _dimension.Items.Add(new ComboBoxItem { Content = "下界", Tag = 1 });
        _dimension.Items.Add(new ComboBoxItem { Content = "末地", Tag = 2 });
        _dimension.SelectedIndex = 0;
        Grid.SetRow(_dimension, 1); root.Children.Add(_dimension);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var ok = new Button { Content = "确定", Padding = new Thickness(16, 5, 16, 5), IsDefault = true };
        ok.Click += (_, _) =>
        {
            Dimension = _dimension.SelectedItem is ComboBoxItem item && item.Tag is int value ? value : 0;
            DialogResult = true;
        };
        var cancel = new Button { Content = "取消", Padding = new Thickness(16, 5, 16, 5), Margin = new Thickness(6, 0, 0, 0), IsCancel = true };
        buttons.Children.Add(ok); buttons.Children.Add(cancel);
        Grid.SetRow(buttons, 3); root.Children.Add(buttons);
        Content = root;
    }
}
