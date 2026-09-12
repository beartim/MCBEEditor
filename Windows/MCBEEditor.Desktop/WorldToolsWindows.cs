using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.World;

namespace MCBEEditor.Desktop;

public sealed class BedrockDataValueWindow : Window
{
    private readonly ComboBox _category = new();
    private readonly TextBox _search = new();
    private readonly DataGrid _grid = new();
    private readonly TextBlock _count = new();

    public BedrockDataValueWindow()
    {
        Title = "基岩版数据值";
        Width = 920; Height = 680; MinWidth = 680; MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi();
        foreach (var name in new[] { "实体 ID", "生物群系 ID", "状态效果 ID", "魔咒 ID", "方块 ID（旧版）" }) _category.Items.Add(name);
        _category.SelectedIndex = 0;
        _category.SelectionChanged += (_, _) => Refresh();
        _search.TextChanged += (_, _) => Refresh();
        Refresh();
    }

    private UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(12) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var top = new Grid { Margin = new Thickness(0,0,0,8) };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _category.Margin = new Thickness(0,0,8,0); top.Children.Add(_category);
        _search.ToolTip = "搜索十进制/十六进制 ID、名称或 identifier";
        _search.Text = string.Empty; Grid.SetColumn(_search, 1); top.Children.Add(_search); root.Children.Add(top);

