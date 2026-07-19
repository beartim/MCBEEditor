import UIKit

private enum EntitySpatialFilterMode: Int {
    case all
    case box
    case radius
}

private enum EntitySpatialFilter {
    case all
    case box(minX: Double, maxX: Double, minZ: Double, maxZ: Double, yRange: ClosedRange<Double>?)
    case radius(centerX: Double, centerY: Double?, centerZ: Double, radius: Double)

    func contains(_ position: BedrockWorldObjectPosition?) -> Bool {
        switch self {
        case .all:
            return true
        case .box(let minX, let maxX, let minZ, let maxZ, let yRange):
            guard let position = position else { return false }
            guard position.x >= minX, position.x <= maxX,
                  position.z >= minZ, position.z <= maxZ else { return false }
            return yRange?.contains(position.y) ?? true
        case .radius(let centerX, let centerY, let centerZ, let radius):
            guard let position = position else { return false }
            let dx = position.x - centerX
            let dz = position.z - centerZ
            if let centerY = centerY {
                let dy = position.y - centerY
                return dx * dx + dy * dy + dz * dz <= radius * radius
            }
            return dx * dx + dz * dz <= radius * radius
        }
    }
}

final class EntityBrowserViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UITextFieldDelegate {
    private let session: WorldSession
    private let onLocate: (BedrockWorldObject) -> Void
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let kindControl = UISegmentedControl(items: ["实体", "方块实体"])
    private let dimensionControl = UISegmentedControl(items: ["全部"] + BedrockDimension.allCases.map(\.displayName))
    private let rangeModeControl = UISegmentedControl(items: ["全部", "坐标区域", "半径"])

    private let rectanglePanel = UIStackView()
    private let rectangleX0 = UITextField()
    private let rectangleZ0 = UITextField()
    private let rectangleX1 = UITextField()
    private let rectangleZ1 = UITextField()
    private let rectangleY0 = UITextField()
    private let rectangleY1 = UITextField()
    private let rectangleYSwitch = UISwitch()
    private let rectangleYRow = UIStackView()
    private let rectangleY0Label = UILabel()
    private let rectangleY1Label = UILabel()

    private let radiusPanel = UIStackView()
    private let radiusX = UITextField()
    private let radiusY = UITextField()
    private let radiusZ = UITextField()
    private let radiusValue = UITextField()
    private let radiusYSwitch = UISwitch()
    private let radiusYRow = UIStackView()
    private let radiusYLabel = UILabel()

    private let statusLabel = UILabel()
    private let searchController = UISearchController(searchResultsController: nil)
    private let scanQueue = DispatchQueue(label: "com.wzn.blocktopograph.entity-scan", qos: .userInitiated)
    private lazy var objectStore = BedrockWorldObjectNBTStore(session: session)
    private var allObjects = [BedrockWorldObject]()
    private var shownObjects = [BedrockWorldObject]()
    private var diagnostics = [String]()
    private var scanGeneration = 0
    private var scanSummary = ""

