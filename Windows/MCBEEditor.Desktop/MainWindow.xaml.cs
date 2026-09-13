using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.Diagnostics;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.LevelDB;
using MCBEEditor.Core.World;
using Microsoft.Win32;

namespace MCBEEditor.Desktop;

public sealed record CommandOutputLine(string Text, Brush Foreground);

public sealed record MapObjectMarker(WorldObjectRow Row);

public sealed record MapBlockSelection(int Dimension, int X, int Y, int Z, string Name);

public sealed record MapRegionSelection(int Dimension, int MinimumX, int MinimumZ, int MaximumX, int MaximumZ)
{
    public long Area => ((long)MaximumX - MinimumX + 1) * ((long)MaximumZ - MinimumZ + 1);
}

public sealed record MapSpawnerOverlayTag(ChunkPosition Position, HardcodedSpawnerArea Area);
public sealed record MapVillageOverlayTag(VillageMapFeature Feature, VillageMapPointFeature? Point);
public sealed record MapViewportSnapshot(BedrockMapAxis Axis, double WorldHorizontal, double WorldVertical, double PixelsPerBlock);
public sealed record MapViewportWorldBounds(double MinimumHorizontal, double MaximumHorizontal, double MinimumVertical, double MaximumVertical);

public sealed record NbtKeySearchRow(byte[] Key, string KeyText, string Description, int ValueLength, bool Viewed = false)
{
    public string KeyHex => Convert.ToHexString(Key).ToLowerInvariant();
    public string ValueLengthText => ValueLength < 0 ? "—" : $"{ValueLength:N0} B";
    public string ViewedText => Viewed ? "已查看" : string.Empty;
}