        _grid.AutoGenerateColumns = false; _grid.IsReadOnly = true; _grid.CanUserAddRows = false; _grid.RowHeaderWidth = 0;
        _grid.Columns.Add(new DataGridTextColumn { Header = "ID", Binding = new Binding(nameof(BedrockDataValueEntry.Id)), Width = 90 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "HEX", Binding = new Binding(nameof(BedrockDataValueEntry.HexadecimalId)), Width = 95 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "名称", Binding = new Binding(nameof(BedrockDataValueEntry.DisplayName)), Width = 220 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "identifier", Binding = new Binding(nameof(BedrockDataValueEntry.Identifier)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        Grid.SetRow(_grid, 1); root.Children.Add(_grid);
        _count.Margin = new Thickness(0,8,0,0); _count.Foreground = System.Windows.Media.Brushes.DimGray; Grid.SetRow(_count,2); root.Children.Add(_count);
        return root;
    }

    private IReadOnlyList<BedrockDataValueEntry> Source() => _category.SelectedIndex switch
    {
        1 => BedrockDataValueCatalog.Biomes,
        2 => BedrockDataValueCatalog.StatusEffects,
        3 => BedrockDataValueCatalog.Enchantments,
        4 => BedrockDataValueCatalog.LegacyBlocks,
        _ => BedrockDataValueCatalog.Entities
    };

    private void Refresh()
    {
        var rows = BedrockDataValueCatalog.Search(Source(), _search.Text);
        _grid.ItemsSource = rows;
        _count.Text = $"{rows.Count:N0} 项";
    }
}

public sealed class WeatherEditorWindow : Window
{
    private readonly WorldDocument _world;
    private readonly Func<Task> _prepare;
    private readonly Action<string> _complete;
    private readonly TextBlock _condition = new();
    private readonly Slider _rain = new() { Minimum = 0, Maximum = 1, TickFrequency = 0.01 };
    private readonly Slider _lightning = new() { Minimum = 0, Maximum = 1, TickFrequency = 0.01 };
    private readonly TextBlock _rainValue = new();
    private readonly TextBlock _lightningValue = new();
    private readonly TextBox _rainTime = new();
    private readonly TextBox _lightningTime = new();
    private readonly CheckBox _automatic = new() { Content = "天气自动变化（doWeatherCycle）" };

    public WeatherEditorWindow(WorldDocument world, Func<Task> prepare, Action<string> complete)
    {
        _world = world; _prepare = prepare; _complete = complete;
        Title = "天气"; Width = 660; Height = 560; MinWidth = 560; MinHeight = 480; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildUi();
        _rain.ValueChanged += (_, _) => UpdateLabels(); _lightning.ValueChanged += (_, _) => UpdateLabels();
        Loaded += async (_, _) => await ReloadAsync();
    }

    private UIElement BuildUi()
    {
        var p = new StackPanel { Margin = new Thickness(18) };
        _condition.FontSize = 20; _condition.FontWeight = FontWeights.SemiBold; p.Children.Add(_condition);
        var presets = new UniformGrid { Columns = 3, Margin = new Thickness(0,12,0,10) };
        presets.Children.Add(Preset("晴朗", () => Apply(BedrockWeatherSettings.Clear(_automatic.IsChecked == true))));
        presets.Children.Add(Preset("下雨", () => Apply(BedrockWeatherSettings.Rain(12_000, 1, _automatic.IsChecked == true))));
        presets.Children.Add(Preset("雷暴", () => Apply(BedrockWeatherSettings.Thunder(12_000, 1, _automatic.IsChecked == true))));
        p.Children.Add(presets); p.Children.Add(_automatic);
        p.Children.Add(Section("降雨")); p.Children.Add(SliderRow(_rain, _rainValue)); p.Children.Add(FieldRow("剩余时间（游戏刻）", _rainTime));
        p.Children.Add(Section("雷暴")); p.Children.Add(SliderRow(_lightning, _lightningValue)); p.Children.Add(FieldRow("剩余时间（游戏刻）", _lightningTime));
        p.Children.Add(new TextBlock { Text = "等级范围 0～1。20 游戏刻约 1 秒。修改只应用到 Cache 临时工作副本，源世界不会被修改。", TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.DimGray, Margin = new Thickness(0,14,0,10) });
        var save = new Button { Content = "应用", Padding = new Thickness(20,6,20,6), HorizontalAlignment = HorizontalAlignment.Right, IsDefault = true };
        save.Click += async (_, _) => await SaveAsync(); p.Children.Add(save); return new ScrollViewer { Content = p, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private static Button Preset(string text, Action action) { var b = new Button { Content = text, Margin = new Thickness(4), Padding = new Thickness(12,7,12,7) }; b.Click += (_, _) => action(); return b; }
    private static TextBlock Section(string text) => new() { Text = text, FontWeight = FontWeights.SemiBold, FontSize = 15, Margin = new Thickness(0,14,0,4) };
    private static UIElement SliderRow(Slider slider, TextBlock label) { var g = new Grid(); g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(70) }); g.Children.Add(slider); label.TextAlignment = TextAlignment.Right; label.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(label,1); g.Children.Add(label); return g; }
    private static UIElement FieldRow(string title, TextBox box) { var g=new Grid{Margin=new Thickness(0,6,0,0)};g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(210)});g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});g.Children.Add(new TextBlock{Text=title,VerticalAlignment=VerticalAlignment.Center});Grid.SetColumn(box,1);g.Children.Add(box);return g; }

    private async Task ReloadAsync()
    {
        try { Apply(await Task.Run(() => WorldWeatherStore.Read(_world))); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "读取天气失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private void Apply(BedrockWeatherSettings s) { _rain.Value=s.RainLevel;_rainTime.Text=s.RainTime.ToString(CultureInfo.InvariantCulture);_lightning.Value=s.LightningLevel;_lightningTime.Text=s.LightningTime.ToString(CultureInfo.InvariantCulture);_automatic.IsChecked=s.AutomaticChange;UpdateLabels(); }
    private void UpdateLabels(){_rainValue.Text=$"{_rain.Value*100:0}%";_lightningValue.Text=$"{_lightning.Value*100:0}%";_condition.Text="当前设置："+(_lightning.Value>0.01?"雷暴":_rain.Value>0.01?"下雨":"晴朗");}
    private async Task SaveAsync()
    {
        if (!int.TryParse(_rainTime.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var rainTime) || rainTime < 0 || !int.TryParse(_lightningTime.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var lightningTime) || lightningTime < 0) { MessageBox.Show(this,"天气时间必须是 0～2147483647 的整数。","输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return; }
        var settings = new BedrockWeatherSettings((float)_rain.Value, rainTime, (float)_lightning.Value, lightningTime, _automatic.IsChecked == true);
        try { await _prepare(); await Task.Run(() => WorldWeatherStore.Save(_world, settings)); var msg=$"已应用天气到工作副本：{settings.ConditionName}";_complete(msg);MessageBox.Show(this,msg,"已应用",MessageBoxButton.OK,MessageBoxImage.Information); }
        catch(Exception ex){MessageBox.Show(this,ex.Message,"应用天气失败",MessageBoxButton.OK,MessageBoxImage.Error);}
    }
}

public sealed class TimeEditorWindow : Window
{
    private readonly WorldDocument _world; private readonly Func<Task> _prepare; private readonly Action<string> _complete;
    private readonly TextBox _time=new(); private readonly CheckBox _automatic=new(){Content="时间自动流逝（dodaylightcycle）"}; private readonly TextBlock _summary=new(); private readonly TextBlock _day=new();
    public TimeEditorWindow(WorldDocument world,Func<Task> prepare,Action<string> complete){_world=world;_prepare=prepare;_complete=complete;Title="时间";Width=650;Height=480;WindowStartupLocation=WindowStartupLocation.CenterOwner;ResizeMode=ResizeMode.NoResize;Content=BuildUi();_time.TextChanged+=(_,_)=>UpdateSummary();Loaded+=async(_,_)=>await ReloadAsync();}
    private UIElement BuildUi(){var p=new StackPanel{Margin=new Thickness(18)};_summary.FontSize=20;_summary.FontWeight=FontWeights.SemiBold;_summary.TextWrapping=TextWrapping.Wrap;p.Children.Add(_summary);_day.Foreground=System.Windows.Media.Brushes.DimGray;_day.Margin=new Thickness(0,5,0,12);p.Children.Add(_day);p.Children.Add(FieldRow("游戏 time",_time));_automatic.Margin=new Thickness(0,12,0,12);p.Children.Add(_automatic);p.Children.Add(new TextBlock{Text="快速设定当前天的时间",FontWeight=FontWeights.SemiBold,Margin=new Thickness(0,6,0,6)});var a=new UniformGrid{Columns=3};a.Children.Add(Preset("白天",0));a.Children.Add(Preset("中午",6000));a.Children.Add(Preset("日落",12001));p.Children.Add(a);var b=new UniformGrid{Columns=3};b.Children.Add(Preset("夜晚",13801));b.Children.Add(Preset("午夜",18000));b.Children.Add(Preset("日出",22201));p.Children.Add(b);p.Children.Add(new TextBlock{Text="白天 0～12000；日落 12001～13800；夜晚 13801～22200；日出 22201～23999。24000 等价于下一天 0。",TextWrapping=TextWrapping.Wrap,Foreground=System.Windows.Media.Brushes.DimGray,Margin=new Thickness(0,14,0,12)});var save=new Button{Content="应用",Padding=new Thickness(20,6,20,6),HorizontalAlignment=HorizontalAlignment.Right,IsDefault=true};save.Click+=async(_,_)=>await SaveAsync();p.Children.Add(save);return p;}
    private static UIElement FieldRow(string title,TextBox box){var g=new Grid();g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(160)});g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});g.Children.Add(new TextBlock{Text=title,VerticalAlignment=VerticalAlignment.Center});Grid.SetColumn(box,1);g.Children.Add(box);return g;}
    private Button Preset(string text,long tick){var b=new Button{Content=text,Padding=new Thickness(8,7,8,7),Margin=new Thickness(4)};b.Click+=(_,_)=>ApplyPreset(tick);return b;}
    private void ApplyPreset(long tick){if(!long.TryParse(_time.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var current))return;var day=EnvironmentCommandStore.FloorDivision(current,24000);try{_time.Text=checked(day*24000+tick).ToString(CultureInfo.InvariantCulture);}catch(OverflowException){_summary.Text="该日期已超出 Int64 游戏刻可表示范围。";}}
    private void UpdateSummary(){if(!long.TryParse(_time.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var value)){_summary.Text="请输入 Int64 游戏刻";_day.Text=string.Empty;return;}_summary.Text=EnvironmentCommandStore.DaytimeSummary(value);_day.Text=$"day={EnvironmentCommandStore.FloorDivision(value,24000)} · gametime={value}";}
    private async Task ReloadAsync(){try{var s=await Task.Run(()=>WorldTimeStore.Read(_world));_time.Text=s.Time.ToString(CultureInfo.InvariantCulture);_automatic.IsChecked=s.AutomaticProgression;UpdateSummary();}catch(Exception ex){MessageBox.Show(this,ex.Message,"读取时间失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
    private async Task SaveAsync(){if(!long.TryParse(_time.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var time)){MessageBox.Show(this,"time 必须是 Int64 整数。","输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return;}var settings=new BedrockTimeSettings(time,_automatic.IsChecked==true);try{await _prepare();await Task.Run(()=>WorldTimeStore.Save(_world,settings));var msg=$"已应用到工作副本：time={time}";_complete(msg);MessageBox.Show(this,msg,"已应用",MessageBoxButton.OK,MessageBoxImage.Information);}catch(Exception ex){MessageBox.Show(this,ex.Message,"应用时间失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
}

public sealed class ExperienceEditorWindow : Window
{
    private readonly WorldDocument _world; private readonly Func<Task> _prepare; private readonly Action<string> _complete; private readonly DataGrid _grid=new(); private readonly TextBlock _status=new(); private IReadOnlyList<PlayerExperienceRecord> _records=[];
    public ExperienceEditorWindow(WorldDocument world,Func<Task> prepare,Action<string> complete){_world=world;_prepare=prepare;_complete=complete;Title="经验";Width=980;Height=620;MinWidth=760;MinHeight=480;WindowStartupLocation=WindowStartupLocation.CenterOwner;Content=BuildUi();Loaded+=async(_,_)=>await ReloadAsync();}
    private UIElement BuildUi(){var root=new Grid{Margin=new Thickness(10)};root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});root.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});root.Children.Add(new TextBlock{Text="双击玩家修改经验。基岩版实际保存 PlayerLevel 与 PlayerLevelProgress；总经验由等级曲线换算。",TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,0,0,8)});_grid.AutoGenerateColumns=false;_grid.IsReadOnly=true;_grid.CanUserAddRows=false;_grid.RowHeaderWidth=0;_grid.Columns.Add(new DataGridTextColumn{Header="玩家",Binding=new Binding("Player.DisplayName"),Width=220});_grid.Columns.Add(new DataGridTextColumn{Header="UniqueID",Binding=new Binding(nameof(PlayerExperienceRecord.UniqueId)),Width=160});_grid.Columns.Add(new DataGridTextColumn{Header="总经验",Binding=new Binding("Experience.Total"),Width=150});_grid.Columns.Add(new DataGridTextColumn{Header="等级",Binding=new Binding("Experience.Level"),Width=100});_grid.Columns.Add(new DataGridTextColumn{Header="进度",Binding=new Binding("Experience.Progress"),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});_grid.MouseDoubleClick+=(_,e)=>{if(e.ChangedButton==MouseButton.Left&&_grid.SelectedItem is PlayerExperienceRecord r){var w=new PlayerExperienceEditWindow(_world,r,_prepare,msg=>{_complete(msg);_ = ReloadAsync();}){Owner=this};w.ShowDialog();}};Grid.SetRow(_grid,1);root.Children.Add(_grid);_status.Foreground=System.Windows.Media.Brushes.DimGray;_status.Margin=new Thickness(0,8,0,0);Grid.SetRow(_status,2);root.Children.Add(_status);return root;}
    private async Task ReloadAsync(){try{_status.Text="正在读取玩家经验…";_records=await Task.Run(()=>{using var db=_world.OpenDatabase(true);return WorldExperienceStore.Records(db);});_grid.ItemsSource=_records;_status.Text=$"{_records.Count:N0} 个玩家。";}catch(Exception ex){_status.Text="读取失败："+ex.Message;}}
}

