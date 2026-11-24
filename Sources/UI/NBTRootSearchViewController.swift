import UIKit

/// Consecutive NBT documents each have their own root. The record number identifies which one.
class NBTRootSearchViewController: NBTSearchTreeViewController {
  var displayedIndices = [Int]()

  override func viewDidLoad() {
    super.viewDidLoad()
    searchController.searchBar.placeholder = "搜索根标签名、标签值或标签类型"
  }

  func showRoots(_ documents: [NBTDocument]) {
    displayedIndices = NBTTreeRows.searchDocuments(documents, query: query)
  }

  func configureRootResult(_ cell: UITableViewCell, index: Int, detail: String) {
    cell.detailTextLabel?.text = query.isEmpty ? detail : "路径：#\(index) /  ·  \(detail)"
    cell.contentView.backgroundColor = isLocated(at: [.list(index)]) ? UIColor.systemYellow.withAlphaComponent(0.32) : nil
  }

  func rootLocationActions(for index: Int) -> [UIAction] {
    searchLocationActions(at: [.list(index)])
  }

  override func visibleRow(at path: [NBTPathComponent]) -> Int? {
    guard path.count == 1, case .list(let index)? = path.first else { return nil }
    return displayedIndices.firstIndex(of: index)
  }
}
