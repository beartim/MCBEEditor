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

enum CrossSectionExportAngle: Int, CaseIterable {
    case xPositive
    case xNegative
    case yPositive
    case yNegative
    case zPositive
    case zNegative

    var displayName: String {
        switch self {
        case .xPositive: return "x+"
        case .xNegative: return "x-"
        case .yPositive: return "y+"
        case .yNegative: return "y-"
        case .zPositive: return "z+"
        case .zNegative: return "z-"
        }
    }
}

struct CrossSectionExportConfiguration {
    var minimumX: Int64?
    var minimumZ: Int64?
    var maximumX: Int64?
    var maximumZ: Int64?
    var angle: CrossSectionExportAngle
}

struct MapImageExportLayers {
    var entities: Bool
    var blockEntities: Bool
    var hardcodedSpawners: Bool
    var villages: Bool
    var spawnPoints: Bool
    var grid: Bool
    var ungeneratedDisplay: MapUngeneratedChunkDisplayMode
}

private final class CrossSectionRangeInputCell: UITableViewCell, UITextFieldDelegate {
    var onChange: ((Int64?, Int64?, Int64?, Int64?) -> Void)?

    private let minimumXField = UITextField()
    private let minimumZField = UITextField()
    private let maximumXField = UITextField()
    private let maximumZField = UITextField()
    private let minimumXInfinityButton = UIButton(type: .system)
    private let minimumZInfinityButton = UIButton(type: .system)
    private let maximumXInfinityButton = UIButton(type: .system)
    private let maximumZInfinityButton = UIButton(type: .system)
    private var isUpdatingUI = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.preservesSuperviewLayoutMargins = true

        let row = UIStackView(arrangedSubviews: [
            makeCoordinateGroup(title: "x1", field: minimumXField, infinityButton: minimumXInfinityButton, infinityTitle: "-∞", selector: #selector(setMinimumXInfinity)),
            makeCoordinateGroup(title: "z1", field: minimumZField, infinityButton: minimumZInfinityButton, infinityTitle: "-∞", selector: #selector(setMinimumZInfinity)),
            makeCoordinateGroup(title: "x2", field: maximumXField, infinityButton: maximumXInfinityButton, infinityTitle: "+∞", selector: #selector(setMaximumXInfinity)),
            makeCoordinateGroup(title: "z2", field: maximumZField, infinityButton: maximumZInfinityButton, infinityTitle: "+∞", selector: #selector(setMaximumZInfinity))
        ])
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fillEqually
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 4),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(minimumX: Int64?, minimumZ: Int64?, maximumX: Int64?, maximumZ: Int64?) {
        isUpdatingUI = true
        minimumXField.text = minimumX.map(String.init) ?? "-∞"
        minimumZField.text = minimumZ.map(String.init) ?? "-∞"
        maximumXField.text = maximumX.map(String.init) ?? "+∞"
        maximumZField.text = maximumZ.map(String.init) ?? "+∞"
        isUpdatingUI = false
    }

    private func makeCoordinateGroup(
        title: String,
        field: UITextField,
        infinityButton: UIButton,
        infinityTitle: String,
        selector: Selector
    ) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center

        field.borderStyle = .roundedRect
        field.textAlignment = .center
        field.keyboardType = .numbersAndPunctuation
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 9
        field.clearButtonMode = .whileEditing
        field.delegate = self
        field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        infinityButton.setTitle(infinityTitle, for: .normal)
        infinityButton.setTitleColor(.white, for: .normal)
        infinityButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        infinityButton.backgroundColor = .systemBlue
        infinityButton.layer.cornerRadius = 8
        infinityButton.layer.masksToBounds = true
        infinityButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        infinityButton.addTarget(self, action: selector, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, field, infinityButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 5
        return stack
    }

    @objc private func setMinimumXInfinity() {
        minimumXField.text = "-∞"
        notifyChange()
    }

    @objc private func setMinimumZInfinity() {
        minimumZField.text = "-∞"
        notifyChange()
    }

    @objc private func setMaximumXInfinity() {
        maximumXField.text = "+∞"
        notifyChange()
    }

    @objc private func setMaximumZInfinity() {
        maximumZField.text = "+∞"
        notifyChange()
    }

    @objc private func editingChanged() { notifyChange() }
    func textFieldDidEndEditing(_ textField: UITextField) { notifyChange() }

    private func notifyChange() {
        guard !isUpdatingUI else { return }
        onChange?(
            parseMinimum(text: minimumXField.text),
            parseMinimum(text: minimumZField.text),
            parseMaximum(text: maximumXField.text),
            parseMaximum(text: maximumZField.text)
        )
    }

    private func parseMinimum(text: String?) -> Int64? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "-∞" || trimmed.lowercased() == "-inf" { return nil }
        return Int64(trimmed)
    }

    private func parseMaximum(text: String?) -> Int64? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "+∞" || trimmed == "∞" || trimmed.lowercased() == "+inf" || trimmed.lowercased() == "inf" {
            return nil
        }
        return Int64(trimmed)
    }
}

private final class CrossSectionAngleCell: UITableViewCell {
    var onChange: ((CrossSectionExportAngle) -> Void)?
    private let control = UISegmentedControl(items: CrossSectionExportAngle.allCases.map(\.displayName))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)
        if #available(iOS 13.0, *) {
            control.selectedSegmentTintColor = .systemBlue
        }
        control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 11, weight: .regular)], for: .normal)
        control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 11, weight: .semibold)], for: .selected)
        contentView.addSubview(control)
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 2),
            control.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            control.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -2),
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(angle: CrossSectionExportAngle) {
        control.selectedSegmentIndex = angle.rawValue
    }

    @objc private func selectionChanged() {
        guard let angle = CrossSectionExportAngle(rawValue: control.selectedSegmentIndex) else { return }
        onChange?(angle)
    }
}

