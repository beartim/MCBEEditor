import UIKit
import MobileCoreServices

final class StructureNBTListViewController: UITableViewController, UISearchResultsUpdating, UIDocumentPickerDelegate {
    private let session: WorldSession
    private let store: StructureNBTStore
    private let queue = DispatchQueue(label: "com.wzn.blocktopograph.structure-nbt", qos: .userInitiated)
    private let searchController = UISearchController(searchResultsController: nil)
    private var allRecords = [StructureNBTRecord]()
    private var shownRecords = [StructureNBTRecord]()
    private var loadGeneration = 0

    init(session: WorldSession) {
        self.session = session
        self.store = StructureNBTStore(session: session)
        super.init(style: .insetGrouped)
        title = "结构 NBT"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索结构名称、键、尺寸或原点"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(loadRecords)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(importStructure))
        ]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(worldDidChange),
            name: WorldSession.worldDidChangeNotification,
            object: session
        )
        loadRecords()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func worldDidChange() { loadRecords() }

    @objc private func loadRecords() {
        loadGeneration += 1
        let generation = loadGeneration
        navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }
        navigationItem.prompt = "正在读取已保存的结构…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let records = try self.store.records()
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
                    self.allRecords = records
                    self.applyFilter()
                    self.navigationItem.prompt = records.isEmpty ? "未找到 structuretemplate 结构记录" : "共 \(records.count) 个已保存结构"
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.loadGeneration else { return }
                    self.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
                    self.navigationItem.prompt = nil
                    self.showError(error, title: "读取结构 NBT 失败")
                }
            }
        }
    }

    @objc private func importStructure() {
        let picker = UIDocumentPickerViewController(
            documentTypes: [kUTTypeItem as String],
            in: .import
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let ext = url.pathExtension.lowercased()
        guard ext == "nbt" || ext == "mcstructure" || ext == "json" else {
            showError(
                BlocktopographError.unsupported("请选择 .nbt、.mcstructure 或 .json 文件"),
                title: "无法导入结构"
            )
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let sourceData = try Data(contentsOf: url)
            let data: Data
            if ext == "json" {
                let documents = try NBTJSONCodec.decode(sourceData)
                guard documents.count == 1, let document = documents.first else {
                    throw BlocktopographError.unsupported("结构 JSON 必须只包含一个 NBT 根标签")
                }
                data = try BedrockNBTCodec.encode(document, encoding: .bigEndian)
            } else {
                data = sourceData
            }
            promptForStructureName(data: data, suggestedName: url.deletingPathExtension().lastPathComponent)
        } catch {
            showError(error, title: "读取结构文件失败")
        }
    }

    private func promptForStructureName(data: Data, suggestedName: String) {
        let alert = UIAlertController(
            title: "指定结构名称",
            message: "名称将用于世界 LevelDB 的 structuretemplate 记录。可使用 namespace:name 格式。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = suggestedName
            field.placeholder = "结构名称"
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let name = alert?.textFields?.first?.text ?? ""
            self.checkAndImportStructure(data: data, name: name)
        })
        present(alert, animated: true)
    }

    private func checkAndImportStructure(data: Data, name: String) {
        let cleanName = store.normalizedStructureName(name)
        guard !cleanName.isEmpty else {
            showError(BlocktopographError.malformedData("结构名称不能为空"), title: "无法导入结构")
            return
        }
        navigationItem.prompt = "正在检查结构文件…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let exists = try self.store.containsStructure(named: cleanName)
                DispatchQueue.main.async {
                    if exists {
                        let alert = UIAlertController(
                            title: "替换同名结构？",
                            message: "世界中已存在“\(cleanName)”。继续将覆盖原结构。",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                        alert.addAction(UIAlertAction(title: "替换", style: .destructive) { [weak self] _ in
                            self?.performImport(data: data, name: cleanName, overwrite: true)
                        })
                        self.present(alert, animated: true)
                    } else {
                        self.performImport(data: data, name: cleanName, overwrite: false)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.navigationItem.prompt = nil
                    self.showError(error, title: "无法检查结构名称")
                }
            }
        }
    }

    private func performImport(data: Data, name: String, overwrite: Bool) {
        navigationItem.prompt = "正在导入结构…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try self.store.importStructure(data: data, named: name, overwrite: overwrite)
                DispatchQueue.main.async {
                    self.navigationItem.prompt = "结构“\(name)”已导入"
                    self.loadRecords()
                    if result.convertedFromJava {
                        let lossyText = result.lossyPaletteEntryCount > 0
                            ? "；\(result.lossyPaletteEntryCount) 个调色板条目存在状态降级或按参考转换为空气"
                            : ""
                        let alert = UIAlertController(
                            title: "Java 结构转换完成",
                            message: "已转换为游戏可读取的 Bedrock mcstructure。写入 \(result.placedBlockCount) 个方块、\(result.paletteEntryCount) 个调色板条目\(lossyText)。按照参考转换方案，实体、水层和高级方块实体数据不会被带入。",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.navigationItem.prompt = nil
                    self.showError(error, title: "导入结构失败")
                }
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) { applyFilter() }

    private func applyFilter() {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        shownRecords = allRecords.filter { record in
            query.isEmpty ||
            record.displayName.lowercased().contains(query) ||
            record.keyText.lowercased().contains(query) ||
            record.detailDescription.lowercased().contains(query)
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shownRecords.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Java .nbt 或结构 JSON 会先转换为游戏可读取的 Bedrock mcstructure，再以 Little Endian 写入；现有 .mcstructure 会校正索引层长度并规范化编码。也可重命名、删除、导出和完整修改结构 NBT。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = shownRecords[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "StructureNBTCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "StructureNBTCell")
        cell.textLabel?.text = record.displayName
        cell.detailTextLabel?.text = "\(record.detailDescription)\n\(record.keyText)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = UIImage(systemName: record.document == nil ? "exclamationmark.triangle" : "square.3.layers.3d")
        cell.imageView?.tintColor = record.document == nil ? .systemOrange : .systemBlue
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = shownRecords[indexPath.row]
        if record.document != nil {
            let controller = StructureNBTEditorViewController(
                record: record,
                store: store,
                onSave: { [weak self] in self?.loadRecords() }
            )
            navigationController?.pushViewController(controller, animated: true)
        } else {
            let controller = DatabaseValueViewController(
                title: record.displayName,
                data: record.rawData,
                editable: false
            )
            controller.navigationItem.prompt = record.decodeError
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard shownRecords.indices.contains(indexPath.row) else { return nil }
        let record = shownRecords[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            self.confirmDelete(record, completion: completion)
        }
        let rename = UIContextualAction(style: .normal, title: "重命名") { [weak self] _, _, completion in
            self?.promptRename(record, completion: completion)
        }
        rename.backgroundColor = .systemOrange
        let export = UIContextualAction(style: .normal, title: "导出") { [weak self] _, sourceView, completion in
            self?.export(record, sourceView: sourceView)
            completion(true)
        }
        export.backgroundColor = .systemGreen
        let copyKey = UIContextualAction(style: .normal, title: "复制键") { _, _, completion in
            UIPasteboard.general.string = record.keyText
            completion(true)
        }
        copyKey.backgroundColor = .systemBlue
        let configuration = UISwipeActionsConfiguration(actions: [delete, rename, export, copyKey])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func promptRename(_ record: StructureNBTRecord, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "重命名结构",
            message: "将修改世界 LevelDB 中的 structuretemplate 键。可使用 namespace:name 格式。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = record.displayName
            field.placeholder = "结构名称"
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { completion(false); return }
            let name = alert?.textFields?.first?.text ?? ""
            let clean = self.store.normalizedStructureName(name)
            guard !clean.isEmpty else {
                completion(false)
                self.showError(BlocktopographError.malformedData("结构名称不能为空"), title: "重命名失败")
                return
            }
            self.checkAndRename(record, to: clean, completion: completion)
        })
        present(alert, animated: true)
    }

    private func checkAndRename(_ record: StructureNBTRecord, to name: String, completion: @escaping (Bool) -> Void) {
        navigationItem.prompt = "正在检查结构名称…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                if self.store.isSameStructure(record, named: name) {
                    DispatchQueue.main.async {
                        self.navigationItem.prompt = nil
                        completion(true)
                    }
                    return
                }
                let exists = try self.store.containsStructure(named: name)
                DispatchQueue.main.async {
                    self.navigationItem.prompt = nil
                    if exists {
                        let alert = UIAlertController(
                            title: "替换同名结构？",
                            message: "世界中已存在“\(name)”。继续会用当前结构替换它，并删除原名称。",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
                        alert.addAction(UIAlertAction(title: "替换并重命名", style: .destructive) { [weak self] _ in
                            self?.performRename(record, to: name, overwrite: true, completion: completion)
                        })
                        self.present(alert, animated: true)
                    } else {
                        self.performRename(record, to: name, overwrite: false, completion: completion)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.navigationItem.prompt = nil
                    completion(false)
                    self.showError(error, title: "重命名失败")
                }
            }
        }
    }

    private func performRename(_ record: StructureNBTRecord, to name: String, overwrite: Bool, completion: @escaping (Bool) -> Void) {
        navigationItem.prompt = "正在重命名结构…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.store.rename(record: record, to: name, overwrite: overwrite)
                DispatchQueue.main.async {
                    completion(true)
                    self.navigationItem.prompt = "结构已重命名为“\(name)”"
                    self.loadRecords()
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false)
                    self.navigationItem.prompt = nil
                    self.showError(error, title: "重命名失败")
                }
            }
        }
    }

    private func confirmDelete(_ record: StructureNBTRecord, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "删除结构？",
            message: "将从世界 LevelDB 删除“\(record.displayName)”。此操作无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { completion(false); return }
            self.queue.async {
                do {
                    try self.store.delete(record: record)
                    DispatchQueue.main.async {
                        completion(true)
                        self.loadRecords()
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(false)
                        self.showError(error, title: "删除结构失败")
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    private func export(_ record: StructureNBTRecord, sourceView: UIView) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeFilename(record.displayName) + ".mcstructure")
        do {
            try record.rawData.write(to: url, options: .atomic)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = sourceView
            activity.popoverPresentationController?.sourceRect = sourceView.bounds
            present(activity, animated: true)
        } catch {
            showError(error, title: "导出结构失败")
        }
    }

    private func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "structure" : String(cleaned.prefix(120))
    }
}
