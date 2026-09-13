using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MCBEEditor.Core.Nbt;
using Microsoft.Win32;

namespace MCBEEditor.Desktop;

public sealed class NbtEditorWindow : Window
{
    private const string ClipboardPrefix = "MCBEEditor-NBT-v1:";
    private const string BatchClipboardPrefix = "MCBEEditor-NBT-batch-v1:";
    private readonly string _rootName;
    private readonly Func<NbtDocument, Task>? _saveAsync;
    private readonly HashSet<string> _protectedRootNames;
    private readonly NbtEncoding _fileEncoding;
    private readonly string? _structureName;
    private readonly TreeView _tree = new();
    private readonly TextBox _searchText = new();
    private readonly TextBlock _searchStatus = new();
    private readonly TextBlock _pathText = new();
    private readonly TextBlock _typeText = new();
    private readonly TextBox _valueText = new();
    private readonly TextBlock _hintText = new();
    private readonly Button _applyButton = new();
    private readonly Button _saveButton = new();
    private readonly WrapPanel _normalActions = new();
    private readonly WrapPanel _batchActions = new() { Visibility = Visibility.Collapsed };
    private readonly Button _batchSelectAllButton = new();
    private readonly Button _batchCopyButton = new();
    private readonly Button _batchExportButton = new();
    private readonly Button _batchDeleteButton = new();
    private NbtEditorNode _root;
    private NbtEditorNode? _selected;
    private List<NbtEditorNode> _searchResults = new();
    private int _searchIndex = -1;
    private string _lastSearch = string.Empty;
    private bool _dirty;
    private bool _batchSelectionActive;
    private readonly HashSet<NbtEditorNode> _batchSelected = new();
    public bool DidSave { get; private set; }

    public NbtEditorWindow(string title, NbtDocument document, Func<NbtDocument, Task>? saveAsync = null,
        IEnumerable<string>? protectedRootNames = null, NbtEncoding fileEncoding = NbtEncoding.LittleEndian, string? structureName = null)
    {
        Title = title;
        Width = 1040;
        Height = 760;
        MinWidth = 780;
        MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        _rootName = document.RootName;
        _saveAsync = saveAsync;
        _fileEncoding = fileEncoding;
        _structureName = structureName;
        _protectedRootNames = new HashSet<string>(protectedRootNames ?? Array.Empty<string>(), StringComparer.OrdinalIgnoreCase);
        _root = NbtEditorNode.Create(document.RootName.Length == 0 ? "<root>" : document.RootName, NbtDocumentTools.DeepClone(document.Root), null, true);
        Content = BuildUi();
        PopulateTree();
    }

