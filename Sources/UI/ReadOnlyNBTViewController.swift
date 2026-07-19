import UIKit

final class ReadOnlyNBTViewController: UITableViewController, UISearchResultsUpdating {
  private let document: NBTDocument
  private let rawData: Data
  private let exportFilename: String
  private var rows = [NBTNode]()
  private var expanded = Set<[NBTPathComponent]>()
  private let searchController = UISearchController(searchResultsController: nil)

  init(title: String, document: NBTDocument, rawData: Data, exportFilename: String? = nil) {
    self.document = document
    self.rawData = rawData
    self.exportFilename = exportFilename ?? "mcbeeditor-nbt-\(UUID().uuidString.prefix(8)).bin"
    super.init(style: .insetGrouped)
    self.title = title
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    searchController.searchResultsUpdater = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "搜索名称、路径、类型或值"
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .action,
      target: self,
      action: #selector(shareRawData)
    )
    expanded.insert([])
    rebuildRows()
  }

  func updateSearchResults(for searchController: UISearchController) { rebuildRows() }

  private var query: String {
    searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      ?? ""
  }

  private func rebuildRows() {
    if query.isEmpty {
      rows = NBTTreeRows.visibleChildren(of: document.root, expanded: expanded)
      navigationItem.prompt = "只读 NBT；点按标量可复制"
    } else {
      rows = NBTTreeRows.search(in: document.root, query: query)
      navigationItem.prompt = "找到 \(rows.count) 个节点"
    }
    tableView.reloadData()
  }

  override func numberOfSections(in tableView: UITableView) -> Int { 1 }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    rows.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let node = rows[indexPath.row]
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "ReadOnlyNBTCell")
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ReadOnlyNBTCell")
    cell.indentationLevel = query.isEmpty ? node.depth : 0
    cell.indentationWidth = 18
    cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    cell.detailTextLabel?.textColor = .secondaryLabel
    cell.detailTextLabel?.numberOfLines = query.isEmpty ? 1 : 2
    let marker = node.hasChildren ? (expanded.contains(node.path) ? "▾" : "▸") : " "
    cell.imageView?.image = NBTTagIcon.image(for: node.value.type)
    cell.imageView?.contentMode = .center
    cell.textLabel?.text = "\(marker) \(node.name)  <\(node.value.type.displayName)>"
    cell.detailTextLabel?.text =
      query.isEmpty ? node.value.summary : "\(node.value.summary)\n\(node.pathDescription)"
    cell.accessoryType = node.hasChildren ? .none : .disclosureIndicator
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let node = rows[indexPath.row]
    if node.hasChildren {
      if expanded.contains(node.path) {
        expanded.remove(node.path)
      } else {
        expanded.insert(node.path)
      }
      rebuildRows()
      return
    }
    let text = "\(node.pathDescription)\n\(node.value.type.displayName)\n\(node.value.summary)"
    let alert = UIAlertController(title: node.name, message: text, preferredStyle: .actionSheet)
    alert.addAction(
      UIAlertAction(title: "复制值", style: .default) { _ in
        UIPasteboard.general.string = node.value.summary
      })
    alert.addAction(
      UIAlertAction(title: "复制路径和值", style: .default) { _ in UIPasteboard.general.string = text })
    alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = tableView
      popover.sourceRect = tableView.rectForRow(at: indexPath)
    }
    present(alert, animated: true)
  }

  @objc private func shareRawData() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFilename)
    do {
      try rawData.write(to: url, options: .atomic)
      let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
      present(activity, animated: true)
    } catch {
      showError(error, title: "导出 NBT 原始数据失败")
    }
  }
}
