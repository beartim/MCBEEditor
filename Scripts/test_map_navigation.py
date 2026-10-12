#!/usr/bin/env python3
"""Exercise production navigation/state methods with headless UI/render boundaries."""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def block(text, pattern):
    match = re.search(pattern, text)
    if not match:
        return None
    start = match.start()
    opening = text.index("{", match.start())
    depth = 1
    cursor = opening + 1
    while depth:
        if text[cursor] == "{":
            depth += 1
        elif text[cursor] == "}":
            depth -= 1
        cursor += 1
    return text[start:cursor]


def swift_test(work):
    source = (ROOT / "Sources/UI/WorldMapViewController.swift").read_text()
    methods = []
    for name in ["locate", "prepareMapLocation", "mapDimensionIndex"]:
        if name == "locate":
            patterns = [r"  private func locate\(player:", r"  func locate\(worldObject:"]
        else:
            patterns = [rf"  private func {name}\("]
        for pattern in patterns:
            body = block(source, pattern)
            if body:
                methods.append(body)
    program = r'''
import Foundation
enum Axis { case x, y, z }
enum BedrockDimension: Int32, CaseIterable { case overworld, nether, theEnd }
enum MCBEEditorError: Error { case malformedData(String) }
struct Position {
  let x: Double, y: Double, z: Double
  var blockX: Int64 { Int64(floor(x)) }
  var blockY: Int32 { Int32(floor(y)) }
  var blockZ: Int64 { Int64(floor(z)) }
}
typealias BedrockWorldObjectPosition = Position
struct MapPlayerCoordinate { let position: PlayerPosition }
struct PlayerPosition { let x: Double, y: Double, z: Double; let dimension: Int32 }
struct Kind { let displayName: String }
struct BedrockWorldObject {
  let stableID = "object"
  let position: Position?
  let dimension: Int32
  let kind = Kind(displayName: "entity")
}
final class Field { var text: String? = "0" }
final class Control { var selectedSegmentIndex = 0 }
final class Session { func rememberSelectedWorldObject(_ value: BedrockWorldObject) {} }
final class Overlay { func setSelectedObjectID(_ value: String) {} }
struct MapViewportAnchor { let blockX: Double, blockZ: Double, zoomScale: Double }
final class Navigation {
  let dimensionControl = Control(), coordinateModeControl = Control()
  let xField = Field(), yField = Field(), zField = Field()
  let session = Session(), objectOverlayView = Overlay()
  var selectedWorldObjectID: String?
  var currentSliceAxis: Axis = .y
  var sliceCenterBlockX: Int64 = 0, sliceCenterBlockZ: Int64 = 0
  var sliceCenterY: Int32 = 63
  var effectiveZoomScale: Double = 1
  var rendered = 0, errors = 0
  func loadViewIfNeeded() {}
  func showError(_ error: Error, title: String) { errors += 1 }
  func render(centerX: Int32, centerZ: Int32, anchor: MapViewportAnchor, reason: String, showOverlay: Bool) { rendered += 1 }
''' + "\n".join(methods) + r'''
  func verifyPlayer(_ value: MapPlayerCoordinate) { locate(player: value) }
}
@main struct Test {
  static func main() {
    var checks = 0
    for axis in [Axis.x, .z] {
      for dimension: Int32 in [0, 1, 2] {
        let object = Navigation(); object.currentSliceAxis = axis
        object.locate(worldObject: BedrockWorldObject(position: Position(x: 1000, y: 100, z: -1000), dimension: dimension))
        precondition(object.rendered == 1 && object.sliceCenterBlockX == 1000 && object.sliceCenterY == 100 && object.sliceCenterBlockZ == -1000, "object stayed on old cross-section")
        precondition(object.yField.text == "100")
        let player = Navigation(); player.currentSliceAxis = axis
        player.verifyPlayer(MapPlayerCoordinate(position: PlayerPosition(x: -1000, y: 90.75, z: 1000, dimension: dimension)))
        precondition(player.rendered == 1 && player.sliceCenterBlockX == -1000 && player.sliceCenterY == 90 && player.sliceCenterBlockZ == 1000, "player stayed on old cross-section")
        checks += 2
      }
    }
    let custom = Navigation()
    custom.locate(worldObject: BedrockWorldObject(position: Position(x: 1, y: 64, z: 1), dimension: 3))
    precondition(custom.rendered == 0 && custom.errors == 1, "unsupported dimension did not report failure")
    let customPlayer = Navigation()
    customPlayer.verifyPlayer(MapPlayerCoordinate(position: PlayerPosition(x: 1, y: 64, z: 1, dimension: 3)))
    precondition(customPlayer.rendered == 0 && customPlayer.errors == 1, "unsupported player dimension silently failed")
    print("PASS iOS production navigation methods: \(checks + 2) checks (headless UI boundaries)")
  }
}
'''
    path = work / "Navigation.swift"
    path.write_text(program)
    executable = work / "swift-navigation"
    subprocess.run([shutil.which("swiftc") or "swiftc", "-parse-as-library", str(path),
                    str(ROOT / "Sources/Chunk/MapCoordinate.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)


def windows_test(work, scenario):
    source = (ROOT / "Windows/MCBEEditor.Desktop/MainWindow.xaml.cs").read_text()
    methods = []
    for name in ["LocateChunkOnMapAsync", "LocateObjectOnMap_Click", "MapDimension_SelectionChanged",
                 "RenderMapAfterControlChange", "CanLocateMapDimension", "InitializeLocalPlayerCenterAsync",
                 "MapObjectLayerOption_Changed", "MapUngeneratedLayerOption_Changed",
                 "MapObjectLayersShowAll_Click", "MapObjectLayersHideAll_Click",
                 "RerenderMapPreservingViewportAsync", "RefreshMapObjectMarkersAsync"]:
        body = block(source, rf"    private (?:async )?(?:Task|void|bool) {name}\(")
        if body:
            methods.append(body.replace("private async void", "private async Task"))
    busy = block(source, r"    private bool _databaseBusy\s*\{") or "private bool _databaseBusy;"
    render = block(source, r"    private async Task RenderMapAsync\(")
    prefix = render[render.index("{") + 1:render.index("        if (!int.TryParse")]
    finalizer = re.findall(r"finally\s*\{\s*(_databaseBusy = false;)\s*\}", render)[-1]
    terrain_guard = render[render.index("                if (_pendingMapRender"):
                           render.index("                _mapRegion = region;")]
    overlay_tail = render[render.index("            _mapObjectMarkers = await"):
                          render.index("        }\n        catch", render.index("            _mapObjectMarkers = await"))]
    program = r'''
using System.Globalization;
record struct ChunkPosition(int X, int Z, int Dimension);
record Row(int Dimension, double? X, double? Y, double? Z);
class RoutedEventArgs {}
class SelectionChangedEventArgs {}
enum BedrockMapAxis { X, Y, Z }
class Toggle { public bool? IsChecked; }
record MapObjectMarker(bool Entity);
record PlayerPosition(int Dimension, double X, double Y, double Z) {
  public int BlockX => (int)Math.Floor(X);
  public int BlockY => (int)Math.Floor(Y);
  public int BlockZ => (int)Math.Floor(Z);
}
record PlayerRecord(bool IsLocal);
class TestDatabase(PlayerPosition? position) : IDisposable {
  public PlayerPosition? Position => position;
  public void Dispose() {}
}
class WorldDocument {
  public PlayerPosition? Position;
  public TestDatabase OpenDatabase(bool readOnly) => new(Position);
}
class PlayerNbtStore(TestDatabase database) {
  public IEnumerable<PlayerRecord> Records() => [new(true)];
  public PlayerPosition? CurrentPosition(PlayerRecord record) => database.Position;
}
enum MessageBoxButton { OK }
enum MessageBoxImage { Information, Warning, Error }
static class MessageBox { public static int Calls; public static void Show(object owner, string text, string title, MessageBoxButton button, MessageBoxImage image) { Calls++; } }
static class BedrockDimensionNames { public static string DisplayName(int value) => value.ToString(); }
class Field { public string Text = "0"; }
class Control {
  int selected;
  public Action? Changed;
  public int SelectedIndex { get => selected; set { selected = value; Changed?.Invoke(); } }
}
class FakeDispatcher {
  readonly Queue<Action> actions = new();
  public bool HasShutdownStarted => false;
  public void BeginInvoke(Action action) { lock(actions) actions.Enqueue(action); }
  public void Drain() { while(true) { Action? action; lock(actions) action = actions.Count > 0 ? actions.Dequeue() : null; if(action is null) return; action(); } }
}
class Navigation {
  WorldDocument? _document = new();
  bool HasRenderedMap = true;
  bool _databaseOperationActive, _mapChangingControls;
  TaskCompletionSource<bool>? _pendingMapRender;
  int? _mapRenderRadiusOverride;
  object? _mapViewportRestore;
  bool _mapPreserveSelectionOnNextRender;
  int _activeMapDimension, _mapCenterY;
  long _mapInteractionVersion;
  bool _mapChangingLayerOptions;
  object? _selectedMapSpawner;
  string? _selectedMapVillageIdentifier;
  BedrockMapAxis _mapAxis = BedrockMapAxis.Y;
  int _lastMapDimension, _lastMapCenterX, _lastMapCenterZ, _lastMapRadius = 5;
  IReadOnlyList<MapObjectMarker> _mapObjectMarkers = Array.Empty<MapObjectMarker>();
  readonly Toggle MapShowPlayers = new(), MapShowEntities = new(), MapShowBlockEntities = new();
  readonly Toggle MapShowSpawnPoints = new(), MapShowHardcodedSpawners = new(), MapShowVillages = new();
  readonly Toggle MapShowUngenerated = new(), MapBuildHeightLimits = new();
  ChunkPosition? _selectedMapChunk;
  readonly Dictionary<int, (int, int)> _mapCenters = new();
  readonly Field MapCenterX = new(), MapCenterY = new(), MapCenterZ = new();
  readonly Control MapDimension = new();
  readonly FakeDispatcher Dispatcher = new();
  Row? SelectedObjectRow;
  string MapStatusText = "", MapDetailText = "", StatusText = "";
  int axis, mode;
  public (int Dimension, int X, int Y, int Z, int Axis, int Mode)? Rendered;
  public int Started;
  bool RenderedUngenerated;
  bool VisibleEntity;
  int StaleOverlayPublishes;
  TaskCompletionSource<bool>? backendGate;
  TaskCompletionSource<bool>? markerGate, markerStarted;
  TaskCompletionSource<bool> backendFinished = new(TaskCreationOptions.RunContinuationsAsynchronously);
''' + busy + "\n" + "\n".join(methods) + r'''
  int SelectedMapDimension() => MapDimension.SelectedIndex;
  object? CaptureMapViewportSnapshot() => null;
  void ScheduleDynamicMapRefresh() {}
  void UpdateMapOverlay() {
    VisibleEntity = MapShowEntities.IsChecked == true && _mapObjectMarkers.Any(item => item.Entity);
    if(_pendingMapRender is not null && MapShowEntities.IsChecked == true && !VisibleEntity) StaleOverlayPublishes++;
  }
  async Task<IReadOnlyList<MapObjectMarker>> LoadMapObjectMarkersAsync(WorldDocument document, int dimension, int x, int z, int radius) {
    var includeEntities = MapShowEntities.IsChecked == true;
    markerStarted?.TrySetResult(true);
    if(markerGate is not null) await markerGate.Task;
    return includeEntities ? [new(true)] : Array.Empty<MapObjectMarker>();
  }
  Task LoadMapFeatureOverlaysAsync(WorldDocument document, int dimension, int x, int z, int radius) => Task.CompletedTask;
  async Task RenderMapAsync(long? expectedInteractionVersion = null) {
''' + prefix + r'''
    Started++;
    var captured = (SelectedMapDimension(), int.Parse(MapCenterX.Text), _mapCenterY, int.Parse(MapCenterZ.Text), axis, mode);
    var showUngeneratedTexture = MapShowUngenerated.IsChecked == true;
    var document = _document!;
    var dimension = captured.Item1; var centerX = captured.Item2; var centerZ = captured.Item4; var radius = 5;
    if(!preserveSelection) _selectedMapChunk = null;
    _databaseBusy = true;
    try {
      if(backendGate is not null) await backendGate.Task;
''' + terrain_guard + r'''
      Rendered = captured;
      RenderedUngenerated = showUngeneratedTexture;
      HasRenderedMap = true;
      _lastMapDimension = dimension; _lastMapCenterX = centerX; _lastMapCenterZ = centerZ;
''' + overlay_tail + r'''
    } finally { ''' + finalizer + r''' backendFinished.TrySetResult(true); }
  }
  public Navigation() { MapDimension.Changed = () => MapDimension_SelectionChanged(this, new()); }
  static async Task Complete(Navigation navigation, params Task[] tasks) {
    var until = DateTime.UtcNow.AddSeconds(3);
    while(tasks.Any(task => !task.IsCompleted) && DateTime.UtcNow < until) {
      navigation.Dispatcher.Drain();
      await Task.Delay(1);
    }
    navigation.Dispatcher.Drain();
    await Task.WhenAll(tasks).WaitAsync(TimeSpan.FromSeconds(3));
  }
  public async Task VerifyLayers() {
    foreach(var next in new[] { true, false }) {
      var map = new Navigation();
      map.HasRenderedMap = false;
      map.MapShowUngenerated.IsChecked = !next;
      map.backendGate = new(TaskCreationOptions.RunContinuationsAsynchronously);
      var render = map.RenderMapAsync();
      map.MapShowUngenerated.IsChecked = next;
      var change = map.MapUngeneratedLayerOption_Changed(map.MapShowUngenerated, new());
      map.backendGate.TrySetResult(true);
      await Complete(map, render, change);
      Check(map.RenderedUngenerated == next, "ungenerated layer toggle during terrain render was lost");
    }
    foreach(var refreshOnly in new[] { false, true }) {
      var map = new Navigation();
      map.MapShowEntities.IsChecked = false;
      map.markerGate = new(TaskCreationOptions.RunContinuationsAsynchronously);
      map.markerStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
      var render = refreshOnly ? map.RefreshMapObjectMarkersAsync() : map.RenderMapAsync();
      await map.markerStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
      map.MapShowEntities.IsChecked = true;
      var change = map.MapObjectLayerOption_Changed(map.MapShowEntities, new());
      map.markerGate.TrySetResult(true);
      await Complete(map, render, change);
      Check(map.VisibleEntity && map.StaleOverlayPublishes == 0, "object layer enabled during marker read was lost or stale markers were published");
    }
    foreach(var show in new[] { true, false }) {
      var map = new Navigation();
      map.MapShowUngenerated.IsChecked = !show;
      map.backendGate = new(TaskCreationOptions.RunContinuationsAsynchronously);
      var render = map.RenderMapAsync();
      var change = show ? map.MapObjectLayersShowAll_Click(map, new()) : map.MapObjectLayersHideAll_Click(map, new());
      map.backendGate.TrySetResult(true);
      await Complete(map, render, change);
      Check(map.RenderedUngenerated == show && map.VisibleEntity == show, "show/hide all during rendering did not apply all layers");
    }
    Console.WriteLine("PASS Windows production layer handlers: first terrain render, both texture directions, full/marker-only late reads, show/hide all (headless render boundaries)");
  }
  public async Task VerifyNavigationRace() {
    foreach(var entityLast in new[] { true, false }) {
      var map = new Navigation();
      map._databaseBusy = true;
      var old = map.LocateChunkOnMapAsync(new(1, 1, 0));
      map.SelectedObjectRow = new(1, 1000, 100, -1000);
      var latest = entityLast ? map.LocateObjectOnMap_Click(map, new()) : map.LocateChunkOnMapAsync(new(10, -10, 1));
      map._databaseBusy = false;
      await Complete(map, old, latest);
      if(entityLast) Check(map.Rendered is { Dimension: 1, X: 1000, Z: -1000 } && map._selectedMapChunk is null && !map.MapDetailText.Contains("(1, 1)"), "obsolete chunk locator overwrote newer entity selection");
      else Check(map.Rendered is { Dimension: 1, X: 168, Z: -152 } && map._selectedMapChunk == new ChunkPosition(10, -10, 1), "obsolete chunk locator overwrote newer chunk selection");
    }
    Console.WriteLine("PASS Windows coalesced navigation: older chunk continuations cannot overwrite latest entity/chunk selection");
  }
  public async Task VerifyDefaultDimension() {
    MapCenterX.Text = "17"; MapCenterZ.Text = "27"; MapCenterY.Text = "63";
    _document!.Position = new(3, 1000, 100, -1000);
    await InitializeLocalPlayerCenterAsync();
    Check(MapDimension.SelectedIndex == 0 && _activeMapDimension == 0 && MapCenterX.Text == "17" && MapCenterZ.Text == "27" && !_mapCenters.ContainsKey(3), "unsupported local-player dimension corrupted spawn fallback");
    foreach(var dimension in new[] { 0, 1, 2 }) {
      HasRenderedMap = false;
      _document.Position = new(dimension, -1000.75, 90.75, 1000.75);
      await InitializeLocalPlayerCenterAsync();
      Check(MapDimension.SelectedIndex == dimension && _activeMapDimension == dimension && MapCenterX.Text == "-1001" && MapCenterZ.Text == "1000" && MapCenterY.Text == "90", "vanilla local-player default center changed");
    }
    Console.WriteLine("PASS Windows local-player default center: custom dimension keeps spawn fallback; all vanilla dimensions retain floor coordinates");
  }
  public async Task Verify() {
    backendGate = new(TaskCreationOptions.RunContinuationsAsynchronously);
    SelectedObjectRow = new(1, 1000, 100, -1000);
    var locate = LocateObjectOnMap_Click(this, new());
    backendGate.TrySetResult(true);
    await backendFinished.Task.WaitAsync(TimeSpan.FromSeconds(3));
    Dispatcher.Drain();
    await locate.WaitAsync(TimeSpan.FromSeconds(3));
    Check(Rendered is { Dimension: 1, X: 1000, Y: 100, Z: -1000 }, "object定位 retained old center");
    _databaseBusy = true;
    MapDimension.SelectedIndex = 2;
    MapCenterX.Text = "200"; MapCenterZ.Text = "-200";
    axis = 2; mode = 3;
    var before = Started;
    RenderMapAfterControlChange();
    RenderMapAfterControlChange();
    _databaseBusy = false;
    Dispatcher.Drain();
    Check(Started == before + 1 && Rendered is { Dimension: 2, X: 200, Z: -200, Axis: 2, Mode: 3 }, "busy control changes were lost or rendered redundantly");
    HasRenderedMap = false;
    _databaseBusy = true;
    MapDimension.SelectedIndex = 1;
    before = Started;
    _databaseBusy = false;
    Dispatcher.Drain();
    Check(Started == before + 1 && Rendered is { Dimension: 1 }, "control change during first render was dropped");
    HasRenderedMap = true;
    var calls = Started;
    SelectedObjectRow = new(3, 1000, 64, 1000);
    await LocateObjectOnMap_Click(this, new());
    await LocateChunkOnMapAsync(new(0, 0, 3));
    Check(Started == calls && MessageBox.Calls >= 2, "custom dimension rendered prior vanilla dimension");
    await LocateChunkOnMapAsync(new(10, -10, 0));
    Check(Rendered is { Dimension: 0, X: 168, Z: -152 }, "chunk locator lost center");
    Console.WriteLine("PASS Windows production navigation/state methods: object/chunk centers, queued latest controls, coalescing and unsupported dimensions (headless render boundary)");
  }
  static void Check(bool value, string message) { if(!value) throw new Exception(message); }
}
class Program { static async Task Main(string[] args) {
  var scenario = args.Length == 0 ? "all" : args[0];
  if(scenario is "all" or "navigation") await new Navigation().Verify();
  if(scenario is "all" or "layers") await new Navigation().VerifyLayers();
  if(scenario is "all" or "navigation-race") await new Navigation().VerifyNavigationRace();
  if(scenario is "all" or "initial-dimension") await new Navigation().VerifyDefaultDimension();
} }
'''
    project = work / "Navigation.csproj"
    project.write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable><NoWarn>CS0169;CS0649;CS0414</NoWarn></PropertyGroup></Project>')
    (work / "Program.cs").write_text(program)
    subprocess.run([shutil.which("dotnet") or "dotnet", "run", "--project", str(project),
                    "-p:UseSharedCompilation=false", "-v:q", "--", scenario], check=True)


with tempfile.TemporaryDirectory(prefix="mcbe-navigation-") as directory:
    work = Path(directory)
    if len(sys.argv) == 1 or sys.argv[1] == "swift":
        swift_test(work)
    if len(sys.argv) == 1 or sys.argv[1] == "windows":
        windows_test(work, sys.argv[2] if len(sys.argv) > 2 else "all")
