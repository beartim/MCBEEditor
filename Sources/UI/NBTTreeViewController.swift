import UIKit

final class NBTTreeViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private var levelDat: LevelDatFile?
    private var rows: [NBTNode] = []
    private var expanded = Set<[NBTPathComponent]>()
    private var dirty = false
    private let searchController = UISearchController(searchResultsController: nil)
    private lazy var batchSelectionCoordinator = NBTBatchSelectionCoordinator(delegate: self)

    init(session: WorldSession) {
        self.session = session
        super.init(style: .insetGrouped)
        title = "世界 NBT"
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(worldDidChange),
            name: WorldSession.worldDidChangeNotification,
            object: session
        )
        loadDocument()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configureNavigationItems() {
        guard !batchSelectionCoordinator.isActive else { return }
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addToRoot)),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(exportCurrentNBT)),
            UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(loadDocument)),
            batchSelectionCoordinator.selectionButton
        ]
    }


    @objc private func worldDidChange() { loadDocument() }

    @objc private func loadDocument() {
        do {
            levelDat = try session.document.readLevelDat()
            expanded = [[]]
            dirty = false
            rebuildRows()
        } catch {
            showError(error, title: "无法读取 level.dat")
        }
    }

    @objc private func exportCurrentNBT() {
        guard let document = levelDat?.document else { return }
        NBTExportUI.presentFormatChooser(
            from: self,
            documents: [document],
            baseFilename: "level-dat",
            barButtonItem: navigationItem.rightBarButtonItems?.dropLast(2).last
        )
    }

    @objc private func save() {
        guard let levelDat = levelDat else { return }
        do {
            try session.document.writeLevelDat(levelDat)
            dirty = false
            rebuildRows()
            navigationItem.prompt = "世界 NBT 已保存"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if self?.searchQuery.isEmpty == true { self?.navigationItem.prompt = nil }
            }
        } catch {
            showError(error, title: "保存失败")
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        rebuildRows()
    }

    private var searchQuery: String {
        searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func rebuildRows() {
        rows.removeAll(keepingCapacity: true)
        guard let root = levelDat?.document.root else {
            tableView.reloadData()
            return
        }

        if searchQuery.isEmpty {
            appendChildren(of: root, parentPath: [], depth: 0)
            navigationItem.prompt = nil
        } else {
            appendMatches(of: root, parentPath: [], depth: 0, query: searchQuery)
            navigationItem.prompt = "找到 \(rows.count) 个节点"
        }
        tableView.reloadData()
        title = dirty ? "世界 NBT •" : "世界 NBT"
        batchSelectionCoordinator.synchronizeWithVisibleRows()
    }

    private func appendChildren(of value: NBTValue, parentPath: [NBTPathComponent], depth: Int) {
        switch value {
        case .compound(let tags):
            for tag in tags {
                let path = parentPath + [.compound(tag.name)]
                rows.append(NBTNode(path: path, name: tag.name, value: tag.value, depth: depth))
                if expanded.contains(path) { appendChildren(of: tag.value, parentPath: path, depth: depth + 1) }
            }
        case .list(_, let values):
            for (index, child) in values.enumerated() {
                let path = parentPath + [.list(index)]
                rows.append(NBTNode(path: path, name: "[\(index)]", value: child, depth: depth))
                if expanded.contains(path) { appendChildren(of: child, parentPath: path, depth: depth + 1) }
            }
        default:
            break
        }
    }

    private func appendMatches(of value: NBTValue, parentPath: [NBTPathComponent], depth: Int, query: String) {
        switch value {
        case .compound(let tags):
            for tag in tags {
                let path = parentPath + [.compound(tag.name)]
                let node = NBTNode(path: path, name: tag.name, value: tag.value, depth: depth)
                if matches(node, query: query) { rows.append(node) }
                appendMatches(of: tag.value, parentPath: path, depth: depth + 1, query: query)
            }
        case .list(_, let values):
            for (index, child) in values.enumerated() {
                let path = parentPath + [.list(index)]
                let node = NBTNode(path: path, name: "[\(index)]", value: child, depth: depth)
                if matches(node, query: query) { rows.append(node) }
                appendMatches(of: child, parentPath: path, depth: depth + 1, query: query)
            }
        default:
            break
        }
    }

    private func matches(_ node: NBTNode, query: String) -> Bool {
        node.name.lowercased().contains(query) ||
        node.pathDescription.lowercased().contains(query) ||
        node.value.type.displayName.lowercased().contains(query) ||
        node.value.summary.lowercased().contains(query)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "长按节点可增加、重命名或删除；左滑节点可快速删除。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let node = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "NBTCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "NBTCell")
        cell.indentationLevel = searchQuery.isEmpty ? node.depth : 0
        cell.indentationWidth = 18
        cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = searchQuery.isEmpty ? 1 : 2
        cell.imageView?.image = NBTTagIcon.image(for: node.value.type)
        cell.imageView?.contentMode = .center
        let marker: String
        if node.hasChildren { marker = expanded.contains(node.path) ? "▾" : "▸" } else { marker = " " }
        cell.textLabel?.text = "\(marker) \(node.name)  <\(node.value.type.displayName)>"
        cell.detailTextLabel?.text = searchQuery.isEmpty ? node.value.summary : "\(node.value.summary)\n\(node.pathDescription)"
        batchSelectionCoordinator.configureCell(cell, node: node, normalAccessory: node.hasChildren ? .none : .disclosureIndicator)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let node = rows[indexPath.row]
        if batchSelectionCoordinator.handleTap(on: node) { return }
        if node.hasChildren {
            if !searchQuery.isEmpty {
                reveal(node)
            } else {
                if expanded.contains(node.path) { expanded.remove(node.path) } else { expanded.insert(node.path) }
                rebuildRows()
            }
            return
        }
        edit(node)
    }

    private func reveal(_ node: NBTNode) {
        for length in 1...node.path.count {
            expanded.insert(Array(node.path.prefix(length)))
        }
        searchController.searchBar.text = ""
        searchController.isActive = false
        rebuildRows()
        if let row = rows.firstIndex(where: { $0.path == node.path }) {
            tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: true)
        }
    }

    private func edit(_ node: NBTNode) {
        guard var file = levelDat else { return }
        NBTEditingUI.presentEdit(from: self, node: node) { [weak self] replacement in
            guard let self = self else { return }
            do {
                file.document.root = try NBTTreeMutation.replacingValue(at: node.path, in: file.document.root, with: replacement)
                self.levelDat = file
                self.dirty = true
                self.rebuildRows()
            } catch {
                self.showError(error, title: "修改失败")
            }
        }
    }




    @objc private func addToRoot() {
        guard let root = levelDat?.document.root else { return }
        NBTEditingUI.presentAddOrPaste(from: self, container: root, sourceView: view) { [weak self] name, value, replacingExisting in
            self?.add(value: value, name: name, to: [], replacingExisting: replacingExisting)
        }
    }

    private func add(value: NBTValue, name: String?, to path: [NBTPathComponent], replacingExisting: Bool = false) {
        guard var file = levelDat else { return }
        do {
            file.document.root = try NBTTreeMutation.adding(value, named: name, to: path, in: file.document.root, replacingExisting: replacingExisting)
            levelDat = file
            expanded.insert(path)
            dirty = true
            rebuildRows()
        } catch {
            showError(error, title: "增加失败")
        }
    }

    private func rename(_ node: NBTNode, to name: String) {
        guard var file = levelDat else { return }
        do {
            file.document.root = try NBTTreeMutation.renaming(at: node.path, to: name, in: file.document.root)
            levelDat = file
            expanded = [[]]
            dirty = true
            rebuildRows()
        } catch {
            showError(error, title: "重命名失败")
        }
    }

    private func delete(_ node: NBTNode) {
        guard var file = levelDat else { return }
        do {
            file.document.root = try NBTTreeMutation.deleting(at: node.path, in: file.document.root)
            levelDat = file
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
                    NBTEditingUI.presentAdd(from: self, container: node.value, sourceView: tableView.cellForRow(at: indexPath)) { [weak self] name, value, replacingExisting in
                        self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
                    }
                })
            } else if case .list = node.value {
                actions.append(UIAction(title: "增加列表元素", image: UIImage(systemName: "plus")) { [weak self] _ in
                    guard let self = self else { return }
                    NBTEditingUI.presentAdd(from: self, container: node.value, sourceView: tableView.cellForRow(at: indexPath)) { [weak self] name, value, replacingExisting in
                        self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
                    }
                })
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

    private func textualData(for value: NBTValue) -> Data {
        Data(value.summary.utf8)
    }
}


extension NBTTreeViewController: NBTBatchTreeSelectionDelegate {
    var nbtBatchRows: [NBTNode] { rows }
    var nbtBatchRoot: NBTValue {
        get { levelDat?.document.root ?? .compound([]) }
        set {
            guard var file = levelDat else { return }
            file.document.root = newValue
            levelDat = file
        }
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