public sealed class PlayerExperienceEditWindow : Window
{
    private readonly WorldDocument _world;private readonly PlayerExperienceRecord _record;private readonly Func<Task> _prepare;private readonly Action<string> _complete;private readonly TextBox _total=new();private readonly TextBox _level=new();private readonly Slider _progress=new(){Minimum=0,Maximum=1,TickFrequency=.001};private readonly TextBlock _progressText=new();private bool _sync;private bool _totalSource;
    public PlayerExperienceEditWindow(WorldDocument world,PlayerExperienceRecord record,Func<Task> prepare,Action<string> complete){_world=world;_record=record;_prepare=prepare;_complete=complete;Title=record.Player.DisplayName;Width=620;Height=430;WindowStartupLocation=WindowStartupLocation.CenterOwner;ResizeMode=ResizeMode.NoResize;Content=BuildUi();Apply(record.Experience);_total.TextChanged+=(_,_)=>TotalChanged();_level.TextChanged+=(_,_)=>LevelChanged();_progress.ValueChanged+=(_,_)=>ProgressChanged();}
    private UIElement BuildUi(){var p=new StackPanel{Margin=new Thickness(18)};var uidText = _record.UniqueId?.ToString(CultureInfo.InvariantCulture) ?? "无UniqueID";p.Children.Add(new TextBlock{Text=$"minecraft:player · UniqueID {uidText}",FontWeight=FontWeights.SemiBold,Margin=new Thickness(0,0,0,12)});p.Children.Add(Field("经验总数",_total));p.Children.Add(Field("经验等级",_level));p.Children.Add(new TextBlock{Text="当前经验条进度",FontWeight=FontWeights.SemiBold,Margin=new Thickness(0,14,0,4)});var g=new Grid();g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(80)});g.Children.Add(_progress);_progressText.TextAlignment=TextAlignment.Right;_progressText.VerticalAlignment=VerticalAlignment.Center;Grid.SetColumn(_progressText,1);g.Children.Add(_progressText);p.Children.Add(g);p.Children.Add(new TextBlock{Text=$"修改总数会自动换算等级/进度；修改等级或进度会同步总数。等级 0～{BedrockPlayerExperience.MaximumLevel}，总经验 0～{BedrockPlayerExperience.MaximumTotal}。",TextWrapping=TextWrapping.Wrap,Foreground=System.Windows.Media.Brushes.DimGray,Margin=new Thickness(0,14,0,12)});var save=new Button{Content="应用",Padding=new Thickness(20,6,20,6),HorizontalAlignment=HorizontalAlignment.Right,IsDefault=true};save.Click+=async(_,_)=>await SaveAsync();p.Children.Add(save);return p;}
    private static UIElement Field(string label,TextBox box){var g=new Grid{Margin=new Thickness(0,5,0,5)};g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(160)});g.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});g.Children.Add(new TextBlock{Text=label,VerticalAlignment=VerticalAlignment.Center});Grid.SetColumn(box,1);g.Children.Add(box);return g;}
    private void Apply(BedrockPlayerExperience x){_sync=true;_total.Text=x.Total.ToString(CultureInfo.InvariantCulture);_level.Text=x.Level.ToString(CultureInfo.InvariantCulture);_progress.Value=x.Progress;_progressText.Text=x.Progress.ToString("0.000",CultureInfo.InvariantCulture);_sync=false;}
    private void TotalChanged(){if(_sync)return;_totalSource=true;if(!long.TryParse(_total.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var value)||value<0||value>BedrockPlayerExperience.MaximumTotal)return;var x=BedrockPlayerExperience.FromTotal(value);_sync=true;_level.Text=x.Level.ToString(CultureInfo.InvariantCulture);_progress.Value=x.Progress;_progressText.Text=x.Progress.ToString("0.000",CultureInfo.InvariantCulture);_sync=false;}
    private void LevelChanged(){if(_sync)return;_totalSource=false;SyncTotal();}
    private void ProgressChanged(){_progressText.Text=_progress.Value.ToString("0.000",CultureInfo.InvariantCulture);if(_sync)return;_totalSource=false;SyncTotal();}
    private void SyncTotal(){if(!int.TryParse(_level.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var level)||level<0||level>BedrockPlayerExperience.MaximumLevel)return;var x=new BedrockPlayerExperience(level,(float)_progress.Value).Bounded();_sync=true;_total.Text=x.Total.ToString(CultureInfo.InvariantCulture);_sync=false;}
    private async Task SaveAsync(){BedrockPlayerExperience experience;if(_totalSource){if(!long.TryParse(_total.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var total)||total<0||total>BedrockPlayerExperience.MaximumTotal){MessageBox.Show(this,$"经验总数必须是 0～{BedrockPlayerExperience.MaximumTotal} 的整数。","输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return;}experience=BedrockPlayerExperience.FromTotal(total);}else{if(!int.TryParse(_level.Text.Trim(),NumberStyles.Integer,CultureInfo.InvariantCulture,out var level)||level<0||level>BedrockPlayerExperience.MaximumLevel){MessageBox.Show(this,$"经验等级必须是 0～{BedrockPlayerExperience.MaximumLevel} 的整数。","输入错误",MessageBoxButton.OK,MessageBoxImage.Warning);return;}experience=new BedrockPlayerExperience(level,(float)_progress.Value).Bounded();}try{await _prepare();await Task.Run(()=>{using var db=_world.OpenDatabase(false);WorldExperienceStore.Save(db,_record.Player,experience);});var msg=$"已应用到工作副本：{_record.Player.DisplayName}：总经验 {experience.Total}，等级 {experience.Level}，进度 {experience.Progress:0.000}";_complete(msg);MessageBox.Show(this,msg,"已应用",MessageBoxButton.OK,MessageBoxImage.Information);DialogResult=true;}catch(Exception ex){MessageBox.Show(this,ex.Message,"应用经验失败",MessageBoxButton.OK,MessageBoxImage.Error);}}
}
