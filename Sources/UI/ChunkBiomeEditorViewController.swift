import UIKit

/// Structured editor for the biome record owned by one Bedrock chunk.
/// Data3D is exposed as vertical 16-block layers; Data2D variants expose one
/// 16×16 horizontal map. Height-map bytes are preserved but intentionally not
/// modified by this screen.
final class ChunkBiomeEditorViewController: UITableViewController {
    private let session: WorldSession
    private let chunk: ChunkPosition
    private let store: BedrockChunkStore
    private let queue = DispatchQueue(label: "com.wzn.blocktopograph.biome-editor", qos: .userInitiated)
    private var record: BedrockChunkStore.BiomeRecord?
    private var dirty = false
    private lazy var saveButton = UIBarButtonItem(
        barButtonSystemItem: .save,
        target: self,
        action: #selector(confirmSave)
    )
    var onSave: ((String) -> Void)?

    init(session: WorldSession, chunk: ChunkPosition) {
        self.session = session
        self.chunk = chunk
        self.store = BedrockChunkStore(session: session)
        super.init(style: .insetGrouped)
        title = "生物群系"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItems = [
            saveButton,
            UIBarButtonItem(title: "ID 对照", style: .plain, target: self, action: #selector(showBiomeCatalog))
        ]
        saveButton.isEnabled = false
        loadRecord()
    }

    private func loadRecord() {
        let overlay = showBusy("读取区块生物群系…")
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let value = try self.store.biomeRecord(at: self.chunk)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.record = value
                    self.dirty = false
                    self.saveButton.isEnabled = false
                    self.tableView.reloadData()
                    if value == nil {
                        let alert = UIAlertController(
                            title: "没有生物群系记录",
                            message: "该区块没有 Data3D、Data2D 或 Data2DLegacy 记录。纯空气区块和部分特殊区块可能没有可编辑的生物群系数据。",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "读取生物群系失败")
                }
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { record == nil ? 0 : 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let record = record else { return 0 }
        return section == 0 ? 3 : record.document.layers.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "记录信息" : "生物群系层"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        return "点击一层后可按数字 ID、中文名称、identifier 或坐标搜索并修改。Data3D 使用 X-Z-Y 顺序；保存会直接写回世界数据库。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BiomeLayer")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BiomeLayer")
        guard let record = record else { return cell }
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = .secondaryLabel
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "格式"
                cell.detailTextLabel?.text = record.document.format.rawValue
            case 1:
                cell.textLabel?.text = "高度图"
                cell.detailTextLabel?.text = "256 项（保持原值）"
            default:
                cell.textLabel?.text = "区块"
                cell.detailTextLabel?.text = "(\(chunk.x), \(chunk.z)) · \(dimensionName)"
            }
            cell.accessoryType = .none
        } else {
            let layer = record.document.layers[indexPath.row]
            if let baseY = layer.baseY {
                cell.textLabel?.text = "Y \(baseY)…\(baseY + 15)"
            } else {
                cell.textLabel?.text = "16×16 平面"
            }
            if layer.isAbsent {
                cell.detailTextLabel?.text = "未保存的层 · 点击可创建"
            } else {
                let unique = layer.uniqueBiomeIDs
                let preview = unique.prefix(5).map { id in
                    "\(id):\(BedrockBiomeCatalog.displayName(for: id))"
                }.joined(separator: ", ")
                cell.detailTextLabel?.text = "\(layer.coordinateCount) 个位置 · \(unique.count) 种 ID" + (preview.isEmpty ? "" : " · \(preview)")
            }
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1, let record = record else { return }
        let layerIndex = indexPath.row
        let editor = BiomeLayerEditorViewController(layer: record.document.layers[layerIndex])
        editor.onCommit = { [weak self] layer in
            guard let self = self, var current = self.record else { return }
            current.document.layers[layerIndex] = layer
            self.record = current
            self.dirty = true
            self.saveButton.isEnabled = true
            self.tableView.reloadRows(at: [indexPath], with: .automatic)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func showBiomeCatalog() {
        navigationController?.pushViewController(
            BiomeIDPickerViewController(currentID: nil, selectionEnabled: false),
            animated: true
        )
    }

    @objc private func confirmSave() {
        guard dirty, let record = record else { return }
        let alert = UIAlertController(
            title: "保存生物群系？",
            message: "将直接写回 \(record.document.format.rawValue) 记录。请确保 Minecraft 已完全退出。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .destructive) { [weak self] _ in self?.save() })
        present(alert, animated: true)
    }

    private func save() {
        guard let record = record else { return }
        let overlay = showBusy("写入生物群系…")
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.store.saveBiomeRecord(record)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.dirty = false
                    self.saveButton.isEnabled = false
                    let message = "已保存 \(record.document.format.rawValue) 生物群系记录。"
                    self.onSave?(message)
                    self.navigationItem.prompt = message
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "保存生物群系失败")
                }
            }
        }
    }

    private var dimensionName: String {
        BedrockDimension(rawValue: chunk.dimension)?.displayName ?? "维度 \(chunk.dimension)"
    }
}

