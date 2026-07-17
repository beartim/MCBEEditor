import UIKit

final class VillageNBTEditorViewController: UITableViewController, UISearchResultsUpdating {
    private let record: VillageNBTRecord
    private let store: VillageNBTStore
    private let onSave: () -> Void
    private var document: NBTDocument
    private var rows = [NBTNode]()
    private var expanded = Set<[NBTPathComponent]>()
    private var dirty = false
    private let searchController = UISearchController(searchResultsController: nil)
    private lazy var batchSelectionCoordinator = NBTBatchSelectionCoordinator(delegate: self)
    private let residentOptionKinds: [VillageResidentEntityKind] = [.villager, .cat, .ironGolem]
    private var residentResolution: VillageResidentResolution?
    private var isLoadingResidents = false
    private let residentQueue = DispatchQueue(label: "com.wzn.blocktopograph.village-residents", qos: .userInitiated)

    init(record: VillageNBTRecord, store: VillageNBTStore, onSave: @escaping () -> Void) {
        self.record = record
        self.store = store
        self.onSave = onSave
        self.document = record.document
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
        navigationItem.prompt = record.keyText
        configureNavigationItems()
        expanded.insert([])
        rebuildRows()
        if showsResidentOptions { loadResidentEntities() }
    }

    private func configureNavigationItems() {
        guard !batchSelectionCoordinator.isActive else { return }
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addToRoot)),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(exportCurrentNBT)),
            batchSelectionCoordinator.selectionButton
        ]
    }

    func updateSearchResults(for searchController: UISearchController) { rebuildRows() }

    private var query: String {
        searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var showsResidentOptions: Bool { record.kind == .dwellers }
    private var nbtSection: Int { showsResidentOptions ? 1 : 0 }

    private func loadResidentEntities() {
        guard !isLoadingResidents else { return }
        isLoadingResidents = true
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
        residentQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let resolution = try self.store.residentResolution(villageIdentifier: self.record.villageIdentifier)
                DispatchQueue.main.async {
                    self.isLoadingResidents = false
                    self.residentResolution = resolution
                    self.tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingResidents = false
                    self.tableView.reloadSections(IndexSet(integer: 0), with: .none)
                    self.showError(error, title: "读取村庄居民实体失败")
                }
            }
        }
    }

    private func showResidentEntities(_ kind: VillageResidentEntityKind) {
        guard let resolution = residentResolution else {
            loadResidentEntities()
            return
        }
        let controller = VillageResidentEntitiesViewController(
            session: store.worldSession,
            objects: resolution.entities(of: kind),
            residentKind: kind
        )
        navigationController?.pushViewController(controller, animated: true)
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
        tableView.reloadData()
        title = dirty ? "\(record.displayName) •" : record.displayName
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
        default: break
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
        default: break
        }
    }

    private func matches(_ node: NBTNode) -> Bool {
        node.name.lowercased().contains(query) ||
        node.pathDescription.lowercased().contains(query) ||
        node.value.type.displayName.lowercased().contains(query) ||
        node.value.summary.lowercased().contains(query)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { showsResidentOptions ? 2 : 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if showsResidentOptions && section == 0 { return residentOptionKinds.count }
        return rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if showsResidentOptions && section == 0 { return "查看该村庄的全部居民实体" }
        return "\(record.kind.displayName) NBT"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if showsResidentOptions && section == 0 {
            if isLoadingResidents { return "正在遍历 Dwellers 的全部 ID，并在世界实体中确定类型…" }
            guard let resolution = residentResolution else { return "点按任一项可重新读取居民实体。" }
            let unresolved = resolution.unresolvedUniqueIDs.isEmpty
                ? ""
                : "；\(resolution.unresolvedUniqueIDs.count) 个 Dwellers ID 未匹配到世界实体"
            return "使用 Dwellers 的 ID 作为实体 UniqueID，在整个世界中匹配并分类\(unresolved)。"
        }
        return "长按节点可增加、重命名或删除；左滑节点可快速删除。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if showsResidentOptions && indexPath.section == 0 {
            let kind = residentOptionKinds[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "VillageResidentOptionCell")
                ?? UITableViewCell(style: .subtitle, reuseIdentifier: "VillageResidentOptionCell")
            let count = residentResolution?.entities(of: kind).count
            cell.textLabel?.text = "查看全部\(kind.displayName)"
            cell.detailTextLabel?.text = isLoadingResidents ? "正在匹配 Dwellers ID（实体 UniqueID）…" : "共 \(count ?? 0) 个"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.image = UIImage(systemName: kind.iconName) ?? UIImage(systemName: "person.fill")
            cell.accessoryType = batchSelectionCoordinator.isActive ? .none : .disclosureIndicator
            cell.selectionStyle = batchSelectionCoordinator.isActive ? .none : .default
            return cell
        }
        let node = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "VillageNBTNodeCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "VillageNBTNodeCell")
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
        if showsResidentOptions && indexPath.section == 0 {
            if !batchSelectionCoordinator.isActive {
                showResidentEntities(residentOptionKinds[indexPath.row])
            }
            return
        }
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
        guard !batchSelectionCoordinator.isActive, indexPath.section == nbtSection, rows.indices.contains(indexPath.row) else { return nil }
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
            default: break
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
            ) { [weak self] name, value, replacingExisting in
                self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
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
        guard !batchSelectionCoordinator.isActive, indexPath.section == nbtSection, rows.indices.contains(indexPath.row) else { return nil }
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

    @objc private func save() {
        guard dirty else {
            navigationItem.prompt = "没有需要保存的修改"
            return
        }
        do {
            try store.save(record: record, document: document)
            dirty = false
            rebuildRows()
            navigationItem.prompt = "村庄 NBT 已保存"
            onSave()
        } catch {
            showError(error, title: "保存村庄 NBT 失败")
        }
    }

    @objc private func exportCurrentNBT() {
        NBTExportUI.presentFormatChooser(
            from: self,
            documents: [document],
            baseFilename: "village-\(record.villageIdentifier)-\(record.kind.rawValue)",
            barButtonItem: navigationItem.rightBarButtonItems?.dropLast().last
        )
    }
}


extension VillageNBTEditorViewController: NBTBatchTreeSelectionDelegate {
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
