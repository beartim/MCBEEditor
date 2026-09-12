using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Desktop;

public sealed class RegionEntitiesWindow : Window
{
    private readonly WorldDocument _world;
    private readonly MapRegionSelection _selection;
    private readonly Func<Task> _prepareMutation;
    private readonly DataGrid _grid = new();
    private readonly TextBlock _status = new();
    private IReadOnlyList<BedrockWorldObject> _objects = Array.Empty<BedrockWorldObject>();

    public RegionEntitiesWindow(WorldDocument world, MapRegionSelection selection, Func<Task> prepareMutation)
    {
        _world = world; _selection = selection; _prepareMutation = prepareMutation;
        Title = "框选区域实体"; Width = 1050; Height = 650; MinWidth = 760; MinHeight = 480; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi();
        Loaded += async (_, _) => await ReloadAsync();
    }

    private UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(10) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var top = new DockPanel { Margin = new Thickness(0,0,0,8) };
        var refresh = new Button { Content = "刷新", Padding = new Thickness(12,4,12,4) }; refresh.Click += async (_,_) => await ReloadAsync(); DockPanel.SetDock(refresh, Dock.Right); top.Children.Add(refresh);
        top.Children.Add(new TextBlock { Text = $"{BedrockDimensionNames.DisplayName(_selection.Dimension)} · X={_selection.MinimumX}…{_selection.MaximumX}, Z={_selection.MinimumZ}…{_selection.MaximumZ} · 双击编辑 NBT", VerticalAlignment = VerticalAlignment.Center });
        root.Children.Add(top);
        _grid.AutoGenerateColumns = false; _grid.IsReadOnly = true; _grid.SelectionMode = DataGridSelectionMode.Single; _grid.CanUserAddRows = false; _grid.RowHeaderWidth = 0;
        _grid.Columns.Add(new DataGridTextColumn { Header="类型", Binding=new Binding(nameof(BedrockWorldObject.Kind)), Width=90 });
        _grid.Columns.Add(new DataGridTextColumn { Header="名称", Binding=new Binding(nameof(BedrockWorldObject.DisplayName)), Width=220 });
        _grid.Columns.Add(new DataGridTextColumn { Header="identifier", Binding=new Binding(nameof(BedrockWorldObject.Identifier)), Width=240 });
        _grid.Columns.Add(new DataGridTextColumn { Header="UniqueID", Binding=new Binding(nameof(BedrockWorldObject.UniqueId)), Width=150 });
        _grid.Columns.Add(new DataGridTextColumn { Header="来源", Binding=new Binding(nameof(BedrockWorldObject.Source)), Width=130 });
        _grid.MouseDoubleClick += async (_, e) => { if (e.ChangedButton == MouseButton.Left && _grid.SelectedItem is BedrockWorldObject item) await EditAsync(item); };
        Grid.SetRow(_grid, 1); root.Children.Add(_grid);
        _status.Margin = new Thickness(0,8,0,0); _status.Foreground = System.Windows.Media.Brushes.DimGray; Grid.SetRow(_status,2); root.Children.Add(_status);
        return root;
    }

    private async Task ReloadAsync()
    {
        _status.Text = "正在扫描框选区域实体…";
        try
        {
            _objects = await Task.Run(() =>
            {
                using var db = _world.OpenDatabase(readOnly:true);
                var minCX = BedrockSurfaceRegionRenderer.FloorDiv(_selection.MinimumX,16); var maxCX = BedrockSurfaceRegionRenderer.FloorDiv(_selection.MaximumX,16);
                var minCZ = BedrockSurfaceRegionRenderer.FloorDiv(_selection.MinimumZ,16); var maxCZ = BedrockSurfaceRegionRenderer.FloorDiv(_selection.MaximumZ,16);
                var centerX = minCX + (maxCX-minCX)/2; var centerZ = minCZ + (maxCZ-minCZ)/2; var radius = Math.Max(maxCX-minCX, maxCZ-minCZ)/2 + 1;
                var scan = new BedrockWorldObjectScanner(db).ScanRegion(centerX, centerZ, _selection.Dimension, radius, true, true, 100000);
                return scan.Objects.Where(o =>
                {
                    if (o.Dimension != _selection.Dimension || o.Position is not { } position) return false;
                    return position.BlockX >= _selection.MinimumX && position.BlockX <= _selection.MaximumX
                        && position.BlockZ >= _selection.MinimumZ && position.BlockZ <= _selection.MaximumZ;
                }).ToArray();
            });
            _grid.ItemsSource = _objects; _status.Text = $"找到 {_objects.Count:N0} 个实体/方块实体。";
        }
        catch (Exception ex) { _status.Text = "扫描失败：" + ex.Message; }
    }

    private async Task EditAsync(BedrockWorldObject item)
    {
        var protectedFields = item.Kind == BedrockWorldObjectKind.Entity ? new[] { "UniqueID", "UniqueId", "uniqueID", "uniqueId" } : Array.Empty<string>();
        var editor = new NbtEditorWindow($"{item.Kind} · {item.DisplayName}", item.Document, async edited =>
        {
            await _prepareMutation();
            await Task.Run(() => { using var db = _world.OpenDatabase(readOnly:false); new BedrockWorldObjectNbtStore(db).Save(item, edited); });
        }, protectedFields, item.Storage.Encoding) { Owner = this };
        editor.ShowDialog();
        if (editor.DidSave) await ReloadAsync();
    }
}

