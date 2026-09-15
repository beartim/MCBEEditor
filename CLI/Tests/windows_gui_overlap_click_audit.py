#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source_path = ROOT / "Windows/MCBEEditor.Desktop/MainWindow.xaml.cs"
source = source_path.read_text(encoding="utf-8")
issues = []

def require(condition: bool, message: str) -> None:
    if not condition:
        issues.append(message)

# A point-choice candidate needs separate single-click selection and menu activation.
require("Func<Task>? OpenFromMenu" in source,
        "overlap candidates do not separate normal selection from menu activation")
require("OpenFromMenuAsync" in source,
        "overlap menu has no explicit async activation path")
require("await captured.OpenFromMenuAsync()" in source,
        "context-menu items do not await their full activation action")
require("ordered[0].Select();" in source,
        "single-candidate clicks no longer preserve normal selection semantics")
require(source.count("new MapPointChoiceCandidate") == 5,
        "unexpected overlap candidate type count; audit new/removed candidate kinds")

# Entity / block-entity / player menu items must open the NBT editor, while normal
# single-click selection remains SelectMapObjectRow.
require("() => SelectMapObjectRow(captured)" in source,
        "normal map object selection path disappeared")
require("() => OpenMapObjectNbtFromChoiceAsync(captured)" in source,
        "overlap entity/block-entity/player choice does not open NBT")
require("private async Task OpenMapObjectNbtFromChoiceAsync(WorldObjectRow row)" in source,
        "missing map-object overlap NBT helper")
require("await EditObjectNbtAsync(row);" in source,
        "map-object overlap helper does not invoke the NBT editor")

# Other editable overlay types must not become dead-end selections when overlap
# forces a context menu instead of a direct double click.
require("OpenMapVillageFromChoice" in source,
        "overlap village choice has no full view/edit action")
require("OpenMapSpawnerFromChoice" in source,
        "overlap HardcodedSpawners choice has no full view/edit action")
require("new VillageFeatureNbtWindow" in source,
        "village overlap action no longer reaches village NBT UI")
require("new HardcodedSpawnersEditorWindow" in source,
        "spawner overlap action no longer reaches spawner editor UI")

# Every call site that can raise the overlap menu must continue marking the event
# handled and must route through the one shared chooser implementation.
require(source.count("TryShowMapPointChoice(") == 6,
        "unexpected number of map overlap chooser call sites; audit new/removed click paths")
for handler in (
    "MapImage_MouseLeftButtonUp",
    "MapSpawnFeature_MouseLeftButtonDown",
    "MapSpawnerFeature_MouseLeftButtonDown",
    "MapVillageFeature_MouseLeftButtonDown",
    "MapObjectMarker_MouseLeftButtonDown",
):
    require(handler in source, f"missing audited overlap click handler: {handler}")

if issues:
    print("windows GUI overlap click audit: FAIL")
    for issue in issues:
        print("-", issue)
    raise SystemExit(1)
print("windows GUI overlap click audit: PASS")