    private UIElement BuildUi()
    {
        var rootGrid = new Grid { Margin = new Thickness(10) };
        rootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.58, GridUnitType.Star) });
        rootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        rootGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.42, GridUnitType.Star) });

        var left = new Grid();
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        left.Children.Add(new TextBlock { Text = "NBT 树", FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 6) });

        var search = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
        var find = new Button { Content = "查找/下一个", Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(6, 0, 0, 0) };
        find.Click += Find_Click;
        DockPanel.SetDock(find, Dock.Right);
        search.Children.Add(find);
        _searchText.MinWidth = 160;
        _searchText.ToolTip = "按名称 → 值 → 类型搜索";
        _searchText.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) { Find_Click(find, new RoutedEventArgs()); e.Handled = true; } };
        search.Children.Add(_searchText);
        Grid.SetRow(search, 1);
        left.Children.Add(search);

        Grid.SetRow(_tree, 2);
        _tree.SelectedItemChanged += Tree_SelectedItemChanged;
        left.Children.Add(_tree);

        _searchStatus.Foreground = Brushes.DimGray;
        _searchStatus.Margin = new Thickness(0, 5, 0, 0);
        Grid.SetRow(_searchStatus, 3);
        left.Children.Add(_searchStatus);
        Grid.SetColumn(left, 0);
        rootGrid.Children.Add(left);

        var splitter = new GridSplitter { Width = 5, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Stretch };
        Grid.SetColumn(splitter, 1);
        rootGrid.Children.Add(splitter);

        var right = new Grid { Margin = new Thickness(8, 0, 0, 0) };
        for (var i = 0; i < 9; i++) right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        AddLabel(right, "路径", 0);
        _pathText.TextWrapping = TextWrapping.Wrap;
        _pathText.Margin = new Thickness(0, 0, 0, 8);
        Grid.SetRow(_pathText, 1);
        right.Children.Add(_pathText);

        AddLabel(right, "类型", 2);
        _typeText.Margin = new Thickness(0, 0, 0, 8);
        Grid.SetRow(_typeText, 3);
        right.Children.Add(_typeText);

        AddLabel(right, "值", 4);
        _valueText.AcceptsReturn = true;
        _valueText.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        _valueText.FontFamily = new FontFamily("Consolas");
        _valueText.MinHeight = 100;
        Grid.SetRow(_valueText, 5);
        right.Children.Add(_valueText);

        _applyButton.Content = "应用当前值";
        _applyButton.Margin = new Thickness(0, 8, 0, 0);
        _applyButton.Padding = new Thickness(12, 4, 12, 4);
        _applyButton.HorizontalAlignment = HorizontalAlignment.Left;
        _applyButton.Click += Apply_Click;
        Grid.SetRow(_applyButton, 6);
        right.Children.Add(_applyButton);

        _normalActions.Margin = new Thickness(0, 10, 0, 0);
        _normalActions.Children.Add(ActionButton("新增子项", AddChild_Click));
        _normalActions.Children.Add(ActionButton("删除", Delete_Click));
        _normalActions.Children.Add(ActionButton("重命名", Rename_Click));
        _normalActions.Children.Add(ActionButton("复制", Copy_Click));
        _normalActions.Children.Add(ActionButton("复制值", CopyValue_Click));
        _normalActions.Children.Add(ActionButton("复制路径和值", CopyPathAndValue_Click));
        _normalActions.Children.Add(ActionButton("粘贴", Paste_Click));
        _normalActions.Children.Add(ActionButton("导入 NBT", Import_Click));
        _normalActions.Children.Add(ActionButton(_structureName is null ? "导出 NBT" : "导出结构…", Export_Click));
        _normalActions.Children.Add(ActionButton("选择", BeginBatchSelection_Click));

        _batchActions.Margin = new Thickness(0, 10, 0, 0);
        _batchActions.Children.Add(ActionButton("取消", CancelBatchSelection_Click));
        _batchSelectAllButton.Content = "全选";
        _batchSelectAllButton.Padding = new Thickness(9, 3, 9, 3);
        _batchSelectAllButton.Margin = new Thickness(0, 0, 5, 5);
        _batchSelectAllButton.Click += ToggleBatchSelectAll_Click;
        _batchActions.Children.Add(_batchSelectAllButton);
        _batchCopyButton.Content = "复制所选";
        _batchCopyButton.Padding = new Thickness(9, 3, 9, 3);
        _batchCopyButton.Margin = new Thickness(0, 0, 5, 5);
        _batchCopyButton.Click += CopyBatchSelection_Click;
        _batchActions.Children.Add(_batchCopyButton);
        _batchExportButton.Content = "导出所选";
        _batchExportButton.Padding = new Thickness(9, 3, 9, 3);
        _batchExportButton.Margin = new Thickness(0, 0, 5, 5);
        _batchExportButton.Click += ExportBatchSelection_Click;
        _batchActions.Children.Add(_batchExportButton);
        _batchDeleteButton.Content = "删除所选";
        _batchDeleteButton.Padding = new Thickness(9, 3, 9, 3);
        _batchDeleteButton.Margin = new Thickness(0, 0, 5, 5);
        _batchDeleteButton.Foreground = Brushes.Firebrick;
        _batchDeleteButton.Click += DeleteBatchSelection_Click;
        _batchActions.Children.Add(_batchDeleteButton);

        var actionHost = new StackPanel();
        actionHost.Children.Add(_normalActions);
        actionHost.Children.Add(_batchActions);
        Grid.SetRow(actionHost, 7);
        right.Children.Add(actionHost);

        _hintText.Foreground = Brushes.DimGray;
        _hintText.TextWrapping = TextWrapping.Wrap;
        _hintText.Margin = new Thickness(0, 8, 0, 8);
        Grid.SetRow(_hintText, 8);
        right.Children.Add(_hintText);

        var spacer = new Border();
        Grid.SetRow(spacer, 9);
        right.Children.Add(spacer);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        _saveButton.Content = _saveAsync is null ? "只读" : "应用 NBT";
        _saveButton.IsEnabled = _saveAsync is not null;
        _saveButton.Padding = new Thickness(14, 5, 14, 5);
        _saveButton.Click += Save_Click;
        buttons.Children.Add(_saveButton);
        var close = new Button { Content = "关闭", Padding = new Thickness(14, 5, 14, 5), Margin = new Thickness(6, 0, 0, 0) };
        close.Click += (_, _) => Close();
        buttons.Children.Add(close);
        Grid.SetRow(buttons, 10);
        right.Children.Add(buttons);

        Grid.SetColumn(right, 2);
        rootGrid.Children.Add(right);
        return rootGrid;
    }

    private static Button ActionButton(string text, RoutedEventHandler handler)
    {
        var button = new Button { Content = text, Padding = new Thickness(9, 3, 9, 3), Margin = new Thickness(0, 0, 5, 5) };
        button.Click += handler;
        return button;
    }

    private static void AddLabel(Grid grid, string text, int row)
    {
        var label = new TextBlock { Text = text, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, row == 0 ? 0 : 6, 0, 3) };
        Grid.SetRow(label, row);
        grid.Children.Add(label);
    }

    private void PopulateTree(NbtEditorNode? select = null)
    {
        _tree.Items.Clear();
        var rootItem = MakeTreeItem(_root);
        rootItem.IsExpanded = true;
        _tree.Items.Add(rootItem);
        SelectNode(select ?? _root);
    }

    private TreeViewItem MakeTreeItem(NbtEditorNode node)
    {
        var item = new TreeViewItem
        {
            Header = CreateTreeHeader(node),
            Tag = node
        };
        item.MouseLeftButtonDown += TreeItem_PreviewMouseLeftButtonDown;
        foreach (var child in node.Children) item.Items.Add(MakeTreeItem(child));
        return item;
    }

    private void Tree_SelectedItemChanged(object sender, RoutedPropertyChangedEventArgs<object> e)
    {
        if (e.NewValue is not TreeViewItem item || item.Tag is not NbtEditorNode node) return;
        _selected = node;
        _pathText.Text = node.Path;
        _typeText.Text = node.Value.Type.ToString();
        _valueText.Text = ScalarText(node.Value);

        var editable = IsEditableScalar(node.Value) && _saveAsync is not null && !IsProtected(node);
        _valueText.IsReadOnly = !editable;
        _applyButton.IsEnabled = editable;
        if (IsProtected(node))
            _hintText.Text = "此字段会影响实体身份或受保护的存储属性，当前保持只读。";
        else if (_saveAsync is null)
            _hintText.Text = "此 NBT 以只读方式打开。搜索、复制和导出仍可使用。";
        else if (!IsEditableScalar(node.Value))
            _hintText.Text = "Compound/List 可新增、删除、重命名、复制/粘贴或导入子项；数组可查看/导出。List 始终强制相同元素类型。";
        else
            _hintText.Text = node.Value.Type switch
            {
                NbtTagType.String => "字符串直接输入；无效 UTF-8 RawString 为保护原始字节保持只读。",
                NbtTagType.ByteArray => "ByteArray 使用空格或逗号分隔；支持十进制、0x 十六进制或带 A-F 的十六进制字节。",
                NbtTagType.IntArray or NbtTagType.LongArray => "数组使用空格或逗号分隔整数。",
                _ => "输入与当前 NBT 类型匹配的数值。"
            };
    }

    private bool IsProtected(NbtEditorNode node)
    {
        for (var cursor = node; cursor.Parent is not null; cursor = cursor.Parent)
            if (cursor.Parent.IsRoot && _protectedRootNames.Contains(cursor.Name)) return true;
        return false;
    }

    private static bool IsEditableScalar(NbtValue value) => value switch
    {
        NbtByteValue or NbtShortValue or NbtIntValue or NbtLongValue or NbtFloatValue or NbtDoubleValue => true,
        NbtByteArrayValue or NbtIntArrayValue or NbtLongArrayValue => true,
        NbtStringValue text => !NbtRawStringCodec.TryRawBytes(text.Value, out _),
        _ => false
    };

    private static string ScalarText(NbtValue value) => value switch
    {
        NbtByteValue v => v.Value.ToString(CultureInfo.InvariantCulture),
        NbtShortValue v => v.Value.ToString(CultureInfo.InvariantCulture),
        NbtIntValue v => v.Value.ToString(CultureInfo.InvariantCulture),
        NbtLongValue v => v.Value.ToString(CultureInfo.InvariantCulture),
        NbtFloatValue v => v.Value.ToString("R", CultureInfo.InvariantCulture),
        NbtDoubleValue v => v.Value.ToString("R", CultureInfo.InvariantCulture),
        NbtStringValue v => NbtRawStringCodec.DisplayText(v.Value),
        NbtByteArrayValue v => string.Join(' ', v.Value.Select(b => b.ToString("x2", CultureInfo.InvariantCulture))),
        NbtIntArrayValue v => string.Join(',', v.Values),
        NbtLongArrayValue v => string.Join(',', v.Values),
        _ => value.Summary
    };

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        if (!TryApplyCurrent(showErrors: true)) return;
        _hintText.Text = "当前值已应用到编辑缓冲区；点击“应用 NBT”才会写入 Cache 工作副本，源世界不会被修改。";
    }

    private bool TryApplyCurrent(bool showErrors)
    {
        var node = _selected;
        if (node is null || !IsEditableScalar(node.Value) || IsProtected(node) || _saveAsync is null) return true;
        try
        {
            node.Value = ParseEditableValue(node.Value.Type, _valueText.Text);
            MarkDirty();
            if (_tree.SelectedItem is TreeViewItem selectedItem)
                selectedItem.Header = CreateTreeHeader(node);
            _typeText.Text = node.Value.Type.ToString();
            return true;
        }
        catch (Exception ex) when (ex is FormatException or OverflowException)
        {
            if (showErrors) MessageBox.Show(this, "值格式无效：" + ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }
    }

    private static NbtValue ParseEditableValue(NbtTagType type, string text) => type switch
    {
        NbtTagType.Byte => new NbtByteValue(sbyte.Parse(text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture)),
        NbtTagType.Short => new NbtShortValue(short.Parse(text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture)),
        NbtTagType.Int => new NbtIntValue(int.Parse(text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture)),
        NbtTagType.Long => new NbtLongValue(long.Parse(text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture)),
        NbtTagType.Float => new NbtFloatValue(float.Parse(text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture)),
        NbtTagType.Double => new NbtDoubleValue(double.Parse(text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture)),
        NbtTagType.String => new NbtStringValue(text),
        NbtTagType.ByteArray => new NbtByteArrayValue(ParseByteArray(text)),
        NbtTagType.IntArray => new NbtIntArrayValue(SplitArrayTokens(text).Select(token => int.Parse(token, NumberStyles.Integer, CultureInfo.InvariantCulture)).ToArray()),
        NbtTagType.LongArray => new NbtLongArrayValue(SplitArrayTokens(text).Select(token => long.Parse(token, NumberStyles.Integer, CultureInfo.InvariantCulture)).ToArray()),
        _ => throw new FormatException("当前类型不是可编辑值。")
    };

    private static byte[] ParseByteArray(string text)
    {
        var values = new List<byte>();
        foreach (var token in SplitArrayTokens(text))
        {
            var value = token.Trim();
            var hex = value.StartsWith("0x", StringComparison.OrdinalIgnoreCase) || value.Any(ch => (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F'));
            if (value.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) value = value[2..];
            values.Add(byte.Parse(value, hex ? NumberStyles.HexNumber : NumberStyles.Integer, CultureInfo.InvariantCulture));
        }
        return values.ToArray();
    }

    private static string[] SplitArrayTokens(string text)
        => text.Split(new[] { ',', ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    private FrameworkElement CreateTreeHeader(NbtEditorNode node)
    {
        var normal = NbtTreeVisuals.CreateHeader(node.Name, node.Value, node.IsRoot, node.Children.Count > 0);
        if (!_batchSelectionActive) return normal;
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        panel.Children.Add(new TextBlock
        {
            Text = _batchSelected.Contains(node) ? "☑" : "☐",
            Width = 24,
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 16,
            Foreground = _batchSelected.Contains(node) ? Brushes.DodgerBlue : Brushes.DimGray
        });
        panel.Children.Add(normal);
        return panel;
    }

    private void TreeItem_PreviewMouseLeftButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (!_batchSelectionActive || sender is not TreeViewItem item || item.Tag is not NbtEditorNode node) return;
        if (!_batchSelected.Add(node)) _batchSelected.Remove(node);
        item.Header = CreateTreeHeader(node);
        UpdateBatchSelectionUi();
        e.Handled = true;
    }

    private void BeginBatchSelection_Click(object sender, RoutedEventArgs e)
    {
        _batchSelectionActive = true;
        _batchSelected.Clear();
        _normalActions.Visibility = Visibility.Collapsed;
        _batchActions.Visibility = Visibility.Visible;
        RefreshTreeHeaders();
        UpdateBatchSelectionUi();
    }

    private void CancelBatchSelection_Click(object sender, RoutedEventArgs e) => EndBatchSelection();

    private void EndBatchSelection(string? message = null)
    {
        _batchSelectionActive = false;
        _batchSelected.Clear();
        _batchActions.Visibility = Visibility.Collapsed;
        _normalActions.Visibility = Visibility.Visible;
        RefreshTreeHeaders();
        if (!string.IsNullOrWhiteSpace(message)) _hintText.Text = message;
    }

    private void ToggleBatchSelectAll_Click(object sender, RoutedEventArgs e)
    {
        if (!_batchSelectionActive) return;
        var visible = VisibleBatchNodes().ToArray();
        var allSelected = visible.Length > 0 && visible.All(_batchSelected.Contains);
        if (allSelected)
        {
            foreach (var node in visible) _batchSelected.Remove(node);
        }
        else
        {
            foreach (var node in visible) _batchSelected.Add(node);
        }
        RefreshTreeHeaders();
        UpdateBatchSelectionUi();
    }

    private void CopyBatchSelection_Click(object sender, RoutedEventArgs e)
    {
        var nodes = BatchSelectedNodes();
        if (nodes.Count == 0) return;
        try
        {
            CopyDocumentsToClipboard(nodes.Select(DocumentForNode).ToArray());
            UpdateBatchSelectionUi($"已复制 {nodes.Count:N0} 个 NBT 标签。 ");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "批量复制失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ExportBatchSelection_Click(object sender, RoutedEventArgs e)
    {
        var nodes = BatchSelectedNodes();
        if (nodes.Count == 0) return;
        var documents = nodes.Select(DocumentForNode).ToArray();
        var dialog = new SaveFileDialog
        {
            Title = "导出所选 NBT",
            Filter = documents.Length == 1
                ? "NBT file (*.nbt)|*.nbt|JSON NBT (*.json)|*.json|mcstructure (*.mcstructure)|*.mcstructure"
                : "连续 NBT (*.nbt)|*.nbt|JSON NBT (*.json)|*.json",
            FileName = $"nbt-selected-{documents.Length}.nbt",
            AddExtension = true
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var extension = Path.GetExtension(dialog.FileName).ToLowerInvariant();
            byte[] data;
            if (extension == ".json") data = StandaloneNbtFileCodec.EncodeJson(documents);
            else if (extension == ".mcstructure") data = StandaloneNbtFileCodec.EncodeAsMcStructure(documents).Data;
            else data = StandaloneNbtFileCodec.Encode(documents, _fileEncoding);
            File.WriteAllBytes(dialog.FileName, data);
            UpdateBatchSelectionUi($"已导出 {documents.Length:N0} 个 NBT 标签。 ");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "批量导出失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void DeleteBatchSelection_Click(object sender, RoutedEventArgs e)
    {
        if (_saveAsync is null) return;
        var selected = BatchSelectedNodes();
        if (selected.Count == 0) return;
        if (selected.Any(node => node.IsRoot || IsProtected(node) || node.Parent is null))
        {
            MessageBox.Show(this, "所选内容包含 NBT 根节点或受保护标签，不能批量删除。", "无法批量删除", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var selectedSet = selected.ToHashSet();
        var normalized = selected.Where(node => !Ancestors(node).Any(selectedSet.Contains)).ToArray();
        if (normalized.Length == 0) return;
        if (MessageBox.Show(this, $"删除所选 {normalized.Length:N0} 个 NBT 标签及其全部子标签？\n修改仍需点击“应用 NBT”才会写入 Cache 工作副本。",
                "删除所选 NBT 标签？", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;

        var affectedParents = new HashSet<NbtEditorNode>();
        foreach (var node in normalized)
        {
            var parent = node.Parent!;
            parent.Children.Remove(node);
            affectedParents.Add(parent);
        }
        foreach (var parent in affectedParents)
        {
            if (parent.Value is NbtListValue && parent.Children.Count == 0)
                parent.Value = new NbtListValue(NbtTagType.End, Array.Empty<NbtValue>());
            parent.ReindexListChildren();
        }
        MarkDirty();
        EndBatchSelection($"已删除 {normalized.Length:N0} 个 NBT 标签；点击“应用 NBT”写入工作副本。");
        PopulateTree(_root);
    }

    private IReadOnlyList<NbtEditorNode> BatchSelectedNodes()
        => _root.DescendantsAndSelf().Where(_batchSelected.Contains).ToArray();

    private static IEnumerable<NbtEditorNode> Ancestors(NbtEditorNode node)
    {
        for (var parent = node.Parent; parent is not null; parent = parent.Parent) yield return parent;
    }

    private IEnumerable<NbtEditorNode> VisibleBatchNodes()
    {
        foreach (var item in _tree.Items.OfType<TreeViewItem>())
        foreach (var node in VisibleBatchNodes(item, includeCurrent: false))
            yield return node;
    }

    private static IEnumerable<NbtEditorNode> VisibleBatchNodes(TreeViewItem item, bool includeCurrent)
    {
        if (includeCurrent && item.Tag is NbtEditorNode node) yield return node;
        if (!item.IsExpanded) yield break;
        foreach (var child in item.Items.OfType<TreeViewItem>())
        foreach (var visibleNode in VisibleBatchNodes(child, includeCurrent: true))
            yield return visibleNode;
    }

    private void RefreshTreeHeaders()
    {
        foreach (var item in _tree.Items.OfType<TreeViewItem>()) RefreshTreeHeaders(item);
    }

    private void RefreshTreeHeaders(TreeViewItem item)
    {
        if (item.Tag is NbtEditorNode node) item.Header = CreateTreeHeader(node);
        foreach (var child in item.Items.OfType<TreeViewItem>()) RefreshTreeHeaders(child);
    }

    private void UpdateBatchSelectionUi(string? message = null)
    {
        var count = _batchSelected.Count;
        var visible = VisibleBatchNodes().ToArray();
        var allVisibleSelected = visible.Length > 0 && visible.All(_batchSelected.Contains);
        _batchSelectAllButton.Content = allVisibleSelected ? "取消全选" : "全选";
        _batchCopyButton.IsEnabled = count > 0;
        _batchExportButton.IsEnabled = count > 0;
        _batchDeleteButton.IsEnabled = count > 0 && _saveAsync is not null;
        _hintText.Text = message ?? $"批量选择：已选择 {count:N0} 个标签。点击树节点切换选择；全选仅作用于当前展开可见节点。";
    }

    private void Find_Click(object? sender, RoutedEventArgs e)
    {
        var query = _searchText.Text.Trim();
        if (query.Length == 0) { _searchStatus.Text = "请输入名称、值或类型。"; return; }
        if (!query.Equals(_lastSearch, StringComparison.OrdinalIgnoreCase))
        {
            _lastSearch = query;
            _searchResults = SearchNodes(query).ToList();
            _searchIndex = -1;
        }
        if (_searchResults.Count == 0) { _searchStatus.Text = "未找到匹配项。"; return; }
        _searchIndex = (_searchIndex + 1) % _searchResults.Count;
        SelectNode(_searchResults[_searchIndex]);
        _searchStatus.Text = $"{_searchIndex + 1}/{_searchResults.Count} · 名称优先，其次值、类型";
    }

    private IEnumerable<NbtEditorNode> SearchNodes(string query)
    {
        var matches = _root.DescendantsAndSelf()
            .Select(node => (Node: node, Rank: MatchRank(node, query)))
            .Where(item => item.Rank >= 0)
            .ToArray();
        if (matches.Length == 0) return Array.Empty<NbtEditorNode>();
        var bestRank = matches.Min(item => item.Rank);
        return matches.Where(item => item.Rank == bestRank)
            .OrderBy(item => item.Node.Path, StringComparer.OrdinalIgnoreCase)
            .Select(item => item.Node);
    }

    private static int MatchRank(NbtEditorNode node, string query)
    {
        if (node.Name.Contains(query, StringComparison.OrdinalIgnoreCase)) return 0;
        var valueText = NbtDocumentTools.SearchValueText(node.Value);
        if (valueText.Length > 0 && valueText.Contains(query, StringComparison.OrdinalIgnoreCase)) return 1;
        if (node.Value.Type.ToString().Contains(query, StringComparison.OrdinalIgnoreCase)) return 2;
        return -1;
    }

    private void AddChild_Click(object sender, RoutedEventArgs e)
    {
        if (_saveAsync is null || _selected is null || IsProtected(_selected)) return;
        var parent = _selected;
        if (parent.Value is not NbtCompoundValue && parent.Value is not NbtListValue)
        {
            MessageBox.Show(this, "只能向 Compound 或 List 新增子项。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var fixedType = parent.Value is NbtListValue list && list.ElementType != NbtTagType.End ? list.ElementType : (NbtTagType?)null;
        var dialog = new NewNbtTagWindow(parent.Value is NbtCompoundValue, fixedType) { Owner = this };
        if (dialog.ShowDialog() != true) return;
        var type = dialog.SelectedType;
        var name = parent.Value is NbtCompoundValue ? UniqueChildName(parent, dialog.TagName) : $"[{parent.Children.Count}]";
        if (parent.Value is NbtListValue emptyList && emptyList.ElementType == NbtTagType.End)
            parent.Value = new NbtListValue(type, Array.Empty<NbtValue>());
        var child = NbtEditorNode.Create(name, DefaultValue(type), parent);
        parent.Children.Add(child);
        parent.ReindexListChildren();
        MarkDirty();
        PopulateTree(child);
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_saveAsync is null || _selected is null || _selected.IsRoot || _selected.Parent is null || IsProtected(_selected)) return;
        var node = _selected;
        if (MessageBox.Show(this, $"删除 {node.Path}？", "MCBEEditor", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        var parent = node.Parent;
        parent.Children.Remove(node);
        if (parent.Value is NbtListValue && parent.Children.Count == 0)
            parent.Value = new NbtListValue(NbtTagType.End, Array.Empty<NbtValue>());
        parent.ReindexListChildren();
        MarkDirty();
        PopulateTree(parent);
    }

    private void Rename_Click(object sender, RoutedEventArgs e)
    {
        if (_saveAsync is null || _selected is null || _selected.IsRoot || _selected.Parent?.Value is not NbtCompoundValue || IsProtected(_selected)) return;
        var name = TextPromptWindow.Prompt(this, "重命名 NBT 标签", "标签名称", _selected.Name);
        if (name is null) return;
        name = name.Trim();
        if (name.Length == 0) { MessageBox.Show(this, "标签名称不能为空。", "MCBEEditor"); return; }
        if (_selected.Parent.Children.Any(child => !ReferenceEquals(child, _selected) && child.Name.Equals(name, StringComparison.Ordinal)))
        {
            MessageBox.Show(this, "同一个 Compound 中已经存在同名标签。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        _selected.Name = name;
        MarkDirty();
        PopulateTree(_selected);
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        try
        {
            CopyDocumentsToClipboard([DocumentForNode(_selected)]);
            _hintText.Text = "所选 NBT 已复制到剪贴板。";
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "复制失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void CopyValue_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        Clipboard.SetText(NbtDocumentTools.SearchValueText(_selected.BuildValue()));
        _hintText.Text = "已复制所选 NBT 的值。";
    }

    private void CopyPathAndValue_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        var value = _selected.BuildValue();
        Clipboard.SetText($"{_selected.Path}{Environment.NewLine}{value.Type.ToString()}{Environment.NewLine}{NbtDocumentTools.SearchValueText(value)}");
        _hintText.Text = "已复制所选 NBT 的路径和值。";
    }

    private void Paste_Click(object sender, RoutedEventArgs e)
    {
        if (_saveAsync is null || _selected is null || IsProtected(_selected)) return;
        try
        {
            if (!TryReadClipboardDocuments(out var documents))
            {
                MessageBox.Show(this, "剪贴板中没有 MCBEEditor NBT 数据。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            if (_selected.Value is not NbtCompoundValue && _selected.Value is not NbtListValue)
                throw new InvalidOperationException("请选择 Compound 或 List 作为粘贴目标。");
            ValidateImportedDocuments(_selected, documents);
            var target = _selected;
            var result = InsertImportedDocuments(target, documents, "粘贴");
            if (result.Cancelled) return;
            PopulateTree(target);
            _hintText.Text = result.Message;
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "粘贴失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void Import_Click(object sender, RoutedEventArgs e)
    {
        if (_saveAsync is null || _selected is null || IsProtected(_selected)) return;
        if (_selected.Value is not NbtCompoundValue && _selected.Value is not NbtListValue)
        {
            MessageBox.Show(this, "请选择 Compound 或 List 作为导入目标。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var dialog = new OpenFileDialog { Filter = "NBT / mcstructure / JSON (*.nbt;*.mcstructure;*.json;*.dat)|*.nbt;*.mcstructure;*.json;*.dat|All files (*.*)|*.*", CheckFileExists = true };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var decoded = StandaloneNbtFileCodec.Decode(File.ReadAllBytes(dialog.FileName), dialog.FileName);
            ValidateImportedDocuments(_selected, decoded.Documents);
            var target = _selected;
            var result = InsertImportedDocuments(target, decoded.Documents, "导入");
            if (result.Cancelled) return;
            PopulateTree(target);
            _hintText.Text = $"{result.Message} 来源：{Path.GetFileName(dialog.FileName)}";
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "导入 NBT 失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        if (_structureName is not null)
        {
            try { _hintText.Text = StructureFileDialogs.ExportSingle(this, new NbtDocument(_rootName, _root.BuildValue()), _structureName).Message; }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "导出结构失败", MessageBoxButton.OK, MessageBoxImage.Error); }
            return;
        }
        if (_selected is null) return;
        var safeName = string.Join('_', (_selected.IsRoot ? "root" : _selected.Name).Split(Path.GetInvalidFileNameChars(), StringSplitOptions.RemoveEmptyEntries));
        if (string.IsNullOrWhiteSpace(safeName)) safeName = "nbt";
        var dialog = new SaveFileDialog { Filter = "NBT file (*.nbt)|*.nbt|All files (*.*)|*.*", FileName = safeName + ".nbt", AddExtension = true };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var document = new NbtDocument(_selected.IsRoot ? _rootName : _selected.Name, _selected.BuildValue());
            File.WriteAllBytes(dialog.FileName, NbtFileCodec.Encode(document, _fileEncoding));
            _hintText.Text = $"已导出：{dialog.FileName}";
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "导出 NBT 失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private readonly record struct ImportInsertionResult(bool Cancelled, string Message);

    private enum CompoundConflictChoice
    {
        Cancel,
        Keep,
        Overwrite
    }

    private ImportInsertionResult InsertImportedDocuments(NbtEditorNode parent, IReadOnlyList<NbtDocument> documents, string operation)
    {
        if (parent.Value is NbtListValue)
        {
            foreach (var document in documents) AddImportedListChild(parent, document);
            return new ImportInsertionResult(false, documents.Count == 1
                ? $"已{operation} NBT 标签。"
                : $"已{operation} {documents.Count:N0} 个 NBT 标签。");
        }
        if (parent.Value is not NbtCompoundValue)
            throw new InvalidOperationException("请选择 Compound 或 List 作为目标。");

        var prepared = PrepareCompoundDocuments(parent, documents);
        var occupied = new HashSet<string>(parent.Children.Select(child => child.Name), StringComparer.Ordinal);
        var conflicts = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var item in prepared)
        {
            if (occupied.Contains(item.Name)) conflicts.Add(item.Name);
            occupied.Add(item.Name);
        }

        var choice = conflicts.Count == 0 ? CompoundConflictChoice.Keep : ShowCompoundConflictDialog(conflicts);
        if (choice == CompoundConflictChoice.Cancel)
            return new ImportInsertionResult(true, string.Empty);

        occupied = new HashSet<string>(parent.Children.Select(child => child.Name), StringComparer.Ordinal);
        var inserted = 0;
        foreach (var item in prepared)
        {
            var isConflict = occupied.Contains(item.Name);
            if (isConflict && choice == CompoundConflictChoice.Keep) continue;

            if (isConflict && choice == CompoundConflictChoice.Overwrite)
            {
                var previous = parent.Children.LastOrDefault(child => child.Name.Equals(item.Name, StringComparison.Ordinal));
                if (previous is not null) parent.Children.Remove(previous);
            }

            parent.Children.Add(NbtEditorNode.Create(item.Name, NbtDocumentTools.DeepClone(item.Document.Root), parent));
            occupied.Add(item.Name);
            inserted++;
        }
        if (inserted > 0) MarkDirty();

        var message = conflicts.Count == 0
            ? inserted == 1 ? $"已{operation} NBT 标签。" : $"已{operation} {inserted:N0} 个 NBT 标签。"
            : choice == CompoundConflictChoice.Overwrite
                ? $"已{operation} {inserted:N0} 个标签并覆盖同名标签。"
                : $"已{operation} {inserted:N0} 个标签；同名标签已保留。";
        return new ImportInsertionResult(false, message);
    }

    private sealed record PreparedCompoundDocument(string Name, NbtDocument Document);

    private static IReadOnlyList<PreparedCompoundDocument> PrepareCompoundDocuments(NbtEditorNode parent, IReadOnlyList<NbtDocument> documents)
    {
        var generatedNames = new HashSet<string>(parent.Children.Select(child => child.Name), StringComparer.Ordinal);
        var output = new List<PreparedCompoundDocument>(documents.Count);
        foreach (var document in documents)
        {
            var name = document.RootName.Trim();
            if (name.Length == 0) name = UniqueGeneratedName("导入的标签", generatedNames);
            output.Add(new PreparedCompoundDocument(name, document));
        }
        return output;
    }

    private static string UniqueGeneratedName(string baseName, HashSet<string> usedNames)
    {
        if (usedNames.Add(baseName)) return baseName;
        for (var suffix = 2; ; suffix++)
        {
            var candidate = $"{baseName} {suffix}";
            if (usedNames.Add(candidate)) return candidate;
        }
    }

    private CompoundConflictChoice ShowCompoundConflictDialog(IEnumerable<string> conflictNames)
    {
        var names = conflictNames.ToArray();
        var shown = string.Join('、', names.Take(8));
        var suffix = names.Length > 8 ? $" 等 {names.Length} 个" : string.Empty;
        var dialog = new CompoundConflictWindow(
            "存在同名标签",
            $"同级 Compound 中已存在：{shown}{suffix}。请选择覆盖已有标签，或保留已有标签并跳过冲突项。")
        { Owner = this };
        dialog.ShowDialog();
        return dialog.Choice;
    }

    private void AddImportedListChild(NbtEditorNode parent, NbtDocument document)
    {
        if (parent.Value is not NbtListValue list)
            throw new InvalidOperationException("请选择 List 作为目标。");
        var elementType = list.ElementType;
        if (elementType == NbtTagType.End && parent.Children.Count == 0)
        {
            elementType = document.Root.Type;
            parent.Value = new NbtListValue(elementType, Array.Empty<NbtValue>());
        }
        if (document.Root.Type != elementType)
            throw new InvalidDataException($"List 元素类型为 {elementType}，不能加入 {document.Root.Type}。");
        parent.Children.Add(NbtEditorNode.Create($"[{parent.Children.Count}]", NbtDocumentTools.DeepClone(document.Root), parent));
        parent.ReindexListChildren();
        MarkDirty();
    }

    private NbtDocument DocumentForNode(NbtEditorNode node)
    {
        var name = node.IsRoot
            ? _rootName
            : node.Parent?.Value is NbtCompoundValue ? node.Name : string.Empty;
        return new NbtDocument(name, node.BuildValue());
    }

    private void CopyDocumentsToClipboard(IReadOnlyList<NbtDocument> documents)
    {
        if (documents.Count == 0) return;
        if (documents.Count == 1)
        {
            var bytes = NbtFileCodec.Encode(documents[0], _fileEncoding);
            Clipboard.SetText(ClipboardPrefix + ((int)_fileEncoding).ToString(CultureInfo.InvariantCulture) + ":" + Convert.ToBase64String(bytes));
            return;
        }
        var batch = StandaloneNbtFileCodec.Encode(documents, _fileEncoding);
        Clipboard.SetText(BatchClipboardPrefix + ((int)_fileEncoding).ToString(CultureInfo.InvariantCulture) + ":" + Convert.ToBase64String(batch));
    }

    private static bool TryReadClipboardDocuments(out IReadOnlyList<NbtDocument> documents)
    {
        documents = Array.Empty<NbtDocument>();
        if (!Clipboard.ContainsText()) return false;
        var text = Clipboard.GetText();
        var batch = text.StartsWith(BatchClipboardPrefix, StringComparison.Ordinal);
        var single = text.StartsWith(ClipboardPrefix, StringComparison.Ordinal);
        if (!batch && !single) return false;
        var prefix = batch ? BatchClipboardPrefix : ClipboardPrefix;
        var payload = text[prefix.Length..];
        var separator = payload.IndexOf(':');
        if (separator <= 0 || !int.TryParse(payload[..separator], out var rawEncoding) || !Enum.IsDefined(typeof(NbtEncoding), rawEncoding)) return false;
        var encoding = (NbtEncoding)rawEncoding;
        var bytes = Convert.FromBase64String(payload[(separator + 1)..]);
        if (!batch)
        {
            documents = [NbtFileCodec.DecodeSingle(bytes, encoding).Document];
            return true;
        }

        var output = new List<NbtDocument>();
        var offset = 0;
        while (offset < bytes.Length)
        {
            var document = BedrockNbtCodec.DecodeOne(bytes.AsSpan(offset), out var consumed, encoding, 256);
            if (consumed <= 0) return false;
            output.Add(document);
            offset += consumed;
        }
        documents = output;
        return output.Count > 0;
    }

    private static void ValidateImportedDocuments(NbtEditorNode parent, IReadOnlyList<NbtDocument> documents)
    {
        if (documents.Count == 0) throw new InvalidDataException("没有可导入的 NBT 根标签。");
        if (parent.Value is not NbtListValue list) return;
        var expected = list.ElementType == NbtTagType.End && parent.Children.Count == 0
            ? documents[0].Root.Type
            : list.ElementType;
        if (documents.Any(document => document.Root.Type != expected))
            throw new InvalidDataException($"List 元素类型为 {expected}，导入内容包含其它 NBT 根类型。");
    }

    private static string UniqueChildName(NbtEditorNode parent, string baseName)
    {
        baseName = string.IsNullOrWhiteSpace(baseName) ? "NewTag" : baseName.Trim();
        if (!parent.Children.Any(child => child.Name.Equals(baseName, StringComparison.Ordinal))) return baseName;
        for (var index = 2; ; index++)
        {
            var candidate = baseName + index.ToString(CultureInfo.InvariantCulture);
            if (!parent.Children.Any(child => child.Name.Equals(candidate, StringComparison.Ordinal))) return candidate;
        }
    }

    private static NbtValue DefaultValue(NbtTagType type) => type switch
    {
        NbtTagType.Byte => new NbtByteValue(0),
        NbtTagType.Short => new NbtShortValue(0),
        NbtTagType.Int => new NbtIntValue(0),
        NbtTagType.Long => new NbtLongValue(0),
        NbtTagType.Float => new NbtFloatValue(0),
        NbtTagType.Double => new NbtDoubleValue(0),
        NbtTagType.ByteArray => new NbtByteArrayValue(Array.Empty<byte>()),
        NbtTagType.String => new NbtStringValue(string.Empty),
        NbtTagType.List => new NbtListValue(NbtTagType.End, Array.Empty<NbtValue>()),
        NbtTagType.Compound => new NbtCompoundValue(Array.Empty<NbtNamedTag>()),
        NbtTagType.IntArray => new NbtIntArrayValue(Array.Empty<int>()),
        NbtTagType.LongArray => new NbtLongArrayValue(Array.Empty<long>()),
        _ => throw new ArgumentOutOfRangeException(nameof(type), "End 不能作为普通 NBT 标签。")
    };

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        if (_saveAsync is null) return;
        if (!TryApplyCurrent(showErrors: true)) return;
        try
        {
            _saveButton.IsEnabled = false;
            var document = new NbtDocument(_rootName, _root.BuildValue());
            await _saveAsync(document);
            DidSave = true;
            _dirty = false;
            _hintText.Text = "NBT 已写入世界。";
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "应用 NBT 失败", MessageBoxButton.OK, MessageBoxImage.Error); }
        finally { _saveButton.IsEnabled = true; }
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (_dirty && _saveAsync is not null)
        {
            var result = MessageBox.Show(this, "NBT 编辑缓冲区还有未应用修改，确定关闭？", "MCBEEditor", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (result != MessageBoxResult.Yes) { e.Cancel = true; return; }
        }
        base.OnClosing(e);
    }

    private void MarkDirty()
    {
        _dirty = true;
        _searchResults.Clear();
        _searchIndex = -1;
        _lastSearch = string.Empty;
    }

    private void SelectNode(NbtEditorNode target)
    {
        foreach (var rootItem in _tree.Items.OfType<TreeViewItem>())
            if (SelectNodeRecursive(rootItem, target)) return;
    }

    private static bool SelectNodeRecursive(TreeViewItem item, NbtEditorNode target)
    {
        if (ReferenceEquals(item.Tag, target))
        {
            item.IsSelected = true;
            item.BringIntoView();
            return true;
        }
        foreach (var child in item.Items.OfType<TreeViewItem>())
        {
            if (SelectNodeRecursive(child, target))
            {
                item.IsExpanded = true;
                return true;
            }
        }
        return false;
    }

    private sealed class CompoundConflictWindow : Window
    {
        public CompoundConflictChoice Choice { get; private set; } = CompoundConflictChoice.Cancel;

        public CompoundConflictWindow(string title, string message)
        {
            Title = title;
            Width = 520;
            SizeToContent = SizeToContent.Height;
            ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;

            var root = new StackPanel { Margin = new Thickness(18) };
            root.Children.Add(new TextBlock
            {
                Text = message,
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = 480,
                Margin = new Thickness(0, 0, 0, 16)
            });
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            buttons.Children.Add(MakeButton("取消", CompoundConflictChoice.Cancel, isCancel: true));
            buttons.Children.Add(MakeButton("保留", CompoundConflictChoice.Keep));
            buttons.Children.Add(MakeButton("覆盖", CompoundConflictChoice.Overwrite));
            root.Children.Add(buttons);
            Content = root;
        }

        private Button MakeButton(string text, CompoundConflictChoice choice, bool isCancel = false)
        {
            var button = new Button
            {
                Content = text, MinWidth = 82, Padding = new Thickness(12, 5, 12, 5),
                Margin = new Thickness(6, 0, 0, 0), IsCancel = isCancel
            };
            button.Click += (_, _) => { Choice = choice; DialogResult = choice != CompoundConflictChoice.Cancel; };
            return button;
        }
    }

    private sealed class NbtEditorNode
    {
        public string Name { get; set; }
        public NbtValue Value { get; set; }
        public NbtEditorNode? Parent { get; }
        public bool IsRoot { get; }
        public List<NbtEditorNode> Children { get; } = new();
        public string Path => Parent is null ? Name : Parent.Path + "/" + Name;

        private NbtEditorNode(string name, NbtValue value, NbtEditorNode? parent, bool isRoot)
        {
            Name = name; Value = value; Parent = parent; IsRoot = isRoot;
        }

        public static NbtEditorNode Create(string name, NbtValue value, NbtEditorNode? parent, bool isRoot = false)
        {
            var node = new NbtEditorNode(name, value, parent, isRoot);
            if (value is NbtCompoundValue compound)
                foreach (var tag in compound.Tags) node.Children.Add(Create(tag.Name, tag.Value, node));
            else if (value is NbtListValue list)
                for (var index = 0; index < list.Values.Count; index++) node.Children.Add(Create($"[{index}]", list.Values[index], node));
            return node;
        }

        public IEnumerable<NbtEditorNode> DescendantsAndSelf()
        {
            yield return this;
            foreach (var child in Children)
                foreach (var item in child.DescendantsAndSelf()) yield return item;
        }

        public void ReindexListChildren()
        {
            if (Value is not NbtListValue) return;
            for (var index = 0; index < Children.Count; index++) Children[index].Name = $"[{index}]";
        }

        public NbtValue BuildValue()
        {
            if (Value is NbtCompoundValue)
                return new NbtCompoundValue(Children.Select(child => new NbtNamedTag(child.Name, child.BuildValue())).ToArray());
            if (Value is NbtListValue list)
            {
                var elementType = list.ElementType;
                var values = Children.Select(child => child.BuildValue()).ToArray();
                if (values.Any(value => value.Type != elementType)) throw new InvalidDataException($"List 元素类型必须全部为 {elementType}。");
                return new NbtListValue(elementType, values);
            }
            return Value;
        }
    }
}

internal sealed class NewNbtTagWindow : Window
{
    private readonly TextBox _name = new() { Text = "NewTag", MinWidth = 220 };
    private readonly ComboBox _type = new() { MinWidth = 180 };
    public string TagName => _name.Text;
    public NbtTagType SelectedType => (NbtTagType)(_type.SelectedItem ?? NbtTagType.String);

    public NewNbtTagWindow(bool needName, NbtTagType? fixedType)
    {
        Title = "新增 NBT 子项";
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        foreach (var type in Enum.GetValues<NbtTagType>().Where(type => type != NbtTagType.End)) _type.Items.Add(type);
        _type.SelectedItem = fixedType ?? NbtTagType.String;
        _type.IsEnabled = !fixedType.HasValue;

        var panel = new StackPanel { Margin = new Thickness(14), MinWidth = 300 };
        if (needName)
        {
            panel.Children.Add(new TextBlock { Text = "名称", Margin = new Thickness(0, 0, 0, 4) });
            panel.Children.Add(_name);
        }
        panel.Children.Add(new TextBlock { Text = "类型", Margin = new Thickness(0, 10, 0, 4) });
        panel.Children.Add(_type);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        var ok = new Button { Content = "确定", IsDefault = true, Padding = new Thickness(14, 4, 14, 4) };
        ok.Click += (_, _) => { if (needName && string.IsNullOrWhiteSpace(_name.Text)) return; DialogResult = true; };
        var cancel = new Button { Content = "取消", IsCancel = true, Padding = new Thickness(14, 4, 14, 4), Margin = new Thickness(6, 0, 0, 0) };
        buttons.Children.Add(ok); buttons.Children.Add(cancel); panel.Children.Add(buttons);
        Content = panel;
    }
}

internal sealed class TextPromptWindow : Window
{
    private readonly TextBox _text = new() { MinWidth = 280 };
    public string Value => _text.Text;

    private TextPromptWindow(string title, string label, string initial)
    {
        Title = title;
        SizeToContent = SizeToContent.WidthAndHeight;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        _text.Text = initial;
        var panel = new StackPanel { Margin = new Thickness(14) };
        panel.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, 0, 0, 4) });
        panel.Children.Add(_text);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        var ok = new Button { Content = "确定", IsDefault = true, Padding = new Thickness(14, 4, 14, 4) };
        ok.Click += (_, _) => DialogResult = true;
        var cancel = new Button { Content = "取消", IsCancel = true, Padding = new Thickness(14, 4, 14, 4), Margin = new Thickness(6, 0, 0, 0) };
        buttons.Children.Add(ok); buttons.Children.Add(cancel); panel.Children.Add(buttons);
        Content = panel;
        Loaded += (_, _) => { _text.SelectAll(); _text.Focus(); };
    }

    public static string? Prompt(Window owner, string title, string label, string initial)
    {
        var window = new TextPromptWindow(title, label, initial) { Owner = owner };
        return window.ShowDialog() == true ? window.Value : null;
    }
}
