#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/mcbeeditor-viewed-unsaved-sync"
rm -rf "$TMP"
mkdir -p "$TMP"

cat > "$TMP/chunk_main.swift" <<'SWIFT'
import Foundation

@main
struct Main {
  static func main() {
    let zero = ChunkCoordinateSearch.parse("(0,0)")
    precondition(zero?.x == 0 && zero?.z == 0)
    let signed = ChunkCoordinateSearch.parse(" ( -2147483648, 2147483647 ) ")
    precondition(signed?.x == Int32.min && signed?.z == Int32.max)
    precondition(ChunkCoordinateSearch.parse("0,0") == nil)
    precondition(ChunkCoordinateSearch.parse("(0)") == nil)
    precondition(ChunkCoordinateSearch.parse("(2147483648,0)") == nil)
    precondition(ChunkCoordinateSearch.parse("(0,0,0)") == nil)
  }
}
SWIFT
swiftc "$ROOT/Sources/World/ChunkCoordinateSearch.swift" "$TMP/chunk_main.swift" -o "$TMP/chunk_test"
"$TMP/chunk_test"

cat > "$TMP/nbt_main.swift" <<'SWIFT'
import Foundation

@main
struct Main {
  static func main() {
    let root: NBTValue = .compound([
      NBTNamedTag(name: "Inventory", value: .compound([
        NBTNamedTag(name: "Slot", value: .byte(1)),
        NBTNamedTag(name: "Nested", value: .compound([
          NBTNamedTag(name: "Damage", value: .short(2))
        ]))
      ])),
      NBTNamedTag(name: "PlayerLevel", value: .int(37))
    ])

    let nameMatches = NBTTreeRows.search(in: root, query: "Inventory")
    precondition(nameMatches.count == 1)
    precondition(nameMatches[0].pathDescription == "/Inventory")

    let explicitPathMatches = NBTTreeRows.search(in: root, query: "/Inventory/Nested/Damage")
    precondition(explicitPathMatches.count == 1)
    precondition(explicitPathMatches[0].name == "Damage")

    let valueMatches = NBTTreeRows.search(in: root, query: "37")
    precondition(valueMatches.count == 1)
    precondition(valueMatches[0].name == "PlayerLevel")
  }
}
SWIFT
swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/UI/NBTNode.swift" \
  "$TMP/nbt_main.swift" \
  -o "$TMP/nbt_test"
"$TMP/nbt_test"

VIEWED="$ROOT/Sources/UI/ViewedListSupport.swift"
GUARD="$ROOT/Sources/UI/UnsavedNBTExitGuard.swift"
grep -q 'title: "清除此查看"' "$VIEWED"
grep -q 'title: "有未保存的修改"' "$GUARD"
grep -q 'title: "不保存直接退出"' "$GUARD"
grep -q 'title: "保存退出"' "$GUARD"
grep -q 'interactivePopGestureRecognizer?.isEnabled = false' "$GUARD"

for file in \
  ChunkListViewController.swift \
  EntityBrowserViewController.swift \
  MapSelectionResultsViewController.swift \
  BlockSearchResultsViewController.swift \
  PlayerNBTListViewController.swift \
  VillageNBTListViewController.swift \
  StructureNBTListViewController.swift \
  MetadataNBTViewControllers.swift \
  StandaloneNBTFileViewController.swift \
  WorldListViewController.swift \
  WorldToolsViewController.swift; do
  grep -q 'ViewedItemTracker' "$ROOT/Sources/UI/$file" || {
    echo "error: viewed-state support missing from $file" >&2
    exit 1
  }
done

for file in \
  NBTTreeViewController.swift \
  PlayerNBTEditorViewController.swift \
  VillageNBTEditorViewController.swift \
  StructureNBTEditorViewController.swift \
  WorldObjectNBTEditorViewController.swift \
  MetadataNBTViewControllers.swift; do
  grep -q 'UnsavedNBTExitGuard' "$ROOT/Sources/UI/$file" || {
    echo "error: unsaved NBT exit guard missing from $file" >&2
    exit 1
  }
done

grep -q 'ChunkCoordinateSearch.parse(query)' "$ROOT/Sources/UI/ChunkListViewController.swift"
grep -q 'query.hasPrefix("0x")' "$ROOT/Sources/UI/NBTMenuViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/ExperienceEditorViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/TimeEditorViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/WeatherEditorViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/PlayerNBTEditorViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/VillageNBTEditorViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/StructureNBTEditorViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/WorldObjectNBTEditorViewController.swift"

echo 'Viewed badges, exact chunk-coordinate search, NBT search filtering, unsaved exit guards and command refresh hooks passed'
