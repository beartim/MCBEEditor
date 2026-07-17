import UIKit

enum MapImageExportScope: Int, CaseIterable {
    case currentRegion
    case loadedDimension

    var displayName: String {
        switch self {
        case .currentRegion: return "当前地图区域"
        case .loadedDimension: return "当前维度全部已加载区域"
        }
    }
}

struct MapImageExportLayers {
    var entities: Bool
    var blockEntities: Bool
    var hardcodedSpawners: Bool
    var villages: Bool
    var spawnPoints: Bool
}

final class MapExportOptionsViewController: UITableViewController {
    var onExport: ((MapImageExportScope, MapImageExportLayers) -> Void)?

    private var scope: MapImageExportScope = .currentRegion
    private var layers: MapImageExportLayers

    init(layers: MapImageExportLayers) {
        self.layers = layers
        super.init(style: .insetGrouped)
        title = "导出地图图片"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "导出", style: .done, target: self, action: #selector(exportMap))
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? MapImageExportScope.allCases.count : 5
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "导出范围" : "附加地图对象图层"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return "“全部已加载区域”会按当前维度已有区块的外接范围生成图片；跨度较大时会自动降低输出比例以控制内存。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MapExportOption") ?? UITableViewCell(style: .default, reuseIdentifier: "MapExportOption")
        if indexPath.section == 0 {
            let value = MapImageExportScope.allCases[indexPath.row]
            cell.textLabel?.text = value.displayName
            cell.accessoryType = value == scope ? .checkmark : .none
        } else {
            let values: [(String, Bool)] = [
                ("实体", layers.entities),
                ("方块实体", layers.blockEntities),
                ("HardcodedSpawners", layers.hardcodedSpawners),
                ("村庄", layers.villages),
                ("出生点", layers.spawnPoints)
            ]
            cell.textLabel?.text = values[indexPath.row].0
            cell.accessoryType = values[indexPath.row].1 ? .checkmark : .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            scope = MapImageExportScope.allCases[indexPath.row]
        } else {
            switch indexPath.row {
            case 0: layers.entities.toggle()
            case 1: layers.blockEntities.toggle()
            case 2: layers.hardcodedSpawners.toggle()
            case 3: layers.villages.toggle()
            case 4: layers.spawnPoints.toggle()
            default: break
            }
        }
        tableView.reloadData()
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func exportMap() {
        let callback = onExport
        dismiss(animated: true) { callback?(self.scope, self.layers) }
    }
}
