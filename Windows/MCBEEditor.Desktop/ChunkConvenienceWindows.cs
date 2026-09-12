using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.World;

namespace MCBEEditor.Desktop;

public sealed record BiomeLayerSummaryRow(int Index, string RangeText, int CoordinateCount, bool IsAbsent, string Summary)
{
    public string StateText => IsAbsent ? "未单独保存 / 继承" : "已保存";
}

public sealed record BiomeCellRow(int Index, int LocalX, int? LocalY, int LocalZ, uint BiomeId)
{
    public string CoordinateText => LocalY.HasValue ? $"{LocalX},{LocalY.Value},{LocalZ}" : $"{LocalX},{LocalZ}";
    public string DisplayName => BedrockBiomeCatalog.DisplayNameForId(BiomeId);
    public string Identifier => BedrockBiomeCatalog.EntryForId(BiomeId)?.Identifier ?? "未知/自定义";
}

public sealed class ChunkBiomeEditorWindow : Window
{
    private readonly WorldDocument _world;
    private readonly ChunkPosition _position;
    private readonly Func<Task> _prepare;
    private readonly Action<string>? _complete;
    private readonly DataGrid _layers = new();
    private readonly TextBlock _info = new();
    private readonly TextBlock _status = new();
    private BedrockChunkBiomeRecord? _record;
    private bool _dirty;

    public ChunkBiomeEditorWindow(WorldDocument world, ChunkPosition position, Func<Task> prepare, Action<string>? complete = null)
    {
        _world = world; _position = position; _prepare = prepare; _complete = complete;
        Title = $"区块生物群系 · {BedrockDimensionNames.DisplayName(position.Dimension)} ({position.X}, {position.Z})";
        Width = 980; Height = 650; MinWidth = 760; MinHeight = 500; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi(); Loaded += async (_, _) => await ReloadAsync();
    }

    private UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(10) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var top = new DockPanel { Margin = new Thickness(0,0,0,8) };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        var catalog = new Button { Content = "ID 对照…", Padding = new Thickness(12,4,12,4) }; catalog.Click += (_,_) => new BedrockDataValueWindow { Owner = this }.ShowDialog();
        var fill = new Button { Content = "整区块设置…", Padding = new Thickness(12,4,12,4), Margin = new Thickness(6,0,0,0) }; fill.Click += (_,_) => FillWholeChunk();
        var reload = new Button { Content = "重新读取", Padding = new Thickness(12,4,12,4), Margin = new Thickness(6,0,0,0) }; reload.Click += async (_,_) => await ReloadAsync();
        var save = new Button { Content = "应用", Padding = new Thickness(16,4,16,4), Margin = new Thickness(6,0,0,0), IsDefault = true }; save.Click += async (_,_) => await SaveAsync();
        buttons.Children.Add(catalog); buttons.Children.Add(fill); buttons.Children.Add(reload); buttons.Children.Add(save); DockPanel.SetDock(buttons, Dock.Right); top.Children.Add(buttons);
        _info.VerticalAlignment = VerticalAlignment.Center; _info.TextWrapping = TextWrapping.Wrap; top.Children.Add(_info); root.Children.Add(top);

