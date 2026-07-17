import UIKit

final class StructureNBTEditorViewController: UITableViewController, UISearchResultsUpdating {
    private let record: StructureNBTRecord
    private let store: StructureNBTStore
    private let onSave: () -> Void
    private var document: NBTDocument
    private var rows = [NBTNode]()
    private var expanded = Set<[NBTPathComponent]>()
    private var dirty = false
    private let searchController = UISearchController(searchResultsController: nil)
    private lazy var batchSelectionCoordinator = NBTBatchSelectionCoordinator(delegate: self)

    init(record: StructureNBTRecord, store: StructureNBTStore, onSave: @escaping () -> Void) {
        guard let document = record.document else {
            fatalError("StructureNBTEditorViewController requires a decoded document")
        }
        self.record = record
        self.store = store
        self.onSave = onSave
        self.document = document
        super.init(style: .insetGrouped)
        title = record.displayName
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
        configureNavigationItems()
        expanded.insert([])
        rebuildRows()
    }

    private func configureNavigationItems() {
        guard !batchSelectionCoordinator.isActive else { return }
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(confirmSave)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addToRoot)),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(exportCurrentNBT)),
            batchSelectionCoordinator.selectionButton
        ]
    }

    func updateSearchResults(for searchController: UISearchController) { rebuildRows() }

    private var query: String {
        searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func rebuildRows() {
        rows.removeAll(keepingCapacity: true)
        if query.isEmpty {
            appendChildren(of: document.root, path: [], depth: 0)
            navigationItem.prompt = dirty ? "\(record.keyText) • 未保存" : record.keyText
        } else {
            appendMatches(of: document.root, path: [], depth: 0)
            navigationItem.prompt = "找到 \(rows.count) 个节点"
        }
        title = dirty ? "\(record.displayName) •" : record.displayName
        tableView.reloadData()
        batchSelectionCoordinator.synchronizeWithVisibleRows()
    }

    private func appendChildren(of value: NBTValue, path: [NBTPathComponent], depth: Int) {
        switch value {
        case .compound(let tags):
            for tag in tags {
                let childPath = path + [.compound(tag.name)]
                let node = NBTNode(path: childPath, name: tag.name, value: tag.value, depth: depth)
                rows.append(node)
                if expanded.contains(childPath) { appendChildren(of: tag.value, path: childPath, depth: depth + 1) }
            }
        case .list(_, let values):
            for (index, child) in values.enumerated() {
                let childPath = path + [.list(index)]
                let node = NBTNode(path: childPath, name: "[\(index)]", value: child, depth: depth)
                rows.append(node)
                if expanded.contains(childPath) { appendChildren(of: child, path: childPath, depth: depth + 1) }
            }
        default:
            break
        }
    }

    private func appendMatches(of value: NBTValue, path: [NBTPathComponent], depth: Int) {
        switch value {
        case .compound(let tags):
            for tag in tags {
                let childPath = path + [.compound(tag.name)]
                let node = NBTNode(path: childPath, name: tag.name, value: tag.value, depth: depth)
                if matches(node) { rows.append(node) }
                appendMatches(of: tag.value, path: childPath, depth: depth + 1)
            }
        case .list(_, let values):
            for (index, child) in values.enumerated() {
                let childPath = path + [.list(index)]
                let node = NBTNode(path: childPath, name: "[\(index)]", value: child, depth: depth)
                if matches(node) { rows.append(node) }
                appendMatches(of: child, path: childPath, depth: depth + 1)
            }
        default:
            break
        }
    }

    private func matches(_ node: NBTNode) -> Bool {
        node.name.lowercased().contains(query) ||
        node.pathDescription.lowercased().contains(query) ||
        node.value.type.displayName.lowercased().contains(query) ||
        node.value.summary.lowercased().contains(query)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "点按标量可修改；长按节点可增加、重命名或删除。修改会直接写入世界数据库。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let node = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "StructureNBTNodeCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "StructureNBTNodeCell")
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
        cell.detailTextLabel?.text = query.isEmpty ? node.value.summary : "\(node.value.summary)\n\(node.pathDescription)"
        batchSelectionCoordinator.configureCell(cell, node: node, normalAccessory: node.hasChildren ? .none : .disclosureIndicator)
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
                self.document.root = try NBTTreeMutation.replacingValue(at: node.path, in: self.document.root, with: replacement)
                self.dirty = true
                self.rebuildRows()
            } catch {
                self.showError(error, title: "修改失败")
            }
        }
    }

    @objc private func addToRoot() {
        NBTEditingUI.presentAddOrPaste(from: self, container: document.root, sourceView: view) { [weak self] name, value in
            self?.add(value: value, name: name, to: [])
        }
    }

    private func add(value: NBTValue, name: String?, to path: [NBTPathComponent]) {
        do {
            document.root = try NBTTreeMutation.adding(value, named: name, to: path, in: document.root)
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
        guard !batchSelectionCoordinator.isActive, rows.indices.contains(indexPath.row) else { return nil }
        let node = rows[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            var actions = [UIAction]()
            switch node.value {
            case .compound:
                actions.append(UIAction(title: "增加子标签", image: UIImage(systemName: "plus")) { [weak self] _ in
                    guard let self = self else { return }
                    NBTEditingUI.presentAdd(from: self, container: node.value, sourceView: tableView.cellForRow(at: indexPath)) { [weak self] name, value in
                        self?.add(value: value, name: name, to: node.path)
                    }
                })
            case .list:
                actions.append(UIAction(title: "增加列表元素", image: UIImage(systemName: "plus")) { [weak self] _ in
                    guard let self = self else { return }
                    NBTEditingUI.presentAdd(from: self, container: node.value, sourceView: tableView.cellForRow(at: indexPath)) { [weak self] name, value in
                        self?.add(value: value, name: name, to: node.path)
                    }
                })
            default:
                break
            }
            if node.value.isDirectlyEditable {
                actions.append(UIAction(title: "修改值", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                    self?.edit(node)
                })
            }
            if case .compound? = node.path.last {
                actions.append(UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in
                    guard let self = self else { return }
                    NBTEditingUI.presentRename(from: self, currentName: node.name) { [weak self] newName in
                        self?.rename(node, to: newName)
                    }
                })
            }
            actions.append(contentsOf: NBTEditingUI.clipboardActions(
                from: self,
                node: node,
                sourceView: tableView.cellForRow(at: indexPath)
            ) { [weak self] name, value in
                self?.add(value: value, name: name, to: node.path)
            })
            actions.append(UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                guard let self = self else { return }
                NBTEditingUI.confirmDelete(from: self, nodeName: node.name) { [weak self] in self?.delete(node) }
            })
            return UIMenu(title: node.pathDescription, children: actions)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !batchSelectionCoordinator.isActive, rows.indices.contains(indexPath.row) else { return nil }
        let node = rows[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            NBTEditingUI.confirmDelete(from: self, nodeName: node.name) { [weak self] in
                self?.delete(node)
                completion(true)
            }
        }
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    @objc private func confirmSave() {
        guard dirty else {
            navigationItem.prompt = "没有需要保存的修改"
            return
        }
        let alert = UIAlertController(
            title: "保存结构 NBT？",
            message: "将直接修改世界 LevelDB 中的 structuretemplate 记录。保存前请退出 Minecraft。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .destructive) { [weak self] _ in self?.performSave() })
        present(alert, animated: true)
    }

    private func performSave() {
        do {
            try store.save(record: record, document: document)
            dirty = false
            rebuildRows()
            navigationItem.prompt = "结构 NBT 已保存"
            onSave()
        } catch {
            showError(error, title: "保存结构 NBT 失败")
        }
    }

    @objc private func exportCurrentNBT() {
        NBTExportUI.presentFormatChooser(
            from: self,
            documents: [document],
            baseFilename: safeFilename(record.displayName),
            allowMCStructure: true,
            barButtonItem: navigationItem.rightBarButtonItems?.dropLast().last
        )
    }

    private func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "structure" : String(cleaned.prefix(120))
    }
}


extension StructureNBTEditorViewController: NBTBatchTreeSelectionDelegate {
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
