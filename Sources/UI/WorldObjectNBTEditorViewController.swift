import UIKit

final class WorldObjectNBTEditorViewController: UITableViewController, UISearchResultsUpdating {
    private let object: BedrockWorldObject
    private let store: BedrockWorldObjectNBTStore
    private let onSave: () -> Void
    private var document: NBTDocument
    private var rows = [NBTNode]()
    private var expanded = Set<[NBTPathComponent]>()
    private var dirty = false
    private let searchController = UISearchController(searchResultsController: nil)
    private lazy var batchSelectionCoordinator = NBTBatchSelectionCoordinator(delegate: self)

    init(object: BedrockWorldObject, session: WorldSession, onSave: @escaping () -> Void) {
        self.object = object
        self.store = BedrockWorldObjectNBTStore(session: session)
        self.onSave = onSave
        self.document = object.document
        super.init(style: .insetGrouped)
        title = object.displayName
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
            UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(confirmDeleteObject)),
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
            let state = dirty ? " • 未保存" : ""
            navigationItem.prompt = "\(object.source.rawValue)\(state)"
        } else {
            appendMatches(of: document.root, path: [], depth: 0)
            navigationItem.prompt = "找到 \(rows.count) 个节点"
        }
        title = dirty ? "\(object.displayName) •" : object.displayName
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

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let node = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorldObjectNBTCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "WorldObjectNBTCell")
        cell.indentationLevel = query.isEmpty ? node.depth : 0
        cell.indentationWidth = 18
        cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = query.isEmpty ? 1 : 2
        let marker = node.hasChildren ? (expanded.contains(node.path) ? "▾" : "▸") : " "
        let protected = isProtectedIdentityNode(node) ? " 🔗" : ""
        cell.imageView?.image = NBTTagIcon.image(for: node.value.type)
        cell.imageView?.contentMode = .center
        cell.textLabel?.text = "\(marker) \(node.name)  <\(node.value.type.displayName)>\(protected)"
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
        NBTEditingUI.presentAddOrPaste(from: self, container: document.root, sourceView: view) { [weak self] name, value, replacingExisting in
            self?.add(value: value, name: name, to: [], replacingExisting: replacingExisting)
        }
    }

    private func add(value: NBTValue, name: String?, to path: [NBTPathComponent], replacingExisting: Bool = false) {
        do {
            document.root = try NBTTreeMutation.adding(value, named: name, to: path, in: document.root, replacingExisting: replacingExisting)
            expanded.insert(path)
            dirty = true
            rebuildRows()
        } catch {
            showError(error, title: "增加失败")
        }
    }

    private func rename(_ node: NBTNode, to name: String) {
        guard !isProtectedIdentityNode(node) else {
            showError(BlocktopographError.unsupported("UniqueID 标签不能重命名。"), title: "受保护字段")
            return
        }
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
        guard !isProtectedIdentityNode(node) else {
            showError(BlocktopographError.unsupported("UniqueID 标签不能删除。"), title: "受保护字段")
            return
        }
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
            if case .compound = node.value {
                actions.append(UIAction(title: "增加子标签", image: UIImage(systemName: "plus")) { [weak self] _ in
                    guard let self = self else { return }
                    NBTEditingUI.presentAdd(from: self, container: node.value, sourceView: tableView.cellForRow(at: indexPath)) { [weak self] name, value in
                        self?.add(value: value, name: name, to: node.path)
                    }
                })
            } else if case .list = node.value {
                actions.append(UIAction(title: "增加列表元素", image: UIImage(systemName: "plus")) { [weak self] _ in
                    guard let self = self else { return }
                    NBTEditingUI.presentAdd(from: self, container: node.value, sourceView: tableView.cellForRow(at: indexPath)) { [weak self] name, value in
                        self?.add(value: value, name: name, to: node.path)
                    }
                })
            }
            if node.value.isDirectlyEditable {
                actions.append(UIAction(title: "修改值", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in self?.edit(node) })
            }
            if case .compound? = node.path.last, !self.isProtectedIdentityNode(node) {
                actions.append(UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in
                    guard let self = self else { return }
                    NBTEditingUI.presentRename(from: self, currentName: node.name) { [weak self] newName in self?.rename(node, to: newName) }
                })
            }
            actions.append(contentsOf: NBTEditingUI.clipboardActions(
                from: self,
                node: node,
                sourceView: tableView.cellForRow(at: indexPath)
            ) { [weak self] name, value, replacingExisting in
                self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
            })
            if !self.isProtectedIdentityNode(node) {
                actions.append(UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    guard let self = self else { return }
                    NBTEditingUI.confirmDelete(from: self, nodeName: node.name) { [weak self] in self?.delete(node) }
                })
            }
            return UIMenu(title: node.pathDescription, children: actions)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !batchSelectionCoordinator.isActive, rows.indices.contains(indexPath.row) else { return nil }
        let node = rows[indexPath.row]
        var actions = [UIContextualAction]()
        if node.value.isDirectlyEditable {
            let editAction = UIContextualAction(style: .normal, title: "修改") { [weak self] _, _, completion in
                self?.edit(node)
                completion(true)
            }
            editAction.backgroundColor = .systemBlue
            actions.append(editAction)
        }
        if !isProtectedIdentityNode(node) {
            let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
                guard let self = self else { completion(false); return }
                NBTEditingUI.confirmDelete(from: self, nodeName: node.name) { [weak self] in self?.delete(node); completion(true) }
            }
            actions.append(deleteAction)
        }
        guard !actions.isEmpty else { return nil }
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func isProtectedIdentityNode(_ node: NBTNode) -> Bool {
        guard object.kind == .entity else { return false }
        let normalized = node.name.replacingOccurrences(of: "_", with: "").lowercased()
        return normalized == "uniqueid"
    }

    @objc private func confirmDeleteObject() {
        let unsaved = dirty ? "当前未保存的 NBT 修改也会丢失。\n" : ""
        let alert = UIAlertController(
            title: "删除\(object.kind.displayName)？",
            message: "\(unsaved)将从世界 LevelDB 删除整个对象；现代实体的 actorprefix 与 digp 引用会同步清理。此操作不可撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            do {
                try self.store.delete(object: self.object)
                self.onSave()
                self.navigationController?.popViewController(animated: true)
            } catch {
                self.showError(error, title: "删除\(self.object.kind.displayName)失败")
            }
        })
        present(alert, animated: true)
    }

    @objc private func confirmSave() {
        guard dirty else {
            navigationItem.prompt = "没有需要保存的修改"
            return
        }
        let alert = UIAlertController(
            title: "保存 \(object.kind.displayName) NBT？",
            message: "将直接修改世界 LevelDB；若坐标跨区块或实体 UniqueID 改变，actorprefix 与 digp 索引会同步迁移。UniqueID 可修改但不能删除或重命名。保存前请退出 Minecraft。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .destructive) { [weak self] _ in
            self?.performSave()
        })
        present(alert, animated: true)
    }

    private func performSave() {
        do {
            let result = try store.save(object: object, document: document)
            dirty = false
            rebuildRows()
            let movedText = result.moved
                ? "；已迁移到维度 \(result.destinationDimension) 区块 (\(result.destinationChunkX), \(result.destinationChunkZ))"
                : ""
            let identityText = result.uniqueIDChanged
                ? result.destinationUniqueID.map { "；UniqueID 已改为 \($0)，索引已迁移" } ?? "；UniqueID 已修改"
                : ""
            navigationItem.prompt = "已保存\(movedText)\(identityText)"
            onSave()
        } catch {
            showError(error, title: "保存 \(object.kind.displayName) NBT 失败")
        }
    }

    @objc private func exportCurrentNBT() {
        let kind = object.kind == .entity ? "entity" : "block-entity"
        NBTExportUI.presentFormatChooser(
            from: self,
            documents: [document],
            baseFilename: "\(kind)-\(object.displayName)",
            barButtonItem: navigationItem.rightBarButtonItems?.dropLast().last
        )
    }
}


extension WorldObjectNBTEditorViewController: NBTBatchTreeSelectionDelegate {
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

    func nbtBatchCanDelete(_ node: NBTNode) -> Bool {
        !node.path.isEmpty && !isProtectedIdentityNode(node)
    }
}