        _layers.AutoGenerateColumns = false; _layers.IsReadOnly = true; _layers.CanUserAddRows = false; _layers.RowHeaderWidth = 0;
        _layers.Columns.Add(new DataGridTextColumn { Header="层", Binding=new Binding(nameof(BiomeLayerSummaryRow.RangeText)), Width=170 });
        _layers.Columns.Add(new DataGridTextColumn { Header="状态", Binding=new Binding(nameof(BiomeLayerSummaryRow.StateText)), Width=145 });
        _layers.Columns.Add(new DataGridTextColumn { Header="位置数", Binding=new Binding(nameof(BiomeLayerSummaryRow.CoordinateCount)), Width=100 });
        _layers.Columns.Add(new DataGridTextColumn { Header="内容", Binding=new Binding(nameof(BiomeLayerSummaryRow.Summary)), Width=new DataGridLength(1,DataGridLengthUnitType.Star) });
        _layers.MouseDoubleClick += (_, e) => { if (e.ChangedButton == MouseButton.Left && _layers.SelectedItem is BiomeLayerSummaryRow row) EditLayer(row.Index); };
        Grid.SetRow(_layers,1); root.Children.Add(_layers);
        _status.Margin = new Thickness(0,8,0,0); _status.Foreground = System.Windows.Media.Brushes.DimGray; _status.TextWrapping = TextWrapping.Wrap; Grid.SetRow(_status,2); root.Children.Add(_status);
        return root;
    }

    private async Task ReloadAsync()
    {
        if (_dirty)
        {
            var answer = MessageBox.Show(this, "当前有未保存的生物群系修改。放弃并重新读取？", "重新读取", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
            if (answer != MessageBoxResult.Yes) return;
        }
        try
        {
            _status.Text = "正在读取区块生物群系…";
            var position = _position;
            _record = await Task.Run(() => { using var db = _world.OpenDatabase(true); return new BedrockChunkBiomeStore(db).Read(position); });
            _dirty = false; RefreshRows();
            if (_record is null) MessageBox.Show(this, "该区块没有 Data3D、Data2D 或 Data2DLegacy 生物群系记录。", "没有生物群系记录", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex) { _status.Text = "读取失败：" + ex.Message; MessageBox.Show(this, ex.Message, "读取生物群系失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void RefreshRows()
    {
        if (_record is null) { _layers.ItemsSource = null; _info.Text = "没有可编辑的生物群系记录。"; _status.Text = string.Empty; return; }
        var document = _record.Document;
        _info.Text = $"格式 {document.Format} · 高度图 256 项（保持原值） · 原始记录 {_record.RawValueSize:N0} B · 双击一层编辑";
        var rows = document.Layers.Select((layer,index) =>
        {
            var counts = layer.BiomeIds.GroupBy(id => id).OrderByDescending(group => group.Count()).ThenBy(group => group.Key).Take(8)
                .Select(group => $"{group.Key}:{BedrockBiomeCatalog.DisplayNameForId(group.Key)}×{group.Count()}");
            var range = layer.BaseY is int baseY ? $"Y {baseY}…{baseY+15}" : "16×16 平面";
            return new BiomeLayerSummaryRow(index, range, layer.BiomeIds.Length, layer.IsAbsent, string.Join("，", counts));
        }).ToArray();
        _layers.ItemsSource = rows;
        _status.Text = _dirty ? "有未保存修改。" : $"{rows.Length} 个生物群系层。Data3D 的 0xff 继承层在编辑后会转为显式保存层。";
    }

    private void EditLayer(int index)
    {
        if (_record is null || (uint)index >= (uint)_record.Document.Layers.Count) return;
        var editor = new BiomeLayerEditorWindow(_record.Document.Layers[index]) { Owner = this };
        if (editor.ShowDialog() == true && editor.ResultLayer is { } result)
        {
            _record.Document.Layers[index] = result; _dirty = true; RefreshRows();
        }
    }

    private void FillWholeChunk()
    {
        if (_record is null) return;
        if (_record.Document.Format != BedrockBiomeFormat.Data3D)
        {
            MessageBox.Show(this, "整区块 16×384×16 设置仅适用于 Data3D；Data2D 请双击 16×16 层后使用“整层设置”。", "格式限制", MessageBoxButton.OK, MessageBoxImage.Information); return;
        }
        var initial = _record.Document.Layers.FirstOrDefault()?.BiomeIds.FirstOrDefault() ?? 0;
        var text = TextPromptWindow.Prompt(this, "整区块生物群系", "输入数字 ID 或 minecraft:identifier", initial.ToString(CultureInfo.InvariantCulture));
        if (text is null) return;
        try { var parsed = BedrockBiomeCatalog.Parse(text.Trim()); _record.Document.FillAllData3DLayers(parsed.Id); _dirty = true; RefreshRows(); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "输入错误", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    private async Task SaveAsync()
    {
        var record = _record;
        if (record is null || !_dirty) return;
        var answer = MessageBox.Show(this, $"将修改应用到 Cache 临时工作副本中的 {record.Document.Format} 生物群系记录？\n\n源世界不会被修改；只有导出 .mcworld 才会持久化结果。", "应用生物群系", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
        if (answer != MessageBoxResult.Yes) return;
        try
        {
            await _prepare();
            var bytes = await Task.Run(() => { using var db = _world.OpenDatabase(false); return new BedrockChunkBiomeStore(db).Save(record); });
            _dirty = false; var message = $"已应用 {record.Document.Format} 生物群系记录到工作副本，{bytes:N0} B。"; _status.Text = message; _complete?.Invoke(message);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "应用生物群系失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
}

public sealed class BiomeLayerEditorWindow : Window
{
    private BedrockBiomeLayer _layer;
    private readonly TextBox _search = new();
    private readonly DataGrid _grid = new();
    private readonly TextBlock _status = new();
    public BedrockBiomeLayer? ResultLayer { get; private set; }

    public BiomeLayerEditorWindow(BedrockBiomeLayer layer)
    {
        _layer = new BedrockBiomeLayer(layer.BaseY, layer.BiomeIds.ToArray(), layer.IsAbsent);
        Title = layer.BaseY is int baseY ? $"生物群系 Y {baseY}…{baseY+15}" : "生物群系 16×16";
        Width=1020; Height=700; MinWidth=760; MinHeight=520; WindowStartupLocation=WindowStartupLocation.CenterOwner; Content=BuildUi();
        _search.TextChanged += (_,_) => RefreshRows(); RefreshRows();
    }
    private UIElement BuildUi()
    {
        var root=new Grid{Margin=new Thickness(10)};root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        var top=new Grid();top.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});top.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});top.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});top.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});
        _search.ToolTip="搜索 ID、中文名称、identifier 或坐标，例如 5,10 / 3,7,12";top.Children.Add(_search);
        var set=new Button{Content="修改选中…",Padding=new Thickness(12,4,12,4),Margin=new Thickness(8,0,0,0)};set.Click+=(_,_)=>SetSelected();Grid.SetColumn(set,1);top.Children.Add(set);
        var fill=new Button{Content="整层设置…",Padding=new Thickness(12,4,12,4),Margin=new Thickness(6,0,0,0)};fill.Click+=(_,_)=>FillLayer();Grid.SetColumn(fill,2);top.Children.Add(fill);
        var done=new Button{Content="完成",Padding=new Thickness(16,4,16,4),Margin=new Thickness(6,0,0,0),IsDefault=true};done.Click+=(_,_)=>{ResultLayer=_layer;DialogResult=true;};Grid.SetColumn(done,3);top.Children.Add(done);root.Children.Add(top);
        _grid.AutoGenerateColumns=false;_grid.IsReadOnly=true;_grid.CanUserAddRows=false;_grid.RowHeaderWidth=0;
        _grid.Columns.Add(new DataGridTextColumn{Header="坐标",Binding=new Binding(nameof(BiomeCellRow.CoordinateText)),Width=130});_grid.Columns.Add(new DataGridTextColumn{Header="ID",Binding=new Binding(nameof(BiomeCellRow.BiomeId)),Width=100});_grid.Columns.Add(new DataGridTextColumn{Header="名称",Binding=new Binding(nameof(BiomeCellRow.DisplayName)),Width=210});_grid.Columns.Add(new DataGridTextColumn{Header="identifier",Binding=new Binding(nameof(BiomeCellRow.Identifier)),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});
        _grid.MouseDoubleClick+=(_,e)=>{if(e.ChangedButton==MouseButton.Left)SetSelected();};Grid.SetRow(_grid,1);_grid.Margin=new Thickness(0,8,0,0);root.Children.Add(_grid);
        _status.Margin=new Thickness(0,8,0,0);_status.Foreground=System.Windows.Media.Brushes.DimGray;Grid.SetRow(_status,2);root.Children.Add(_status);return root;
    }
    private IReadOnlyList<BiomeCellRow> AllRows()
    {
        var output=new List<BiomeCellRow>(_layer.BiomeIds.Length);if(_layer.BaseY is int baseY){for(var x=0;x<16;x++)for(var z=0;z<16;z++)for(var y=0;y<16;y++){var i=x*256+z*16+y;if(i<_layer.BiomeIds.Length)output.Add(new BiomeCellRow(i,x,baseY+y,z,_layer.BiomeIds[i]));}}
        else{for(var z=0;z<16;z++)for(var x=0;x<16;x++){var i=z*16+x;if(i<_layer.BiomeIds.Length)output.Add(new BiomeCellRow(i,x,null,z,_layer.BiomeIds[i]));}}return output;
    }
    private void RefreshRows(){var q=_search.Text.Trim().ToLowerInvariant();var rows=AllRows();if(q.Length>0)rows=rows.Where(r=>r.BiomeId.ToString(CultureInfo.InvariantCulture).Contains(q,StringComparison.OrdinalIgnoreCase)||r.DisplayName.Contains(q,StringComparison.OrdinalIgnoreCase)||r.Identifier.Contains(q,StringComparison.OrdinalIgnoreCase)||r.CoordinateText.Contains(q,StringComparison.OrdinalIgnoreCase)).ToArray();_grid.ItemsSource=rows;_status.Text=$"显示 {rows.Count:N0} / {_layer.BiomeIds.Length:N0} 个位置 · {(_layer.IsAbsent?"当前来自继承层；第一次修改后会显式保存":"已显式保存")}";}
    private uint? PromptId(uint initial){var text=TextPromptWindow.Prompt(this,"修改生物群系","输入数字 ID 或 minecraft:identifier",initial.ToString(CultureInfo.InvariantCulture));if(text is null)return null;try{return BedrockBiomeCatalog.Parse(text.Trim()).Id;}catch(Exception ex){MessageBox.Show(this,ex.Message,"输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return null;}}
    private void SetSelected(){if(_grid.SelectedItem is not BiomeCellRow row)return;var id=PromptId(row.BiomeId);if(!id.HasValue)return;var values=_layer.BiomeIds.ToArray();values[row.Index]=id.Value;_layer=new BedrockBiomeLayer(_layer.BaseY,values,false);RefreshRows();}
    private void FillLayer(){var initial=_layer.BiomeIds.FirstOrDefault();var id=PromptId(initial);if(!id.HasValue)return;_layer=new BedrockBiomeLayer(_layer.BaseY,Enumerable.Repeat(id.Value,_layer.BiomeIds.Length).ToArray(),false);RefreshRows();}
}

public sealed record TickingAreaRow(EnvironmentTickingAreaSpec Area, bool ContainsFocus)
{
    public string Name => string.IsNullOrWhiteSpace(Area.Name) ? "未命名" : Area.Name;
    public string Dimension => BedrockDimensionNames.DisplayName(Area.Dimension);
    public string Shape => Area.IsCircle ? "圆形" : "矩形";
    public string Range => Area.IsCircle ? $"中心区块 ({Area.CenterChunk.X}, {Area.CenterChunk.Z}) · 半径 {Area.Radius}" : $"({Area.Normalized.MinimumX},{Area.Normalized.MinimumZ}) → ({Area.Normalized.MaximumX},{Area.Normalized.MaximumZ})";
    public string Preload => Area.Preload ? "是" : "否";
}

public sealed class TickingAreaManagerWindow : Window
{
    private readonly WorldDocument _world; private readonly Func<Task> _prepare; private readonly Action<string>? _complete; private readonly Action<ChunkPosition>? _locate; private readonly ChunkPosition? _focus; private readonly EnvironmentTickingAreaSpec? _suggestedArea;
    private readonly DataGrid _grid=new();private readonly TextBlock _status=new();private IReadOnlyList<TickingAreaRow> _rows=[];
    public TickingAreaManagerWindow(WorldDocument world,Func<Task> prepare,Action<string>? complete=null,ChunkPosition? focus=null,Action<ChunkPosition>? locate=null,EnvironmentTickingAreaSpec? suggestedArea=null){_world=world;_prepare=prepare;_complete=complete;_focus=focus;_locate=locate;_suggestedArea=suggestedArea;Title="常加载区域";Width=1050;Height=650;MinWidth=780;MinHeight=500;WindowStartupLocation=WindowStartupLocation.CenterOwner;Content=BuildUi();Loaded+=async(_,_)=>await ReloadAsync();}
    private UIElement BuildUi(){var root=new Grid{Margin=new Thickness(10)};root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});var top=new DockPanel{Margin=new Thickness(0,0,0,8)};var panel=new StackPanel{Orientation=Orientation.Horizontal};
        Button Add(string text,RoutedEventHandler handler){var b=new Button{Content=text,Padding=new Thickness(12,4,12,4),Margin=new Thickness(6,0,0,0)};b.Click+=handler;panel.Children.Add(b);return b;}
        Add("新增…",(_,_)=>Edit(null));if(_suggestedArea is not null)Add("按所选区块新增",(_,_)=>CreateFromSelection());else if(_focus.HasValue)Add("按当前区块新增",(_,_)=>CreateFromFocus());Add("编辑…",(_,_)=>{if(_grid.SelectedItem is TickingAreaRow r)Edit(r.Area);});Add("开启预加载",async(_,_)=>await SetPreloadAsync(true));Add("关闭预加载",async(_,_)=>await SetPreloadAsync(false));Add("删除",async(_,_)=>await DeleteAsync());Add("定位",(_,_)=>LocateSelected());Add("刷新",async(_,_)=>await ReloadAsync());DockPanel.SetDock(panel,Dock.Right);top.Children.Add(panel);top.Children.Add(new TextBlock{Text=_suggestedArea is { } suggested?$"所选区块建议范围：{BedrockDimensionNames.DisplayName(suggested.Dimension)} ({suggested.Normalized.MinimumX},{suggested.Normalized.MinimumZ}) → ({suggested.Normalized.MaximumX},{suggested.Normalized.MaximumZ})。":_focus is { } f?$"当前区块：{BedrockDimensionNames.DisplayName(f.Dimension)} ({f.X}, {f.Z})；橙色行包含当前区块。":"基岩版每世界最多 10 个常加载区域；Ctrl/Shift 可多选，双击编辑。",VerticalAlignment=VerticalAlignment.Center,TextWrapping=TextWrapping.Wrap});root.Children.Add(top);
        _grid.AutoGenerateColumns=false;_grid.IsReadOnly=true;_grid.CanUserAddRows=false;_grid.SelectionMode=DataGridSelectionMode.Extended;_grid.SelectionUnit=DataGridSelectionUnit.FullRow;_grid.RowHeaderWidth=0;_grid.Columns.Add(new DataGridTextColumn{Header="名称",Binding=new Binding(nameof(TickingAreaRow.Name)),Width=180});_grid.Columns.Add(new DataGridTextColumn{Header="维度",Binding=new Binding(nameof(TickingAreaRow.Dimension)),Width=110});_grid.Columns.Add(new DataGridTextColumn{Header="形状",Binding=new Binding(nameof(TickingAreaRow.Shape)),Width=90});_grid.Columns.Add(new DataGridTextColumn{Header="范围",Binding=new Binding(nameof(TickingAreaRow.Range)),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});_grid.Columns.Add(new DataGridTextColumn{Header="预加载",Binding=new Binding(nameof(TickingAreaRow.Preload)),Width=85});_grid.LoadingRow+=(_,e)=>{e.Row.Background=e.Row.Item is TickingAreaRow r&&r.ContainsFocus?System.Windows.Media.Brushes.Moccasin:System.Windows.Media.Brushes.Transparent;};_grid.MouseDoubleClick+=(_,e)=>{if(e.ChangedButton==MouseButton.Left&&_grid.SelectedItem is TickingAreaRow r)Edit(r.Area);};Grid.SetRow(_grid,1);root.Children.Add(_grid);_status.Margin=new Thickness(0,8,0,0);_status.Foreground=System.Windows.Media.Brushes.DimGray;Grid.SetRow(_status,2);root.Children.Add(_status);return root;}
    private static bool Contains(EnvironmentTickingAreaSpec area,ChunkPosition focus){if(area.Dimension!=focus.Dimension)return false;var a=area.Normalized;if(a.IsCircle){var c=a.CenterChunk;var dx=(long)focus.X-c.X;var dz=(long)focus.Z-c.Z;return dx*dx+dz*dz<=(long)a.Radius*a.Radius;}return focus.X>=a.MinimumX&&focus.X<=a.MaximumX&&focus.Z>=a.MinimumZ&&focus.Z<=a.MaximumZ;}
    private async Task ReloadAsync(){try{_status.Text="正在读取常加载区域…";var values=await Task.Run(()=>{using var db=_world.OpenDatabase(true);return new EnvironmentCommandStore(_world,db).TickingAreas();});_rows=values.Select(a=>new TickingAreaRow(a,_focus.HasValue&&Contains(a,_focus.Value))).OrderByDescending(r=>r.ContainsFocus).ThenBy(r=>r.Area.Dimension).ThenBy(r=>r.Name,StringComparer.OrdinalIgnoreCase).ToArray();_grid.ItemsSource=_rows;_status.Text=$"{_rows.Count} 个区域"+(_focus.HasValue?$"；{_rows.Count(r=>r.ContainsFocus)} 个包含当前区块。":"。")+" 地图/列表编辑均只写 Cache 临时工作副本。";}catch(Exception ex){_status.Text="读取失败："+ex.Message;}}
    private void CreateFromFocus(){if(_focus is not { } f)return;var area=new EnvironmentTickingAreaSpec(f.Dimension,false,f.X,f.Z,f.X,f.Z,$"chunk_{f.X}_{f.Z}",false);Edit(area,creating:true);}
    private void CreateFromSelection(){if(_suggestedArea is not { } area)return;Edit(area,creating:true);}
    private void Edit(EnvironmentTickingAreaSpec? area,bool creating=false){var initial=area;if(initial is null&&_focus is { } f)initial=new EnvironmentTickingAreaSpec(f.Dimension,false,f.X,f.Z,f.X,f.Z,$"area_{DateTime.Now:HHmmss}",false);var dialog=new TickingAreaEditWindow(initial,creating||area is null){Owner=this};if(dialog.ShowDialog()!=true||dialog.ResultArea is not { } result)return;_ = SaveAsync(result,creating||area is null?null:area!.Name);}
    private async Task SaveAsync(EnvironmentTickingAreaSpec area,string? originalName){try{await _prepare();var message=await Task.Run(()=>{using var db=_world.OpenDatabase(false);return new EnvironmentCommandStore(_world,db).SaveTickingArea(area,originalName).Message;});_complete?.Invoke(message);_status.Text=message;await ReloadAsync();}catch(Exception ex){MessageBox.Show(this,ex.Message,"应用常加载区域失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
    private TickingAreaRow[] SelectedRows()=>_grid.SelectedItems.Cast<TickingAreaRow>().ToArray();
    private async Task SetPreloadAsync(bool enabled){var rows=SelectedRows();if(rows.Length==0)return;try{await _prepare();var names=rows.Select(row=>row.Area.Name).ToArray();var result=await Task.Run(()=>{using var db=_world.OpenDatabase(false);return new EnvironmentCommandStore(_world,db).SetTickingAreaPreload(names,enabled);});_complete?.Invoke(result.Message);_status.Text=result.Message;await ReloadAsync();}catch(Exception ex){MessageBox.Show(this,ex.Message,"批量修改预加载失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
    private async Task DeleteAsync(){var rows=SelectedRows();if(rows.Length==0)return;var prompt=rows.Length==1?$"删除常加载区域 {rows[0].Name}？":$"删除所选 {rows.Length} 个常加载区域？\n\n不会删除区域内的区块数据。";if(MessageBox.Show(this,prompt,"确认删除",MessageBoxButton.YesNo,MessageBoxImage.Warning,MessageBoxResult.No)!=MessageBoxResult.Yes)return;try{await _prepare();var names=rows.Select(row=>row.Area.Name).ToArray();var result=await Task.Run(()=>{using var db=_world.OpenDatabase(false);return new EnvironmentCommandStore(_world,db).DeleteTickingAreas(names);});_complete?.Invoke(result.Message);_status.Text=result.Message;await ReloadAsync();}catch(Exception ex){MessageBox.Show(this,ex.Message,"删除失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
    private void LocateSelected(){if(_locate is null||_grid.SelectedItem is not TickingAreaRow row)return;var a=row.Area.Normalized;var c=a.IsCircle?a.CenterChunk:((int)(((long)a.MinimumX+a.MaximumX)/2L),(int)(((long)a.MinimumZ+a.MaximumZ)/2L));_locate(new ChunkPosition(c.Item1,c.Item2,a.Dimension));}
}

public sealed class TickingAreaEditWindow : Window
{
    private readonly TextBox _name=new();private readonly ComboBox _dimension=new();private readonly ComboBox _shape=new();private readonly CheckBox _preload=new(){Content="进入世界时预加载"};private readonly TextBox _x0=new();private readonly TextBox _z0=new();private readonly TextBox _x1=new();private readonly TextBox _z1=new();private readonly TextBlock _x0Label=new();private readonly TextBlock _z0Label=new();private readonly TextBlock _x1Label=new();private readonly TextBlock _z1Label=new();private readonly Grid _z1Row=new();
    public EnvironmentTickingAreaSpec? ResultArea{get;private set;}
    public TickingAreaEditWindow(EnvironmentTickingAreaSpec? area,bool creating){Title=creating?"新增常加载区域":"编辑常加载区域";Width=650;Height=500;ResizeMode=ResizeMode.NoResize;WindowStartupLocation=WindowStartupLocation.CenterOwner;Content=BuildUi();foreach(var d in new[]{"主世界","下界","末地"})_dimension.Items.Add(d);_shape.Items.Add("矩形");_shape.Items.Add("圆形");Populate(area);_shape.SelectionChanged+=(_,_)=>UpdateShape();UpdateShape();}
    private UIElement BuildUi(){var p=new StackPanel{Margin=new Thickness(18)};p.Children.Add(Row("名称",_name));p.Children.Add(Row("维度",_dimension));p.Children.Add(Row("形状",_shape));p.Children.Add(_preload);p.Children.Add(CoordinateRow(_x0Label,_x0));p.Children.Add(CoordinateRow(_z0Label,_z0));p.Children.Add(CoordinateRow(_x1Label,_x1));_z1Row.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(170)});_z1Row.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});_z1Label.VerticalAlignment=VerticalAlignment.Center;_z1Row.Children.Add(_z1Label);Grid.SetColumn(_z1,1);_z1Row.Children.Add(_z1);_z1Row.Margin=new Thickness(0,6,0,0);p.Children.Add(_z1Row);p.Children.Add(new TextBlock{Text="矩形坐标单位为区块；圆形中心坐标单位为方块、半径单位为区块（0～4）。每个区域最多 100 个区块。",TextWrapping=TextWrapping.Wrap,Foreground=System.Windows.Media.Brushes.DimGray,Margin=new Thickness(0,14,0,12)});var save=new Button{Content="应用",Padding=new Thickness(18,6,18,6),HorizontalAlignment=HorizontalAlignment.Right,IsDefault=true};save.Click+=(_,_)=>Save();p.Children.Add(save);return p;}
    private static UIElement Row(string label,Control control){var g=new Grid{Margin=new Thickness(0,6,0,0)};g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(170)});g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});g.Children.Add(new TextBlock{Text=label,VerticalAlignment=VerticalAlignment.Center});Grid.SetColumn(control,1);g.Children.Add(control);return g;}private static UIElement CoordinateRow(TextBlock label,TextBox box){var g=new Grid{Margin=new Thickness(0,6,0,0)};g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(170)});g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});label.VerticalAlignment=VerticalAlignment.Center;g.Children.Add(label);Grid.SetColumn(box,1);g.Children.Add(box);return g;}
    private void Populate(EnvironmentTickingAreaSpec? source){var a=source??new EnvironmentTickingAreaSpec(0,false,0,0,0,0,$"area_{DateTime.Now:HHmmss}",false);_name.Text=a.Name;_dimension.SelectedIndex=Math.Clamp(a.Dimension,0,2);_shape.SelectedIndex=a.IsCircle?1:0;_preload.IsChecked=a.Preload;if(a.IsCircle){_x0.Text=a.CenterBlockX.ToString(CultureInfo.InvariantCulture);_z0.Text=a.CenterBlockZ.ToString(CultureInfo.InvariantCulture);_x1.Text=a.Radius.ToString(CultureInfo.InvariantCulture);_z1.Text="";}else{var n=a.Normalized;_x0.Text=n.MinimumX.ToString(CultureInfo.InvariantCulture);_z0.Text=n.MinimumZ.ToString(CultureInfo.InvariantCulture);_x1.Text=n.MaximumX.ToString(CultureInfo.InvariantCulture);_z1.Text=n.MaximumZ.ToString(CultureInfo.InvariantCulture);}}
    private void UpdateShape(){var circle=_shape.SelectedIndex==1;_x0Label.Text=circle?"中心方块 X":"最小区块 X";_z0Label.Text=circle?"中心方块 Z":"最小区块 Z";_x1Label.Text=circle?"半径（区块）":"最大区块 X";_z1Label.Text="最大区块 Z";_z1Row.Visibility=circle?Visibility.Collapsed:Visibility.Visible;}
    private void Save(){try{var name=_name.Text.Trim();if(string.IsNullOrWhiteSpace(name)||name.Equals("ALL",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("名称不能为空，也不能是 ALL。");if(name.Any(c=>!(char.IsLetterOrDigit(c)||c is '_' or '.' or ':' or '-')))throw new InvalidDataException("名称只能包含字母、数字、下划线、点、冒号和连字符。");var dim=_dimension.SelectedIndex;if(dim<0)throw new InvalidDataException("请选择维度。");if(!int.TryParse(_x0.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var x0)||!int.TryParse(_z0.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var z0)||!int.TryParse(_x1.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var x1))throw new InvalidDataException("坐标/半径必须是 Int32 整数。");EnvironmentTickingAreaSpec area;if(_shape.SelectedIndex==1){if(x1 is <0 or >4)throw new InvalidDataException("圆形半径必须为 0～4。");var radius=(long)x1*16;var minX=checked((int)((long)x0-radius));var minZ=checked((int)((long)z0-radius));var maxX=checked((int)((long)x0+radius));var maxZ=checked((int)((long)z0+radius));area=new EnvironmentTickingAreaSpec(dim,true,minX,minZ,maxX,maxZ,name,_preload.IsChecked==true);}else{if(!int.TryParse(_z1.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var z1))throw new InvalidDataException("最大区块 Z 必须是 Int32 整数。");area=new EnvironmentTickingAreaSpec(dim,false,x0,z0,x1,z1,name,_preload.IsChecked==true).Normalized;}if(area.ChunkCount is <=0 or >100)throw new InvalidDataException("单个常加载区域最多 100 个区块。");ResultArea=area;DialogResult=true;}catch(Exception ex){MessageBox.Show(this,ex.Message,"输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);}}
}

public sealed class VillageResidentEntitiesWindow : Window
{
    private readonly WorldDocument _world;private readonly string _identifier;private readonly VillageResidentEntityKind _kind;private readonly Func<Task> _prepare;private readonly DataGrid _grid=new();private readonly TextBlock _status=new();private IReadOnlyList<BedrockWorldObject> _objects=[];
    public VillageResidentEntitiesWindow(WorldDocument world,string identifier,VillageResidentEntityKind kind,Func<Task> prepare){_world=world;_identifier=identifier;_kind=kind;_prepare=prepare;Title=$"村庄居民 · {KindText(kind)}";Width=1050;Height=650;MinWidth=760;MinHeight=480;WindowStartupLocation=WindowStartupLocation.CenterOwner;Content=BuildUi();Loaded+=async(_,_)=>await ReloadAsync();}
    public static string KindText(VillageResidentEntityKind kind)=>kind switch{VillageResidentEntityKind.Villager=>"村民",VillageResidentEntityKind.Cat=>"猫",VillageResidentEntityKind.IronGolem=>"铁傀儡",_=>"其他实体"};
    private UIElement BuildUi(){var root=new Grid{Margin=new Thickness(10)};root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.Children.Add(new TextBlock{Text=$"使用村庄 DWELLERS 中的 ID / UniqueID 与世界实体 UniqueID 匹配。双击查看/编辑 {KindText(_kind)} NBT。",TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,0,0,8)});_grid.AutoGenerateColumns=false;_grid.IsReadOnly=true;_grid.CanUserAddRows=false;_grid.RowHeaderWidth=0;_grid.Columns.Add(new DataGridTextColumn{Header="名称",Binding=new Binding(nameof(BedrockWorldObject.DisplayName)),Width=180});_grid.Columns.Add(new DataGridTextColumn{Header="identifier",Binding=new Binding(nameof(BedrockWorldObject.Identifier)),Width=240});_grid.Columns.Add(new DataGridTextColumn{Header="UniqueID",Binding=new Binding(nameof(BedrockWorldObject.UniqueId)),Width=160});_grid.Columns.Add(new DataGridTextColumn{Header="维度",Binding=new Binding(nameof(BedrockWorldObject.Dimension)),Width=80});_grid.Columns.Add(new DataGridTextColumn{Header="区块 X",Binding=new Binding(nameof(BedrockWorldObject.ChunkX)),Width=90});_grid.Columns.Add(new DataGridTextColumn{Header="区块 Z",Binding=new Binding(nameof(BedrockWorldObject.ChunkZ)),Width=90});_grid.Columns.Add(new DataGridTextColumn{Header="来源",Binding=new Binding(nameof(BedrockWorldObject.SourceText)),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});_grid.MouseDoubleClick+=async(_,e)=>{if(e.ChangedButton==MouseButton.Left&&_grid.SelectedItem is BedrockWorldObject item)await EditAsync(item);};Grid.SetRow(_grid,1);root.Children.Add(_grid);_status.Margin=new Thickness(0,8,0,0);_status.Foreground=System.Windows.Media.Brushes.DimGray;Grid.SetRow(_status,2);root.Children.Add(_status);return root;}
    private async Task ReloadAsync(){try{_status.Text="正在遍历 Dwellers ID 并匹配世界实体…";var result=await Task.Run(()=>{using var db=_world.OpenDatabase(true);return new VillageNbtStore(db).ResidentResolution(_identifier);});_objects=result.EntitiesOf(_kind);_grid.ItemsSource=_objects;_status.Text=$"Dwellers 请求 {result.RequestedUniqueIds.Count:N0} 个 UniqueID；匹配到 {result.Entities.Count:N0} 个实体，其中 {KindText(_kind)} {_objects.Count:N0} 个；未匹配 {result.UnresolvedUniqueIds.Count:N0} 个。";}catch(Exception ex){_status.Text="读取失败："+ex.Message;}}
    private async Task EditAsync(BedrockWorldObject item){var protectedFields=new[]{"UniqueID","UniqueId","uniqueID","uniqueId"};var editor=new NbtEditorWindow($"{KindText(_kind)} · {item.DisplayName}",item.Document,async edited=>{await _prepare();await Task.Run(()=>{using var db=_world.OpenDatabase(false);new BedrockWorldObjectNbtStore(db).Save(item,edited);});},protectedFields,item.Storage.Encoding){Owner=this};editor.ShowDialog();if(editor.DidSave)await ReloadAsync();}
}
