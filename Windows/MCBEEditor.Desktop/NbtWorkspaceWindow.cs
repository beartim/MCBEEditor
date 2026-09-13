using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.LevelDB;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;
using Microsoft.Win32;

namespace MCBEEditor.Desktop;

public enum NbtWorkspaceKind
{
    Players,
    Villages,
    Structures,
    Metadata
}

public sealed class NbtWorkspaceRow : INotifyPropertyChanged
{
    private bool _viewed;

    public required string StableId { get; init; }
    public required string Category { get; init; }
    public required string DisplayName { get; init; }
    public required string Detail { get; init; }
    public required string KeyText { get; init; }
    public required object Payload { get; init; }

    public bool Viewed
    {
        get => _viewed;
        set
        {
            if (_viewed == value) return;
            _viewed = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Viewed)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ViewedText)));
        }
    }

    public string ViewedText => Viewed ? "已查看" : string.Empty;
    public event PropertyChangedEventHandler? PropertyChanged;
}

public sealed class NbtWorkspaceWindow : Window, INotifyPropertyChanged
{
    private readonly WorldDocument _world;
    private readonly NbtWorkspaceKind _kind;
    private readonly Func<Task> _prepareMutation;
    private readonly TextBox _search = new();
    private readonly TextBlock _status = new();
    private readonly DataGrid _grid = new();
    private readonly Button _openButton = new();
    private readonly Button _addButton = new();
    private readonly Button _renameButton = new();
    private readonly Button _deleteButton = new();
    private IReadOnlyList<NbtWorkspaceRow> _allRows = Array.Empty<NbtWorkspaceRow>();
    private IReadOnlyList<NbtWorkspaceRow> _rows = Array.Empty<NbtWorkspaceRow>();
    private bool _busy;

    public NbtWorkspaceWindow(WorldDocument world, NbtWorkspaceKind kind, Func<Task> prepareMutation)
    {
        _world = world ?? throw new ArgumentNullException(nameof(world));
        _kind = kind;
        _prepareMutation = prepareMutation ?? throw new ArgumentNullException(nameof(prepareMutation));
        Title = kind switch
        {
            NbtWorkspaceKind.Players => "玩家 NBT",
            NbtWorkspaceKind.Villages => "村庄 NBT",
            NbtWorkspaceKind.Structures => "结构 NBT",
            _ => "元数据 NBT"
        };
        Width = 1120;
        Height = 720;
        MinWidth = 820;
        MinHeight = 520;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        DataContext = this;
        Content = BuildUi();
        Loaded += async (_, _) => await ReloadAsync();
    }

