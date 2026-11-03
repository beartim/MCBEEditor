#!/usr/bin/env python3
"""Run real list callbacks and editor init/save/delete with real Bedrock storage.

Linux has no UIKit. Presentation controls are substituted, and only the editor
members needed for this navigation/save flow are compiled from its actual source.
The entire map/resident list classes, scanner, NBT store and codecs are real.
This is an executable state-flow regression, not an iOS device UI test.
"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def member(source: str, marker: str) -> str:
    start = source.index(marker)
    opening = source.index("{", start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor].replace("private ", "").replace("@objc ", "")


UI = r'''
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
enum TableStyle { case insetGrouped }
enum CellStyle { case subtitle }
enum AlertStyle { case actionSheet, alert }
enum ActionStyle { case `default`, cancel, destructive }
enum Color { case secondaryLabel }
class UIView {}
class UIViewController {
    var title: String?
    var navigationItem = NavigationItem()
    var navigationController: UINavigationController?
    var definesPresentationContext = false
    var presented: UIViewController?
    var errors = [String]()
    func viewDidLoad() {}
    func present(_ vc: UIViewController, animated: Bool) { presented = vc }
    func showError(_ error: Error, title: String) { errors.append(title + ": " + error.localizedDescription) }
}
class UINavigationController {
    var top: UIViewController?
    func pushViewController(_ vc: UIViewController, animated: Bool) { top = vc; vc.navigationController = self }
    func popViewController(animated: Bool) { top = nil }
}
class NavigationItem {
    var prompt: String?
    var searchController: UISearchController?
    var hidesSearchBarWhenScrolling = false
    var rightBarButtonItems: [BarItem]?
}
class BarItem { var isEnabled = true }
class UITableView: UIView {
    var isUserInteractionEnabled = true
    func reloadData() {}
    func reloadRows(at: [IndexPath], with: RowAnimation) {}
    enum RowAnimation { case none }
    func dequeueReusableCell(withIdentifier: String) -> UITableViewCell? { nil }
    func deselectRow(at: IndexPath, animated: Bool) {}
    func rectForRow(at: IndexPath) -> CGRect { .zero }
}
class UITableViewController: UIViewController {
    let tableView = UITableView()
    init(style: TableStyle) { super.init() }
    required init?(coder: NSCoder) { fatalError() }
    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { fatalError() }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
}
class Label { var text: String?; var numberOfLines = 1; var textColor: Color? }
class ImageView { var image: UIImage? }
class UIImage { init?(systemName: String) {} }
class UITableViewCell {
    var textLabel: Label? = Label()
    var detailTextLabel: Label? = Label()
    var imageView: ImageView? = ImageView()
    var viewed = false
    init(style: CellStyle, reuseIdentifier: String) {}
    func mcbe_enableCompactText() {}
}
protocol UISearchResultsUpdating { func updateSearchResults(for searchController: UISearchController) }
class SearchBar { var text: String?; var placeholder: String? }
class UISearchController: UIViewController {
    var searchResultsUpdater: UISearchResultsUpdating?
    var obscuresBackgroundDuringPresentation = false
    var searchBar = SearchBar()
    init(searchResultsController: UIViewController?) { super.init() }
}
class UIAlertAction {
    let title: String?
    let handler: ((UIAlertAction) -> Void)?
    init(title: String?, style: ActionStyle, handler: ((UIAlertAction) -> Void)? = nil) { self.title = title; self.handler = handler }
}
class Popover { var sourceView: UIView?; var sourceRect = CGRect.zero }
class UIAlertController: UIViewController {
    var actions = [UIAlertAction]()
    var popoverPresentationController: Popover? = Popover()
    init(title: String?, message: String?, preferredStyle: AlertStyle) { super.init(); self.title = title }
    func addAction(_ action: UIAlertAction) { actions.append(action) }
}
class UIPasteboard { static let general = UIPasteboard(); var string: String? }
extension IndexPath {
    init(row: Int, section: Int) { self.init(indexes: [section, row]) }
    var section: Int { self[0] }
    var row: Int { self[1] }
}
enum ViewedListSupport {
    static func configure(cell: UITableViewCell, isEnabled: Bool = false, isViewed: Bool, showsDisclosure: Bool = true, clearAction: @escaping () -> Void) { cell.viewed = isEnabled && isViewed }
    static func presentClearConfirmation(from: UIViewController, completion: @escaping () -> Void) { completion() }
}
enum VillageResidentEntityKind { case villager; var displayName: String { "村民" }; var iconName: String { "person.fill" } }
// An unmodified source archive exposes raw objects; the fixed list uses rows.
// This test-only adapter lets the same behavioral assertions run against both.
extension BedrockWorldObject { var object: BedrockWorldObject { self } }
'''

TEST = r'''
import Foundation
@main
struct EntityEditorReopenRegression {
    static var failures = [String]()
    static func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message); print("FAIL: " + message) }
    }
    static func doc(_ id: Int64?, x: Float = 1, dimension: Int32 = 0, marker: String = "initial", block: Bool = false) -> NBTDocument {
        var tags = [NBTNamedTag(name: block ? "id" : "identifier", value: .string(block ? "Chest" : "minecraft:pig")),
                    NBTNamedTag(name: "DimensionId", value: .int(dimension)),
                    NBTNamedTag(name: "CustomName", value: .string(marker)),
                    NBTNamedTag(name: "Nested", value: .compound([NBTNamedTag(name: "Value", value: .string(marker))]))]
        if block { tags += [NBTNamedTag(name: "x", value: .int(Int32(x))), NBTNamedTag(name: "y", value: .int(64)), NBTNamedTag(name: "z", value: .int(1))] }
        else { tags.append(NBTNamedTag(name: "Pos", value: .list(.float, [.float(x), .float(64), .float(1)]))) }
        if let id = id { tags.append(NBTNamedTag(name: "UniqueID", value: .long(id))) }
        return NBTDocument(rootName: "", root: .compound(tags))
    }
    static func key(_ text: String, _ id: Int64) -> Data {
        var data = Data(text.utf8)
        let bits = UInt64(bitPattern: id)
        for shift in stride(from: 0, through: 56, by: 8) { data.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        return data
    }
    static func fixture(_ source: BedrockWorldObjectSource) throws -> (WorldSession, [BedrockWorldObject]) {
        let db = MojangLevelDB(values: [:])
        if source == .modernActor {
            let actor = key("actorprefix", 800)
            let digp = Data("digp".utf8) + Data(repeating: 0, count: 8)
            db.values[actor] = try BedrockNBTCodec.encode(doc(101))
            db.values[digp] = key("", 800)
        } else {
            var recordKey = Data(repeating: 0, count: 8)
            recordKey.append(source == .blockEntity ? 0x31 : 0x32)
            db.values[recordKey] = try BedrockNBTCodec.encode(doc(source == .blockEntity ? nil : 101, block: source == .blockEntity))
                + BedrockNBTCodec.encode(doc(source == .blockEntity ? nil : 102, x: 2, marker: "sibling", block: source == .blockEntity))
        }
        let objects = try BedrockWorldObjectScanner(database: db).scanRegion(centerX: 0, centerZ: 0, dimension: 0, radius: 0, includeEntities: true, includeBlockEntities: true).objects
        return (WorldSession(db: db), objects)
    }
    static func action(_ title: String, on owner: UIViewController) {
        guard let alert = owner.presented as? UIAlertController,
              let item = alert.actions.first(where: { $0.title == title }) else { fatalError("Missing real UI action: " + title) }
        item.handler?(item)
    }
    static func open(_ list: MapSelectionResultsViewController, nav: UINavigationController, section: Int, row: Int = 0) -> WorldObjectNBTEditorViewController? {
        list.tableView(list.tableView, didSelectRowAt: IndexPath(row: row, section: section))
        action("编辑 NBT", on: list)
        return nav.top as? WorldObjectNBTEditorViewController
    }
    static func save(_ editor: WorldObjectNBTEditorViewController, _ edited: NBTDocument) -> Bool {
        editor.document = edited; editor.dirty = true; return editor.performSave()
    }
    static func same(_ a: NBTDocument, _ b: NBTDocument) throws -> Bool {
        try BedrockNBTCodec.encode(a) == BedrockNBTCodec.encode(b)
    }
    static func scenario(_ name: String, _ body: () throws -> Void) {
        do { try body() } catch { failures.append(name + ": " + error.localizedDescription); print("FAIL: " + name + ": " + error.localizedDescription) }
    }
    static func main() throws {
        for source in [BedrockWorldObjectSource.modernActor, .legacyChunkEntity, .blockEntity] {
            scenario(source.rawValue) {
                let (session, objects) = try fixture(source)
                let original = objects.first(where: { $0.customName == "initial" })!
                let nav = UINavigationController()
                let list = MapSelectionResultsViewController(session: session, objects: objects, boundsText: "X=0…15 Z=0…15", onSelect: { _ in }, onLocate: { _ in })
                list.navigationController = nav; list.viewDidLoad()
                let section = source == .blockEntity ? 1 : 0
                let first = open(list, nav: nav, section: section)!
                let firstDoc = doc(source == .blockEntity ? nil : 101, marker: "saved-once", block: source == .blockEntity)
                check(save(first, firstDoc), "\(source): first Save failed")
                check(try same(BedrockWorldObjectNBTStore(session: session).document(for: original), firstDoc), "\(source): storage did not commit first edit")
                nav.top = nil
                let second = open(list, nav: nav, section: section)!
                check(try same(second.document, firstDoc), "\(source): reopening a viewed row shows the initial NBT")
                check(list.objects.first?.object.customName == "saved-once", "\(source): list metadata stayed at initial NBT")

                // Keep this editor open through two moves: callback identity must
                // advance on every Save, not capture only the first row identity.
                for (id, x, dim, marker) in [(Int64(201), Float(17), Int32(0), "moved-once"), (202, -17, 2, "moved-twice")] {
                    let edited = doc(source == .blockEntity ? nil : id, x: x, dimension: dim, marker: marker, block: source == .blockEntity)
                    check(save(second, edited), "\(source): repeated Save failed")
                    check(list.objects.first?.object.customName == marker && list.objects.first?.object.dimension == dim && list.objects.first?.object.position?.x == Double(x), "\(source): Save did not publish latest location/metadata")
                }
                nav.top = nil
                guard let reopened = open(list, nav: nav, section: section) else { check(false, "\(source): moved entity cannot reopen"); return }
                let finalDoc = doc(source == .blockEntity ? nil : 202, x: -17, dimension: 2, marker: "moved-twice", block: source == .blockEntity)
                check(try same(reopened.document, finalDoc), "\(source): moved NBT was not retained")
                let cell = list.tableView(list.tableView, cellForRowAt: IndexPath(row: 0, section: section))
                check(cell.viewed, "\(source): saved row lost its viewed state")
                check(cell.textLabel?.text == "moved-twice", "\(source): row title is stale")

                // A failed write must not replace the valid row/document.
                if source != .blockEntity {
                    let before = session.db.values
                    check(!save(reopened, doc(0, x: -17, dimension: 2, marker: "invalid")), "\(source): invalid UniqueID was accepted")
                    check(before == session.db.values && list.objects.first?.object.customName == "moved-twice", "\(source): failed Save changed the list or database")
                    reopened.dirty = false
                }
                // Active search is reapplied using the newly committed metadata.
                list.searchController.searchBar.text = "moved-twice"; list.updateSearchResults(for: list.searchController)
                let renamed = doc(source == .blockEntity ? nil : 202, x: -17, dimension: 2, marker: "renamed", block: source == .blockEntity)
                check(save(reopened, renamed), "\(source): searched Save failed")
                check(list.tableView(list.tableView, numberOfRowsInSection: section) == 0, "\(source): search retained a row that no longer matches")
                list.searchController.searchBar.text = ""; list.updateSearchResults(for: list.searchController)
                if objects.count > 1 {
                    let sibling = objects.first(where: { $0.customName == "sibling" })!
                    let siblingIndex = list.objects(in: section).firstIndex(where: { $0.object.customName == "sibling" })!
                    let siblingEditor = open(list, nav: nav, section: section, row: siblingIndex)!
                    check(try same(siblingEditor.document, sibling.document), "\(source): sibling record changed or wrong root opened after index shift")
                    check(try same(BedrockWorldObjectNBTStore(session: session).document(for: sibling), sibling.document), "\(source): sibling bytes changed")
                }
                reopened.confirmDeleteObject(); action("删除", on: reopened)
                check(list.objects.allSatisfy { $0.object.customName != "renamed" }, "\(source): deleted row remains reopenable")
            }
        }
        scenario("fresh read and failed read") {
            let (session, objects) = try fixture(.modernActor)
            let original = objects[0]
            let latest = doc(101, marker: "external-latest")
            _ = try BedrockWorldObjectNBTStore(session: session).save(object: original, document: latest)
            let before = session.db.values
            let nav = UINavigationController()
            let list = MapSelectionResultsViewController(session: session, objects: objects, boundsText: "fixture", onSelect: { _ in }, onLocate: { _ in })
            list.navigationController = nav; list.viewDidLoad()
            let fresh = open(list, nav: nav, section: 0)!
            check(try same(fresh.document, latest), "opening an old snapshot did not read the current persisted NBT")
            check(before == session.db.values, "opening NBT unexpectedly wrote database records")
            nav.top = nil
            session.db.values.removeValue(forKey: original.storage.primaryKey)
            _ = open(list, nav: nav, section: 0)
            check(nav.top == nil && !list.errors.isEmpty, "missing record opened an editable stale snapshot")
        }
        scenario("resident snapshot list") {
            let (session, objects) = try fixture(.modernActor)
            let nav = UINavigationController()
            let list = VillageResidentEntitiesViewController(session: session, objects: objects, residentKind: .villager)
            list.navigationController = nav; list.viewDidLoad()
            list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 0, section: 0)); action("编辑 NBT", on: list)
            let editor = nav.top as! WorldObjectNBTEditorViewController
            let edited = doc(303, x: 33, dimension: 1, marker: "resident-saved")
            check(save(editor, edited), "resident save failed")
            nav.top = nil
            list.tableView(list.tableView, didSelectRowAt: IndexPath(row: 0, section: 0)); action("编辑 NBT", on: list)
            check((nav.top as? WorldObjectNBTEditorViewController)?.object.customName == "resident-saved", "resident list kept the original object identity")
            check(try same((nav.top as! WorldObjectNBTEditorViewController).document, edited), "resident list reopened stale NBT")
        }
        for resident in [false, true] {
            for moveFirst in [false, true] {
                scenario("three-root index shifts, resident=\(resident), move=\(moveFirst)") {
                    let (session, initial) = try fixture(.legacyChunkEntity)
                    let recordKey = initial[0].storage.primaryKey
                    session.db.values[recordKey] = try BedrockNBTCodec.encode(doc(101, marker: "A"))
                        + BedrockNBTCodec.encode(doc(102, x: 2, marker: "B"))
                        + BedrockNBTCodec.encode(doc(103, x: 3, marker: "C"))
                    let objects = try BedrockWorldObjectScanner(database: session.db).scanRegion(centerX: 0, centerZ: 0, dimension: 0, radius: 0, includeEntities: true, includeBlockEntities: true).objects
                    let nav = UINavigationController()
                    let map = MapSelectionResultsViewController(session: session, objects: objects, boundsText: "three-root", onSelect: { _ in }, onLocate: { _ in })
                    let residents = VillageResidentEntitiesViewController(session: session, objects: objects, residentKind: .villager)
                    let owner: UITableViewController = resident ? residents : map
                    owner.navigationController = nav; owner.viewDidLoad()
                    func rows() -> [BedrockWorldObject] { resident ? residents.shownObjects.map(\.object) : map.objects(in: 0).map(\.object) }
                    func openID(_ id: Int64) -> WorldObjectNBTEditorViewController {
                        let index = rows().firstIndex(where: { $0.uniqueID == id })!
                        owner.tableView(owner.tableView, didSelectRowAt: IndexPath(row: index, section: 0))
                        action("编辑 NBT", on: owner)
                        return nav.top as! WorldObjectNBTEditorViewController
                    }
                    let a = openID(101)
                    if moveFirst { check(save(a, doc(101, x: 17, marker: "A-moved")), "three-root: first root move failed") }
                    else { a.confirmDeleteObject(); action("删除", on: a) }
                    let c = openID(103)
                    check(save(c, doc(103, x: 3, marker: "C-first")), "three-root: first C Save failed")
                    if !resident {
                        let bIndex = rows().firstIndex(where: { $0.uniqueID == 102 })!
                        let bCell = map.tableView(map.tableView, cellForRowAt: IndexPath(row: bIndex, section: 0))
                        check(!bCell.viewed, "three-root: unviewed B inherited C's viewed badge after index shift")
                    }
                    check(save(c, doc(103, x: 3, marker: "C-second")), "three-root: second C Save failed")
                    check(rows().filter { $0.uniqueID == 102 }.count == 1 && rows().filter { $0.uniqueID == 103 }.count == 1,
                          "three-root: repeated Save replaced sibling B with duplicate C")
                    let persisted = try ConsecutiveNBTCodec.decode(session.db.values[recordKey]!).map { $0.document.root.int64Value(namedAny: ["UniqueID"])! }
                    check(persisted == [102, 103], "three-root: persisted siblings were changed")
                    c.confirmDeleteObject(); action("删除", on: c)
                    check(rows().filter { $0.uniqueID == 102 }.count == 1 && rows().allSatisfy { $0.uniqueID != 103 },
                          "three-root: delete callback removed a different row or left stale C")
                    if rows().contains(where: { $0.uniqueID == 102 }) {
                        let b = openID(102)
                        check(try same(b.document, doc(102, x: 2, marker: "B")), "three-root: retained sibling opens the wrong NBT")
                    }
                }
            }
        }
        scenario("committed but ambiguous rebind") {
            let (session, initial) = try fixture(.legacyChunkEntity)
            let recordKey = initial[0].storage.primaryKey
            let first = doc(101, marker: "initial")
            let peer = doc(101, x: 2, marker: "peer")
            // Pre-existing duplicate IDs are readable by their exact root/index.
            // Saving an identical second root cannot be uniquely rebound.
            session.db.values[recordKey] = try BedrockNBTCodec.encode(first) + BedrockNBTCodec.encode(peer)
            let objects = try BedrockWorldObjectScanner(database: session.db).scanRegion(centerX: 0, centerZ: 0, dimension: 0, radius: 0, includeEntities: true, includeBlockEntities: false).objects
            let nav = UINavigationController()
            let list = MapSelectionResultsViewController(session: session, objects: objects, boundsText: "ambiguous", onSelect: { _ in }, onLocate: { _ in })
            list.navigationController = nav; list.viewDidLoad()
            let index = objects.firstIndex(where: { $0.customName == "initial" })!
            let editor = open(list, nav: nav, section: 0, row: index)!
            check(save(editor, peer), "committed rebind failure was reported as a failed write")
            check(!editor.dirty && !editor.tableView.isUserInteractionEnabled, "ambiguous committed save still permits stale editing")
            check(list.objects.count == 1 && list.objects[0].object.customName == "peer", "ambiguous committed row was not removed independently of its sibling")
            let records = try ConsecutiveNBTCodec.decode(session.db.values[recordKey]!)
            check(records.count == 2 && records.allSatisfy { $0.document.root.stringValue(namedAny: ["CustomName"]) == "peer" }, "ambiguous committed save lost or altered a persisted root")
        }
        if !failures.isEmpty { fatalError("Entity editor reopen: \(failures.count) failures:\n" + failures.joined(separator: "\n")) }
        print("PASS: real map/resident callbacks, Save/back/reopen/Save, actor/legacy/block NBT, moves/UniqueID, three-root index shifts, independent viewed badges/search, deletion and failed reads/saves")
    }
}
'''


def run(root: Path) -> None:
    swiftc = shutil.which("swiftc")
    if not swiftc:
        raise SystemExit("Swift compiler is required for entity NBT reopen regression")
    runner = (root / "Scripts/run_core_tests.sh").read_text()
    fixture = runner.split('cat > "$TMP/WorldObjectNBTStoreStubs.swift" <<\'SWIFT\'\n', 1)[1].split("\nSWIFT", 1)[0]
    fixture = fixture.replace("func database() throws -> MojangLevelDB { db }", "func database() throws -> MojangLevelDB { db }\n    func invalidateAfterExternalChange() {}")
    editor = (root / "Sources/UI/WorldObjectNBTEditorViewController.swift").read_text()
    fields = editor[editor.index("  private var object:"):editor.index("  private var rows")].replace("private ", "")
    init_marker = re.search(r"  init\(\s*object:", editor).group(0)
    editor_members = "\n".join(member(editor, text) for text in [init_marker, "  required init?(coder:", "  private func performSave(", "  @objc private func confirmDeleteObject("])
    editor_class = "final class WorldObjectNBTEditorViewController: UITableViewController {\n" + fields + "\n var dirty = false\n func rebuildRows() {}\n" + editor_members + "\n}\n"
    tracker = member((root / "Sources/UI/ViewedListSupport.swift").read_text(), "final class ViewedItemTracker")
    lists = "\n".join((root / ("Sources/UI/" + name + ".swift")).read_text().replace("import UIKit", "").replace("private ", "") for name in ["MapSelectionResultsViewController", "VillageResidentEntitiesViewController"])
    # Reuse the production-core source list already maintained by the full suite.
    command = runner[:runner.index('"$TMP/world-object-nbt-tests"\n')].rsplit("\nswiftc \\\n", 1)[1]
    files = [root / p for p in re.findall(r'"\$ROOT/([^"]+)"', command)]
    with tempfile.TemporaryDirectory(prefix="mcbe-entity-reopen-") as directory:
        temp = Path(directory)
        row_source = root / "Sources/UI/WorldObjectListItem.swift"
        rows = row_source.read_text() if row_source.is_file() else ""
        imports = "import Foundation\n#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif\n"
        generated = {"fixture.swift": fixture, "ui.swift": UI, "controllers.swift": imports + rows + tracker + "\n" + editor_class + lists, "regression.swift": TEST}
        for name, content in generated.items():
            (temp / name).write_text(content)
        output = temp / "entity-editor-reopen"
        subprocess.run([swiftc, *map(str, files), *(str(temp / name) for name in generated), "-parse-as-library", "-o", str(output)], check=True)
        subprocess.run([str(output)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help="Source root; allows proving the same regression against an unmodified archive")
    run(parser.parse_args().root.resolve())