public sealed record WorldObjectRow(
    string KindText,
    string DisplayName,
    string Identifier,
    int Dimension,
    double? X,
    double? Y,
    double? Z,
    string SourceText,
    long? UniqueId,
    int? ItemCount,
    PlayerNbtRecord? Player,
    BedrockWorldObject? WorldObject)
{
    public string DimensionText => BedrockDimensionNames.DisplayName(Dimension);
    public string XText => CoordinateText(X);
    public string YText => CoordinateText(Y);
    public string ZText => CoordinateText(Z);
    public string UniqueIdText => UniqueId?.ToString(CultureInfo.InvariantCulture) ?? string.Empty;
    public string ItemCountText => ItemCount?.ToString(CultureInfo.InvariantCulture) ?? string.Empty;
    private static string CoordinateText(double? value)
        => value.HasValue ? (Math.Abs(value.Value - Math.Round(value.Value)) < 0.0000001
            ? Math.Round(value.Value).ToString(CultureInfo.InvariantCulture)
            : value.Value.ToString("0.##", CultureInfo.InvariantCulture)) : string.Empty;
}

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private WorldDocument? _document;
    private PortableWorldWorkspace? _workspace;
    private string? _worldPath;
    private string? _sourceWorldPath;
    private bool _workingCopyDirty;
    private string _worldName = "未打开世界";
    private string _statusText = "可打开 Bedrock 世界文件夹或 .mcworld/ZIP；编辑只发生在程序同级 Cache 工作副本中。";
    private string _databaseStatus = "尚未打开 LevelDB。";
    private IReadOnlyList<BedrockChunkSummary> _allChunks = Array.Empty<BedrockChunkSummary>();
    private IReadOnlyList<BedrockChunkSummary> _chunkRows = Array.Empty<BedrockChunkSummary>();
    private IReadOnlyList<LevelDbBrowserRow> _databaseRows = Array.Empty<LevelDbBrowserRow>();
    private IReadOnlyList<NbtKeySearchRow> _nbtKeyRows = Array.Empty<NbtKeySearchRow>();
    private NbtKeySearchRow? _selectedNbtKeyRow;
    private string _nbtKeyStatusText = "输入 UTF-8 键文本搜索；以 0x 开头可按十六进制键搜索。";
    private readonly HashSet<string> _viewedNbtKeys = new(StringComparer.Ordinal);
    private BedrockChunkSummary? _selectedChunk;
    private bool _databaseBusy;
    private IReadOnlyList<WorldObjectRow> _objectRows = Array.Empty<WorldObjectRow>();
    private IReadOnlyList<WorldObjectRow> _allObjectRows = Array.Empty<WorldObjectRow>();
    private WorldObjectRow? _selectedObjectRow;
    private string _objectStatusText = "尚未扫描玩家/实体。";
    private string _objectScanSummary = string.Empty;
    private IReadOnlyList<MapObjectMarker> _mapObjectMarkers = Array.Empty<MapObjectMarker>();
    private IReadOnlyList<SpawnMapFeature> _spawnMapFeatures = Array.Empty<SpawnMapFeature>();
    private IReadOnlyList<HardcodedSpawnersRecord> _spawnerMapRecords = Array.Empty<HardcodedSpawnersRecord>();
    private IReadOnlyList<VillageMapFeature> _villageMapFeatures = Array.Empty<VillageMapFeature>();
    private MapBlockSelection? _selectedMapBlock;
    private MapSpawnerOverlayTag? _selectedMapSpawner;
    private string? _selectedMapVillageIdentifier;
    private ChunkPosition? _selectedMapChunk;
    private MapRegionSelection? _mapRegionSelection;
    private (int X, int Z)? _mapRegionFirstCorner;
    private bool _mapRegionSelecting;
    private string? _mapSelectionDragEdge;
    private bool _entityTabNeedsInitialScan = true;
    private bool _mapChangingLayerOptions;
    private bool _commandBatchRunning;
    private readonly List<string> _commandHistory = new();
    private int _commandHistoryIndex = -1;
    private string _commandHistoryDraft = string.Empty;

    private BedrockSurfaceRegion? _mapRegion;
    private BedrockCrossSectionRegion? _crossSectionRegion;
    private BedrockMapAxis _mapAxis = BedrockMapAxis.Y;
    private string _mapStatusText = "尚未渲染地图。";
    private string _mapDetailText = "打开世界后自动以本机玩家/维度默认中心渲染；移动和缩放会按可视范围自动续载。";
    private double _mapZoom = 4.0;
    private bool _mapDragging;
    private bool _mapDragMoved;
    private Point _mapDragStart;
    private double _mapDragStartHorizontalOffset;
    private double _mapDragStartVerticalOffset;
    private int _spawnX;
    private int _spawnZ;
    private int _mapCenterY = 63;
    private int _activeMapDimension;
    private int _lastMapRadius = 5;
    private BedrockMapRenderMode _lastMapMode = BedrockMapRenderMode.Surface;
    private int _lastMapDimension;
    private int _lastMapCenterX;
    private int _lastMapCenterZ;
    private int _lastMapCenterY = 63;
    // Windows deliberately spends more memory/LevelDB work than iOS so zoomed-out
    // maps remain crisp much longer before representative sampling begins.
    private const int WindowsMapMaximumSamplesPerAxis = 512;
    private const int WindowsMapMaximumRasterSide = 8192;
    private readonly DispatcherTimer _mapDynamicRenderTimer = new() { Interval = TimeSpan.FromMilliseconds(350) };
    private bool _mapApplyingViewport;
    private double _mapSurfaceInsetX;
    private double _mapSurfaceInsetY;
    private bool _mapDynamicRefreshRunning;
    private long _mapInteractionVersion;
    private int? _mapRenderRadiusOverride;
    private MapViewportSnapshot? _mapViewportRestore;
    private bool _mapPreserveSelectionOnNextRender;
    private BedrockBlockRecord? _mapBlockDetailRecord;
    private bool _mapBlockDetailChangingStorage;
    private bool _mapBlockDetailCollapsed = true;
    private const double MapBlockDetailExpandedWidth = 360.0;
    private const double MapBlockDetailCollapsedWidth = 38.0;
    private readonly Dictionary<int, (int X, int Z)> _mapCenters = new()
    {
        [0] = (0, 0),
        [1] = (0, 0),
        [2] = (0, 0)
    };

    public MainWindow()
    {
        PortablePaths.PreparePersistentDirectories();
        InitializeComponent();
        DataContext = this;
        CommandOutputRows.CollectionChanged += CommandOutputRows_CollectionChanged;
        _mapDynamicRenderTimer.Tick += MapDynamicRenderTimer_Tick;
        BlockTextureOverrideStore.PrepareAndReload();
        BedrockBlockMapColorCatalog.OverrideProvider = BlockTextureOverrideStore.ColorFor;
        try { SharedCommandFileStore.PrepareSharedDirectory(); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    public ObservableCollection<WorldInfoRow> InfoRows { get; } = new();
    public ObservableCollection<CommandOutputLine> CommandOutputRows { get; } = new();
    public bool HasWorld => _document is not null;
    public string WorldPath => _sourceWorldPath ?? string.Empty;

    public string WorldName
    {
        get => _worldName;
        private set { _worldName = value; OnPropertyChanged(); }
    }

    public string StatusText
    {
        get => _statusText;
        private set { _statusText = value; OnPropertyChanged(); }
    }

    public string DatabaseStatus
    {
        get => _databaseStatus;
        private set { _databaseStatus = value; OnPropertyChanged(); }
    }

    public string MapStatusText
    {
        get => _mapStatusText;
        private set { _mapStatusText = value; OnPropertyChanged(); }
    }

    public string MapDetailText
    {
        get => _mapDetailText;
        private set { _mapDetailText = value; OnPropertyChanged(); }
    }

    public string MapZoomText => HasRenderedMap ? $"缩放 {CurrentMapPixelsPerBlock():0.###} px/方块" : $"缩放 {_mapZoom:0.##}×";

    public IReadOnlyList<BedrockChunkSummary> ChunkRows
    {
        get => _chunkRows;
        private set
        {
            _chunkRows = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ChunkCountText));
        }
    }

    public string ChunkCountText
        => _allChunks.Count == 0 ? "0 个区块" : $"显示 {ChunkRows.Count:N0} / {_allChunks.Count:N0} 个区块";

    public IReadOnlyList<LevelDbBrowserRow> DatabaseRows
    {
        get => _databaseRows;
        private set
        {
            _databaseRows = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DatabaseRowCountText));
        }
    }

    public string DatabaseRowCountText => $"{DatabaseRows.Count:N0} 条记录";

    public IReadOnlyList<NbtKeySearchRow> NbtKeyRows
    {
        get => _nbtKeyRows;
        private set { _nbtKeyRows = value; OnPropertyChanged(); }
    }

    public NbtKeySearchRow? SelectedNbtKeyRow
    {
        get => _selectedNbtKeyRow;
        set { _selectedNbtKeyRow = value; OnPropertyChanged(); }
    }

    public string NbtKeyStatusText
    {
        get => _nbtKeyStatusText;
        private set { _nbtKeyStatusText = value; OnPropertyChanged(); }
    }

    public IReadOnlyList<WorldObjectRow> ObjectRows
    {
        get => _objectRows;
        private set { _objectRows = value; OnPropertyChanged(); }
    }

    public WorldObjectRow? SelectedObjectRow
    {
        get => _selectedObjectRow;
        set
        {
            _selectedObjectRow = value;
            OnPropertyChanged();
            if (MapOverlayCanvas is not null && HasRenderedMap) UpdateMapOverlay();
        }
    }

    public string ObjectStatusText
    {
        get => _objectStatusText;
        private set { _objectStatusText = value; OnPropertyChanged(); }
    }

    public BedrockChunkSummary? SelectedChunk
    {
        get => _selectedChunk;
        set { _selectedChunk = value; OnPropertyChanged(); }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private async void OpenWorld_Click(object sender, RoutedEventArgs e)
    {
        if (_commandBatchRunning) return;
        var dialog = new OpenFolderDialog
        {
            Title = "选择 Minecraft Bedrock 世界文件夹",
            Multiselect = false
        };
        if (dialog.ShowDialog(this) == true)
            await OpenWorldSourceAsync(dialog.FolderName);
    }

    private async void OpenWorldArchive_Click(object sender, RoutedEventArgs e)
    {
        if (_commandBatchRunning) return;
        var dialog = new OpenFileDialog
        {
            Title = "选择 Minecraft Bedrock 世界文件",
            Filter = "Bedrock 世界 (*.mcworld;*.zip)|*.mcworld;*.zip|所有文件 (*.*)|*.*",
            Multiselect = false
        };
        if (dialog.ShowDialog(this) == true)
            await OpenWorldSourceAsync(dialog.FileName);
    }

    private void OpenStandaloneNbt_Click(object sender, RoutedEventArgs e)
    {
        if (_commandBatchRunning) return;
        var dialog = new OpenFileDialog
        {
            Title = "选择 NBT / mcstructure / JSON 文件",
            Filter = "NBT / mcstructure / JSON|*.nbt;*.mcstructure;*.json|NBT|*.nbt|mcstructure|*.mcstructure|JSON|*.json|所有文件|*.*",
            Multiselect = false
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var file = StandaloneNbtFileCodec.Decode(File.ReadAllBytes(dialog.FileName), dialog.FileName);
            var window = new StandaloneNbtFileWindow(file) { Owner = this };
            window.ShowDialog();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "无法打开 NBT 文件", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void AboutLicense_Click(object sender, RoutedEventArgs e)
    {
        new AboutLicenseWindow { Owner = this }.ShowDialog();
    }

    private void Window_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = TryGetDroppedWorld(e.Data, out _) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private async void Window_Drop(object sender, DragEventArgs e)
    {
        if (_commandBatchRunning) return;
        if (TryGetDroppedWorld(e.Data, out var path))
            await OpenWorldSourceAsync(path!);
    }

    private static bool TryGetDroppedWorld(IDataObject data, out string? path)
    {
        path = null;
        if (!data.GetDataPresent(DataFormats.FileDrop)) return false;
        if (data.GetData(DataFormats.FileDrop) is not string[] items || items.Length != 1) return false;
        var candidate = items[0];
        if (Directory.Exists(candidate) && WorldDocument.LooksLikeBedrockWorld(candidate))
        {
            path = candidate;
            return true;
        }
        if (File.Exists(candidate))
        {
            var extension = Path.GetExtension(candidate);
            if (extension.Equals(".mcworld", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".zip", StringComparison.OrdinalIgnoreCase))
            {
                path = candidate;
                return true;
            }
        }
        return false;
    }

    private bool ConfirmDiscardWorkingCopy(string action)
    {
        if (!_workingCopyDirty) return true;
        return MessageBox.Show(
            this,
            $"当前工作副本包含尚未通过 .mcworld 导出的修改。{action}会丢弃这些修改。\n\n是否继续？",
            "未导出的修改",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning) == MessageBoxResult.Yes;
    }

    private void MarkWorkingCopyDirty()
    {
        _workingCopyDirty = true;
    }

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (_commandBatchRunning)
        {
            e.Cancel = true;
            MessageBox.Show(this, "Command.txt 正在执行，完成前不能关闭程序。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_workingCopyDirty && !ConfirmDiscardWorkingCopy("关闭程序"))
        {
            e.Cancel = true;
            return;
        }
        _workspace?.Dispose();
        _workspace = null;
    }

    private async Task OpenWorldSourceAsync(string sourcePath)
    {
        if (!ConfirmDiscardWorkingCopy("打开其它世界")) return;
        PortableWorldWorkspace? workspace = null;
        try
        {
            StatusText = "正在复制/解压到临时工作副本…";
            workspace = await Task.Run(() => PortableWorldWorkspace.Create(PortablePaths.WorldCachePath, sourcePath));
            var document = new WorldDocument(workspace.WorkingRootPath, MarkWorkingCopyDirty);
            var oldWorkspace = _workspace;
            _workspace = workspace;
            workspace = null;
            _document = document;
            _worldPath = document.RootPath;
            _sourceWorldPath = _workspace.SourcePath;
            _workingCopyDirty = false;
            oldWorkspace?.Dispose();
            await LoadWorkingDocumentAsync(document);
        }
        catch (Exception ex)
        {
            workspace?.Dispose();
            StatusText = "打开世界失败。";
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task LoadWorkingDocumentAsync(WorldDocument document)
    {
        StatusText = "正在读取临时工作副本的 level.dat 与世界信息…";
        var rows = await Task.Run(() => new WorldInfoService().Inspect(document));

        _document = document;
        _worldPath = document.RootPath;
        DatabaseRows = Array.Empty<LevelDbBrowserRow>();
        NbtKeyRows = Array.Empty<NbtKeySearchRow>();
        SelectedNbtKeyRow = null;
        _viewedNbtKeys.Clear();
        NbtKeyStatusText = "输入 UTF-8 键文本搜索；以 0x 开头可按十六进制键搜索。";
        CommandInput?.Clear();
        CommandOutputRows.Clear();
        _allObjectRows = Array.Empty<WorldObjectRow>();
        ObjectRows = Array.Empty<WorldObjectRow>();
        SelectedObjectRow = null;
        _objectScanSummary = string.Empty;
        ObjectStatusText = "尚未扫描实体/方块实体。";
        _entityTabNeedsInitialScan = true;
        _mapObjectMarkers = Array.Empty<MapObjectMarker>();
        _selectedMapBlock = null;
        InfoRows.Clear();
        foreach (var row in rows)
        {
            if (row.Title == "世界目录")
            {
                InfoRows.Add(new WorldInfoRow("源世界", _sourceWorldPath ?? string.Empty));
                InfoRows.Add(new WorldInfoRow("临时工作副本", document.RootPath));
            }
            else
            {
                InfoRows.Add(row);
            }
        }
        WorldName = rows.FirstOrDefault(row => row.Title == "名称")?.Value ?? Path.GetFileName(document.RootPath);
        ResetMapForWorld(document);
        OnPropertyChanged(nameof(WorldPath));
        OnPropertyChanged(nameof(HasWorld));

        StatusText = $"已打开：{WorldName}。源文件保持只读，正在扫描临时工作副本 LevelDB…";
        await LoadDatabaseAsync();
        await InitializeLocalPlayerCenterAsync();
        await HandleSharedCommandFileAsync();
        MapViewportLayout.UpdateLayout();
        MapScrollViewer.UpdateLayout();
        if (!_databaseBusy)
            await RenderMapAsync();
        if (MainTabs.SelectedItem is TabItem currentTab && string.Equals(currentTab.Header?.ToString(), "实体", StringComparison.Ordinal))
            await EnsureEntityTabInitialScanAsync();
    }

    private async void ReloadDatabase_Click(object sender, RoutedEventArgs e)
        => await LoadDatabaseAsync();

    private async Task LoadDatabaseAsync()
    {
        if (_document is null || _databaseBusy) return;
        _databaseBusy = true;
        DatabaseStatus = $"正在扫描：{_document.DatabasePath}";
        StatusText = "正在枚举 Bedrock LevelDB 区块键…";
        _allChunks = Array.Empty<BedrockChunkSummary>();
        ChunkRows = Array.Empty<BedrockChunkSummary>();
        SelectedChunk = null;

        try
        {
            var document = _document;
            var chunks = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: true);
                return new BedrockChunkStore(database).ListChunks();
            });

            _allChunks = chunks;
            ApplyChunkFilter(showErrors: false);
            DatabaseStatus = $"LevelDB 连接成功 · 已识别 {_allChunks.Count:N0} 个区块 · 临时工作副本可编辑";
            StatusText = $"{WorldName}：level.dat + LevelDB 已读取，共 {_allChunks.Count:N0} 个区块。";
        }
        catch (Exception ex)
        {
            _allChunks = Array.Empty<BedrockChunkSummary>();
            ChunkRows = Array.Empty<BedrockChunkSummary>();
            DatabaseStatus = "LevelDB 未能打开：" + ex.Message;
            StatusText = "level.dat 已读取，但 LevelDB 未连接。";
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private void ApplyChunkFilter_Click(object sender, RoutedEventArgs e)
        => ApplyChunkFilter(showErrors: true);

    private void ResetChunkFilter_Click(object sender, RoutedEventArgs e)
    {
        DimensionFilter.SelectedIndex = 0;
        ChunkXFilter.Clear();
        ChunkZFilter.Clear();
        ApplyChunkFilter(showErrors: false);
    }

    private void ApplyChunkFilter(bool showErrors)
    {
        int? dimension = null;
        if (DimensionFilter.SelectedItem is ComboBoxItem item && item.Tag is string tag && tag != "all")
            dimension = int.Parse(tag);

        if (!TryOptionalInt(ChunkXFilter.Text, "区块 X", showErrors, out var x)) return;
        if (!TryOptionalInt(ChunkZFilter.Text, "区块 Z", showErrors, out var z)) return;

        IEnumerable<BedrockChunkSummary> query = _allChunks;
        if (dimension.HasValue) query = query.Where(chunk => chunk.Position.Dimension == dimension.Value);
        if (x.HasValue) query = query.Where(chunk => chunk.X == x.Value);
        if (z.HasValue) query = query.Where(chunk => chunk.Z == z.Value);
        ChunkRows = query.ToArray();
        SelectedChunk = ChunkRows.FirstOrDefault();
    }

    private bool TryOptionalInt(string text, string fieldName, bool showErrors, out int? value)
    {
        value = null;
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return true;
        if (int.TryParse(trimmed, out var parsed))
        {
            value = parsed;
            return true;
        }
        if (showErrors)
            MessageBox.Show(this, $"{fieldName} 必须为 32 位整数。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Warning);
        return false;
    }

    private async void InspectChunk_Click(object sender, RoutedEventArgs e)
        => await InspectSelectedChunkAsync();

    private async void ChunkGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (ChunkGrid.SelectedItem is BedrockChunkSummary)
            await InspectSelectedChunkAsync();
    }

    private async Task InspectSelectedChunkAsync()
    {
        if (_document is null || SelectedChunk is null)
        {
            MessageBox.Show(this, "请先在区块列表中选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;

        _databaseBusy = true;
        var selected = SelectedChunk;
        StatusText = $"正在读取 {selected.DimensionText} ({selected.X}, {selected.Z})…";
        try
        {
            var document = _document;
            var result = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: true);
                var store = new BedrockChunkStore(database);
                return (Records: store.RecordsAt(selected.Position, includeValues: true),
                        SubChunks: store.DecodeSubChunks(selected.Position),
                        Generation: store.GenerationDescription(store.SummaryAt(selected.Position)));
            });

            var text = new StringBuilder();
            text.AppendLine($"维度：{selected.DimensionText} ({selected.Position.Dimension})");
            text.AppendLine($"区块：X={selected.X}, Z={selected.Z}");
            text.AppendLine($"生成情况：{result.Generation}");
            text.AppendLine($"记录数：{result.Records.Count}");
            text.AppendLine($"SubChunk：{result.SubChunks.Count}");
            text.AppendLine();

            if (result.SubChunks.Count > 0)
            {
                text.AppendLine("SubChunk 解码：");
                foreach (var subChunk in result.SubChunks)
                {
                    var y = subChunk.YIndex?.ToString() ?? "?";
                    var mode = subChunk.IsRawPreservedUnknownVersion ? "未知版本/原样保留" :
                               subChunk.IsLegacyNumeric ? "Legacy numeric" : $"storage={subChunk.Storages.Count}";
                    text.AppendLine($" Y={y,-4} v{subChunk.Version,-3} {mode}");
                }
                text.AppendLine();
            }

            text.AppendLine("LevelDB 记录：");
            foreach (var record in result.Records)
            {
                var length = record.ValueLength >= 0 ? $"{record.ValueLength:N0} B" : "未读取值";
                text.AppendLine($" {record.DisplayName} · {length}");
                text.AppendLine($" key={Convert.ToHexString(record.Key)}");
            }

            MessageBox.Show(this, text.ToString(), $"区块 {selected.DimensionText} ({selected.X}, {selected.Z})",
                MessageBoxButton.OK, MessageBoxImage.Information);
            StatusText = $"已读取 {selected.DimensionText} ({selected.X}, {selected.Z}) 的 {result.Records.Count} 条记录。";
        }
        catch (Exception ex)
        {
            StatusText = "读取区块失败。";
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private void CopyChunk_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null || SelectedChunk is null)
        {
            MessageBox.Show(this, "请先选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var world = _document;
        var window = new ChunkCopyWindow(world, SelectedChunk.Position, () => PrepareWorldMutationAsync(world), (message, destination) =>
        {
            StatusText = message;
            _ = RefreshAfterChunkMutationAsync(destination);
        }) { Owner = this };
        window.ShowDialog();
    }

    private void SearchReplaceChunk_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null || SelectedChunk is null)
        {
            MessageBox.Show(this, "请先选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var world = _document;
        var window = new RegionReplaceWindow(world, ChunkRegion(SelectedChunk.Position), () => PrepareWorldMutationAsync(world), message =>
        {
            StatusText = message;
            _ = RefreshAfterChunkMutationAsync(SelectedChunk?.Position);
        }) { Owner = this };
        window.ShowDialog();
    }

    private void EditChunkHardcodedSpawners_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null || SelectedChunk is null)
        {
            MessageBox.Show(this, "请先选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var world = _document;
        var position = SelectedChunk.Position;
        var window = new HardcodedSpawnersEditorWindow(world, position, () => PrepareWorldMutationAsync(world), message =>
        {
            StatusText = message;
            _ = RefreshAfterChunkMutationAsync(position);
        }) { Owner = this };
        window.ShowDialog();
    }

    private void BatchChunkOperations_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null) return;
        var chunks = SelectedChunkPositions();
        if (chunks.Count == 0)
        {
            MessageBox.Show(this, "请使用 Ctrl/Shift 选择一个或多个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var dialog = new ChunkBatchActionWindow(chunks.Count) { Owner = this };
        if (dialog.ShowDialog() != true || dialog.SelectedAction is not { } action) return;
        var world = _document;
        switch (action)
        {
            case ChunkBatchAction.SearchReplace:
            {
                var selections = chunks.Select(ChunkRegion).ToArray();
                new RegionReplaceWindow(world, selections, () => PrepareWorldMutationAsync(world), message =>
                {
                    StatusText = message;
                    _ = RefreshAfterChunkMutationAsync(null);
                }) { Owner = this }.ShowDialog();
                break;
            }
            case ChunkBatchAction.LayerReplace:
            {
                var selections = chunks.Select(ChunkRegion).ToArray();
                new RegionLayerReplaceWindow(world, selections, () => PrepareWorldMutationAsync(world), message =>
                {
                    StatusText = message;
                    _ = RefreshAfterChunkMutationAsync(null);
                }) { Owner = this }.ShowDialog();
                break;
            }
            case ChunkBatchAction.SetBiome:
                _ = SetBatchChunkBiomeAsync(chunks);
                break;
            case ChunkBatchAction.TickingArea:
                OpenTickingAreaManager(chunks);
                break;
            case ChunkBatchAction.DeleteHardcodedSpawners:
            case ChunkBatchAction.Clear:
            case ChunkBatchAction.Regenerate:
                _ = ExecuteBatchChunkMutationAsync(action, chunks);
                break;
        }
    }

    private IReadOnlyList<ChunkPosition> SelectedChunkPositions()
    {
        var positions = ChunkGrid.SelectedItems.OfType<BedrockChunkSummary>().Select(item => item.Position).Distinct().ToList();
        if (positions.Count == 0 && SelectedChunk is { } selected) positions.Add(selected.Position);
        return positions.OrderBy(item => item.Dimension).ThenBy(item => item.Z).ThenBy(item => item.X).ToArray();
    }

    private static MapRegionSelection ChunkRegion(ChunkPosition position)
    {
        var minimumX = checked((long)position.X * 16L);
        var minimumZ = checked((long)position.Z * 16L);
        var maximumX = checked(minimumX + 15L);
        var maximumZ = checked(minimumZ + 15L);
        if (minimumX < int.MinValue || maximumX > int.MaxValue || minimumZ < int.MinValue || maximumZ > int.MaxValue)
            throw new NotSupportedException("该区块坐标超出当前方块区域操作支持的 Int32 范围。");
        return new MapRegionSelection(position.Dimension, (int)minimumX, (int)minimumZ, (int)maximumX, (int)maximumZ);
    }

    private async Task SetBatchChunkBiomeAsync(IReadOnlyList<ChunkPosition> chunks)
    {
        if (_document is null || chunks.Count == 0) return;
        var input = TextPromptWindow.Prompt(this, "统一修改生物群系", $"输入数字 ID 或 minecraft:identifier。将精确修改所选 {chunks.Count:N0} 个区块。", "1");
        if (input is null) return;
        uint id;
        try { id = BedrockBiomeCatalog.Parse(input.Trim()).Id; }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "输入错误", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var displayName = BedrockBiomeCatalog.DisplayNameForId(id);
        if (MessageBox.Show(this, $"将所选 {chunks.Count:N0} 个区块的全部可编辑生物群系位置设置为 ID {id}（{displayName}）？", "确认批量修改生物群系", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        var world = _document;
        try
        {
            await PrepareWorldMutationAsync(world);
            var result = await Task.Run(() =>
            {
                using var db = world.OpenDatabase(false);
                var store = new BedrockRegionAdvancedStore(db);
                var changed = 0; long cells = 0; var skipped = 0;
                foreach (var chunk in chunks)
                {
                    var region = ChunkRegion(chunk);
                    try
                    {
                        var item = store.SetBiome(region.Dimension, region.MinimumX, region.MinimumZ, region.MaximumX, region.MaximumZ, id);
                        changed += item.ChangedChunks; cells += item.ChangedCells; skipped += item.SkippedChunks;
                    }
                    catch (InvalidOperationException) { skipped++; }
                    catch (NotSupportedException) { skipped++; }
                }
                return (Changed: changed, Cells: cells, Skipped: skipped);
            });
            if (result.Changed == 0) throw new NotSupportedException("所选区块中没有可修改的生物群系记录。");
            var message = $"已修改 {result.Changed:N0} 个区块、{result.Cells:N0} 个生物群系位置；跳过 {result.Skipped:N0} 个区块。";
            StatusText = message;
            MessageBox.Show(this, message, "批量修改生物群系完成", MessageBoxButton.OK, MessageBoxImage.Information);
            await RefreshAfterChunkMutationAsync(null);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "批量修改生物群系失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void OpenTickingAreaManager(IReadOnlyList<ChunkPosition> chunks)
    {
        if (_document is null || chunks.Count == 0) return;
        var dimensions = chunks.Select(item => item.Dimension).Distinct().ToArray();
        if (dimensions.Length != 1)
        {
            MessageBox.Show(this, "一次只能编辑同一维度区块对应的常加载区域。", "维度不一致", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        var dimension = dimensions[0];
        var minX = chunks.Min(item => item.X); var maxX = chunks.Max(item => item.X);
        var minZ = chunks.Min(item => item.Z); var maxZ = chunks.Max(item => item.Z);
        var suggested = new EnvironmentTickingAreaSpec(dimension, false, minX, minZ, maxX, maxZ, $"selection_{DateTime.Now:HHmmss}", false).Normalized;
        var center = new ChunkPosition((int)(((long)minX + maxX) / 2L), (int)(((long)minZ + maxZ) / 2L), dimension);
        var world = _document;
        var window = new TickingAreaManagerWindow(world, () => PrepareWorldMutationAsync(world), message =>
        {
            StatusText = message;
            if (HasRenderedMap) _ = RenderMapAsync();
        }, center, position => _ = LocateChunkOnMapAsync(position), suggested) { Owner = this };
        window.ShowDialog();
    }

    private async Task ExecuteBatchChunkMutationAsync(ChunkBatchAction action, IReadOnlyList<ChunkPosition> chunks)
    {
        if (_document is null || chunks.Count == 0) return;
        var (title, detail) = action switch
        {
            ChunkBatchAction.DeleteHardcodedSpawners => ("删除 HardcodedSpawners", "删除所选区块中的 0x39 HardcodedSpawners 记录。"),
            ChunkBatchAction.Clear => ("清空区块", "删除区块数据与关联实体，并写入纯空气区块。"),
            ChunkBatchAction.Regenerate => ("重新生成区块", "删除区块数据与关联实体，使 Minecraft 按种子重新生成。"),
            _ => throw new ArgumentOutOfRangeException(nameof(action))
        };
        if (MessageBox.Show(this, $"{title}：共 {chunks.Count:N0} 个所选区块。\n\n{detail}\n\n修改只写入 Cache 工作副本。", "确认批量处理", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        var world = _document;
        try
        {
            await PrepareWorldMutationAsync(world);
            var result = await Task.Run(() =>
            {
                using var db = world.OpenDatabase(false);
                var store = new BedrockChunkStore(db);
                var changed = 0; var skipped = 0;
                foreach (var chunk in chunks)
                {
                    try
                    {
                        switch (action)
                        {
                            case ChunkBatchAction.DeleteHardcodedSpawners:
                            {
                                var key = new BedrockDbKey(chunk, ChunkRecordType.HardcodedSpawners, null).Encode();
                                if (db.Get(key) is null) { skipped++; continue; }
                                db.Delete(key, sync: true);
                                break;
                            }
                            case ChunkBatchAction.Clear:
                                _ = store.ClearChunk(chunk);
                                break;
                            case ChunkBatchAction.Regenerate:
                                _ = store.RegenerateChunk(chunk);
                                break;
                        }
                        changed++;
                    }
                    catch (InvalidOperationException) { skipped++; }
                    catch (NotSupportedException) { skipped++; }
                }
                return (Changed: changed, Skipped: skipped);
            });
            if (result.Changed == 0) throw new NotSupportedException("所选区块中没有可执行该操作的记录。");
            var message = $"已{title} {result.Changed:N0} 个区块；跳过 {result.Skipped:N0} 个区块。";
            StatusText = message;
            MessageBox.Show(this, message, title + "完成", MessageBoxButton.OK, MessageBoxImage.Information);
            await RefreshAfterChunkMutationAsync(null);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, title + "失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task RefreshAfterChunkMutationAsync(ChunkPosition? position)
    {
        await LoadDatabaseAsync();
        if (ObjectRows.Count > 0) await ScanObjectsAsync();
        if (HasRenderedMap) await RenderMapAsync();
        if (position is { } target && ChunkRows.FirstOrDefault(item => item.Position == target) is { } row)
            SelectedChunk = row;
    }

    private void EditChunkBiome_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null || SelectedChunk is null)
        {
            MessageBox.Show(this, "请先选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var world = _document;
        var position = SelectedChunk.Position;
        var window = new ChunkBiomeEditorWindow(world, position, () => PrepareWorldMutationAsync(world), message =>
        {
            StatusText = message;
            if (HasRenderedMap) _ = RenderMapAsync();
        }) { Owner = this };
        window.ShowDialog();
    }

    private void EditChunkTickingArea_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null || SelectedChunk is null)
        {
            MessageBox.Show(this, "请先选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        OpenTickingAreaManager(SelectedChunk.Position);
    }

    private async void LocateChunkOnMap_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedChunk is null)
        {
            MessageBox.Show(this, "请先选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        await LocateChunkOnMapAsync(SelectedChunk.Position);
    }

    private async Task LocateChunkOnMapAsync(ChunkPosition position)
    {
        if (position.Dimension is >= 0 and <= 2) MapDimension.SelectedIndex = position.Dimension;
        _activeMapDimension = position.Dimension;
        var centerX = (int)Math.Clamp((long)position.X * 16L + 8L, int.MinValue, int.MaxValue);
        var centerZ = (int)Math.Clamp((long)position.Z * 16L + 8L, int.MinValue, int.MaxValue);
        MapCenterX.Text = centerX.ToString(CultureInfo.InvariantCulture);
        MapCenterZ.Text = centerZ.ToString(CultureInfo.InvariantCulture);
        await RenderMapAsync();
        _selectedMapChunk = position;
        UpdateMapOverlay();
        MapDetailText = $"已定位区块：{BedrockDimensionNames.DisplayName(position.Dimension)} ({position.X}, {position.Z})。";
    }

    private async void ClearChunk_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedChunk is null)
        {
            MessageBox.Show(this, "请先选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        await ConfirmAndExecuteMutationAsync(ChunkCommandKind.Empty, SelectedChunk.Position);
    }

    private async void RegenerateChunk_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedChunk is null)
        {
            MessageBox.Show(this, "请先选择一个区块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        await ConfirmAndExecuteMutationAsync(ChunkCommandKind.Regenerate, SelectedChunk.Position);
    }

    private async Task<string?> ConfirmAndExecuteMutationAsync(ChunkCommandKind kind, ChunkPosition position)
    {
        if (_document is null || _databaseBusy) return null;
        var action = kind == ChunkCommandKind.Empty ? "清空为空气区块" : "重新生成区块";
        var detail = kind == ChunkCommandKind.Empty
            ? "将删除该坐标全部区块记录、digp 和对应 Actor，再写入最小空气区块元数据。"
            : "将删除该坐标全部已知/未知区块记录、digp 和对应 Actor。Minecraft 下次加载时会按世界种子重新生成。";
        if (!ConfirmCommandMutation(
            $"{action}：{position.DimensionName} ({position.X}, {position.Z})\n\n{detail}\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。")) return null;

        _databaseBusy = true;
        string? resultMessage = null;
        try
        {
            var document = _document;
            StatusText = "正在检查 LevelDB 写入锁…";
            await Task.Run(() =>
            {
                using var probe = document.OpenDatabase(readOnly: false);
            });

            StatusText = $"正在{action}…";
            resultMessage = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: false);
                var store = new BedrockChunkStore(database);
                if (kind == ChunkCommandKind.Empty)
                {
                    var result = store.ClearChunk(position);
                    var digest = result.DeletedDigestCount > 0 ? $"、{result.DeletedDigestCount} 条 digp" : string.Empty;
                    var actors = result.DeletedActorCount > 0 ? $"、{result.DeletedActorCount} 个 Actor" : string.Empty;
                    var metadata = result.VersionRecordType == ChunkRecordType.LegacyTerrain
                        ? "LegacyTerrain 空列"
                        : $"{result.VersionRecordType.DisplayName()} + FinalizedState=2";
                    return $"chunk empty 完成：{ChunkCommandParser.DimensionName(position.Dimension)} ({position.X}, {position.Z})，删除 {result.DeletedChunkRecordCount} 条旧区块记录{digest}{actors}，创建 {result.CreatedMetadataRecordCount} 条纯空气区块元数据（{metadata}）。";
                }
                else
                {
                    var result = store.RegenerateChunk(position);
                    var digest = result.DeletedDigestCount > 0 ? $"、{result.DeletedDigestCount} 条 digp" : string.Empty;
                    var actors = result.DeletedActorCount > 0 ? $"、{result.DeletedActorCount} 个 Actor" : string.Empty;
                    return $"chunk regenerate 完成：{ChunkCommandParser.DimensionName(position.Dimension)} ({position.X}, {position.Z})，完整移除 {result.DeletedChunkRecordCount} 条区块记录{digest}{actors}；Minecraft 下次加载时会按种子重新生成。";
                }
            });
            StatusText = resultMessage;
            if (!_commandBatchRunning)
                MessageBox.Show(this, resultMessage, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            StatusText = action + "失败。";
            if (_commandBatchRunning) throw;
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            _databaseBusy = false;
        }

        if (resultMessage is not null)
            await LoadDatabaseAsync();
        return resultMessage;
    }

    private async void RefreshDatabaseBrowser_Click(object sender, RoutedEventArgs e)
        => await RefreshDatabaseBrowserAsync();

    private async Task RefreshDatabaseBrowserAsync()
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;
        if (!int.TryParse(DatabaseLimit.Text.Trim(), out var limit) || limit is < 1 or > 5000)
        {
            MessageBox.Show(this, "记录上限必须为 1～5000。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        _databaseBusy = true;
        StatusText = "正在读取 LevelDB 记录…";
        try
        {
            var document = _document;
            var prefix = DatabasePrefixFilter.Text;
            DatabaseRows = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: true);
                return LevelDbBrowserService.Browse(database, prefix, limit);
            });
            StatusText = $"数据库浏览器已读取 {DatabaseRows.Count:N0} 条记录。";
        }
        catch (Exception ex)
        {
            StatusText = "数据库浏览失败。";
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private async void ResetDatabaseBrowser_Click(object sender, RoutedEventArgs e)
    {
        DatabasePrefixFilter.Clear();
        DatabaseLimit.Text = "500";
        await RefreshDatabaseBrowserAsync();
    }

    private void OpenCommands_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SharedCommandFileStore.PrepareSharedDirectory();
            Process.Start(new ProcessStartInfo
            {
                FileName = SharedCommandFileStore.DirectoryPath,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task HandleSharedCommandFileAsync()
    {
        if (_document is null || !SharedCommandFileStore.CommandFileExists) return;
        SelectMainTab("命令");

        IReadOnlyList<SharedCommandFileLine> lines;
        try
        {
            lines = SharedCommandFileStore.ReadCommandLines();
        }
        catch (Exception ex)
        {
            CommandOutputRows.Add(new CommandOutputLine("Command.txt 读取失败：" + ex.Message, Brushes.Firebrick));
            StatusText = "Command.txt 读取失败。";
            return;
        }

        if (lines.Count == 0)
        {
            CommandOutputRows.Add(new CommandOutputLine("Commands/Command.txt 存在，但没有非空命令。", Brushes.DimGray));
            return;
        }

        var answer = MessageBox.Show(this,
            $"检测到 Commands/Command.txt，共 {lines.Count:N0} 条非空命令。\n\n是否先检查全部命令语法并在全部通过后按顺序执行？",
            "执行 Command.txt", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (answer != MessageBoxResult.Yes)
        {
            CommandOutputRows.Add(new CommandOutputLine("Command.txt：用户取消执行。", Brushes.DimGray));
            return;
        }

        var syntaxErrors = new List<string>();
        foreach (var line in lines)
        {
            try { ValidateCommandSyntax(line.Text); }
            catch (Exception ex) { syntaxErrors.Add($"第 {line.LineNumber} 行：{ex.Message}"); }
        }
        if (syntaxErrors.Count > 0)
        {
            CommandOutputRows.Add(new CommandOutputLine($"Command.txt 语法检查失败：{syntaxErrors.Count} 行存在错误；本次没有执行任何命令。", Brushes.Firebrick));
            foreach (var error in syntaxErrors)
                CommandOutputRows.Add(new CommandOutputLine(error, Brushes.Firebrick));
            StatusText = "Command.txt 语法检查失败，未执行。";
            return;
        }

        _commandBatchRunning = true;
        SetCommandBatchLock(true);
        StatusText = $"正在执行 Command.txt：0 / {lines.Count}";
        CommandOutputRows.Add(new CommandOutputLine($"Command.txt 语法检查通过，开始执行 {lines.Count:N0} 条命令。", Brushes.ForestGreen));
        try
        {
            for (var i = 0; i < lines.Count; i++)
            {
                var line = lines[i];
                StatusText = $"正在执行 Command.txt：{i + 1} / {lines.Count}（源文件第 {line.LineNumber} 行）";
                CommandInput.Text = line.Text;
                await ExecuteCommandAsync();
                await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.Background);
            }
            CommandOutputRows.Add(new CommandOutputLine("Command.txt 执行完成。", Brushes.ForestGreen));
            StatusText = $"Command.txt 执行完成：{lines.Count:N0} 条命令。";
        }
        finally
        {
            _commandBatchRunning = false;
            SetCommandBatchLock(false);
            SelectMainTab("命令");
        }
    }

    private void SetCommandBatchLock(bool locked)
    {
        foreach (var tab in MainTabs.Items.OfType<TabItem>())
            tab.IsEnabled = !locked || string.Equals(tab.Header?.ToString(), "命令", StringComparison.Ordinal);

        CommandInput.IsReadOnly = locked;
        CommandRunButton.IsEnabled = !locked;
        CommandClearButton.IsEnabled = !locked;
        CommandFolderButton.IsEnabled = !locked;
        if (locked) SelectMainTab("命令");
    }

    private void SelectMainTab(string header)
    {
        foreach (var item in MainTabs.Items.OfType<TabItem>())
        {
            if (!string.Equals(item.Header?.ToString(), header, StringComparison.Ordinal)) continue;
            MainTabs.SelectedItem = item;
            return;
        }
    }

    private static void ValidateCommandSyntax(string text)
    {
        ValidateCommandName(text);
        try
        {
            if (IsHelpCommand(text))
            {
                _ = HelpTextFor(text, validateOnly: true);
                return;
            }
            if (BlockCommandParser.IsBlockCommand(text)) { _ = BlockCommandParser.Parse(text); return; }
            if (StorageBiomeCommandParser.IsStorageBiomeCommand(text)) { _ = StorageBiomeCommandParser.Parse(text); return; }
            if (TargetingCommandParser.IsTargetingCommand(text)) { _ = TargetingCommandParser.Parse(text); return; }
            if (EntityActionCommandParser.IsEntityActionCommand(text)) { _ = EntityActionCommandParser.Parse(text); return; }
            if (EnvironmentCommandParser.IsEnvironmentCommand(text)) { _ = EnvironmentCommandParser.Parse(text); return; }
            if (StructureTemplateCommandParser.IsStructureTemplateCommand(text)) { _ = StructureTemplateCommandParser.Parse(text); return; }
            _ = ChunkCommandParser.Parse(text);
        }
        catch (InvalidDataException ex)
        {
            throw new InvalidDataException(CommandErrorText(text, ex.Message));
        }
    }

    private static void ValidateCommandName(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.StartsWith("/", StringComparison.Ordinal))
            throw new InvalidDataException("命令不需要斜杠，请直接输入命令名称");
        var command = FirstCommandToken(trimmed);
        if (command.Length == 0)
            throw new InvalidDataException("请输入命令");
        if (!CommandHelpCatalog.IsKnownCommand(command))
            throw new InvalidDataException($"不存在的命令：{command}。输入 help 查看全部命令。");
    }

    private static string FirstCommandToken(string text)
    {
        var trimmed = text.TrimStart();
        if (trimmed.Length == 0) return string.Empty;
        var end = 0;
        while (end < trimmed.Length && !char.IsWhiteSpace(trimmed[end])) end++;
        return trimmed[..end];
    }

    private static string CommandErrorText(string text, string message)
    {
        var command = FirstCommandToken(text);
        if (message.StartsWith("参数格式错误。", StringComparison.Ordinal)
            && CommandHelpCatalog.TryGetUsage(command, out var usage))
            return "参数格式错误。\n" + usage;
        return message;
    }

    private static bool IsHelpCommand(string text)
    {
        var tokens = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return tokens.Length > 0 && tokens[0].Equals("help", StringComparison.OrdinalIgnoreCase);
    }

    private static string HelpTextFor(string text, bool validateOnly = false)
    {
        var tokens = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (tokens.Length is < 1 or > 2 || !tokens[0].Equals("help", StringComparison.OrdinalIgnoreCase))
        {
            CommandHelpCatalog.TryGetUsage("help", out var helpUsage);
            throw new InvalidDataException("参数格式错误。\n" + helpUsage);
        }
        if (tokens.Length == 1)
            return validateOnly ? string.Empty : CommandHelpCatalog.AllUsageText;

        if (!CommandHelpCatalog.TryGetUsage(tokens[1], out var usage))
            throw new InvalidDataException($"不存在的命令：{tokens[1]}");
        return validateOnly ? string.Empty : usage;
    }

    private bool ConfirmCommandMutation(string message)
        => _commandBatchRunning || MessageBox.Show(this, message, "确认修改存档",
            MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) == MessageBoxResult.Yes;

    private async void ExecuteCommand_Click(object sender, RoutedEventArgs e)
        => await ExecuteCommandAsync();

    private void CommandOutputRows_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (!Dispatcher.CheckAccess())
        {
            _ = Dispatcher.InvokeAsync(() => CommandOutputRows_CollectionChanged(sender, e), DispatcherPriority.Background);
            return;
        }
        if (CommandOutputBox is null) return;

        var viewer = FindVisualChild<ScrollViewer>(CommandOutputBox);
        var keepAtBottom = viewer is null || viewer.ScrollableHeight - viewer.VerticalOffset <= 56.0;

        if (e.Action == NotifyCollectionChangedAction.Reset)
        {
            CommandOutputBox.Document.Blocks.Clear();
        }
        else if (e.Action == NotifyCollectionChangedAction.Add && e.NewItems is not null)
        {
            foreach (var item in e.NewItems.OfType<CommandOutputLine>())
            {
                var paragraph = new Paragraph
                {
                    Margin = new Thickness(0),
                    Padding = new Thickness(0),
                    FontFamily = new FontFamily("Consolas"),
                    FontSize = 13,
                    LineHeight = 18
                };
                paragraph.Inlines.Add(new Run(item.Text) { Foreground = item.Foreground });
                CommandOutputBox.Document.Blocks.Add(paragraph);
            }
        }
        else
        {
            RebuildCommandOutputDocument();
        }

        if (keepAtBottom)
            _ = Dispatcher.InvokeAsync(() => CommandOutputBox.ScrollToEnd(), DispatcherPriority.Background);
    }

    private void RebuildCommandOutputDocument()
    {
        if (CommandOutputBox is null) return;
        CommandOutputBox.Document.Blocks.Clear();
        foreach (var item in CommandOutputRows)
        {
            var paragraph = new Paragraph
            {
                Margin = new Thickness(0),
                Padding = new Thickness(0),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 13,
                LineHeight = 18
            };
            paragraph.Inlines.Add(new Run(item.Text) { Foreground = item.Foreground });
            CommandOutputBox.Document.Blocks.Add(paragraph);
        }
    }

    private void CommandOutput_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        var viewer = FindVisualChild<ScrollViewer>(CommandOutputBox);
        if (viewer is null) return;
        var step = -(e.Delta / 120.0) * 30.0;
        viewer.ScrollToVerticalOffset(Math.Clamp(viewer.VerticalOffset + step, 0.0, viewer.ScrollableHeight));
        e.Handled = true;
    }

    private void ScrollCommandOutputToEnd()
    {
        if (CommandOutputBox is null) return;
        _ = Dispatcher.InvokeAsync(() =>
        {
            CommandOutputBox.ScrollToEnd();
            var viewer = FindVisualChild<ScrollViewer>(CommandOutputBox);
            if (viewer is not null) viewer.ScrollToVerticalOffset(viewer.ScrollableHeight);
        }, DispatcherPriority.Background);
    }

    private static T? FindVisualChild<T>(DependencyObject? root) where T : DependencyObject
    {
        if (root is null) return null;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T typed) return typed;
            var nested = FindVisualChild<T>(child);
            if (nested is not null) return nested;
        }
        return null;
    }

    private async void CommandInput_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            e.Handled = true;
            await ExecuteCommandAsync();
            return;
        }

        if (e.Key == Key.Up)
        {
            e.Handled = true;
            RecallPreviousCommand();
            return;
        }

        if (e.Key == Key.Down)
        {
            e.Handled = true;
            RecallNextCommand();
        }
        // Left/Right are intentionally left to the real TextBox so caret movement,
        // selection with Shift, Ctrl+Left/Right and clipboard shortcuts behave like cmd.exe.
    }

    private void RecallPreviousCommand()
    {
        if (_commandHistory.Count == 0) return;
        if (_commandHistoryIndex < 0)
        {
            _commandHistoryDraft = CommandInput.Text;
            _commandHistoryIndex = _commandHistory.Count - 1;
        }
        else if (_commandHistoryIndex > 0)
        {
            _commandHistoryIndex--;
        }
        SetCommandInputText(_commandHistory[_commandHistoryIndex]);
    }

    private void RecallNextCommand()
    {
        if (_commandHistoryIndex < 0) return;
        if (_commandHistoryIndex < _commandHistory.Count - 1)
        {
            _commandHistoryIndex++;
            SetCommandInputText(_commandHistory[_commandHistoryIndex]);
            return;
        }

        _commandHistoryIndex = -1;
        SetCommandInputText(_commandHistoryDraft);
    }

    private void SetCommandInputText(string text)
    {
        CommandInput.Text = text;
        CommandInput.CaretIndex = CommandInput.Text.Length;
        CommandInput.SelectionLength = 0;
    }

    private void RememberCommandHistory(string text)
    {
        if (_commandBatchRunning) return;
        _commandHistory.Add(text);
        _commandHistoryIndex = -1;
        _commandHistoryDraft = string.Empty;
    }

    private void ClearCommandOutput_Click(object sender, RoutedEventArgs e)
    {
        CommandOutputRows.Clear();
        CommandInput.Focus();
    }

    private async Task ExecuteCommandAsync()
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;

        var text = CommandInput.Text.Trim();
        if (text.Length == 0) return;
        RememberCommandHistory(text);
        CommandInput.Clear();
        CommandOutputRows.Add(new CommandOutputLine("> " + text, Brushes.DimGray));
        try
        {
            ValidateCommandName(text);
            if (IsHelpCommand(text))
            {
                CommandOutputRows.Add(new CommandOutputLine(HelpTextFor(text), Brushes.DodgerBlue));
                StatusText = "help 完成。";
                return;
            }
            if (BlockCommandParser.IsBlockCommand(text))
            {
                await ExecuteBlockCommandAsync(text);
                return;
            }
            if (StorageBiomeCommandParser.IsStorageBiomeCommand(text))
            {
                await ExecuteStorageBiomeCommandAsync(text);
                return;
            }
            if (TargetingCommandParser.IsTargetingCommand(text))
            {
                await ExecuteTargetingCommandAsync(text);
                return;
            }
            if (EntityActionCommandParser.IsEntityActionCommand(text))
            {
                await ExecuteEntityActionCommandAsync(text);
                return;
            }
            if (EnvironmentCommandParser.IsEnvironmentCommand(text))
            {
                await ExecuteEnvironmentCommandAsync(text);
                return;
            }
            if (StructureTemplateCommandParser.IsStructureTemplateCommand(text))
            {
                await ExecuteStructureTemplateCommandAsync(text);
                return;
            }

            var request = ChunkCommandParser.Parse(text);
            if (request.IsDestructive)
            {
                var position = new ChunkPosition(request.X!.Value, request.Z!.Value, request.Dimension!.Value);
                var result = await ConfirmAndExecuteMutationAsync(request.Kind, position);
                if (result is not null)
                    CommandOutputRows.Add(new CommandOutputLine(result, Brushes.ForestGreen));
                return;
            }

            _databaseBusy = true;
            try
            {
                StatusText = "正在执行 chunk query…";
                var document = _document;
                var lines = await Task.Run(() =>
                {
                    using var database = document.OpenDatabase(readOnly: true);
                    var store = new BedrockChunkStore(database);
                    IReadOnlyList<BedrockChunkSummary> summaries;
                    if (request.Dimension.HasValue && request.X.HasValue && request.Z.HasValue)
                    {
                        summaries = [store.SummaryAt(new ChunkPosition(request.X.Value, request.Z.Value, request.Dimension.Value))];
                    }
                    else
                    {
                        var dimensions = request.Dimension.HasValue ? new[] { request.Dimension.Value } : new[] { 0, 1, 2 };
                        var order = dimensions.Select((value, index) => (value, index)).ToDictionary(item => item.value, item => item.index);
                        summaries = store.ListChunks()
                            .Where(item => order.ContainsKey(item.Position.Dimension))
                            .OrderBy(item => order[item.Position.Dimension])
                            .ThenBy(item => item.Position.Z)
                            .ThenBy(item => item.Position.X)
                            .ToArray();
                    }
                    return summaries.Select(store.QueryText).ToArray();
                });

                if (lines.Length == 0)
                    CommandOutputRows.Add(new CommandOutputLine("chunk query：没有匹配的已加载区块。", Brushes.DodgerBlue));
                else
                    foreach (var line in lines) CommandOutputRows.Add(new CommandOutputLine(line, Brushes.DodgerBlue));
                StatusText = $"chunk query 完成：{lines.Length:N0} 行。";
            }
            finally
            {
                _databaseBusy = false;
            }
        }
        catch (Exception ex)
        {
            var message = ex is InvalidDataException
                ? CommandErrorText(text, ex.Message)
                : ex.Message;
            CommandOutputRows.Add(new CommandOutputLine(message, Brushes.Firebrick));
            StatusText = "命令执行失败。";
        }
        finally
        {
            ScrollCommandOutputToEnd();
            if (!_commandBatchRunning) CommandInput.Focus();
        }
    }


    private void OpenDataValues_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null) return;
        new BedrockDataValueWindow { Owner = this }.ShowDialog();
    }

    private void OpenWeatherEditor_Click(object sender, RoutedEventArgs e)
    {
        if (_document is not { } document) return;
        var window = new WeatherEditorWindow(document, () => PrepareWorldMutationAsync(document), message =>
        {
            StatusText = message;
            _ = ReloadWorldInfoAfterToolEditAsync(document);
        }) { Owner = this };
        window.ShowDialog();
    }

    private void OpenTimeEditor_Click(object sender, RoutedEventArgs e)
    {
        if (_document is not { } document) return;
        var window = new TimeEditorWindow(document, () => PrepareWorldMutationAsync(document), message =>
        {
            StatusText = message;
            _ = ReloadWorldInfoAfterToolEditAsync(document);
        }) { Owner = this };
        window.ShowDialog();
    }

    private void OpenExperienceEditor_Click(object sender, RoutedEventArgs e)
    {
        if (_document is not { } document) return;
        var window = new ExperienceEditorWindow(document, () => PrepareWorldMutationAsync(document), message =>
        {
            StatusText = message;
            if (ObjectRows.Count > 0) _ = ScanObjectsAsync();
        }) { Owner = this };
        window.ShowDialog();
    }

    private async void ExportMcworld_Click(object sender, RoutedEventArgs e)
    {
        if (_document is not { } document) return;
        var safeName = string.Concat(WorldName.Select(ch => Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch));
        if (string.IsNullOrWhiteSpace(safeName)) safeName = "world";
        var dialog = new SaveFileDialog
        {
            Title = "导出当前世界 (.mcworld)",
            Filter = "Minecraft Bedrock World (*.mcworld)|*.mcworld",
            FileName = safeName + ".mcworld",
            AddExtension = true,
            DefaultExt = ".mcworld",
            OverwritePrompt = true
        };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var destination = Path.GetFullPath(dialog.FileName);
            ValidateExportDestination(destination);
            StatusText = "正在创建 .mcworld…";
            await Task.Run(() => WorldArchiveService.ExportMcworld(document, destination));
            _workingCopyDirty = false;
            StatusText = "世界导出完成：" + destination;
            MessageBox.Show(this, "已导出：\n" + destination, "导出完成", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            StatusText = "世界导出失败。";
            MessageBox.Show(this, ex.Message, "导出失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ValidateExportDestination(string destination)
    {
        var target = Path.GetFullPath(destination);
        if (!Path.GetExtension(target).Equals(".mcworld", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("世界编辑结果只能通过 .mcworld 导出。请使用 .mcworld 扩展名。");
        var cacheRoot = Path.GetFullPath(PortablePaths.CachePath).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (PathEquals(target, cacheRoot) || IsPathInside(target, cacheRoot))
            throw new InvalidOperationException("导出目标不能位于 Cache 中；程序退出时 Cache 会被自动清空。请选择其它目录。");

        if (string.IsNullOrWhiteSpace(_sourceWorldPath)) return;
        var source = Path.GetFullPath(_sourceWorldPath);
        if (File.Exists(source))
        {
            if (PathEquals(target, source))
                throw new InvalidOperationException("不能覆盖原始世界文件。请将编辑结果另存为新的 .mcworld 文件。");
            return;
        }
        if (Directory.Exists(source))
        {
            var sourceRoot = source.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (PathEquals(target, sourceRoot) || IsPathInside(target, sourceRoot))
                throw new InvalidOperationException("导出目标不能位于原始世界文件夹内部。请选择其它目录，源世界必须保持不变。");
        }
    }

    private static bool IsPathInside(string candidate, string directory)
    {
        var root = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        return Path.GetFullPath(candidate).StartsWith(root, StringComparison.OrdinalIgnoreCase);
    }

    private static bool PathEquals(string left, string right)
        => string.Equals(
            Path.GetFullPath(left).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            Path.GetFullPath(right).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            StringComparison.OrdinalIgnoreCase);

    private async Task ReloadWorldInfoAfterToolEditAsync(WorldDocument document)
    {
        try
        {
            var rows = await Task.Run(() => new WorldInfoService().Inspect(document));
            if (!ReferenceEquals(_document, document)) return;
            InfoRows.Clear();
            foreach (var row in rows)
            {
                if (row.Title == "世界目录")
                {
                    InfoRows.Add(new WorldInfoRow("源世界", _sourceWorldPath ?? string.Empty));
                    InfoRows.Add(new WorldInfoRow("临时工作副本", document.RootPath));
                }
                else
                {
                    InfoRows.Add(row);
                }
            }
        }
        catch (Exception ex)
        {
            StatusText = "修改已保存，但刷新世界信息失败：" + ex.Message;
        }
    }

    private async Task ExecuteStorageBiomeCommandAsync(string text)
    {
        if (_document is null) throw new InvalidOperationException("请先打开世界。");
        var request = StorageBiomeCommandParser.Parse(text);
        var document = _document;

        if (request is InfoStorageBiomeCommandRequest)
        {
            StatusText = "正在读取世界信息…";
            var rows = await Task.Run(() => new WorldInfoService().Inspect(document));
            foreach (var row in rows)
                CommandOutputRows.Add(new CommandOutputLine($"{row.Title}={row.Value}", Brushes.ForestGreen));
            StatusText = $"info 完成：{rows.Count:N0} 行。";
            return;
        }

        if (request is StorageQueryStorageBiomeCommandRequest query)
        {
            _databaseBusy = true;
            try
            {
                StatusText = "正在执行 storage query…";
                var lines = await Task.Run(() =>
                {
                    using var database = document.OpenDatabase(readOnly: true);
                    return new BedrockStorageCommandStore(database).Query(query.Dimension, query.Position);
                });
                foreach (var line in lines)
                    CommandOutputRows.Add(new CommandOutputLine(line,
                        line == "Block not generated" ? Brushes.ForestGreen : Brushes.DodgerBlue));
                StatusText = lines.Count == 1 && lines[0] == "Block not generated"
                    ? "storage query：Block not generated"
                    : $"storage query 完成：{lines.Count:N0} 个 storage。";
            }
            finally
            {
                _databaseBusy = false;
            }
            return;
        }

        var actionText = request switch
        {
            StorageSetStorageBiomeCommandRequest set => $"storage set {CommandDimensionToken(set.Dimension)} ({set.Position.X}, {set.Position.Y}, {set.Position.Z}) 层 {set.Layer}",
            StorageDeleteStorageBiomeCommandRequest delete => $"storage delete {CommandDimensionToken(delete.Dimension)} ({delete.Position.X}, {delete.Position.Y}, {delete.Position.Z}) 层 {delete.Layer}",
            StorageClearStorageBiomeCommandRequest clear => $"storage clear {CommandDimensionToken(clear.Dimension)} ({clear.Position.X}, {clear.Position.Y}, {clear.Position.Z}) 保留到层 {clear.KeepThroughLayer}",
            FillBiomeStorageBiomeCommandRequest biome => $"fillbiome {CommandDimensionToken(biome.Dimension)} {biome.Region.Volume:N0} 个方块范围 → {biome.BiomeDisplayText}",
            _ => "存档修改命令"
        };
        if (!ConfirmCommandMutation(
            $"确认执行 {actionText}？\n\n该操作会保持原有 SubChunk/biome 记录格式，并将本次命令聚合到一次 LevelDB WriteBatch。storage 命令只允许已知结构化 v8/v9 SubChunk；fillbiome 不会为完全没有 biome 记录的区块猜测创建数据。\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。"))
        {
            CommandOutputRows.Add(new CommandOutputLine("已取消。", Brushes.DimGray));
            return;
        }

        _databaseBusy = true;
        string resultMessage;
        try
        {
            StatusText = "正在检查 LevelDB 写入锁…";
            await PrepareWorldMutationAsync(document);
            StatusText = "正在执行 写入事务…";
            resultMessage = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: false);
                switch (request)
                {
                    case StorageSetStorageBiomeCommandRequest set:
                        return new BedrockStorageCommandStore(database).Set(set.Dimension, set.Position, set.Layer, set.Block).Message;
                    case StorageDeleteStorageBiomeCommandRequest delete:
                        return new BedrockStorageCommandStore(database).Delete(delete.Dimension, delete.Position, delete.Layer).Message;
                    case StorageClearStorageBiomeCommandRequest clear:
                        return new BedrockStorageCommandStore(database).Clear(clear.Dimension, clear.Position, clear.KeepThroughLayer).Message;
                    case FillBiomeStorageBiomeCommandRequest biome:
                    {
                        var result = new BedrockBiomeRegionStore(database).FillBiome(biome.Dimension, biome.Region, biome.BiomeId);
                        return $"fillbiome 完成：ID {biome.BiomeDisplayText}，修改 {result.ChangedChunkCount:N0} 个区块、{result.ChangedCellCount:N0} 个生物群系位置；跳过 {result.SkippedChunkCount:N0} 个无记录区块；WriteBatch Put={result.PutCount:N0}。";
                    }
                    default:
                        throw new InvalidOperationException("无法执行未知命令。");
                }
            });
        }
        finally
        {
            _databaseBusy = false;
        }

        CommandOutputRows.Add(new CommandOutputLine(resultMessage, Brushes.ForestGreen));
        StatusText = resultMessage;
        await LoadDatabaseAsync();
        if (HasRenderedMap) await RenderMapAsync();
    }


    private async Task ExecuteTargetingCommandAsync(string text)
    {
        if (_document is null) throw new InvalidOperationException("请先打开世界。");
        var request = TargetingCommandParser.Parse(text);
        var document = _document;

        if (request is ExperienceTargetingCommandRequest { Operation: TargetingExperienceOperationKind.Query } query)
        {
            _databaseBusy = true;
            try
            {
                StatusText = "正在执行 experience query…";
                var queryResult = await Task.Run(() =>
                {
                    using var database = document.OpenDatabase(readOnly: true);
                    return new TargetingCommandStore(database).Experience(query);
                });
                foreach (var line in queryResult.OutputLines)
                    CommandOutputRows.Add(new CommandOutputLine(line.Text, TargetingOutputBrush(line.Style)));
                StatusText = $"experience query 完成：{queryResult.OutputLines.Count:N0} 个玩家。";
            }
            finally
            {
                _databaseBusy = false;
            }
            return;
        }

        var actionText = request switch
        {
            SetWorldSpawnTargetingCommandRequest spawn => $"setworldspawn ({spawn.Position.X}, {spawn.Position.Y}, {spawn.Position.Z})",
            SpawnPointTargetingCommandRequest spawn => $"spawnpoint {spawn.Target.DisplayText} {CommandDimensionToken(spawn.Dimension)} ({spawn.Position.X}, {spawn.Position.Y}, {spawn.Position.Z})",
            ClearSpawnPointTargetingCommandRequest clear => $"clearspawnpoint {clear.Target.DisplayText}",
            TeleportTargetingCommandRequest teleport => $"teleport {teleport.Target.DisplayText} → {CommandDimensionToken(teleport.Dimension)} {TargetingCommandParser.CoordinateText(teleport.X)} {teleport.Y.DisplayText} {TargetingCommandParser.CoordinateText(teleport.Z)}",
            SpreadTargetingCommandRequest spread => $"spread {spread.Target.DisplayText}",
            ExperienceTargetingCommandRequest experience => $"experience {experience.Operation.ToString().ToLowerInvariant()} {experience.Target.DisplayText}",
            _ => "玩家/实体命令"
        };
        if (!ConfirmCommandMutation(
            $"确认执行 {actionText}？\n\n该操作会复用现有 Player NBT 与 actor/digp/旧式 Entity 数据层。teleport/spread 跨区块或跨维度移动实体时会同步更新数据库归属；玩家批量写入使用 LevelDB WriteBatch。\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。"))
        {
            CommandOutputRows.Add(new CommandOutputLine("已取消。", Brushes.DimGray));
            return;
        }

        _databaseBusy = true;
        TargetingCommandExecutionResult result;
        try
        {
            StatusText = "正在检查 LevelDB 写入锁…";
            await PrepareWorldMutationAsync(document);
            StatusText = "正在执行 玩家/实体写入…";
            result = await Task.Run(() =>
            {
                if (request is SetWorldSpawnTargetingCommandRequest setWorldSpawn)
                    return TargetingCommandExecutionResult.Success(TargetingCommandStore.SetWorldSpawn(document, setWorldSpawn.Position), true);

                using var database = document.OpenDatabase(readOnly: false);
                var store = new TargetingCommandStore(database);
                return request switch
                {
                    SpawnPointTargetingCommandRequest spawn => store.SpawnPoint(spawn),
                    ClearSpawnPointTargetingCommandRequest clear => store.ClearSpawnPoint(clear),
                    TeleportTargetingCommandRequest teleport => store.Teleport(teleport),
                    SpreadTargetingCommandRequest spread => store.Spread(spread),
                    ExperienceTargetingCommandRequest experience => store.Experience(experience),
                    _ => throw new InvalidOperationException("无法执行未知命令。")
                };
            });
        }
        finally
        {
            _databaseBusy = false;
        }

        foreach (var line in result.OutputLines)
            CommandOutputRows.Add(new CommandOutputLine(line.Text, TargetingOutputBrush(line.Style)));
        StatusText = result.OutputLines.Count > 1 ? $"命令完成：{result.OutputLines.Count:N0} 行输出。" : result.Message;

        if (request is SetWorldSpawnTargetingCommandRequest)
        {
            var rows = await Task.Run(() => new WorldInfoService().Inspect(document));
            InfoRows.Clear();
            foreach (var row in rows) InfoRows.Add(row);
        }
        await LoadDatabaseAsync();
        if (ObjectRows.Count > 0) await ScanObjectsAsync();
        if (HasRenderedMap) await RenderMapAsync();
    }

    private static Brush TargetingOutputBrush(TargetingOutputStyle style) => style switch
    {
        TargetingOutputStyle.LocalPlayer => Brushes.Goldenrod,
        TargetingOutputStyle.OnlinePlayer => Brushes.DodgerBlue,
        TargetingOutputStyle.Entity => Brushes.MediumPurple,
        _ => Brushes.ForestGreen
    };

    private async Task ExecuteEntityActionCommandAsync(string text)
    {
        if (_document is null) throw new InvalidOperationException("请先打开世界。");
        var request = EntityActionCommandParser.Parse(text);
        var document = _document;
        var actionText = request switch
        {
            ClearEntityActionCommandRequest clear => $"clear {clear.Target.DisplayText}",
            GiveEntityActionCommandRequest give => $"give {give.Target.DisplayText} {give.Slot.DisplayText} {give.ItemIdentifier} × {give.Count}",
            KillEntityActionCommandRequest kill => $"kill {kill.Target.DisplayText} {(kill.KillCreativePlayers ? 1 : 0)}",
            KickEntityActionCommandRequest kick => $"kick {kick.Target.DisplayText}",
            SummonEntityActionCommandRequest summon => $"summon {summon.Identifier} {CommandDimensionToken(summon.Dimension)} {TargetingCommandParser.CoordinateText(summon.X)} {TargetingCommandParser.CoordinateText(summon.Y)} {TargetingCommandParser.CoordinateText(summon.Z)}",
            EffectEntityActionCommandRequest effect => $"effect {effect.Operation.ToString().ToLowerInvariant()} {effect.Target.DisplayText} {effect.Selection.DisplayText}",
            _ => "对象状态命令"
        };
        if (!ConfirmCommandMutation(
            $"确认执行 {actionText}？\n\n该操作会直接修改玩家/实体 NBT，或创建/删除实体。clear/give/effect 会在写入前完成目标数据校验；summon 复用现有实体存储选择；kill 删除普通实体时复用 actor/digp/旧式 Entity 清理。\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。"))
        {
            CommandOutputRows.Add(new CommandOutputLine("已取消。", Brushes.DimGray));
            return;
        }

        _databaseBusy = true;
        TargetingCommandExecutionResult executionResult;
        try
        {
            StatusText = "正在检查 LevelDB 写入锁…";
            await PrepareWorldMutationAsync(document);
            StatusText = "正在执行 对象状态写入…";
            executionResult = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: false);
                var store = new EntityActionCommandStore(database);
                return request switch
                {
                    ClearEntityActionCommandRequest clear => store.Clear(clear),
                    GiveEntityActionCommandRequest give => store.Give(give),
                    KillEntityActionCommandRequest kill => store.Kill(kill),
                    KickEntityActionCommandRequest kick => store.Kick(kick),
                    SummonEntityActionCommandRequest summon => store.Summon(summon),
                    EffectEntityActionCommandRequest effect => store.Effect(effect),
                    _ => throw new InvalidOperationException("无法执行未知命令。")
                };
            });
        }
        finally
        {
            _databaseBusy = false;
        }

        foreach (var line in executionResult.OutputLines)
            CommandOutputRows.Add(new CommandOutputLine(line.Text, TargetingOutputBrush(line.Style)));
        StatusText = executionResult.Message;
        await LoadDatabaseAsync();
        if (ObjectRows.Count > 0 || request is SummonEntityActionCommandRequest) await ScanObjectsAsync();
        if (HasRenderedMap) await RenderMapAsync();
    }

    private async Task ExecuteEnvironmentCommandAsync(string text)
    {
        if (_document is null) throw new InvalidOperationException("请先打开世界。");
        var request = EnvironmentCommandParser.Parse(text);
        var document = _document;

        if (!request.IsDestructive)
        {
            _databaseBusy = true;
            try
            {
                StatusText = "正在读取世界状态…";
                var readResult = await Task.Run(() =>
                {
                    using var database = document.OpenDatabase(readOnly: true);
                    return new EnvironmentCommandStore(document, database).Execute(request);
                });
                foreach (var line in readResult.OutputLines)
                    CommandOutputRows.Add(new CommandOutputLine(line.Text, Brushes.ForestGreen));
                StatusText = "世界状态查询完成。";
            }
            finally
            {
                _databaseBusy = false;
            }
            return;
        }

        var actionText = request switch
        {
            DayLockEnvironmentCommandRequest dayLock => $"daylock {(dayLock.Locked ? 1 : 0)}",
            TimeEnvironmentCommandRequest time => time.Operation switch
            {
                EnvironmentTimeOperationKind.Add => $"time add {time.Value}",
                EnvironmentTimeOperationKind.Set => $"time set {time.Value}",
                EnvironmentTimeOperationKind.Ceil => $"time ceil {EnvironmentCommandParser.TimePeriodName(time.Period)}",
                EnvironmentTimeOperationKind.Floor => $"time floor {EnvironmentCommandParser.TimePeriodName(time.Period)}",
                _ => "time"
            },
            WeatherEnvironmentCommandRequest weather => weather.Condition switch
            {
                EnvironmentWeatherCondition.Clear => $"weather clear {(weather.AutomaticChange ? 1 : 0)}",
                _ => $"weather {weather.Condition.ToString().ToLowerInvariant()} {weather.Duration} {weather.Intensity?.ToString("G3", CultureInfo.InvariantCulture)} {(weather.AutomaticChange ? 1 : 0)}"
            },
            TickingAreaEnvironmentCommandRequest { Operation: EnvironmentTickingAreaOperationKind.Add, Area: { } area } => $"tickingarea add {(area.IsCircle ? "circle" : "square")} {CommandDimensionToken(area.Dimension)} {area.Name}",
            TickingAreaEnvironmentCommandRequest { Operation: EnvironmentTickingAreaOperationKind.Delete, Name: { } name } => $"tickingarea delete {name}",
            TickingAreaEnvironmentCommandRequest { Operation: EnvironmentTickingAreaOperationKind.Delete } => "tickingarea delete ALL",
            _ => "世界状态命令"
        };
        if (!ConfirmCommandMutation(
            $"确认执行 {actionText}？\n\ndaylock/time/weather 会修改 level.dat；tickingarea 会直接读写原生 tickingarea_* LevelDB NBT 记录。\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。"))
        {
            CommandOutputRows.Add(new CommandOutputLine("已取消。", Brushes.DimGray));
            return;
        }

        _databaseBusy = true;
        TargetingCommandExecutionResult executionResult;
        try
        {
            StatusText = "正在检查 LevelDB 写入锁…";
            await PrepareWorldMutationAsync(document);
            StatusText = "正在执行 世界状态写入…";
            executionResult = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: false);
                return new EnvironmentCommandStore(document, database).Execute(request);
            });
        }
        finally
        {
            _databaseBusy = false;
        }

        foreach (var line in executionResult.OutputLines)
            CommandOutputRows.Add(new CommandOutputLine(line.Text, Brushes.ForestGreen));
        StatusText = executionResult.Message;

        if (request is DayLockEnvironmentCommandRequest or TimeEnvironmentCommandRequest or WeatherEnvironmentCommandRequest)
        {
            var rows = await Task.Run(() => new WorldInfoService().Inspect(document));
            InfoRows.Clear();
            foreach (var row in rows) InfoRows.Add(row);
        }
        await LoadDatabaseAsync();
    }

    private async Task ExecuteStructureTemplateCommandAsync(string text)
    {
        if (_document is null) throw new InvalidOperationException("请先打开世界。");
        var request = StructureTemplateCommandParser.Parse(text);
        var document = _document;
        if (request.Operation is StructureTemplateStructureOperationKind.Query or StructureTemplateStructureOperationKind.Import or StructureTemplateStructureOperationKind.Export)
        {
            _databaseBusy = true;
            TargetingCommandExecutionResult result;
            try
            {
                result = request.Operation switch
                {
                    StructureTemplateStructureOperationKind.Import => await StructureFileDialogs.ImportAsync(this, document, () => PrepareWorldMutationAsync(document), request.Name),
                    StructureTemplateStructureOperationKind.Export => await StructureFileDialogs.ExportAsync(this, document, request.Format!.Value, request.Name),
                    _ => await Task.Run(() =>
                    {
                        using var database = document.OpenDatabase(readOnly: true);
                        return new StructureTemplateCommandStore(database).Query();
                    })
                };
            }
            finally { _databaseBusy = false; }
            foreach (var line in result.OutputLines) CommandOutputRows.Add(new CommandOutputLine(line.Text, Brushes.ForestGreen));
            StatusText = request.Operation == StructureTemplateStructureOperationKind.Query ? "结构查询完成。" : result.Message;
            if (result.ChangedWorld) await LoadDatabaseAsync();
            return;
        }
        var actionText = request.Operation switch
        {
            StructureTemplateStructureOperationKind.Save => $"structure save {request.Name} {CommandDimensionToken(request.Dimension!.Value)}",
            StructureTemplateStructureOperationKind.Load => $"structure load {request.Name} {CommandDimensionToken(request.Dimension!.Value)}",
            StructureTemplateStructureOperationKind.Delete when request.DeleteAll => "structure delete ALL",
            StructureTemplateStructureOperationKind.Delete => $"structure delete {request.Name}",
            _ => "structure"
        };
        if (!ConfirmCommandMutation(
            $"确认执行 {actionText}？\n\nstructure save 会覆盖同名 structuretemplate_ 记录；load 会批量写入目标方块和 BlockEntity；delete 会删除结构记录。\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。"))
        {
            CommandOutputRows.Add(new CommandOutputLine("已取消。", Brushes.DimGray));
            return;
        }

        _databaseBusy = true;
        TargetingCommandExecutionResult executionResult;
        try
        {
            StatusText = "正在检查 LevelDB 写入锁…";
            await PrepareWorldMutationAsync(document);
            StatusText = request.Operation switch
            {
                StructureTemplateStructureOperationKind.Save => "正在保存 structuretemplate…",
                StructureTemplateStructureOperationKind.Load => "正在加载 structuretemplate…",
                _ => "正在删除 structuretemplate…"
            };
            executionResult = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: false);
                return new StructureTemplateCommandStore(database).Execute(request);
            });
        }
        finally
        {
            _databaseBusy = false;
        }

        foreach (var line in executionResult.OutputLines)
            CommandOutputRows.Add(new CommandOutputLine(line.Text, Brushes.ForestGreen));
        StatusText = executionResult.Message;
        await LoadDatabaseAsync();
        if (request.Operation == StructureTemplateStructureOperationKind.Load && HasRenderedMap) await RenderMapAsync();
    }

    private async Task ExecuteBlockCommandAsync(string text)
    {
        if (_document is null) throw new InvalidOperationException("请先打开世界。");
        var request = BlockCommandParser.Parse(text);
        var document = _document;

        if (request is GetBlockCommandRequest get)
        {
            _databaseBusy = true;
            try
            {
                StatusText = "正在执行 getblock…";
                var output = await Task.Run(() =>
                {
                    using var database = document.OpenDatabase(readOnly: true);
                    return new BedrockRegionBlockStore(database).GetBlockText(get.Dimension, get.Position);
                });
                foreach (var line in output.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None))
                    CommandOutputRows.Add(new CommandOutputLine(line, line.StartsWith("BlockEntity=", StringComparison.Ordinal) ? Brushes.MediumPurple : Brushes.DodgerBlue));
                StatusText = "getblock 完成。";
            }
            finally
            {
                _databaseBusy = false;
            }
            return;
        }

        var actionText = request switch
        {
            SetBlockCommandRequest set => $"setblock {CommandDimensionToken(set.Dimension)} ({set.Position.X}, {set.Position.Y}, {set.Position.Z})",
            FillBlockCommandRequest fill => $"fill {CommandDimensionToken(fill.Dimension)} {fill.Region.Volume:N0} 个方块位置",
            CloneBlockCommandRequest clone => $"clone {CommandDimensionToken(clone.SourceDimension)} → {CommandDimensionToken(clone.TargetDimension)}，{clone.Source.Volume:N0} 个方块位置",
            _ => "区域方块命令"
        };
        if (!ConfirmCommandMutation(
            $"确认执行 {actionText}？\n\n方块数据与相关 BlockEntity 会使用一个 LevelDB WriteBatch 一次提交。Fill/SetBlock 会删除被覆盖位置原有 BlockEntity；Clone 会按命令开始时的源快照同步目标 BlockEntity。\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。"))
        {
            CommandOutputRows.Add(new CommandOutputLine("已取消。", Brushes.DimGray));
            return;
        }

        BedrockRegionMutationResult result;
        _databaseBusy = true;
        try
        {
            StatusText = "正在检查 LevelDB 写入锁…";
            await PrepareWorldMutationAsync(document);
            StatusText = "正在执行区域方块事务…";
            result = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: false);
                var store = new BedrockRegionBlockStore(database);
                return request switch
                {
                    SetBlockCommandRequest set => store.SetBlock(set.Dimension, set.Position, set.Storages),
                    FillBlockCommandRequest fill => store.Fill(fill.Dimension, fill.Region, fill.Storages),
                    CloneBlockCommandRequest clone => store.Clone(clone.SourceDimension, clone.Source, clone.TargetDimension, clone.Destination),
                    _ => throw new InvalidOperationException("无法执行未知方块命令。")
                };
            });
        }
        finally
        {
            _databaseBusy = false;
        }

        var entityText = result.CopiedBlockEntities > 0 || result.RemovedBlockEntities > 0
            ? $"；BlockEntity 删除 {result.RemovedBlockEntities}、复制 {result.CopiedBlockEntities}"
            : string.Empty;
        var message = $"完成：处理 {result.ChangedBlockPositions:N0} 个方块位置，写入 {result.TouchedSubChunks:N0} 个 SubChunk / {result.TouchedChunks:N0} 个区块；WriteBatch 项 Put={result.PutCount}, Delete={result.DeleteCount}{entityText}。";
        CommandOutputRows.Add(new CommandOutputLine(message, Brushes.ForestGreen));
        StatusText = message;

        await LoadDatabaseAsync();
        if (HasRenderedMap) await RenderMapAsync();
    }

    private static string CommandDimensionToken(int dimension) => dimension switch
    {
        0 => "overworld",
        1 => "nether",
        2 => "the_end",
        _ => throw new InvalidDataException($"不支持的维度：{dimension}")
    };

    private async Task InitializeLocalPlayerCenterAsync()
    {
        if (_document is null) return;
        try
        {
            var document = _document;
            var position = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: true);
                var store = new PlayerNbtStore(database);
                var local = store.Records().FirstOrDefault(player => player.IsLocal);
                return local is null ? null : store.CurrentPosition(local);
            });
            if (position is null) return;
            _mapCenters[position.Dimension] = (position.BlockX, position.BlockZ);
            if (position.Dimension is >= 0 and <= 2) MapDimension.SelectedIndex = position.Dimension;
            _activeMapDimension = position.Dimension;
            MapCenterX.Text = position.BlockX.ToString(CultureInfo.InvariantCulture);
            MapCenterZ.Text = position.BlockZ.ToString(CultureInfo.InvariantCulture);
            MapCenterY.Text = position.BlockY.ToString(CultureInfo.InvariantCulture);
            _mapCenterY = position.BlockY;
            MapStatusText = $"默认中心：本机玩家 · {BedrockDimensionNames.DisplayName(position.Dimension)} ({position.X:0.##}, {position.Y:0.##}, {position.Z:0.##})";
        }
        catch
        {
            // Some worlds have no local player record; keep the spawn fallback.
        }
    }


    private async void MainTabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!ReferenceEquals(e.Source, MainTabs) || MainTabs.SelectedItem is not TabItem tab) return;
        var header = tab.Header?.ToString();
        if (string.Equals(header, "实体", StringComparison.Ordinal))
        {
            await EnsureEntityTabInitialScanAsync();
            return;
        }
        if (string.Equals(header, "命令", StringComparison.Ordinal))
        {
            _ = Dispatcher.InvokeAsync(() =>
            {
                if (!_commandBatchRunning)
                {
                    CommandInput.Focus();
                    Keyboard.Focus(CommandInput);
                }
            }, DispatcherPriority.Input);
            return;
        }
        if (string.Equals(header, "世界信息", StringComparison.Ordinal))
            await RefreshWorldInfoAsync();
    }

    private async Task RefreshWorldInfoAsync()
    {
        if (_document is null || _databaseBusy) return;
        var document = _document;
        _databaseBusy = true;
        try
        {
            var rows = await Task.Run(() => new WorldInfoService().Inspect(document));
            if (!ReferenceEquals(_document, document)) return;
            InfoRows.Clear();
            foreach (var row in rows) InfoRows.Add(row);
            StatusText = "世界信息已刷新。";
        }
        catch (Exception ex)
        {
            StatusText = "世界信息刷新失败：" + ex.Message;
        }
        finally { _databaseBusy = false; }
    }

    private async Task EnsureEntityTabInitialScanAsync()
    {
        if (!_entityTabNeedsInitialScan || _document is null || _databaseBusy) return;
        _entityTabNeedsInitialScan = false;
        if (EntityDimension is not null) EntityDimension.SelectedIndex = 0; // 当前地图维度
        if (EntityIncludePlayers is not null) EntityIncludePlayers.IsChecked = false;
        if (EntityIncludeEntities is not null) EntityIncludeEntities.IsChecked = true;
        if (EntityIncludeBlockEntities is not null) EntityIncludeBlockEntities.IsChecked = true;
        if (EntitySpatialMode is not null) EntitySpatialMode.SelectedIndex = 0; // 全部坐标
        if (EntitySearch is not null) EntitySearch.Text = string.Empty;
        UpdateEntityFilterPanels();
        await ScanObjectsAsync();
    }

    private async void ScanEntities_Click(object sender, RoutedEventArgs e)
        => await ScanObjectsAsync();

    private void EntitySpatialMode_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        UpdateEntityFilterPanels();
        ApplyEntityFilter(showErrors: false);
    }

    private void EntityYFilterChanged(object sender, RoutedEventArgs e)
    {
        UpdateEntityFilterPanels();
        ApplyEntityFilter(showErrors: false);
    }

    private void EntitySearch_TextChanged(object sender, TextChangedEventArgs e)
        => ApplyEntityFilter(showErrors: false);

    private void ApplyEntityRange_Click(object sender, RoutedEventArgs e)
        => ApplyEntityFilter(showErrors: true);

    private void UpdateEntityFilterPanels()
    {
        if (EntitySpatialMode is null || EntityBoxPanel is null || EntityRadiusPanel is null) return;
        var mode = (EntitySpatialMode.SelectedItem as ComboBoxItem)?.Tag as string ?? "all";
        EntityBoxPanel.Visibility = mode == "box" ? Visibility.Visible : Visibility.Collapsed;
        EntityRadiusPanel.Visibility = mode == "radius" ? Visibility.Visible : Visibility.Collapsed;
        if (EntityBoxYPanel is not null)
            EntityBoxYPanel.Visibility = EntityBoxUseY?.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        if (EntityRadiusYPanel is not null)
            EntityRadiusYPanel.Visibility = EntityRadiusUseY?.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UseSelectedBlockForEntityRange_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedMapBlock is not { } block)
        {
            MessageBox.Show(this, "请先在地图中选择一个方块。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        SetEntityFilterCenter(block.X, block.Y, block.Z);
    }

    private void UseSelectedObjectForEntityRange_Click(object sender, RoutedEventArgs e)
    {
        var row = SelectedObjectRow;
        if (row?.X is not double x || row.Y is not double y || row.Z is not double z)
        {
            MessageBox.Show(this, "请先选择一个带坐标的实体或方块实体。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        SetEntityFilterCenter(x, y, z);
    }

    private void SetEntityFilterCenter(double x, double y, double z)
    {
        var sx = FormatEntityFilterNumber(x);
        var sy = FormatEntityFilterNumber(y);
        var sz = FormatEntityFilterNumber(z);
        EntityBoxX0.Text = sx;
        EntityBoxX1.Text = sx;
        EntityBoxY0.Text = sy;
        EntityBoxY1.Text = sy;
        EntityBoxZ0.Text = sz;
        EntityBoxZ1.Text = sz;
        EntityRadiusX.Text = sx;
        EntityRadiusY.Text = sy;
        EntityRadiusZ.Text = sz;
        ApplyEntityFilter(showErrors: false);
    }

    private static string FormatEntityFilterNumber(double value)
        => Math.Abs(value - Math.Round(value)) < 0.0000001
            ? Math.Round(value).ToString(CultureInfo.InvariantCulture)
            : value.ToString("0.##", CultureInfo.InvariantCulture);

    private async Task ScanObjectsAsync()
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;

        var includePlayers = EntityIncludePlayers.IsChecked == true;
        var includeEntities = EntityIncludeEntities.IsChecked == true;
        var includeBlockEntities = EntityIncludeBlockEntities.IsChecked == true;
        if (!includePlayers && !includeEntities && !includeBlockEntities)
        {
            MessageBox.Show(this, "至少选择一种对象类型。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var dimensionTag = (EntityDimension.SelectedItem as ComboBoxItem)?.Tag as string ?? "map";
        var currentDimension = SelectedMapDimension();
        HashSet<int>? dimensions = dimensionTag switch
        {
            "all" => null,
            "map" => [currentDimension],
            _ when int.TryParse(dimensionTag, out var parsed) => [parsed],
            _ => [currentDimension]
        };
        var dimensionDescription = dimensions is null
            ? "全部维度"
            : string.Join("/", dimensions.OrderBy(value => value).Select(BedrockDimensionNames.DisplayName));

        _databaseBusy = true;
        ObjectStatusText = $"正在扫描{dimensionDescription}全部对象…";
        StatusText = ObjectStatusText;
        try
        {
            var document = _document;
            var result = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: true);
                var rows = new List<WorldObjectRow>();
                if (includePlayers)
                {
                    var playerStore = new PlayerNbtStore(database);
                    foreach (var player in playerStore.Records())
                    {
                        var position = playerStore.CurrentPosition(player);
                        var dimension = position?.Dimension ?? 0;
                        if (dimensions is not null && !dimensions.Contains(dimension)) continue;
                        rows.Add(RowForPlayer(player, position, playerStore.UniqueId(player)));
                    }
                }

                var diagnostics = new List<string>();
                var actorCount = 0;
                var legacyCount = 0;
                var blockCount = 0;
                if (includeEntities || includeBlockEntities)
                {
                    var scan = new BedrockWorldObjectScanner(database).ScanAll(
                        dimensions, includeEntities, includeBlockEntities, maximumObjects: 1_000_000);
                    diagnostics.AddRange(scan.Diagnostics);
                    actorCount = scan.ActorRecordCount;
                    legacyCount = scan.LegacyEntityRecordCount;
                    blockCount = scan.BlockEntityRecordCount;
                    rows.AddRange(scan.Objects.Select(RowForWorldObject));
                }

                var ordered = rows.OrderBy(ObjectKindSortOrder)
                    .ThenBy(row => row.Dimension)
                    .ThenBy(row => row.DisplayName, StringComparer.CurrentCultureIgnoreCase)
                    .ThenBy(row => row.Z ?? 0)
                    .ThenBy(row => row.X ?? 0)
                    .ToArray();
                return (Rows: (IReadOnlyList<WorldObjectRow>)ordered, Diagnostics: diagnostics, Actor: actorCount, Legacy: legacyCount, Block: blockCount);
            });

            if (!ReferenceEquals(_document, document)) return;
            _allObjectRows = result.Rows;
            _objectScanSummary = $"{dimensionDescription}：共 {_allObjectRows.Count:N0} 个对象 · actor {result.Actor:N0} · 旧实体记录 {result.Legacy:N0} · 方块实体记录 {result.Block:N0}" +
                                 (result.Diagnostics.Count == 0 ? string.Empty : $" · {result.Diagnostics.Count} 条诊断");
            ApplyEntityFilter(showErrors: false);
            StatusText = "实体/玩家扫描完成。";
            if (result.Diagnostics.Count > 0)
                MapDetailText = "对象扫描诊断（首条）：" + result.Diagnostics[0];
        }
        catch (Exception ex)
        {
            ObjectStatusText = "对象扫描失败。";
            StatusText = "对象扫描失败。";
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private void ApplyEntityFilter(bool showErrors)
    {
        if (EntitySpatialMode is null || EntitySearch is null) return;
        try
        {
            var mode = (EntitySpatialMode.SelectedItem as ComboBoxItem)?.Tag as string ?? "all";
            var query = EntitySearch.Text.Trim();
            var rangeDescription = "全部坐标";
            Func<WorldObjectRow, bool> spatial = static _ => true;

            if (mode == "box")
            {
                if (!TryEntityDouble(EntityBoxX0.Text, out var x0) || !TryEntityDouble(EntityBoxZ0.Text, out var z0) ||
                    !TryEntityDouble(EntityBoxX1.Text, out var x1) || !TryEntityDouble(EntityBoxZ1.Text, out var z1))
                    throw new InvalidDataException("坐标区域的 X0、Z0、X1、Z1 必须是数字。");
                var minX = Math.Min(x0, x1); var maxX = Math.Max(x0, x1);
                var minZ = Math.Min(z0, z1); var maxZ = Math.Max(z0, z1);
                double? minY = null, maxY = null;
                if (EntityBoxUseY.IsChecked == true)
                {
                    if (!TryEntityDouble(EntityBoxY0.Text, out var y0) || !TryEntityDouble(EntityBoxY1.Text, out var y1))
                        throw new InvalidDataException("Y0、Y1 必须是数字。");
                    minY = Math.Min(y0, y1); maxY = Math.Max(y0, y1);
                }
                spatial = row => row.X is { } x && row.Z is { } z && x >= minX && x <= maxX && z >= minZ && z <= maxZ &&
                    (!minY.HasValue || row.Y is { } y && y >= minY.Value && y <= maxY!.Value);
                rangeDescription = minY.HasValue
                    ? $"区域 X={FormatEntityFilterNumber(minX)}…{FormatEntityFilterNumber(maxX)}，Z={FormatEntityFilterNumber(minZ)}…{FormatEntityFilterNumber(maxZ)}，Y={FormatEntityFilterNumber(minY.Value)}…{FormatEntityFilterNumber(maxY!.Value)}"
                    : $"区域 X={FormatEntityFilterNumber(minX)}…{FormatEntityFilterNumber(maxX)}，Z={FormatEntityFilterNumber(minZ)}…{FormatEntityFilterNumber(maxZ)}";
            }
            else if (mode == "radius")
            {
                if (!TryEntityDouble(EntityRadiusX.Text, out var cx) || !TryEntityDouble(EntityRadiusZ.Text, out var cz) ||
                    !TryEntityDouble(EntityRadiusValue.Text, out var radius) || radius < 0)
                    throw new InvalidDataException("中心 X、Z 和半径必须是有效数字，且半径不能为负数。");
                double? cy = null;
                if (EntityRadiusUseY.IsChecked == true)
                {
                    if (!TryEntityDouble(EntityRadiusY.Text, out var parsedY))
                        throw new InvalidDataException("开启 Y 后必须填写中心 Y。");
                    cy = parsedY;
                }
                var radiusSquared = radius * radius;
                spatial = row =>
                {
                    if (row.X is not { } x || row.Z is not { } z) return false;
                    var dx = x - cx; var dz = z - cz;
                    if (!cy.HasValue) return dx * dx + dz * dz <= radiusSquared;
                    if (row.Y is not { } y) return false;
                    var dy = y - cy.Value;
                    return dx * dx + dy * dy + dz * dz <= radiusSquared;
                };
                rangeDescription = cy.HasValue
                    ? $"XYZ 半径 {FormatEntityFilterNumber(radius)}，中心 ({FormatEntityFilterNumber(cx)}, {FormatEntityFilterNumber(cy.Value)}, {FormatEntityFilterNumber(cz)})"
                    : $"XZ 半径 {FormatEntityFilterNumber(radius)}，中心 ({FormatEntityFilterNumber(cx)}, {FormatEntityFilterNumber(cz)})";
            }

            bool TextMatches(WorldObjectRow row)
            {
                if (query.Length == 0) return true;
                return row.DisplayName.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                    || row.Identifier.Contains(query, StringComparison.OrdinalIgnoreCase)
                    || row.SourceText.Contains(query, StringComparison.OrdinalIgnoreCase)
                    || row.UniqueIdText.Contains(query, StringComparison.OrdinalIgnoreCase)
                    || $"{row.XText},{row.YText},{row.ZText}".Contains(query, StringComparison.OrdinalIgnoreCase);
            }

            var filtered = _allObjectRows.Where(row => spatial(row) && TextMatches(row)).ToArray();
            ObjectRows = filtered;
            if (SelectedObjectRow is null || !filtered.Contains(SelectedObjectRow))
                SelectedObjectRow = filtered.FirstOrDefault();
            ObjectStatusText = (_objectScanSummary.Length == 0 ? "尚未扫描世界" : _objectScanSummary) +
                               $" · {rangeDescription} · 当前显示 {filtered.Length:N0} 项";
        }
        catch (Exception ex)
        {
            ObjectStatusText = (_objectScanSummary.Length == 0 ? "尚未扫描世界" : _objectScanSummary) + " · 范围参数尚未生效：" + ex.Message;
            if (showErrors)
                MessageBox.Show(this, ex.Message, "范围参数错误", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static bool TryEntityDouble(string? text, out double value)
        => double.TryParse(text?.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out value)
           || double.TryParse(text?.Trim(), NumberStyles.Float, CultureInfo.CurrentCulture, out value);

    private static int ObjectKindSortOrder(WorldObjectRow row)
        => row.WorldObject?.Kind switch
        {
            BedrockWorldObjectKind.Entity => 0,
            BedrockWorldObjectKind.BlockEntity => 1,
            _ => 2
        };

    private static WorldObjectRow RowForPlayer(PlayerNbtRecord player, PlayerCurrentPosition? position, long? uniqueId)
        => new(
            player.IsLocal ? "本地玩家" : "在线玩家",
            player.DisplayName,
            "minecraft:player",
            position?.Dimension ?? 0,
            position?.X,
            position?.Y,
            position?.Z,
            player.KeyText,
            uniqueId,
            CountItems(player.Document.Root),
            player,
            null);

    private static WorldObjectRow RowForWorldObject(BedrockWorldObject item)
        => new(
            item.KindText,
            item.DisplayName,
            item.Identifier,
            item.Dimension,
            item.Position?.X,
            item.Position?.Y,
            item.Position?.Z,
            item.SourceText,
            item.UniqueId,
            item.ItemCount,
            null,
            item);

    private static int CountItems(NbtValue root)
    {
        var count = 0;
        foreach (var name in new[] { "Items", "items", "Inventory", "inventory", "Armor", "Mainhand", "Offhand" })
        {
            if (root.CompoundValueIgnoreCase(name) is not NbtListValue list) continue;
            foreach (var item in list.Values)
            {
                var stackCount = item is NbtCompoundValue ? item.CompoundValueIgnoreCase("Count", "count")?.IntegerValue() ?? 1 : 1;
                if (stackCount > 0) count++;
            }
        }
        return count;
    }

    private async void ObjectGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (ObjectGrid.SelectedItem is WorldObjectRow row) await EditObjectNbtAsync(row);
    }

    private async void CreateEntity_Click(object sender, RoutedEventArgs e)
        => await CreateWorldObjectAsync(BedrockWorldObjectKind.Entity, null);

    private async void CreateBlockEntity_Click(object sender, RoutedEventArgs e)
        => await CreateWorldObjectAsync(BedrockWorldObjectKind.BlockEntity, null);

    private async void DuplicateObject_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedObjectRow?.WorldObject is not { } item)
        {
            MessageBox.Show(this, "请先选择一个实体或方块实体。玩家不能通过通用对象复制功能创建。", "MCBEEditor",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        await CreateWorldObjectAsync(item.Kind, item);
    }

    private async void ExportSelectedEntity_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedObjectRow?.WorldObject is not { Kind: BedrockWorldObjectKind.Entity } item)
        {
            MessageBox.Show(this, "请先选择一个实体。方块实体可在 NBT 编辑器中导出。", "MCBEEditor",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var safeIdentifier = string.Concat(item.Identifier.Select(ch => Path.GetInvalidFileNameChars().Contains(ch) || ch == ':' ? '_' : ch));
        var suffix = item.UniqueId?.ToString(CultureInfo.InvariantCulture) ?? "entity";
        var save = new SaveFileDialog
        {
            Title = "导出实体 NBT",
            Filter = "Little Endian NBT (*.nbt)|*.nbt|Little Endian VarInt NBT (*.nbt)|*.nbt|Big Endian NBT (*.nbt)|*.nbt|JSON NBT (*.json)|*.json",
            FilterIndex = 1, AddExtension = true, FileName = $"{safeIdentifier}-{suffix}.nbt"
        };
        if (save.ShowDialog(this) != true) return;
        try
        {
            byte[] data = save.FilterIndex switch
            {
                2 => StandaloneNbtFileCodec.Encode([item.Document], NbtEncoding.LittleEndianVarInt),
                3 => StandaloneNbtFileCodec.Encode([item.Document], NbtEncoding.BigEndian),
                4 => StandaloneNbtFileCodec.EncodeJson([item.Document]),
                _ => StandaloneNbtFileCodec.Encode([item.Document], NbtEncoding.LittleEndian)
            };
            await File.WriteAllBytesAsync(save.FileName, data);
            StatusText = $"实体 NBT 已导出：{save.FileName}";
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "导出实体 NBT 失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void CopySelectedObjectCoordinates_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedObjectRow is not { X: double x, Y: double y, Z: double z })
        {
            MessageBox.Show(this, "所选对象没有可复制的坐标。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        static string F(double value) => Math.Abs(value - Math.Round(value)) < 0.0000001
            ? Math.Round(value).ToString(CultureInfo.InvariantCulture)
            : value.ToString("0.##", CultureInfo.InvariantCulture);
        var text = $"{F(x)}, {F(y)}, {F(z)}";
        Clipboard.SetText(text);
        StatusText = $"已复制坐标：{text}";
    }

    private async void MoveSelectedBlockEntity_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;
        if (SelectedObjectRow?.WorldObject is not { Kind: BedrockWorldObjectKind.BlockEntity, Position: not null } item)
        {
            MessageBox.Show(this, "请先选择一个带有效坐标的方块实体。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var dialog = new BlockEntityMoveWindow(item) { Owner = this };
        if (dialog.ShowDialog() != true) return;
        var source = item.Position!;
        if (item.Dimension == dialog.Dimension && source.BlockX == dialog.X && source.BlockY == dialog.Y && source.BlockZ == dialog.Z)
        {
            MessageBox.Show(this, "目标坐标与源坐标相同，无需移动。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var warning = $"确定移动方块实体吗？\n\n源：{BedrockDimensionNames.DisplayName(item.Dimension)} ({source.BlockX}, {source.BlockY}, {source.BlockZ})\n目标：{BedrockDimensionNames.DisplayName(dialog.Dimension)} ({dialog.X}, {dialog.Y}, {dialog.Z})\n\n源坐标全部 block storage 会搬到目标，源位置置空气；目标已有方块会被覆盖。BlockEntity NBT 与方块数据在同一个 LevelDB WriteBatch 中提交。若目标已有方块实体则整个操作拒绝，不会写入。\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。";
        var answer = MessageBox.Show(this, warning,
            "确认移动方块实体", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
        if (answer != MessageBoxResult.Yes) return;

        var world = _document;
        try
        {
            _databaseBusy = true;
            StatusText = "正在原子迁移方块实体与方块数据…";
            await PrepareWorldMutationAsync(world);
            await Task.Run(() =>
            {
                using var database = world.OpenDatabase(readOnly: false);
                new BedrockWorldObjectNbtStore(database).MoveBlockEntity(item, dialog.Dimension, dialog.X, dialog.Y, dialog.Z);
            });
            StatusText = $"方块实体已移动到 {BedrockDimensionNames.DisplayName(dialog.Dimension)} ({dialog.X}, {dialog.Y}, {dialog.Z})。";
        }
        catch (Exception ex)
        {
            StatusText = "移动方块实体失败。";
            MessageBox.Show(this, ex.Message, "移动方块实体失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        finally
        {
            _databaseBusy = false;
        }

        if (ObjectRows.Count > 0) await ScanObjectsAsync();
        if (HasRenderedMap) await RenderMapAsync();
    }

    private async Task CreateWorldObjectAsync(BedrockWorldObjectKind kind, BedrockWorldObject? template)
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;

        var world = _document;
        var (defaultPosition, defaultDimension) = DefaultObjectLocation(template);
        var selectedLocation = SelectedObjectLocation();
        long suggestedUniqueId = 1;
        if (kind == BedrockWorldObjectKind.Entity)
        {
            try
            {
                suggestedUniqueId = await Task.Run(() =>
                {
                    using var database = world.OpenDatabase(readOnly: true);
                    return new BedrockWorldObjectNbtStore(database).SuggestedUniqueId();
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "生成 UniqueID 失败", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }
        }

        var dialog = new WorldObjectCreateWindow(
            kind, template, defaultPosition, defaultDimension, suggestedUniqueId,
            selectedLocation?.Position, selectedLocation?.Dimension) { Owner = this };
        if (dialog.ShowDialog() != true) return;

        try
        {
            _databaseBusy = true;
            StatusText = kind == BedrockWorldObjectKind.Entity ? "正在创建实体…" : "正在创建方块实体 NBT…";
            await PrepareWorldMutationAsync(world);
            var result = await Task.Run(() =>
            {
                using var database = world.OpenDatabase(readOnly: false);
                var store = new BedrockWorldObjectNbtStore(database);
                return store.Create(kind, dialog.Identifier, dialog.Position, dialog.Dimension, dialog.UniqueId, template);
            });
            StatusText = result.Kind == BedrockWorldObjectKind.Entity
                ? $"实体已创建：{dialog.Identifier} · {BedrockDimensionNames.DisplayName(result.Dimension)} 区块 ({result.ChunkX}, {result.ChunkZ}) · UniqueID {result.UniqueId}"
                : $"方块实体 NBT 已创建：{dialog.Identifier} · {BedrockDimensionNames.DisplayName(result.Dimension)} 区块 ({result.ChunkX}, {result.ChunkZ})";
        }
        catch (Exception ex)
        {
            StatusText = "创建对象失败。";
            MessageBox.Show(this, ex.Message, "创建对象失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        finally
        {
            _databaseBusy = false;
        }

        if (ObjectRows.Count > 0) await ScanObjectsAsync();
        if (HasRenderedMap) await RefreshMapObjectMarkersAsync();
    }

    private async void DeleteSelectedObjects_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;

        var objects = ObjectGrid.SelectedItems.Cast<WorldObjectRow>()
            .Select(row => row.WorldObject)
            .Where(item => item is not null)
            .Cast<BedrockWorldObject>()
            .GroupBy(item => item.StableId, StringComparer.Ordinal)
            .Select(group => group.First())
            .ToArray();
        if (objects.Length == 0)
        {
            MessageBox.Show(this, "请至少选择一个实体或方块实体。玩家不能通过通用删除功能删除。", "MCBEEditor",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var blockEntityCount = objects.Count(item => item.Kind == BedrockWorldObjectKind.BlockEntity);
        var warning = $"确定删除所选 {objects.Length} 个对象吗？\n\n现代实体会同时清理 actorprefix/digp 引用。";
        if (blockEntityCount > 0)
            warning += $"\n其中 {blockEntityCount} 个方块实体只删除 BlockEntity NBT，不会替换对应方块。";
        warning += "\n\n修改只会写入程序同级 Cache 的临时工作副本；源世界不会被修改。只有“导出 .mcworld”会持久化结果。";
        if (MessageBox.Show(this, warning, "删除所选对象", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        var world = _document;
        try
        {
            _databaseBusy = true;
            StatusText = $"正在删除 {objects.Length} 个对象…";
            await PrepareWorldMutationAsync(world);
            var deleted = await Task.Run(() =>
            {
                using var database = world.OpenDatabase(readOnly: false);
                return new BedrockWorldObjectNbtStore(database).Delete(objects);
            });
            StatusText = $"已删除 {deleted} 个对象。";
        }
        catch (Exception ex)
        {
            StatusText = "删除对象失败。";
            MessageBox.Show(this, ex.Message, "删除对象失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        finally
        {
            _databaseBusy = false;
        }

        await ScanObjectsAsync();
        if (HasRenderedMap) await RefreshMapObjectMarkersAsync();
    }

    private async void ImportEntities_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;

        var world = _document;
        var (defaultPosition, _) = DefaultObjectLocation(null);
        long suggestedUniqueId;
        try
        {
            suggestedUniqueId = await Task.Run(() =>
            {
                using var database = world.OpenDatabase(readOnly: true);
                return new BedrockWorldObjectNbtStore(database).SuggestedUniqueId();
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "生成 UniqueID 失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        var options = new EntityImportOptionsWindow(defaultPosition, suggestedUniqueId) { Owner = this };
        if (options.ShowDialog() != true) return;

        var picker = new OpenFileDialog
        {
            Title = "选择实体 NBT / JSON",
            Filter = "实体 NBT/JSON|*.nbt;*.json|NBT 文件|*.nbt|JSON 文件|*.json|所有文件|*.*",
            Multiselect = false,
            CheckFileExists = true
        };
        if (picker.ShowDialog(this) != true) return;

        IReadOnlyList<NbtDocument> decoded;
        try
        {
            var data = await File.ReadAllBytesAsync(picker.FileName);
            decoded = string.Equals(Path.GetExtension(picker.FileName), ".json", StringComparison.OrdinalIgnoreCase)
                ? NbtJsonCodec.DecodeEntityDocuments(data)
                : DecodeEntityNbtDocuments(data, picker.FileName);
            if (decoded.Count == 0) throw new InvalidDataException("文件中没有可导入的实体根标签。");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "读取实体文件失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        IReadOnlyList<NbtDocument> prepared;
        try
        {
            using var database = world.OpenDatabase(readOnly: true);
            var store = new BedrockWorldObjectNbtStore(database);
            var list = new List<NbtDocument>(decoded.Count);
            for (var index = 0; index < decoded.Count; index++)
            {
                var uniqueId = checked(options.BaseUniqueId + index);
                if (uniqueId == 0) throw new InvalidDataException("导入序列生成了 UniqueID 0，请更换起始 UniqueID。");
                list.Add(store.PrepareImportedEntityDocument(decoded[index], options.Position, uniqueId));
            }
            prepared = list;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "准备实体导入失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        var review = new EntityImportReviewWindow(prepared, async (documents, fallbackDimension) =>
        {
            await PrepareWorldMutationAsync(world);
            await Task.Run(() =>
            {
                using var database = world.OpenDatabase(readOnly: false);
                var store = new BedrockWorldObjectNbtStore(database);
                foreach (var document in documents) store.CreateEntityFromDocument(document, fallbackDimension);
            });
            StatusText = $"已导入 {documents.Count:N0} 个实体。";
        }) { Owner = this };
        review.ShowDialog();
        if (!review.DidImport) return;
        if (ObjectRows.Count > 0) await ScanObjectsAsync();
        if (HasRenderedMap) await RefreshMapObjectMarkersAsync();
    }

    private (BedrockWorldObjectPosition Position, int Dimension)? SelectedObjectLocation()
    {
        if (SelectedObjectRow is { X: double x, Y: double y, Z: double z } row)
            return (new BedrockWorldObjectPosition(x, y, z), row.Dimension);
        if (_selectedMapBlock is { } selectedBlock)
            return (new BedrockWorldObjectPosition(selectedBlock.X, selectedBlock.Y, selectedBlock.Z), selectedBlock.Dimension);
        return null;
    }

    private (BedrockWorldObjectPosition Position, int Dimension) DefaultObjectLocation(BedrockWorldObject? template)
    {
        if (template?.Position is { } templatePosition)
            return (templatePosition, template.Dimension);
        if (SelectedObjectLocation() is { } selected)
            return selected;
        if (HasRenderedMap)
            return (new BedrockWorldObjectPosition(_lastMapCenterX, _lastMapCenterY, _lastMapCenterZ), _lastMapDimension);
        return (new BedrockWorldObjectPosition(_spawnX, 64, _spawnZ), SelectedMapDimension());
    }

    private async Task PrepareWorldMutationAsync(WorldDocument world)
    {
        // The source world is never opened for writing. This probe only verifies that
        // the disposable Cache working copy can be opened for mutation.
        await Task.Run(() =>
        {
            using var probe = world.OpenDatabase(readOnly: false);
        });
    }

    private static IReadOnlyList<NbtDocument> DecodeEntityNbtDocuments(byte[] data, string filename)
        => StandaloneNbtFileCodec.Decode(data, filename).Documents;

    private async void EditSelectedObjectNbt_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedObjectRow is null)
        {
            MessageBox.Show(this, "请先选择一个玩家、实体或方块实体。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        await EditObjectNbtAsync(SelectedObjectRow);
    }

    private async Task EditObjectNbtAsync(WorldObjectRow row)
    {
        if (_document is null) return;
        var document = row.Player?.Document ?? row.WorldObject?.Document;
        if (document is null) return;
        var world = _document;
        var protectedFields = row.Player is not null || row.WorldObject?.Kind == BedrockWorldObjectKind.Entity
            ? new[] { "UniqueID", "UniqueId", "uniqueID", "uniqueId" }
            : Array.Empty<string>();

        var editor = new NbtEditorWindow($"{row.KindText} · {row.DisplayName}", document, async edited =>
        {
            await PrepareWorldMutationAsync(world);
            await Task.Run(() =>
            {
                using var database = world.OpenDatabase(readOnly: false);
                if (row.Player is { } player) new PlayerNbtStore(database).Save(player, edited);
                else if (row.WorldObject is { } item) new BedrockWorldObjectNbtStore(database).Save(item, edited);
            });
            StatusText = $"NBT 已应用到工作副本：{row.DisplayName}";
        }, protectedFields, row.WorldObject?.Storage.Encoding ?? NbtEncoding.LittleEndian) { Owner = this };
        editor.ShowDialog();
        if (editor.DidSave)
        {
            if (ObjectRows.Count > 0) await ScanObjectsAsync();
            if (HasRenderedMap)
            {
                if (row.WorldObject?.Kind == BedrockWorldObjectKind.BlockEntity) await RenderMapAsync();
                else await RefreshMapObjectMarkersAsync();
            }
        }
    }

    private async void EditLevelDatNbt_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var world = _document;
        var file = world.ReadLevelDat();
        var editor = new NbtEditorWindow("level.dat", file.Document, async edited =>
        {
                await Task.Run(() => world.WriteLevelDat(new LevelDatFile(file.Version, edited)));
            var rows = new WorldInfoService().Inspect(world);
            InfoRows.Clear();
            foreach (var info in rows) InfoRows.Add(info);
            StatusText = "level.dat NBT 已应用到工作副本。";
        }) { Owner = this };
        editor.ShowDialog();
    }

    private void OpenPlayerNbtWorkspace_Click(object sender, RoutedEventArgs e)
        => OpenNbtWorkspace(NbtWorkspaceKind.Players);

    private void OpenVillageNbtWorkspace_Click(object sender, RoutedEventArgs e)
        => OpenNbtWorkspace(NbtWorkspaceKind.Villages);

    private void OpenStructureNbtWorkspace_Click(object sender, RoutedEventArgs e)
        => OpenNbtWorkspace(NbtWorkspaceKind.Structures);

    private void OpenMetadataNbtWorkspace_Click(object sender, RoutedEventArgs e)
        => OpenNbtWorkspace(NbtWorkspaceKind.Metadata);

    private void OpenNbtWorkspace(NbtWorkspaceKind kind)
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var world = _document;
        var window = new NbtWorkspaceWindow(world, kind, async () => await PrepareWorldMutationAsync(world)) { Owner = this };
        window.ShowDialog();
    }

    private async void SearchNbtKeys_Click(object sender, RoutedEventArgs e)
        => await SearchNbtKeysAsync();

    private async void NbtKeySearchText_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        e.Handled = true;
        await SearchNbtKeysAsync();
    }

    private async Task SearchNbtKeysAsync()
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var query = NbtKeySearchText.Text.Trim();
        if (query.Length == 0)
        {
            NbtKeyRows = Array.Empty<NbtKeySearchRow>();
            SelectedNbtKeyRow = null;
            NbtKeyStatusText = "请输入要搜索的 NBT / LevelDB 键；普通文本匹配 UTF-8 键，0x 前缀也匹配十六进制。";
            return;
        }
        if (_databaseBusy) return;
        _databaseBusy = true;
        NbtKeyStatusText = "正在读取并筛选 LevelDB 键…";
        try
        {
            var world = _document;
            var rows = await Task.Run(() =>
            {
                using var database = world.OpenDatabase(readOnly: true);
                var explicitHex = query.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? query[2..] : null;
                var output = new List<NbtKeySearchRow>();
                var strictUtf8 = new UTF8Encoding(false, true);
                foreach (var entry in database.Entries(includeValues: false))
                {
                    string keyText;
                    try { keyText = strictUtf8.GetString(entry.Key).Replace("\0", "\\0", StringComparison.Ordinal); }
                    catch (DecoderFallbackException) { keyText = "0x" + Convert.ToHexString(entry.Key).ToLowerInvariant(); }
                    var textMatch = keyText.Contains(query, StringComparison.OrdinalIgnoreCase);
                    var hex = explicitHex is { Length: > 0 } ? Convert.ToHexString(entry.Key).ToLowerInvariant() : string.Empty;
                    var hexMatch = explicitHex is { Length: > 0 } && hex.Contains(explicitHex, StringComparison.OrdinalIgnoreCase);
                    if (!textMatch && !hexMatch) continue;
                    var keyHex = Convert.ToHexString(entry.Key);
                    output.Add(new NbtKeySearchRow(entry.Key.ToArray(), keyText, LevelDbBrowserService.DescribeKey(entry.Key), -1, _viewedNbtKeys.Contains(keyHex)));
                    if (output.Count >= 500) break;
                }
                return (IReadOnlyList<NbtKeySearchRow>)output;
            });
            NbtKeyRows = rows;
            SelectedNbtKeyRow = rows.FirstOrDefault();
            NbtKeyStatusText = rows.Count == 500
                ? "找到至少 500 个匹配键；当前仅显示前 500 个。双击后会读取值并尝试按 NBT 解析。"
                : $"找到 {rows.Count:N0} 个匹配键。双击后会读取值并尝试按 NBT 解析。";
        }
        catch (Exception ex)
        {
            NbtKeyRows = Array.Empty<NbtKeySearchRow>();
            SelectedNbtKeyRow = null;
            NbtKeyStatusText = "搜索失败：" + ex.Message;
            MessageBox.Show(this, ex.Message, "搜索 NBT 键失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private async void OpenSelectedNbtKey_Click(object sender, RoutedEventArgs e)
        => await OpenSelectedNbtKeyAsync();

    private async void NbtKeyGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left) await OpenSelectedNbtKeyAsync();
    }

    private async Task OpenSelectedNbtKeyAsync()
    {
        if (_document is null || SelectedNbtKeyRow is null)
        {
            MessageBox.Show(this, "请先搜索并选择一个 LevelDB 键。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var world = _document;
        var selected = SelectedNbtKeyRow;
        var selectedHex = Convert.ToHexString(selected.Key);
        _viewedNbtKeys.Add(selectedHex);
        var viewedRows = NbtKeyRows.Select(row => Convert.ToHexString(row.Key) == selectedHex ? row with { Viewed = true } : row).ToArray();
        NbtKeyRows = viewedRows;
        SelectedNbtKeyRow = viewedRows.FirstOrDefault(row => Convert.ToHexString(row.Key) == selectedHex);
        try
        {
            var raw = await Task.Run(() =>
            {
                using var database = world.OpenDatabase(readOnly: true);
                return database.Get(selected.Key) ?? throw new InvalidDataException("该键没有值或已被删除。");
            });
            IReadOnlyList<ConsecutiveNbtRecord>? roots = null;
            string? decodeError = null;
            try
            {
                var decoded = ConsecutiveNbtCodec.Decode(raw);
                if (decoded.Count > 0) roots = decoded;
                else decodeError = "NBT 值为空。";
            }
            catch (Exception ex)
            {
                decodeError = ex.Message;
            }

            if (roots is null)
            {
                new RawDataWindow(selected.KeyText, raw, decodeError) { Owner = this }.ShowDialog();
                NbtKeyStatusText = $"{selected.KeyText}：无法解析为连续 Bedrock NBT，已按原始值打开。";
                return;
            }

            var rootWindow = new ConsecutiveNbtWindow(selected.KeyText, roots, async updated =>
            {
                await PrepareWorldMutationAsync(world);
                var encoded = ConsecutiveNbtCodec.Encode(updated);
                await Task.Run(() =>
                {
                    using var database = world.OpenDatabase(readOnly: false);
                    if (database.Get(selected.Key) is null) throw new InvalidDataException("该键已被删除，请重新搜索。");
                    database.Put(selected.Key, encoded, sync: true);
                });
                NbtKeyStatusText = $"已应用 NBT 键到工作副本：{selected.KeyText}";
            }) { Owner = this };
            rootWindow.ShowDialog();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "打开 NBT 键失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void LocateObjectOnMap_Click(object sender, RoutedEventArgs e)
    {
        var row = SelectedObjectRow;
        if (row is null || !row.X.HasValue || !row.Y.HasValue || !row.Z.HasValue)
        {
            MessageBox.Show(this, "所选对象没有可用坐标。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var x = row.X.Value;
        var y = row.Y.Value;
        var z = row.Z.Value;
        if (row.Dimension is >= 0 and <= 2) MapDimension.SelectedIndex = row.Dimension;
        _activeMapDimension = row.Dimension;
        _mapCenters[row.Dimension] = ((int)Math.Floor(x), (int)Math.Floor(z));
        MapCenterX.Text = ((int)Math.Floor(x)).ToString(CultureInfo.InvariantCulture);
        MapCenterZ.Text = ((int)Math.Floor(z)).ToString(CultureInfo.InvariantCulture);
        MapCenterY.Text = ((int)Math.Floor(y)).ToString(CultureInfo.InvariantCulture);
        _mapCenterY = (int)Math.Floor(y);
        await RenderMapAsync();
    }

    private async void MapObjectLayerOption_Changed(object sender, RoutedEventArgs e)
    {
        if (_mapChangingLayerOptions) return;
        if (ReferenceEquals(sender, MapShowHardcodedSpawners) && MapShowHardcodedSpawners.IsChecked != true)
            _selectedMapSpawner = null;
        if (ReferenceEquals(sender, MapShowVillages) && MapShowVillages.IsChecked != true)
            _selectedMapVillageIdentifier = null;
        if (!HasRenderedMap || _document is null || _databaseBusy) return;
        await RefreshMapObjectMarkersAsync();
    }

    private async void MapUngeneratedLayerOption_Changed(object sender, RoutedEventArgs e)
    {
        if (_mapChangingLayerOptions) return;
        if (!HasRenderedMap || _document is null || _databaseBusy) return;
        await RerenderMapPreservingViewportAsync();
    }

    private async void MapObjectLayersShowAll_Click(object sender, RoutedEventArgs e)
    {
        _mapChangingLayerOptions = true;
        try
        {
            MapShowPlayers.IsChecked = true;
            MapShowEntities.IsChecked = true;
            MapShowBlockEntities.IsChecked = true;
            MapShowSpawnPoints.IsChecked = true;
            MapShowHardcodedSpawners.IsChecked = true;
            MapShowVillages.IsChecked = _mapAxis == BedrockMapAxis.Y;
            MapShowUngenerated.IsChecked = true;
            MapBuildHeightLimits.IsChecked = true;
        }
        finally { _mapChangingLayerOptions = false; }
        if (!HasRenderedMap || _document is null || _databaseBusy) return;
        await RerenderMapPreservingViewportAsync();
    }

    private async void MapObjectLayersHideAll_Click(object sender, RoutedEventArgs e)
    {
        _mapChangingLayerOptions = true;
        try
        {
            MapShowPlayers.IsChecked = false;
            MapShowEntities.IsChecked = false;
            MapShowBlockEntities.IsChecked = false;
            MapShowSpawnPoints.IsChecked = false;
            MapShowHardcodedSpawners.IsChecked = false;
            MapShowVillages.IsChecked = false;
            MapShowUngenerated.IsChecked = false;
            MapBuildHeightLimits.IsChecked = false;
            _selectedMapSpawner = null;
            _selectedMapVillageIdentifier = null;
        }
        finally { _mapChangingLayerOptions = false; }
        if (!HasRenderedMap || _document is null || _databaseBusy) return;
        await RerenderMapPreservingViewportAsync();
    }

    private async Task RerenderMapPreservingViewportAsync()
    {
        var snapshot = CaptureMapViewportSnapshot();
        _mapViewportRestore = snapshot;
        _mapPreserveSelectionOnNextRender = true;
        await RenderMapAsync();
    }

    private async Task RefreshMapObjectMarkersAsync()
    {
        if (_document is null || !HasRenderedMap || _databaseBusy) return;
        _databaseBusy = true;
        try
        {
            _mapObjectMarkers = await LoadMapObjectMarkersAsync(_document, _lastMapDimension, _lastMapCenterX, _lastMapCenterZ, _lastMapRadius);
            await LoadMapFeatureOverlaysAsync(_document, _lastMapDimension, _lastMapCenterX, _lastMapCenterZ, _lastMapRadius);
            UpdateMapOverlay();
        }
        catch (Exception ex)
        {
            MapDetailText = "地图对象层读取失败：" + ex.Message;
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private Task<IReadOnlyList<MapObjectMarker>> LoadMapObjectMarkersAsync(WorldDocument document, int dimension, int centerX, int centerZ, int radius)
    {
        var includePlayers = MapShowPlayers?.IsChecked == true;
        var includeEntities = MapShowEntities?.IsChecked == true;
        var includeBlockEntities = MapShowBlockEntities?.IsChecked == true;
        return Task.Run<IReadOnlyList<MapObjectMarker>>(() =>
        {
            if (!includePlayers && !includeEntities && !includeBlockEntities) return Array.Empty<MapObjectMarker>();
            using var database = document.OpenDatabase(readOnly: true);
            var rows = new List<WorldObjectRow>();
            var centerChunkX = BedrockSurfaceRegionRenderer.FloorDiv(centerX, 16);
            var centerChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(centerZ, 16);
            var minimumBlockX = ((long)centerChunkX - radius) * 16;
            var maximumBlockXExclusive = ((long)centerChunkX + radius + 1) * 16;
            var minimumBlockZ = ((long)centerChunkZ - radius) * 16;
            var maximumBlockZExclusive = ((long)centerChunkZ + radius + 1) * 16;

            bool InLogicalRange(double x, double z)
                => x >= minimumBlockX && x < maximumBlockXExclusive && z >= minimumBlockZ && z < maximumBlockZExclusive;

            if (includePlayers)
            {
                var players = new PlayerNbtStore(database);
                foreach (var player in players.Records())
                {
                    var position = players.CurrentPosition(player);
                    if (position is null || position.Dimension != dimension || !InLogicalRange(position.X, position.Z)) continue;
                    rows.Add(RowForPlayer(player, position, players.UniqueId(player)));
                }
            }
            if (includeEntities || includeBlockEntities)
            {
                BedrockWorldObjectScanResult scan;
                if (radius <= 128)
                {
                    scan = new BedrockWorldObjectScanner(database).ScanRegion(centerChunkX, centerChunkZ, dimension, radius,
                        includeEntities, includeBlockEntities, maximumObjects: 10000);
                }
                else
                {
                    scan = new BedrockWorldObjectScanner(database).ScanAll(new HashSet<int> { dimension },
                        includeEntities, includeBlockEntities, maximumObjects: 200000);
                }
                rows.AddRange(scan.Objects
                    .Where(item => item.Position is { } position && InLogicalRange(position.X, position.Z))
                    .Select(RowForWorldObject));
            }
            return rows.Where(row => row.X.HasValue && row.Y.HasValue && row.Z.HasValue)
                .Select(row => new MapObjectMarker(row)).ToArray();
        });
    }


    private async Task LoadMapFeatureOverlaysAsync(WorldDocument document, int dimension, int centerX, int centerZ, int radius)
    {
        var showSpawn = MapShowSpawnPoints?.IsChecked == true;
        var showSpawners = MapShowHardcodedSpawners?.IsChecked == true;
        var showVillages = MapShowVillages?.IsChecked == true;
        var values = await Task.Run(() =>
        {
            using var database = document.OpenDatabase(readOnly: true);
            var spawn = showSpawn ? SpawnMapFeatureStore.Read(document, database).Where(item => item.Dimension == dimension).ToArray() : Array.Empty<SpawnMapFeature>();
            IReadOnlyList<HardcodedSpawnersRecord> spawners = Array.Empty<HardcodedSpawnersRecord>();
            if (showSpawners)
            {
                var centerChunkX = BedrockSurfaceRegionRenderer.FloorDiv(centerX, 16);
                var centerChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(centerZ, 16);
                var minimumChunkX = ClampLongToInt((long)centerChunkX - radius - 1);
                var minimumChunkZ = ClampLongToInt((long)centerChunkZ - radius - 1);
                var maximumChunkX = ClampLongToInt((long)centerChunkX + radius + 1);
                var maximumChunkZ = ClampLongToInt((long)centerChunkZ + radius + 1);
                spawners = new HardcodedSpawnersStore(database).RecordsInChunkRectangle(dimension,
                    minimumChunkX, minimumChunkZ, maximumChunkX, maximumChunkZ);
            }
            var villages = showVillages ? new VillageMapFeatureStore(database).Features().Where(item => item.Dimension == dimension).ToArray() : Array.Empty<VillageMapFeature>();
            return (Spawn: (IReadOnlyList<SpawnMapFeature>)spawn, Spawners: spawners, Villages: (IReadOnlyList<VillageMapFeature>)villages);
        });
        _spawnMapFeatures = values.Spawn;
        _spawnerMapRecords = values.Spawners;
        _villageMapFeatures = values.Villages;
    }


    private void ResetMapForWorld(WorldDocument document)
    {
        try
        {
            var root = document.ReadLevelDat().Document.Root;
            _spawnX = root.IntValue("SpawnX") ?? 0;
            _spawnZ = root.IntValue("SpawnZ") ?? 0;
        }
        catch
        {
            _spawnX = 0;
            _spawnZ = 0;
        }

        _mapCenters[0] = (_spawnX, _spawnZ);
        _mapCenters[1] = (0, 0);
        _mapCenters[2] = (0, 0);
        _activeMapDimension = 0;
        if (MapDimension is not null) MapDimension.SelectedIndex = 0;
        if (MapCenterX is not null) MapCenterX.Text = _spawnX.ToString();
        if (MapCenterZ is not null) MapCenterZ.Text = _spawnZ.ToString();
        _mapRegion = null;
        _crossSectionRegion = null;
        _mapObjectMarkers = Array.Empty<MapObjectMarker>();
        _selectedMapBlock = null;
        ClearMapBlockDetailPanel(collapse: true);
        _selectedMapSpawner = null;
        _selectedMapVillageIdentifier = null;
        _selectedMapChunk = null;
        _mapRegionSelection = null;
        _mapRegionFirstCorner = null;
        _mapRegionSelecting = false;
        _mapSelectionDragEdge = null;
        UpdateMapRegionSelectionButton();
        _mapAxis = BedrockMapAxis.Y;
        _mapCenterY = 63;
        _mapChangingLayerOptions = true;
        try
        {
            if (MapAxis is not null) MapAxis.SelectedIndex = 1;
            if (MapChunkGrid is not null) MapChunkGrid.IsChecked = false;
            if (MapShowPlayers is not null) MapShowPlayers.IsChecked = true;
            if (MapShowEntities is not null) MapShowEntities.IsChecked = true;
            if (MapShowBlockEntities is not null) MapShowBlockEntities.IsChecked = true;
            if (MapShowSpawnPoints is not null) MapShowSpawnPoints.IsChecked = true;
            if (MapShowHardcodedSpawners is not null) MapShowHardcodedSpawners.IsChecked = false;
            if (MapShowVillages is not null) MapShowVillages.IsChecked = false;
            if (MapShowUngenerated is not null) MapShowUngenerated.IsChecked = false;
            if (MapBuildHeightLimits is not null) MapBuildHeightLimits.IsChecked = true;
        }
        finally
        {
            _mapChangingLayerOptions = false;
        }
        if (MapCenterY is not null) MapCenterY.Text = "63";
        if (MapRenderMode is not null) MapRenderMode.SelectedIndex = 0;
        if (MapImage is not null)
        {
            MapImage.Source = null;
            MapImage.Width = double.NaN;
            MapImage.Height = double.NaN;
        }
        _mapZoom = 4.0;
        _mapSurfaceInsetX = 0;
        _mapSurfaceInsetY = 0;
        if (MapSurfaceHost is not null) MapSurfaceHost.Margin = new Thickness(0);
        MapStatusText = $"准备自动渲染 · 主世界默认中心为出生点 ({_spawnX}, {_spawnZ})";
        MapDetailText = "地图会按当前窗口与缩放自动加载可见区块；移动/缩放会自动续载。选择方块后右侧自动展开 NBT 详情。";
        OnPropertyChanged(nameof(MapZoomText));
    }

    private int SelectedMapDimension()
    {
        if (MapDimension.SelectedItem is ComboBoxItem item && item.Tag is string tag && int.TryParse(tag, out var dimension))
            return dimension;
        return 0;
    }

    private int DynamicMapRadiusForViewport(double pixelsPerBlock)
    {
        var safePixelsPerBlock = Math.Max(0.00000001, pixelsPerBlock);
        var viewportWidth = Math.Max(320.0, MapScrollViewer?.ViewportWidth ?? 0.0);
        var viewportHeight = Math.Max(240.0, MapScrollViewer?.ViewportHeight ?? 0.0);
        var visibleBlocks = Math.Max(viewportWidth, viewportHeight) / safePixelsPerBlock;
        var desiredSideChunksDouble = Math.Ceiling(visibleBlocks / 16.0) + 4.0;
        var desiredSideChunks = desiredSideChunksDouble >= 65535.0
            ? 65535
            : Math.Max(3, (int)desiredSideChunksDouble);
        if ((desiredSideChunks & 1) == 0) desiredSideChunks++;
        desiredSideChunks = Math.Min(65535, desiredSideChunks);
        return Math.Max(1, Math.Min(32767, (desiredSideChunks - 1) / 2));
    }

    private BedrockMapAxis SelectedMapAxis()
    {
        if (MapAxis.SelectedItem is ComboBoxItem item && item.Tag is string tag && Enum.TryParse<BedrockMapAxis>(tag, true, out var axis))
            return axis;
        return BedrockMapAxis.Y;
    }

    private BedrockMapRenderMode SelectedMapRenderMode()
    {
        if (MapRenderMode.SelectedItem is ComboBoxItem item && item.Tag is string tag && Enum.TryParse<BedrockMapRenderMode>(tag, true, out var mode))
            return mode;
        return BedrockMapRenderMode.Surface;
    }

    private static string MapModeDisplayName(BedrockMapRenderMode mode, BedrockMapAxis axis) => mode switch
    {
        BedrockMapRenderMode.Surface => axis == BedrockMapAxis.Y ? "地表" : "方块",
        BedrockMapRenderMode.Height => "高度",
        BedrockMapRenderMode.Minerals => "矿物",
        BedrockMapRenderMode.Biome => "生物群系",
        BedrockMapRenderMode.TickingAreas => "常加载区块",
        BedrockMapRenderMode.Slime => "史莱姆区块",
        _ => mode.ToString()
    };

    private bool HasRenderedMap => _mapRegion is not null || _crossSectionRegion is not null;

    private (int Width, int Height) RenderedMapSize()
        => _crossSectionRegion is not null ? (_crossSectionRegion.Width, _crossSectionRegion.Height)
            : _mapRegion is not null ? (_mapRegion.Width, _mapRegion.Height)
            : (0, 0);

    private void MapAxis_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MapAxis is null || MapCenterY is null || MapChunkGrid is null || MapRenderMode is null) return;
        _mapAxis = SelectedMapAxis();
        var vertical = _mapAxis != BedrockMapAxis.Y;
        MapCenterY.IsEnabled = vertical;
        MapCenterYLabel.Opacity = vertical ? 1.0 : 0.45;
        MapChunkGrid.Content = vertical ? "子区块网格" : "区块网格";
        MapBuildHeightLimits.IsEnabled = vertical;
        MapBuildHeightLimits.Opacity = vertical ? 1.0 : 0.45;
        MapShowVillages.IsEnabled = !vertical;
        MapShowVillages.Opacity = vertical ? 0.45 : 1.0;
        MapShowUngenerated.Content = vertical ? "未生成子区块" : "未生成区块";
        MapStatusText = vertical
            ? $"{_mapAxis} 剖面 · 固定 {(_mapAxis == BedrockMapAxis.X ? "X" : "Z")} 坐标，中心 Y={_mapCenterY} · 自动按视口渲染"
            : "Y 顶视图 · 自动按视口渲染";
        RenderMapAfterControlChange();
    }

    private void MapRenderMode_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MapRenderMode is null || MapAxis is null) return;
        var mode = SelectedMapRenderMode();
        var axis = SelectedMapAxis();
        MapStatusText = mode switch
        {
            BedrockMapRenderMode.Minerals when axis != BedrockMapAxis.Y => MapShowUngenerated?.IsChecked == true
                ? "矿物剖面：未生成子区块已开启，仅投影当前剖面所在的 16 格区块。"
                : "矿物剖面：从当前 X/Z 向负方向投影 129 格（当前格 + 后方 128 格）。",
            BedrockMapRenderMode.Biome when axis != BedrockMapAxis.Y => "生物群系剖面：读取当前 X/Z 切面位置的生物群系属性。",
            BedrockMapRenderMode.TickingAreas when axis != BedrockMapAxis.Y => "常加载区块剖面：按切面所在区块显示常加载状态。",
            BedrockMapRenderMode.Slime when axis != BedrockMapAxis.Y => "史莱姆区块剖面：按基岩版区块坐标算法显示，不读取世界种子。",
            _ => $"{MapModeDisplayName(mode, axis)}模式 · 自动按视口渲染"
        };
        RenderMapAfterControlChange();
    }

    private void MapDimension_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MapCenterX is null || MapCenterZ is null || MapDimension is null) return;
        if (int.TryParse(MapCenterX.Text.Trim(), out var oldX) && int.TryParse(MapCenterZ.Text.Trim(), out var oldZ))
            _mapCenters[_activeMapDimension] = (oldX, oldZ);

        var dimension = SelectedMapDimension();
        _activeMapDimension = dimension;
        var center = _mapCenters.TryGetValue(dimension, out var saved) ? saved : (0, 0);
        MapCenterX.Text = center.Item1.ToString();
        MapCenterZ.Text = center.Item2.ToString();
        MapStatusText = $"{BedrockDimensionNames.DisplayName(dimension)} · 中心 ({center.Item1}, {center.Item2}) · 自动按视口渲染";
        RenderMapAfterControlChange();
    }

    private void RenderMapAfterControlChange()
    {
        if (_document is null || !HasRenderedMap || _databaseBusy) return;
        _ = RenderMapAsync();
    }

    private async void RenderMap_Click(object sender, RoutedEventArgs e)
        => await RenderMapAsync();

    private async Task RenderMapAsync(long? expectedInteractionVersion = null)
    {
        var radiusOverride = _mapRenderRadiusOverride;
        var viewportRestore = _mapViewportRestore;
        var preserveSelection = _mapPreserveSelectionOnNextRender;
        _mapRenderRadiusOverride = null;
        _mapViewportRestore = null;
        _mapPreserveSelectionOnNextRender = false;

        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;
        if (!int.TryParse(MapCenterX.Text.Trim(), out var centerX) || !int.TryParse(MapCenterZ.Text.Trim(), out var centerZ))
        {
            MessageBox.Show(this, "地图中心 X/Z 必须为 32 位整数。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var axis = SelectedMapAxis();
        var mode = SelectedMapRenderMode();
        var showUngeneratedTexture = MapShowUngenerated?.IsChecked == true;
        if (axis != BedrockMapAxis.Y && !int.TryParse(MapCenterY.Text.Trim(), out _mapCenterY))
        {
            MessageBox.Show(this, "X/Z 剖面的中心 Y 必须为 32 位整数。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var dimension = SelectedMapDimension();
        var radius = Math.Clamp(radiusOverride ?? DynamicMapRadiusForViewport(
            HasRenderedMap ? CurrentMapPixelsPerBlock() : _mapZoom), 1, 32767);
        if (!preserveSelection)
        {
            _selectedMapBlock = null;
            ClearMapBlockDetailPanel(collapse: true);
            _selectedMapSpawner = null;
            _selectedMapVillageIdentifier = null;
            _selectedMapChunk = null;
            _mapRegionSelection = null;
            _mapRegionFirstCorner = null;
            _mapRegionSelecting = false;
            UpdateMapRegionSelectionButton();
        }
        BlockTextureOverrideStore.Reload();
        _mapCenters[dimension] = (centerX, centerZ);
        _activeMapDimension = dimension;
        _mapAxis = axis;
        _databaseBusy = true;
        var modeText = MapModeDisplayName(mode, axis);
        MapStatusText = axis == BedrockMapAxis.Y
            ? $"正在渲染 {BedrockDimensionNames.DisplayName(dimension)} · Y 顶视图/{modeText} · 中心 ({centerX}, {centerZ}) · 自动视口 {(long)radius * 2 + 1}×{(long)radius * 2 + 1} 区块…"
            : $"正在渲染 {BedrockDimensionNames.DisplayName(dimension)} · {axis} 剖面/{modeText} · 中心 ({centerX}, {_mapCenterY}, {centerZ}) · 自动视口 {(long)radius * 2 + 1}×{(long)radius * 2 + 1} 区块…";
        StatusText = "正在读取地图 SubChunk…";

        try
        {
            var document = _document;
            if (axis == BedrockMapAxis.Y)
            {
                var region = await Task.Run(() =>
                {
                    using var database = document.OpenDatabase(readOnly: true);
                    return new BedrockSurfaceRegionRenderer(database).Render(
                        dimension, centerX, centerZ, radius, drawChunkGrid: false, mode: mode,
                        maximumSamplesPerAxis: WindowsMapMaximumSamplesPerAxis, maximumRasterSide: WindowsMapMaximumRasterSide,
                        showUngeneratedTexture: showUngeneratedTexture);
                });

                if (expectedInteractionVersion.HasValue && expectedInteractionVersion.Value != _mapInteractionVersion)
                {
                    ScheduleDynamicMapRefresh();
                    return;
                }
                _mapRegion = region;
                _crossSectionRegion = null;
                MapImage.Source = CreateMapBitmap(region.Width, region.Height, region.Rgb);
                ApplyRenderedViewport(viewportRestore);
                var errorText = region.Errors.Count == 0 ? string.Empty : $" · {region.Errors.Count} 个解码异常";
                var sampleText = region.IsDownsampled
                    ? $" · 代表采样 {region.SampledChunkCount} 区块/步长 {region.SampleStrideChunks}"
                    : string.Empty;
                MapStatusText = mode switch
                {
                    BedrockMapRenderMode.TickingAreas => $"Y/常加载区块 · 动态 {region.LogicalWidthBlocks / 16}×{region.LogicalHeightBlocks / 16} 区块 · 区域 {region.TickingAreaCount} 个 · 当前采样覆盖 {region.VisibleTickingChunkCount}{sampleText}{errorText}",
                    BedrockMapRenderMode.Slime => $"Y/史莱姆区块 · 逻辑 {region.LogicalWidthBlocks}×{region.LogicalHeightBlocks} 方块 · 位图 {region.Width}×{region.Height}{sampleText}{errorText}",
                    _ => $"Y/{modeText} · 逻辑 {region.LogicalWidthBlocks}×{region.LogicalHeightBlocks} 方块 · 位图 {region.Width}×{region.Height} · 采样已生成 {region.GeneratedChunkCount} · 采样未生成 {region.MissingChunkCount}{sampleText}{errorText}"
                };
                MapDetailText = mode switch
                {
                    BedrockMapRenderMode.TickingAreas => "绿=普通常加载，橙=预加载，紫=区域重叠；低倍率代表采样只影响显示，点击会重新读取真实区块。",
                    BedrockMapRenderMode.Slime => "绿色为史莱姆区块；低倍率代表采样只影响显示，点击按真实世界 X/Z 重新计算。",
                    BedrockMapRenderMode.Biome => "生物群系模式读取 Data3D/Data2D/LegacyTerrain；大范围低倍率自动代表采样，点击重新读取真实位置。",
                    BedrockMapRenderMode.Height => "高度模式：水体使用蓝色高度渐变，其余方块使用灰度高度渐变；拖动/缩放会持续扩展视口。",
                    _ => $"中心：{BedrockDimensionNames.DisplayName(dimension)} X={centerX}, Z={centerZ} · 逻辑原点 X={region.OriginBlockX}, Z={region.OriginBlockZ} · 拖动/缩放会持续续载。"
                };
            }
            else
            {
                var sideBlocks = checked((radius * 2 + 1) * 16);
                var projectionDepth = mode == BedrockMapRenderMode.Minerals ? 129 : 128;
                var region = await Task.Run(() =>
                {
                    using var database = document.OpenDatabase(readOnly: true);
                    return new BedrockCrossSectionRenderer(database).Render(
                        axis, centerX, centerZ, _mapCenterY, sideBlocks, dimension, mode,
                        drawSubChunkGrid: false, drawBuildHeightLimits: false, projectionDepth: projectionDepth,
                        maximumRasterSide: WindowsMapMaximumRasterSide, showUngeneratedTexture: showUngeneratedTexture);
                });

                if (expectedInteractionVersion.HasValue && expectedInteractionVersion.Value != _mapInteractionVersion)
                {
                    ScheduleDynamicMapRefresh();
                    return;
                }
                _crossSectionRegion = region;
                _mapRegion = null;
                MapImage.Source = CreateMapBitmap(region.Width, region.Height, region.Rgb);
                ApplyRenderedViewport(viewportRestore);
                var errorText = region.Errors.Count == 0 ? string.Empty : $" · {region.Errors.Count} 个解码异常";
                var horizontalName = axis == BedrockMapAxis.X ? "Z" : "X";
                var fixedName = axis == BedrockMapAxis.X ? "X" : "Z";
                var fixedValue = axis == BedrockMapAxis.X ? centerX : centerZ;
                var projectionChunkMinimum = BedrockSurfaceRegionRenderer.FloorDiv(fixedValue, 16) * 16;
                var projectionChunkMaximum = projectionChunkMinimum + 15;
                var projectionText = mode switch
                {
                    BedrockMapRenderMode.Biome or BedrockMapRenderMode.TickingAreas or BedrockMapRenderMode.Slime => $"{fixedName}={fixedValue}（精确切面）",
                    _ when showUngeneratedTexture => $"{fixedName}={projectionChunkMaximum} → {projectionChunkMinimum}（当前区块）",
                    BedrockMapRenderMode.Minerals => $"{fixedName}={fixedValue} → {fixedValue - 128}",
                    _ => $"{fixedName}={fixedValue} → {fixedValue - 127}"
                };
                var sampling = region.SampleStride > 1 ? $" · 采样步长 {region.SampleStride}" : string.Empty;
                MapStatusText = $"{axis}/{modeText} · 逻辑 {region.LogicalHorizontalBlocks}×{region.LogicalVerticalBlocks} 方块 · 位图 {region.Width}×{region.Height} · 投影 {projectionText} · 解码 {region.DecodedSubChunks} SubChunk{sampling}{errorText}";
                MapDetailText = mode switch
                {
                    BedrockMapRenderMode.Biome => $"{axis} 生物群系剖面：固定 {fixedName}={fixedValue}；拖动/缩放可持续扩展，降采样点击会精确重读。",
                    BedrockMapRenderMode.TickingAreas => $"{axis} 常加载区块剖面：固定 {fixedName}={fixedValue}；拖动/缩放可持续扩展。",
                    BedrockMapRenderMode.Slime => $"{axis} 史莱姆区块剖面：固定 {fixedName}={fixedValue}；点击按真实区块坐标计算。",
                    _ => $"{axis} 剖面：固定 {fixedName}={fixedValue} · 横轴 {horizontalName}={region.OriginHorizontal}…{region.OriginHorizontal + region.LogicalHorizontalBlocks - 1} · Y={region.MinimumY}…{region.MaximumY}。"
                };
            }
            _lastMapRadius = radius;
            _lastMapMode = mode;
            _lastMapDimension = dimension;
            _lastMapCenterX = centerX;
            _lastMapCenterZ = centerZ;
            _lastMapCenterY = _mapCenterY;
            if (expectedInteractionVersion.HasValue && expectedInteractionVersion.Value != _mapInteractionVersion)
            {
                ScheduleDynamicMapRefresh();
                return;
            }
            _mapObjectMarkers = await LoadMapObjectMarkersAsync(document, dimension, centerX, centerZ, radius);
            await LoadMapFeatureOverlaysAsync(document, dimension, centerX, centerZ, radius);
            UpdateMapOverlay();
            StatusText = "地图渲染完成。";
        }
        catch (Exception ex)
        {
            MapStatusText = "地图渲染失败。";
            StatusText = "地图渲染失败。";
            if (viewportRestore is null)
                MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
            else
                MapDetailText = "动态续载失败：" + ex.Message;
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private void ApplyRenderedViewport(MapViewportSnapshot? snapshot)
    {
        _mapApplyingViewport = true;
        try
        {
            if (snapshot is null || snapshot.Axis != _mapAxis)
            {
                ApplyMapZoom(_mapZoom, preserveViewportCenter: false);
                MapScrollViewer.UpdateLayout();
                ScrollMapToRenderedCenter();
                return;
            }

            var rasterWidth = Math.Max(1, RenderedMapSize().Width);
            var logicalWidth = _mapRegion?.LogicalWidthBlocks ?? _crossSectionRegion?.LogicalHorizontalBlocks ?? rasterWidth;
            var targetZoom = snapshot.PixelsPerBlock * logicalWidth / rasterWidth;
            ApplyMapZoom(targetZoom, preserveViewportCenter: false);
            MapScrollViewer.UpdateLayout();

            double pixelX;
            double pixelY;
            if (_mapRegion is { } surface)
            {
                pixelX = surface.PixelXForWorld(snapshot.WorldHorizontal);
                pixelY = surface.PixelZForWorld(snapshot.WorldVertical);
            }
            else if (_crossSectionRegion is { } cross)
            {
                pixelX = cross.PixelXForWorld(snapshot.WorldHorizontal);
                pixelY = cross.PixelYForWorld(snapshot.WorldVertical);
            }
            else return;

            MapScrollViewer.ScrollToHorizontalOffset(_mapSurfaceInsetX + pixelX * _mapZoom - MapScrollViewer.ViewportWidth / 2.0);
            MapScrollViewer.ScrollToVerticalOffset(_mapSurfaceInsetY + pixelY * _mapZoom - MapScrollViewer.ViewportHeight / 2.0);
        }
        finally
        {
            _mapApplyingViewport = false;
            OnPropertyChanged(nameof(MapZoomText));
        }
    }

    private static BitmapSource CreateMapBitmap(int width, int height, uint[] rgb)
    {
        var stride = checked(width * 4);
        var buffer = new byte[checked(stride * height)];
        for (var index = 0; index < rgb.Length; index++)
        {
            var color = rgb[index];
            var offset = index * 4;
            buffer[offset] = (byte)(color & 0xFF);
            buffer[offset + 1] = (byte)((color >> 8) & 0xFF);
            buffer[offset + 2] = (byte)((color >> 16) & 0xFF);
            buffer[offset + 3] = 0xFF;
        }
        var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, buffer, stride);
        bitmap.Freeze();
        return bitmap;
    }

    private void MapSpawn_Click(object sender, RoutedEventArgs e)
    {
        MapDimension.SelectedIndex = 0;
        _activeMapDimension = 0;
        _mapCenters[0] = (_spawnX, _spawnZ);
        MapCenterX.Text = _spawnX.ToString();
        MapCenterZ.Text = _spawnZ.ToString();
        MapStatusText = $"主世界出生点 ({_spawnX}, {_spawnZ}) · 正在自动定位";
        RenderMapAfterControlChange();
    }

    private void MapZoomIn_Click(object sender, RoutedEventArgs e)
    {
        _mapInteractionVersion++;
        ApplyMapZoom(_mapZoom * 1.25, preserveViewportCenter: true);
    }

    private void MapZoomOut_Click(object sender, RoutedEventArgs e)
    {
        _mapInteractionVersion++;
        ApplyMapZoom(_mapZoom / 1.25, preserveViewportCenter: true);
    }

    private void MapFit_Click(object sender, RoutedEventArgs e)
    {
        if (!HasRenderedMap) return;
        _mapInteractionVersion++;
        var size = RenderedMapSize();
        var width = Math.Max(1.0, MapScrollViewer.ViewportWidth - 4.0);
        var height = Math.Max(1.0, MapScrollViewer.ViewportHeight - 4.0);
        var scale = Math.Min(width / size.Width, height / size.Height);
        ApplyMapZoom(scale, preserveViewportCenter: false);
        ScrollMapToRenderedCenter();
    }

    private async void EditSelectedMapBlock_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null)
        {
            MessageBox.Show(this, "请先打开世界。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;
        if (_selectedMapBlock is not { } selection)
        {
            MessageBox.Show(this, "请先在地图上选择方块；X/Z 剖面也可以选择未生成位置。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        BedrockBlockRecord block;
        try
        {
            using var database = _document.OpenDatabase(readOnly: true);
            block = new BedrockBlockStore(database).ReadBlockForEditing(selection.Dimension, selection.X, selection.Y, selection.Z);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "读取方块失败", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        if (block.Layers.Count == 0)
        {
            SetSelectedMapBlock(null);
            MessageBox.Show(this, "该坐标没有可编辑的 SubChunk/LegacyTerrain storage。请重新渲染并选择已生成方块。", "MCBEEditor",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var isLegacy = block.Layers.All(layer => layer.Nbt is null);
        var canCreateNextStorage = block.BackingKind == BedrockSubChunkBackingKind.SubChunk
            && (isLegacy ? block.Layers.Count < 2 : block.Layers.Count < byte.MaxValue);
        var storageIndex = block.PreferredLayerIndex;
        if (block.Layers.Count > 1 || canCreateNextStorage)
        {
            var picker = new BlockLayerPickerWindow(block) { Owner = this };
            if (picker.ShowDialog() != true) return;
            storageIndex = picker.StorageIndex;
        }
        var state = storageIndex < block.Layers.Count
            ? block.Layers[storageIndex]
            : isLegacy
                ? new BedrockBlockState(null, 0, 0)
                : (BedrockPaletteFormat.Detect(block.Layers) ?? new BedrockPaletteFormat(false, null)).Air;
        var world = _document;

        if (state.Nbt is not null)
        {
            var editor = new NbtEditorWindow(
                $"方块 storage {storageIndex} · {BedrockDimensionNames.DisplayName(block.Dimension)} ({block.X}, {block.Y}, {block.Z})",
                new NbtDocument(string.Empty, NbtDocumentTools.DeepClone(state.Nbt)), async edited =>
                {
                    await PrepareWorldMutationAsync(world);
                    await Task.Run(() =>
                    {
                        using var database = world.OpenDatabase(readOnly: false);
                        new BedrockBlockStore(database).SaveModernState(block.Dimension, block.X, block.Y, block.Z, storageIndex, edited);
                    });
                    StatusText = $"方块已应用到工作副本：{BedrockDimensionNames.DisplayName(block.Dimension)} ({block.X}, {block.Y}, {block.Z}) storage {storageIndex}";
                }, Array.Empty<string>(), NbtEncoding.LittleEndian) { Owner = this };
            editor.ShowDialog();
            if (!editor.DidSave) return;
        }
        else
        {
            var editor = new LegacyBlockEditWindow(block, storageIndex, state) { Owner = this };
            if (editor.ShowDialog() != true) return;
            try
            {
                _databaseBusy = true;
                StatusText = "正在应用旧版数字方块到工作副本…";
                await PrepareWorldMutationAsync(world);
                await Task.Run(() =>
                {
                    using var database = world.OpenDatabase(readOnly: false);
                    new BedrockBlockStore(database).SaveLegacyState(block.Dimension, block.X, block.Y, block.Z, storageIndex, editor.LegacyId, editor.LegacyData);
                });
                StatusText = $"旧版数字方块已应用到工作副本：{BedrockDimensionNames.DisplayName(block.Dimension)} ({block.X}, {block.Y}, {block.Z}) storage {storageIndex}";
            }
            catch (Exception ex)
            {
                StatusText = "应用方块失败。";
                MessageBox.Show(this, ex.Message, "应用方块失败", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }
            finally
            {
                _databaseBusy = false;
            }
        }

        SetSelectedMapBlock(null);
        if (HasRenderedMap) await RenderMapAsync();
    }


    private void RegionAdvanced_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null || _mapRegionSelection is not { } selection)
        {
            MessageBox.Show(this, "请先在 Y 顶视图完成区域框选。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var world = _document;
        var window = new RegionOperationsWindow(world, selection,
            () => PrepareWorldMutationAsync(world),
            message => { StatusText = message; if (HasRenderedMap) _ = RenderMapAsync(); },
            hit => LocateRegionSearchHit(hit),
            position => _ = LocateChunkOnMapAsync(position),
            updated => { _mapRegionSelection = updated; UpdateMapOverlay(); MapDetailText = $"框选范围已更新：X={updated.MinimumX}…{updated.MaximumX}, Z={updated.MinimumZ}…{updated.MaximumZ}"; })
        { Owner = this };
        window.ShowDialog();
    }

    private void LocateRegionSearchHit(BedrockRegionBlockHit hit)
    {
        SetSelectedMapBlock(new MapBlockSelection(hit.Dimension, hit.X, hit.Y, hit.Z, hit.Name));
        MapDetailText = $"区域搜索命中：{BedrockDimensionNames.DisplayName(hit.Dimension)} X={hit.X}, Y={hit.Y}, Z={hit.Z} · storage {hit.StorageIndex} · {hit.Name}";
        if (_mapRegion is { } surface && hit.Dimension == surface.Dimension)
        {
            var px = surface.PixelXForWorld(hit.X + 0.5);
            var pz = surface.PixelZForWorld(hit.Z + 0.5);
            MapScrollViewer.ScrollToHorizontalOffset(_mapSurfaceInsetX + px * _mapZoom - MapScrollViewer.ViewportWidth / 2.0);
            MapScrollViewer.ScrollToVerticalOffset(_mapSurfaceInsetY + pz * _mapZoom - MapScrollViewer.ViewportHeight / 2.0);
        }
    }

    private void MapSpawner_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null) return;
        var dimension = HasRenderedMap ? _lastMapDimension : SelectedMapDimension();
        var x = _selectedMapBlock?.X ?? _lastMapCenterX;
        var z = _selectedMapBlock?.Z ?? _lastMapCenterZ;
        var chunk = new ChunkPosition(BedrockSurfaceRegionRenderer.FloorDiv(x, 16), BedrockSurfaceRegionRenderer.FloorDiv(z, 16), dimension);
        var world = _document;
        var window = new HardcodedSpawnersEditorWindow(world, chunk, () => PrepareWorldMutationAsync(world), message =>
        {
            StatusText = message;
            MapShowHardcodedSpawners.IsChecked = true;
            if (HasRenderedMap) _ = RefreshMapObjectMarkersAsync();
        }) { Owner = this };
        window.ShowDialog();
    }


    private void MapTickingAreas_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null) return;
        var dimension = HasRenderedMap ? _lastMapDimension : SelectedMapDimension();
        var x = _selectedMapBlock?.X ?? _lastMapCenterX;
        var z = _selectedMapBlock?.Z ?? _lastMapCenterZ;
        var focus = new ChunkPosition(BedrockSurfaceRegionRenderer.FloorDiv(x, 16), BedrockSurfaceRegionRenderer.FloorDiv(z, 16), dimension);
        OpenTickingAreaManager(focus);
    }

    private void OpenTickingAreaManager(ChunkPosition focus)
    {
        if (_document is null) return;
        var world = _document;
        var window = new TickingAreaManagerWindow(world, () => PrepareWorldMutationAsync(world), message =>
        {
            StatusText = message;
            if (HasRenderedMap) _ = RenderMapAsync();
        }, focus, position => _ = LocateChunkOnMapAsync(position)) { Owner = this };
        window.ShowDialog();
    }

    private void SelectMapRegion_Click(object sender, RoutedEventArgs e)
    {
        if (_mapRegionSelecting)
        {
            _mapRegionSelecting = false;
            _mapRegionFirstCorner = null;
            UpdateMapRegionSelectionButton();
            UpdateMapOverlay();
            MapDetailText = _mapRegionSelection is null ? "已退出框选模式。" : "已退出框选模式；保留当前框选区域。";
            return;
        }
        if (_mapRegion is null || _crossSectionRegion is not null || _mapAxis != BedrockMapAxis.Y)
        {
            MessageBox.Show(this, "区域框选仅在已渲染的 Y 顶视图可用。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        _mapRegionSelection = null;
        _mapRegionFirstCorner = null;
        _mapRegionSelecting = true;
        UpdateMapRegionSelectionButton();
        UpdateMapOverlay();
        MapDetailText = "区域框选：请在 Y 顶视图单击第一个 X/Z 角点；再次点击“框选”可退出。未生成区块也可以作为框选边界。";
    }

    private void UpdateMapRegionSelectionButton()
    {
        if (MapRegionSelectButton is null) return;
        MapRegionSelectButton.Content = _mapRegionSelecting ? "退出框选" : "框选";
        MapRegionSelectButton.ToolTip = _mapRegionSelecting ? "退出框选模式" : "进入区域框选模式";
    }

    private void ClearMapRegion_Click(object sender, RoutedEventArgs e)
    {
        _mapRegionSelection = null;
        _mapRegionFirstCorner = null;
        _mapRegionSelecting = false;
        _mapSelectionDragEdge = null;
        if (MapOverlayCanvas.IsMouseCaptured) MapOverlayCanvas.ReleaseMouseCapture();
        UpdateMapRegionSelectionButton();
        UpdateMapOverlay();
        MapDetailText = "区域框选已清除。";
    }

    private void AlignMapRegionToChunkBounds_Click(object sender, RoutedEventArgs e)
    {
        if (_mapRegionSelection is not { } selection)
        {
            MessageBox.Show(this, "请先在 Y 顶视图完成区域框选。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var minimumChunkX = BedrockSurfaceRegionRenderer.FloorDiv(selection.MinimumX, 16);
        var maximumChunkX = BedrockSurfaceRegionRenderer.FloorDiv(selection.MaximumX, 16);
        var minimumChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(selection.MinimumZ, 16);
        var maximumChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(selection.MaximumZ, 16);
        var aligned = new MapRegionSelection(
            selection.Dimension,
            checked(minimumChunkX * 16),
            checked(minimumChunkZ * 16),
            checked(maximumChunkX * 16 + 15),
            checked(maximumChunkZ * 16 + 15));
        _mapRegionSelection = aligned;
        _mapRegionFirstCorner = null;
        UpdateMapOverlay();
        MapDetailText = $"已向外对齐区块边界：X={aligned.MinimumX}…{aligned.MaximumX}, Z={aligned.MinimumZ}…{aligned.MaximumZ}，覆盖 {((long)maximumChunkX - minimumChunkX + 1) * ((long)maximumChunkZ - minimumChunkZ + 1):N0} 个完整区块。";
    }

    private async void FillMapRegion_Click(object sender, RoutedEventArgs e)
    {
        if (_mapRegionSelection is not { } selection)
        {
            MessageBox.Show(this, "请先在 Y 顶视图点击“框选”，再依次单击两个 X/Z 角点。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var dialog = new RegionFillWindow(selection, _lastMapCenterY) { Owner = this };
        if (dialog.ShowDialog() != true) return;
        var command = FormattableString.Invariant($"fill {CommandDimensionToken(selection.Dimension)} {selection.MinimumX} {dialog.MinimumY} {selection.MinimumZ} {selection.MaximumX} {dialog.MaximumY} {selection.MaximumZ} {dialog.Block0} {dialog.States0}");
        if (dialog.Block1 is not null)
            command += $" {dialog.Block1} {dialog.States1}";
        CommandInput.Text = command;
        await ExecuteCommandAsync();
    }

    private async void CloneMapRegion_Click(object sender, RoutedEventArgs e)
    {
        if (_mapRegionSelection is not { } selection)
        {
            MessageBox.Show(this, "请先在 Y 顶视图点击“框选”，再依次单击两个 X/Z 角点。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var dialog = new RegionCloneWindow(selection, _lastMapCenterY) { Owner = this };
        if (dialog.ShowDialog() != true) return;
        var command = FormattableString.Invariant($"clone {CommandDimensionToken(selection.Dimension)} {selection.MinimumX} {dialog.MinimumY} {selection.MinimumZ} {selection.MaximumX} {dialog.MaximumY} {selection.MaximumZ} {CommandDimensionToken(dialog.TargetDimension)} {dialog.TargetX} {dialog.TargetY} {dialog.TargetZ}");
        CommandInput.Text = command;
        await ExecuteCommandAsync();
    }

    private void MapScrollViewer_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (!HasRenderedMap) return;
        e.Handled = true;
        _mapInteractionVersion++;
        var wheelSteps = Math.Clamp(e.Delta / 120.0, -8.0, 8.0);
        if (Math.Abs(wheelSteps) < 0.0001) wheelSteps = e.Delta > 0 ? 1.0 : -1.0;
        var factor = Math.Pow(1.18, wheelSteps);
        var imagePoint = e.GetPosition(MapImage);
        var rasterPixelX = imagePoint.X / Math.Max(_mapZoom, 0.0000001);
        var rasterPixelY = imagePoint.Y / Math.Max(_mapZoom, 0.0000001);
        var viewportPoint = e.GetPosition(MapScrollViewer);

        // Treat one wheel packet as a single viewport transaction. WPF can emit
        // intermediate ScrollChanged events while image size/insets are changing;
        // allowing those events to schedule independent rerenders is what made
        // rapid wheel/precision-touchpad zoom occasionally appear to be ignored.
        var wasApplyingViewport = _mapApplyingViewport;
        _mapApplyingViewport = true;
        try
        {
            ApplyMapZoom(_mapZoom * factor, preserveViewportCenter: false);
            MapScrollViewer.UpdateLayout();
            MapScrollViewer.ScrollToHorizontalOffset(_mapSurfaceInsetX + rasterPixelX * _mapZoom - viewportPoint.X);
            MapScrollViewer.ScrollToVerticalOffset(_mapSurfaceInsetY + rasterPixelY * _mapZoom - viewportPoint.Y);
        }
        finally
        {
            _mapApplyingViewport = wasApplyingViewport;
        }
        ScheduleDynamicMapRefresh();
    }

    private void MapScrollViewer_ScrollChanged(object sender, ScrollChangedEventArgs e)
    {
        if (!HasRenderedMap || _mapApplyingViewport) return;
        if (Math.Abs(e.ViewportWidthChange) > 0.01 || Math.Abs(e.ViewportHeightChange) > 0.01)
        {
            _mapApplyingViewport = true;
            try
            {
                UpdateMapSurfaceInsets();
                MapScrollViewer.UpdateLayout();
            }
            finally
            {
                _mapApplyingViewport = false;
            }
        }
        var offsetChanged = Math.Abs(e.HorizontalChange) > 0.01 || Math.Abs(e.VerticalChange) > 0.01;
        if (offsetChanged) _mapInteractionVersion++;
        if (!_mapDragging && (offsetChanged
            || Math.Abs(e.ViewportWidthChange) > 0.01 || Math.Abs(e.ViewportHeightChange) > 0.01))
            ScheduleDynamicMapRefresh();
    }

    private double CurrentMapPixelsPerBlock()
    {
        if (_mapRegion is { } surface)
            return surface.Width * _mapZoom / Math.Max(1.0, surface.LogicalWidthBlocks);
        if (_crossSectionRegion is { } cross)
            return cross.Width * _mapZoom / Math.Max(1.0, cross.LogicalHorizontalBlocks);
        return _mapZoom;
    }

    private MapViewportSnapshot? CaptureMapViewportSnapshot()
    {
        if (!HasRenderedMap || MapScrollViewer.ViewportWidth <= 0 || MapScrollViewer.ViewportHeight <= 0) return null;
        var zoom = Math.Max(_mapZoom, 0.0000001);
        var rasterX = (MapScrollViewer.HorizontalOffset + MapScrollViewer.ViewportWidth / 2.0 - _mapSurfaceInsetX) / zoom;
        var rasterY = (MapScrollViewer.VerticalOffset + MapScrollViewer.ViewportHeight / 2.0 - _mapSurfaceInsetY) / zoom;
        var pixelsPerBlock = Math.Max(0.00000001, CurrentMapPixelsPerBlock());
        if (_mapRegion is { } surface)
            return new MapViewportSnapshot(BedrockMapAxis.Y, surface.WorldXAtPixel(rasterX), surface.WorldZAtPixel(rasterY), pixelsPerBlock);
        if (_crossSectionRegion is { } cross)
            return new MapViewportSnapshot(cross.Axis, cross.WorldHorizontalAtPixel(rasterX), cross.WorldYAtPixel(rasterY), pixelsPerBlock);
        return null;
    }

    private MapViewportWorldBounds? CaptureMapViewportWorldBounds()
    {
        if (!HasRenderedMap || MapScrollViewer.ViewportWidth <= 0 || MapScrollViewer.ViewportHeight <= 0) return null;
        var zoom = Math.Max(_mapZoom, 0.0000001);
        var rasterX0 = (MapScrollViewer.HorizontalOffset - _mapSurfaceInsetX) / zoom;
        var rasterX1 = (MapScrollViewer.HorizontalOffset + MapScrollViewer.ViewportWidth - _mapSurfaceInsetX) / zoom;
        var rasterY0 = (MapScrollViewer.VerticalOffset - _mapSurfaceInsetY) / zoom;
        var rasterY1 = (MapScrollViewer.VerticalOffset + MapScrollViewer.ViewportHeight - _mapSurfaceInsetY) / zoom;

        double a0, a1, b0, b1;
        if (_mapRegion is { } surface)
        {
            a0 = surface.WorldXAtPixel(rasterX0);
            a1 = surface.WorldXAtPixel(rasterX1);
            b0 = surface.WorldZAtPixel(rasterY0);
            b1 = surface.WorldZAtPixel(rasterY1);
        }
        else if (_crossSectionRegion is { } cross)
        {
            a0 = cross.WorldHorizontalAtPixel(rasterX0);
            a1 = cross.WorldHorizontalAtPixel(rasterX1);
            b0 = cross.WorldYAtPixel(rasterY0);
            b1 = cross.WorldYAtPixel(rasterY1);
        }
        else return null;

        return new MapViewportWorldBounds(
            Math.Min(a0, a1), Math.Max(a0, a1),
            Math.Min(b0, b1), Math.Max(b0, b1));
    }

    private void ScheduleDynamicMapRefresh()
    {
        if (!HasRenderedMap || _document is null || _mapApplyingViewport) return;
        _mapDynamicRenderTimer.Stop();
        _mapDynamicRenderTimer.Start();
    }

    private async void MapDynamicRenderTimer_Tick(object? sender, EventArgs e)
    {
        _mapDynamicRenderTimer.Stop();
        if (_document is null) return;
        if (_mapDynamicRefreshRunning || _databaseBusy || _mapDragging || _mapApplyingViewport)
        {
            _mapDynamicRenderTimer.Start();
            return;
        }
        _mapDynamicRefreshRunning = true;
        try { await RefreshDynamicMapViewportAsync(); }
        finally { _mapDynamicRefreshRunning = false; }
    }

    private async Task RefreshDynamicMapViewportAsync()
    {
        var interactionVersion = _mapInteractionVersion;
        var snapshot = CaptureMapViewportSnapshot();
        var visibleBounds = CaptureMapViewportWorldBounds();
        if (snapshot is null || visibleBounds is null || snapshot.Axis != _mapAxis || _databaseBusy) return;
        var pixelsPerBlock = Math.Max(snapshot.PixelsPerBlock, 0.00000001);
        var visibleBlocks = Math.Max(MapScrollViewer.ViewportWidth, MapScrollViewer.ViewportHeight) / pixelsPerBlock;
        var desiredChunksDouble = Math.Ceiling(visibleBlocks / 16.0) + 4.0;
        var desiredSideChunks = desiredChunksDouble >= 65535.0 ? 65535 : Math.Max(3, (int)desiredChunksDouble);
        if ((desiredSideChunks & 1) == 0) desiredSideChunks++;
        desiredSideChunks = Math.Min(65535, desiredSideChunks);
        int currentLogicalSide;
        double minA, maxA, minB, maxB;
        if (_mapRegion is { } surface)
        {
            currentLogicalSide = Math.Max(1, surface.LogicalWidthBlocks / 16);
            minA = surface.OriginBlockX;
            maxA = surface.OriginBlockX + (double)surface.LogicalWidthBlocks;
            minB = surface.OriginBlockZ;
            maxB = surface.OriginBlockZ + (double)surface.LogicalHeightBlocks;
        }
        else if (_crossSectionRegion is { } cross)
        {
            currentLogicalSide = Math.Max(1, cross.LogicalHorizontalBlocks / 16);
            minA = cross.OriginHorizontal;
            maxA = cross.OriginHorizontal + (double)cross.LogicalHorizontalBlocks;
            minB = cross.MinimumY;
            maxB = cross.MaximumY + 1.0;
        }
        else return;

        // Test the complete visible rectangle, not merely its center. With a finite
        // WPF ScrollViewer the viewport can hit the bitmap edge while its center is
        // still far from the old threshold; checking the edges guarantees a reload
        // before panning runs out of content, matching the iOS preload-window model.
        var needsRecentering = MapViewportPolicy.NeedsRecentering(
            visibleBounds.MinimumHorizontal, visibleBounds.MaximumHorizontal,
            visibleBounds.MinimumVertical, visibleBounds.MaximumVertical,
            minA, maxA, minB, maxB);
        var needsExpansion = desiredSideChunks > currentLogicalSide;
        var needsDetailRefinement = desiredSideChunks * 2 < currentLogicalSide;
        if (!needsRecentering && !needsExpansion && !needsDetailRefinement) return;

        var targetSideChunks = needsExpansion || needsDetailRefinement ? desiredSideChunks : currentLogicalSide;
        if ((targetSideChunks & 1) == 0) targetSideChunks++;
        var targetRadius = Math.Max(1, Math.Min(32767, (targetSideChunks - 1) / 2));

        var centerX = _lastMapCenterX;
        var centerZ = _lastMapCenterZ;
        var centerY = _lastMapCenterY;
        if (_mapAxis == BedrockMapAxis.Y)
        {
            centerX = ClampFloorToInt(snapshot.WorldHorizontal);
            centerZ = ClampFloorToInt(snapshot.WorldVertical);
        }
        else
        {
            centerY = ClampFloorToInt(snapshot.WorldVertical);
            if (_mapAxis == BedrockMapAxis.X) centerZ = ClampFloorToInt(snapshot.WorldHorizontal);
            else centerX = ClampFloorToInt(snapshot.WorldHorizontal);
        }

        MapCenterX.Text = centerX.ToString(CultureInfo.InvariantCulture);
        MapCenterZ.Text = centerZ.ToString(CultureInfo.InvariantCulture);
        MapCenterY.Text = centerY.ToString(CultureInfo.InvariantCulture);
        _mapCenterY = centerY;
        _mapRenderRadiusOverride = targetRadius;
        _mapViewportRestore = snapshot;
        _mapPreserveSelectionOnNextRender = true;
        await RenderMapAsync(interactionVersion);
    }

    private static int ClampFloorToInt(double value)
    {
        var floor = Math.Floor(value);
        if (floor <= int.MinValue) return int.MinValue;
        if (floor >= int.MaxValue) return int.MaxValue;
        return (int)floor;
    }

    private static int ClampLongToInt(long value)
    {
        if (value <= int.MinValue) return int.MinValue;
        if (value >= int.MaxValue) return int.MaxValue;
        return (int)value;
    }

    private void UpdateMapSurfaceInsets()
    {
        if (!HasRenderedMap || MapSurfaceHost is null || MapImage is null || MapScrollViewer is null) return;
        var viewportWidth = Math.Max(0.0, MapScrollViewer.ViewportWidth);
        var viewportHeight = Math.Max(0.0, MapScrollViewer.ViewportHeight);
        var imageWidth = double.IsFinite(MapImage.Width) ? Math.Max(0.0, MapImage.Width) : 0.0;
        var imageHeight = double.IsFinite(MapImage.Height) ? Math.Max(0.0, MapImage.Height) : 0.0;
        var insetX = Math.Max(0.0, (viewportWidth - imageWidth) / 2.0);
        var insetY = Math.Max(0.0, (viewportHeight - imageHeight) / 2.0);
        if (Math.Abs(insetX - _mapSurfaceInsetX) < 0.25 && Math.Abs(insetY - _mapSurfaceInsetY) < 0.25) return;
        _mapSurfaceInsetX = insetX;
        _mapSurfaceInsetY = insetY;
        MapSurfaceHost.Margin = new Thickness(insetX, insetY, insetX, insetY);
    }

    private void ApplyMapZoom(double zoom, bool preserveViewportCenter)
    {
        if (!HasRenderedMap) return;
        var size = RenderedMapSize();
        var oldZoom = Math.Max(_mapZoom, 0.0000001);
        var centerPixelX = (MapScrollViewer.HorizontalOffset + MapScrollViewer.ViewportWidth / 2.0 - _mapSurfaceInsetX) / oldZoom;
        var centerPixelY = (MapScrollViewer.VerticalOffset + MapScrollViewer.ViewportHeight / 2.0 - _mapSurfaceInsetY) / oldZoom;
        _mapZoom = Math.Clamp(zoom, 0.0001, 1_000_000.0);
        MapImage.Width = size.Width * _mapZoom;
        MapImage.Height = size.Height * _mapZoom;
        MapOverlayCanvas.Width = MapImage.Width;
        MapOverlayCanvas.Height = MapImage.Height;
        UpdateMapOverlay();
        OnPropertyChanged(nameof(MapZoomText));
        MapScrollViewer.UpdateLayout();
        UpdateMapSurfaceInsets();
        MapScrollViewer.UpdateLayout();
        if (preserveViewportCenter)
        {
            MapScrollViewer.ScrollToHorizontalOffset(_mapSurfaceInsetX + centerPixelX * _mapZoom - MapScrollViewer.ViewportWidth / 2.0);
            MapScrollViewer.ScrollToVerticalOffset(_mapSurfaceInsetY + centerPixelY * _mapZoom - MapScrollViewer.ViewportHeight / 2.0);
        }
        if (!_mapApplyingViewport) ScheduleDynamicMapRefresh();
    }

    private void ScrollMapToRenderedCenter()
    {
        double pixelX;
        double pixelY;
        if (_crossSectionRegion is { } cross)
        {
            var centerHorizontal = cross.Axis == BedrockMapAxis.X ? cross.FixedZ : cross.FixedX;
            pixelX = cross.PixelXForWorld(centerHorizontal + 0.5);
            pixelY = cross.PixelYForWorld(cross.CenterY + 0.5);
        }
        else if (_mapRegion is { } surface)
        {
            pixelX = surface.PixelXForWorld(surface.CenterBlockX + 0.5);
            pixelY = surface.PixelZForWorld(surface.CenterBlockZ + 0.5);
        }
        else return;

        MapScrollViewer.ScrollToHorizontalOffset(_mapSurfaceInsetX + pixelX * _mapZoom - MapScrollViewer.ViewportWidth / 2.0);
        MapScrollViewer.ScrollToVerticalOffset(_mapSurfaceInsetY + pixelY * _mapZoom - MapScrollViewer.ViewportHeight / 2.0);
    }

    private void MapImage_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (!HasRenderedMap) return;
        _mapInteractionVersion++;
        _mapDragging = true;
        _mapDragMoved = false;
        _mapDragStart = e.GetPosition(MapScrollViewer);
        _mapDragStartHorizontalOffset = MapScrollViewer.HorizontalOffset;
        _mapDragStartVerticalOffset = MapScrollViewer.VerticalOffset;
        MapImage.CaptureMouse();
        e.Handled = true;
    }

    private void MapImage_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_mapDragging || e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(MapScrollViewer);
        var dx = point.X - _mapDragStart.X;
        var dy = point.Y - _mapDragStart.Y;
        if (Math.Abs(dx) > 3 || Math.Abs(dy) > 3) _mapDragMoved = true;
        _mapInteractionVersion++;
        MapScrollViewer.ScrollToHorizontalOffset(_mapDragStartHorizontalOffset - dx);
        MapScrollViewer.ScrollToVerticalOffset(_mapDragStartVerticalOffset - dy);
        e.Handled = true;
    }

    private async void MapImage_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_mapDragging) return;
        var moved = _mapDragMoved;
        _mapDragging = false;
        _mapDragMoved = false;
        var point = e.GetPosition(MapImage);
        MapImage.ReleaseMouseCapture();
        e.Handled = true;
        if (!moved)
        {
            if (_mapRegionSelecting) ShowMapBlockAt(point);
            else if (!TryShowMapPointChoice(point)) await ShowMapBlockPickerAtAsync(point);
        }
        else ScheduleDynamicMapRefresh();
    }

    private void MapImage_LostMouseCapture(object sender, MouseEventArgs e)
    {
        if (!_mapDragging) return;
        _mapDragging = false;
        _mapDragMoved = false;
        _mapInteractionVersion++;
        ScheduleDynamicMapRefresh();
    }

    private async Task ShowMapBlockPickerAtAsync(Point imagePoint)
    {
        if (_document is null || _databaseBusy) return;
        var pixelX = (int)Math.Floor(imagePoint.X / Math.Max(_mapZoom, 0.0000001));
        var pixelY = (int)Math.Floor(imagePoint.Y / Math.Max(_mapZoom, 0.0000001));
        var document = _document;

        try
        {
            _databaseBusy = true;
            if (_crossSectionRegion is { } cross)
            {
                if (!cross.ContainsPixel(pixelX, pixelY)) return;
                var horizontal = ClampFloorToInt(cross.WorldHorizontalAtPixel(pixelX + 0.5));
                var worldY = ClampFloorToInt(cross.WorldYAtPixel(pixelY + 0.5));
                var centerCoordinate = cross.Axis == BedrockMapAxis.X ? cross.FixedX : cross.FixedZ;
                var minimumCoordinate = ClampLongToInt((long)centerCoordinate - 128);
                var maximumCoordinate = ClampLongToInt((long)centerCoordinate + 128);
                var showUngeneratedSubChunks = MapShowUngenerated?.IsChecked == true;
                var automaticMinimumCoordinate = showUngeneratedSubChunks
                    ? checked(BedrockSurfaceRegionRenderer.FloorDiv(centerCoordinate, 16) * 16)
                    : ClampLongToInt((long)centerCoordinate - (cross.Mode == BedrockMapRenderMode.Minerals ? 128L : 127L));
                var automaticMaximumCoordinate = showUngeneratedSubChunks
                    ? checked(automaticMinimumCoordinate + 15)
                    : centerCoordinate;
                var automaticInitialCoordinate = showUngeneratedSubChunks
                    ? automaticMaximumCoordinate
                    : centerCoordinate;
                var fixedX = cross.Axis == BedrockMapAxis.X ? centerCoordinate : horizontal;
                var fixedZ = cross.Axis == BedrockMapAxis.Z ? centerCoordinate : horizontal;
                MapDetailText = $"正在读取 {cross.Axis} 轴方块选择列表…";

                var result = await Task.Run(() =>
                {
                    using var database = document.OpenDatabase(readOnly: true);
                    return new BedrockBlockPickerService(database).BlockAxisLine(
                        cross.Axis, worldY, fixedX, fixedZ, minimumCoordinate, maximumCoordinate, cross.Dimension);
                });
                _databaseBusy = false;

                var picker = new BlockPositionPickerWindow(
                    result.Blocks, cross.Axis, automaticInitialCoordinate,
                    automaticMinimumCoordinate: automaticMinimumCoordinate,
                    automaticMaximumCoordinate: automaticMaximumCoordinate,
                    preferHighlightedOre: cross.Mode == BedrockMapRenderMode.Minerals,
                    diagnostics: result.Diagnostics)
                { Owner = this };
                if (picker.ShowDialog() == true && picker.SelectedBlock is { } selected)
                    SelectBlockFromPicker(selected);
                return;
            }

            if (_mapRegion is not { } surface || !surface.ContainsPixel(pixelX, pixelY)) return;
            var blockX = ClampFloorToInt(surface.WorldXAtPixel(pixelX + 0.5));
            var blockZ = ClampFloorToInt(surface.WorldZAtPixel(pixelY + 0.5));
            MapDetailText = $"正在读取 X={blockX}、Z={blockZ} 的 Y 轴方块…";
            var column = await Task.Run(() =>
            {
                using var database = document.OpenDatabase(readOnly: true);
                var result = new BedrockBlockPickerService(database).BlockColumn(blockX, blockZ, surface.Dimension);
                var initialY = result.Blocks.FirstOrDefault(block => block.Layers.Any(state => !state.IsAir))?.Y ?? 0;
                return (Result: result, InitialY: initialY);
            });
            _databaseBusy = false;

            var columnPicker = new BlockPositionPickerWindow(
                column.Result.Blocks, BedrockMapAxis.Y, column.InitialY,
                diagnostics: column.Result.Diagnostics)
            { Owner = this };
            if (columnPicker.ShowDialog() == true && columnPicker.SelectedBlock is { } selectedBlock)
                SelectBlockFromPicker(selectedBlock);
        }
        catch (Exception ex)
        {
            _databaseBusy = false;
            MapDetailText = "读取方块选择列表失败：" + ex.Message;
            MessageBox.Show(this, ex.Message, "无法读取方块列表", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private void SelectBlockFromPicker(BedrockBlockRecord block)
    {
        var name = block.Layers.Count == 0
            ? "minecraft:air"
            : block.Layers[Math.Clamp(block.PreferredLayerIndex, 0, block.Layers.Count - 1)].Name;
        SetSelectedMapBlock(new MapBlockSelection(block.Dimension, block.X, block.Y, block.Z, name));
        MapDetailText = $"已选中方块：{BedrockDimensionNames.DisplayName(block.Dimension)} · X={block.X}, Y={block.Y}, Z={block.Z} · {name}";
    }

    private void MapImage_MouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!HasRenderedMap) return;
        e.Handled = true;
        OpenMapContextAt(e.GetPosition(MapImage));
    }

    private void OpenMapContextAt(Point imagePoint)
    {
        if (_document is null) return;
        var pixelX = (int)Math.Floor(imagePoint.X / Math.Max(_mapZoom, 0.0001));
        var pixelY = (int)Math.Floor(imagePoint.Y / Math.Max(_mapZoom, 0.0001));
        int dimension; int blockX; int blockZ; BedrockMapRenderMode mode;
        if (_crossSectionRegion is { } cross)
        {
            if (!cross.ContainsPixel(pixelX, pixelY)) return;
            var horizontal = ClampFloorToInt(cross.WorldHorizontalAtPixel(pixelX + 0.5));
            blockX = cross.Axis == BedrockMapAxis.X ? cross.FixedCoordinate : horizontal;
            blockZ = cross.Axis == BedrockMapAxis.Z ? cross.FixedCoordinate : horizontal;
            dimension = cross.Dimension; mode = cross.Mode;
        }
        else if (_mapRegion is { } surface)
        {
            if (!surface.ContainsPixel(pixelX, pixelY)) return;
            blockX = ClampFloorToInt(surface.WorldXAtPixel(pixelX + 0.5));
            blockZ = ClampFloorToInt(surface.WorldZAtPixel(pixelY + 0.5));
            dimension = surface.Dimension; mode = surface.Mode;
        }
        else return;
        var chunk = new ChunkPosition(BedrockSurfaceRegionRenderer.FloorDiv(blockX,16), BedrockSurfaceRegionRenderer.FloorDiv(blockZ,16), dimension);
        _selectedMapChunk = chunk;
        UpdateMapOverlay();
        if (mode == BedrockMapRenderMode.TickingAreas) OpenTickingAreaManager(chunk);
        else if (mode == BedrockMapRenderMode.Biome)
        {
            var world = _document;
            new ChunkBiomeEditorWindow(world, chunk, () => PrepareWorldMutationAsync(world), message => { StatusText = message; if (HasRenderedMap) _ = RenderMapAsync(); }) { Owner = this }.ShowDialog();
        }
    }

    private void SetSelectedMapBlock(MapBlockSelection? selection)
    {
        _selectedMapBlock = selection;
        if (selection is null)
        {
            ClearMapBlockDetailPanel(collapse: true);
        }
        else
        {
            var requestedSelection = selection;
            var requestedDocument = _document;
            _ = Dispatcher.InvokeAsync(() =>
            {
                _ = ShowMapBlockDetailWhenReadyAsync(requestedSelection, requestedDocument);
            });
        }
        UpdateMapOverlay();
    }

    private async Task ShowMapBlockDetailWhenReadyAsync(MapBlockSelection selection, WorldDocument? requestedDocument)
    {
        if (requestedDocument is null) return;
        while (_databaseBusy)
        {
            if (!ReferenceEquals(_document, requestedDocument) || _selectedMapBlock is not { } current || !current.Equals(selection))
                return;
            await Task.Delay(40);
        }
        if (ReferenceEquals(_document, requestedDocument) && _selectedMapBlock is { } selected && selected.Equals(selection))
            ShowMapBlockDetail(selection);
    }

    private void MapBlockDetailCollapse_Click(object sender, RoutedEventArgs e)
        => SetMapBlockDetailCollapsed(!_mapBlockDetailCollapsed, preserveViewportCenter: true);

    private void SetMapBlockDetailCollapsed(bool collapsed, bool preserveViewportCenter)
    {
        if (MapBlockDetailPanel is null) return;
        var snapshot = preserveViewportCenter ? CaptureMapViewportSnapshot() : null;
        _mapBlockDetailCollapsed = collapsed;
        MapBlockDetailPanel.Width = collapsed ? MapBlockDetailCollapsedWidth : MapBlockDetailExpandedWidth;
        MapBlockDetailBody.Visibility = collapsed ? Visibility.Collapsed : Visibility.Visible;
        MapBlockDetailTitle.Visibility = collapsed ? Visibility.Collapsed : Visibility.Visible;
        MapBlockDetailCollapseButton.Content = collapsed ? "◀" : "▶";
        MapBlockDetailCollapseButton.ToolTip = collapsed ? "展开方块 NBT" : "收起方块 NBT";
        MapViewportLayout.UpdateLayout();
        MapScrollViewer.UpdateLayout();
        if (snapshot is not null && snapshot.Axis == _mapAxis)
            ApplyRenderedViewport(snapshot);
    }

    private void ClearMapBlockDetailPanel(bool collapse)
    {
        _mapBlockDetailRecord = null;
        if (MapBlockDetailStorage is not null)
        {
            _mapBlockDetailChangingStorage = true;
            MapBlockDetailStorage.Items.Clear();
            MapBlockDetailStorage.SelectedIndex = -1;
            _mapBlockDetailChangingStorage = false;
        }
        MapBlockDetailTree?.Items.Clear();
        if (MapBlockDetailCoordinateText is not null)
            MapBlockDetailCoordinateText.Text = "选择地图中的方块后显示详情。";
        if (MapBlockDetailSummaryText is not null)
            MapBlockDetailSummaryText.Text = string.Empty;
        if (collapse && MapBlockDetailPanel is not null)
            SetMapBlockDetailCollapsed(true, preserveViewportCenter: HasRenderedMap);
    }

    private void ShowMapBlockDetail(MapBlockSelection selection)
    {
        if (_document is null) return;
        try
        {
            using var database = _document.OpenDatabase(readOnly: true);
            var block = new BedrockBlockStore(database).ReadBlockForEditing(selection.Dimension, selection.X, selection.Y, selection.Z);
            _mapBlockDetailRecord = block;

            var chunkX = BedrockSurfaceRegionRenderer.FloorDiv(block.X, 16);
            var chunkZ = BedrockSurfaceRegionRenderer.FloorDiv(block.Z, 16);
            var localX = block.X - chunkX * 16;
            var localZ = block.Z - chunkZ * 16;
            var localY = ((block.Y % 16) + 16) % 16;
            MapBlockDetailCoordinateText.Text =
                $"{BedrockDimensionNames.DisplayName(block.Dimension)} · X={block.X}, Y={block.Y}, Z={block.Z}\n" +
                $"区块 ({chunkX}, {chunkZ}) · 局部 ({localX}, {localY}, {localZ})";

            var generatedText = block.Generated ? "已生成" : "SubChunk 未生成（按空气模板显示）";
            var versionText = block.SubChunkVersion.HasValue ? $"v{block.SubChunkVersion.Value}" : "未知版本";
            var backingText = block.BackingKind?.ToString() ?? "未生成";
            MapBlockDetailSummaryText.Text = $"{generatedText} · {versionText} · {backingText}";

            _mapBlockDetailChangingStorage = true;
            MapBlockDetailStorage.Items.Clear();
            for (var index = 0; index < block.Layers.Count; index++)
            {
                var state = block.Layers[index];
                MapBlockDetailStorage.Items.Add(new ComboBoxItem
                {
                    Content = $"{index}: {state.Name}",
                    Tag = index
                });
            }
            MapBlockDetailStorage.SelectedIndex = block.Layers.Count == 0
                ? -1
                : Math.Clamp(block.PreferredLayerIndex, 0, block.Layers.Count - 1);
            _mapBlockDetailChangingStorage = false;
            PopulateMapBlockDetailTree();
            SetMapBlockDetailCollapsed(false, preserveViewportCenter: true);
        }
        catch (Exception ex)
        {
            _mapBlockDetailRecord = null;
            MapBlockDetailCoordinateText.Text = $"X={selection.X}, Y={selection.Y}, Z={selection.Z}";
            MapBlockDetailSummaryText.Text = "读取方块 NBT 失败：" + ex.Message;
            MapBlockDetailTree.Items.Clear();
            SetMapBlockDetailCollapsed(false, preserveViewportCenter: true);
        }
    }

    private void MapBlockDetailStorage_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_mapBlockDetailChangingStorage) return;
        PopulateMapBlockDetailTree();
    }

    private void PopulateMapBlockDetailTree()
    {
        MapBlockDetailTree.Items.Clear();
        if (_mapBlockDetailRecord is not { } block ||
            MapBlockDetailStorage.SelectedItem is not ComboBoxItem item ||
            item.Tag is not int storageIndex || storageIndex < 0 || storageIndex >= block.Layers.Count)
            return;

        var state = block.Layers[storageIndex];
        NbtValue root;
        if (state.Nbt is not null)
        {
            root = NbtDocumentTools.DeepClone(state.Nbt);
        }
        else
        {
            root = new NbtCompoundValue([
                new NbtNamedTag("name", new NbtStringValue(state.Name)),
                new NbtNamedTag("legacy_id", new NbtIntValue(state.LegacyId ?? 0)),
                new NbtNamedTag("legacy_data", new NbtByteValue(unchecked((sbyte)(state.LegacyData ?? 0))))
            ]);
        }

        MapBlockDetailTree.Items.Add(NbtTreeVisuals.CreateReadOnlyTreeItem($"storage {storageIndex}", root, isRoot: true));
    }

    private void ShowMapBlockAt(Point imagePoint)
    {
        var pixelX = (int)Math.Floor(imagePoint.X / Math.Max(_mapZoom, 0.0000001));
        var pixelY = (int)Math.Floor(imagePoint.Y / Math.Max(_mapZoom, 0.0000001));

        if (_crossSectionRegion is { } cross)
        {
            if (!cross.ContainsPixel(pixelX, pixelY) || _document is null) return;
            var screenHorizontal = ClampFloorToInt(cross.WorldHorizontalAtPixel(pixelX + 0.5));
            var screenY = ClampFloorToInt(cross.WorldYAtPixel(pixelY + 0.5));
            try
            {
                using var database = _document.OpenDatabase(readOnly: true);
                var exactCenterX = cross.Axis == BedrockMapAxis.X ? cross.FixedX : screenHorizontal;
                var exactCenterZ = cross.Axis == BedrockMapAxis.Z ? cross.FixedZ : screenHorizontal;
                var exact = new BedrockCrossSectionRenderer(database).Render(
                    cross.Axis, exactCenterX, exactCenterZ, screenY, 16, cross.Dimension, cross.Mode,
                    drawSubChunkGrid: false, drawBuildHeightLimits: false,
                    projectionDepth: cross.ProjectionDepth, maximumRasterSide: 256,
                    showUngeneratedTexture: MapShowUngenerated?.IsChecked == true);
                var exactPixelX = Math.Clamp(screenHorizontal - exact.OriginHorizontal, 0, exact.Width - 1);
                var exactPixelY = Math.Clamp(exact.MaximumY - screenY, 0, exact.Height - 1);
                ShowCrossSectionDetail(exact, exact.Index(exactPixelX, exactPixelY), screenHorizontal, screenY);
            }
            catch (Exception ex)
            {
                MapDetailText = "精确读取剖面位置失败：" + ex.Message;
            }
            return;
        }

        if (_mapRegion is not { } surface || !surface.ContainsPixel(pixelX, pixelY) || _document is null) return;
        var blockX = ClampFloorToInt(surface.WorldXAtPixel(pixelX + 0.5));
        var blockZ = ClampFloorToInt(surface.WorldZAtPixel(pixelY + 0.5));
        if (_mapRegionSelecting)
        {
            if (_mapRegionFirstCorner is not { } first)
            {
                _mapRegionFirstCorner = (blockX, blockZ);
                MapDetailText = $"区域框选：第一角 X={blockX}, Z={blockZ}；请单击第二个角点。";
                UpdateMapOverlay();
            }
            else
            {
                _mapRegionSelection = new MapRegionSelection(surface.Dimension,
                    Math.Min(first.X, blockX), Math.Min(first.Z, blockZ),
                    Math.Max(first.X, blockX), Math.Max(first.Z, blockZ));
                _mapRegionFirstCorner = null;
                _mapRegionSelecting = false;
                UpdateMapRegionSelectionButton();
                MapDetailText = $"框选完成：X={_mapRegionSelection.MinimumX}…{_mapRegionSelection.MaximumX}, Z={_mapRegionSelection.MinimumZ}…{_mapRegionSelection.MaximumZ}，共 {_mapRegionSelection.Area:N0} 个 X/Z 列。可点击 Fill 或 Clone。";
                UpdateMapOverlay();
            }
            return;
        }

        try
        {
            using var database = _document.OpenDatabase(readOnly: true);
            var chunkX = BedrockSurfaceRegionRenderer.FloorDiv(blockX, 16);
            var chunkZ = BedrockSurfaceRegionRenderer.FloorDiv(blockZ, 16);
            var position = new ChunkPosition(chunkX, chunkZ, surface.Dimension);
            var localX = blockX - chunkX * 16;
            var localZ = blockZ - chunkZ * 16;

            if (surface.Mode == BedrockMapRenderMode.TickingAreas)
            {
                SetSelectedMapBlock(null);
                var matches = BedrockTickingAreaMap.Read(database).Areas
                    .Where(area => area.Dimension == surface.Dimension && BedrockTickingAreaMap.ContainsChunk(area, chunkX, chunkZ))
                    .ToArray();
                var state = matches.Length switch
                {
                    > 1 => "多个常加载区域重叠",
                    1 when matches[0].Preload => "预加载常加载区域",
                    1 => "普通常加载区域",
                    _ => "非常加载区块"
                };
                MapDetailText = $"{BedrockDimensionNames.DisplayName(surface.Dimension)} · 区块 ({chunkX}, {chunkZ}) · {state}";
                return;
            }
            if (surface.Mode == BedrockMapRenderMode.Slime)
            {
                SetSelectedMapBlock(null);
                var slime = BedrockSlimeChunk.IsSlimeChunk(chunkX, chunkZ);
                MapDetailText = $"{BedrockDimensionNames.DisplayName(surface.Dimension)} · 区块 ({chunkX}, {chunkZ}) · {(slime ? "史莱姆区块" : "非史莱姆区块")} · 与世界种子无关";
                return;
            }

            var chunk = new BedrockSurfaceRenderer(database).RenderChunk(position, surface.Mode);
            var index = chunk.Index(localX, localZ);
            if (!chunk.Generated)
            {
                SetSelectedMapBlock(null);
                MapDetailText = $"{BedrockDimensionNames.DisplayName(surface.Dimension)} · X={blockX}, Z={blockZ} · 未生成区块";
                return;
            }
            var height = chunk.Heights[index];
            var name = chunk.BlockNames[index];
            var heightText = height == int.MinValue ? "无匹配方块" : $"Y={height}";
            if (height == int.MinValue)
            {
                SetSelectedMapBlock(null);
                if (surface.Mode == BedrockMapRenderMode.Biome)
                {
                    var biomeId = chunk.BiomeIds[index];
                    var biomeText = biomeId == uint.MaxValue ? "无生物群系数据" : BedrockBiomeCatalog.DetailText(biomeId);
                    MapDetailText = $"{BedrockDimensionNames.DisplayName(surface.Dimension)} · X={blockX}, Z={blockZ} · {heightText} · {biomeText}";
                }
                else MapDetailText = $"{BedrockDimensionNames.DisplayName(surface.Dimension)} · X={blockX}, Z={blockZ} · {heightText} · {name}";
                return;
            }
            SetSelectedMapBlock(new MapBlockSelection(surface.Dimension, blockX, height, blockZ, name));
            if (surface.Mode == BedrockMapRenderMode.Biome)
            {
                var biomeId = chunk.BiomeIds[index];
                var biomeText = biomeId == uint.MaxValue ? "无生物群系数据" : BedrockBiomeCatalog.DetailText(biomeId);
                MapDetailText = $"{BedrockDimensionNames.DisplayName(surface.Dimension)} · X={blockX}, Z={blockZ} · {heightText} · {name} · {biomeText} · 已按真实坐标选择表面方块";
            }
            else MapDetailText = $"{BedrockDimensionNames.DisplayName(surface.Dimension)} · X={blockX}, Z={blockZ} · {heightText} · {name} · 已按真实坐标选择；可在右侧“方块 NBT”面板中编辑";
        }
        catch (Exception ex)
        {
            MapDetailText = "精确读取地图位置失败：" + ex.Message;
        }
    }

    private void ShowCrossSectionDetail(BedrockCrossSectionRegion cross, int index, int screenHorizontal, int screenY)
    {
        var horizontalName = cross.Axis == BedrockMapAxis.X ? "Z" : "X";
        var fixedName = cross.Axis == BedrockMapAxis.X ? "X" : "Z";
        var fixedValue = cross.FixedCoordinate;
        var exactX = cross.Axis == BedrockMapAxis.X ? fixedValue : screenHorizontal;
        var exactZ = cross.Axis == BedrockMapAxis.Z ? fixedValue : screenHorizontal;
        if (cross.Mode == BedrockMapRenderMode.TickingAreas)
        {
            SetSelectedMapBlock(null);
            var chunkX = BedrockSurfaceRegionRenderer.FloorDiv(exactX, 16);
            var chunkZ = BedrockSurfaceRegionRenderer.FloorDiv(exactZ, 16);
            var active = cross.BlockNames[index] != "mcbeeditor:non_ticking_chunk";
            MapDetailText = $"{BedrockDimensionNames.DisplayName(cross.Dimension)} · {cross.Axis} 常加载区块剖面 · 区块 ({chunkX}, {chunkZ}) · {(active ? "常加载" : "非常加载")} · Y={screenY}";
            return;
        }
        if (cross.Mode == BedrockMapRenderMode.Slime)
        {
            SetSelectedMapBlock(null);
            var chunkX = BedrockSurfaceRegionRenderer.FloorDiv(exactX, 16);
            var chunkZ = BedrockSurfaceRegionRenderer.FloorDiv(exactZ, 16);
            var slime = cross.BlockNames[index] == "mcbeeditor:slime_chunk";
            MapDetailText = $"{BedrockDimensionNames.DisplayName(cross.Dimension)} · {cross.Axis} 史莱姆区块剖面 · 区块 ({chunkX}, {chunkZ}) · {(slime ? "史莱姆区块" : "非史莱姆区块")} · Y={screenY}";
            return;
        }
        if (cross.Mode == BedrockMapRenderMode.Biome)
        {
            SetSelectedMapBlock(null);
            var biomeId = cross.BiomeIds[index];
            var biomeText = biomeId == uint.MaxValue ? "无生物群系数据" : BedrockBiomeCatalog.DetailText(biomeId);
            MapDetailText = $"{BedrockDimensionNames.DisplayName(cross.Dimension)} · {cross.Axis} 生物群系剖面 · X={exactX}, Y={screenY}, Z={exactZ} · {biomeText}";
            return;
        }
        if (!cross.Generated[index])
        {
            SetSelectedMapBlock(new MapBlockSelection(cross.Dimension, exactX, screenY, exactZ, "minecraft:air"));
            MapDetailText = $"{BedrockDimensionNames.DisplayName(cross.Dimension)} · X={exactX}, Y={screenY}, Z={exactZ} · SubChunk 未生成；可在右侧“方块 NBT”面板中编辑，应用后创建";
            return;
        }

        var name = cross.BlockNames[index];
        if (cross.Mode == BedrockMapRenderMode.Minerals && BedrockBlockMapColorCatalog.IsAir(name))
        {
            SetSelectedMapBlock(null);
            if (MapShowUngenerated?.IsChecked == true)
            {
                var chunkMinimum = BedrockSurfaceRegionRenderer.FloorDiv(fixedValue, 16) * 16;
                var chunkMaximum = chunkMinimum + 15;
                MapDetailText = $"{BedrockDimensionNames.DisplayName(cross.Dimension)} · {cross.Axis} 矿物剖面 · {horizontalName}={screenHorizontal}, Y={screenY} · 当前区块 {fixedName}={chunkMinimum}…{chunkMaximum} 未找到矿物";
            }
            else
            {
                MapDetailText = $"{BedrockDimensionNames.DisplayName(cross.Dimension)} · {cross.Axis} 矿物剖面 · {horizontalName}={screenHorizontal}, Y={screenY} · 当前 {fixedName}={fixedValue} 到 {fixedValue - 128} 未找到矿物";
            }
            return;
        }

        var x = cross.BlockX[index];
        var y = cross.BlockY[index];
        var z = cross.BlockZ[index];
        var projectedCoordinate = cross.Axis == BedrockMapAxis.X ? x : z;
        var projectionFront = MapShowUngenerated?.IsChecked == true
            ? BedrockSurfaceRegionRenderer.FloorDiv(fixedValue, 16) * 16 + 15
            : fixedValue;
        var depth = projectionFront - projectedCoordinate;
        SetSelectedMapBlock(new MapBlockSelection(cross.Dimension, x, y, z, name));
        MapDetailText = $"{BedrockDimensionNames.DisplayName(cross.Dimension)} · {cross.Axis} 剖面 · 屏幕 {horizontalName}={screenHorizontal}, Y={screenY} · 命中 X={x}, Y={y}, Z={z} · 深度 {depth} · {name} · 已按真实位置选择";
    }

    private void MapOverlayOption_Click(object sender, RoutedEventArgs e)
    {
        UpdateMapOverlay();
    }

    private void UpdateMapOverlay()
    {
        if (MapOverlayCanvas is null) return;
        MapOverlayCanvas.Children.Clear();
        if (!HasRenderedMap) return;

        var size = RenderedMapSize();
        MapOverlayCanvas.Width = size.Width * _mapZoom;
        MapOverlayCanvas.Height = size.Height * _mapZoom;

        if (MapChunkGrid.IsChecked == true)
        {
            if (_mapRegion is { } surface) DrawSurfaceGridOverlay(surface);
            else if (_crossSectionRegion is { } cross) DrawCrossSectionGridOverlay(cross);
        }

        if (_crossSectionRegion is { } section && MapBuildHeightLimits.IsChecked == true)
            DrawBuildHeightOverlay(section);

        DrawMapRegionSelectionOverlay();
        DrawStaticMapFeatureOverlays();
        DrawVillagePoiRelations();
        DrawMapObjectOverlay();
        DrawSelectedMapHighlights();
    }


    private void DrawMapRegionSelectionOverlay()
    {
        if (_mapRegion is not { } surface) return;
        int minX, maxX, minZ, maxZ;
        var completedSelection = _mapRegionSelection is { } completed && completed.Dimension == surface.Dimension;
        if (completedSelection)
        {
            var current = _mapRegionSelection!;
            minX = current.MinimumX; maxX = current.MaximumX;
            minZ = current.MinimumZ; maxZ = current.MaximumZ;
        }
        else if (_mapRegionSelecting && _mapRegionFirstCorner is { } first)
        {
            minX = maxX = first.X; minZ = maxZ = first.Z;
        }
        else return;

        var left = surface.PixelXForWorld(minX) * _mapZoom;
        var top = surface.PixelZForWorld(minZ) * _mapZoom;
        var right = surface.PixelXForWorld((double)maxX + 1) * _mapZoom;
        var bottom = surface.PixelZForWorld((double)maxZ + 1) * _mapZoom;
        var width = Math.Max(1.0, right - left);
        var height = Math.Max(1.0, bottom - top);
        var rectangle = new System.Windows.Shapes.Rectangle
        {
            Width = width,
            Height = height,
            Stroke = Brushes.DeepSkyBlue,
            StrokeThickness = Math.Max(1.0, Math.Min(3.0, _mapZoom / 2.0)),
            Fill = new SolidColorBrush(Color.FromArgb(42, 0, 191, 255)),
            StrokeDashArray = new DoubleCollection { 4, 2 },
            IsHitTestVisible = false
        };
        Canvas.SetLeft(rectangle, left);
        Canvas.SetTop(rectangle, top);
        Panel.SetZIndex(rectangle, 80);
        MapOverlayCanvas.Children.Add(rectangle);

        if (!completedSelection) return;
        const double grip = 10.0;
        AddMapSelectionEdgeGrip("left", left - grip / 2.0, top, grip, height, Cursors.SizeWE);
        AddMapSelectionEdgeGrip("right", right - grip / 2.0, top, grip, height, Cursors.SizeWE);
        AddMapSelectionEdgeGrip("top", left, top - grip / 2.0, width, grip, Cursors.SizeNS);
        AddMapSelectionEdgeGrip("bottom", left, bottom - grip / 2.0, width, grip, Cursors.SizeNS);
    }

    private void AddMapSelectionEdgeGrip(string edge, double left, double top, double width, double height, Cursor cursor)
    {
        var grip = new System.Windows.Shapes.Rectangle
        {
            Width = Math.Max(1.0, width),
            Height = Math.Max(1.0, height),
            Fill = new SolidColorBrush(Color.FromArgb(2, 0, 191, 255)),
            Cursor = cursor,
            Tag = edge,
            ToolTip = "拖动调整框选边界"
        };
        grip.MouseLeftButtonDown += MapSelectionEdge_MouseLeftButtonDown;
        Canvas.SetLeft(grip, left);
        Canvas.SetTop(grip, top);
        Panel.SetZIndex(grip, 120);
        MapOverlayCanvas.Children.Add(grip);
    }

    private void MapSelectionEdge_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement element || element.Tag is not string edge || _mapRegionSelection is null) return;
        _mapSelectionDragEdge = edge;
        _mapInteractionVersion++;
        MapOverlayCanvas.CaptureMouse();
        e.Handled = true;
    }

    private void MapOverlayCanvas_MouseMove(object sender, MouseEventArgs e)
    {
        if (_mapSelectionDragEdge is not { } edge || e.LeftButton != MouseButtonState.Pressed ||
            _mapRegionSelection is not { } selection || _mapRegion is not { } surface) return;
        var point = e.GetPosition(MapOverlayCanvas);
        var blockX = ClampFloorToInt(surface.WorldXAtPixel(point.X / Math.Max(_mapZoom, 0.0000001)));
        var blockZ = ClampFloorToInt(surface.WorldZAtPixel(point.Y / Math.Max(_mapZoom, 0.0000001)));
        blockX = Math.Clamp(blockX, surface.OriginBlockX, checked(surface.OriginBlockX + surface.LogicalWidthBlocks - 1));
        blockZ = Math.Clamp(blockZ, surface.OriginBlockZ, checked(surface.OriginBlockZ + surface.LogicalHeightBlocks - 1));

        var updated = edge switch
        {
            "left" => selection with { MinimumX = Math.Min(blockX, selection.MaximumX) },
            "right" => selection with { MaximumX = Math.Max(blockX, selection.MinimumX) },
            "top" => selection with { MinimumZ = Math.Min(blockZ, selection.MaximumZ) },
            "bottom" => selection with { MaximumZ = Math.Max(blockZ, selection.MinimumZ) },
            _ => selection
        };
        if (updated == selection) return;
        _mapRegionSelection = updated;
        MapDetailText = $"框选范围：X={updated.MinimumX}…{updated.MaximumX}, Z={updated.MinimumZ}…{updated.MaximumZ}，共 {updated.Area:N0} 个 X/Z 列。";
        UpdateMapOverlay();
        e.Handled = true;
    }

    private void MapOverlayCanvas_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_mapSelectionDragEdge is null) return;
        _mapSelectionDragEdge = null;
        if (MapOverlayCanvas.IsMouseCaptured) MapOverlayCanvas.ReleaseMouseCapture();
        if (_mapRegionSelection is { } selection)
            MapDetailText = $"框选边界调整完成：X={selection.MinimumX}…{selection.MaximumX}, Z={selection.MinimumZ}…{selection.MaximumZ}。";
        e.Handled = true;
    }

    private void MapOverlayCanvas_LostMouseCapture(object sender, MouseEventArgs e)
        => _mapSelectionDragEdge = null;


    private void DrawStaticMapFeatureOverlays()
    {
        if (MapShowSpawnPoints?.IsChecked == true) DrawSpawnOverlays();
        if (MapShowHardcodedSpawners?.IsChecked == true) DrawSpawnerOverlays();
        if (MapShowVillages?.IsChecked == true && _mapRegion is not null) DrawVillageOverlays();
    }

    private void DrawSpawnOverlays()
    {
        foreach (var feature in _spawnMapFeatures)
        {
            if (!TryMapFeaturePoint(feature.X, feature.Y, feature.Z, out var px, out var py)) continue;
            var text = new TextBlock
            {
                Text = feature.IsWorldSpawn ? "◆" : "●",
                Foreground = feature.IsWorldSpawn ? Brushes.Gold : Brushes.LimeGreen,
                FontSize = 16,
                FontWeight = FontWeights.Bold,
                Width = 18,
                Height = 18,
                TextAlignment = TextAlignment.Center,
                Cursor = Cursors.Hand,
                Tag = feature,
                ToolTip = $"{feature.Label}\n{BedrockDimensionNames.DisplayName(feature.Dimension)} X={feature.X}, Y={(feature.Y?.ToString() ?? "?")}, Z={feature.Z}"
            };
            text.MouseLeftButtonDown += MapSpawnFeature_MouseLeftButtonDown;
            Canvas.SetLeft(text, px - 9); Canvas.SetTop(text, py - 9); Panel.SetZIndex(text, 120); MapOverlayCanvas.Children.Add(text);
        }
    }

    private bool TryMapFeaturePoint(long x, long? y, long z, out double pixelX, out double pixelY)
    {
        pixelX = pixelY = 0;
        if (_mapRegion is { } surface)
        {
            if (!surface.ContainsWorld(x + 0.5, z + 0.5)) return false;
            pixelX = surface.PixelXForWorld(x + 0.5) * _mapZoom;
            pixelY = surface.PixelZForWorld(z + 0.5) * _mapZoom;
            return true;
        }
        if (_crossSectionRegion is not { } cross || !y.HasValue) return false;
        var fixedCoordinate = cross.Axis == BedrockMapAxis.X ? x : z;
        if (fixedCoordinate != cross.FixedCoordinate) return false;
        var horizontal = cross.Axis == BedrockMapAxis.X ? z : x;
        pixelX = cross.PixelXForWorld(horizontal + 0.5) * _mapZoom;
        pixelY = cross.PixelYForWorld(y.Value + 0.5) * _mapZoom;
        return pixelX >= 0 && pixelY >= 0 && pixelX < cross.Width * _mapZoom && pixelY < cross.Height * _mapZoom;
    }

    private void DrawSpawnerOverlays()
    {
        foreach (var record in _spawnerMapRecords)
        foreach (var area in record.Document.Areas)
        {
            if (_mapRegion is { } surface)
            {
                var left = surface.PixelXForWorld(area.MinimumX) * _mapZoom;
                var top = surface.PixelZForWorld(area.MinimumZ) * _mapZoom;
                var right = surface.PixelXForWorld((double)area.MaximumX + 1) * _mapZoom;
                var bottom = surface.PixelZForWorld((double)area.MaximumZ + 1) * _mapZoom;
                var width = right - left;
                var height = bottom - top;
                if (right < 0 || bottom < 0 || left >= surface.Width * _mapZoom || top >= surface.Height * _mapZoom) continue;
                AddSpawnerRectangle(record.Position, area, left, top, width, height);
            }
            else if (_crossSectionRegion is { } cross)
            {
                var fixedValue = cross.FixedCoordinate;
                if (cross.Axis == BedrockMapAxis.X && (fixedValue < area.MinimumX || fixedValue > area.MaximumX)) continue;
                if (cross.Axis == BedrockMapAxis.Z && (fixedValue < area.MinimumZ || fixedValue > area.MaximumZ)) continue;
                var h0 = cross.Axis == BedrockMapAxis.X ? area.MinimumZ : area.MinimumX;
                var h1 = cross.Axis == BedrockMapAxis.X ? area.MaximumZ : area.MaximumX;
                var left = cross.PixelXForWorld(h0) * _mapZoom;
                var right = cross.PixelXForWorld((double)h1 + 1) * _mapZoom;
                var top = cross.PixelYForWorld((double)area.MaximumY + 1) * _mapZoom;
                var bottom = cross.PixelYForWorld(area.MinimumY) * _mapZoom;
                var width = right - left;
                var height = bottom - top;
                if (right < 0 || bottom < 0 || left >= cross.Width * _mapZoom || top >= cross.Height * _mapZoom) continue;
                AddSpawnerRectangle(record.Position, area, left, top, width, height);
            }
        }
    }

    private void AddSpawnerRectangle(ChunkPosition position, HardcodedSpawnerArea area, double left, double top, double width, double height)
    {
        var rectangle = new System.Windows.Shapes.Rectangle
        {
            Width = Math.Max(2, width), Height = Math.Max(2, height), Stroke = Brushes.DeepPink, StrokeThickness = 1.5,
            StrokeDashArray = new DoubleCollection { 5, 3 }, Fill = new SolidColorBrush(Color.FromArgb(18, 255, 20, 147)),
            Cursor = Cursors.Hand, Tag = new MapSpawnerOverlayTag(position, area), ToolTip = $"{area.KindText}\n{area.RangeText}\n双击编辑区块 HardcodedSpawners"
        };
        rectangle.MouseLeftButtonDown += MapSpawnerFeature_MouseLeftButtonDown;
        Canvas.SetLeft(rectangle,left);Canvas.SetTop(rectangle,top);Panel.SetZIndex(rectangle,75);MapOverlayCanvas.Children.Add(rectangle);
    }

    private void DrawVillageOverlays()
    {
        var surface = _mapRegion!;
        foreach (var feature in _villageMapFeatures)
        {
            if (feature.Bounds is { } bounds)
            {
                var left = surface.PixelXForWorld(bounds.MinimumX) * _mapZoom;
                var top = surface.PixelZForWorld(bounds.MinimumZ) * _mapZoom;
                var right = surface.PixelXForWorld((double)bounds.MaximumX + 1) * _mapZoom;
                var bottom = surface.PixelZForWorld((double)bounds.MaximumZ + 1) * _mapZoom;
                var width = right - left;
                var height = bottom - top;
                if (right >= 0 && bottom >= 0 && left < surface.Width * _mapZoom && top < surface.Height * _mapZoom)
                {
                    var rect = new System.Windows.Shapes.Rectangle
                    {
                        Width = Math.Max(2, width), Height = Math.Max(2, height), Stroke = Brushes.LimeGreen,
                        StrokeThickness = 1.5, StrokeDashArray = new DoubleCollection { 6, 3 }, Fill = Brushes.Transparent,
                        Cursor = Cursors.Hand, Tag = new MapVillageOverlayTag(feature, null), ToolTip = feature.DisplayName + " · 双击打开村庄 NBT"
                    };
                    rect.MouseLeftButtonDown += MapVillageFeature_MouseLeftButtonDown;
                    Canvas.SetLeft(rect, left); Canvas.SetTop(rect, top); Panel.SetZIndex(rect, 70); MapOverlayCanvas.Children.Add(rect);
                }
            }
            if (feature.Center is { } center) AddVillagePoint(feature, center, Brushes.DarkOrange, "◆", 90);
            foreach (var point in feature.PointsOfInterest) AddVillagePoint(feature, point, Brushes.MediumPurple, "■", 92);
        }
    }

    private void AddVillagePoint(VillageMapFeature feature, VillageMapPointFeature point, Brush brush, string glyph, int zIndex)
    {
        if (_mapRegion is not { } surface || !surface.ContainsWorld(point.X + 0.5, point.Z + 0.5)) return;
        var px = surface.PixelXForWorld(point.X + 0.5) * _mapZoom;
        var py = surface.PixelZForWorld(point.Z + 0.5) * _mapZoom;
        var linkText = point.LinkedEntityIds.Count == 0 ? string.Empty : $"\n关联实体：{string.Join(", ", point.LinkedEntityIds)}";
        var text = new TextBlock
        {
            Text = glyph, Foreground = brush, FontSize = 13, Width = 16, Height = 16, TextAlignment = TextAlignment.Center,
            Cursor = Cursors.Hand, Tag = new MapVillageOverlayTag(feature, point),
            ToolTip = $"{feature.DisplayName} · {point.Label}\nX={point.X}, Y={point.Y}, Z={point.Z}{linkText}"
        };
        text.MouseLeftButtonDown += MapVillageFeature_MouseLeftButtonDown;
        Canvas.SetLeft(text, px - 8); Canvas.SetTop(text, py - 8); Panel.SetZIndex(text, zIndex); MapOverlayCanvas.Children.Add(text);
    }

    private void DrawVillagePoiRelations()
    {
        if (_mapRegion is not { } surface || MapShowVillages?.IsChecked != true || MapShowEntities?.IsChecked != true) return;
        var brush = new SolidColorBrush(Color.FromArgb(220, 147, 82, 214));
        brush.Freeze();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var feature in _villageMapFeatures)
        {
            foreach (var resident in feature.ResidentEntities)
            {
                if (resident.Kind != BedrockWorldObjectKind.Entity || resident.Position is not { } position || resident.Dimension != surface.Dimension) continue;
                var localName = resident.Identifier.Split(':').LastOrDefault()?.ToLowerInvariant() ?? resident.Identifier.ToLowerInvariant();
                if (localName != "villager" && localName != "villager_v2") continue;
                if (!surface.ContainsWorld(position.X, position.Z)) continue;
                var references = VillageMapFeatureStore.ReferencePositionKeys(resident.Document.Root);
                foreach (var point in feature.PointsOfInterest)
                {
                    var idMatches = resident.UniqueId.HasValue && point.LinkedEntityIds.Contains(resident.UniqueId.Value);
                    var positionMatches = references.Contains(point.CoordinateKey) || references.Contains(point.HorizontalCoordinateKey);
                    if (!idMatches && !positionMatches) continue;
                    var key = resident.StableId + "|" + point.CoordinateKey;
                    if (!seen.Add(key) || !surface.ContainsWorld(point.X + 0.5, point.Z + 0.5)) continue;
                    var x1 = surface.PixelXForWorld(position.X) * _mapZoom;
                    var y1 = surface.PixelZForWorld(position.Z) * _mapZoom;
                    var x2 = surface.PixelXForWorld(point.X + 0.5) * _mapZoom;
                    var y2 = surface.PixelZForWorld(point.Z + 0.5) * _mapZoom;
                    AddOverlayLine(x1, y1, x2, y2, brush, 2.0, 82);
                    AddArrowHead(x1, y1, x2, y2, brush);
                }
            }
        }
    }

    private void AddArrowHead(double x1, double y1, double x2, double y2, Brush brush)
    {
        var dx = x2 - x1; var dy = y2 - y1;
        var length = Math.Sqrt(dx * dx + dy * dy);
        if (length < 6) return;
        var ux = dx / length; var uy = dy / length;
        const double arrowLength = 7; const double halfWidth = 3.5;
        var baseX = x2 - ux * arrowLength; var baseY = y2 - uy * arrowLength;
        var px = -uy * halfWidth; var py = ux * halfWidth;
        var polygon = new System.Windows.Shapes.Polygon
        {
            Fill = brush, Stroke = brush, StrokeThickness = 0.5, IsHitTestVisible = false,
            Points = new PointCollection { new Point(x2, y2), new Point(baseX + px, baseY + py), new Point(baseX - px, baseY - py) }
        };
        Panel.SetZIndex(polygon, 83);
        MapOverlayCanvas.Children.Add(polygon);
    }

    private void MapSpawnFeature_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement element || element.Tag is not SpawnMapFeature feature) return;
        e.Handled = true;
        var point = e.GetPosition(MapOverlayCanvas);
        if (!TryShowMapPointChoice(point)) SelectMapSpawnFeature(feature);
    }

    private void MapSpawnerFeature_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement element || element.Tag is not MapSpawnerOverlayTag tag) return;
        e.Handled = true;
        if (e.ClickCount >= 2 && _document is { } world)
        {
            new HardcodedSpawnersEditorWindow(world, tag.Position, () => PrepareWorldMutationAsync(world),
                msg => { StatusText = msg; _ = RefreshMapObjectMarkersAsync(); }) { Owner = this }.ShowDialog();
            return;
        }
        var point = e.GetPosition(MapOverlayCanvas);
        if (!TryShowMapPointChoice(point)) SelectMapSpawnerFeature(tag);
    }

    private void MapVillageFeature_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement element || element.Tag is not MapVillageOverlayTag tag) return;
        e.Handled = true;
        if (e.ClickCount >= 2 && _document is { } world)
        {
            new VillageFeatureNbtWindow(world, tag.Feature.Identifier, () => PrepareWorldMutationAsync(world)) { Owner = this }.ShowDialog();
            return;
        }
        var point = e.GetPosition(MapOverlayCanvas);
        if (!TryShowMapPointChoice(point)) SelectMapVillageFeature(tag.Feature, tag.Point);
    }

    private void DrawMapObjectOverlay()
    {
        foreach (var marker in _mapObjectMarkers)
        {
            var row = marker.Row;
            if (row.Dimension != _lastMapDimension || row.X is not double x || row.Y is not double y || row.Z is not double z) continue;
            double pixelX;
            double pixelY;
            if (_mapRegion is { } surface)
            {
                if (!surface.ContainsWorld(x, z)) continue;
                pixelX = surface.PixelXForWorld(x) * _mapZoom;
                pixelY = surface.PixelZForWorld(z) * _mapZoom;
            }
            else if (_crossSectionRegion is { } cross)
            {
                var fixedDelta = cross.Axis == BedrockMapAxis.X ? Math.Abs(x - cross.FixedX) : Math.Abs(z - cross.FixedZ);
                if (fixedDelta > 0.99) continue;
                var horizontal = cross.Axis == BedrockMapAxis.X ? z : x;
                pixelX = cross.PixelXForWorld(horizontal) * _mapZoom;
                pixelY = cross.PixelYForWorld(y) * _mapZoom;
                if (pixelX < 0 || pixelY < 0 || pixelX >= cross.Width * _mapZoom || pixelY >= cross.Height * _mapZoom) continue;
            }
            else continue;

            var element = CreateMapObjectElement(row);
            element.Tag = row;
            element.ToolTip = $"{row.KindText} · {row.DisplayName}\n{row.DimensionText} X={row.XText} Y={row.YText} Z={row.ZText}\n{row.Identifier}";
            element.MouseLeftButtonDown += MapObjectMarker_MouseLeftButtonDown;
            var markerWidth = double.IsNaN(element.Width) || element.Width <= 0 ? 16.0 : element.Width;
            var markerHeight = double.IsNaN(element.Height) || element.Height <= 0 ? 16.0 : element.Height;
            Canvas.SetLeft(element, pixelX - markerWidth / 2.0);
            Canvas.SetTop(element, pixelY - markerHeight / 2.0);
            Panel.SetZIndex(element, 100);
            MapOverlayCanvas.Children.Add(element);
        }
    }

    private static FrameworkElement CreateMapObjectElement(WorldObjectRow row)
    {
        if (row.KindText == "本地玩家" || row.KindText == "在线玩家")
        {
            return new TextBlock
            {
                Text = "★",
                Foreground = row.KindText == "本地玩家" ? Brushes.Gold : Brushes.DodgerBlue,
                FontSize = 16,
                FontWeight = FontWeights.Bold,
                Width = 16,
                Height = 18,
                TextAlignment = TextAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Cursor = Cursors.Hand
            };
        }

        if (row.KindText == "方块实体")
        {
            return new System.Windows.Shapes.Rectangle
            {
                Width = 10,
                Height = 10,
                Fill = Brushes.MediumPurple,
                Stroke = Brushes.White,
                StrokeThickness = 1,
                Cursor = Cursors.Hand
            };
        }

        return new System.Windows.Shapes.Ellipse
        {
            Width = 10,
            Height = 10,
            Fill = Brushes.IndianRed,
            Stroke = Brushes.White,
            StrokeThickness = 1,
            Cursor = Cursors.Hand
        };
    }

    private async void MapObjectMarker_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement element || element.Tag is not WorldObjectRow row) return;
        e.Handled = true;
        if (e.ClickCount >= 2)
        {
            await EditObjectNbtAsync(row);
            return;
        }
        var point = e.GetPosition(MapOverlayCanvas);
        if (!TryShowMapPointChoice(point)) SelectMapObjectRow(row);
    }

    private sealed record MapPointChoiceCandidate(string Title, double Distance, int Priority, Action Select);

    private static double Distance2D(double x, double y)
        => Math.Sqrt((x * x) + (y * y));

    private bool TryShowMapPointChoice(Point point)
    {
        if (!HasRenderedMap || _mapRegionSelecting) return false;
        var candidates = new List<MapPointChoiceCandidate>();

        if (MapShowVillages?.IsChecked == true && _mapRegion is { } surface)
        {
            foreach (var feature in _villageMapFeatures)
            {
                if (feature.Center is { } center && surface.ContainsWorld(center.X + 0.5, center.Z + 0.5))
                {
                    var px = surface.PixelXForWorld(center.X + 0.5) * _mapZoom;
                    var py = surface.PixelZForWorld(center.Z + 0.5) * _mapZoom;
                    var distance = Distance2D(px - point.X, py - point.Y);
                    if (distance <= 13)
                    {
                        var capturedFeature = feature;
                        var capturedCenter = center;
                        candidates.Add(new MapPointChoiceCandidate(
                            $"查看村庄中心 · {feature.DisplayName}", distance, 0,
                            () => SelectMapVillageFeature(capturedFeature, capturedCenter)));
                    }
                }
                foreach (var poi in feature.PointsOfInterest)
                {
                    if (!surface.ContainsWorld(poi.X + 0.5, poi.Z + 0.5)) continue;
                    var px = surface.PixelXForWorld(poi.X + 0.5) * _mapZoom;
                    var py = surface.PixelZForWorld(poi.Z + 0.5) * _mapZoom;
                    var distance = Distance2D(px - point.X, py - point.Y);
                    if (distance > 12) continue;
                    var capturedFeature = feature;
                    var capturedPoi = poi;
                    candidates.Add(new MapPointChoiceCandidate(
                        $"查看兴趣点方块 · {poi.Label}", distance, 1,
                        () => SelectMapVillagePoiBlock(capturedFeature, capturedPoi)));
                }
            }
        }

        if (MapShowSpawnPoints?.IsChecked == true)
        {
            foreach (var feature in _spawnMapFeatures)
            {
                if (feature.Dimension != _lastMapDimension || !TryMapFeaturePoint(feature.X, feature.Y, feature.Z, out var px, out var py)) continue;
                var distance = Distance2D(px - point.X, py - point.Y);
                if (distance > 14) continue;
                var captured = feature;
                candidates.Add(new MapPointChoiceCandidate(
                    feature.IsWorldSpawn ? "查看世界出生点" : $"查看玩家出生点 · {feature.Label}",
                    distance, 4, () => SelectMapSpawnFeature(captured)));
            }
        }

        foreach (var marker in _mapObjectMarkers)
        {
            var row = marker.Row;
            if (!IsMapObjectLayerVisible(row) || !TryMapObjectPoint(row, out var px, out var py)) continue;
            var distance = Distance2D(px - point.X, py - point.Y);
            if (distance > 15) continue;
            var captured = row;
            var priority = row.KindText == "本地玩家" ? 2 : row.KindText == "在线玩家" ? 3 : row.KindText == "实体" ? 5 : 6;
            candidates.Add(new MapPointChoiceCandidate(
                $"查看{row.KindText} · {row.DisplayName}", distance, priority, () => SelectMapObjectRow(captured)));
        }

        if (MapShowHardcodedSpawners?.IsChecked == true)
        {
            foreach (var record in _spawnerMapRecords)
            foreach (var area in record.Document.Areas)
            {
                if (!MapSpawnerContainsPoint(area, point)) continue;
                var captured = new MapSpawnerOverlayTag(record.Position, area);
                candidates.Add(new MapPointChoiceCandidate(
                    $"查看刷怪区域 · {area.KindText}", 0, 7, () => SelectMapSpawnerFeature(captured)));
            }
        }

        if (candidates.Count == 0) return false;
        var ordered = candidates
            .OrderBy(item => item.Priority)
            .ThenBy(item => item.Distance)
            .ThenBy(item => item.Title, StringComparer.CurrentCultureIgnoreCase)
            .Take(24)
            .ToArray();
        if (ordered.Length == 1)
        {
            ordered[0].Select();
            return true;
        }

        var menu = new ContextMenu { PlacementTarget = MapOverlayCanvas, Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint };
        foreach (var candidate in ordered)
        {
            var item = new MenuItem { Header = candidate.Title };
            var captured = candidate;
            item.Click += (_, _) => captured.Select();
            menu.Items.Add(item);
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(new MenuItem { Header = "取消" });
        menu.IsOpen = true;
        return true;
    }

    private bool IsMapObjectLayerVisible(WorldObjectRow row)
        => row.KindText switch
        {
            "本地玩家" or "在线玩家" => MapShowPlayers?.IsChecked == true,
            "方块实体" => MapShowBlockEntities?.IsChecked == true,
            _ => MapShowEntities?.IsChecked == true
        };

    private void SelectMapObjectRow(WorldObjectRow row)
    {
        _selectedMapVillageIdentifier = null;
        _selectedMapSpawner = null;
        _selectedMapBlock = null;
        ClearMapBlockDetailPanel(collapse: true);
        SelectedObjectRow = row;
        MapDetailText = $"{row.KindText} · {row.DisplayName} · {row.DimensionText} X={row.XText}, Y={row.YText}, Z={row.ZText} · {row.Identifier}";
        UpdateMapOverlay();
    }

    private void SelectMapSpawnFeature(SpawnMapFeature feature)
    {
        _selectedMapVillageIdentifier = null;
        _selectedMapSpawner = null;
        MapDetailText = $"{feature.Label} · {BedrockDimensionNames.DisplayName(feature.Dimension)} X={feature.X}, Y={(feature.Y?.ToString() ?? "?")}, Z={feature.Z}"
            + (feature.Forced.HasValue ? $" · Forced={feature.Forced.Value}" : string.Empty);
        UpdateMapOverlay();
    }

    private void SelectMapVillageFeature(VillageMapFeature feature, VillageMapPointFeature? point)
    {
        _selectedMapVillageIdentifier = feature.Identifier;
        _selectedMapSpawner = null;
        _selectedMapBlock = null;
        ClearMapBlockDetailPanel(collapse: true);
        var suffix = point is null ? "中心" : $"{point.Label} X={point.X}, Y={point.Y}, Z={point.Z}";
        MapDetailText = $"{feature.DisplayName} · {suffix}";
        UpdateMapOverlay();
    }

    private void SelectMapVillagePoiBlock(VillageMapFeature feature, VillageMapPointFeature point)
    {
        _selectedMapVillageIdentifier = feature.Identifier;
        _selectedMapSpawner = null;
        SetSelectedMapBlock(new MapBlockSelection(feature.Dimension, ClampLongToInt(point.X), ClampLongToInt(point.Y), ClampLongToInt(point.Z), point.Label));
        MapDetailText = $"{feature.DisplayName} · 兴趣点 {point.Label} · X={point.X}, Y={point.Y}, Z={point.Z}";
    }

    private bool MapSpawnerContainsPoint(HardcodedSpawnerArea area, Point point)
    {
        if (_mapRegion is { } surface)
        {
            var surfaceLeft = surface.PixelXForWorld(area.MinimumX) * _mapZoom;
            var surfaceRight = surface.PixelXForWorld((double)area.MaximumX + 1) * _mapZoom;
            var surfaceTop = surface.PixelZForWorld(area.MinimumZ) * _mapZoom;
            var surfaceBottom = surface.PixelZForWorld((double)area.MaximumZ + 1) * _mapZoom;
            return point.X >= surfaceLeft && point.X <= surfaceRight && point.Y >= surfaceTop && point.Y <= surfaceBottom;
        }
        if (_crossSectionRegion is not { } cross) return false;
        var fixedValue = cross.FixedCoordinate;
        if (cross.Axis == BedrockMapAxis.X && (fixedValue < area.MinimumX || fixedValue > area.MaximumX)) return false;
        if (cross.Axis == BedrockMapAxis.Z && (fixedValue < area.MinimumZ || fixedValue > area.MaximumZ)) return false;
        var h0 = cross.Axis == BedrockMapAxis.X ? area.MinimumZ : area.MinimumX;
        var h1 = cross.Axis == BedrockMapAxis.X ? area.MaximumZ : area.MaximumX;
        var crossLeft = cross.PixelXForWorld(h0) * _mapZoom;
        var crossRight = cross.PixelXForWorld((double)h1 + 1) * _mapZoom;
        var crossTop = cross.PixelYForWorld((double)area.MaximumY + 1) * _mapZoom;
        var crossBottom = cross.PixelYForWorld(area.MinimumY) * _mapZoom;
        return point.X >= crossLeft && point.X <= crossRight && point.Y >= crossTop && point.Y <= crossBottom;
    }

    private void SelectMapSpawnerFeature(MapSpawnerOverlayTag tag)
    {
        _selectedMapSpawner = tag;
        _selectedMapVillageIdentifier = null;
        _selectedMapBlock = null;
        ClearMapBlockDetailPanel(collapse: true);
        MapDetailText = $"HardcodedSpawners · {tag.Area.KindText} · {tag.Area.RangeText}";
        UpdateMapOverlay();
    }

    private void DrawSelectedMapHighlights()
    {
        DrawSelectedVillageHighlight();
        DrawSelectedSpawnerHighlight();
        DrawSelectedObjectHighlights();
        DrawSelectedBlockHighlight();
        DrawSelectedChunkHighlight();
    }

    private void DrawSelectedVillageHighlight()
    {
        if (_mapRegion is not { } surface || string.IsNullOrWhiteSpace(_selectedMapVillageIdentifier)) return;
        var feature = _villageMapFeatures.FirstOrDefault(item => string.Equals(item.Identifier, _selectedMapVillageIdentifier, StringComparison.OrdinalIgnoreCase));
        if (feature is null) return;

        if (feature.Bounds is { } bounds)
        {
            var left = surface.PixelXForWorld(bounds.MinimumX) * _mapZoom;
            var top = surface.PixelZForWorld(bounds.MinimumZ) * _mapZoom;
            var right = surface.PixelXForWorld((double)bounds.MaximumX + 1) * _mapZoom;
            var bottom = surface.PixelZForWorld((double)bounds.MaximumZ + 1) * _mapZoom;
            AddBlinkingSelectionRectangle(left, top, right - left, bottom - top,
                Brushes.Gold, Color.FromArgb(30, 255, 215, 0), new DoubleCollection { 10, 4 }, 0.62, 150);
        }
        else if (feature.Center is { } center && surface.ContainsWorld(center.X + 0.5, center.Z + 0.5))
        {
            var px = surface.PixelXForWorld(center.X + 0.5) * _mapZoom;
            var py = surface.PixelZForWorld(center.Z + 0.5) * _mapZoom;
            AddBlinkingSelectionRectangle(px - 9, py - 9, 18, 18,
                Brushes.Gold, Color.FromArgb(30, 255, 215, 0), new DoubleCollection { 6, 3 }, 0.62, 150);
        }
    }

    private void DrawSelectedSpawnerHighlight()
    {
        if (_selectedMapSpawner is not { } selected) return;
        var area = selected.Area;
        if (_mapRegion is { } surface)
        {
            var left = surface.PixelXForWorld(area.MinimumX) * _mapZoom;
            var top = surface.PixelZForWorld(area.MinimumZ) * _mapZoom;
            var right = surface.PixelXForWorld((double)area.MaximumX + 1) * _mapZoom;
            var bottom = surface.PixelZForWorld((double)area.MaximumZ + 1) * _mapZoom;
            AddBlinkingSelectionRectangle(left - 2, top - 2, right - left + 4, bottom - top + 4,
                Brushes.Gold, Color.FromArgb(40, 255, 215, 0), new DoubleCollection { 6, 3 }, 0.54, 151);
            return;
        }
        if (_crossSectionRegion is not { } cross) return;
        var fixedValue = cross.FixedCoordinate;
        if (cross.Axis == BedrockMapAxis.X && (fixedValue < area.MinimumX || fixedValue > area.MaximumX)) return;
        if (cross.Axis == BedrockMapAxis.Z && (fixedValue < area.MinimumZ || fixedValue > area.MaximumZ)) return;
        var h0 = cross.Axis == BedrockMapAxis.X ? area.MinimumZ : area.MinimumX;
        var h1 = cross.Axis == BedrockMapAxis.X ? area.MaximumZ : area.MaximumX;
        var leftCross = cross.PixelXForWorld(h0) * _mapZoom;
        var rightCross = cross.PixelXForWorld((double)h1 + 1) * _mapZoom;
        var topCross = cross.PixelYForWorld((double)area.MaximumY + 1) * _mapZoom;
        var bottomCross = cross.PixelYForWorld(area.MinimumY) * _mapZoom;
        AddBlinkingSelectionRectangle(leftCross - 2, topCross - 2, rightCross - leftCross + 4, bottomCross - topCross + 4,
            Brushes.Gold, Color.FromArgb(40, 255, 215, 0), new DoubleCollection { 6, 3 }, 0.54, 151);
    }

    private void DrawSelectedObjectHighlights()
    {
        HashSet<string>? villageResidents = null;
        if (!string.IsNullOrWhiteSpace(_selectedMapVillageIdentifier))
        {
            var feature = _villageMapFeatures.FirstOrDefault(item => string.Equals(item.Identifier, _selectedMapVillageIdentifier, StringComparison.OrdinalIgnoreCase));
            if (feature is not null)
                villageResidents = feature.ResidentEntities.Select(item => item.StableId).ToHashSet(StringComparer.Ordinal);
        }

        foreach (var marker in _mapObjectMarkers)
        {
            var row = marker.Row;
            var isSelected = ReferenceEquals(row, SelectedObjectRow)
                || (row.WorldObject is { } worldObject && villageResidents?.Contains(worldObject.StableId) == true);
            if (!isSelected || !TryMapObjectPoint(row, out var px, out var py)) continue;
            var size = row.KindText == "本地玩家" || row.KindText == "在线玩家" ? 20.0 : 16.0;
            var shape = row.KindText == "方块实体"
                ? (System.Windows.Shapes.Shape)new System.Windows.Shapes.Rectangle { RadiusX = 2, RadiusY = 2 }
                : new System.Windows.Shapes.Ellipse();
            shape.Width = size;
            shape.Height = size;
            shape.Stroke = Brushes.Gold;
            shape.StrokeThickness = 3;
            shape.Fill = new SolidColorBrush(Color.FromArgb(55, 255, 215, 0));
            shape.IsHitTestVisible = false;
            Canvas.SetLeft(shape, px - size / 2.0);
            Canvas.SetTop(shape, py - size / 2.0);
            Panel.SetZIndex(shape, 152);
            StartMapSelectionBlink(shape, 0.48);
            MapOverlayCanvas.Children.Add(shape);
        }
    }

    private bool TryMapObjectPoint(WorldObjectRow row, out double pixelX, out double pixelY)
    {
        pixelX = pixelY = 0;
        if (row.Dimension != _lastMapDimension || row.X is not double x || row.Y is not double y || row.Z is not double z) return false;
        if (_mapRegion is { } surface)
        {
            if (!surface.ContainsWorld(x, z)) return false;
            pixelX = surface.PixelXForWorld(x) * _mapZoom;
            pixelY = surface.PixelZForWorld(z) * _mapZoom;
            return true;
        }
        if (_crossSectionRegion is not { } cross) return false;
        var fixedDelta = cross.Axis == BedrockMapAxis.X ? Math.Abs(x - cross.FixedX) : Math.Abs(z - cross.FixedZ);
        if (fixedDelta > 0.99) return false;
        var horizontal = cross.Axis == BedrockMapAxis.X ? z : x;
        pixelX = cross.PixelXForWorld(horizontal) * _mapZoom;
        pixelY = cross.PixelYForWorld(y) * _mapZoom;
        return pixelX >= 0 && pixelY >= 0 && pixelX < cross.Width * _mapZoom && pixelY < cross.Height * _mapZoom;
    }

    private void DrawSelectedBlockHighlight()
    {
        if (_selectedMapBlock is not { } block) return;
        double left, top, right, bottom;
        if (_mapRegion is { } surface)
        {
            if (block.Dimension != surface.Dimension || !surface.ContainsWorld(block.X + 0.5, block.Z + 0.5)) return;
            left = surface.PixelXForWorld(block.X) * _mapZoom;
            right = surface.PixelXForWorld((double)block.X + 1) * _mapZoom;
            top = surface.PixelZForWorld(block.Z) * _mapZoom;
            bottom = surface.PixelZForWorld((double)block.Z + 1) * _mapZoom;
        }
        else if (_crossSectionRegion is { } cross)
        {
            if (block.Dimension != cross.Dimension) return;
            var fixedCoordinate = cross.Axis == BedrockMapAxis.X ? block.X : block.Z;
            if (fixedCoordinate != cross.FixedCoordinate || block.Y < cross.MinimumY || block.Y > cross.MaximumY) return;
            var horizontal = cross.Axis == BedrockMapAxis.X ? block.Z : block.X;
            if (horizontal < cross.OriginHorizontal || horizontal >= (long)cross.OriginHorizontal + cross.LogicalHorizontalBlocks) return;
            left = cross.PixelXForWorld(horizontal) * _mapZoom;
            right = cross.PixelXForWorld((double)horizontal + 1) * _mapZoom;
            top = cross.PixelYForWorld((double)block.Y + 1) * _mapZoom;
            bottom = cross.PixelYForWorld(block.Y) * _mapZoom;
        }
        else return;

        var width = Math.Abs(right - left);
        var height = Math.Abs(bottom - top);
        var centerX = (left + right) / 2.0;
        var centerY = (top + bottom) / 2.0;
        width = Math.Max(12, width + 2);
        height = Math.Max(12, height + 2);
        AddBlinkingSelectionRectangle(centerX - width / 2.0, centerY - height / 2.0, width, height,
            Brushes.Gold, Color.FromArgb(72, 255, 215, 0), null, 0.42, 153);
    }

    private void DrawSelectedChunkHighlight()
    {
        if (_mapRegion is not { } surface || _selectedMapChunk is not { } chunk || chunk.Dimension != surface.Dimension) return;
        var blockX = (long)chunk.X * 16;
        var blockZ = (long)chunk.Z * 16;
        var left = surface.PixelXForWorld(blockX) * _mapZoom;
        var right = surface.PixelXForWorld(blockX + 16.0) * _mapZoom;
        var top = surface.PixelZForWorld(blockZ) * _mapZoom;
        var bottom = surface.PixelZForWorld(blockZ + 16.0) * _mapZoom;
        if (right < 0 || bottom < 0 || left > surface.Width * _mapZoom || top > surface.Height * _mapZoom) return;
        AddBlinkingSelectionRectangle(left - 1.5, top - 1.5, right - left + 3, bottom - top + 3,
            Brushes.DarkOrange, Color.FromArgb(30, 255, 140, 0), null, 0.58, 154);
    }

    private void AddBlinkingSelectionRectangle(double left, double top, double width, double height, Brush stroke, Color fill,
        DoubleCollection? dash, double duration, int zIndex)
    {
        if (!double.IsFinite(left) || !double.IsFinite(top) || !double.IsFinite(width) || !double.IsFinite(height)) return;
        if (width <= 0 || height <= 0) return;
        var rectangle = new System.Windows.Shapes.Rectangle
        {
            Width = Math.Max(2, width), Height = Math.Max(2, height), Stroke = stroke, StrokeThickness = 3,
            Fill = new SolidColorBrush(fill), StrokeDashArray = dash, IsHitTestVisible = false
        };
        Canvas.SetLeft(rectangle, left);
        Canvas.SetTop(rectangle, top);
        Panel.SetZIndex(rectangle, zIndex);
        StartMapSelectionBlink(rectangle, duration);
        MapOverlayCanvas.Children.Add(rectangle);
    }

    private static void StartMapSelectionBlink(UIElement element, double duration)
    {
        var animation = new DoubleAnimation
        {
            From = 1.0,
            To = 0.16,
            Duration = TimeSpan.FromSeconds(duration),
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever
        };
        element.BeginAnimation(UIElement.OpacityProperty, animation, HandoffBehavior.SnapshotAndReplace);
    }

    private void DrawSurfaceGridOverlay(BedrockSurfaceRegion region)
    {
        var brush = new SolidColorBrush(Color.FromRgb(0x55, 0x55, 0x55));
        brush.Freeze();
        var endX = (long)region.OriginBlockX + region.LogicalWidthBlocks;
        var endZ = (long)region.OriginBlockZ + region.LogicalHeightBlocks;
        for (long worldX = FirstMultipleAtOrAfter(region.OriginBlockX, 16); worldX <= endX; worldX += 16)
        {
            if (worldX <= region.OriginBlockX || worldX >= endX) continue;
            var x = region.PixelXForWorld(worldX) * _mapZoom;
            AddOverlayLine(x, 0, x, region.Height * _mapZoom, brush);
        }
        for (long worldZ = FirstMultipleAtOrAfter(region.OriginBlockZ, 16); worldZ <= endZ; worldZ += 16)
        {
            if (worldZ <= region.OriginBlockZ || worldZ >= endZ) continue;
            var y = region.PixelZForWorld(worldZ) * _mapZoom;
            AddOverlayLine(0, y, region.Width * _mapZoom, y, brush);
        }
    }

    private void DrawCrossSectionGridOverlay(BedrockCrossSectionRegion region)
    {
        var brush = new SolidColorBrush(Color.FromRgb(0x66, 0x66, 0x66));
        brush.Freeze();
        var endHorizontal = (long)region.OriginHorizontal + region.LogicalHorizontalBlocks;
        for (long boundary = FirstMultipleAtOrAfter(region.OriginHorizontal, 16); boundary <= endHorizontal; boundary += 16)
        {
            if (boundary <= region.OriginHorizontal || boundary >= endHorizontal) continue;
            var x = region.PixelXForWorld(boundary) * _mapZoom;
            AddOverlayLine(x, 0, x, region.Height * _mapZoom, brush);
        }

        var firstYBoundary = FirstMultipleAtOrAfter(region.MinimumY + 1, 16);
        for (long boundaryY = firstYBoundary; boundaryY <= (long)region.MaximumY + 1; boundaryY += 16)
        {
            var y = region.PixelYForWorld(boundaryY) * _mapZoom;
            if (y > 0 && y < region.Height * _mapZoom)
                AddOverlayLine(0, y, region.Width * _mapZoom, y, brush);
        }
    }

    private void DrawBuildHeightOverlay(BedrockCrossSectionRegion region)
    {
        var (minimum, maximumExclusive) = region.Dimension switch
        {
            1 => (0, 128),
            2 => (0, 256),
            _ => (-64, 320)
        };
        DrawBuildLimitOverlay(region, minimum);
        DrawBuildLimitOverlay(region, maximumExclusive);
    }

    private void DrawBuildLimitOverlay(BedrockCrossSectionRegion region, int boundaryY)
    {
        var y = region.PixelYForWorld(boundaryY) * _mapZoom;
        if (y < 0 || y > region.Height * _mapZoom) return;
        var brush = new SolidColorBrush(Color.FromRgb(0xE5, 0x39, 0x35));
        brush.Freeze();

        var logicalEnd = (long)region.OriginHorizontal + region.LogicalHorizontalBlocks;
        var firstDash = (long)BedrockSurfaceRegionRenderer.FloorDiv(region.OriginHorizontal, 4) * 4;
        for (var worldStart = firstDash; worldStart < logicalEnd; worldStart += 4)
        {
            var dashIndex = (long)Math.Floor(worldStart / 4.0);
            if ((dashIndex & 1) != 0) continue;
            var clippedStart = Math.Max((double)worldStart, region.OriginHorizontal);
            var clippedEnd = Math.Min((double)worldStart + 4.0, logicalEnd);
            if (clippedEnd <= clippedStart) continue;
            var x1 = region.PixelXForWorld(clippedStart) * _mapZoom;
            var x2 = region.PixelXForWorld(clippedEnd) * _mapZoom;
            AddOverlayLine(x1, y, x2, y, brush);
        }
    }

    private void AddOverlayLine(double x1, double y1, double x2, double y2, Brush brush, double thickness = 1.0, int zIndex = 0)
    {
        var line = new System.Windows.Shapes.Line
        {
            X1 = x1, Y1 = y1, X2 = x2, Y2 = y2, Stroke = brush, StrokeThickness = thickness,
            SnapsToDevicePixels = true, IsHitTestVisible = false
        };
        RenderOptions.SetEdgeMode(line, EdgeMode.Aliased);
        if (zIndex != 0) Panel.SetZIndex(line, zIndex);
        MapOverlayCanvas.Children.Add(line);
    }

    private static long FirstMultipleAtOrAfter(int value, int divisor)
    {
        var floor = (long)BedrockSurfaceRegionRenderer.FloorDiv(value, divisor) * divisor;
        return floor < value ? floor + divisor : floor;
    }

    private void OpenTextures_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            BlockTextureOverrideStore.PrepareAndReload();
            Process.Start(new ProcessStartInfo
            {
                FileName = BlockTextureOverrideStore.DirectoryPath,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void ReloadTextures_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            BlockTextureOverrideStore.Reload();
            BedrockBlockMapColorCatalog.OverrideProvider = BlockTextureOverrideStore.ColorFor;
            MapStatusText = $"Textures 已重新加载：{BlockTextureOverrideStore.Count} 个颜色覆盖。";
            if (HasRenderedMap) await RenderMapAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void MapExport_Click(object sender, RoutedEventArgs e)
    {
        if (_document is null || !HasRenderedMap)
        {
            MessageBox.Show(this, "请先渲染地图。", "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (_databaseBusy) return;

        var initialAngle = _crossSectionRegion?.Axis switch
        {
            BedrockMapAxis.X => MapExportAngle.XPositive,
            BedrockMapAxis.Z => MapExportAngle.ZPositive,
            _ => MapExportAngle.YPositive
        };
        var initialBounds = CurrentMapExportBounds();
        var isCrossSectionExport = initialAngle is MapExportAngle.XPositive or MapExportAngle.XNegative
            or MapExportAngle.ZPositive or MapExportAngle.ZNegative;
        var optionsWindow = new MapExportOptionsWindow(
            initialAngle, initialBounds.MinimumX, initialBounds.MinimumZ, initialBounds.MaximumX, initialBounds.MaximumZ,
            MapShowPlayers.IsChecked == true,
            MapShowEntities.IsChecked == true,
            MapShowBlockEntities.IsChecked == true,
            MapShowHardcodedSpawners.IsChecked == true,
            !isCrossSectionExport && MapShowVillages.IsChecked == true,
            MapShowSpawnPoints.IsChecked == true,
            isCrossSectionExport ? MapUngeneratedExportMode.Air : MapUngeneratedExportMode.Transparent)
        { Owner = this };
        if (optionsWindow.ShowDialog() != true || optionsWindow.Options is not { } options) return;

        var angleText = options.Angle switch
        {
            MapExportAngle.XPositive => "x+",
            MapExportAngle.XNegative => "x-",
            MapExportAngle.YPositive => "y+",
            MapExportAngle.YNegative => "y-",
            MapExportAngle.ZPositive => "z+",
            _ => "z-"
        };
        var save = new SaveFileDialog
        {
            Title = "导出地图 PNG",
            Filter = "PNG 图片 (*.png)|*.png",
            DefaultExt = ".png",
            AddExtension = true,
            FileName = $"MCBEEditor-{BedrockDimensionNames.DisplayName(_lastMapDimension)}-{angleText}.png"
        };
        if (save.ShowDialog(this) != true) return;

        _databaseBusy = true;
        StatusText = "正在生成 PNG…";
        try
        {
            BlockTextureOverrideStore.Reload();
            var document = _document!;
            var exportOverlays = new MapExportOverlayOptions(
                options.Players, options.Entities, options.BlockEntities,
                options.SpawnPoints, options.HardcodedSpawners, options.Villages);
            var frame = await Task.Run(() => RenderExportFrame(document, options, exportOverlays));
            var effectivePixelsPerBlock = EffectiveExportPixelsPerBlock(frame, options.PixelsPerBlock);
            var bitmap = CreateExportBitmap(frame, effectivePixelsPerBlock, options.DrawGrid,
                MapBuildHeightLimits.IsChecked == true, options.UngeneratedDisplay);
            using var stream = File.Create(save.FileName);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            encoder.Save(stream);
            StatusText = $"PNG 已导出：{save.FileName}";
            var scaleNote = effectivePixelsPerBlock == options.PixelsPerBlock
                ? string.Empty
                : $" · 自动降为 {effectivePixelsPerBlock} px/方块";
            MapStatusText = $"导出完成 · {frame.Width * effectivePixelsPerBlock}×{frame.Height * effectivePixelsPerBlock} px · {angleText}{scaleNote}";
        }
        catch (Exception ex)
        {
            StatusText = "PNG 导出失败。";
            MessageBox.Show(this, ex.Message, "MCBEEditor", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            _databaseBusy = false;
        }
    }

    private (long MinimumX, long MinimumZ, long MaximumX, long MaximumZ) CurrentMapExportBounds()
    {
        if (_mapRegion is { } surface)
        {
            return (
                surface.OriginBlockX,
                surface.OriginBlockZ,
                (long)surface.OriginBlockX + surface.LogicalWidthBlocks - 1,
                (long)surface.OriginBlockZ + surface.LogicalHeightBlocks - 1);
        }

        var centerChunkX = BedrockSurfaceRegionRenderer.FloorDiv(_lastMapCenterX, 16);
        var centerChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(_lastMapCenterZ, 16);
        var minimumChunkX = (long)centerChunkX - _lastMapRadius;
        var minimumChunkZ = (long)centerChunkZ - _lastMapRadius;
        var maximumChunkX = (long)centerChunkX + _lastMapRadius;
        var maximumChunkZ = (long)centerChunkZ + _lastMapRadius;
        return (
            minimumChunkX * 16,
            minimumChunkZ * 16,
            maximumChunkX * 16 + 15,
            maximumChunkZ * 16 + 15);
    }

    private MapExportFrame RenderExportFrame(
        WorldDocument document,
        MapExportOptions options,
        MapExportOverlayOptions overlayOptions)
    {
        using var database = document.OpenDatabase(readOnly: true);
        var range = ResolveMapExportRange(database, _lastMapDimension, options);
        return options.Angle switch
        {
            MapExportAngle.YPositive or MapExportAngle.YNegative
                => RenderSurfaceExportFrame(document, database, options, overlayOptions, range),
            MapExportAngle.XPositive or MapExportAngle.XNegative or MapExportAngle.ZPositive or MapExportAngle.ZNegative
                => RenderCrossSectionExportFrame(document, database, options, overlayOptions, range),
            _ => throw new InvalidOperationException("未知导出方向。")
        };
    }

    private ResolvedMapExportRange ResolveMapExportRange(IWorldDatabase database, int dimension, MapExportOptions options)
    {
        var loaded = new BedrockChunkStore(database).ListChunks()
            .Where(summary => summary.Position.Dimension == dimension && IsLoadedExportChunk(summary))
            .ToArray();
        if (loaded.Length == 0)
            throw new InvalidOperationException("当前维度没有可导出的已加载区块。");

        var loadedMinimumX = loaded.Min(summary => (long)summary.Position.X) * 16;
        var loadedMaximumX = loaded.Max(summary => (long)summary.Position.X) * 16 + 15;
        var loadedMinimumZ = loaded.Min(summary => (long)summary.Position.Z) * 16;
        var loadedMaximumZ = loaded.Max(summary => (long)summary.Position.Z) * 16 + 15;

        var minimumX = options.MinimumX ?? loadedMinimumX;
        var minimumZ = options.MinimumZ ?? loadedMinimumZ;
        var maximumX = options.MaximumX ?? loadedMaximumX;
        var maximumZ = options.MaximumZ ?? loadedMaximumZ;
        if (minimumX > maximumX || minimumZ > maximumZ)
            throw new InvalidOperationException("导出范围无效：最小坐标不能大于最大坐标。");
        if (minimumX < int.MinValue || minimumX > int.MaxValue
            || maximumX < int.MinValue || maximumX > int.MaxValue
            || minimumZ < int.MinValue || minimumZ > int.MaxValue
            || maximumZ < int.MinValue || maximumZ > int.MaxValue)
            throw new InvalidOperationException("导出范围超出 Windows 当前 Int32 方块坐标范围。");

        var width = maximumX - minimumX + 1;
        var depth = maximumZ - minimumZ + 1;
        if (width > 4096 || depth > 4096)
            throw new InvalidOperationException(
                $"当前导出范围为 {width}×{depth} 方块。Windows 版单次精确 PNG 导出每个 X/Z 方向最多 4096 方块；请缩小范围或将无穷边界改为具体坐标。");

        return new ResolvedMapExportRange(
            dimension, checked((int)minimumX), checked((int)minimumZ), checked((int)maximumX), checked((int)maximumZ), loaded);
    }

    private static bool IsLoadedExportChunk(BedrockChunkSummary summary)
        => summary.HasTerrain
            || summary.BiomeRecordType is not null
            || summary.HasBlockEntities
            || summary.HasLegacyEntities
            || summary.HasHardcodedSpawners
            || summary.RecordCount > (summary.HasActorDigest ? 1 : 0);

    private MapExportFrame RenderSurfaceExportFrame(
        WorldDocument document,
        IWorldDatabase database,
        MapExportOptions options,
        MapExportOverlayOptions overlayOptions,
        ResolvedMapExportRange range)
    {
        var minimumChunkX = BedrockSurfaceRegionRenderer.FloorDiv(range.MinimumX, 16);
        var maximumChunkX = BedrockSurfaceRegionRenderer.FloorDiv(range.MaximumX, 16);
        var minimumChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(range.MinimumZ, 16);
        var maximumChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(range.MaximumZ, 16);
        var widthChunks = checked(maximumChunkX - minimumChunkX + 1);
        var depthChunks = checked(maximumChunkZ - minimumChunkZ + 1);
        var sideChunks = Math.Max(3, Math.Max(widthChunks, depthChunks));
        if ((sideChunks & 1) == 0) sideChunks++;
        var radius = sideChunks / 2;
        var centerChunkX = checked(minimumChunkX + radius);
        var centerChunkZ = checked(minimumChunkZ + radius);
        var centerBlockX64 = (long)centerChunkX * 16;
        var centerBlockZ64 = (long)centerChunkZ * 16;
        if (centerBlockX64 < int.MinValue || centerBlockX64 > int.MaxValue
            || centerBlockZ64 < int.MinValue || centerBlockZ64 > int.MaxValue)
            throw new InvalidOperationException("导出范围过于接近坐标极限，无法建立临时渲染区域。");

        var direction = options.Angle == MapExportAngle.YPositive
            ? BedrockProjectionDirection.PositiveToNegative
            : BedrockProjectionDirection.NegativeToPositive;
        var logicalSide = checked(sideChunks * 16);
        var region = new BedrockSurfaceRegionRenderer(database).Render(
            range.Dimension,
            (int)centerBlockX64,
            (int)centerBlockZ64,
            radius,
            drawChunkGrid: false,
            mode: _lastMapMode,
            verticalDirection: direction,
            maximumSamplesPerAxis: Math.Min(sideChunks, 512),
            maximumRasterSide: logicalSide,
            showUngeneratedTexture: false);
        if (region.IsDownsampled)
            throw new InvalidOperationException("导出范围无法保持 1:1 方块采样，请缩小导出范围。");

        var width = range.Width;
        var height = range.Depth;
        var sourceX = checked(range.MinimumX - region.OriginBlockX);
        var sourceZ = checked(range.MinimumZ - region.OriginBlockZ);
        var rgb = CropRgb(region.Rgb, region.Width, sourceX, sourceZ, width, height);
        var generated = BuildSurfaceExportGeneratedMask(range, width, height);
        ApplySurfaceUngeneratedDisplay(rgb, generated, width, height, range.MinimumX, range.MinimumZ, options.UngeneratedDisplay);
        var overlays = LoadExportOverlays(
            document, database, range.Dimension, BedrockMapAxis.Y, null,
            range.MinimumX, range.MinimumZ, width, height, overlayOptions);
        return new MapExportFrame(
            range.Dimension, BedrockMapAxis.Y, null,
            range.MinimumX, range.MinimumZ, 0, 0,
            width, height, rgb, generated, overlays);
    }

    private MapExportFrame RenderCrossSectionExportFrame(
        WorldDocument document,
        IWorldDatabase database,
        MapExportOptions options,
        MapExportOverlayOptions overlayOptions,
        ResolvedMapExportRange range)
    {
        var axis = options.Angle is MapExportAngle.XPositive or MapExportAngle.XNegative
            ? BedrockMapAxis.X
            : BedrockMapAxis.Z;
        var direction = options.Angle is MapExportAngle.XPositive or MapExportAngle.ZPositive
            ? BedrockProjectionDirection.PositiveToNegative
            : BedrockProjectionDirection.NegativeToPositive;
        var projectionMinimum = axis == BedrockMapAxis.X ? range.MinimumX : range.MinimumZ;
        var projectionMaximum = axis == BedrockMapAxis.X ? range.MaximumX : range.MaximumZ;
        var horizontalMinimum = axis == BedrockMapAxis.X ? range.MinimumZ : range.MinimumX;
        var horizontalMaximum = axis == BedrockMapAxis.X ? range.MaximumZ : range.MaximumX;
        var projectionDepth = checked(projectionMaximum - projectionMinimum + 1);
        var horizontalWidth = checked(horizontalMaximum - horizontalMinimum + 1);

        var minimumProjectionChunk = BedrockSurfaceRegionRenderer.FloorDiv(projectionMinimum, 16);
        var maximumProjectionChunk = BedrockSurfaceRegionRenderer.FloorDiv(projectionMaximum, 16);
        var intersecting = range.LoadedSummaries.Where(summary =>
        {
            var fixedChunk = axis == BedrockMapAxis.X ? summary.Position.X : summary.Position.Z;
            return fixedChunk >= minimumProjectionChunk && fixedChunk <= maximumProjectionChunk;
        }).ToArray();
        var (minimumY, maximumY) = LoadedVerticalRange(intersecting, range.Dimension);
        var verticalHeight = checked(maximumY - minimumY + 1);
        var sideBlocks = Math.Max(16, Math.Max(horizontalWidth, verticalHeight));
        if (sideBlocks > 4096)
            throw new InvalidOperationException("当前剖面导出范围超过 4096 方块，请缩小 X/Z 范围。");
        var half = sideBlocks / 2;
        var centerY = checked(minimumY + half);
        var horizontalCenter = checked(horizontalMinimum + half);
        var frontCoordinate = direction == BedrockProjectionDirection.PositiveToNegative
            ? projectionMaximum
            : projectionMinimum;
        var fixedX = axis == BedrockMapAxis.X ? frontCoordinate : horizontalCenter;
        var fixedZ = axis == BedrockMapAxis.Z ? frontCoordinate : horizontalCenter;

        var region = new BedrockCrossSectionRenderer(database).Render(
            axis,
            fixedX,
            fixedZ,
            centerY,
            sideBlocks,
            range.Dimension,
            _lastMapMode,
            drawSubChunkGrid: false,
            drawBuildHeightLimits: false,
            projectionDepth: projectionDepth,
            projectionDirection: direction,
            maximumRasterSide: sideBlocks,
            showUngeneratedTexture: false,
            projectionMinimumCoordinateOverride: projectionMinimum,
            projectionMaximumCoordinateOverride: projectionMaximum);
        if (region.IsDownsampled)
            throw new InvalidOperationException("剖面导出范围无法保持 1:1 方块采样，请缩小范围。");

        var sourceX = checked(horizontalMinimum - region.OriginHorizontal);
        var sourceY = checked(region.MaximumY - maximumY);
        var rgb = CropRgb(region.Rgb, region.Width, sourceX, sourceY, horizontalWidth, verticalHeight);
        var generated = BuildCrossExportPlaneGeneratedMask(
            database, range.Dimension, axis, frontCoordinate, horizontalMinimum, minimumY, horizontalWidth, verticalHeight);
        if (options.UngeneratedDisplay == MapUngeneratedExportMode.Texture)
            ApplyCrossUngeneratedTexture(rgb, generated, horizontalWidth, verticalHeight, horizontalMinimum, minimumY);
        var overlays = LoadExportOverlays(
            document, database, range.Dimension, axis, frontCoordinate,
            horizontalMinimum, minimumY, horizontalWidth, verticalHeight, overlayOptions);
        return new MapExportFrame(
            range.Dimension, axis, frontCoordinate,
            horizontalMinimum, minimumY, minimumY, maximumY,
            horizontalWidth, verticalHeight, rgb, generated, overlays);
    }

    private static void ApplySurfaceUngeneratedDisplay(
        uint[] rgb,
        bool[] generated,
        int width,
        int height,
        int minimumX,
        int minimumZ,
        MapUngeneratedExportMode mode)
    {
        if (mode == MapUngeneratedExportMode.Transparent) return;
        for (var z = 0; z < height; z++)
        for (var x = 0; x < width; x++)
        {
            var index = z * width + x;
            if (generated[index]) continue;
            if (mode == MapUngeneratedExportMode.Air)
            {
                rgb[index] = BedrockBlockMapColorCatalog.AirRgb;
                continue;
            }
            var worldX = minimumX + x;
            var worldZ = minimumZ + z;
            rgb[index] = BedrockSurfaceRegionRenderer.IsUngeneratedStripe(worldX, worldZ)
                ? BedrockBlockMapColorCatalog.UngeneratedLineRgb
                : BedrockBlockMapColorCatalog.AirRgb;
        }
    }

    private static void ApplyCrossUngeneratedTexture(
        uint[] rgb,
        bool[] generated,
        int width,
        int height,
        int minimumHorizontal,
        int minimumY)
    {
        for (var row = 0; row < height; row++)
        {
            var y = minimumY + (height - 1 - row);
            var localY = y - BedrockSurfaceRegionRenderer.FloorDiv(y, 16) * 16;
            var screenLocalY = 15 - localY;
            for (var column = 0; column < width; column++)
            {
                var index = row * width + column;
                if (generated[index]) continue;
                var horizontal = minimumHorizontal + column;
                var localHorizontal = horizontal - BedrockSurfaceRegionRenderer.FloorDiv(horizontal, 16) * 16;
                var difference = screenLocalY - localHorizontal;
                rgb[index] = difference is -8 or 0 or 8
                    ? BedrockBlockMapColorCatalog.UngeneratedLineRgb
                    : BedrockBlockMapColorCatalog.AirRgb;
            }
        }
    }

    private static bool[] BuildSurfaceExportGeneratedMask(ResolvedMapExportRange range, int width, int height)
    {
        var loaded = range.LoadedSummaries
            .Select(summary => summary.Position)
            .ToHashSet();
        var generated = new bool[checked(width * height)];
        for (var z = 0; z < height; z++)
        for (var x = 0; x < width; x++)
        {
            var worldX = range.MinimumX + x;
            var worldZ = range.MinimumZ + z;
            var position = new ChunkPosition(
                BedrockSurfaceRegionRenderer.FloorDiv(worldX, 16),
                BedrockSurfaceRegionRenderer.FloorDiv(worldZ, 16),
                range.Dimension);
            generated[z * width + x] = loaded.Contains(position);
        }
        return generated;
    }

    private static bool[] BuildCrossExportPlaneGeneratedMask(
        IWorldDatabase database,
        int dimension,
        BedrockMapAxis axis,
        int fixedCoordinate,
        int minimumHorizontal,
        int minimumY,
        int width,
        int height)
    {
        var generated = new bool[checked(width * height)];
        var access = new BedrockChunkSubChunkAccess(database);
        var cache = new Dictionary<ChunkPosition, HashSet<sbyte>>();

        bool HasSubChunk(int horizontal, int y)
        {
            var worldX = axis == BedrockMapAxis.X ? fixedCoordinate : horizontal;
            var worldZ = axis == BedrockMapAxis.Z ? fixedCoordinate : horizontal;
            var position = new ChunkPosition(
                BedrockSurfaceRegionRenderer.FloorDiv(worldX, 16),
                BedrockSurfaceRegionRenderer.FloorDiv(worldZ, 16),
                dimension);
            var subY = BedrockSurfaceRegionRenderer.FloorDiv(y, 16);
            if (subY < sbyte.MinValue || subY > sbyte.MaxValue) return false;
            if (!cache.TryGetValue(position, out var ys))
            {
                ys = access.Records(position).Select(record => record.YIndex).ToHashSet();
                cache[position] = ys;
            }
            return ys.Contains((sbyte)subY);
        }

        for (var row = 0; row < height; row++)
        {
            var y = minimumY + (height - 1 - row);
            for (var column = 0; column < width; column++)
            {
                var horizontal = minimumHorizontal + column;
                generated[row * width + column] = HasSubChunk(horizontal, y);
            }
        }
        return generated;
    }

    private static (int MinimumY, int MaximumY) LoadedVerticalRange(
        IReadOnlyList<BedrockChunkSummary> summaries,
        int dimension)
    {
        int? minimumY = null;
        int? maximumY = null;
        foreach (var summary in summaries)
        {
            if (summary.HasLegacyTerrain)
            {
                minimumY = Math.Min(minimumY ?? 0, 0);
                maximumY = Math.Max(maximumY ?? 127, 127);
            }
            if (summary.MinimumSubChunkY is { } minimumSub)
            {
                var value = minimumSub * 16;
                minimumY = Math.Min(minimumY ?? value, value);
            }
            if (summary.MaximumSubChunkY is { } maximumSub)
            {
                var value = maximumSub * 16 + 15;
                maximumY = Math.Max(maximumY ?? value, value);
            }
        }
        if (minimumY.HasValue && maximumY.HasValue) return (minimumY.Value, maximumY.Value);
        return dimension switch
        {
            1 => (0, 127),
            2 => (0, 255),
            _ => (-64, 319)
        };
    }

    private static uint[] CropRgb(
        uint[] source,
        int sourceWidth,
        int sourceX,
        int sourceY,
        int width,
        int height)
    {
        if (sourceWidth <= 0 || width <= 0 || height <= 0 || sourceX < 0 || sourceY < 0)
            throw new InvalidOperationException("导出裁剪范围无效。");
        var sourceHeight = source.Length / sourceWidth;
        if (sourceX + width > sourceWidth || sourceY + height > sourceHeight)
            throw new InvalidOperationException("导出裁剪范围超出临时渲染图像。");
        var result = new uint[checked(width * height)];
        for (var row = 0; row < height; row++)
            Array.Copy(source, (sourceY + row) * sourceWidth + sourceX, result, row * width, width);
        return result;
    }

    private static int EffectiveExportPixelsPerBlock(MapExportFrame frame, int requested)
    {
        requested = Math.Clamp(requested, 1, 16);
        var longestSide = Math.Max(frame.Width, frame.Height);
        if (longestSide <= 0) return 1;
        var maximum = Math.Max(1, 4096 / longestSide);
        return Math.Min(requested, maximum);
    }

    private static MapExportOverlayData LoadExportOverlays(
        WorldDocument document,
        IWorldDatabase database,
        int dimension,
        BedrockMapAxis axis,
        int? fixedCoordinate,
        int originHorizontal,
        int originVertical,
        int width,
        int height,
        MapExportOverlayOptions options)
    {
        var spawn = options.SpawnPoints
            ? SpawnMapFeatureStore.Read(document, database).Where(item => item.Dimension == dimension).ToArray()
            : Array.Empty<SpawnMapFeature>();
        IReadOnlyList<HardcodedSpawnersRecord> spawners = Array.Empty<HardcodedSpawnersRecord>();
        if (options.HardcodedSpawners)
        {
            int minChunkX, maxChunkX, minChunkZ, maxChunkZ;
            if (axis == BedrockMapAxis.Y)
            {
                minChunkX = BedrockSurfaceRegionRenderer.FloorDiv(originHorizontal, 16);
                maxChunkX = BedrockSurfaceRegionRenderer.FloorDiv(originHorizontal + width - 1, 16);
                minChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(originVertical, 16);
                maxChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(originVertical + height - 1, 16);
            }
            else if (axis == BedrockMapAxis.X)
            {
                var fixedX = fixedCoordinate ?? 0;
                minChunkX = maxChunkX = BedrockSurfaceRegionRenderer.FloorDiv(fixedX, 16);
                minChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(originHorizontal, 16);
                maxChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(originHorizontal + width - 1, 16);
            }
            else
            {
                var fixedZ = fixedCoordinate ?? 0;
                minChunkZ = maxChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(fixedZ, 16);
                minChunkX = BedrockSurfaceRegionRenderer.FloorDiv(originHorizontal, 16);
                maxChunkX = BedrockSurfaceRegionRenderer.FloorDiv(originHorizontal + width - 1, 16);
            }
            spawners = new HardcodedSpawnersStore(database).RecordsInChunkRectangle(
                dimension, minChunkX, minChunkZ, maxChunkX, maxChunkZ);
        }
        var villages = options.Villages && axis == BedrockMapAxis.Y
            ? new VillageMapFeatureStore(database).Features().Where(item => item.Dimension == dimension).ToArray()
            : Array.Empty<VillageMapFeature>();

        var objects = new List<WorldObjectRow>();
        if (options.Players || options.Entities || options.BlockEntities)
        {
            bool InFrame(double x, double y, double z)
            {
                if (axis == BedrockMapAxis.Y)
                    return x >= originHorizontal && x < originHorizontal + width
                        && z >= originVertical && z < originVertical + height;
                if (fixedCoordinate is not int fixedValue) return false;
                var fixedDelta = axis == BedrockMapAxis.X ? Math.Abs(x - fixedValue) : Math.Abs(z - fixedValue);
                if (fixedDelta > 0.99 || y < originVertical || y >= originVertical + height) return false;
                var horizontal = axis == BedrockMapAxis.X ? z : x;
                return horizontal >= originHorizontal && horizontal < originHorizontal + width;
            }

            if (options.Players)
            {
                var players = new PlayerNbtStore(database);
                foreach (var player in players.Records())
                {
                    var position = players.CurrentPosition(player);
                    if (position is null || position.Dimension != dimension || !InFrame(position.X, position.Y, position.Z)) continue;
                    objects.Add(RowForPlayer(player, position, players.UniqueId(player)));
                }
            }

            if (options.Entities || options.BlockEntities)
            {
                var centerHorizontal = originHorizontal + Math.Max(0, width - 1) / 2;
                int centerX; int centerZ;
                if (axis == BedrockMapAxis.X)
                {
                    centerX = fixedCoordinate ?? 0; centerZ = centerHorizontal;
                }
                else if (axis == BedrockMapAxis.Z)
                {
                    centerX = centerHorizontal; centerZ = fixedCoordinate ?? 0;
                }
                else
                {
                    centerX = originHorizontal + Math.Max(0, width - 1) / 2;
                    centerZ = originVertical + Math.Max(0, height - 1) / 2;
                }
                var radiusChunks = Math.Max(1, (Math.Max(width, axis == BedrockMapAxis.Y ? height : width) + 31) / 32);
                var scan = new BedrockWorldObjectScanner(database).ScanRegion(
                    BedrockSurfaceRegionRenderer.FloorDiv(centerX, 16),
                    BedrockSurfaceRegionRenderer.FloorDiv(centerZ, 16),
                    dimension, radiusChunks, options.Entities, options.BlockEntities, maximumObjects: 200_000);
                objects.AddRange(scan.Objects
                    .Where(item => item.Position is { } position && InFrame(position.X, position.Y, position.Z))
                    .Select(RowForWorldObject));
            }
        }
        return new MapExportOverlayData(spawn, spawners, villages, objects);
    }

    private static BitmapSource CreateExportBitmap(
        MapExportFrame frame,
        int pixelsPerBlock,
        bool drawGrid,
        bool drawBuildLimits,
        MapUngeneratedExportMode ungeneratedDisplay)
    {
        pixelsPerBlock = Math.Clamp(pixelsPerBlock, 1, 16);
        var width = checked(frame.Width * pixelsPerBlock);
        var height = checked(frame.Height * pixelsPerBlock);
        var stride = checked(width * 4);
        var buffer = new byte[checked(stride * height)];

        for (var sourceY = 0; sourceY < frame.Height; sourceY++)
        {
            for (var sourceX = 0; sourceX < frame.Width; sourceX++)
            {
                var color = frame.Rgb[sourceY * frame.Width + sourceX];
                var b = (byte)(color & 0xFF);
                var g = (byte)((color >> 8) & 0xFF);
                var r = (byte)((color >> 16) & 0xFF);
                for (var py = 0; py < pixelsPerBlock; py++)
                {
                    var row = (sourceY * pixelsPerBlock + py) * stride;
                    for (var px = 0; px < pixelsPerBlock; px++)
                    {
                        var offset = row + (sourceX * pixelsPerBlock + px) * 4;
                        buffer[offset] = b;
                        buffer[offset + 1] = g;
                        buffer[offset + 2] = r;
                        buffer[offset + 3] = ungeneratedDisplay == MapUngeneratedExportMode.Transparent
                            && !frame.Generated[sourceY * frame.Width + sourceX]
                                ? (byte)0
                                : (byte)0xFF;
                    }
                }
            }
        }

        if (drawGrid)
        {
            if (frame.IsCrossSection)
                DrawCrossExportGrid(buffer, stride, width, height, frame, pixelsPerBlock);
            else
                DrawSurfaceExportGrid(buffer, stride, width, height, frame, pixelsPerBlock);
        }
        if (drawBuildLimits && frame.IsCrossSection)
            DrawBuildExportLimits(buffer, stride, width, height, frame, pixelsPerBlock);
        DrawExportFeatureOverlays(buffer, stride, width, height, frame, pixelsPerBlock);

        var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, buffer, stride);
        bitmap.Freeze();
        return bitmap;
    }

    private static void DrawExportFeatureOverlays(byte[] buffer, int stride, int widthPixels, int heightPixels, MapExportFrame frame, int ppb)
    {
        foreach (var spawn in frame.Overlays.SpawnPoints)
        {
            if (!TryExportPoint(frame, spawn.X, spawn.Y, spawn.Z, ppb, out var x, out var y)) continue;
            DrawRasterMarker(buffer, stride, widthPixels, heightPixels, x, y, spawn.IsWorldSpawn ? 0xFFD700u : 0x32CD32u, ppb);
        }

        foreach (var record in frame.Overlays.HardcodedSpawners)
        foreach (var area in record.Document.Areas)
        {
            if (frame.Axis == BedrockMapAxis.Y)
            {
                var x0 = (area.MinimumX - frame.OriginHorizontal) * ppb;
                var y0 = (area.MinimumZ - frame.OriginVertical) * ppb;
                var x1 = (area.MaximumX - frame.OriginHorizontal + 1) * ppb - 1;
                var y1 = (area.MaximumZ - frame.OriginVertical + 1) * ppb - 1;
                DrawRasterRectangle(buffer, stride, widthPixels, heightPixels, x0, y0, x1, y1, 0xFF1493);
            }
            else
            {
                if (frame.FixedCoordinate is not int fixedCoordinate) continue;
                if (frame.Axis == BedrockMapAxis.X && (fixedCoordinate < area.MinimumX || fixedCoordinate > area.MaximumX)) continue;
                if (frame.Axis == BedrockMapAxis.Z && (fixedCoordinate < area.MinimumZ || fixedCoordinate > area.MaximumZ)) continue;
                var horizontal0 = frame.Axis == BedrockMapAxis.X ? area.MinimumZ : area.MinimumX;
                var horizontal1 = frame.Axis == BedrockMapAxis.X ? area.MaximumZ : area.MaximumX;
                var x0 = (horizontal0 - frame.OriginHorizontal) * ppb;
                var x1 = (horizontal1 - frame.OriginHorizontal + 1) * ppb - 1;
                var y0 = (frame.MaximumY - area.MaximumY) * ppb;
                var y1 = (frame.MaximumY - area.MinimumY + 1) * ppb - 1;
                DrawRasterRectangle(buffer, stride, widthPixels, heightPixels, x0, y0, x1, y1, 0xFF1493);
            }
        }

        if (frame.Axis == BedrockMapAxis.Y)
        {
            foreach (var village in frame.Overlays.Villages)
            {
                if (village.Bounds is { } bounds)
                {
                    var x0 = (int)((bounds.MinimumX - frame.OriginHorizontal) * ppb);
                    var y0 = (int)((bounds.MinimumZ - frame.OriginVertical) * ppb);
                    var x1 = (int)((bounds.MaximumX - frame.OriginHorizontal + 1) * ppb - 1);
                    var y1 = (int)((bounds.MaximumZ - frame.OriginVertical + 1) * ppb - 1);
                    DrawRasterRectangle(buffer, stride, widthPixels, heightPixels, x0, y0, x1, y1, 0x32CD32);
                }
                if (village.Center is { } center && TryExportPoint(frame, center.X, center.Y, center.Z, ppb, out var cx, out var cy))
                    DrawRasterMarker(buffer, stride, widthPixels, heightPixels, cx, cy, 0xFF8C00, ppb);
                foreach (var poi in village.PointsOfInterest)
                    if (TryExportPoint(frame, poi.X, poi.Y, poi.Z, ppb, out var px, out var py))
                        DrawRasterMarker(buffer, stride, widthPixels, heightPixels, px, py, 0x9370DB, ppb);
            }
        }

        foreach (var row in frame.Overlays.Objects)
        {
            if (row.X is not { } objectX || row.Y is not { } objectY || row.Z is not { } objectZ) continue;
            if (!TryExportObjectPoint(frame, objectX, objectY, objectZ, ppb, out var px, out var py)) continue;
            var color = row.KindText switch
            {
                "本地玩家" => 0xFFD700u,
                "在线玩家" => 0x1E90FFu,
                "方块实体" => 0x9370DBu,
                _ => 0xCD5C5Cu
            };
            DrawRasterMarker(buffer, stride, widthPixels, heightPixels, px, py, color, ppb);
        }
    }

    private static bool TryExportPoint(MapExportFrame frame, long x, long? y, long z, int ppb, out int pixelX, out int pixelY)
    {
        pixelX = pixelY = 0;
        if (frame.Axis == BedrockMapAxis.Y)
        {
            pixelX = checked((int)((x - frame.OriginHorizontal) * ppb + ppb / 2));
            pixelY = checked((int)((z - frame.OriginVertical) * ppb + ppb / 2));
            return pixelX >= 0 && pixelY >= 0 && pixelX < frame.Width * ppb && pixelY < frame.Height * ppb;
        }
        if (!y.HasValue || frame.FixedCoordinate is not int fixedCoordinate) return false;
        var fixedValue = frame.Axis == BedrockMapAxis.X ? x : z;
        if (fixedValue != fixedCoordinate) return false;
        var horizontal = frame.Axis == BedrockMapAxis.X ? z : x;
        pixelX = checked((int)((horizontal - frame.OriginHorizontal) * ppb + ppb / 2));
        pixelY = checked((int)((frame.MaximumY - y.Value) * ppb + ppb / 2));
        return pixelX >= 0 && pixelY >= 0 && pixelX < frame.Width * ppb && pixelY < frame.Height * ppb;
    }

    private static bool TryExportObjectPoint(MapExportFrame frame, double x, double y, double z, int ppb, out int pixelX, out int pixelY)
    {
        pixelX = pixelY = 0;
        if (frame.Axis == BedrockMapAxis.Y)
        {
            var rasterX = (x - frame.OriginHorizontal) * ppb;
            var rasterY = (z - frame.OriginVertical) * ppb;
            pixelX = (int)Math.Round(rasterX, MidpointRounding.AwayFromZero);
            pixelY = (int)Math.Round(rasterY, MidpointRounding.AwayFromZero);
            return pixelX >= 0 && pixelY >= 0 && pixelX < frame.Width * ppb && pixelY < frame.Height * ppb;
        }
        if (frame.FixedCoordinate is not int fixedCoordinate) return false;
        var fixedValue = frame.Axis == BedrockMapAxis.X ? x : z;
        if (Math.Abs(fixedValue - fixedCoordinate) > 0.99) return false;
        var horizontal = frame.Axis == BedrockMapAxis.X ? z : x;
        pixelX = (int)Math.Round((horizontal - frame.OriginHorizontal) * ppb, MidpointRounding.AwayFromZero);
        pixelY = (int)Math.Round((frame.MaximumY - y) * ppb, MidpointRounding.AwayFromZero);
        return pixelX >= 0 && pixelY >= 0 && pixelX < frame.Width * ppb && pixelY < frame.Height * ppb;
    }

    private static void DrawRasterMarker(byte[] buffer, int stride, int width, int height, int centerX, int centerY, uint rgb, int ppb)
    {
        var radius = Math.Max(1, Math.Min(4, ppb));
        for (var y = centerY - radius; y <= centerY + radius; y++)
        for (var x = centerX - radius; x <= centerX + radius; x++)
        {
            if (x < 0 || y < 0 || x >= width || y >= height) continue;
            SetRasterPixel(buffer, stride, x, y, rgb);
        }
    }

    private static void DrawRasterRectangle(byte[] buffer, int stride, int width, int height, int x0, int y0, int x1, int y1, uint rgb)
    {
        if (width <= 0 || height <= 0) return;
        if (x0 > x1) (x0, x1) = (x1, x0);
        if (y0 > y1) (y0, y1) = (y1, y0);
        // Reject a fully off-canvas rectangle before clamping. Clamping first would
        // collapse it onto an image edge and draw a false border line.
        if (x1 < 0 || y1 < 0 || x0 >= width || y0 >= height) return;
        x0 = Math.Clamp(x0, 0, width - 1); x1 = Math.Clamp(x1, 0, width - 1);
        y0 = Math.Clamp(y0, 0, height - 1); y1 = Math.Clamp(y1, 0, height - 1);
        for (var x = x0; x <= x1; x++) { SetRasterPixel(buffer, stride, x, y0, rgb); SetRasterPixel(buffer, stride, x, y1, rgb); }
        for (var y = y0; y <= y1; y++) { SetRasterPixel(buffer, stride, x0, y, rgb); SetRasterPixel(buffer, stride, x1, y, rgb); }
    }

    private static void DrawSurfaceExportGrid(byte[] buffer, int stride, int widthPixels, int heightPixels, MapExportFrame frame, int ppb)
    {
        var endX = frame.OriginHorizontal + frame.Width;
        var endZ = frame.OriginVertical + frame.Height;
        for (var worldX = FirstMultipleAtOrAfter(frame.OriginHorizontal, 16); worldX < endX; worldX += 16)
        {
            if (worldX <= frame.OriginHorizontal) continue;
            DrawVerticalRasterLine(buffer, stride, widthPixels, heightPixels, checked((int)((worldX - frame.OriginHorizontal) * ppb)), 0x555555);
        }
        for (var worldZ = FirstMultipleAtOrAfter(frame.OriginVertical, 16); worldZ < endZ; worldZ += 16)
        {
            if (worldZ <= frame.OriginVertical) continue;
            DrawHorizontalRasterLine(buffer, stride, widthPixels, heightPixels, checked((int)((worldZ - frame.OriginVertical) * ppb)), 0, widthPixels, 0x555555);
        }
    }

    private static void DrawCrossExportGrid(byte[] buffer, int stride, int widthPixels, int heightPixels, MapExportFrame frame, int ppb)
    {
        var endHorizontal = frame.OriginHorizontal + frame.Width;
        for (var boundary = FirstMultipleAtOrAfter(frame.OriginHorizontal, 16); boundary < endHorizontal; boundary += 16)
        {
            if (boundary <= frame.OriginHorizontal) continue;
            DrawVerticalRasterLine(buffer, stride, widthPixels, heightPixels, checked((int)((boundary - frame.OriginHorizontal) * ppb)), 0x666666);
        }
        for (var boundaryY = FirstMultipleAtOrAfter(frame.MinimumY + 1, 16); boundaryY <= frame.MaximumY; boundaryY += 16)
        {
            var y = (frame.MaximumY - boundaryY + 1) * ppb;
            if (y > 0 && y < heightPixels)
                DrawHorizontalRasterLine(buffer, stride, widthPixels, heightPixels, checked((int)y), 0, widthPixels, 0x666666);
        }
    }

    private static void DrawBuildExportLimits(byte[] buffer, int stride, int widthPixels, int heightPixels, MapExportFrame frame, int ppb)
    {
        var (minimum, maximumExclusive) = frame.Dimension switch
        {
            1 => (0, 128),
            2 => (0, 256),
            _ => (-64, 320)
        };
        foreach (var boundaryY in new[] { minimum, maximumExclusive })
        {
            var y = (frame.MaximumY - boundaryY + 1) * ppb;
            if (y < 0 || y >= heightPixels) continue;
            for (var x = 0; x < frame.Width; x++)
            {
                var world = frame.OriginHorizontal + x;
                if ((BedrockSurfaceRegionRenderer.FloorDiv(world, 4) & 1) != 0) continue;
                DrawHorizontalRasterLine(buffer, stride, widthPixels, heightPixels, y, x * ppb, Math.Min(widthPixels, (x + 1) * ppb), 0xE53935);
            }
        }
    }

    private static void DrawVerticalRasterLine(byte[] buffer, int stride, int width, int height, int x, uint rgb)
    {
        if (x < 0 || x >= width) return;
        for (var y = 0; y < height; y++) SetRasterPixel(buffer, stride, x, y, rgb);
    }

    private static void DrawHorizontalRasterLine(byte[] buffer, int stride, int width, int height, int y, int startX, int endX, uint rgb)
    {
        if (y < 0 || y >= height) return;
        startX = Math.Clamp(startX, 0, width);
        endX = Math.Clamp(endX, 0, width);
        for (var x = startX; x < endX; x++) SetRasterPixel(buffer, stride, x, y, rgb);
    }

    private static void SetRasterPixel(byte[] buffer, int stride, int x, int y, uint rgb)
    {
        var offset = y * stride + x * 4;
        buffer[offset] = (byte)(rgb & 0xFF);
        buffer[offset + 1] = (byte)((rgb >> 8) & 0xFF);
        buffer[offset + 2] = (byte)((rgb >> 16) & 0xFF);
        buffer[offset + 3] = 0xFF;
    }

    private sealed record ResolvedMapExportRange(
        int Dimension,
        int MinimumX,
        int MinimumZ,
        int MaximumX,
        int MaximumZ,
        IReadOnlyList<BedrockChunkSummary> LoadedSummaries)
    {
        public int Width => checked(MaximumX - MinimumX + 1);
        public int Depth => checked(MaximumZ - MinimumZ + 1);
    }

    private sealed record MapExportOverlayOptions(
        bool Players, bool Entities, bool BlockEntities,
        bool SpawnPoints, bool HardcodedSpawners, bool Villages);
    private sealed record MapExportOverlayData(
        IReadOnlyList<SpawnMapFeature> SpawnPoints,
        IReadOnlyList<HardcodedSpawnersRecord> HardcodedSpawners,
        IReadOnlyList<VillageMapFeature> Villages,
        IReadOnlyList<WorldObjectRow> Objects);

    private sealed record MapExportFrame(
        int Dimension,
        BedrockMapAxis Axis,
        int? FixedCoordinate,
        int OriginHorizontal,
        int OriginVertical,
        int MinimumY,
        int MaximumY,
        int Width,
        int Height,
        uint[] Rgb,
        bool[] Generated,
        MapExportOverlayData Overlays)
    {
        public bool IsCrossSection => Axis != BedrockMapAxis.Y;
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
