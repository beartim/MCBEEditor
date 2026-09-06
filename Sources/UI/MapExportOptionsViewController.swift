import UIKit

enum MapImageExportScope: Int, CaseIterable {
    case selectedRegion
    case currentRegion
    case loadedDimension

    var displayName: String {
        switch self {
        case .selectedRegion: return "当前框选区域"
        case .currentRegion: return "当前地图区域"
        case .loadedDimension: return "当前维度全部已加载区域"
        }
    }
}

enum MapUngeneratedChunkDisplayMode: Int, CaseIterable {
    case transparent
    case air
    case texture

    var displayName: String {
        switch self {
        case .transparent: return "透明"
        case .air: return "空气"
        case .texture: return "纹理"
        }
    }
}

struct MapImageExportLayers {
    var entities: Bool
    var blockEntities: Bool
    var hardcodedSpawners: Bool
    var villages: Bool
    var spawnPoints: Bool
    var ungeneratedDisplay: MapUngeneratedChunkDisplayMode
}

final class MapExportOptionsViewController: UITableViewController {
    var onExport: ((MapImageExportScope, MapImageExportLayers) -> Void)?

    private var scope: MapImageExportScope
    private let availableScopes: [MapImageExportScope]
    private var layers: MapImageExportLayers

    init(layers: MapImageExportLayers, hasSelectedRegion: Bool = false) {
        self.layers = layers
        self.availableScopes = MapImageExportScope.allCases.filter { $0 != .selectedRegion || hasSelectedRegion }
        self.scope = hasSelectedRegion ? .selectedRegion : .currentRegion
        super.init(style: .insetGrouped)
        title = "导出地图图片"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "导出", style: .done, target: self, action: #selector(exportMap))
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return availableScopes.count
        case 1: return 5
        default: return MapUngeneratedChunkDisplayMode.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "导出范围"
        case 1: return "附加地图对象图层"
        default: return "未生成区块显示"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "框选模式下可直接导出当前精确框选范围；“全部已加载区域”会按当前维度已有区块的外接范围生成图片，跨度较大时会自动降低输出比例以控制内存。"
        case 2:
            return "“透明”会让未生成区块在 PNG 中保持透明；“空气”按空气底色导出；“纹理”会为未生成区块叠加固定密度的纹理。"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MapExportOption") ?? UITableViewCell(style: .default, reuseIdentifier: "MapExportOption")
        switch indexPath.section {
        case 0:
            let value = availableScopes[indexPath.row]
            cell.textLabel?.text = value.displayName
            cell.accessoryType = value == scope ? .checkmark : .none
        case 1:
            let values: [(String, Bool)] = [
                ("实体", layers.entities),
                ("方块实体", layers.blockEntities),
                ("HardcodedSpawners", layers.hardcodedSpawners),
                ("村庄", layers.villages),
                ("出生点", layers.spawnPoints)
            ]
            cell.textLabel?.text = values[indexPath.row].0
            cell.accessoryType = values[indexPath.row].1 ? .checkmark : .none
        default:
            let mode = MapUngeneratedChunkDisplayMode.allCases[indexPath.row]
            cell.textLabel?.text = mode.displayName
            cell.accessoryType = mode == layers.ungeneratedDisplay ? .checkmark : .none
        }
        cell.mcbe_enableCompactText()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0:
            scope = availableScopes[indexPath.row]
        case 1:
            switch indexPath.row {
            case 0: layers.entities.toggle()
            case 1: layers.blockEntities.toggle()
            case 2: layers.hardcodedSpawners.toggle()
            case 3: layers.villages.toggle()
            case 4: layers.spawnPoints.toggle()
            default: break
            }
        default:
            layers.ungeneratedDisplay = MapUngeneratedChunkDisplayMode.allCases[indexPath.row]
        }
        tableView.reloadData()
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func exportMap() {
        let callback = onExport
        dismiss(animated: true) { callback?(self.scope, self.layers) }
    }
}
