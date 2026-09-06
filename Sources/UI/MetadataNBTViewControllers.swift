import UIKit

final class MetadataNBTListViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private let store: MetadataNBTStore
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.metadata-nbt", qos: .userInitiated)
    private let searchController = UISearchController(searchResultsController: nil)
    private var allRecords = [MetadataNBTRecord]()
    private var shownRecords = [MetadataNBTRecord]()
    private var loadGeneration = 0
    private let viewedItems = ViewedItemTracker()
    private var isBatchSelecting = false
    private var batchSelectedKeys = Set<Data>()

    init(session: WorldSession) {
        self.session = session
        self.store = MetadataNBTStore(session: session)
        super.init(style: .insetGrouped)
        title = "世界元数据"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索元数据键或名称"
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
        loadRecords()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configureNavigationItems() {
        guard !isBatchSelecting else { return }
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(loadRecords)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(promptCreateMetadata)),
            UIBarButtonItem(title: "选择", style: .plain, target: self, action: #selector(beginBatchSelection))
        ]
    }

    @objc private func worldDidChange() {
        guard !isBatchSelecting else {
            navigationItem.prompt = "世界已发生变化；结束批量选择后刷新。"
            return
        }
        loadRecords()
    }

    @objc private func loadRecords() {
        loadGeneration += 1
        let generation = loadGeneration
        navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }
        navigationItem.prompt = "正在读取元数据 NBT…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let records = try self.store.records()
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
                    self.viewedItems.reset()
                    self.allRecords = records
                    self.batchSelectedKeys.formIntersection(Set(records.map(\.key)))
                    self.applyFilter()
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
                    self.navigationItem.prompt = nil
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
        if isBatchSelecting {
            updateBatchNavigationItems()
        } else {
            navigationItem.prompt = "\(shownRecords.count) 项元数据"
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shownRecords.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "支持新建、重命名、删除世界元数据；左滑可操作单项，右上角“选择”可批量重命名、复制键名或删除。支持固定元数据键与 map_* 地图键。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = shownRecords[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "MetadataNBTCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "MetadataNBTCell")
        cell.textLabel?.text = record.displayName
        cell.detailTextLabel?.text = "\(record.keyText) · \(record.detailText)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: record.roots == nil ? "doc.questionmark" : "doc.text.magnifyingglass")
        if isBatchSelecting {
            ViewedListSupport.clearAccessory(cell)
            cell.accessoryType = batchSelectedKeys.contains(record.key) ? .checkmark : .none
        } else {
            ViewedListSupport.configure(
                cell: cell,
                isViewed: viewedItems.contains(record.keyText),
                clearAction: { [weak self] in
                    guard let self = self else { return }
                    ViewedListSupport.presentClearConfirmation(from: self) { [weak self] in
                        guard let self = self else { return }
                        self.viewedItems.clear(record.keyText)
                        self.tableView.reloadData()
                    }
                }
            )
        }
        cell.mcbe_enableCompactText()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = shownRecords[indexPath.row]
        if isBatchSelecting {
            if batchSelectedKeys.contains(record.key) {
                batchSelectedKeys.remove(record.key)
            } else {
                batchSelectedKeys.insert(record.key)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
            updateBatchNavigationItems()
            return
        }
        viewedItems.mark(record.keyText)
        tableView.reloadRows(at: [indexPath], with: .none)
        open(record: record)
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

    // MARK: - Create / rename / delete

    @objc private func promptCreateMetadata() {
        let existing = Set(allRecords.map(\.keyText))
        let alert = UIAlertController(
            title: "新建世界元数据",
            message: MetadataNBTStore.creationHint(existingKeys: existing),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "例如 map_123"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "下一步", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let keyText = alert?.textFields?.first?.text ?? ""
            do {
                let clean = try MetadataNBTStore.validatedKeyText(keyText)
                guard !existing.contains(clean) else {
                    throw MCBEEditorError.malformedData("已存在同名元数据键：\(clean)")
                }
                self.presentCreateRoot(for: clean)
            } catch {
                self.showError(error, title: "无法新建元数据")
            }
        })
        present(alert, animated: true)
    }

    private func presentCreateRoot(for keyText: String) {
        NBTEditingUI.presentCreateRoot(from: self, sourceView: view) { [weak self] documents in
            guard let self = self, !documents.isEmpty else { return }
            self.navigationItem.prompt = "正在新建 \(keyText)…"
            self.queue.async { [weak self] in
                guard let self = self else { return }
                do {
                    _ = try self.store.create(keyText: keyText, documents: documents, overwrite: false)
                    DispatchQueue.main.async {
                        self.navigationItem.prompt = "已新建 \(keyText)"
                        self.loadRecords()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.navigationItem.prompt = nil
                        self.showError(error, title: "新建元数据失败")
                    }
                }
            }
        }
    }

    private func promptRename(_ record: MetadataNBTRecord, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "重命名元数据键",
            message: "只修改 LevelDB 键名，NBT 值会逐字节保留。支持固定元数据键与 map_* 地图键。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = record.keyText
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { completion(false); return }
            do {
                let target = try MetadataNBTStore.validatedKeyText(alert?.textFields?.first?.text ?? "")
                if target == record.keyText { completion(true); return }
                if self.allRecords.contains(where: { $0.keyText == target && $0.key != record.key }) {
                    self.confirmRenameReplacing(record, target: target, completion: completion)
                } else {
                    self.performRename(record, target: target, overwrite: false, completion: completion)
                }
            } catch {
                completion(false)
                self.showError(error, title: "重命名失败")
            }
        })
        present(alert, animated: true)
    }

    private func confirmRenameReplacing(_ record: MetadataNBTRecord, target: String, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "替换同名元数据？",
            message: "“\(target)”已经存在。继续会用当前记录的原始 NBT 值替换目标记录，并删除“\(record.keyText)”。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "替换并重命名", style: .destructive) { [weak self] _ in
            self?.performRename(record, target: target, overwrite: true, completion: completion)
        })
        present(alert, animated: true)
    }

    private func performRename(_ record: MetadataNBTRecord, target: String, overwrite: Bool, completion: @escaping (Bool) -> Void) {
        navigationItem.prompt = "正在重命名元数据…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.store.rename(record: record, to: target, overwrite: overwrite)
                DispatchQueue.main.async {
                    completion(true)
                    self.navigationItem.prompt = "已重命名为 \(target)"
                    self.loadRecords()
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false)
                    self.navigationItem.prompt = nil
                    self.showError(error, title: "重命名元数据失败")
                }
            }
        }
    }

    private func confirmDelete(_ record: MetadataNBTRecord, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "删除世界元数据？",
            message: "将从 LevelDB 删除“\(record.keyText)”及其全部 NBT 数据。此操作无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { completion(false); return }
            self.queue.async { [weak self] in
                guard let self = self else { return }
                do {
                    try self.store.delete(record: record)
                    DispatchQueue.main.async {
                        completion(true)
                        self.loadRecords()
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(false)
                        self.showError(error, title: "删除元数据失败")
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isBatchSelecting, shownRecords.indices.contains(indexPath.row) else { return nil }
        let record = shownRecords[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            self?.confirmDelete(record, completion: done)
        }
        let rename = UIContextualAction(style: .normal, title: "重命名") { [weak self] _, _, done in
            self?.promptRename(record, completion: done)
        }
        rename.backgroundColor = .systemOrange
        let copyKey = UIContextualAction(style: .normal, title: "复制键") { _, _, done in
            UIPasteboard.general.string = record.keyText
            done(true)
        }
        copyKey.backgroundColor = .systemBlue
        let configuration = UISwipeActionsConfiguration(actions: [delete, rename, copyKey])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    // MARK: - Batch operations

    @objc private func beginBatchSelection() {
        guard !shownRecords.isEmpty else { return }
        isBatchSelecting = true
        batchSelectedKeys.removeAll()
        tableView.reloadData()
        updateBatchNavigationItems()
    }

    @objc private func cancelBatchSelection() {
        isBatchSelecting = false
        batchSelectedKeys.removeAll()
        tableView.reloadData()
        configureNavigationItems()
        applyFilter()
    }

    @objc private func toggleBatchSelectAll() {
        let visible = Set(shownRecords.map(\.key))
        if !visible.isEmpty, visible.isSubset(of: batchSelectedKeys) {
            batchSelectedKeys.subtract(visible)
        } else {
            batchSelectedKeys.formUnion(visible)
        }
        tableView.reloadData()
        updateBatchNavigationItems()
    }

    private var batchSelectedRecords: [MetadataNBTRecord] {
        allRecords.filter { batchSelectedKeys.contains($0.key) }
    }

    @objc private func copyBatchKeys() {
        let records = batchSelectedRecords
        guard !records.isEmpty else { return }
        UIPasteboard.general.string = records.map(\.keyText).joined(separator: "\n")
        updateBatchNavigationItems(message: "已复制 \(records.count) 个元数据键名")
    }

    @objc private func promptBatchRename() {
        let records = batchSelectedRecords
        guard !records.isEmpty else { return }
        let alert = UIAlertController(
            title: "批量重命名元数据",
            message: "新键名 = 前缀 +（原键名执行区分大小写的查找替换）+ 后缀。查找为空时只添加前/后缀。所有结果仍必须是固定元数据键或 map_*。",
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = "查找文本（可留空）"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        alert.addTextField { $0.placeholder = "替换为（可留空）"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        alert.addTextField { $0.placeholder = "前缀（可留空）"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        alert.addTextField { $0.placeholder = "后缀（可留空）"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "预览并重命名", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let fields = alert?.textFields ?? []
            let find = fields.indices.contains(0) ? (fields[0].text ?? "") : ""
            let replace = fields.indices.contains(1) ? (fields[1].text ?? "") : ""
            let prefix = fields.indices.contains(2) ? (fields[2].text ?? "") : ""
            let suffix = fields.indices.contains(3) ? (fields[3].text ?? "") : ""
            if find.isEmpty && prefix.isEmpty && suffix.isEmpty {
                self.showError(MCBEEditorError.malformedData("请至少输入查找文本、前缀或后缀之一"), title: "无法批量重命名")
                return
            }
            let renames = records.map { record -> MetadataNBTRename in
                let middle = find.isEmpty ? record.keyText : record.keyText.replacingOccurrences(of: find, with: replace)
                return MetadataNBTRename(record: record, newKeyText: prefix + middle + suffix)
            }
            do {
                for rename in renames { _ = try MetadataNBTStore.validatedKeyText(rename.newKeyText) }
                let changes = renames.filter { $0.newKeyText != $0.record.keyText }
                guard !changes.isEmpty else {
                    throw MCBEEditorError.malformedData("当前规则不会改变任何所选元数据键")
                }
                let sample = changes.prefix(5).map { "\($0.record.keyText) → \($0.newKeyText)" }.joined(separator: "\n")
                let more = changes.count > 5 ? "\n…另有 \(changes.count - 5) 项" : ""
                self.confirmBatchRename(renames, message: sample + more)
            } catch {
                self.showError(error, title: "无法批量重命名")
            }
        })
        present(alert, animated: true)
    }

    private func confirmBatchRename(_ renames: [MetadataNBTRename], message: String) {
        let alert = UIAlertController(
            title: "确认批量重命名？",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.navigationItem.prompt = "正在批量重命名…"
            self.queue.async { [weak self] in
                guard let self = self else { return }
                do {
                    try self.store.renameBatch(renames)
                    DispatchQueue.main.async {
                        let count = renames.filter { $0.newKeyText != $0.record.keyText }.count
                        self.isBatchSelecting = false
                        self.batchSelectedKeys.removeAll()
                        self.configureNavigationItems()
                        self.navigationItem.prompt = "已重命名 \(count) 项元数据"
                        self.loadRecords()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showError(error, title: "批量重命名失败")
                        self.updateBatchNavigationItems()
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    @objc private func deleteBatchSelection() {
        let records = batchSelectedRecords
        guard !records.isEmpty else { return }
        let alert = UIAlertController(
            title: "删除所选世界元数据？",
            message: "将一次删除 \(records.count) 个 LevelDB 元数据键及其全部 NBT 数据。此操作无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.navigationItem.prompt = "正在批量删除…"
            self.queue.async { [weak self] in
                guard let self = self else { return }
                do {
                    let count = try self.store.delete(records: records)
                    DispatchQueue.main.async {
                        self.isBatchSelecting = false
                        self.batchSelectedKeys.removeAll()
                        self.configureNavigationItems()
                        self.navigationItem.prompt = "已删除 \(count) 项元数据"
                        self.loadRecords()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showError(error, title: "批量删除元数据失败")
                        self.updateBatchNavigationItems()
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    private func updateBatchNavigationItems(message: String? = nil) {
        guard isBatchSelecting else { return }
        let visible = Set(shownRecords.map(\.key))
        let allSelected = !visible.isEmpty && visible.isSubset(of: batchSelectedKeys)
        let cancel = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelBatchSelection))
        let selectAll = UIBarButtonItem(title: allSelected ? "取消全选" : "全选", style: .plain, target: self, action: #selector(toggleBatchSelectAll))
        let copy = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(copyBatchKeys))
        copy.accessibilityLabel = "复制所选元数据键名"
        let rename = UIBarButtonItem(title: "重命名", style: .plain, target: self, action: #selector(promptBatchRename))
        let delete = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(deleteBatchSelection))
        delete.tintColor = .systemRed
        let enabled = !batchSelectedKeys.isEmpty
        copy.isEnabled = enabled
        rename.isEnabled = enabled
        delete.isEnabled = enabled
        navigationItem.rightBarButtonItems = [delete, rename, copy, selectAll, cancel]
        navigationItem.prompt = message ?? "批量选择：已选择 \(batchSelectedKeys.count) 项元数据"
    }
}

final class MetadataNBTRecordViewController: UITableViewController, UISearchResultsUpdating {
    private var originalRecord: MetadataNBTRecord
    private let store: MetadataNBTStore
    private let onSave: () -> Void
    private var roots: [ConsecutiveNBTRecord]
    private var displayedIndices = [Int]()
    private var dirty = false
    private let searchController = UISearchController(searchResultsController: nil)
    private lazy var exitGuard = UnsavedNBTExitGuard(
        controller: self,
        isDirty: { [weak self] in self?.dirty ?? false },
        saveChanges: { [weak self] in self?.saveChangesForExit() ?? false }
    )
    private var isBatchSelecting = false
    private var batchSelectedIndices = Set<Int>()
    private let viewedItems = ViewedItemTracker()

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
        searchController.searchBar.placeholder = "搜索根标签名、标签值或标签类型"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        configureNavigationItems()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(worldDidChange),
            name: WorldSession.worldDidChangeNotification,
            object: store.worldSession
        )
        rebuild()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func worldDidChange() {
        guard !dirty else {
            navigationItem.prompt = "世界已被命令修改；当前未保存内容仍保留，退出或保存后再刷新。"
            return
        }
        let key = originalRecord.key
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let refreshed = try? self.store.record(for: key)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.dirty else { return }
                guard let refreshed = refreshed, let roots = refreshed.roots else {
                    self.navigationItem.prompt = "该元数据记录已被命令删除或无法重新读取。"
                    return
                }
                self.originalRecord = refreshed
                self.roots = roots
                self.viewedItems.reset()
                self.rebuild()
            }
        }
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
        displayedIndices = NBTTreeRows.searchDocuments(roots.map(\.document), query: query)
        batchSelectedIndices.formIntersection(Set(roots.indices))
        navigationItem.prompt = "\(originalRecord.keyText)\(dirty ? " · 未保存" : "")"
        exitGuard.synchronize()
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
        let key = String(index)
        if isBatchSelecting {
            ViewedListSupport.clearAccessory(cell)
            cell.accessoryType = batchSelectedIndices.contains(index) ? .checkmark : .none
        } else {
            ViewedListSupport.configure(
                cell: cell,
                isViewed: viewedItems.contains(key),
                clearAction: { [weak self] in
                    guard let self = self else { return }
                    ViewedListSupport.presentClearConfirmation(from: self) { [weak self] in
                        guard let self = self else { return }
                        self.viewedItems.clear(key)
                        self.tableView.reloadData()
                    }
                }
            )
        }
        cell.mcbe_enableCompactText()
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
        viewedItems.mark(String(index))
        tableView.reloadRows(at: [indexPath], with: .none)
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
            showError(MCBEEditorError.unsupported("元数据至少需要保留一个 NBT 根标签。"), title: "无法删除全部根标签")
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

    @objc private func save() { _ = saveChangesForExit() }

    private func saveChangesForExit() -> Bool {
        guard dirty else { return true }
        do {
            try store.save(record: originalRecord, roots: roots)
            dirty = false
            rebuild()
            onSave()
            navigationItem.prompt = "已保存 \(originalRecord.keyText)"
            return true
        } catch {
            showError(error, title: "保存元数据失败")
            return false
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