private final class BiomeLayerEditorViewController: UITableViewController, UISearchResultsUpdating {
    private var layer: BedrockBiomeLayer
    private var visibleIndices = [Int]()
    private let searchController = UISearchController(searchResultsController: nil)
    var onCommit: ((BedrockBiomeLayer) -> Void)?

    init(layer: BedrockBiomeLayer) {
        self.layer = layer
        super.init(style: .plain)
        if let baseY = layer.baseY {
            title = "生物群系 Y \(baseY)…\(baseY + 15)"
        } else {
            title = "生物群系 16×16"
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索 ID、名称、identifier 或坐标"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "整层设置", style: .plain, target: self, action: #selector(fillLayer)),
            UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(commit))
        ]
        definesPresentationContext = true
        rebuildIndices()
    }

    func updateSearchResults(for searchController: UISearchController) { rebuildIndices() }

    private func rebuildIndices() {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        visibleIndices = layer.biomeIDs.indices.filter { index in
            guard !query.isEmpty else { return true }
            let id = layer.biomeIDs[index]
            let name = BedrockBiomeCatalog.displayName(for: id).lowercased()
            let identifier = BedrockBiomeCatalog.identifier(for: id)?.lowercased() ?? ""
            return String(id).contains(query)
                || name.contains(query)
                || identifier.contains(query)
                || layer.coordinateText(for: index).lowercased().contains(query)
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleIndices.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BiomeValue")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BiomeValue")
        let index = visibleIndices[indexPath.row]
        let id = layer.biomeIDs[index]
        cell.textLabel?.text = "ID \(id) · \(BedrockBiomeCatalog.displayName(for: id))"
        let identifier = BedrockBiomeCatalog.identifier(for: id) ?? "未知/自定义"
        cell.detailTextLabel?.text = "\(layer.coordinateText(for: index)) · \(identifier)"
        cell.imageView?.image = UIImage(systemName: "leaf")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let index = visibleIndices[indexPath.row]
        pickBiomeID(current: layer.biomeIDs[index]) { [weak self] value in
            guard let self = self else { return }
            self.layer.biomeIDs[index] = value
            self.layer.isAbsent = false
            self.rebuildIndices()
        }
    }

    @objc private func fillLayer() {
        pickBiomeID(current: layer.biomeIDs.first ?? 0) { [weak self] value in
            guard let self = self else { return }
            self.layer.biomeIDs = Array(repeating: value, count: self.layer.biomeIDs.count)
            self.layer.isAbsent = false
            self.rebuildIndices()
        }
    }

    private func pickBiomeID(current: UInt32, completion: @escaping (UInt32) -> Void) {
        let picker = BiomeIDPickerViewController(currentID: current, selectionEnabled: true)
        picker.onSelect = completion
        navigationController?.pushViewController(picker, animated: true)
    }

    @objc private func commit() {
        onCommit?(layer)
        navigationController?.popViewController(animated: true)
    }
}
