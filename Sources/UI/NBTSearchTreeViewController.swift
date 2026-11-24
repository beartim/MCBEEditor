import UIKit

/// Shared navigation between filtered NBT matches and the editable or read-only tree.
class NBTSearchTreeViewController: UITableViewController, UISearchResultsUpdating, UISearchControllerDelegate {
  var rows = [NBTNode]()
  var expanded = Set<[NBTPathComponent]>()
  let searchController = UISearchController(searchResultsController: nil)
  var nbtSection: Int { 0 }

  private var locatedPath: [NBTPathComponent]?
  private var documentRevision = 0

  var query: String {
    searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    searchController.searchResultsUpdater = self
    searchController.delegate = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "搜索标签名、标签值或标签类型"
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true
  }

  func rebuildRows() { preconditionFailure("NBT tree subclasses must implement rebuildRows()") }

  func updateSearchResults(for searchController: UISearchController) {
    if !query.isEmpty { locatedPath = nil }
    rebuildRows()
  }

  func invalidateSearchLocation() {
    documentRevision += 1
    locatedPath = nil
  }

  func isLocated(_ node: NBTNode) -> Bool { isLocated(at: node.path) }

  func isLocated(at path: [NBTPathComponent]) -> Bool { locatedPath == path && query.isEmpty }

  func searchLocationActions(for node: NBTNode) -> [UIAction] {
    searchLocationActions(at: node.path)
  }

  func searchLocationActions(at path: [NBTPathComponent]) -> [UIAction] {
    let resultQuery = query
    guard !resultQuery.isEmpty else { return [] }
    let revision = documentRevision
    return [UIAction(title: "定位到此标签", image: UIImage(systemName: "scope")) { [weak self] _ in
      guard let self = self, self.documentRevision == revision, self.query == resultQuery else { return }
      self.revealSearchPath(path)
    }]
  }

  func revealSearchNode(_ node: NBTNode, expandingTarget: Bool = false) {
    if expandingTarget && node.hasChildren { expanded.insert(node.path) }
    revealSearchPath(node.path)
  }

  private func revealSearchPath(_ path: [NBTPathComponent]) {
    for length in path.indices { expanded.insert(Array(path.prefix(length))) }
    locatedPath = path
    searchController.searchBar.text = ""
    searchController.isActive = false
    rebuildRows()
    scrollToLocatedTag()
  }

  func didDismissSearchController(_ searchController: UISearchController) {
    // UIKit can restore the old content offset at the end of search dismissal.
    scrollToLocatedTag()
  }

  func visibleRow(at path: [NBTPathComponent]) -> Int? {
    rows.firstIndex { $0.path == path }
  }

  private func scrollToLocatedTag() {
    guard query.isEmpty, let path = locatedPath,
      let row = visibleRow(at: path)
    else { return }
    tableView.layoutIfNeeded()
    tableView.scrollToRow(at: IndexPath(row: row, section: nbtSection), at: .middle, animated: false)
  }

  override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    if indexPath.section == nbtSection && !query.isEmpty { return 64 }
    return tableView.rowHeight
  }

  // Read-only trees offer just the navigation action. Editors also include their editing actions.
  override func tableView(
    _ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard indexPath.section == nbtSection, rows.indices.contains(indexPath.row) else { return nil }
    let node = rows[indexPath.row]
    let actions = searchLocationActions(for: node)
    guard !actions.isEmpty else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
      UIMenu(title: node.pathDescription, children: actions)
    }
  }
}
