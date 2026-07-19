import UIKit

final class StandaloneNBTEditorViewController: UITableViewController, UISearchResultsUpdating {
  private var document: NBTDocument
  private let displayTitle: String
  private let onCommit: (NBTDocument) -> Void
  private var rows = [NBTNode]()
  private var expanded = Set<[NBTPathComponent]>()
  private var dirty = false
  private let searchController = UISearchController(searchResultsController: nil)
  private lazy var batchSelectionCoordinator = NBTBatchSelectionCoordinator(delegate: self)

  init(document: NBTDocument, title: String, onCommit: @escaping (NBTDocument) -> Void) {
    self.document = document
    self.displayTitle = title
    self.onCommit = onCommit
    super.init(style: .insetGrouped)
    self.title = title
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.interactivePopGestureRecognizer?.isEnabled = false
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    navigationController?.interactivePopGestureRecognizer?.isEnabled = true
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    searchController.searchResultsUpdater = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "搜索名称、路径、类型或值"
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true
    configureNavigationItems()
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "返回",
      style: .plain,
      target: self,
      action: #selector(closeEditor)
    )
    expanded.insert([])
    rebuildRows()
  }

  private func configureNavigationItems() {
    guard !batchSelectionCoordinator.isActive else { return }
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(commitChanges)),
      UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addToRoot)),
      UIBarButtonItem(
        barButtonSystemItem: .action, target: self, action: #selector(exportCurrentNBT)),
      UIBarButtonItem(title: "根名称", style: .plain, target: self, action: #selector(editRootName)),
      batchSelectionCoordinator.selectionButton,
    ]
  }

  func updateSearchResults(for searchController: UISearchController) { rebuildRows() }

  private var query: String {
    searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      ?? ""
  }

  private func rebuildRows() {
    if query.isEmpty {
      rows.removeAll(keepingCapacity: true)
      if rootNeedsOwnRow {
        rows.append(
          NBTNode(
            path: [],
            name: document.rootName.isEmpty ? "（根标签）" : document.rootName,
            value: document.root,
            depth: 0
          ))
      } else {
        rows = NBTTreeRows.visibleChildren(of: document.root, expanded: expanded)
      }
      navigationItem.prompt =
        "根名称：\(document.rootName.isEmpty ? "（空）" : document.rootName)\(dirty ? " · 未保存" : "")"
    } else {
      if rootNeedsOwnRow {
        let root = NBTNode(
          path: [],
          name: document.rootName.isEmpty ? "（根标签）" : document.rootName,
          value: document.root,
          depth: 0
        )
        if NBTTreeRows.matches(root, query: query) { rows.append(root) }
      }
      rows.append(contentsOf: NBTTreeRows.search(in: document.root, query: query))
      navigationItem.prompt = "找到 \(rows.count) 个节点"
    }
    title = dirty ? "\(displayTitle) •" : displayTitle
    tableView.reloadData()
    batchSelectionCoordinator.synchronizeWithVisibleRows()
  }

  private var rootNeedsOwnRow: Bool {
    switch document.root {
    case .compound, .list:
      return false
    default:
      return true
    }
  }

  override func numberOfSections(in tableView: UITableView) -> Int { 1 }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    rows.count
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    "点按标量可修改；长按节点可复制、粘贴、增加、重命名或删除。完成后点击保存，再从上一级导出文件。"
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let node = rows[indexPath.row]
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "StandaloneNBTNodeCell")
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: "StandaloneNBTNodeCell")
    cell.indentationLevel = query.isEmpty ? node.depth : 0
    cell.indentationWidth = 18
    cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    cell.detailTextLabel?.textColor = .secondaryLabel
    cell.detailTextLabel?.numberOfLines = query.isEmpty ? 1 : 2
    cell.imageView?.image = NBTTagIcon.image(for: node.value.type)
    cell.imageView?.contentMode = .center
    let marker = node.hasChildren ? (expanded.contains(node.path) ? "▾" : "▸") : " "
    cell.textLabel?.text = "\(marker) \(node.name)  <\(node.value.type.displayName)>"
    cell.detailTextLabel?.text =
      query.isEmpty ? node.value.summary : "\(node.value.summary)\n\(node.pathDescription)"
    batchSelectionCoordinator.configureCell(
      cell, node: node, normalAccessory: node.hasChildren ? .none : .disclosureIndicator)
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let node = rows[indexPath.row]
    if batchSelectionCoordinator.handleTap(on: node) { return }
    if node.hasChildren {
      if !query.isEmpty {
        for length in 1...node.path.count { expanded.insert(Array(node.path.prefix(length))) }
        searchController.searchBar.text = ""
        searchController.isActive = false
      } else if expanded.contains(node.path) {
        expanded.remove(node.path)
      } else {
        expanded.insert(node.path)
      }
      rebuildRows()
      return
    }
    edit(node)
  }

  private func edit(_ node: NBTNode) {
    NBTEditingUI.presentEdit(from: self, node: node) { [weak self] replacement in
      guard let self = self else { return }
      do {
        self.document.root = try NBTTreeMutation.replacingValue(
          at: node.path,
          in: self.document.root,
          with: replacement
        )
        self.dirty = true
        self.rebuildRows()
      } catch {
        self.showError(error, title: "修改失败")
      }
    }
  }

  @objc private func editRootName() {
    let alert = UIAlertController(
      title: "修改 NBT 根名称",
      message: "根名称可以为空；Bedrock mcstructure 通常使用空根名称。",
      preferredStyle: .alert
    )
    alert.addTextField { [weak self] field in
      field.text = self?.document.rootName
      field.clearButtonMode = .whileEditing
      field.autocapitalizationType = .none
      field.autocorrectionType = .no
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "修改", style: .default) { [weak self, weak alert] _ in
        guard let self = self else { return }
        self.document.rootName = alert?.textFields?.first?.text ?? ""
        self.dirty = true
        self.rebuildRows()
      })
    present(alert, animated: true)
  }

  @objc private func addToRoot() {
    NBTEditingUI.presentAddOrPaste(from: self, container: document.root, sourceView: view) {
      [weak self] name, value, replacingExisting in
      self?.add(value: value, name: name, to: [], replacingExisting: replacingExisting)
    }
  }

  private func add(
    value: NBTValue, name: String?, to path: [NBTPathComponent], replacingExisting: Bool = false
  ) {
    do {
      document.root = try NBTTreeMutation.adding(
        value, named: name, to: path, in: document.root, replacingExisting: replacingExisting)
      expanded.insert(path)
      dirty = true
      rebuildRows()
    } catch {
      showError(error, title: "增加失败")
    }
  }

  private func rename(_ node: NBTNode, to name: String) {
    do {
      document.root = try NBTTreeMutation.renaming(at: node.path, to: name, in: document.root)
      expanded = [[]]
      dirty = true
      rebuildRows()
    } catch {
      showError(error, title: "重命名失败")
    }
  }

  private func delete(_ node: NBTNode) {
    do {
      document.root = try NBTTreeMutation.deleting(at: node.path, in: document.root)
      expanded = Set(expanded.filter { !$0.starts(with: node.path) })
      dirty = true
      rebuildRows()
    } catch {
      showError(error, title: "删除失败")
    }
  }

  override func tableView(
    _ tableView: UITableView,
    contextMenuConfigurationForRowAt indexPath: IndexPath,
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard !batchSelectionCoordinator.isActive, rows.indices.contains(indexPath.row) else {
      return nil
    }
    let node = rows[indexPath.row]
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      guard let self = self else { return nil }
      var actions = [UIAction]()
      switch node.value {
      case .compound:
        actions.append(
          UIAction(title: "增加子标签", image: UIImage(systemName: "plus")) { [weak self] _ in
            guard let self = self else { return }
            NBTEditingUI.presentAddOrPaste(
              from: self,
              container: node.value,
              sourceView: tableView.cellForRow(at: indexPath)
            ) { [weak self] name, value, replacingExisting in
              self?.add(
                value: value, name: name, to: node.path, replacingExisting: replacingExisting)
            }
          })
      case .list:
        actions.append(
          UIAction(title: "增加列表元素", image: UIImage(systemName: "plus")) { [weak self] _ in
            guard let self = self else { return }
            NBTEditingUI.presentAddOrPaste(
              from: self,
              container: node.value,
              sourceView: tableView.cellForRow(at: indexPath)
            ) { [weak self] name, value, replacingExisting in
              self?.add(
                value: value, name: name, to: node.path, replacingExisting: replacingExisting)
            }
          })
      default:
        break
      }
      if node.value.isDirectlyEditable {
        actions.append(
          UIAction(title: "修改值", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
            self?.edit(node)
          })
      }
      if case .compound? = node.path.last {
        actions.append(
          UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in
            guard let self = self else { return }
            NBTEditingUI.presentRename(from: self, currentName: node.name) { [weak self] newName in
              self?.rename(node, to: newName)
            }
          })
      }
      actions.append(
        contentsOf: NBTEditingUI.clipboardActions(
          from: self,
          node: node,
          sourceView: tableView.cellForRow(at: indexPath)
        ) { [weak self] name, value, replacingExisting in
          self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
        })
      if !node.path.isEmpty {
        actions.append(
          UIAction(
            title: "删除",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
          ) { [weak self] _ in
            guard let self = self else { return }
            NBTEditingUI.confirmDelete(from: self, nodeName: node.name) { [weak self] in
              self?.delete(node)
            }
          })
      }
      return UIMenu(title: node.pathDescription, children: actions)
    }
  }

  override func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    guard !batchSelectionCoordinator.isActive, rows.indices.contains(indexPath.row) else {
      return nil
    }
    let node = rows[indexPath.row]
    guard !node.path.isEmpty else { return nil }
    let deleteAction = UIContextualAction(style: .destructive, title: "删除") {
      [weak self] _, _, completion in
      guard let self = self else {
        completion(false)
        return
      }
      NBTEditingUI.confirmDelete(from: self, nodeName: node.name) { [weak self] in
        self?.delete(node)
        completion(true)
      }
    }
    let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
    configuration.performsFirstActionWithFullSwipe = false
    return configuration
  }

  @objc private func exportCurrentNBT() {
    NBTExportUI.presentFormatChooser(
      from: self,
      documents: [document],
      baseFilename: displayTitle,
      allowMCStructure: true,
      barButtonItem: navigationItem.rightBarButtonItems?.dropLast(2).last
    )
  }

  @objc private func commitChanges() {
    guard dirty else {
      navigationItem.prompt = "没有需要保存的修改"
      return
    }
    saveChanges()
    navigationItem.prompt = "已保存到文件会话，可返回上一级导出"
  }

  private func saveChanges() {
    onCommit(document)
    dirty = false
    rebuildRows()
  }

  @objc private func closeEditor() {
    guard dirty else {
      navigationController?.popViewController(animated: true)
      return
    }
    let alert = UIAlertController(
      title: "保存修改后返回？",
      message: "保存会把当前根标签写入文件会话；返回上一级后可继续导出或格式转换。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "不保存", style: .destructive) { [weak self] _ in
        self?.navigationController?.popViewController(animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "保存并返回", style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.saveChanges()
        self.navigationController?.popViewController(animated: true)
      })
    present(alert, animated: true)
  }
}

extension StandaloneNBTEditorViewController: NBTBatchTreeSelectionDelegate {
  var nbtBatchRows: [NBTNode] { rows }
  var nbtBatchRoot: NBTValue {
    get { document.root }
    set { document.root = newValue }
  }
  var nbtBatchNavigationItem: UINavigationItem { navigationItem }
  var nbtBatchTableView: UITableView { tableView }
  var nbtBatchPresenter: UIViewController { self }

  func restoreNBTNavigationItems() {
    configureNavigationItems()
    rebuildRows()
  }

  func nbtBatchSelectionDidMutate() {
    dirty = true
    expanded = [[]]
    rebuildRows()
  }
}