    init(session: WorldSession, onLocate: @escaping (BedrockWorldObject) -> Void) {
        self.session = session
        self.onLocate = onLocate
        super.init(nibName: nil, bundle: nil)
        title = "实体"
        tabBarItem = UITabBarItem(title: "实体", image: UIImage(systemName: "person.3"), tag: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(worldDidChange),
            name: WorldSession.worldDidChangeNotification,
            object: session
        )
        scan()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configureUI() {
        kindControl.selectedSegmentIndex = 0
        // “全部”位于主世界左侧，但默认仍显示所选的主世界全部对象。
        dimensionControl.selectedSegmentIndex = 1
        rangeModeControl.selectedSegmentIndex = EntitySpatialFilterMode.all.rawValue
        kindControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        dimensionControl.addTarget(self, action: #selector(scan), for: .valueChanged)
        rangeModeControl.addTarget(self, action: #selector(rangeModeChanged), for: .valueChanged)
        rectangleYSwitch.isOn = false
        radiusYSwitch.isOn = false
        rectangleYSwitch.addTarget(self, action: #selector(yRangeSwitchChanged), for: .valueChanged)
        radiusYSwitch.addTarget(self, action: #selector(yRangeSwitchChanged), for: .valueChanged)

        let fields = [
            rectangleX0, rectangleZ0, rectangleX1, rectangleZ1, rectangleY0, rectangleY1,
            radiusX, radiusY, radiusZ, radiusValue
        ]
        for field in fields {
            field.borderStyle = .roundedRect
            field.keyboardType = .numbersAndPunctuation
            field.delegate = self
            field.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
            field.textAlignment = .center
            field.clearButtonMode = .whileEditing
            field.widthAnchor.constraint(equalToConstant: 76).isActive = true
            field.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        rectangleX0.placeholder = "X0"; rectangleZ0.placeholder = "Z0"
        rectangleX1.placeholder = "X1"; rectangleZ1.placeholder = "Z1"
        rectangleY0.placeholder = "Y0"; rectangleY1.placeholder = "Y1"
        radiusX.placeholder = "X"; radiusY.placeholder = "Y"; radiusZ.placeholder = "Z"
        radiusValue.placeholder = "半径"
        rectangleX0.text = "-16"; rectangleZ0.text = "-16"
        rectangleX1.text = "16"; rectangleZ1.text = "16"
        rectangleY0.text = "-64"; rectangleY1.text = "320"
        radiusX.text = "0"; radiusY.text = "64"; radiusZ.text = "0"; radiusValue.text = "64"

        configureRectanglePanel()
        configureRadiusPanel()

        let controls = UIStackView(arrangedSubviews: [
            kindControl,
            dimensionControl,
            rangeModeControl,
            rectanglePanel,
            radiusPanel
        ])
        controls.axis = .vertical
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.isUserInteractionEnabled = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showDiagnostics)))

        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索名称、ID、坐标或来源"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(scan)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createObject))
        ]

        view.addSubview(controls)
        view.addSubview(statusLabel)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 7),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        rangeModeChanged()
    }

    private func configureRectanglePanel() {
        rectanglePanel.axis = .vertical
        rectanglePanel.spacing = 6
        rectanglePanel.isLayoutMarginsRelativeArrangement = true
        rectanglePanel.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        rectanglePanel.backgroundColor = .secondarySystemGroupedBackground
        rectanglePanel.layer.cornerRadius = 10

        let first = coordinatePair(title: "起点", xTitle: "X0", xField: rectangleX0, zTitle: "Z0", zField: rectangleZ0)
        let second = coordinatePair(title: "终点", xTitle: "X1", xField: rectangleX1, zTitle: "Z1", zField: rectangleZ1)
        let coordinateRows = UIStackView(arrangedSubviews: [first, second])
        coordinateRows.axis = .vertical
        coordinateRows.spacing = 6
        coordinateRows.setContentHuggingPriority(.required, for: .horizontal)
        coordinateRows.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topArea = UIStackView(arrangedSubviews: [coordinateRows, makeRangeActionGrid()])
        topArea.axis = .horizontal
        topArea.spacing = 14
        topArea.alignment = .fill
        topArea.distribution = .fill

        rectangleY0Label.text = "Y0"
        rectangleY1Label.text = "Y1"
        configureCompactLabel(rectangleY0Label)
        configureCompactLabel(rectangleY1Label)
        rectangleYRow.axis = .horizontal
        rectangleYRow.spacing = 7
        rectangleYRow.alignment = .center
        rectangleYRow.addArrangedSubview(compactLabel("指定 Y 范围"))
        rectangleYRow.addArrangedSubview(rectangleYSwitch)
        rectangleYRow.addArrangedSubview(rectangleY0Label)
        rectangleYRow.addArrangedSubview(rectangleY0)
        rectangleYRow.addArrangedSubview(rectangleY1Label)
        rectangleYRow.addArrangedSubview(rectangleY1)
        rectangleYRow.addArrangedSubview(UIView())

        rectanglePanel.addArrangedSubview(topArea)
        rectanglePanel.addArrangedSubview(rectangleYRow)
    }

    private func configureRadiusPanel() {
        radiusPanel.axis = .vertical
        radiusPanel.spacing = 6
        radiusPanel.isLayoutMarginsRelativeArrangement = true
        radiusPanel.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        radiusPanel.backgroundColor = .secondarySystemGroupedBackground
        radiusPanel.layer.cornerRadius = 10

        let center = coordinatePair(title: "中心", xTitle: "X", xField: radiusX, zTitle: "Z", zField: radiusZ)
        radiusYLabel.text = "中心 Y"
        configureCompactLabel(radiusYLabel)

        let radiusValueRow = UIStackView(arrangedSubviews: [compactLabel("半径"), radiusValue, UIView()])
        radiusValueRow.axis = .horizontal
        radiusValueRow.spacing = 7
        radiusValueRow.alignment = .center

        radiusYRow.axis = .horizontal
        radiusYRow.spacing = 7
        radiusYRow.alignment = .center
        radiusYRow.addArrangedSubview(compactLabel("计算包含 Y"))
        radiusYRow.addArrangedSubview(radiusYSwitch)
        radiusYRow.addArrangedSubview(radiusYLabel)
        radiusYRow.addArrangedSubview(radiusY)
        radiusYRow.addArrangedSubview(UIView())

        // The four action buttons align only with the “中心” and “半径” rows.
        // Keep the optional Y controls on their own full-width row below so
        // enabling them cannot stretch or vertically misalign the button grid.
        let primaryRadiusRows = UIStackView(arrangedSubviews: [center, radiusValueRow])
        primaryRadiusRows.axis = .vertical
        primaryRadiusRows.spacing = 6
        primaryRadiusRows.setContentHuggingPriority(.required, for: .horizontal)
        primaryRadiusRows.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topArea = UIStackView(arrangedSubviews: [primaryRadiusRows, makeRangeActionGrid()])
        topArea.axis = .horizontal
        topArea.spacing = 14
        topArea.alignment = .fill
        topArea.distribution = .fill
        radiusPanel.addArrangedSubview(topArea)
        radiusPanel.addArrangedSubview(radiusYRow)
    }

    private func makeRangeActionGrid() -> UIStackView {
        let selectedBlockPosition = makeRangeActionButton(
            title: "使用选中方块位置",
            action: #selector(useSelectedBlockPosition)
        )
        let selectedObjectPosition = makeRangeActionButton(
            title: "使用选中实体/方块实体位置",
            action: #selector(useSelectedWorldObjectPosition)
        )
        selectedObjectPosition.titleLabel?.adjustsFontSizeToFitWidth = true
        selectedObjectPosition.titleLabel?.minimumScaleFactor = 0.72

        let applyRange = makeRangeActionButton(title: "应用范围", action: #selector(applyRangeFilter))
        let refresh = makeRangeActionButton(title: "重新扫描世界", action: #selector(scan))

        let firstRow = UIStackView(arrangedSubviews: [selectedBlockPosition, selectedObjectPosition])
        firstRow.axis = .horizontal
        firstRow.spacing = 8
        firstRow.distribution = .fillEqually

        let secondRow = UIStackView(arrangedSubviews: [applyRange, refresh])
        secondRow.axis = .horizontal
        secondRow.spacing = 8
        secondRow.distribution = .fillEqually

        let grid = UIStackView(arrangedSubviews: [firstRow, secondRow])
        grid.axis = .vertical
        grid.spacing = 6
        grid.distribution = .fillEqually
        grid.setContentHuggingPriority(.defaultLow, for: .horizontal)
        grid.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return grid
    }

    private func makeRangeActionButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.titleLabel?.numberOfLines = 1
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        button.backgroundColor = .tertiarySystemBackground
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.55).cgColor
        button.clipsToBounds = true
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        return button
    }

    private func coordinatePair(title: String, xTitle: String, xField: UITextField, zTitle: String, zField: UITextField) -> UIStackView {
        let titleLabel = compactLabel(title)
        titleLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let row = UIStackView(arrangedSubviews: [titleLabel, compactLabel(xTitle), xField, compactLabel(zTitle), zField])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        return row
    }

    private func compactLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        configureCompactLabel(label)
        return label
    }

