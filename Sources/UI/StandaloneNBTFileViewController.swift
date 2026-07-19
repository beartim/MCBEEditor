import UIKit

final class StandaloneNBTFileViewController: UITableViewController, UISearchResultsUpdating {
    private let file: StandaloneNBTFile
    private let searchController = UISearchController(searchResultsController: nil)
    private var displayedIndices = [Int]()
    private var presentConversionWhenVisible: Bool
    private var isBatchSelecting = false
    private var batchSelectedIndices = Set<Int>()

    init(file: StandaloneNBTFile, presentConversionWhenVisible: Bool = false) {
        self.file = file
        self.presentConversionWhenVisible = presentConversionWhenVisible
        super.init(style: .insetGrouped)
        title = file.originalFilename
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索根名称、名称标签或序号"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        configureNavigationItems()
        rebuildDisplayedIndices()
    }

    private func configureNavigationItems() {
        guard !isBatchSelecting else { return }
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(showExportMenu)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addRootDocument)),
            UIBarButtonItem(title: "选择", style: .plain, target: self, action: #selector(beginBatchSelection))
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if presentConversionWhenVisible {
            presentConversionWhenVisible = false
            showExportMenu()
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        rebuildDisplayedIndices()
    }

    private var query: String {
        searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func rebuildDisplayedIndices() {
        if query.isEmpty {
            displayedIndices = Array(file.documents.indices)
        } else {
            displayedIndices = file.documents.indices.filter { index in
                let document = file.documents[index]
                return String(index).contains(query) ||
                    document.rootName.lowercased().contains(query) ||
                    primaryName(of: document).lowercased().contains(query) ||
                    document.root.summary.lowercased().contains(query)
            }
        }
        batchSelectedIndices.formIntersection(Set(file.documents.indices))
        navigationItem.prompt = "\(file.formatDescription)\(file.dirty ? " · 有未导出的修改" : "")"
        tableView.reloadData()
        updateBatchNavigationItems()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { displayedIndices.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if query.isEmpty { return file.documents.count == 1 ? "NBT 根标签" : "连续 NBT 根标签（\(file.documents.count)）" }
        return "搜索结果（\(displayedIndices.count)）"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if file.storageKind == .consecutive {
            return "支持多个 NBT 根标签连续存储的文件。根标签序号从 0 开始；可新建、修改或重命名，导出时会重新连续编码全部记录。"
        }
        return "点按进入完整 NBT 编辑器；右上角可导出 JSON、三种 NBT 编码或 Bedrock mcstructure。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let index = displayedIndices[indexPath.row]
        let document = file.documents[index]
        let cell = tableView.dequeueReusableCell(withIdentifier: "StandaloneNBTDocumentCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "StandaloneNBTDocumentCell")
        let name = primaryName(of: document)
        cell.textLabel?.text = file.documents.count == 1 ? name : "#\(index)  \(name)"
        cell.detailTextLabel?.text = "根名称：\(document.rootName.isEmpty ? "（空）" : document.rootName) · \(document.root.summary)"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = NBTTagIcon.image(for: document.root.type)
        cell.accessoryType = isBatchSelecting
            ? (batchSelectedIndices.contains(index) ? .checkmark : .none)
            : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let documentIndex = displayedIndices[indexPath.row]
        if isBatchSelecting {
            if batchSelectedIndices.contains(documentIndex) {
                batchSelectedIndices.remove(documentIndex)
            } else {
                batchSelectedIndices.insert(documentIndex)
            }
            tableView.reloadData()
            updateBatchNavigationItems()
            return
        }
        openEditor(documentIndex: documentIndex)
    }

    private func openEditor(documentIndex: Int) {
        guard file.documents.indices.contains(documentIndex) else { return }
        let editor = StandaloneNBTEditorViewController(
            document: file.documents[documentIndex],
            title: primaryName(of: file.documents[documentIndex])
        ) { [weak self] updated in
            guard let self = self, self.file.documents.indices.contains(documentIndex) else { return }
            self.file.documents[documentIndex] = updated
            self.file.dirty = true
            self.rebuildDisplayedIndices()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func addRootDocument() {
        NBTEditingUI.presentCreateRoot(from: self, sourceView: view) { [weak self] documents in
            guard let self = self, !documents.isEmpty else { return }
            self.searchController.searchBar.text = ""
            self.searchController.isActive = false
            self.file.documents.append(contentsOf: documents)
            self.file.dirty = true
            self.rebuildDisplayedIndices()
            let newIndex = self.file.documents.count - documents.count
            if let row = self.displayedIndices.firstIndex(of: newIndex) {
                self.tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: true)
            }
        }
    }

    private func renameRoot(documentIndex: Int) {
        guard file.documents.indices.contains(documentIndex) else { return }
        let currentName = file.documents[documentIndex].rootName
        let alert = UIAlertController(
            title: "重命名 NBT 根标签",
            message: "根名称可以为空。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = currentName
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak self, weak alert] _ in
            guard let self = self, self.file.documents.indices.contains(documentIndex) else { return }
            self.file.documents[documentIndex].rootName = alert?.textFields?.first?.text ?? ""
            self.file.dirty = true
            self.rebuildDisplayedIndices()
        })
        present(alert, animated: true)
    }

    private func deleteRoot(documentIndex: Int) {
        guard file.documents.count > 1, file.documents.indices.contains(documentIndex) else { return }
        let alert = UIAlertController(
            title: "删除 NBT 根标签？",
            message: "将删除序号 #\(documentIndex) 及其全部内容。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self, self.file.documents.indices.contains(documentIndex) else { return }
            self.file.documents.remove(at: documentIndex)
            self.file.dirty = true
            self.rebuildDisplayedIndices()
        })
        present(alert, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isBatchSelecting, displayedIndices.indices.contains(indexPath.row) else { return nil }
        let documentIndex = displayedIndices[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            var actions = [UIAction]()
            actions.append(UIAction(title: "修改", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                self?.openEditor(documentIndex: documentIndex)
            })
            actions.append(UIAction(title: "重命名根标签", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.renameRoot(documentIndex: documentIndex)
            })
            actions.append(UIAction(title: "新建根标签", image: UIImage(systemName: "plus")) { [weak self] _ in
                self?.addRootDocument()
            })
            if self.file.documents.count > 1 {
                actions.append(UIAction(
                    title: "删除根标签",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.deleteRoot(documentIndex: documentIndex)
                })
            }
            return UIMenu(title: "根标签 #\(documentIndex)", children: actions)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isBatchSelecting, displayedIndices.indices.contains(indexPath.row) else { return nil }
        let documentIndex = displayedIndices[indexPath.row]
        let rename = UIContextualAction(style: .normal, title: "重命名") { [weak self] _, _, completion in
            self?.renameRoot(documentIndex: documentIndex)
            completion(true)
        }
        rename.backgroundColor = .systemOrange
        let configuration = UISwipeActionsConfiguration(actions: [rename])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isBatchSelecting, file.documents.count > 1, displayedIndices.indices.contains(indexPath.row) else { return nil }
        let documentIndex = displayedIndices[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            self?.deleteRoot(documentIndex: documentIndex)
            completion(true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
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
        rebuildDisplayedIndices()
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
        let indices = batchSelectedIndices.sorted()
        guard !indices.isEmpty else { return }
        let documents = indices.compactMap { file.documents.indices.contains($0) ? file.documents[$0] : nil }
        NBTEditingUI.copyDocuments(documents, from: self)
        updateBatchNavigationItems(message: "已复制 \(documents.count) 个 NBT 根标签")
    }

    @objc private func exportBatchSelection() {
        let indices = batchSelectedIndices.sorted()
        let documents = indices.compactMap { file.documents.indices.contains($0) ? file.documents[$0] : nil }
        guard !documents.isEmpty else { return }
        NBTExportUI.presentFormatChooser(
            from: self,
            documents: documents,
            baseFilename: baseFilename() + "-selected",
            allowMCStructure: documents.count == 1,
            barButtonItem: navigationItem.rightBarButtonItems?.first
        )
    }

    @objc private func deleteBatchSelection() {
        let indices = batchSelectedIndices.sorted(by: >)
        guard !indices.isEmpty else { return }
        guard file.documents.count - indices.count >= 1 else {
            showError(MCBEEditorError.unsupported("NBT 文件至少需要保留一个根标签。"), title: "无法删除全部根标签")
            return
        }
        let alert = UIAlertController(
            title: "删除所选 NBT 根标签？",
            message: "将删除 \(indices.count) 个根标签及其全部内容。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            for index in indices where self.file.documents.indices.contains(index) {
                self.file.documents.remove(at: index)
            }
            self.file.dirty = true
            self.batchSelectedIndices.removeAll()
            self.rebuildDisplayedIndices()
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

    @objc private func showExportMenu() {
        let sheet = UIAlertController(
            title: "导出与格式转换",
            message: "修改保存在当前会话中。请选择输出格式后通过“文件”或分享菜单保存。支持 JSON 与三种 NBT 编码；压缩输入会导出为未压缩数据。",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: file.originalWasJSON ? "原格式 · JSON NBT" : "原编码 · \(StandaloneNBTFile.description(of: file.originalEncoding))",
            style: .default
        ) { [weak self] _ in
            self?.exportOriginalFormat()
        })
        sheet.addAction(UIAlertAction(title: "JSON NBT", style: .default) { [weak self] _ in
            self?.exportJSON()
        })
        sheet.addAction(UIAlertAction(title: "Little Endian NBT", style: .default) { [weak self] _ in
            self?.exportNBT(encoding: .littleEndian, suffix: "-little-endian")
        })
        sheet.addAction(UIAlertAction(title: "Little Endian VarInt NBT", style: .default) { [weak self] _ in
            self?.exportNBT(encoding: .littleEndianVarInt, suffix: "-little-varint")
        })
        sheet.addAction(UIAlertAction(title: "Big Endian NBT", style: .default) { [weak self] _ in
            self?.exportNBT(encoding: .bigEndian, suffix: "-big-endian")
        })
        sheet.addAction(UIAlertAction(title: "转换为 Bedrock .mcstructure", style: .default) { [weak self] _ in
            self?.exportMCStructure()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(sheet, animated: true)
    }

    private func exportOriginalFormat() {
        let documents = file.documents
        if file.originalWasJSON {
            exportInBackground(filename: safeFilename(baseFilename()) + ".json") {
                try StandaloneNBTFileCodec.encodeJSON(documents)
            }
            return
        }
        let ext = file.originalExtension == "mcstructure" ? "mcstructure" : "nbt"
        let filename = safeFilename(baseFilename()) + "." + ext
        exportInBackground(filename: filename) {
            try StandaloneNBTFileCodec.encode(documents, encoding: self.file.originalEncoding)
        }
    }

    private func exportJSON() {
        let documents = file.documents
        exportInBackground(filename: safeFilename(baseFilename()) + ".json") {
            try StandaloneNBTFileCodec.encodeJSON(documents)
        }
    }

    private func exportNBT(encoding: NBTEncoding, suffix: String) {
        let documents = file.documents
        let filename = safeFilename(baseFilename()) + suffix + ".nbt"
        exportInBackground(filename: filename) {
            try StandaloneNBTFileCodec.encode(documents, encoding: encoding)
        }
    }

    private func exportMCStructure() {
        let documents = file.documents
        let filename = safeFilename(baseFilename()) + ".mcstructure"
        exportInBackground(filename: filename) {
            try StandaloneNBTFileCodec.encodeAsMCStructure(documents).data
        }
    }

    private func exportInBackground(filename: String, producer: @escaping () throws -> Data) {
        let overlay = showBusy("转换并生成文件…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let data = try producer()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    overlay.removeFromSuperview()
                    self.file.dirty = false
                    self.rebuildDisplayedIndices()
                    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    activity.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItems?.first
                    self.present(activity, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self?.showError(error, title: "转换或导出失败")
                }
            }
        }
    }

    private func primaryName(of document: NBTDocument) -> String {
        let candidates = ["name", "Name", "identifier", "id"]
        for key in candidates {
            if let value = document.root.stringValue(named: key), !value.isEmpty { return value }
        }
        if !document.rootName.isEmpty { return document.rootName }
        return "未命名 \(document.root.type.displayName)"
    }

    private func baseFilename() -> String {
        let value = (file.originalFilename as NSString).deletingPathExtension
        return value.isEmpty ? "document" : value
    }

    private func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "document" : String(cleaned.prefix(120))
    }
}
