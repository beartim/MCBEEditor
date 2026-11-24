// UIKit boundary for the portable NBT navigation test. Only the controls touched by navigation are modeled.
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension IndexPath {
  init(row: Int, section: Int) { self.init(indexes: [section, row]) }
  var row: Int { self[1] }
  var section: Int { self[0] }
}

class UIColor {
  static let systemYellow = UIColor()
  func withAlphaComponent(_ alpha: CGFloat) -> UIColor { self }
}
class UIView { var backgroundColor: UIColor? }
class UILabel { var text: String? }
class UITableViewCell { let contentView = UIView(); let detailTextLabel: UILabel? = UILabel() }
class UIImage { init?(systemName: String) {} }
class UIAction {
  let title: String
  let handler: (UIAction) -> Void
  init(title: String, image: UIImage?, handler: @escaping (UIAction) -> Void) {
    self.title = title; self.handler = handler
  }
  func perform() { handler(self) }
}
class UIMenu {
  let title: String
  let children: [UIAction]
  init(title: String, children: [UIAction]) { self.title = title; self.children = children }
}
class UIContextMenuConfiguration {
  let menu: UIMenu?
  init(identifier: NSCopying?, previewProvider: (() -> AnyObject?)?, actionProvider: ([Any]) -> UIMenu?) {
    menu = actionProvider([])
  }
}
protocol UISearchResultsUpdating: AnyObject {
  func updateSearchResults(for searchController: UISearchController)
}
protocol UISearchControllerDelegate: AnyObject {
  func didDismissSearchController(_ searchController: UISearchController)
}
class UISearchBar { var text: String?; var placeholder: String? }
class UISearchController {
  init(searchResultsController: AnyObject?) {}
  let searchBar = UISearchBar()
  weak var searchResultsUpdater: UISearchResultsUpdating?
  weak var delegate: UISearchControllerDelegate?
  var obscuresBackgroundDuringPresentation = true
  var isActive = false
}
class UINavigationItem {
  var searchController: UISearchController?
  var hidesSearchBarWhenScrolling = true
}
class UITableView {
  enum ScrollPosition { case middle }
  var rowHeight: CGFloat = 44
  var scrolled: IndexPath?
  func reloadData() {}
  func layoutIfNeeded() {}
  func scrollToRow(at indexPath: IndexPath, at position: ScrollPosition, animated: Bool) { scrolled = indexPath }
}
class UITableViewController {
  let tableView = UITableView()
  let navigationItem = UINavigationItem()
  var definesPresentationContext = false
  func viewDidLoad() {}
  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { tableView.rowHeight }
  func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
                 point: CGPoint) -> UIContextMenuConfiguration? { nil }
}

private final class Tree: NBTSearchTreeViewController {
  var document: NBTDocument { didSet { invalidateSearchLocation() } }
  init(_ root: NBTValue) { document = NBTDocument(rootName: "Health", root: root); super.init() }
  override var nbtSection: Int { 1 } // Dwellers has resident options in section zero.
  override func rebuildRows() { rows = NBTTreeRows.rows(in: document, expanded: expanded, query: query) }
  func search(_ text: String) {
    searchController.isActive = true
    searchController.searchBar.text = text
    searchController.searchResultsUpdater?.updateSearchResults(for: searchController)
  }
  func locateAction(row: Int) -> UIAction {
    let menu = tableView(tableView, contextMenuConfigurationForRowAt: IndexPath(row: row, section: nbtSection), point: .zero)
    let actions = menu?.menu?.children ?? []
    precondition(actions.map(\.title) == ["定位到此标签"])
    return actions[0]
  }
}

private final class Roots: NBTRootSearchViewController {
  let documents = [NBTDocument(rootName: "one", root: .int(17)), NBTDocument(rootName: "two", root: .int(17))]
  override func rebuildRows() { showRoots(documents) }
}

@main
struct NBTNavigationTests {
  static func main() {
    let root: NBTValue = .compound([
      NBTNamedTag(name: "Bag", value: .list(.compound, [
        .compound([NBTNamedTag(name: "Name", value: .string("first"))]),
        .compound([NBTNamedTag(name: "Name", value: .string("second")),
                   NBTNamedTag(name: "Name", value: .string("third"))])
      ])),
      NBTNamedTag(name: "Other", value: .compound([NBTNamedTag(name: "Name", value: .int(1))]))
    ])
    let tree = Tree(root)
    tree.viewDidLoad()
    let unrelated: [NBTPathComponent] = [.compound("Other")]
    tree.expanded.insert(unrelated)
    tree.search("Name")
    precondition(tree.rows.map(\.value.summary) == ["first", "second", "third", "1"])
    let target = tree.rows[2]
    precondition(tree.tableView(tree.tableView, heightForRowAt: IndexPath(row: 0, section: 1)) >= 60)
    precondition(tree.tableView(tree.tableView, contextMenuConfigurationForRowAt: IndexPath(row: 0, section: 0),
                                point: .zero) == nil)
    tree.locateAction(row: 2).perform()
    let row = tree.tableView.scrolled!
    precondition(row.section == 1 && tree.rows[row.row].path == target.path && tree.query.isEmpty)
    precondition(tree.rows.filter(tree.isLocated).map(\.value.summary) == ["third"])
    precondition(tree.expanded.contains(unrelated) && !tree.expanded.contains([.compound("Bag"), .list(0)]))
    precondition(!tree.searchController.isActive && tree.searchLocationActions(for: target).isEmpty)
    tree.tableView.scrolled = nil
    tree.searchController.delegate?.didDismissSearchController(tree.searchController)
    precondition(tree.tableView.scrolled == row)
    tree.search("Bag")
    let container = tree.rows[0]
    tree.revealSearchNode(container, expandingTarget: true)
    precondition(tree.expanded.contains(container.path) && tree.isLocated(container))
    tree.search("Name")
    let stale = tree.locateAction(row: 2)
    tree.document = NBTDocument(rootName: "Health", root: .int(17))
    tree.rebuildRows()
    stale.perform()
    precondition(tree.query == "name" && tree.searchController.isActive)
    tree.search("17")
    tree.locateAction(row: 0).perform()
    precondition(tree.tableView.scrolled?.row == 0 && tree.rows[0].path.isEmpty && tree.isLocated(tree.rows[0]))

    let roots = Roots()
    roots.viewDidLoad()
    roots.searchController.searchBar.text = "two"
    roots.updateSearchResults(for: roots.searchController)
    let cell = UITableViewCell()
    roots.configureRootResult(cell, index: 1, detail: "Int")
    precondition(cell.detailTextLabel?.text == "路径：#1 /  ·  Int")
    let action = roots.rootLocationActions(for: roots.displayedIndices[0]).first!
    action.perform()
    roots.updateSearchResults(for: roots.searchController)
    roots.didDismissSearchController(roots.searchController)
    roots.configureRootResult(cell, index: 1, detail: "Int")
    precondition(roots.tableView.scrolled?.row == 1 && cell.contentView.backgroundColor != nil)
    roots.configureRootResult(cell, index: 0, detail: "Int")
    precondition(cell.contentView.backgroundColor == nil)
    roots.searchController.searchBar.text = "two"
    roots.updateSearchResults(for: roots.searchController)
    let oldRoot = roots.rootLocationActions(for: 1).first!
    roots.invalidateSearchLocation()
    oldRoot.perform()
    precondition(roots.query == "two")
    print("PASS NBT long-press navigation, exact highlight, section offsets, stale actions, scalar and consecutive roots")
  }
}