public sealed class RegionBlockSearchWindow : Window
{
    private readonly WorldDocument _world; private readonly MapRegionSelection _selection; private readonly Action<BedrockRegionBlockHit> _locate;
    private readonly TextBox _query = new() { Text = "minecraft:diamond_ore" }; private readonly ComboBox _scope = new(); private readonly DataGrid _grid = new(); private readonly TextBlock _status = new();
    public RegionBlockSearchWindow(WorldDocument world, MapRegionSelection selection, Action<BedrockRegionBlockHit> locate)
    {
        _world=world; _selection=selection; _locate=locate; Title="区域方块搜索"; Width=1000; Height=650; MinWidth=760; MinHeight=480; WindowStartupLocation=WindowStartupLocation.CenterOwner;
        Content=BuildUi();
    }
    private UIElement BuildUi()
    {
        var root=new Grid{Margin=new Thickness(10)}; root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto}); root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)}); root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        var top=new Grid(); top.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto}); top.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)}); top.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(140)}); top.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});
        top.Children.Add(new TextBlock{Text="方块 name",VerticalAlignment=VerticalAlignment.Center}); Grid.SetColumn(_query,1); _query.Margin=new Thickness(8,0,8,0); top.Children.Add(_query);
        _scope.Items.Add("storage 0"); _scope.Items.Add("storage 1"); _scope.Items.Add("两层"); _scope.SelectedIndex=2; Grid.SetColumn(_scope,2); _scope.Margin=new Thickness(0,0,8,0); top.Children.Add(_scope);
        var search=new Button{Content="搜索",Padding=new Thickness(16,4,16,4),IsDefault=true}; search.Click+=async(_,_)=>await SearchAsync(); Grid.SetColumn(search,3); top.Children.Add(search); root.Children.Add(top);
        _grid.AutoGenerateColumns=false; _grid.IsReadOnly=true; _grid.CanUserAddRows=false; _grid.RowHeaderWidth=0;
        _grid.Columns.Add(new DataGridTextColumn{Header="X",Binding=new Binding(nameof(BedrockRegionBlockHit.X)),Width=90}); _grid.Columns.Add(new DataGridTextColumn{Header="Y",Binding=new Binding(nameof(BedrockRegionBlockHit.Y)),Width=90}); _grid.Columns.Add(new DataGridTextColumn{Header="Z",Binding=new Binding(nameof(BedrockRegionBlockHit.Z)),Width=90}); _grid.Columns.Add(new DataGridTextColumn{Header="storage",Binding=new Binding(nameof(BedrockRegionBlockHit.StorageIndex)),Width=90}); _grid.Columns.Add(new DataGridTextColumn{Header="方块",Binding=new Binding(nameof(BedrockRegionBlockHit.Name)),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});
        _grid.MouseDoubleClick+=(_,e)=>{if(e.ChangedButton==MouseButton.Left&&_grid.SelectedItem is BedrockRegionBlockHit hit){_locate(hit);_status.Text=$"已定位 {hit.CoordinateText} storage {hit.StorageIndex}";}}; Grid.SetRow(_grid,1); _grid.Margin=new Thickness(0,8,0,0); root.Children.Add(_grid);
        _status.Margin=new Thickness(0,8,0,0); _status.Foreground=System.Windows.Media.Brushes.DimGray; Grid.SetRow(_status,2); root.Children.Add(_status); return root;
    }
    private BedrockRegionStorageScope Scope()=>_scope.SelectedIndex switch{0=>BedrockRegionStorageScope.Layer0,1=>BedrockRegionStorageScope.Layer1,_=>BedrockRegionStorageScope.Both};
    private async Task SearchAsync()
    {
        try
        {
            _status.Text = "正在搜索…";
            // Snapshot every Dispatcher-owned control value on the UI thread before
            // entering Task.Run. WPF controls must never be read from a worker thread.
            var query = _query.Text;
            var scope = Scope();
            var selection = _selection;
            var result = await Task.Run(() =>
            {
                using var db = _world.OpenDatabase(true);
                return new BedrockRegionAdvancedStore(db).Search(
                    selection.Dimension, selection.MinimumX, selection.MinimumZ,
                    selection.MaximumX, selection.MaximumZ, query, scope);
            });
            _grid.ItemsSource = result.Hits;
            _status.Text = $"找到 {result.Hits.Count:N0} 项，扫描 {result.ScannedSubChunks:N0} 个 SubChunk"
                + (result.Truncated ? "；达到 10000 项上限" : string.Empty) + "。双击结果可定位。";
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "搜索失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}

public sealed class RegionReplaceWindow : Window
{
    private readonly WorldDocument _world;
    private readonly IReadOnlyList<MapRegionSelection> _selections;
    private MapRegionSelection Selection => _selections[0];
    private readonly Func<Task> _prepare;
    private readonly Action<string> _complete;
    private readonly TextBox _search0Name = new();
    private readonly TextBox _search0States = new() { AcceptsReturn = true, Height = 76, TextWrapping = TextWrapping.Wrap };
    private readonly TextBox _search1Name = new();
    private readonly TextBox _search1States = new() { AcceptsReturn = true, Height = 76, TextWrapping = TextWrapping.Wrap };
    private readonly ComboBox _scope = new();
    private readonly TextBox _replace0Name = new() { Text = "minecraft:diamond_block" };
    private readonly TextBox _replace0States = new() { Text = "NULL" };
    private readonly CheckBox _changeLayer1 = new() { Content = "同时改变 storage 1；留空时把匹配坐标的 storage 1 写为空气" };
    private readonly TextBox _replace1Name = new();
    private readonly TextBox _replace1States = new() { Text = "NULL" };

    public RegionReplaceWindow(WorldDocument world, MapRegionSelection selection, Func<Task> prepare, Action<string> complete)
        : this(world, new[] { selection }, prepare, complete) { }

    public RegionReplaceWindow(WorldDocument world, IReadOnlyList<MapRegionSelection> selections, Func<Task> prepare, Action<string> complete)
    {
        if (selections.Count == 0) throw new ArgumentException("至少需要一个区块/区域。", nameof(selections));
        _world = world; _selections = selections; _prepare = prepare; _complete = complete;
        Title = selections.Count == 1 ? "区域方块搜索替换" : $"所选区块方块搜索替换（{selections.Count}）"; Width = 900; Height = 760; MinWidth = 760; MinHeight = 650;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi();
        _scope.Items.Add("storage 0"); _scope.Items.Add("storage 1"); _scope.Items.Add("storage 0 和 1"); _scope.SelectedIndex = 2;
        _changeLayer1.Checked += (_, _) => UpdateLayer1Enabled();
        _changeLayer1.Unchecked += (_, _) => UpdateLayer1Enabled();
        UpdateLayer1Enabled();
    }

    private UIElement BuildUi()
    {
        var stack = new StackPanel { Margin = new Thickness(18) };
        stack.Children.Add(new TextBlock
        {
            Text = SelectionSummary(),
            FontWeight = FontWeights.SemiBold
        });
        stack.Children.Add(new TextBlock
        {
            Text = "搜索 name 和 states 都是部分匹配。states 搜索每行写“标签名”或“标签名=值”；若 storage 0/1 两列都填写，同一坐标必须同时满足两列条件。",
            TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.DimGray, Margin = new Thickness(0,8,0,8)
        });

        var searchGrid = TwoColumnGroup("搜索条件", "storage 0", _search0Name, _search0States, "storage 1", _search1Name, _search1States);
        stack.Children.Add(searchGrid);
        stack.Children.Add(Labelled("单列条件查找范围", _scope));

        stack.Children.Add(new TextBlock
        {
            Text = "替换内容", FontWeight = FontWeights.SemiBold, FontSize = 15, Margin = new Thickness(0,14,0,6)
        });
        stack.Children.Add(Labelled("storage 0 目标 name", _replace0Name));
        stack.Children.Add(Labelled("storage 0 typed states", _replace0States));
        stack.Children.Add(new TextBlock
        {
            Text = "typed states 使用命令栏相同语法；NULL 表示空 states。匹配后 storage 0 默认清空原 states 再写入新 states。",
            TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.DimGray, Margin = new Thickness(0,2,0,8)
        });
        stack.Children.Add(_changeLayer1);
        stack.Children.Add(Labelled("storage 1 目标 name", _replace1Name));
        stack.Children.Add(Labelled("storage 1 typed states", _replace1States));

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0,14,0,0) };
        var searchOnly = new Button { Content = "仅搜索", Padding = new Thickness(18,6,18,6) };
        searchOnly.Click += async (_, _) => await SearchOnlyAsync();
        buttons.Children.Add(searchOnly);
        var apply = new Button { Content = "执行替换", Padding = new Thickness(18,6,18,6), Margin = new Thickness(8,0,0,0), IsDefault = true };
        apply.Click += async (_, _) => await ApplyAsync();
        buttons.Children.Add(apply);
        buttons.Children.Add(new Button { Content = "取消", Padding = new Thickness(18,6,18,6), Margin = new Thickness(8,0,0,0), IsCancel = true });
        stack.Children.Add(buttons);
        return new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = stack };
    }

    private static UIElement TwoColumnGroup(string title, string leftTitle, TextBox leftName, TextBox leftStates, string rightTitle, TextBox rightName, TextBox rightStates)
    {
        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var left = SearchColumn(title + " · " + leftTitle, leftName, leftStates);
        var right = SearchColumn(title + " · " + rightTitle, rightName, rightStates);
        Grid.SetColumn(left, 0); Grid.SetColumn(right, 2); root.Children.Add(left); root.Children.Add(right);
        return root;
    }

    private static FrameworkElement SearchColumn(string title, TextBox name, TextBox states)
    {
        var p = new StackPanel();
        p.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold });
        p.Children.Add(new TextBlock { Text = "name 包含", Margin = new Thickness(0,5,0,2) }); p.Children.Add(name);
        p.Children.Add(new TextBlock { Text = "states 条件", Margin = new Thickness(0,5,0,2) }); p.Children.Add(states);
        return p;
    }

    private static FrameworkElement Labelled(string label, Control control)
    {
        var grid = new Grid { Margin = new Thickness(0,6,0,0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(190) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0,0,10,0) });
        Grid.SetColumn(control, 1); grid.Children.Add(control); return grid;
    }

    private void UpdateLayer1Enabled()
    {
        var enabled = _changeLayer1.IsChecked == true;
        _replace1Name.IsEnabled = enabled; _replace1States.IsEnabled = enabled;
    }

    private BedrockRegionStorageScope Scope() => _scope.SelectedIndex switch
    {
        0 => BedrockRegionStorageScope.Layer0,
        1 => BedrockRegionStorageScope.Layer1,
        _ => BedrockRegionStorageScope.Both
    };

    private static BedrockRegionBlockSearchCriteria? Criteria(string name, string statesText)
    {
        var criteria = new List<BedrockRegionBlockStateCriterion>();
        foreach (var raw in statesText.Replace("\r", string.Empty).Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var split = raw.IndexOf('=');
            criteria.Add(split < 0
                ? new BedrockRegionBlockStateCriterion(raw, null)
                : new BedrockRegionBlockStateCriterion(raw[..split].Trim(), raw[(split + 1)..].Trim()));
        }
        var cleanName = string.IsNullOrWhiteSpace(name) ? null : name.Trim();
        return cleanName is null && criteria.Count == 0 ? null : new BedrockRegionBlockSearchCriteria(cleanName, criteria);
    }

    private static BedrockRegionBlockReplacement Replacement(string name, string statesText)
    {
        var cleanName = string.IsNullOrWhiteSpace(name) ? null : name.Trim();
        var states = BlockCommandParser.ParseStates(string.IsNullOrWhiteSpace(statesText) ? "NULL" : statesText.Trim());
        return new BedrockRegionBlockReplacement(cleanName, states, ReplaceAllStates: true);
    }

    private string SelectionSummary()
    {
        if (_selections.Count == 1)
        {
            var s = Selection;
            return $"{BedrockDimensionNames.DisplayName(s.Dimension)} · X={s.MinimumX}…{s.MaximumX}, Z={s.MinimumZ}…{s.MaximumZ}";
        }
        var dimensions = _selections.Select(item => item.Dimension).Distinct().Count();
        return $"精确处理 {_selections.Count:N0} 个所选区块 · {dimensions:N0} 个维度（不会处理未选择的中间区块）";
    }

    private (BedrockRegionBlockSearchCriteria? Search0, BedrockRegionBlockSearchCriteria? Search1, BedrockRegionStorageScope Scope) SearchInputs()
    {
        var search0 = Criteria(_search0Name.Text, _search0States.Text);
        var search1 = Criteria(_search1Name.Text, _search1States.Text);
        if (search0 is null && search1 is null) throw new InvalidDataException("至少填写 storage 0 或 storage 1 的搜索条件。");
        var scope = search0 is not null && search1 is not null ? BedrockRegionStorageScope.Both : Scope();
        return (search0, search1, scope);
    }

    private async Task SearchOnlyAsync()
    {
        try
        {
            var inputs = SearchInputs();
            var operation = new BedrockRegionCoordinatedOperation(inputs.Search0, inputs.Search1, inputs.Scope,
                new BedrockRegionBlockReplacement(null, [], ReplaceAllStates: false), false, null);
            var result = await Task.Run(() =>
            {
                using var db = _world.OpenDatabase(true);
                var store = new BedrockRegionAdvancedStore(db);
                var hits = new List<BedrockRegionBlockHit>();
                var scanned = 0;
                var truncated = false;
                foreach (var selection in _selections)
                {
                    var remaining = 10000 - hits.Count;
                    if (remaining <= 0) { truncated = true; break; }
                    var item = store.SearchCoordinated(selection.Dimension, selection.MinimumX, selection.MinimumZ,
                        selection.MaximumX, selection.MaximumZ, operation, remaining);
                    hits.AddRange(item.Hits);
                    scanned += item.ScannedSubChunks;
                    if (item.Truncated) { truncated = true; break; }
                }
                return new BedrockRegionSearchResult(hits, scanned, truncated);
            });
            var window = new RegionCoordinatedSearchResultsWindow(result) { Owner = this };
            window.ShowDialog();
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "搜索失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private async Task ApplyAsync()
    {
        try
        {
            var inputs = SearchInputs();
            var search0 = inputs.Search0;
            var search1 = inputs.Search1;
            var scope = inputs.Scope;
            var replacement0 = Replacement(_replace0Name.Text, _replace0States.Text);
            BedrockRegionBlockReplacement? replacement1 = null;
            if (_changeLayer1.IsChecked == true && (!string.IsNullOrWhiteSpace(_replace1Name.Text) || !string.Equals(_replace1States.Text.Trim(), "NULL", StringComparison.OrdinalIgnoreCase)))
                replacement1 = Replacement(_replace1Name.Text, _replace1States.Text);
            var operation = new BedrockRegionCoordinatedOperation(search0, search1, scope, replacement0, _changeLayer1.IsChecked == true, replacement1);
            await _prepare();
            var result = await Task.Run(() =>
            {
                using var db = _world.OpenDatabase(false);
                var store = new BedrockRegionAdvancedStore(db);
                var matched = 0; var written = 0; var skippedSubChunks = 0; var skippedSelections = 0;
                foreach (var selection in _selections)
                {
                    try
                    {
                        var item = store.ReplaceCoordinated(selection.Dimension, selection.MinimumX, selection.MinimumZ, selection.MaximumX, selection.MaximumZ, operation);
                        matched += item.MatchedPositions; written += item.WrittenSubChunks; skippedSubChunks += item.SkippedSubChunks;
                    }
                    catch (InvalidOperationException) { skippedSelections++; }
                    catch (NotSupportedException) { skippedSelections++; }
                }
                if (written == 0) throw new InvalidOperationException("所选区块中没有可替换的匹配方块。");
                return (Matched: matched, Written: written, SkippedSubChunks: skippedSubChunks, SkippedSelections: skippedSelections);
            });
            var extra = result.SkippedSelections > 0 ? $"；另有 {result.SkippedSelections:N0} 个所选区块无匹配/不支持" : string.Empty;
            var msg = $"已替换 {result.Matched:N0} 个坐标，写回 {result.Written:N0} 个 SubChunk；跳过 {result.SkippedSubChunks:N0} 个不支持的 SubChunk{extra}。";
            _complete(msg); MessageBox.Show(this, msg, "搜索替换完成", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "搜索替换失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
}

public sealed class RegionCoordinatedSearchResultsWindow : Window
{
    public RegionCoordinatedSearchResultsWindow(BedrockRegionSearchResult result)
    {
        Title = "方块搜索结果"; Width = 900; Height = 620; MinWidth = 680; MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new Grid { Margin = new Thickness(10) };
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var grid = new DataGrid { AutoGenerateColumns = false, IsReadOnly = true, CanUserAddRows = false, RowHeaderWidth = 0, ItemsSource = result.Hits };
        grid.Columns.Add(new DataGridTextColumn { Header = "维度", Binding = new Binding(nameof(BedrockRegionBlockHit.Dimension)), Width = 80 });
        grid.Columns.Add(new DataGridTextColumn { Header = "X", Binding = new Binding(nameof(BedrockRegionBlockHit.X)), Width = 90 });
        grid.Columns.Add(new DataGridTextColumn { Header = "Y", Binding = new Binding(nameof(BedrockRegionBlockHit.Y)), Width = 90 });
        grid.Columns.Add(new DataGridTextColumn { Header = "Z", Binding = new Binding(nameof(BedrockRegionBlockHit.Z)), Width = 90 });
        grid.Columns.Add(new DataGridTextColumn { Header = "storage", Binding = new Binding(nameof(BedrockRegionBlockHit.StorageIndex)), Width = 90 });
        grid.Columns.Add(new DataGridTextColumn { Header = "方块", Binding = new Binding(nameof(BedrockRegionBlockHit.Name)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        root.Children.Add(grid);
        var status = new TextBlock
        {
            Text = $"找到 {result.Hits.Count:N0} 项，扫描 {result.ScannedSubChunks:N0} 个 SubChunk" + (result.Truncated ? "；达到 10000 项上限。" : "。"),
            Foreground = System.Windows.Media.Brushes.DimGray, Margin = new Thickness(0,8,0,0)
        };
        Grid.SetRow(status, 1); root.Children.Add(status); Content = root;
    }
}

public sealed class RegionLayerReplaceWindow : Window
{
    private readonly WorldDocument _world;
    private readonly IReadOnlyList<MapRegionSelection> _selections;
    private MapRegionSelection Selection => _selections[0];
    private readonly Func<Task> _prepare;
    private readonly Action<string> _complete;
    private readonly ComboBox _layer = new();
    private readonly TextBox _name = new() { Text = "minecraft:air" };
    private readonly TextBox _states = new() { Text = "NULL" };
    private readonly CheckBox _includeAir = new() { Content = "选择 storage 0 与 1 都为空气的位置" };

    public RegionLayerReplaceWindow(WorldDocument world, MapRegionSelection selection, Func<Task> prepare, Action<string> complete)
        : this(world, new[] { selection }, prepare, complete) { }

    public RegionLayerReplaceWindow(WorldDocument world, IReadOnlyList<MapRegionSelection> selections, Func<Task> prepare, Action<string> complete)
    {
        if (selections.Count == 0) throw new ArgumentException("至少需要一个区块/区域。", nameof(selections));
        _world = world; _selections = selections; _prepare = prepare; _complete = complete;
        Title = selections.Count == 1 ? "区域批量层 0 / 层 1 替换" : $"所选区块层 0 / 层 1 替换（{selections.Count}）"; Width = 650; Height = 390;
        WindowStartupLocation = WindowStartupLocation.CenterOwner; ResizeMode = ResizeMode.NoResize; Content = BuildUi();
    }

    private UIElement BuildUi()
    {
        var p = new StackPanel { Margin = new Thickness(18) };
        p.Children.Add(new TextBlock { Text = SelectionSummary(), FontWeight = FontWeights.SemiBold });
        _layer.Items.Add("storage 0"); _layer.Items.Add("storage 1"); _layer.SelectedIndex = 1;
        p.Children.Add(new TextBlock { Text = "批量替换层", Margin = new Thickness(0,12,0,4) }); p.Children.Add(_layer);
        p.Children.Add(new TextBlock { Text = "目标方块 name", Margin = new Thickness(0,10,0,4) }); p.Children.Add(_name);
        p.Children.Add(new TextBlock { Text = "typed states", Margin = new Thickness(0,10,0,4) }); p.Children.Add(_states);
        _includeAir.Margin = new Thickness(0,12,0,4); p.Children.Add(_includeAir);
        p.Children.Add(new TextBlock
        {
            Text = "默认只处理框选范围内 storage 0 或 1 至少一层非空气的位置；开启后现有 SubChunk 的全部高度位置都会参与。缺失的目标层会自动创建，框外方块保持不变。",
            Margin = new Thickness(0,6,0,12), TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.DimGray
        });
        var b = new Button { Content = "执行批量替换", HorizontalAlignment = HorizontalAlignment.Right, Padding = new Thickness(16,6,16,6) };
        b.Click += async (_, _) => await ApplyAsync(); p.Children.Add(b); return p;
    }

    private string SelectionSummary()
    {
        if (_selections.Count == 1)
        {
            var s = Selection;
            return $"范围：X={s.MinimumX}…{s.MaximumX}, Z={s.MinimumZ}…{s.MaximumZ}";
        }
        var dimensions = _selections.Select(item => item.Dimension).Distinct().Count();
        return $"精确处理 {_selections.Count:N0} 个所选区块 · {dimensions:N0} 个维度（不会处理未选择的中间区块）";
    }

    private async Task ApplyAsync()
    {
        try
        {
            var assignments = BlockCommandParser.ParseStates(string.IsNullOrWhiteSpace(_states.Text) ? "NULL" : _states.Text.Trim());
            // Snapshot Dispatcher-owned control values before Task.Run.
            var layer = _layer.SelectedIndex;
            var name = _name.Text;
            var includeAir = _includeAir.IsChecked == true;
            var selections = _selections;
            await _prepare();
            var result = await Task.Run(() =>
            {
                using var db = _world.OpenDatabase(false);
                var store = new BedrockRegionAdvancedStore(db);
                var matched = 0; var written = 0; var skippedSubChunks = 0; var skippedSelections = 0;
                foreach (var selection in selections)
                {
                    try
                    {
                        var item = store.ReplaceWholeStorage(selection.Dimension, selection.MinimumX, selection.MinimumZ, selection.MaximumX, selection.MaximumZ, layer, name, includeAir, assignments);
                        matched += item.MatchedPositions; written += item.WrittenSubChunks; skippedSubChunks += item.SkippedSubChunks;
                    }
                    catch (InvalidOperationException) { skippedSelections++; }
                    catch (NotSupportedException) { skippedSelections++; }
                }
                if (written == 0) throw new InvalidOperationException("所选区块中没有可执行批量层替换的方块。");
                return (Matched: matched, Written: written, SkippedSubChunks: skippedSubChunks, SkippedSelections: skippedSelections);
            });
            var extra = result.SkippedSelections > 0 ? $"；另有 {result.SkippedSelections:N0} 个所选区块无可写内容/不支持" : string.Empty;
            var msg = $"已在所选区块替换层 {layer} 的 {result.Matched:N0} 个方块位置，写回 {result.Written:N0} 个 SubChunk；跳过 {result.SkippedSubChunks:N0} 个不支持的 SubChunk{extra}。";
            _complete(msg); MessageBox.Show(this, msg, "批量替换完成", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "批量替换失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
}

public sealed class RegionBiomeWindow : Window
{
    private readonly WorldDocument _world;private readonly MapRegionSelection _selection;private readonly Func<Task> _prepare;private readonly Action<string> _complete;private readonly TextBox _id=new(){Text="1"};private readonly TextBlock _detail=new();
    public RegionBiomeWindow(WorldDocument world,MapRegionSelection selection,Func<Task> prepare,Action<string> complete){_world=world;_selection=selection;_prepare=prepare;_complete=complete;Title="区域生物群系";Width=560;Height=260;WindowStartupLocation=WindowStartupLocation.CenterOwner;ResizeMode=ResizeMode.NoResize;Content=BuildUi();_id.TextChanged+=(_,_)=>UpdateDetail();UpdateDetail();}
    private UIElement BuildUi(){var p=new StackPanel{Margin=new Thickness(16)};p.Children.Add(new TextBlock{Text=$"{BedrockDimensionNames.DisplayName(_selection.Dimension)} · X={_selection.MinimumX}…{_selection.MaximumX}, Z={_selection.MinimumZ}…{_selection.MaximumZ}",FontWeight=FontWeights.SemiBold});p.Children.Add(new TextBlock{Text="生物群系原始 ID",Margin=new Thickness(0,12,0,4)});p.Children.Add(_id);_detail.Margin=new Thickness(0,8,0,8);_detail.Foreground=System.Windows.Media.Brushes.DimGray;p.Children.Add(_detail);var b=new Button{Content="应用",Padding=new Thickness(18,5,18,5),HorizontalAlignment=HorizontalAlignment.Right};b.Click+=async(_,_)=>await ApplyAsync();p.Children.Add(b);return p;}
    private void UpdateDetail(){_detail.Text=uint.TryParse(_id.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var id)?BedrockBiomeCatalog.DetailText(id):"请输入 UInt32 生物群系 ID";}
    private async Task ApplyAsync(){if(!uint.TryParse(_id.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var id)){MessageBox.Show(this,"请输入 0…4294967295 的生物群系 ID。","输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return;}try{await _prepare();var result=await Task.Run(()=>{using var db=_world.OpenDatabase(false);return new BedrockRegionAdvancedStore(db).SetBiome(_selection.Dimension,_selection.MinimumX,_selection.MinimumZ,_selection.MaximumX,_selection.MaximumZ,id);});var msg=$"修改 {result.ChangedChunks:N0} 个区块、{result.ChangedCells:N0} 个生物群系位置；跳过 {result.SkippedChunks:N0} 个无记录区块。";_complete(msg);MessageBox.Show(this,msg,"完成",MessageBoxButton.OK,MessageBoxImage.Information);}catch(Exception ex){MessageBox.Show(this,ex.Message,"修改生物群系失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
}

public sealed class HardcodedSpawnersEditorWindow : Window
{
    private readonly WorldDocument _world; private readonly ChunkPosition _position; private readonly Func<Task> _prepare; private readonly Action<string>? _complete; private readonly ListBox _list=new(); private List<HardcodedSpawnerArea> _areas=[];
    public HardcodedSpawnersEditorWindow(WorldDocument world,ChunkPosition position,Func<Task> prepare,Action<string>? complete=null){_world=world;_position=position;_prepare=prepare;_complete=complete;Title=$"HardcodedSpawners · 区块 ({position.X}, {position.Z})";Width=760;Height=520;WindowStartupLocation=WindowStartupLocation.CenterOwner;Content=BuildUi();Loaded+=async(_,_)=>await ReloadAsync();}
    private UIElement BuildUi(){var root=new Grid{Margin=new Thickness(10)};root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.Children.Add(new TextBlock{Text=$"{_position.DimensionName} · 保存空列表会删除 0x39 HardcodedSpawners 记录。",Margin=new Thickness(0,0,0,8)});Grid.SetRow(_list,1);root.Children.Add(_list);var p=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,8,0,0)};var add=B("新增",(_,_)=>EditArea(null));var edit=B("编辑",(_,_)=>{if(_list.SelectedIndex>=0)EditArea(_list.SelectedIndex);});var del=B("删除",(_,_)=>{if(_list.SelectedIndex>=0){_areas.RemoveAt(_list.SelectedIndex);Refresh();}});var save=B("应用",async(_,_)=>await SaveAsync());edit.Margin=del.Margin=save.Margin=new Thickness(6,0,0,0);p.Children.Add(add);p.Children.Add(edit);p.Children.Add(del);p.Children.Add(save);Grid.SetRow(p,2);root.Children.Add(p);return root;}
    private static Button B(string text,RoutedEventHandler h){var b=new Button{Content=text,Padding=new Thickness(12,4,12,4)};b.Click+=h;return b;}
    private async Task ReloadAsync(){try{var rec=await Task.Run(()=>{using var db=_world.OpenDatabase(true);return new HardcodedSpawnersStore(db).Read(_position);});_areas=rec.Document.Areas.ToList();Refresh();}catch(Exception ex){MessageBox.Show(this,ex.Message,"读取失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
    private void Refresh(){_list.ItemsSource=null;_list.ItemsSource=_areas.Select((a,i)=>$"{i+1}. {a.KindText} · {a.RangeText}").ToArray();}
    private void EditArea(int? index){var current=index.HasValue?_areas[index.Value]:new HardcodedSpawnerArea(_position.X*16,0,_position.Z*16,_position.X*16+15,255,_position.Z*16+15,1);var w=new SpawnerAreaEditWindow(current){Owner=this};if(w.ShowDialog()!=true)return;if(index.HasValue)_areas[index.Value]=w.Area;else _areas.Add(w.Area);Refresh();}
    private async Task SaveAsync(){try{var areas=_areas.ToArray();await _prepare();await Task.Run(()=>{using var db=_world.OpenDatabase(false);var store=new HardcodedSpawnersStore(db);var old=store.Read(_position);store.Save(old with{Document=new HardcodedSpawnersDocument(areas)});});var msg=areas.Length==0?"已删除 HardcodedSpawners 记录。":$"已应用 {areas.Length} 个 HardcodedSpawners 区域到工作副本。";_complete?.Invoke(msg);MessageBox.Show(this,msg,"已应用",MessageBoxButton.OK,MessageBoxImage.Information);}catch(Exception ex){MessageBox.Show(this,ex.Message,"应用失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
}

public sealed class RegionHardcodedSpawnersWindow : Window
{
    private readonly WorldDocument _world;private readonly MapRegionSelection _selection;private readonly Func<Task> _prepare;private readonly Action<string> _complete;private readonly DataGrid _grid=new();private IReadOnlyList<HardcodedSpawnersRecord> _records=[];
    public RegionHardcodedSpawnersWindow(WorldDocument world,MapRegionSelection selection,Func<Task> prepare,Action<string> complete){_world=world;_selection=selection;_prepare=prepare;_complete=complete;Title="区域 HardcodedSpawners";Width=760;Height=570;WindowStartupLocation=WindowStartupLocation.CenterOwner;Content=BuildUi();Loaded+=async(_,_)=>await ReloadAsync();}
    private UIElement BuildUi(){var root=new Grid{Margin=new Thickness(10)};root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.Children.Add(new TextBlock{Text="双击区块进入 HardcodedSpawners 编辑页；没有记录的区块也可以创建。",Margin=new Thickness(0,0,0,8)});_grid.AutoGenerateColumns=false;_grid.IsReadOnly=true;_grid.CanUserAddRows=false;_grid.RowHeaderWidth=0;_grid.Columns.Add(new DataGridTextColumn{Header="区块",Binding=new Binding("Position.CoordinateText"),Width=180});_grid.Columns.Add(new DataGridTextColumn{Header="维度",Binding=new Binding("Position.DimensionName"),Width=120});_grid.Columns.Add(new DataGridTextColumn{Header="区域数",Binding=new Binding("Document.Areas.Count"),Width=100});_grid.MouseDoubleClick+=(_,e)=>{if(e.ChangedButton==MouseButton.Left&&_grid.SelectedItem is HardcodedSpawnersRecord r){var w=new HardcodedSpawnersEditorWindow(_world,r.Position,_prepare,msg=>{_complete(msg);_ = ReloadAsync();}){Owner=this};w.ShowDialog();}};Grid.SetRow(_grid,1);root.Children.Add(_grid);var refresh=new Button{Content="刷新",Padding=new Thickness(12,4,12,4),HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,8,0,0)};refresh.Click+=async(_,_)=>await ReloadAsync();Grid.SetRow(refresh,2);root.Children.Add(refresh);return root;}
    private async Task ReloadAsync(){var minCX=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MinimumX,16);var maxCX=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MaximumX,16);var minCZ=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MinimumZ,16);var maxCZ=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MaximumZ,16);_records=await Task.Run(()=>{using var db=_world.OpenDatabase(true);return new HardcodedSpawnersStore(db).RecordsInChunkRectangle(_selection.Dimension,minCX,minCZ,maxCX,maxCZ,true);});_grid.ItemsSource=_records;}
}

public sealed class SpawnerAreaEditWindow : Window
{
    private readonly TextBox[] _c=Enumerable.Range(0,6).Select(_=>new TextBox()).ToArray();private readonly TextBox _kind=new();public HardcodedSpawnerArea Area{get;private set;}
    public SpawnerAreaEditWindow(HardcodedSpawnerArea area){Area=area;Title="编辑刷怪区域";Width=520;Height=430;WindowStartupLocation=WindowStartupLocation.CenterOwner;ResizeMode=ResizeMode.NoResize;Content=BuildUi();var vals=new[]{area.MinimumX,area.MinimumY,area.MinimumZ,area.MaximumX,area.MaximumY,area.MaximumZ};for(var i=0;i<6;i++)_c[i].Text=vals[i].ToString(CultureInfo.InvariantCulture);_kind.Text=area.Kind.ToString(CultureInfo.InvariantCulture);}
    private UIElement BuildUi(){var g=new Grid{Margin=new Thickness(16)};g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(150)});g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});for(var i=0;i<9;i++)g.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});var labels=new[]{"最小 X","最小 Y","最小 Z","最大 X","最大 Y","最大 Z"};for(var i=0;i<6;i++)Add(g,i,labels[i],_c[i]);Add(g,6,"类型 byte",_kind);var hint=new TextBlock{Text="1=下界要塞，2=沼泽小屋，3=海底神殿，5=掠夺者前哨站；其它 UInt8 值会原样保留。",TextWrapping=TextWrapping.Wrap,Foreground=System.Windows.Media.Brushes.DimGray,Margin=new Thickness(0,8,0,10)};Grid.SetRow(hint,7);Grid.SetColumnSpan(hint,2);g.Children.Add(hint);var p=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};var ok=new Button{Content="确定",Padding=new Thickness(18,5,18,5),IsDefault=true};ok.Click+=Ok;p.Children.Add(ok);p.Children.Add(new Button{Content="取消",Padding=new Thickness(18,5,18,5),Margin=new Thickness(8,0,0,0),IsCancel=true});Grid.SetRow(p,8);Grid.SetColumnSpan(p,2);g.Children.Add(p);return g;}
    private static void Add(Grid g,int r,string l,UIElement c){var t=new TextBlock{Text=l,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,6,12,6)};Grid.SetRow(t,r);g.Children.Add(t);if(c is FrameworkElement f)f.Margin=new Thickness(0,6,0,6);Grid.SetRow(c,r);Grid.SetColumn(c,1);g.Children.Add(c);}
    private void Ok(object s,RoutedEventArgs e){var v=new int[6];for(var i=0;i<6;i++)if(!int.TryParse(_c[i].Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out v[i])){MessageBox.Show(this,"坐标必须为 Int32。","输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return;}if(!byte.TryParse(_kind.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var kind)){MessageBox.Show(this,"类型必须为 0…255。","输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return;}try{Area=new HardcodedSpawnerArea(v[0],v[1],v[2],v[3],v[4],v[5],kind).Validate();DialogResult=true;}catch(Exception ex){MessageBox.Show(this,ex.Message,"输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);}}
}

public sealed class VillageFeatureNbtWindow : Window
{
    private readonly WorldDocument _world;
    private readonly string _identifier;
    private readonly Func<Task> _prepare;
    private readonly DataGrid _grid = new();
    private readonly TextBlock _status = new();
    private IReadOnlyList<VillageNbtRecord> _records = [];

    public VillageFeatureNbtWindow(WorldDocument world, string identifier, Func<Task> prepare)
    {
        _world = world; _identifier = identifier; _prepare = prepare;
        Title = "村庄 NBT · " + identifier; Width = 960; Height = 620; MinWidth = 720; MinHeight = 460;
        WindowStartupLocation = WindowStartupLocation.CenterOwner; Content = BuildUi();
        Loaded += async (_, _) => await ReloadAsync();
    }

    private UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(10) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var top = new DockPanel { Margin = new Thickness(0,0,0,8) };
        var residentButtons = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var item in new[]
        {
            ("村民…", VillageResidentEntityKind.Villager),
            ("猫…", VillageResidentEntityKind.Cat),
            ("铁傀儡…", VillageResidentEntityKind.IronGolem)
        })
        {
            var button = new Button { Content = item.Item1, Padding = new Thickness(10,3,10,3), Margin = new Thickness(6,0,0,0) };
            var kind = item.Item2;
            button.Click += (_, _) => new VillageResidentEntitiesWindow(_world, _identifier, kind, _prepare) { Owner = this }.ShowDialog();
            residentButtons.Children.Add(button);
        }
        DockPanel.SetDock(residentButtons, Dock.Right); top.Children.Add(residentButtons);
        top.Children.Add(new TextBlock { Text = "仅显示当前地图村庄关联的 INFO / POI / DWELLERS / PLAYERS（或旧版 mVillages 子记录）；双击编辑。居民快捷入口按 Dwellers UniqueID 匹配全世界实体。", TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center });
        root.Children.Add(top);
        _grid.AutoGenerateColumns = false; _grid.IsReadOnly = true; _grid.CanUserAddRows = false; _grid.RowHeaderWidth = 0;
        _grid.Columns.Add(new DataGridTextColumn { Header = "类型", Binding = new Binding(nameof(VillageNbtRecord.DisplayName)), Width = 170 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "详情", Binding = new Binding(nameof(VillageNbtRecord.DetailText)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        _grid.Columns.Add(new DataGridTextColumn { Header = "Key", Binding = new Binding(nameof(VillageNbtRecord.KeyText)), Width = 280 });
        _grid.MouseDoubleClick += async (_, e) =>
        {
            if (e.ChangedButton == MouseButton.Left && _grid.SelectedItem is VillageNbtRecord record) await EditAsync(record);
        };
        Grid.SetRow(_grid, 1); root.Children.Add(_grid);
        _status.Margin = new Thickness(0,8,0,0); _status.Foreground = System.Windows.Media.Brushes.DimGray; Grid.SetRow(_status,2); root.Children.Add(_status);
        return root;
    }

    private async Task ReloadAsync()
    {
        try
        {
            _records = await Task.Run(() =>
            {
                using var db = _world.OpenDatabase(true);
                return new VillageNbtStore(db).ScanRecords().Records
                    .Where(record => record.VillageIdentifier.Equals(_identifier, StringComparison.OrdinalIgnoreCase))
                    .ToArray();
            });
            _grid.ItemsSource = _records;
            _status.Text = $"当前村庄 {_records.Count} 条 NBT 记录。";
        }
        catch (Exception ex) { _status.Text = "读取失败：" + ex.Message; }
    }

    private async Task EditAsync(VillageNbtRecord record)
    {
        var editor = new NbtEditorWindow(record.VillageDisplayName + " · " + record.DisplayName, record.Document, async edited =>
        {
            await _prepare();
            await Task.Run(() =>
            {
                using var db = _world.OpenDatabase(false);
                new VillageNbtStore(db).Save(record, edited);
            });
        }, fileEncoding: record.Encoding) { Owner = this };
        editor.ShowDialog();
        if (editor.DidSave) await ReloadAsync();
    }
}

public sealed class RegionCopyWindow : Window
{
    private readonly WorldDocument _world;
    private readonly MapRegionSelection _source;
    private readonly Func<Task> _prepare;
    private readonly Action<string> _complete;
    private readonly ComboBox _dimension = new();
    private readonly TextBox _x = new();
    private readonly TextBox _z = new();
    private readonly TextBlock _status = new();

    public RegionCopyWindow(WorldDocument world, MapRegionSelection source, Func<Task> prepare, Action<string> complete)
    {
        _world = world;
        _source = source;
        _prepare = prepare;
        _complete = complete;
        Title = "复制区域";
        Width = 600;
        Height = 430;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        Content = BuildUi();
    }

    private UIElement BuildUi()
    {
        var root = RegionFillWindow.CreateRoot(8);
        _dimension.Items.Add(new ComboBoxItem { Content = "主世界", Tag = 0 });
        _dimension.Items.Add(new ComboBoxItem { Content = "下界", Tag = 1 });
        _dimension.Items.Add(new ComboBoxItem { Content = "末地", Tag = 2 });
        _dimension.SelectedIndex = _source.Dimension is >= 0 and <= 2 ? _source.Dimension : 0;
        _x.Text = _source.MinimumX.ToString(CultureInfo.InvariantCulture);
        _z.Text = _source.MinimumZ.ToString(CultureInfo.InvariantCulture);

        var summary = new TextBlock
        {
            Text = $"源区域：X={_source.MinimumX}…{_source.MaximumX}, Z={_source.MinimumZ}…{_source.MaximumZ}\n大小：{(long)_source.MaximumX - _source.MinimumX + 1:N0} × {(long)_source.MaximumZ - _source.MinimumZ + 1:N0} 方块",
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 10)
        };
        Grid.SetRow(summary, 0); Grid.SetColumnSpan(summary, 2); root.Children.Add(summary);
        RegionFillWindow.AddRow(root, 1, "目标维度", _dimension);
        RegionFillWindow.AddRow(root, 2, "目标 X0", _x);
        RegionFillWindow.AddRow(root, 3, "目标 Z0", _z);

        var note = new TextBlock
        {
            Text = "X1、Z1 会按源区域大小自动计算。复制层 0/层 1 的全部已保存垂直方块状态，并复制生物群系与方块实体；不会复制普通实体、刻计划或 HardcodedSpawners。目标区域已有内容会被覆盖。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.DimGray,
            Margin = new Thickness(0, 10, 0, 10)
        };
        Grid.SetRow(note, 4); Grid.SetColumnSpan(note, 2); root.Children.Add(note);
        _status.Foreground = System.Windows.Media.Brushes.DimGray;
        _status.TextWrapping = TextWrapping.Wrap;
        Grid.SetRow(_status, 5); Grid.SetColumnSpan(_status, 2); root.Children.Add(_status);
        RegionFillWindow.AddButtons(root, 7, "复制", Copy_Click);
        return root;
    }

    private async void Copy_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(_x.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var targetX)
            || !int.TryParse(_z.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var targetZ))
        {
            MessageBox.Show(this, "请输入有效的目标 X0、Z0。", "坐标错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var targetDimension = _dimension.SelectedItem is ComboBoxItem item && item.Tag is int value ? value : 0;
        var width = (long)_source.MaximumX - _source.MinimumX + 1;
        var depth = (long)_source.MaximumZ - _source.MinimumZ + 1;
        var maxX = (long)targetX + width - 1;
        var maxZ = (long)targetZ + depth - 1;
        if (maxX is < int.MinValue or > int.MaxValue || maxZ is < int.MinValue or > int.MaxValue)
        {
            MessageBox.Show(this, "目标区域坐标超出 Int32 范围。", "坐标错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (targetDimension == _source.Dimension && targetX == _source.MinimumX && targetZ == _source.MinimumZ)
        {
            MessageBox.Show(this, "源区域与目标区域不能完全相同。", "复制区域", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (MessageBox.Show(this,
                $"目标区域：X={targetX}…{maxX}, Z={targetZ}…{maxZ}。\n\n目标区域已有内容会被覆盖；操作不会自动备份。继续复制？",
                "覆盖目标区域？", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
            return;

        try
        {
            IsEnabled = false;
            _status.Text = "正在复制区域…";
            await _prepare();
            var source = _source;
            var result = await Task.Run(() =>
            {
                using var database = _world.OpenDatabase(false);
                return new BedrockRegionAdvancedStore(database).CopyRegion(
                    source.Dimension, source.MinimumX, source.MinimumZ, source.MaximumX, source.MaximumZ,
                    targetDimension, targetX, targetZ);
            });

            var message = result.UsedWholeChunkCopy
                ? $"区域已按完整区块复制，共写入 {result.CopiedRecords:N0} 条地形、生物群系、方块实体和区块状态记录。"
                : $"已复制 {result.CopiedBlockStates:N0} 个方块层状态，写回 {result.WrittenSubChunks:N0} 个 SubChunk。";
            if (!result.UsedWholeChunkCopy && result.CopiedBiomeCells > 0) message += $" 同时复制 {result.CopiedBiomeCells:N0} 个生物群系位置。";
            if (!result.UsedWholeChunkCopy && result.CopiedBlockEntities > 0) message += $" 同时复制 {result.CopiedBlockEntities:N0} 个方块实体。";
            if (result.SkippedIncompatibleStates > 0) message += $" 跳过 {result.SkippedIncompatibleStates:N0} 个不兼容旧版数字 ID 状态。";
            _status.Text = message;
            _complete(message);
            MessageBox.Show(this, message, "复制完成", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            _status.Text = "复制失败：" + ex.Message;
            MessageBox.Show(this, ex.Message, "复制区域失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsEnabled = true;
        }
    }
}

public sealed class RegionOperationsWindow : Window
{
    private readonly WorldDocument _world; private MapRegionSelection _selection; private readonly Func<Task> _prepare; private readonly Action<string> _complete; private readonly Action<BedrockRegionBlockHit> _locate; private readonly Action<ChunkPosition> _locateChunk; private readonly Action<MapRegionSelection> _selectionChanged; private readonly TextBlock _summary=new();
    public RegionOperationsWindow(WorldDocument world,MapRegionSelection selection,Func<Task> prepare,Action<string> complete,Action<BedrockRegionBlockHit> locate,Action<ChunkPosition> locateChunk,Action<MapRegionSelection> selectionChanged){_world=world;_selection=selection;_prepare=prepare;_complete=complete;_locate=locate;_locateChunk=locateChunk;_selectionChanged=selectionChanged;Title="框选区域高级操作";Width=650;Height=760;WindowStartupLocation=WindowStartupLocation.CenterOwner;ResizeMode=ResizeMode.NoResize;Content=BuildUi();UpdateSummary();}
    private UIElement BuildUi(){var scroll=new ScrollViewer{VerticalScrollBarVisibility=ScrollBarVisibility.Auto};var p=new StackPanel{Margin=new Thickness(18)};scroll.Content=p;_summary.FontWeight=FontWeights.SemiBold;_summary.TextWrapping=TextWrapping.Wrap;p.Children.Add(_summary);p.Children.Add(B("编辑框选坐标…",(_,_)=>EditSelection()));p.Children.Add(B("常加载区域编辑…",(_,_)=>OpenTickingAreas()));p.Children.Add(B("查看区域内实体/方块实体…",(_,_)=>new RegionEntitiesWindow(_world,_selection,_prepare){Owner=this}.ShowDialog()));p.Children.Add(B("复制区域内容到等大区域…",(_,_)=>new RegionCopyWindow(_world,_selection,_prepare,_complete){Owner=this}.ShowDialog()));p.Children.Add(B("方块搜索 / 结果导航…",(_,_)=>new RegionBlockSearchWindow(_world,_selection,_locate){Owner=this}.ShowDialog()));p.Children.Add(B("区域内方块搜索替换…",(_,_)=>new RegionReplaceWindow(_world,_selection,_prepare,_complete){Owner=this}.ShowDialog()));p.Children.Add(B("批量 layer/storage 替换…",(_,_)=>new RegionLayerReplaceWindow(_world,_selection,_prepare,_complete){Owner=this}.ShowDialog()));p.Children.Add(B("区域生物群系修改…",(_,_)=>new RegionBiomeWindow(_world,_selection,_prepare,_complete){Owner=this}.ShowDialog()));p.Children.Add(B("区域 HardcodedSpawners…",(_,_)=>new RegionHardcodedSpawnersWindow(_world,_selection,_prepare,_complete){Owner=this}.ShowDialog()));p.Children.Add(B("清空区域…",async(_,_)=>await MutateRegionAsync(false)));p.Children.Add(B("重新生成区域…",async(_,_)=>await MutateRegionAsync(true)));p.Children.Add(new TextBlock{Text="区域实体仅按 X/Z 边界过滤；区域复制覆盖全部已保存垂直方块状态、生物群系和方块实体。清空/重新生成按 iOS 行为向外扩展到完整区块。",TextWrapping=TextWrapping.Wrap,Foreground=System.Windows.Media.Brushes.DimGray,Margin=new Thickness(0,14,0,0)});return scroll;}
    private static Button B(string text,RoutedEventHandler h){var b=new Button{Content=text,HorizontalContentAlignment=HorizontalAlignment.Left,Padding=new Thickness(14,8,14,8),Margin=new Thickness(0,8,0,0)};b.Click+=h;return b;}
    private void UpdateSummary()=>_summary.Text=$"{BedrockDimensionNames.DisplayName(_selection.Dimension)} · X={_selection.MinimumX}…{_selection.MaximumX}, Z={_selection.MinimumZ}…{_selection.MaximumZ} · {_selection.Area:N0} 个 X/Z 列";
    private void EditSelection(){var w=new RegionSelectionEditWindow(_selection){Owner=this};if(w.ShowDialog()!=true)return;_selection=w.Selection;_selectionChanged(_selection);UpdateSummary();}
    private void OpenTickingAreas(){var minX=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MinimumX,16);var maxX=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MaximumX,16);var minZ=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MinimumZ,16);var maxZ=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MaximumZ,16);var suggested=new EnvironmentTickingAreaSpec(_selection.Dimension,false,minX,minZ,maxX,maxZ,$"selection_{DateTime.Now:HHmmss}",false).Normalized;var center=new ChunkPosition((int)(((long)minX+maxX)/2L),(int)(((long)minZ+maxZ)/2L),_selection.Dimension);new TickingAreaManagerWindow(_world,_prepare,_complete,center,_locateChunk,suggested){Owner=this}.ShowDialog();}
    private async Task MutateRegionAsync(bool regenerate){var minChunkX=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MinimumX,16);var maxChunkX=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MaximumX,16);var minChunkZ=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MinimumZ,16);var maxChunkZ=BedrockSurfaceRegionRenderer.FloorDiv(_selection.MaximumZ,16);var minX=checked(minChunkX*16);var minZ=checked(minChunkZ*16);var maxX=checked(maxChunkX*16+15);var maxZ=checked(maxChunkZ*16+15);var count=(long)(maxChunkX-minChunkX+1)*(maxChunkZ-minChunkZ+1);var action=regenerate?"重新生成":"清空";var explanation=regenerate?"将删除扩展范围内全部区块记录和关联 Actor，使 Minecraft 按种子重新生成。":"将删除扩展范围内全部区块记录和关联 Actor，再写入已生成的纯空气区块。";if(MessageBox.Show(this,$"实际操作范围：X={minX}…{maxX}, Z={minZ}…{maxZ}，共 {count:N0} 个完整区块。\n\n{explanation}\n\n修改只写入 Cache 工作副本；操作不会自动备份。",$"{action}区域？",MessageBoxButton.YesNo,MessageBoxImage.Warning,MessageBoxResult.No)!=MessageBoxResult.Yes)return;try{IsEnabled=false;await _prepare();var selection=_selection;var result=await Task.Run(()=>{using var db=_world.OpenDatabase(false);var store=new BedrockChunkStore(db);return regenerate?store.RegenerateRegion(selection.Dimension,selection.MinimumX,selection.MinimumZ,selection.MaximumX,selection.MaximumZ):store.ClearRegion(selection.Dimension,selection.MinimumX,selection.MinimumZ,selection.MaximumX,selection.MaximumZ);});var message=$"已{action} {result.ChangedChunkCount:N0} 个区块，跳过 {result.SkippedChunkCount:N0} 个无记录区块。";_complete(message);MessageBox.Show(this,message,$"{action}区域完成",MessageBoxButton.OK,MessageBoxImage.Information);}catch(Exception ex){MessageBox.Show(this,ex.Message,$"{action}区域失败",MessageBoxButton.OK,MessageBoxImage.Error);}finally{IsEnabled=true;}}
}

public sealed class RegionSelectionEditWindow : Window
{
    private readonly TextBox _x0=new(),_z0=new(),_x1=new(),_z1=new();public MapRegionSelection Selection{get;private set;}
    public RegionSelectionEditWindow(MapRegionSelection selection){Selection=selection;Title="编辑框选坐标";Width=480;Height=330;WindowStartupLocation=WindowStartupLocation.CenterOwner;ResizeMode=ResizeMode.NoResize;Content=BuildUi();_x0.Text=selection.MinimumX.ToString(CultureInfo.InvariantCulture);_z0.Text=selection.MinimumZ.ToString(CultureInfo.InvariantCulture);_x1.Text=selection.MaximumX.ToString(CultureInfo.InvariantCulture);_z1.Text=selection.MaximumZ.ToString(CultureInfo.InvariantCulture);}
    private UIElement BuildUi(){var g=new Grid{Margin=new Thickness(16)};g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(120)});g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});for(var i=0;i<6;i++)g.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});Add(g,0,"X0",_x0);Add(g,1,"Z0",_z0);Add(g,2,"X1",_x1);Add(g,3,"Z1",_z1);var help=new TextBlock{Text="输入顺序不限；保存时自动归一化为最小/最大坐标。",Foreground=System.Windows.Media.Brushes.DimGray,Margin=new Thickness(0,8,0,10)};Grid.SetRow(help,4);Grid.SetColumnSpan(help,2);g.Children.Add(help);var p=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};var ok=new Button{Content="确定",Padding=new Thickness(18,5,18,5),IsDefault=true};ok.Click+=Ok;p.Children.Add(ok);p.Children.Add(new Button{Content="取消",Padding=new Thickness(18,5,18,5),Margin=new Thickness(8,0,0,0),IsCancel=true});Grid.SetRow(p,5);Grid.SetColumnSpan(p,2);g.Children.Add(p);return g;}
    private static void Add(Grid g,int row,string label,UIElement c){var l=new TextBlock{Text=label,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,6,12,6)};Grid.SetRow(l,row);g.Children.Add(l);if(c is FrameworkElement f)f.Margin=new Thickness(0,6,0,6);Grid.SetRow(c,row);Grid.SetColumn(c,1);g.Children.Add(c);}
    private void Ok(object s,RoutedEventArgs e){if(!int.TryParse(_x0.Text.Trim(),out var x0)||!int.TryParse(_z0.Text.Trim(),out var z0)||!int.TryParse(_x1.Text.Trim(),out var x1)||!int.TryParse(_z1.Text.Trim(),out var z1)){MessageBox.Show(this,"四个坐标必须为 Int32。","输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return;}Selection=new MapRegionSelection(Selection.Dimension,Math.Min(x0,x1),Math.Min(z0,z1),Math.Max(x0,x1),Math.Max(z0,z1));DialogResult=true;}
}
