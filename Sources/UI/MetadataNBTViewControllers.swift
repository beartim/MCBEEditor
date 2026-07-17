import UIKit

final class MetadataNBTListViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private let store: MetadataNBTStore
    private let searchController = UISearchController(searchResultsController: nil)
    private var allRecords = [MetadataNBTRecord]()
    private var shownRecords = [MetadataNBTRecord]()

    init(session: WorldSession) {
        self.session = session
        self.store = MetadataNBTStore(session: session)
        super.init(style: .insetGrouped)
        title = "元数据"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索元数据键或名称"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(loadRecords))
        loadRecords()
    }

    @objc private func loadRecords() {
        let overlay = showBusy("读取元数据 NBT…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let records = try self.store.records()
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.allRecords = records
                    self.applyFilter()
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "读取元数据失败")
                }
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) { applyFilter() }

    private func applyFilter() {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        shownRecords = allRecords.filter {
            query.isEmpty || $0.keyText.lowercased().contains(query) || $0.displayName.lowercased().contains(query)
        }
        navigationItem.prompt = "\(shownRecords.count) 项元数据"
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shownRecords.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "AutonomousEntities、BiomeData、mVillages、三个维度、portals、scoreboard、mobevents、schedulerWT 与 map_*。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = shownRecords[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "MetadataNBTCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "MetadataNBTCell")
        cell.textLabel?.text = record.displayName
        cell.detailTextLabel?.text = "\(record.keyText) · \(record.detailText)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: record.roots == nil ? "doc.questionmark" : "doc.text.magnifyingglass")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(record: shownRecords[indexPath.row])
    }

    private func open(record: MetadataNBTRecord) {
        guard record.roots != nil else {
            let detail = DatabaseValueViewController(title: record.displayName, data: record.rawData, editable: false)
            detail.navigationItem.prompt = record.decodeError
            navigationController?.pushViewController(detail, animated: true)
            return
        }
        navigationController?.pushViewController(
            MetadataNBTRecordViewController(record: record, store: store) { [weak self] in self?.loadRecords() },
            animated: true
        )
    }
}

final class MetadataNBTRecordViewController: UITableViewController, UISearchResultsUpdating {
    private let originalRecord: MetadataNBTRecord
    private let store: MetadataNBTStore
    private let onSave: () -> Void
    private var roots: [ConsecutiveNBTRecord]
    private var displayedIndices = [Int]()
    private var dirty = false
    private let searchController = UISearchController(searchResultsController: nil)
    private var isBatchSelecting = false
    private var batchSelectedIndices = Set<Int>()

    init(record: MetadataNBTRecord, store: MetadataNBTStore, onSave: @escaping () -> Void) {
        self.originalRecord = record
        self.store = store
        self.onSave = onSave
        self.roots = record.roots ?? []
        super.init(style: .insetGrouped)
        title = record.displayName
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索根名称、内容摘要或序号"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        configureNavigationItems()
        rebuild()
    }

