import UIKit
import MobileCoreServices

final class WorldListViewController: UITableViewController, UIDocumentPickerDelegate, UISearchResultsUpdating {
    private enum PickerPurpose {
        case worldFiles
        case worldFolder
        case nbtEdit
        case nbtConvert
    }

    private enum SortMode {
        case importedAt
        case name
    }

    private let store = WorldStore.shared
    private let importer = WorldImportService()
    private let searchController = UISearchController(searchResultsController: nil)
    private var pickerPurpose: PickerPurpose?
    private var sortMode: SortMode = .importedAt

    private var displayedWorlds: [ImportedWorld] {
        let query = searchController.searchBar.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        var worlds = store.worlds
        if !query.isEmpty {
            worlds = worlds.filter {
                $0.name.lowercased().contains(query) ||
                $0.sourceKind.rawValue.lowercased().contains(query)
            }
        }
        switch sortMode {
        case .importedAt:
            worlds.sort { $0.importedAt > $1.importedAt }
        case .name:
            worlds.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return worlds
    }

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Blocktopograph"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(showImporter)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "更多",
            style: .plain,
            target: self,
            action: #selector(showMoreMenu)
        )

        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "搜索已导入世界"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.keyboardDismissMode = .onDrag
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        tableView.reloadData()
    }

    @objc private func showImporter() {
        let sheet = UIAlertController(
            title: "导入 Bedrock 世界",
            message: "iOS 13 对自定义扩展名的识别并不一致，因此世界文件与目录使用独立入口。",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "选择 .mcworld / ZIP 文件", style: .default) { [weak self] _ in
            self?.presentWorldFilePicker()
        })
        sheet.addAction(UIAlertAction(title: "选择世界目录", style: .default) { [weak self] _ in
            self?.presentWorldFolderPicker()
        })
        sheet.addAction(UIAlertAction(title: "扫描 App 文件共享目录", style: .default) { [weak self] _ in
            self?.scanSharedDocuments()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    private func presentWorldFilePicker() {
        pickerPurpose = .worldFiles
        // iOS 13 的部分文件提供程序不会把 .mcworld 映射到 App 声明的自定义 UTI。
        // 使用 public.item 让文件可选，回调后再由导入器严格验证扩展名和世界结构。
        let picker = UIDocumentPickerViewController(
            documentTypes: [kUTTypeItem as String],
            in: .import
        )
        picker.delegate = self
        // iOS 13 的多选模式需要额外确认，容易被误认为点击文件无响应。
        // 单选导入会在点按文件后立即返回；批量导入仍可使用文件共享目录扫描。
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func presentWorldFolderPicker() {
        pickerPurpose = .worldFolder
        let picker = UIDocumentPickerViewController(
            documentTypes: [kUTTypeFolder as String],
            in: .open
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }


    private func presentNBTFilePicker(for purpose: PickerPurpose) {
        pickerPurpose = purpose
        let picker = UIDocumentPickerViewController(
            documentTypes: [kUTTypeItem as String],
            in: .import
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func showMoreMenu() {
        let sheet = UIAlertController(title: "更多", message: nil, preferredStyle: .actionSheet)
        let recentTitle = sortMode == .importedAt ? "✓ 按导入时间排序" : "按导入时间排序"
        let nameTitle = sortMode == .name ? "✓ 按名称排序" : "按名称排序"
        sheet.addAction(UIAlertAction(title: recentTitle, style: .default) { [weak self] _ in
            self?.sortMode = .importedAt
            self?.tableView.reloadData()
        })
        sheet.addAction(UIAlertAction(title: nameTitle, style: .default) { [weak self] _ in
            self?.sortMode = .name
            self?.tableView.reloadData()
        })
        sheet.addAction(UIAlertAction(title: "扫描 App 文件共享目录", style: .default) { [weak self] _ in
            self?.scanSharedDocuments()
        })
        sheet.addAction(UIAlertAction(title: "说明与许可证", style: .default) { [weak self] _ in
            self?.showAbout()
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(sheet, animated: true)
    }

    private func showAbout() {
        let alert = UIAlertController(
            title: "Blocktopograph 1.0.0",
            message: "原生 iOS 13 版。支持 Bedrock 世界、NBT/mcstructure/JSON 文件读取修改、Java 结构转换、连续多根 NBT、地图与 LevelDB 编辑。当前固定版本 1.0.0。导入内容会复制到 App 沙盒。GNU AGPL-3.0-or-later，无任何担保。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "查看许可证", style: .default) { [weak self] _ in
            guard let url = Bundle.main.url(forResource: "AGPL-3.0", withExtension: "txt"),
                  let data = try? Data(contentsOf: url) else { return }
            self?.navigationController?.pushViewController(
                DatabaseValueViewController(title: "GNU AGPL-3.0", data: data, editable: false),
                animated: true
            )
        })
        alert.addAction(UIAlertAction(title: "确定", style: .cancel))
        present(alert, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let purpose = pickerPurpose
        pickerPurpose = nil
        switch purpose {
        case .worldFiles:
            let fileURLs = urls.filter {
                WorldImportService.supportedArchiveExtensions.contains($0.pathExtension.lowercased())
            }
            guard !fileURLs.isEmpty else {
                showError(
                    BlocktopographError.invalidWorld("所选项目不是 .mcworld 或 ZIP 文件。请选择“世界目录”入口导入文件夹。"),
                    title: "无法导入"
                )
                return
            }
            importExternalURLs(fileURLs)
        case .worldFolder:
            importExternalURLs(Array(urls.prefix(1)))
        case .nbtEdit:
            guard let url = urls.first else { return }
            openStandaloneNBTFile(url, presentConversion: false)
        case .nbtConvert:
            guard let url = urls.first else { return }
            openStandaloneNBTFile(url, presentConversion: true)
        case .none:
            handleExternalURLs(urls)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pickerPurpose = nil
    }

    func handleExternalURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let nbtExtensions: Set<String> = ["nbt", "mcstructure", "json"]
        if urls.count == 1, let url = urls.first,
           nbtExtensions.contains(url.pathExtension.lowercased()) {
            openStandaloneNBTFile(url, presentConversion: false)
            return
        }
        importExternalURLs(urls)
    }

    private func openStandaloneNBTFile(_ url: URL, presentConversion: Bool) {
        loadViewIfNeeded()
        let overlay = showBusy("读取并识别 NBT/JSON 格式…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let file = try StandaloneNBTFileCodec.decode(data: data, filename: url.lastPathComponent)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    overlay.removeFromSuperview()
                    let controller = StandaloneNBTFileViewController(
                        file: file,
                        presentConversionWhenVisible: presentConversion
                    )
                    self.navigationController?.pushViewController(controller, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self?.showError(error, title: "无法读取 NBT/JSON 文件")
                }
            }
        }
    }

    func importExternalURL(_ url: URL) {
        handleExternalURLs([url])
    }

    func importExternalURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        loadViewIfNeeded()
        let message = urls.count == 1 ? "复制并验证世界…" : "批量导入 \(urls.count) 个项目…"
        let overlay = showBusy(message)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var imported: [ImportedWorld] = []
            var failures: [String] = []

            for url in urls {
                do {
                    imported.append(try self.importer.importURL(url))
                } catch {
                    failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                overlay.removeFromSuperview()
                self.tableView.reloadData()
                if imported.count == 1 && failures.isEmpty, let world = imported.first {
                    self.open(world)
                    return
                }
                let lines = [
                    "成功导入：\(imported.count)",
                    "失败：\(failures.count)"
                ] + failures.prefix(5)
                let alert = UIAlertController(
                    title: failures.isEmpty ? "导入完成" : "部分项目未导入",
                    message: lines.joined(separator: "\n"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func scanSharedDocuments() {
        do {
            let candidates = try importer.sharedImportCandidates()
            guard !candidates.isEmpty else {
                let alert = UIAlertController(
                    title: "未找到世界",
                    message: "可在“文件”App 的“在我的 iPhone/iPad 上 → Blocktopograph”中放入 .mcworld、ZIP 或完整世界目录，然后再次扫描。",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                present(alert, animated: true)
                return
            }
            let names = candidates.prefix(6).map { "• \($0.lastPathComponent)" }.joined(separator: "\n")
            let alert = UIAlertController(
                title: "发现 \(candidates.count) 个可导入项目",
                message: names,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "全部导入", style: .default) { [weak self] _ in
                self?.importExternalURLs(candidates)
            })
            present(alert, animated: true)
        } catch {
            showError(error, title: "扫描失败")
        }
    }

    private func open(_ world: ImportedWorld) {
        let detail = WorldDetailTabBarController(world: world)
        detail.modalPresentationStyle = .fullScreen
        present(detail, animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            let worlds = displayedWorlds
            return worlds.isEmpty ? 1 : worlds.count
        case 1:
            return 1
        case 2:
            return 5
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            if store.worlds.isEmpty { return "尚未导入世界" }
            if displayedWorlds.isEmpty { return "没有匹配的世界" }
            return "已导入世界（\(displayedWorlds.count)）"
        case 1:
            return "NBT工具"
        case 2:
            return "基岩版数据值"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 1:
            return "无需导入世界即可读取、修改并转换 NBT、mcstructure 和连续多根 NBT 文件。"
        case 2:
            return "无需选择或导入世界即可查询数字 ID。"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "NBTFileToolCell")
                ?? UITableViewCell(style: .subtitle, reuseIdentifier: "NBTFileToolCell")
            cell.textLabel?.text = "NBT/mcstructure/JSON读取修改和转换"
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.text = "自动识别 JSON、字节序、压缩和连续根标签，并支持格式转换"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.image = NBTTagIcon.toolImage()
            cell.imageView?.contentMode = .center
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return cell
        }

        if indexPath.section == 2 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "DataValueCell")
                ?? UITableViewCell(style: .subtitle, reuseIdentifier: "DataValueCell")
            let rows: [(String, String)] = [
                ("实体ID", "实体短数字 ID、identifier 与十六进制值"),
                ("生物群系ID", "生物群系数字 ID、名称与颜色图标"),
                ("状态效果ID", "状态效果数字 ID、名称与十六进制值"),
                ("魔咒ID", "魔咒数字 ID、名称与十六进制值"),
                ("方块ID", "旧版数字 ID、字符串 ID 与十六进制值")
            ]
            cell.textLabel?.text = rows[indexPath.row].0
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.text = rows[indexPath.row].1
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.image = nil
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return cell
        }

        let worlds = displayedWorlds
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorldCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "WorldCell")
        guard !worlds.isEmpty else {
            cell.textLabel?.text = store.worlds.isEmpty
                ? "点击右上角 + 导入 .mcworld 或世界目录"
                : "没有符合搜索条件的世界"
            cell.detailTextLabel?.text = store.worlds.isEmpty
                ? "也可从“文件”直接用 Blocktopograph 打开 .mcworld"
                : "尝试其他关键词"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.textLabel?.textColor = .secondaryLabel
            cell.imageView?.image = UIImage(systemName: "tray")
            cell.accessoryType = .none
            cell.selectionStyle = .none
            return cell
        }

        let world = worlds[indexPath.row]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        cell.textLabel?.text = world.name
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = "\(world.sourceKind == .mcworld ? ".mcworld" : "目录") · \(formatter.string(from: world.importedAt))"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: "cube.transparent")
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            presentNBTFilePicker(for: .nbtEdit)
            return
        }
        if indexPath.section == 2 {
            showBedrockDataValues(row: indexPath.row)
            return
        }
        let worlds = displayedWorlds
        guard worlds.indices.contains(indexPath.row) else { return }
        open(worlds[indexPath.row])
    }

    private func showBedrockDataValues(row: Int) {
        let controller: UIViewController
        switch row {
        case 0:
            controller = BedrockDataValueListViewController(
                title: "实体 ID",
                entries: BedrockDataValueCatalog.entities
            )
        case 1:
            controller = BiomeIDPickerViewController(selectionEnabled: false)
        case 2:
            controller = BedrockDataValueListViewController(
                title: "状态效果 ID",
                entries: BedrockDataValueCatalog.statusEffects
            )
        case 3:
            controller = BedrockDataValueListViewController(
                title: "魔咒 ID",
                entries: BedrockDataValueCatalog.enchantments
            )
        case 4:
            controller = BedrockDataValueListViewController(
                title: "方块 ID",
                entries: BedrockLegacyBlockCatalog.blocks
            )
        default:
            return
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 0 else { return nil }
        let worlds = displayedWorlds
        guard worlds.indices.contains(indexPath.row) else { return nil }
        let world = worlds[indexPath.row]
        let rename = UIContextualAction(style: .normal, title: "重命名") { [weak self] _, _, completion in
            self?.rename(world)
            completion(true)
        }
        rename.backgroundColor = .systemOrange
        return UISwipeActionsConfiguration(actions: [rename])
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 0 else { return nil }
        let worlds = displayedWorlds
        guard worlds.indices.contains(indexPath.row) else { return nil }
        let world = worlds[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            do {
                try self?.store.remove(world)
                self?.tableView.reloadData()
                completion(true)
            } catch {
                self?.showError(error, title: "删除失败")
                completion(false)
            }
        }
        let export = UIContextualAction(style: .normal, title: "导出") { [weak self] _, _, completion in
            self?.export(world)
            completion(true)
        }
        export.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [delete, export])
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == 0 else { return nil }
        let worlds = displayedWorlds
        guard worlds.indices.contains(indexPath.row) else { return nil }
        let world = worlds[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let rename = UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { _ in self?.rename(world) }
            let duplicate = UIAction(title: "创建副本", image: UIImage(systemName: "doc.on.doc")) { _ in self?.duplicate(world) }
            let export = UIAction(title: "导出 .mcworld", image: UIImage(systemName: "square.and.arrow.up")) { _ in self?.export(world) }
            let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirmDelete(world)
            }
            return UIMenu(title: world.name, children: [rename, duplicate, export, delete])
        }
    }

    private func rename(_ world: ImportedWorld) {
        let alert = UIAlertController(title: "重命名世界", message: "名称会同步写入 level.dat 与 levelname.txt。", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = world.name
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let name = alert?.textFields?.first?.text else { return }
            do {
                try self.store.rename(world, to: name)
                self.tableView.reloadData()
            } catch {
                self.showError(error, title: "重命名失败")
            }
        })
        present(alert, animated: true)
    }

    private func duplicate(_ world: ImportedWorld) {
        let overlay = showBusy("复制完整世界…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let copy = try self.store.duplicate(world)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.tableView.reloadData()
                    let alert = UIAlertController(title: "副本已创建", message: copy.name, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "打开", style: .default) { [weak self] _ in self?.open(copy) })
                    alert.addAction(UIAlertAction(title: "稍后", style: .cancel))
                    self.present(alert, animated: true)
                }
            } catch {
                DispatchQueue.main.async { overlay.removeFromSuperview(); self.showError(error, title: "复制失败") }
            }
        }
    }

    private func confirmDelete(_ world: ImportedWorld) {
        let alert = UIAlertController(
            title: "删除“\(world.name)”？",
            message: "会删除 App 沙盒中的世界副本，但不会删除最初导入的文件。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            do {
                try self?.store.remove(world)
                self?.tableView.reloadData()
            } catch {
                self?.showError(error, title: "删除失败")
            }
        })
        present(alert, animated: true)
    }

    private func export(_ world: ImportedWorld) {
        let overlay = showBusy("创建 .mcworld…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let url = try self.importer.exportWorld(world)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    activity.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem
                    self.present(activity, animated: true)
                }
            } catch {
                DispatchQueue.main.async { overlay.removeFromSuperview(); self.showError(error, title: "导出失败") }
            }
        }
    }
}