    public IReadOnlyList<NbtWorkspaceRow> Rows
    {
        get => _rows;
        private set
        {
            _rows = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CountText));
        }
    }

    public string CountText => $"显示 {Rows.Count:N0} / {_allRows.Count:N0} 条";
    public event PropertyChangedEventHandler? PropertyChanged;

    private UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(10) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var top = new Grid { Margin = new Thickness(0, 0, 0, 8) };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _search.Margin = new Thickness(0, 0, 8, 0);
        _search.ToolTip = SearchHint();
        _search.TextChanged += (_, _) => ApplyFilter();
        top.Children.Add(_search);
        var refresh = Button("刷新", async (_, _) => await ReloadAsync());
        Grid.SetColumn(refresh, 1);
        top.Children.Add(refresh);
        var count = new TextBlock { Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        count.SetBinding(TextBlock.TextProperty, new Binding(nameof(CountText)));
        Grid.SetColumn(count, 2);
        top.Children.Add(count);
        Grid.SetRow(top, 0);
        root.Children.Add(top);

        _grid.AutoGenerateColumns = false;
        _grid.IsReadOnly = true;
        _grid.SelectionMode = DataGridSelectionMode.Extended;
        _grid.SelectionUnit = DataGridSelectionUnit.FullRow;
        _grid.CanUserAddRows = false;
        _grid.RowHeaderWidth = 0;
        _grid.HeadersVisibility = DataGridHeadersVisibility.Column;
        _grid.MouseDoubleClick += async (_, e) =>
        {
            if (e.ChangedButton == MouseButton.Left && _grid.SelectedItem is NbtWorkspaceRow) await OpenSelectedAsync();
        };
        _grid.SelectionChanged += (_, _) => UpdateActions();
        _grid.Columns.Add(new DataGridTextColumn { Header = "", Binding = new Binding(nameof(NbtWorkspaceRow.ViewedText)), Width = 70 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "类别", Binding = new Binding(nameof(NbtWorkspaceRow.Category)), Width = 130 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "名称", Binding = new Binding(nameof(NbtWorkspaceRow.DisplayName)), Width = 240 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "详情", Binding = new Binding(nameof(NbtWorkspaceRow.Detail)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        _grid.Columns.Add(new DataGridTextColumn { Header = "LevelDB 键", Binding = new Binding(nameof(NbtWorkspaceRow.KeyText)), Width = 300 });
        _grid.SetBinding(ItemsControl.ItemsSourceProperty, new Binding(nameof(Rows)));
        Grid.SetRow(_grid, 1);
        root.Children.Add(_grid);

        var buttons = new WrapPanel { Margin = new Thickness(0, 8, 0, 4) };
        _openButton.Content = "打开 NBT";
        _openButton.Padding = new Thickness(12, 4, 12, 4);
        _openButton.Click += async (_, _) => await OpenSelectedAsync();
        buttons.Children.Add(_openButton);

        _addButton.Content = _kind == NbtWorkspaceKind.Structures ? "导入结构" : "新建元数据";
        _addButton.Padding = new Thickness(12, 4, 12, 4);
        _addButton.Margin = new Thickness(6, 0, 0, 0);
        _addButton.Visibility = _kind is NbtWorkspaceKind.Structures or NbtWorkspaceKind.Metadata ? Visibility.Visible : Visibility.Collapsed;
        _addButton.Click += async (_, _) => await AddAsync();
        buttons.Children.Add(_addButton);

        _renameButton.Content = "重命名";
        _renameButton.Padding = new Thickness(12, 4, 12, 4);
        _renameButton.Margin = new Thickness(6, 0, 0, 0);
        _renameButton.Visibility = _kind is NbtWorkspaceKind.Structures or NbtWorkspaceKind.Metadata ? Visibility.Visible : Visibility.Collapsed;
        _renameButton.Click += async (_, _) => await RenameSelectedAsync();
        buttons.Children.Add(_renameButton);

        _deleteButton.Content = "删除";
        _deleteButton.Padding = new Thickness(12, 4, 12, 4);
        _deleteButton.Margin = new Thickness(6, 0, 0, 0);
        _deleteButton.Visibility = _kind is NbtWorkspaceKind.Structures or NbtWorkspaceKind.Metadata ? Visibility.Visible : Visibility.Collapsed;
        _deleteButton.Click += async (_, _) => await DeleteSelectedAsync();
        buttons.Children.Add(_deleteButton);

        var copyKey = Button("复制键", (_, _) =>
        {
            if (_grid.SelectedItem is NbtWorkspaceRow row) Clipboard.SetText(row.KeyText);
        });
        copyKey.Margin = new Thickness(6, 0, 0, 0);
        buttons.Children.Add(copyKey);

        var export = Button(_kind == NbtWorkspaceKind.Structures ? "导出结构…" : "导出原始 NBT", (_, _) => ExportSelected());
        export.Margin = new Thickness(6, 0, 0, 0);
        buttons.Children.Add(export);

        if (_kind == NbtWorkspaceKind.Metadata)
        {
            var batchRename = Button("批量重命名", async (_, _) => await BatchRenameMetadataAsync());
            batchRename.Margin = new Thickness(6, 0, 0, 0);
            buttons.Children.Add(batchRename);
            var copyKeys = Button("复制所选键", (_, _) => CopySelectedMetadataKeys());
            copyKeys.Margin = new Thickness(6, 0, 0, 0);
            buttons.Children.Add(copyKeys);
        }
        var clearViewed = Button("清除“已查看”", (_, _) =>
        {
            foreach (var row in _allRows) row.Viewed = false;
            ApplyFilter();
        });
        clearViewed.Margin = new Thickness(6, 0, 0, 0);
        buttons.Children.Add(clearViewed);
        Grid.SetRow(buttons, 2);
        root.Children.Add(buttons);

        _status.TextWrapping = TextWrapping.Wrap;
        _status.Margin = new Thickness(0, 5, 0, 0);
        _status.Foreground = System.Windows.Media.Brushes.DimGray;
        Grid.SetRow(_status, 3);
        root.Children.Add(_status);
        UpdateActions();
        return root;
    }

    private static Button Button(string text, RoutedEventHandler click)
    {
        var button = new Button { Content = text, Padding = new Thickness(12, 4, 12, 4) };
        button.Click += click;
        return button;
    }

    private string SearchHint() => _kind switch
    {
        NbtWorkspaceKind.Players => "搜索玩家名称、键或 ID",
        NbtWorkspaceKind.Villages => "搜索村庄、记录类型、键或 NBT 根名称",
        NbtWorkspaceKind.Structures => "搜索结构名称、键、尺寸或原点",
        _ => "搜索元数据名称、LevelDB 键或 NBT 根名称"
    };

    private async Task ReloadAsync()
    {
        if (_busy) return;
        _busy = true;
        _status.Text = "正在读取…";
        try
        {
            var oldViewed = _allRows.Where(row => row.Viewed).Select(row => row.StableId).ToHashSet(StringComparer.Ordinal);
            var loaded = await Task.Run(LoadRows);
            foreach (var row in loaded) row.Viewed = oldViewed.Contains(row.StableId);
            _allRows = loaded;
            ApplyFilter();
            _status.Text = StatusAfterLoad(loaded.Count);
        }
        catch (Exception ex)
        {
            _status.Text = "读取失败：" + ex.Message;
            MessageBox.Show(this, ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            _busy = false;
            UpdateActions();
        }
    }

    private IReadOnlyList<NbtWorkspaceRow> LoadRows()
    {
        using var database = _world.OpenDatabase(readOnly: true);
        if (_kind == NbtWorkspaceKind.Players)
        {
            return new PlayerNbtStore(database).Records().Select(record => new NbtWorkspaceRow
            {
                StableId = "player:" + record.KeyText,
                Category = record.IsLocal ? "本机玩家" : "玩家",
                DisplayName = record.DisplayName,
                Detail = $"根 {record.Document.RootName} · {record.RawData.Length:N0} B",
                KeyText = record.KeyText,
                Payload = record
            }).ToArray();
        }
        if (_kind == NbtWorkspaceKind.Villages)
        {
            var scan = new VillageNbtStore(database).ScanRecords();
            return scan.Records.Select(record => new NbtWorkspaceRow
            {
                StableId = "village:" + record.StableId,
                Category = record.VillageDisplayName,
                DisplayName = record.DisplayName,
                Detail = record.DetailText,
                KeyText = record.KeyText,
                Payload = record
            }).ToArray();
        }
        if (_kind == NbtWorkspaceKind.Structures)
        {
            return new StructureNbtStore(database).Records().Select(record => new NbtWorkspaceRow
            {
                StableId = "structure:" + record.KeyText,
                Category = record.Document is null ? "无法解析" : "结构",
                DisplayName = record.DisplayName,
                Detail = record.DetailText,
                KeyText = record.KeyText,
                Payload = record
            }).ToArray();
        }
        return new MetadataNbtStore(database).Records().Select(record => new NbtWorkspaceRow
        {
            StableId = "metadata:" + record.KeyText,
            Category = record.Roots is null ? "无法解析" : "元数据",
            DisplayName = record.DisplayName,
            Detail = record.DetailText,
            KeyText = record.KeyText,
            Payload = record
        }).ToArray();
    }

    private string StatusAfterLoad(int count) => _kind switch
    {
        NbtWorkspaceKind.Villages when count == 0 => "未找到 mVillages 或 VILLAGE_* 记录。",
        NbtWorkspaceKind.Structures when count == 0 => "未找到 structuretemplate 结构记录。",
        NbtWorkspaceKind.Players when count == 0 => "未找到玩家数据键。",
        NbtWorkspaceKind.Metadata when count == 0 => "未找到支持的世界元数据键。",
        _ => $"已读取 {count:N0} 条记录。双击即可进入完整 NBT 编辑器。"
    };

    private void ApplyFilter()
    {
        var query = _search.Text.Trim();
        Rows = query.Length == 0
            ? _allRows
            : _allRows.Where(row =>
                row.DisplayName.Contains(query, StringComparison.OrdinalIgnoreCase)
                || row.Category.Contains(query, StringComparison.OrdinalIgnoreCase)
                || row.KeyText.Contains(query, StringComparison.OrdinalIgnoreCase)
                || row.Detail.Contains(query, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (_grid.SelectedItem is null && Rows.Count > 0) _grid.SelectedItem = Rows[0];
        UpdateActions();
    }

    private void UpdateActions()
    {
        var selected = _grid.SelectedItem is NbtWorkspaceRow;
        _openButton.IsEnabled = selected && !_busy;
        _renameButton.IsEnabled = selected && !_busy;
        _deleteButton.IsEnabled = selected && !_busy;
        _addButton.IsEnabled = !_busy;
    }

    private async Task OpenSelectedAsync()
    {
        if (_grid.SelectedItem is not NbtWorkspaceRow row) return;
        row.Viewed = true;
        switch (row.Payload)
        {
            case PlayerNbtRecord player:
            {
                var protectedFields = new[] { "UniqueID" };
                var editor = new NbtEditorWindow($"玩家 NBT · {player.DisplayName}", player.Document, async edited =>
                {
                    await _prepareMutation();
                    using var database = _world.OpenDatabase(readOnly: false);
                    new PlayerNbtStore(database).Save(player, edited);
                    _status.Text = $"已应用玩家 NBT 到工作副本：{player.DisplayName}";
                }, protectedFields, NbtEncoding.LittleEndian) { Owner = this };
                editor.ShowDialog();
                if (editor.DidSave) await ReloadAsync();
                break;
            }
            case VillageNbtRecord village:
            {
                var editor = new NbtEditorWindow($"{village.VillageDisplayName} · {village.DisplayName}", village.Document, async edited =>
                {
                    await _prepareMutation();
                    using var database = _world.OpenDatabase(readOnly: false);
                    new VillageNbtStore(database).Save(village, edited);
                    _status.Text = $"已应用到工作副本：{village.VillageDisplayName} / {village.DisplayName}";
                }, Array.Empty<string>(), village.Encoding) { Owner = this };
                editor.ShowDialog();
                if (editor.DidSave) await ReloadAsync();
                break;
            }
            case StructureNbtRecord structure:
            {
                if (structure.Document is null)
                {
                    new RawDataWindow(structure.DisplayName, structure.RawData, structure.DecodeError) { Owner = this }.ShowDialog();
                    break;
                }
                var editor = new NbtEditorWindow($"结构 NBT · {structure.DisplayName}", structure.Document, async edited =>
                {
                    await _prepareMutation();
                    using var database = _world.OpenDatabase(readOnly: false);
                    new StructureNbtStore(database).Save(structure, edited);
                    _status.Text = $"已应用结构 NBT 到工作副本：{structure.DisplayName}";
                }, Array.Empty<string>(), structure.Encoding ?? NbtEncoding.LittleEndian, structureName: structure.DisplayName) { Owner = this };
                editor.ShowDialog();
                if (editor.DidSave) await ReloadAsync();
                break;
            }
            case MetadataNbtRecord metadata:
            {
                if (metadata.Roots is null)
                {
                    new RawDataWindow(metadata.DisplayName, metadata.RawData, metadata.DecodeError) { Owner = this }.ShowDialog();
                    break;
                }
                var rootsWindow = new ConsecutiveNbtWindow(metadata.DisplayName, metadata.Roots, async roots =>
                {
                    await _prepareMutation();
                    using var database = _world.OpenDatabase(readOnly: false);
                    var store = new MetadataNbtStore(database);
                    var current = store.Record(metadata.Key) ?? throw new InvalidDataException("元数据记录已不存在，请刷新列表。");
                    store.Save(current, roots);
                    _status.Text = $"已应用元数据到工作副本：{metadata.KeyText}";
                }) { Owner = this };
                rootsWindow.ShowDialog();
                if (rootsWindow.DidSave) await ReloadAsync();
                break;
            }
        }
    }

    private async Task AddAsync()
    {
        if (_kind == NbtWorkspaceKind.Metadata)
        {
            var key = NbtTextPromptWindow.Show(this, "新建元数据", "输入固定元数据键或 map_<ID>：", "map_0");
            if (key is null) return;
            try
            {
                key = MetadataNbtStore.ValidateKeyText(key);
                await _prepareMutation();
                using var database = _world.OpenDatabase(readOnly: false);
                new MetadataNbtStore(database).Create(key, [new NbtDocument(string.Empty, new NbtCompoundValue([]))], overwrite: false);
                await ReloadAsync();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "新建元数据失败", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            return;
        }

        if (_kind != NbtWorkspaceKind.Structures) return;
        try
        {
            var result = await StructureFileDialogs.ImportAsync(this, _world, _prepareMutation);
            if (result.ChangedWorld) await ReloadAsync();
            _status.Text = result.Message;
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "导入结构失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private async Task RenameSelectedAsync()
    {
        if (_grid.SelectedItem is not NbtWorkspaceRow row) return;
        try
        {
            if (row.Payload is StructureNbtRecord structure)
            {
                var name = NbtTextPromptWindow.Show(this, "重命名结构", "输入新的结构名称：", structure.DisplayName);
                if (name is null) return;
                name = StructureNbtStore.NormalizeName(name);
                if (name.Length == 0) throw new InvalidDataException("结构名称不能为空。");
                bool exists;
                using (var database = _world.OpenDatabase(readOnly: true)) exists = new StructureNbtStore(database).Contains(name);
                var overwrite = exists && !StructureNbtStore.KeyForName(name).AsSpan().SequenceEqual(structure.Key);
                if (overwrite && MessageBox.Show(this, $"“{name}”已经存在。继续会用当前结构替换目标结构。", "替换同名结构？", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
                    return;
                await _prepareMutation();
                using (var database = _world.OpenDatabase(readOnly: false)) new StructureNbtStore(database).Rename(structure, name, overwrite);
                await ReloadAsync();
                return;
            }
            if (row.Payload is MetadataNbtRecord metadata)
            {
                var key = NbtTextPromptWindow.Show(this, "重命名元数据键", "只修改 LevelDB 键名，NBT 原始值保持不变：", metadata.KeyText);
                if (key is null) return;
                key = MetadataNbtStore.ValidateKeyText(key);
                bool exists;
                using (var database = _world.OpenDatabase(readOnly: true)) exists = database.Get(Encoding.UTF8.GetBytes(key)) is not null;
                var overwrite = exists && !Encoding.UTF8.GetBytes(key).AsSpan().SequenceEqual(metadata.Key);
                if (overwrite && MessageBox.Show(this, $"“{key}”已经存在。继续会替换目标元数据。", "替换同名元数据？", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
                    return;
                await _prepareMutation();
                using (var database = _world.OpenDatabase(readOnly: false)) new MetadataNbtStore(database).Rename(metadata, key, overwrite);
                await ReloadAsync();
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "重命名失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task DeleteSelectedAsync()
    {
        if (_grid.SelectedItem is not NbtWorkspaceRow row) return;
        var selectedMetadata = _kind == NbtWorkspaceKind.Metadata
            ? _grid.SelectedItems.Cast<NbtWorkspaceRow>().Select(item => item.Payload).OfType<MetadataNbtRecord>().ToArray()
            : Array.Empty<MetadataNbtRecord>();
        var deleteMessage = selectedMetadata.Length > 1
            ? $"确定删除所选 {selectedMetadata.Length} 个元数据记录？\n\n此操作无法撤销。"
            : $"确定删除“{row.DisplayName}”？\n\nLevelDB 键：{row.KeyText}\n此操作无法撤销。";
        if (MessageBox.Show(this, deleteMessage, "确认删除", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
            return;
        try
        {
            await _prepareMutation();
            using var database = _world.OpenDatabase(readOnly: false);
            if (selectedMetadata.Length > 1) new MetadataNbtStore(database).Delete(selectedMetadata);
            else if (row.Payload is StructureNbtRecord structure) new StructureNbtStore(database).Delete(structure);
            else if (row.Payload is MetadataNbtRecord metadata) new MetadataNbtStore(database).Delete(metadata);
            else return;
            await ReloadAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "删除失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void CopySelectedMetadataKeys()
    {
        var records = _grid.SelectedItems.Cast<NbtWorkspaceRow>().Select(row => row.Payload).OfType<MetadataNbtRecord>().ToArray();
        if (records.Length == 0) return;
        Clipboard.SetText(string.Join(Environment.NewLine, records.Select(record => record.KeyText)));
        _status.Text = $"已复制 {records.Length:N0} 个元数据键名。";
    }

    private async Task BatchRenameMetadataAsync()
    {
        var records = _grid.SelectedItems.Cast<NbtWorkspaceRow>().Select(row => row.Payload).OfType<MetadataNbtRecord>().ToArray();
        if (records.Length == 0)
        {
            MessageBox.Show(this, "请先 Ctrl/Shift 选择一个或多个元数据记录。", "批量重命名", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var dialog = new MetadataBatchRenameWindow { Owner = this };
        if (dialog.ShowDialog() != true) return;
        try
        {
            if (dialog.Find.Length == 0 && dialog.Prefix.Length == 0 && dialog.Suffix.Length == 0)
                throw new InvalidDataException("请至少输入查找文本、前缀或后缀之一。");
            var renames = records.Select(record =>
            {
                var middle = dialog.Find.Length == 0 ? record.KeyText : record.KeyText.Replace(dialog.Find, dialog.Replace, StringComparison.Ordinal);
                return new MetadataNbtRename(record, dialog.Prefix + middle + dialog.Suffix);
            }).ToArray();
            foreach (var rename in renames) _ = MetadataNbtStore.ValidateKeyText(rename.NewKeyText);
            var changes = renames.Where(rename => rename.NewKeyText != rename.Record.KeyText).ToArray();
            if (changes.Length == 0) throw new InvalidDataException("当前规则不会改变任何所选元数据键。");
            var preview = string.Join(Environment.NewLine, changes.Take(5).Select(rename => rename.Record.KeyText + " → " + rename.NewKeyText));
            if (changes.Length > 5) preview += $"{Environment.NewLine}…另有 {changes.Length - 5} 项";
            if (MessageBox.Show(this, preview, "确认批量重命名？", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
            await _prepareMutation();
            using (var database = _world.OpenDatabase(readOnly: false)) new MetadataNbtStore(database).RenameBatch(renames);
            await ReloadAsync();
            _status.Text = $"已批量重命名 {changes.Length:N0} 项元数据。";
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "批量重命名失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ExportSelected()
    {
        var selectedRows = _grid.SelectedItems.Cast<NbtWorkspaceRow>().ToArray();
        if (selectedRows.Length == 0 && _grid.SelectedItem is NbtWorkspaceRow single) selectedRows = [single];
        if (selectedRows.Length == 0) return;
        try
        {
            if (_kind == NbtWorkspaceKind.Structures)
            {
                var records = selectedRows.Select(row => (StructureNbtRecord)row.Payload).ToArray();
                if (records.Length == 1)
                {
                    var record = records[0];
                    _status.Text = StructureFileDialogs.ExportSingle(this, record.Document ?? throw new InvalidDataException("结构 NBT 无法解析。"), record.DisplayName).Message;
                }
                else StructureFileDialogs.ExportMany(this, records);
                return;
            }
            if (selectedRows.Length > 1)
            {
                var folder = new OpenFolderDialog { Title = $"选择目录以导出 {selectedRows.Length} 个原始 NBT", Multiselect = false };
                if (folder.ShowDialog(this) != true) return;
                var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var row in selectedRows)
                {
                    var (data, defaultName) = ExportPayload(row);
                    var candidate = defaultName;
                    var stem = Path.GetFileNameWithoutExtension(defaultName);
                    var ext = Path.GetExtension(defaultName);
                    for (var suffix = 2; !used.Add(candidate); suffix++) candidate = stem + "-" + suffix.ToString(CultureInfo.InvariantCulture) + ext;
                    File.WriteAllBytes(Path.Combine(folder.FolderName, candidate), data);
                }
                _status.Text = $"已导出 {selectedRows.Length:N0} 个原始 NBT 文件。";
                return;
            }

            var (singleData, singleName) = ExportPayload(selectedRows[0]);
            var save = new SaveFileDialog
            {
                Title = "导出原始 NBT",
                Filter = "NBT 文件|*.nbt;*.mcstructure|所有文件|*.*",
                FileName = singleName
            };
            if (save.ShowDialog(this) == true) File.WriteAllBytes(save.FileName, singleData);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "导出失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private static (byte[] Data, string DefaultName) ExportPayload(NbtWorkspaceRow row)
        => row.Payload switch
        {
            PlayerNbtRecord player => (player.RawData, SafeFileName(player.DisplayName) + ".nbt"),
            VillageNbtRecord village => (BedrockNbtCodec.Encode(village.Document, village.Encoding), SafeFileName(village.VillageDisplayName + "-" + village.DisplayName) + ".nbt"),
            MetadataNbtRecord metadata => (metadata.RawData, SafeFileName(metadata.KeyText) + ".nbt"),
            _ => throw new InvalidDataException("无法导出所选记录。")
        };

    private static string SafeFileName(string value)
    {
        foreach (var invalid in Path.GetInvalidFileNameChars()) value = value.Replace(invalid, '_');
        return string.IsNullOrWhiteSpace(value) ? "NBT" : value.Trim();
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

internal sealed class MetadataBatchRenameWindow : Window
{
    private readonly TextBox _find = new();
    private readonly TextBox _replace = new();
    private readonly TextBox _prefix = new();
    private readonly TextBox _suffix = new();
    public string Find => _find.Text;
    public string Replace => _replace.Text;
    public string Prefix => _prefix.Text;
    public string Suffix => _suffix.Text;

    public MetadataBatchRenameWindow()
    {
        Title = "批量重命名元数据"; Width = 620; Height = 330; ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new Grid { Margin = new Thickness(14) };
        for (var i = 0; i < 6; i++) root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var note = new TextBlock { Text = "新键名 = 前缀 +（原键名执行区分大小写的查找替换）+ 后缀。所有结果仍必须是固定元数据键或 map_*。", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0,0,0,10) };
        root.Children.Add(note);
        AddField(root, 1, "查找文本（可留空）", _find); AddField(root, 2, "替换为（可留空）", _replace); AddField(root, 3, "前缀（可留空）", _prefix); AddField(root, 4, "后缀（可留空）", _suffix);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0,12,0,0) };
        var cancel = new Button { Content = "取消", Padding = new Thickness(14,5,14,5), IsCancel = true };
        var ok = new Button { Content = "预览并重命名", Padding = new Thickness(14,5,14,5), Margin = new Thickness(8,0,0,0), IsDefault = true };
        ok.Click += (_, _) => { DialogResult = true; Close(); }; buttons.Children.Add(cancel); buttons.Children.Add(ok); Grid.SetRow(buttons, 5); root.Children.Add(buttons);
        Content = root;
    }

    private static void AddField(Grid root, int row, string label, TextBox box)
    {
        var grid = new Grid { Margin = new Thickness(0,3,0,3) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(155) }); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center }); Grid.SetColumn(box, 1); grid.Children.Add(box); Grid.SetRow(grid, row); root.Children.Add(grid);
    }
}

public sealed class ConsecutiveNbtWindow : Window
{
    private readonly Func<IReadOnlyList<ConsecutiveNbtRecord>, Task> _saveAsync;
    private readonly DataGrid _grid = new();
    private readonly TextBox _search = new();
    private readonly TextBlock _status = new();
    private List<ConsecutiveNbtRecord> _roots;
    private IReadOnlyList<RootRow> _shown = Array.Empty<RootRow>();
    public bool DidSave { get; private set; }

    private sealed record RootRow(int Index, string Name, string Type, string Summary, string Encoding, ConsecutiveNbtRecord Record)
    {
        public string DisplayIndex => Index.ToString(CultureInfo.InvariantCulture);
    }

    public ConsecutiveNbtWindow(string title, IReadOnlyList<ConsecutiveNbtRecord> roots, Func<IReadOnlyList<ConsecutiveNbtRecord>, Task> saveAsync)
    {
        Title = title + " · NBT 根标签";
        Width = 900;
        Height = 620;
        MinWidth = 700;
        MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        _roots = roots.Select(record => record with { Document = new NbtDocument(record.Document.RootName, NbtDocumentTools.DeepClone(record.Document.Root)) }).ToList();
        _saveAsync = saveAsync;
        Content = BuildUi();
        Rebuild();
    }

    private UIElement BuildUi()
    {
        var root = new Grid { Margin = new Thickness(10) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        _search.ToolTip = "搜索根标签名称或内部 NBT 名称/值/类型";
        _search.TextChanged += (_, _) => Rebuild();
        Grid.SetRow(_search, 0);
        root.Children.Add(_search);

        _grid.AutoGenerateColumns = false;
        _grid.IsReadOnly = true;
        _grid.CanUserAddRows = false;
        _grid.RowHeaderWidth = 0;
        _grid.SelectionMode = DataGridSelectionMode.Extended;
        _grid.Columns.Add(new DataGridTextColumn { Header = "#", Binding = new Binding(nameof(RootRow.DisplayIndex)), Width = 55 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "根名称", Binding = new Binding(nameof(RootRow.Name)), Width = 220 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "类型", Binding = new Binding(nameof(RootRow.Type)), Width = 110 });
        _grid.Columns.Add(new DataGridTextColumn { Header = "摘要", Binding = new Binding(nameof(RootRow.Summary)), Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        _grid.Columns.Add(new DataGridTextColumn { Header = "编码", Binding = new Binding(nameof(RootRow.Encoding)), Width = 150 });
        _grid.MouseDoubleClick += (_, e) =>
        {
            if (e.ChangedButton == MouseButton.Left) OpenSelected();
        };
        Grid.SetRow(_grid, 1);
        root.Children.Add(_grid);

        var buttons = new WrapPanel { Margin = new Thickness(0, 8, 0, 0) };
        buttons.Children.Add(ActionButton("打开", (_, _) => OpenSelected()));
        buttons.Children.Add(ActionButton("新增根 Compound", async (_, _) => await AddRootAsync()));
        buttons.Children.Add(ActionButton("删除所选根", async (_, _) => await DeleteSelectedAsync()));
        buttons.Children.Add(ActionButton("导出全部", (_, _) => ExportAll()));
        Grid.SetRow(buttons, 2);
        root.Children.Add(buttons);

        _status.Foreground = System.Windows.Media.Brushes.DimGray;
        _status.Margin = new Thickness(0, 7, 0, 0);
        Grid.SetRow(_status, 3);
        root.Children.Add(_status);
        return root;
    }

    private static Button ActionButton(string text, RoutedEventHandler handler)
    {
        var button = new Button { Content = text, Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(0, 0, 6, 0) };
        button.Click += handler;
        return button;
    }

    private void Rebuild()
    {
        var query = _search.Text.Trim();
        var rows = _roots.Select((record, index) => new RootRow(index,
            string.IsNullOrEmpty(record.Document.RootName) ? "<root>" : record.Document.RootName,
            record.Document.Root.Type.ToString(), record.Document.Root.Summary, record.Encoding.ToString(), record)).ToArray();
        if (query.Length != 0)
        {
            rows = rows.Where(row => row.Name.Contains(query, StringComparison.OrdinalIgnoreCase)
                || row.Type.Contains(query, StringComparison.OrdinalIgnoreCase)
                || NbtDocumentTools.Search(row.Record.Document, query, 1).Count > 0).ToArray();
        }
        _shown = rows;
        _grid.ItemsSource = _shown;
        _status.Text = $"NBT 根标签 {_roots.Count:N0} 个；当前显示 {_shown.Count:N0} 个。";
        if (_grid.SelectedItem is null && _shown.Count > 0) _grid.SelectedItem = _shown[0];
    }

    private void OpenSelected()
    {
        if (_grid.SelectedItem is not RootRow row) return;
        var editor = new NbtEditorWindow($"{Title} · #{row.Index}", row.Record.Document, async edited =>
        {
            _roots[row.Index] = _roots[row.Index] with { Document = edited };
            await SaveAsync();
        }, Array.Empty<string>(), row.Record.Encoding) { Owner = this };
        editor.ShowDialog();
        if (editor.DidSave) Rebuild();
    }

    private async Task AddRootAsync()
    {
        var name = NbtTextPromptWindow.Show(this, "新增 NBT 根标签", "根标签名称（可留空）：", string.Empty);
        if (name is null) return;
        _roots.Add(new ConsecutiveNbtRecord(new NbtDocument(name, new NbtCompoundValue([])), [], NbtEncoding.LittleEndian));
        if (!await TrySaveAsync())
        {
            _roots.RemoveAt(_roots.Count - 1);
            return;
        }
        Rebuild();
    }

    private async Task DeleteSelectedAsync()
    {
        var indexes = _grid.SelectedItems.Cast<RootRow>().Select(row => row.Index).Distinct().OrderByDescending(index => index).ToArray();
        if (indexes.Length == 0) return;
        if (_roots.Count - indexes.Length < 1)
        {
            MessageBox.Show(this, "至少需要保留一个 NBT 根标签。", Title, MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (MessageBox.Show(this, $"删除所选 {indexes.Length} 个 NBT 根标签？", "确认删除", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
            return;
        var backup = _roots.ToList();
        foreach (var index in indexes) _roots.RemoveAt(index);
        if (!await TrySaveAsync())
        {
            _roots = backup;
            return;
        }
        Rebuild();
    }

    private async Task SaveAsync()
    {
        await _saveAsync(_roots);
        DidSave = true;
        _status.Text = $"已保存 {_roots.Count:N0} 个 NBT 根标签。";
    }

    private async Task<bool> TrySaveAsync()
    {
        try
        {
            await SaveAsync();
            return true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "应用 NBT 失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return false;
        }
    }

    private void ExportAll()
    {
        var save = new SaveFileDialog { Title = "导出连续 NBT", Filter = "NBT 文件 (*.nbt)|*.nbt|所有文件|*.*", FileName = "metadata.nbt" };
        if (save.ShowDialog(this) == true) File.WriteAllBytes(save.FileName, ConsecutiveNbtCodec.Encode(_roots));
    }
}

public sealed class RawDataWindow : Window
{
    public RawDataWindow(string title, byte[] data, string? note = null)
    {
        Title = title + " · 原始值";
        Width = 900;
        Height = 650;
        MinWidth = 650;
        MinHeight = 450;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var grid = new Grid { Margin = new Thickness(10) };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var info = new TextBlock
        {
            Text = (string.IsNullOrWhiteSpace(note) ? "无法解析为支持的 NBT。" : note) + $" · {data.Length:N0} B",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 8)
        };
        grid.Children.Add(info);
        var box = new TextBox
        {
            FontFamily = new System.Windows.Media.FontFamily("Consolas"),
            IsReadOnly = true,
            AcceptsReturn = true,
            AcceptsTab = true,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            TextWrapping = TextWrapping.NoWrap,
            Text = HexDump(data)
        };
        Grid.SetRow(box, 1);
        grid.Children.Add(box);
        Content = grid;
    }

    private static string HexDump(byte[] data)
    {
        var displayLength = Math.Min(data.Length, 2 * 1024 * 1024);
        var builder = new StringBuilder(displayLength * 4 / 3);
        for (var offset = 0; offset < displayLength; offset += 16)
        {
            var count = Math.Min(16, displayLength - offset);
            builder.Append(offset.ToString("X8", CultureInfo.InvariantCulture)).Append(" ");
            for (var i = 0; i < 16; i++)
            {
                if (i < count) builder.Append(data[offset + i].ToString("X2", CultureInfo.InvariantCulture));
                else builder.Append(" ");
                builder.Append(i == 7 ? " " : " ");
            }
            builder.Append(" | ");
            for (var i = 0; i < count; i++)
            {
                var value = data[offset + i];
                builder.Append(value is >= 0x20 and <= 0x7E ? (char)value : '.');
            }
            builder.AppendLine();
        }
        if (displayLength < data.Length) builder.AppendLine($"… 已截断显示，完整值共 {data.Length:N0} B。");
        return builder.ToString();
    }
}

public sealed class NbtTextPromptWindow : Window
{
    private readonly TextBox _input = new();
    public string? Result { get; private set; }

    private NbtTextPromptWindow(string title, string message, string initial)
    {
        Title = title;
        Width = 520;
        Height = 190;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new Grid { Margin = new Thickness(14) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap });
        _input.Text = initial;
        _input.Margin = new Thickness(0, 10, 0, 12);
        _input.SelectAll();
        Grid.SetRow(_input, 1);
        root.Children.Add(_input);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var ok = new Button { Content = "确定", IsDefault = true, Padding = new Thickness(14, 4, 14, 4) };
        ok.Click += (_, _) => { Result = _input.Text; DialogResult = true; };
        buttons.Children.Add(ok);
        var cancel = new Button { Content = "取消", IsCancel = true, Padding = new Thickness(14, 4, 14, 4), Margin = new Thickness(6, 0, 0, 0) };
        buttons.Children.Add(cancel);
        Grid.SetRow(buttons, 2);
        root.Children.Add(buttons);
        Content = root;
        Loaded += (_, _) => _input.Focus();
    }

    public static string? Show(Window owner, string title, string message, string initial)
    {
        var dialog = new NbtTextPromptWindow(title, message, initial) { Owner = owner };
        return dialog.ShowDialog() == true ? dialog.Result : null;
    }
}
