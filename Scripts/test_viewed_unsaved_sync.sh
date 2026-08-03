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
      NBTNamedTag(name: "IntByName", value: .string("value-one")),
      NBTNamedTag(name: "ValueHolder", value: .string("Int appears in value")),
      NBTNamedTag(name: "TypedOnly", value: .int(37)),
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

    // Paths are never searchable, even when the query contains path syntax.
    let pathMatches = NBTTreeRows.search(in: root, query: "/Inventory/Nested/Damage")
    precondition(pathMatches.isEmpty)

    let valueMatches = NBTTreeRows.search(in: root, query: "37")
    precondition(valueMatches.map(\.name) == ["TypedOnly", "PlayerLevel"])

    // Search stops at the first non-empty category: name, then value, then type.
    let priorityMatches = NBTTreeRows.search(in: root, query: "Int")
    precondition(priorityMatches.map(\.name) == ["IntByName"])

    let valueFallback = NBTTreeRows.search(in: root, query: "appears in value")
    precondition(valueFallback.map(\.name) == ["ValueHolder"])

    let typeFallback = NBTTreeRows.search(in: root, query: "Short")
    precondition(typeFallback.map(\.name) == ["Damage"])

    // Container summaries such as Compound{n}/List[n] are not tag values.
    precondition(NBTTreeRows.search(in: root, query: "Compound{1}").isEmpty)

    let roots = [
      NBTDocument(rootName: "IntRoot", root: .string("alpha")),
      NBTDocument(rootName: "Other", root: .string("Int in value")),
      NBTDocument(rootName: "Typed", root: .int(1))
    ]
    precondition(NBTTreeRows.searchDocuments(roots, query: "Int") == [0])
    precondition(NBTTreeRows.searchDocuments(roots, query: "in value") == [1])
    precondition(NBTTreeRows.searchDocuments(roots, query: "Int") != [1, 2])
    precondition(NBTTreeRows.searchDocuments(roots, query: "Long").isEmpty)
    precondition(NBTTreeRows.searchDocuments(roots, query: "0").isEmpty)
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
  EntityBrowserViewController.swift \
  MapSelectionResultsViewController.swift; do
  grep -q 'ViewedItemTracker' "$ROOT/Sources/UI/$file" || {
    echo "error: viewed-state support missing from $file" >&2
    exit 1
  }
  grep -q 'isEnabled: true' "$ROOT/Sources/UI/$file" || {
    echo "error: viewed badge is not enabled in $file" >&2
    exit 1
  }
done

grep -q 'BlockSearchViewedState' "$ROOT/Sources/UI/BlockSearchResultsViewController.swift"
grep -q 'viewedState: viewedState' "$ROOT/Sources/UI/WorldDetailTabBarController.swift"
grep -q 'rememberedBlockSearchViewedState' "$ROOT/Sources/World/WorldSession.swift"
grep -q 'isEnabled: true' "$ROOT/Sources/UI/BlockSearchResultsViewController.swift"

if [[ "$(grep -R -l 'isEnabled: true' "$ROOT/Sources/UI" | wc -l | tr -d ' ')" != "3" ]]; then
  echo "error: viewed badges are enabled outside the three requested lists" >&2
  exit 1
fi

grep -q 'markViewedAfterOpeningEditor(object)' "$ROOT/Sources/UI/EntityBrowserViewController.swift"
grep -q 'markViewedAfterOpeningEditor(object)' "$ROOT/Sources/UI/MapSelectionResultsViewController.swift"
if grep -q 'viewedItems.mark(object.stableID)' <(sed -n '/didSelectRowAt/,/trailingSwipeActions/p' "$ROOT/Sources/UI/EntityBrowserViewController.swift"); then
  echo "error: entity row tap still marks viewed before Edit NBT" >&2
  exit 1
fi

grep -q 'Paths, parent summaries and child contents are never searched' "$ROOT/Sources/UI/NBTNode.swift"
if grep -R -q '搜索名称、路径、类型或值' "$ROOT/Sources/UI"; then
  echo "error: an NBT search field still advertises path search" >&2
  exit 1
fi
grep -q '搜索根标签名、标签值或标签类型' "$ROOT/Sources/UI/StandaloneNBTFileViewController.swift"
grep -q '搜索根标签名、标签值或标签类型' "$ROOT/Sources/UI/MetadataNBTViewControllers.swift"
if grep -q 'String(index) == query' "$ROOT/Sources/UI/StandaloneNBTFileViewController.swift" "$ROOT/Sources/UI/MetadataNBTViewControllers.swift"; then
  echo "error: root NBT search still matches sequence indices" >&2
  exit 1
fi

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
grep -q 'private let session: WorldSession' "$ROOT/Sources/UI/VillageNBTListViewController.swift"
grep -q 'self.session = session' "$ROOT/Sources/UI/VillageNBTListViewController.swift"
grep -q 'object: session' "$ROOT/Sources/UI/VillageNBTListViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/VillageNBTEditorViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/StructureNBTEditorViewController.swift"
grep -q 'WorldSession.worldDidChangeNotification' "$ROOT/Sources/UI/WorldObjectNBTEditorViewController.swift"

echo 'Viewed badges, exact chunk-coordinate search, NBT search filtering, unsaved exit guards and command refresh hooks passed'