    private func configureNavigationItems() {
        guard !isBatchSelecting else { return }
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addRoot)),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(exportAllRoots)),
            UIBarButtonItem(title: "选择", style: .plain, target: self, action: #selector(beginBatchSelection))
        ]
    }

    func updateSearchResults(for searchController: UISearchController) { rebuild() }

    private func rebuild() {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        displayedIndices = roots.indices.filter { index in
            let document = roots[index].document
            return query.isEmpty || String(index).contains(query) || document.rootName.lowercased().contains(query) || document.root.summary.lowercased().contains(query)
        }
        batchSelectedIndices.formIntersection(Set(roots.indices))
        navigationItem.prompt = "\(originalRecord.keyText)\(dirty ? " · 未保存" : "")"
        tableView.reloadData()
        updateBatchNavigationItems()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { displayedIndices.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "NBT 根标签（\(roots.count)）" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "点按根标签进入完整编辑器；修改后请点击右上角保存写回 LevelDB。" }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let index = displayedIndices[indexPath.row]
        let document = roots[index].document
        let cell = tableView.dequeueReusableCell(withIdentifier: "MetadataRootCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "MetadataRootCell")
        cell.textLabel?.text = "#\(index)  \(document.rootName.isEmpty ? "（空根名称）" : document.rootName)"
        cell.detailTextLabel?.text = document.root.summary
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = NBTTagIcon.image(for: document.root.type)
        cell.accessoryType = isBatchSelecting
            ? (batchSelectedIndices.contains(index) ? .checkmark : .none)
            : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let index = displayedIndices[indexPath.row]
        if isBatchSelecting {
            if batchSelectedIndices.contains(index) {
                batchSelectedIndices.remove(index)
            } else {
                batchSelectedIndices.insert(index)
            }
            tableView.reloadData()
            updateBatchNavigationItems()
            return
        }
        let document = roots[index].document
        let editor = StandaloneNBTEditorViewController(document: document, title: originalRecord.displayName) { [weak self] updated in
            guard let self = self, self.roots.indices.contains(index) else { return }
            self.roots[index].document = updated
            self.dirty = true
            self.rebuild()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func exportAllRoots() {
        NBTExportUI.presentFormatChooser(
            from: self,
            documents: roots.map(\.document),
            baseFilename: originalRecord.displayName,
            allowMCStructure: roots.count == 1,
            barButtonItem: navigationItem.rightBarButtonItems?.dropLast().last
        )
    }

    @objc private func beginBatchSelection() {
        guard !displayedIndices.isEmpty else { return }
        isBatchSelecting = true
        batchSelectedIndices.removeAll()
        tableView.reloadData()
        updateBatchNavigationItems()
    }

    @objc private func cancelBatchSelection() {
        isBatchSelecting = false
        batchSelectedIndices.removeAll()
        tableView.reloadData()
        configureNavigationItems()
        rebuild()
    }

    @objc private func toggleBatchSelectAll() {
        let visible = Set(displayedIndices)
        if !visible.isEmpty, visible.isSubset(of: batchSelectedIndices) {
            batchSelectedIndices.subtract(visible)
        } else {
            batchSelectedIndices.formUnion(visible)
        }
        tableView.reloadData()
        updateBatchNavigationItems()
    }

    @objc private func copyBatchSelection() {
        let documents = batchSelectedIndices.sorted().compactMap { index in
            roots.indices.contains(index) ? roots[index].document : nil
        }
        guard !documents.isEmpty else { return }
        NBTEditingUI.copyDocuments(documents, from: self)
        updateBatchNavigationItems(message: "已复制 \(documents.count) 个 NBT 根标签")
    }

    @objc private func exportBatchSelection() {
        let documents = batchSelectedIndices.sorted().compactMap { index in
            roots.indices.contains(index) ? roots[index].document : nil
        }
        guard !documents.isEmpty else { return }
        NBTExportUI.presentFormatChooser(
            from: self,
            documents: documents,
            baseFilename: originalRecord.displayName + "-selected",
            allowMCStructure: documents.count == 1,
            barButtonItem: navigationItem.rightBarButtonItems?.first
        )
    }

    @objc private func deleteBatchSelection() {
        let indices = batchSelectedIndices.sorted(by: >)
        guard !indices.isEmpty else { return }
        guard roots.count - indices.count >= 1 else {
            showError(BlocktopographError.unsupported("元数据至少需要保留一个 NBT 根标签。"), title: "无法删除全部根标签")
            return
        }
        let alert = UIAlertController(
            title: "删除所选 NBT 根标签？",
            message: "将删除 \(indices.count) 个根标签；点击保存后才会写回 LevelDB。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            for index in indices where self.roots.indices.contains(index) {
                self.roots.remove(at: index)
            }
            self.batchSelectedIndices.removeAll()
            self.dirty = true
            self.rebuild()
            self.updateBatchNavigationItems(message: "已删除 \(indices.count) 个 NBT 根标签")
        })
        present(alert, animated: true)
    }

    private func updateBatchNavigationItems(message: String? = nil) {
        guard isBatchSelecting else { return }
        let visible = Set(displayedIndices)
        let allSelected = !visible.isEmpty && visible.isSubset(of: batchSelectedIndices)
        let cancel = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelBatchSelection))
        let selectAll = UIBarButtonItem(title: allSelected ? "取消全选" : "全选", style: .plain, target: self, action: #selector(toggleBatchSelectAll))
        let export = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(exportBatchSelection))
        export.accessibilityLabel = "导出所选根标签"
        let copy = UIBarButtonItem(title: "复制", style: .plain, target: self, action: #selector(copyBatchSelection))
        let delete = UIBarButtonItem(title: "删除", style: .plain, target: self, action: #selector(deleteBatchSelection))
        delete.tintColor = .systemRed
        export.isEnabled = !batchSelectedIndices.isEmpty
        copy.isEnabled = !batchSelectedIndices.isEmpty
        delete.isEnabled = !batchSelectedIndices.isEmpty
        navigationItem.rightBarButtonItems = [delete, copy, export, selectAll, cancel]
        navigationItem.prompt = message ?? "批量选择：已选择 \(batchSelectedIndices.count) 个根标签"
    }

    @objc private func addRoot() {
        NBTEditingUI.presentCreateRoot(from: self, sourceView: view) { [weak self] documents in
            guard let self = self, !documents.isEmpty else { return }
            self.roots.append(contentsOf: documents.map {
                ConsecutiveNBTRecord(document: $0, rawData: Data(), encoding: .littleEndian)
            })
            self.dirty = true
            self.rebuild()
        }
    }

    @objc private func save() {
        do {
            try store.save(record: originalRecord, roots: roots)
            dirty = false
            rebuild()
            onSave()
            navigationItem.prompt = "已保存 \(originalRecord.keyText)"
        } catch {
            showError(error, title: "保存元数据失败")
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isBatchSelecting else { return nil }
        let rootIndex = displayedIndices[indexPath.row]
        let rename = UIContextualAction(style: .normal, title: "重命名") { [weak self] _, _, done in
            guard let self = self, self.roots.indices.contains(rootIndex) else { done(false); return }
            let alert = UIAlertController(title: "重命名根标签", message: "根名称可以为空。", preferredStyle: .alert)
            alert.addTextField { $0.text = self.roots[rootIndex].document.rootName }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
                guard let self = self, self.roots.indices.contains(rootIndex) else { return }
                self.roots[rootIndex].document.rootName = alert?.textFields?.first?.text ?? ""
                self.dirty = true
                self.rebuild()
            })
            self.present(alert, animated: true)
            done(true)
        }
        rename.backgroundColor = .systemOrange
        var actions = [rename]
        if roots.count > 1 {
            let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
                guard let self = self, self.roots.indices.contains(rootIndex), self.roots.count > 1 else { done(false); return }
                self.roots.remove(at: rootIndex)
                self.dirty = true
                self.rebuild()
                done(true)
            }
            actions.insert(delete, at: 0)
        }
        return UISwipeActionsConfiguration(actions: actions)
    }
}