    private func configureCompactLabel(_ label: UILabel) {
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @objc private func useSelectedBlockPosition() {
        guard let coordinate = session.selectedBlockCoordinate else {
            showError(
                BlocktopographError.unsupported("尚未在地图中选中方块。请先打开地图并选择一个具体 Y 高度的方块。"),
                title: "没有选中方块"
            )
            return
        }
        applySelectionCoordinate(coordinate)
    }

    @objc private func useSelectedWorldObjectPosition() {
        guard let coordinate = session.selectedWorldObjectCoordinate else {
            showError(
                BlocktopographError.unsupported("尚未选中带坐标的实体或方块实体。可在地图或实体列表中先选择对象。"),
                title: "没有选中对象"
            )
            return
        }
        applySelectionCoordinate(coordinate)
    }

    private func applySelectionCoordinate(_ coordinate: WorldSelectionCoordinate) {
        let x = format(coordinate.x)
        let y = format(coordinate.y)
        let z = format(coordinate.z)
        radiusX.text = x
        radiusY.text = y
        radiusZ.text = z
        rectangleX0.text = x
        rectangleX1.text = x
        rectangleY0.text = y
        rectangleY1.text = y
        rectangleZ0.text = z
        rectangleZ1.text = z
        var dimensionChanged = false
        if let index = BedrockDimension.allCases.firstIndex(where: { $0.rawValue == coordinate.dimension }) {
            let targetIndex = index + 1
            dimensionChanged = dimensionControl.selectedSegmentIndex != targetIndex
            dimensionControl.selectedSegmentIndex = targetIndex
        }
        if dimensionChanged {
            scan()
        } else {
            applyFilter(showErrors: false)
        }
        navigationItem.prompt = "已使用选中位置：\(coordinate.blockDescription)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.navigationItem.prompt?.hasPrefix("已使用选中位置") == true {
                self?.navigationItem.prompt = nil
            }
        }
    }


    @objc private func createObject() {
        let kind: BedrockWorldObjectKind = kindControl.selectedSegmentIndex == 0 ? .entity : .blockEntity
        let controller = WorldObjectCreationViewController(
            session: session,
            kind: kind,
            onCreate: {}
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func duplicateObject(_ object: BedrockWorldObject) {
        let controller = WorldObjectCreationViewController(
            session: session,
            kind: object.kind,
            template: object,
            onCreate: {}
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func confirmDelete(_ object: BedrockWorldObject) {
        let alert = UIAlertController(
            title: "删除\(object.kind.displayName)？",
            message: "将从世界 LevelDB 删除“\(dataValueDisplayName(for: object))”。现代实体的 actorprefix 和 digp 引用会同步清理。此操作不可撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.deleteObject(object)
        })
        present(alert, animated: true)
    }

    private func deleteObject(_ object: BedrockWorldObject) {
        do {
            try objectStore.delete(object: object)
            session.invalidateAfterExternalChange()
            navigationItem.prompt = "已删除\(object.kind.displayName)：\(dataValueDisplayName(for: object))"
        } catch {
            showError(error, title: "删除\(object.kind.displayName)失败")
        }
    }

    @objc private func worldDidChange() {
        allObjects = []
        shownObjects = []
        tableView.reloadData()
        scan()
    }

    @objc private func scan() {
        view.endEditing(true)
        let dimensions: Set<Int32>?
        let dimensionText: String
        if dimensionControl.selectedSegmentIndex == 0 {
            dimensions = nil
            dimensionText = "全部维度"
        } else {
            let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex - 1]
            dimensions = [dimension.rawValue]
            dimensionText = dimension.displayName
        }

        scanGeneration += 1
        let generation = scanGeneration
        statusLabel.text = "正在扫描\(dimensionText)全部实体与方块实体…"
        navigationItem.rightBarButtonItems?.first?.isEnabled = false

        scanQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let repairedDigestCount = try self.objectStore.repairAppCreatedOverworldActorDigests()
                let scanner = BedrockWorldObjectScanner(database: try self.session.database())
                let result = try scanner.scanAll(
                    dimensions: dimensions,
                    includeEntities: true,
                    includeBlockEntities: true,
                    maximumObjects: 200_000,
                    shouldCancel: { generation != self.scanGeneration }
                )
                DispatchQueue.main.async {
                    guard generation == self.scanGeneration else { return }
                    self.navigationItem.rightBarButtonItems?.first?.isEnabled = true
                    self.allObjects = result.objects
                    self.diagnostics = result.diagnostics
                    let entityCount = result.objects.filter { $0.kind == .entity }.count
                    let blockCount = result.objects.filter { $0.kind == .blockEntity }.count
                    let errors = result.diagnostics.isEmpty ? "" : "；诊断 \(result.diagnostics.count) 条，点按查看"
                    let repaired = repairedDigestCount > 0 ? "；已修复 \(repairedDigestCount) 条旧版错误 digp" : ""
                    self.scanSummary = "\(dimensionText)：实体 \(entityCount)，方块实体 \(blockCount)；摘要 \(result.actorDigestCount)，actor \(result.actorRecordCount)\(repaired)\(errors)"
                    self.applyFilter(showErrors: false)
                }
            } catch {
                DispatchQueue.main.async {
                    guard generation == self.scanGeneration else { return }
                    self.navigationItem.rightBarButtonItems?.first?.isEnabled = true
                    self.statusLabel.text = "扫描失败：\(error.localizedDescription)"
                    self.showError(error, title: "实体扫描失败")
                }
            }
        }
    }

    @objc private func rangeModeChanged() {
        let mode = EntitySpatialFilterMode(rawValue: rangeModeControl.selectedSegmentIndex) ?? .all
        rectanglePanel.isHidden = mode != .box
        radiusPanel.isHidden = mode != .radius
        yRangeSwitchChanged()
        applyFilter(showErrors: false)
    }

    @objc private func yRangeSwitchChanged() {
        rectangleY0Label.isHidden = !rectangleYSwitch.isOn
        rectangleY0.isHidden = !rectangleYSwitch.isOn
        rectangleY1Label.isHidden = !rectangleYSwitch.isOn
        rectangleY1.isHidden = !rectangleYSwitch.isOn
        radiusYLabel.isHidden = !radiusYSwitch.isOn
        radiusY.isHidden = !radiusYSwitch.isOn
        applyFilter(showErrors: false)
    }

    @objc private func applyRangeFilter() { applyFilter(showErrors: true) }
    @objc private func filterChanged() { applyFilter(showErrors: false) }
    func updateSearchResults(for searchController: UISearchController) { applyFilter(showErrors: false) }

    private func makeSpatialFilter() throws -> (EntitySpatialFilter, String) {
        let mode = EntitySpatialFilterMode(rawValue: rangeModeControl.selectedSegmentIndex) ?? .all
        switch mode {
        case .all:
            return (.all, "全部坐标")
        case .box:
            guard let x0 = Double(rectangleX0.text ?? ""), let z0 = Double(rectangleZ0.text ?? ""),
                  let x1 = Double(rectangleX1.text ?? ""), let z1 = Double(rectangleZ1.text ?? "") else {
                throw BlocktopographError.malformedData("坐标区域的 X0、Z0、X1、Z1 必须是数字")
            }
            let yRange: ClosedRange<Double>?
            if rectangleYSwitch.isOn {
                guard let y0 = Double(rectangleY0.text ?? ""), let y1 = Double(rectangleY1.text ?? "") else {
                    throw BlocktopographError.malformedData("Y0、Y1 必须是数字")
                }
                yRange = min(y0, y1)...max(y0, y1)
            } else {
                yRange = nil
            }
            let description = yRange == nil
                ? "区域 X=\(format(min(x0, x1)))…\(format(max(x0, x1)))，Z=\(format(min(z0, z1)))…\(format(max(z0, z1)))"
                : "区域 X/Z + Y=\(format(yRange!.lowerBound))…\(format(yRange!.upperBound))"
            return (.box(
                minX: min(x0, x1), maxX: max(x0, x1),
                minZ: min(z0, z1), maxZ: max(z0, z1),
                yRange: yRange
            ), description)
        case .radius:
            guard let x = Double(radiusX.text ?? ""), let z = Double(radiusZ.text ?? ""),
                  let radius = Double(radiusValue.text ?? ""), radius >= 0 else {
                throw BlocktopographError.malformedData("中心 X、Z 和半径必须是有效数字，且半径不能为负数")
            }
            let y: Double?
            if radiusYSwitch.isOn {
                guard let parsedY = Double(radiusY.text ?? "") else {
                    throw BlocktopographError.malformedData("开启 Y 后必须填写中心 Y")
                }
                y = parsedY
            } else {
                y = nil
            }
            let description = y == nil
                ? "XZ 半径 \(format(radius))，中心 (\(format(x)), \(format(z)))"
                : "XYZ 半径 \(format(radius))，中心 (\(format(x)), \(format(y!)), \(format(z)))"
            return (.radius(centerX: x, centerY: y, centerZ: z, radius: radius), description)
        }
    }

    private func applyFilter(showErrors: Bool) {
        let filterResult: (EntitySpatialFilter, String)
        do {
            filterResult = try makeSpatialFilter()
        } catch {
            if showErrors { showError(error, title: "范围参数错误") }
            statusLabel.text = scanSummary.isEmpty ? error.localizedDescription : "\(scanSummary)；范围参数尚未生效：\(error.localizedDescription)"
            return
        }
        let (spatial, rangeDescription) = filterResult

        let kind: BedrockWorldObjectKind = kindControl.selectedSegmentIndex == 0 ? .entity : .blockEntity
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        shownObjects = allObjects.filter { object in
            guard object.kind == kind, spatial.contains(object.position) else { return false }
            guard !query.isEmpty else { return true }
            return object.displayName.lowercased().contains(query) ||
                object.identifier.lowercased().contains(query) ||
                object.coordinateText.lowercased().contains(query) ||
                object.source.rawValue.lowercased().contains(query) ||
                object.uniqueID.map { String($0).contains(query) } == true
        }
        title = "\(kind.displayName)（\(shownObjects.count)）"
        tableView.reloadData()
        statusLabel.text = scanSummary.isEmpty
            ? "\(rangeDescription)；显示 \(shownObjects.count) 项"
            : "\(scanSummary)；\(rangeDescription)；当前显示 \(shownObjects.count) 项"
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int64(value)) : String(format: "%.2f", value)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shownObjects.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let object = shownObjects[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorldObjectCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "WorldObjectCell")
        cell.textLabel?.text = dataValueDisplayName(for: object)
        let dimension = BedrockDimension(rawValue: object.dimension)?.displayName ?? "维度 \(object.dimension)"
        let identifierText = object.identifier.isEmpty ? "" : "\(object.identifier)；"
        cell.detailTextLabel?.text = "\(identifierText)\(dimension)；\(object.subtitle)"
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = UIImage(systemName: object.kind == .entity ? "person.fill" : "shippingbox.fill")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showDetails(shownObjects[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let object = shownObjects[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            self?.confirmDelete(object)
            completion(true)
        }
        let duplicate = UIContextualAction(style: .normal, title: "新建副本") { [weak self] _, _, completion in
            self?.duplicateObject(object)
            completion(true)
        }
        duplicate.backgroundColor = .systemOrange
        let locate = UIContextualAction(style: .normal, title: "地图") { [weak self] _, _, completion in
            self?.onLocate(object)
            completion(true)
        }
        locate.backgroundColor = .systemBlue
        let configuration = UISwipeActionsConfiguration(actions: [delete, duplicate, locate])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard shownObjects.indices.contains(indexPath.row) else { return nil }
        let object = shownObjects[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            var actions = [UIAction(title: "编辑 NBT", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                self?.openEditor(object)
            }]
            actions.append(UIAction(title: "复制为新\(object.kind.displayName)", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                self?.duplicateObject(object)
            })
            if object.kind == .entity {
                actions.append(UIAction(title: "导出实体 NBT", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.exportEntity(object)
                })
            }
            if object.position != nil {
                actions.append(UIAction(title: "在地图中定位", image: UIImage(systemName: "map")) { [weak self] _ in
                    self?.onLocate(object)
                })
            }
            actions.append(UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.confirmDelete(object)
            })
            return UIMenu(title: self.dataValueDisplayName(for: object), children: actions)
        }
    }

    private func openEditor(_ object: BedrockWorldObject) {
        let controller = WorldObjectNBTEditorViewController(
            object: object,
            session: session,
            onSave: { [weak self] in
                self?.session.invalidateAfterExternalChange()
            }
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func showDetails(_ object: BedrockWorldObject) {
        session.rememberSelectedWorldObject(object)
        let dimension = BedrockDimension(rawValue: object.dimension)?.displayName ?? "维度 \(object.dimension)"
        var message = "\(object.identifier)\n\(dimension)；\(object.coordinateText)\n来源：\(object.source.rawValue)"
        if let uniqueID = object.uniqueID { message += "\nUniqueID：\(uniqueID)" }
        if object.itemCount > 0 { message += "\n物品槽：\(object.itemCount)" }
        let alert = UIAlertController(title: dataValueDisplayName(for: object), message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "编辑 NBT", style: .default) { [weak self] _ in
            self?.openEditor(object)
        })
        alert.addAction(UIAlertAction(title: "复制为新\(object.kind.displayName)", style: .default) { [weak self] _ in
            self?.duplicateObject(object)
        })
        if object.kind == .entity {
            alert.addAction(UIAlertAction(title: "导出实体 NBT", style: .default) { [weak self] _ in
                self?.exportEntity(object)
            })
        }
        alert.addAction(UIAlertAction(title: "删除\(object.kind.displayName)", style: .destructive) { [weak self] _ in
            self?.confirmDelete(object)
        })
        if object.position != nil {
            alert.addAction(UIAlertAction(title: "在地图中定位", style: .default) { [weak self] _ in self?.onLocate(object) })
        }
        alert.addAction(UIAlertAction(title: "复制坐标", style: .default) { _ in UIPasteboard.general.string = object.coordinateText })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = CGRect(x: tableView.bounds.midX, y: tableView.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func exportEntity(_ object: BedrockWorldObject) {
        do {
            let document = try objectStore.document(for: object)
            let identifier = object.identifier.replacingOccurrences(of: ":", with: "_")
            let suffix = object.uniqueID.map(String.init) ?? "entity"
            NBTExportUI.presentEntityFormatChooser(
                from: self,
                document: document,
                baseFilename: "\(identifier)-\(suffix)",
                sourceView: tableView
            )
        } catch {
            showError(error, title: "导出实体 NBT 失败")
        }
    }

    private func dataValueDisplayName(for object: BedrockWorldObject) -> String {
        if object.kind == .entity,
           let entry = BedrockDataValueCatalog.entity(forIdentifier: object.identifier) {
            if let customName = object.customName?.trimmingCharacters(in: .whitespacesAndNewlines), !customName.isEmpty {
                return "\(customName)（\(entry.displayName)）"
            }
            return entry.displayName
        }
        return object.displayName
    }

    @objc private func showDiagnostics() {
        let message = diagnostics.isEmpty ? "本次扫描没有记录解析错误。" : diagnostics.prefix(120).joined(separator: "\n")
        let alert = UIAlertController(title: "实体扫描诊断", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "复制", style: .default) { _ in UIPasteboard.general.string = message })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        applyFilter(showErrors: true)
        return true
    }
}