final class MapExportOptionsViewController: UITableViewController {
    var onExport: ((MapImageExportScope, MapImageExportLayers, CrossSectionExportConfiguration?) -> Void)?

    private var scope: MapImageExportScope
    private let availableScopes: [MapImageExportScope]
    private var layers: MapImageExportLayers
    private let isCrossSection: Bool
    private var crossSectionConfiguration: CrossSectionExportConfiguration?

    init(
        layers: MapImageExportLayers,
        hasSelectedRegion: Bool = false,
        isCrossSection: Bool = false,
        crossSectionConfiguration: CrossSectionExportConfiguration? = nil
    ) {
        self.layers = layers
        self.isCrossSection = isCrossSection
        self.availableScopes = MapImageExportScope.allCases.filter { $0 != .selectedRegion || hasSelectedRegion }
        self.scope = hasSelectedRegion ? .selectedRegion : .currentRegion
        self.crossSectionConfiguration = crossSectionConfiguration
        super.init(style: .insetGrouped)
        title = "导出地图图片"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "导出", style: .done, target: self, action: #selector(exportMap))
        tableView.keyboardDismissMode = .interactive
    }

    override func numberOfSections(in tableView: UITableView) -> Int { isCrossSection ? 4 : 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isCrossSection {
            switch section {
            case 0: return 1
            case 1: return 1
            case 2: return 5
            default: return MapUngeneratedChunkDisplayMode.allCases.count
            }
        }
        switch section {
        case 0: return availableScopes.count
        case 1: return 6
        default: return MapUngeneratedChunkDisplayMode.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isCrossSection {
            switch section {
            case 0: return "导出范围"
            case 1: return "导出角度"
            case 2: return "附加地图对象图层"
            default: return "未生成子区块显示"
            }
        }
        switch section {
        case 0: return "导出范围"
        case 1: return "附加地图对象图层"
        default: return "未生成区块显示"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if isCrossSection {
            switch section {
            case 0:
                return "两组 (x,z) 分别表示导出范围的两个角点。默认填入当前地图区域范围；四个蓝色无穷按钮分别对应 x1、z1、x2、z2。四个范围均设为无穷时等效于导出当前维度全部已加载区域。"
            case 1:
                return "“+” 表示从正方向向负方向看，“-” 表示从负方向向正方向看。X/Z 模式默认分别使用 x+ 与 z+。"
            case 2:
                return "“网格”默认关闭；导出的 PNG 是否包含区块/子区块网格只由这里的选项决定，不跟随地图页面当前网格开关。"
            case 3:
                return "“透明”让未生成 SubChunk 透明；“空气”使用普通背景；“纹理”为未生成 SubChunk 叠加固定密度纹理。"
            default:
                return nil
            }
        }
        switch section {
        case 0:
            return "框选模式下可直接导出当前精确框选范围；“全部已加载区域”会按当前维度已有区块的外接范围生成图片，跨度较大时会自动降低输出比例以控制内存。"
        case 1:
            return "“网格”默认关闭；导出的 PNG 是否包含区块网格只由这里的选项决定，不跟随地图页面当前网格开关。"
        case 2:
            return "“透明”会让未生成区块在 PNG 中保持透明；“空气”按空气底色导出；“纹理”会为未生成区块叠加固定密度的纹理。"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isCrossSection {
            switch indexPath.section {
            case 0:
                let cell = tableView.dequeueReusableCell(withIdentifier: "CrossSectionRangeInput") as? CrossSectionRangeInputCell
                    ?? CrossSectionRangeInputCell(style: .default, reuseIdentifier: "CrossSectionRangeInput")
                let configuration = crossSectionConfiguration ?? CrossSectionExportConfiguration(
                    minimumX: nil, minimumZ: nil, maximumX: nil, maximumZ: nil, angle: .xPositive)
                cell.configure(
                    minimumX: configuration.minimumX,
                    minimumZ: configuration.minimumZ,
                    maximumX: configuration.maximumX,
                    maximumZ: configuration.maximumZ
                )
                cell.onChange = { [weak self] minimumX, minimumZ, maximumX, maximumZ in
                    guard let self = self else { return }
                    if self.crossSectionConfiguration == nil {
                        self.crossSectionConfiguration = CrossSectionExportConfiguration(
                            minimumX: minimumX,
                            minimumZ: minimumZ,
                            maximumX: maximumX,
                            maximumZ: maximumZ,
                            angle: .xPositive
                        )
                    } else {
                        self.crossSectionConfiguration?.minimumX = minimumX
                        self.crossSectionConfiguration?.minimumZ = minimumZ
                        self.crossSectionConfiguration?.maximumX = maximumX
                        self.crossSectionConfiguration?.maximumZ = maximumZ
                    }
                }
                return cell
            case 1:
                let cell = tableView.dequeueReusableCell(withIdentifier: "CrossSectionAngle") as? CrossSectionAngleCell
                    ?? CrossSectionAngleCell(style: .default, reuseIdentifier: "CrossSectionAngle")
                let angle = crossSectionConfiguration?.angle ?? .xPositive
                cell.configure(angle: angle)
                cell.onChange = { [weak self] angle in
                    guard let self = self else { return }
                    if self.crossSectionConfiguration == nil {
                        self.crossSectionConfiguration = CrossSectionExportConfiguration(
                            minimumX: nil, minimumZ: nil, maximumX: nil, maximumZ: nil, angle: angle)
                    } else {
                        self.crossSectionConfiguration?.angle = angle
                    }
                }
                return cell
            case 2:
                return makeToggleCell(indexPath: indexPath, crossSection: true)
            default:
                return makeUngeneratedCell(indexPath: indexPath)
            }
        }

        switch indexPath.section {
        case 0:
            let cell = reusableOptionCell()
            let value = availableScopes[indexPath.row]
            cell.textLabel?.text = value.displayName
            cell.accessoryType = value == scope ? .checkmark : .none
            return cell
        case 1:
            return makeToggleCell(indexPath: indexPath, crossSection: false)
        default:
            return makeUngeneratedCell(indexPath: indexPath)
        }
    }

    private func reusableOptionCell() -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MapExportOption")
            ?? UITableViewCell(style: .default, reuseIdentifier: "MapExportOption")
        cell.mcbe_enableCompactText()
        return cell
    }

    private func makeToggleCell(indexPath: IndexPath, crossSection: Bool) -> UITableViewCell {
        let cell = reusableOptionCell()
        let values: [(String, Bool)] = crossSection
            ? [
                ("实体", layers.entities),
                ("方块实体", layers.blockEntities),
                ("HardcodedSpawners", layers.hardcodedSpawners),
                ("出生点", layers.spawnPoints),
                ("网格", layers.grid)
            ]
            : [
                ("实体", layers.entities),
                ("方块实体", layers.blockEntities),
                ("HardcodedSpawners", layers.hardcodedSpawners),
                ("村庄", layers.villages),
                ("出生点", layers.spawnPoints),
                ("网格", layers.grid)
            ]
        cell.textLabel?.text = values[indexPath.row].0
        cell.accessoryType = values[indexPath.row].1 ? .checkmark : .none
        return cell
    }

    private func makeUngeneratedCell(indexPath: IndexPath) -> UITableViewCell {
        let cell = reusableOptionCell()
        let mode = MapUngeneratedChunkDisplayMode.allCases[indexPath.row]
        cell.textLabel?.text = mode.displayName
        cell.accessoryType = mode == layers.ungeneratedDisplay ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if isCrossSection {
            switch indexPath.section {
            case 2:
                switch indexPath.row {
                case 0: layers.entities.toggle()
                case 1: layers.blockEntities.toggle()
                case 2: layers.hardcodedSpawners.toggle()
                case 3: layers.spawnPoints.toggle()
                case 4: layers.grid.toggle()
                default: break
                }
                // Do not reload the table here. Reloading an inset-grouped table
                // containing active text fields can reset its estimated layout and
                // unexpectedly jump the export sheet back to the top.
                tableView.cellForRow(at: indexPath)?.accessoryType = currentToggleValue(
                    row: indexPath.row, crossSection: true) ? .checkmark : .none
            case 3:
                layers.ungeneratedDisplay = MapUngeneratedChunkDisplayMode.allCases[indexPath.row]
                refreshVisibleCheckmarks(inSection: 3)
            default:
                break
            }
            return
        }

        switch indexPath.section {
        case 0:
            scope = availableScopes[indexPath.row]
            refreshVisibleCheckmarks(inSection: 0)
        case 1:
            switch indexPath.row {
            case 0: layers.entities.toggle()
            case 1: layers.blockEntities.toggle()
            case 2: layers.hardcodedSpawners.toggle()
            case 3: layers.villages.toggle()
            case 4: layers.spawnPoints.toggle()
            case 5: layers.grid.toggle()
            default: break
            }
            tableView.cellForRow(at: indexPath)?.accessoryType = currentToggleValue(
                row: indexPath.row, crossSection: false) ? .checkmark : .none
        default:
            layers.ungeneratedDisplay = MapUngeneratedChunkDisplayMode.allCases[indexPath.row]
            refreshVisibleCheckmarks(inSection: 2)
        }
    }

    private func currentToggleValue(row: Int, crossSection: Bool) -> Bool {
        if crossSection {
            switch row {
            case 0: return layers.entities
            case 1: return layers.blockEntities
            case 2: return layers.hardcodedSpawners
            case 3: return layers.spawnPoints
            case 4: return layers.grid
            default: return false
            }
        }
        switch row {
        case 0: return layers.entities
        case 1: return layers.blockEntities
        case 2: return layers.hardcodedSpawners
        case 3: return layers.villages
        case 4: return layers.spawnPoints
        case 5: return layers.grid
        default: return false
        }
    }

    private func refreshVisibleCheckmarks(inSection section: Int) {
        guard let visible = tableView.indexPathsForVisibleRows else { return }
        for indexPath in visible where indexPath.section == section {
            guard let cell = tableView.cellForRow(at: indexPath) else { continue }
            if !isCrossSection && section == 0 {
                let value = availableScopes[indexPath.row]
                cell.accessoryType = value == scope ? .checkmark : .none
            } else {
                let value = MapUngeneratedChunkDisplayMode.allCases[indexPath.row]
                cell.accessoryType = value == layers.ungeneratedDisplay ? .checkmark : .none
            }
        }
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func exportMap() {
        view.endEditing(true)
        if isCrossSection {
            if crossSectionConfiguration == nil {
                crossSectionConfiguration = CrossSectionExportConfiguration(
                    minimumX: nil,
                    minimumZ: nil,
                    maximumX: nil,
                    maximumZ: nil,
                    angle: .xPositive
                )
            }
            if let minimumX = crossSectionConfiguration?.minimumX,
               let maximumX = crossSectionConfiguration?.maximumX,
               minimumX > maximumX {
                showRangeError("x1 不能大于 x2")
                return
            }
            if let minimumZ = crossSectionConfiguration?.minimumZ,
               let maximumZ = crossSectionConfiguration?.maximumZ,
               minimumZ > maximumZ {
                showRangeError("z1 不能大于 z2")
                return
            }
        }
        let callback = onExport
        dismiss(animated: true) { callback?(self.scope, self.layers, self.crossSectionConfiguration) }
    }

    private func showRangeError(_ message: String) {
        let alert = UIAlertController(title: "导出范围无效", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
