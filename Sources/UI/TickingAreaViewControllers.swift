import UIKit

final class TickingAreaEditorViewController: UIViewController, UITextFieldDelegate {
    private let initialArea: BedrockTickingArea?
    private let defaultDimension: Int32
    private let existingCount: Int
    private let isCreating: Bool

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let nameField = UITextField()
    private let dimensionControl = UISegmentedControl(items: BedrockDimension.allCases.map(\.displayName))
    private let shapeControl = UISegmentedControl(items: ["矩形", "圆形"])
    private let preloadSwitch = UISwitch()
    private let firstXField = UITextField()
    private let firstZField = UITextField()
    private let secondXField = UITextField()
    private let secondZField = UITextField()
    private let firstXLabel = UILabel()
    private let firstZLabel = UILabel()
    private let secondXLabel = UILabel()
    private let secondZLabel = UILabel()
    private let secondZRow = UIStackView()
    private let summaryLabel = UILabel()

    var onSave: ((BedrockTickingArea) -> Void)?

    init(
        area: BedrockTickingArea?,
        defaultDimension: Int32 = 0,
        existingCount: Int,
        isCreating: Bool? = nil
    ) {
        self.initialArea = area
        self.defaultDimension = defaultDimension
        self.existingCount = existingCount
        self.isCreating = isCreating ?? (area == nil)
        super.init(nibName: nil, bundle: nil)
        title = self.isCreating ? "新增常加载区域" : "编辑常加载区域"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        configureUI()
        populate()
        updateShapeUI()
    }

    private func configureUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 20, left: 16, bottom: 28, right: 16)
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        [nameField, firstXField, firstZField, secondXField, secondZField].forEach { field in
            field.borderStyle = .roundedRect
            field.delegate = self
            field.clearButtonMode = .whileEditing
        }
        nameField.placeholder = "可选；例如 spawn_area"
        [firstXField, firstZField, secondXField, secondZField].forEach {
            $0.keyboardType = .numbersAndPunctuation
            $0.addTarget(self, action: #selector(valuesChanged), for: .editingChanged)
        }
        shapeControl.addTarget(self, action: #selector(shapeChanged), for: .valueChanged)
        dimensionControl.addTarget(self, action: #selector(valuesChanged), for: .valueChanged)
        preloadSwitch.addTarget(self, action: #selector(valuesChanged), for: .valueChanged)

        contentStack.addArrangedSubview(sectionTitle("基本信息"))
        contentStack.addArrangedSubview(fieldRow(title: "名称", control: nameField))
        contentStack.addArrangedSubview(fieldRow(title: "维度", control: dimensionControl))
        contentStack.addArrangedSubview(fieldRow(title: "形状", control: shapeControl))
        contentStack.addArrangedSubview(fieldRow(title: "进入世界时预加载", control: preloadSwitch))
        contentStack.addArrangedSubview(sectionTitle("坐标"))
        contentStack.addArrangedSubview(coordinateRow(label: firstXLabel, field: firstXField))
        contentStack.addArrangedSubview(coordinateRow(label: firstZLabel, field: firstZField))
        contentStack.addArrangedSubview(coordinateRow(label: secondXLabel, field: secondXField))
        secondZRow.axis = .horizontal
        secondZRow.spacing = 12
        secondZRow.alignment = .center
        secondZLabel.widthAnchor.constraint(equalToConstant: 104).isActive = true
        secondZRow.addArrangedSubview(secondZLabel)
        secondZRow.addArrangedSubview(secondZField)
        contentStack.addArrangedSubview(secondZRow)

        summaryLabel.font = .preferredFont(forTextStyle: .footnote)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0
        contentStack.addArrangedSubview(summaryLabel)

        let note = UILabel()
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        note.text = "矩形边界坐标单位为区块；圆形中心坐标单位为方块，半径单位为区块。基岩版每个世界最多 10 个常加载区域；单个区域最多 100 个区块；圆形半径最多 4 个区块。"
        contentStack.addArrangedSubview(note)
    }

    private func populate() {
        let area = initialArea ?? BedrockTickingArea(
            dimension: defaultDimension,
            isCircle: false,
            minimumX: 0,
            minimumZ: 0,
            maximumX: 0,
            maximumZ: 0,
            name: "",
            preload: false
        )
        nameField.text = area.name
        dimensionControl.selectedSegmentIndex = BedrockDimension.allCases.firstIndex(where: { $0.rawValue == area.dimension }) ?? 0
        shapeControl.selectedSegmentIndex = area.isCircle ? 1 : 0
        preloadSwitch.isOn = area.preload
        if area.isCircle {
            firstXField.text = String(area.centerBlockX)
            firstZField.text = String(area.centerBlockZ)
            secondXField.text = String(area.radius)
            secondZField.text = ""
        } else {
            firstXField.text = String(area.minimumX)
            firstZField.text = String(area.minimumZ)
            secondXField.text = String(area.maximumX)
            secondZField.text = String(area.maximumZ)
        }
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func fieldRow(title: String, control: UIView) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        return stack
    }

    private func coordinateRow(label: UILabel, field: UITextField) -> UIStackView {
        label.font = .preferredFont(forTextStyle: .body)
        label.widthAnchor.constraint(equalToConstant: 104).isActive = true
        let stack = UIStackView(arrangedSubviews: [label, field])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        return stack
    }

    @objc private func shapeChanged() {
        if shapeControl.selectedSegmentIndex == 1, initialArea?.isCircle != true {
            secondXField.text = "0"
            secondZField.text = ""
        }
        updateShapeUI()
    }

    private func updateShapeUI() {
        let circle = shapeControl.selectedSegmentIndex == 1
        firstXLabel.text = circle ? "中心方块 X" : "最小区块 X"
        firstZLabel.text = circle ? "中心方块 Z" : "最小区块 Z"
        secondXLabel.text = circle ? "半径（区块）" : "最大区块 X"
        secondZLabel.text = "最大 Z"
        secondZRow.isHidden = circle
        updateSummary()
    }

    @objc private func valuesChanged() { updateSummary() }

    private func draftArea() -> BedrockTickingArea? {
        guard dimensionControl.selectedSegmentIndex >= 0,
              let firstX = Int64(firstXField.text ?? ""),
              let firstZ = Int64(firstZField.text ?? ""),
              let secondX = Int64(secondXField.text ?? ""),
              firstX >= Int64(Int32.min), firstX <= Int64(Int32.max),
              firstZ >= Int64(Int32.min), firstZ <= Int64(Int32.max) else { return nil }
        let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
        if shapeControl.selectedSegmentIndex == 1 {
            let radiusChunks = max(0, secondX)
            guard radiusChunks <= Int64(TickingAreaStore.maximumCircleRadius) else { return nil }
            let centerBlockX = firstX
            let centerBlockZ = firstZ
            let radiusBlocks = MapCoordinate.blockDistance(fromChunkDistance: radiusChunks)
            let minimumX = centerBlockX - radiusBlocks
            let minimumZ = centerBlockZ - radiusBlocks
            let maximumX = centerBlockX + radiusBlocks
            let maximumZ = centerBlockZ + radiusBlocks
            guard minimumX >= Int64(Int32.min), minimumZ >= Int64(Int32.min),
                  maximumX <= Int64(Int32.max), maximumZ <= Int64(Int32.max) else { return nil }
            return BedrockTickingArea(
                dimension: dimension,
                isCircle: true,
                minimumX: Int32(minimumX),
                minimumZ: Int32(minimumZ),
                maximumX: Int32(maximumX),
                maximumZ: Int32(maximumZ),
                name: nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                preload: preloadSwitch.isOn
            )
        }
        guard let secondZ = Int64(secondZField.text ?? ""),
              secondX >= Int64(Int32.min), secondX <= Int64(Int32.max),
              secondZ >= Int64(Int32.min), secondZ <= Int64(Int32.max) else { return nil }
        return BedrockTickingArea(
            dimension: dimension,
            isCircle: false,
            minimumX: Int32(firstX),
            minimumZ: Int32(firstZ),
            maximumX: Int32(secondX),
            maximumZ: Int32(secondZ),
            name: nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            preload: preloadSwitch.isOn
        ).normalized
    }

    private func updateSummary() {
        guard let area = draftArea() else {
            summaryLabel.text = "请输入完整的整数坐标。"
            return
        }
        summaryLabel.text = area.detailText
    }

    @objc private func save() {
        view.endEditing(true)
        guard let area = draftArea() else {
            showError(MCBEEditorError.malformedData("请输入完整的整数坐标"), title: "坐标错误")
            return
        }
        if isCreating, existingCount >= TickingAreaStore.maximumAreaCount {
            showError(MCBEEditorError.unsupported("世界中已有 \(existingCount) 个常加载区域，无法继续增加"), title: "数量已达上限")
            return
        }
        do {
            try TickingAreaStore.validate(area)
            onSave?(area.normalized)
            navigationController?.popViewController(animated: true)
        } catch {
            showError(error, title: "常加载区域无效")
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

final class TickingAreaListViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private let store: TickingAreaStore
    private let workQueue = DispatchQueue(label: "com.wzn.mcbeeditor.ticking-area", qos: .userInitiated)
    private let initialDimension: Int32
    private let selectionContext: TickingAreaSelectionContext?
    private let dimensionControl = UISegmentedControl(items: ["全部"] + BedrockDimension.allCases.map(\.displayName))
    private var records = [BedrockTickingAreaRecord]()
    private var filtered = [BedrockTickingAreaRecord]()
    private var query = ""
    private var isBatchMode = false
    private var selectedIDs = Set<String>()

    var onSelectChunk: ((ChunkPosition) -> Void)?
    var onMutation: ((String) -> Void)?

    init(
        session: WorldSession,
        initialDimension: Int32,
        selectionContext: TickingAreaSelectionContext? = nil
    ) {
        self.session = session
        self.store = TickingAreaStore(session: session)
        self.initialDimension = initialDimension
        self.selectionContext = selectionContext
        super.init(style: .insetGrouped)
        title = selectionContext == nil ? "常加载区块" : "常加载区域编辑"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TickingArea")
        tableView.rowHeight = 72
        let search = UISearchController(searchResultsController: nil)
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "搜索名称、坐标或维度"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        let preferredDimension = selectionContext?.dimension ?? initialDimension
        dimensionControl.selectedSegmentIndex = BedrockDimension.allCases.firstIndex(where: { $0.rawValue == preferredDimension }).map { $0 + 1 } ?? 0
        dimensionControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        dimensionControl.isEnabled = selectionContext == nil
        let wrapper = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 52))
        dimensionControl.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(dimensionControl)
        NSLayoutConstraint.activate([
            dimensionControl.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            dimensionControl.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            dimensionControl.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])
        tableView.tableHeaderView = wrapper
        updateNavigationButtons()
        reloadRecords()
    }

    private func updateNavigationButtons() {
        if isBatchMode {
            let cancel = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelBatch))
            let visible = Set(filtered.map(\.stableID))
            let all = !visible.isEmpty && visible.isSubset(of: selectedIDs)
            let selectAll = UIBarButtonItem(title: all ? "取消全选" : "全选", style: .plain, target: self, action: #selector(toggleSelectAll))
            let process = UIBarButtonItem(title: "处理", style: .done, target: self, action: #selector(showBatchActions))
            process.isEnabled = !selectedIDs.isEmpty
            navigationItem.rightBarButtonItems = [process, selectAll, cancel]
            navigationItem.prompt = "已选择 \(selectedIDs.count) 个常加载区域"
        } else {
            let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addArea))
            let batch = UIBarButtonItem(title: "批量", style: .plain, target: self, action: #selector(beginBatch))
            batch.isEnabled = !records.isEmpty
            navigationItem.rightBarButtonItems = [add, batch]
            if let selectionContext = selectionContext {
                navigationItem.prompt = "\(selectionContext.detailText) · 相交 \(filtered.count) 个 · LevelDB：tickingarea_"
            } else {
                navigationItem.prompt = "LevelDB：tickingarea_ · \(records.count)/\(TickingAreaStore.maximumAreaCount) 个区域"
            }
        }
    }

    @objc private func reloadRecords() {
        let overlay = showBusy("读取常加载区域…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let values = try self.store.records(migratingLegacy: true)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.records = values
                    self.selectedIDs.formIntersection(Set(values.map(\.stableID)))
                    self.applyFilter()
                    self.updateNavigationButtons()
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "无法读取常加载区块")
                }
            }
        }
    }

    @objc private func filterChanged() { applyFilter() }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        applyFilter()
    }

    private func applyFilter() {
        let dimension: Int32? = dimensionControl.selectedSegmentIndex == 0 ? nil : BedrockDimension.allCases[dimensionControl.selectedSegmentIndex - 1].rawValue
        filtered = records.filter { record in
            if let dimension = dimension, record.area.dimension != dimension { return false }
            if let selectionContext = selectionContext, !selectionContext.intersects(record.area) { return false }
            guard !query.isEmpty else { return true }
            let text = "\(record.area.name) \(record.area.detailText)"
            return text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        tableView.reloadData()
        if filtered.isEmpty {
            let label = UILabel()
            label.text = selectionContext == nil
                ? "没有常加载区域"
                : "选区内没有相交的常加载区域。\n点击右上角“+”可按当前范围新增。"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
        updateNavigationButtons()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if let selectionContext = selectionContext {
            return "当前按 \(selectionContext.detailText) 筛选相交区域。点击“+”会以该选区的区块外接矩形作为初始范围；已有区域可继续编辑或删除。"
        }
        return "常加载区域可在未生成区块上存在。地图中的“常加载区块”模式会按这里的范围显示全部区域。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TickingArea", for: indexPath)
        let record = filtered[indexPath.row]
        cell.textLabel?.numberOfLines = 3
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        let name = record.area.name.isEmpty ? "未命名区域" : record.area.name
        cell.textLabel?.text = "\(name)\n\(record.area.detailText)"
        cell.accessoryType = isBatchMode ? (selectedIDs.contains(record.stableID) ? .checkmark : .none) : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let record = filtered[indexPath.row]
        tableView.deselectRow(at: indexPath, animated: true)
        if isBatchMode {
            if selectedIDs.contains(record.stableID) { selectedIDs.remove(record.stableID) }
            else { selectedIDs.insert(record.stableID) }
            tableView.reloadRows(at: [indexPath], with: .none)
            updateNavigationButtons()
            return
        }
        showActions(record, source: tableView.cellForRow(at: indexPath))
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isBatchMode else { return nil }
        let record = filtered[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            self?.confirmDelete(ids: [record.stableID])
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func showActions(_ record: BedrockTickingAreaRecord, source: UIView?) {
        let alert = UIAlertController(title: record.area.name.isEmpty ? "常加载区域" : record.area.name, message: record.area.detailText, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "在地图中查看", style: .default) { [weak self] _ in
            self?.onSelectChunk?(record.area.centerChunk)
            self?.navigationController?.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: "编辑…", style: .default) { [weak self] _ in self?.edit(record) })
        alert.addAction(UIAlertAction(title: "删除…", style: .destructive) { [weak self] _ in self?.confirmDelete(ids: [record.stableID]) })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = source ?? view
        alert.popoverPresentationController?.sourceRect = source?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(alert, animated: true)
    }

    @objc private func addArea() {
        let selectedDimension = dimensionControl.selectedSegmentIndex == 0 ? initialDimension : BedrockDimension.allCases[dimensionControl.selectedSegmentIndex - 1].rawValue
        let controller = TickingAreaEditorViewController(
            area: selectionContext?.suggestedArea,
            defaultDimension: selectedDimension,
            existingCount: records.count,
            isCreating: true
        )
        controller.onSave = { [weak self] area in self?.append(area) }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func edit(_ record: BedrockTickingAreaRecord) {
        let controller = TickingAreaEditorViewController(area: record.area, defaultDimension: record.area.dimension, existingCount: records.count)
        controller.onSave = { [weak self] area in self?.replace(id: record.stableID, with: area) }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func append(_ area: BedrockTickingArea) {
        do {
            var values = records
            values.append(try store.makeRecord(area: area))
            save(values, message: "已增加常加载区域。")
        } catch { showError(error, title: "增加失败") }
    }

    private func replace(id: String, with area: BedrockTickingArea) {
        guard let index = records.firstIndex(where: { $0.stableID == id }) else { return }
        var values = records
        values[index].area = area
        save(values, message: "已更新常加载区域。")
    }

    private func save(_ values: [BedrockTickingAreaRecord], message: String) {
        let overlay = showBusy("保存常加载区域…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.store.save(values)
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.session.invalidateAfterExternalChange()
                    self.onMutation?(message)
                    self.reloadRecords()
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "保存失败")
                }
            }
        }
    }

    @objc private func beginBatch() {
        isBatchMode = true
        selectedIDs.removeAll()
        updateNavigationButtons()
        tableView.reloadData()
    }

    @objc private func cancelBatch() {
        isBatchMode = false
        selectedIDs.removeAll()
        updateNavigationButtons()
        tableView.reloadData()
    }

    @objc private func toggleSelectAll() {
        let visible = Set(filtered.map(\.stableID))
        if !visible.isEmpty, visible.isSubset(of: selectedIDs) { selectedIDs.subtract(visible) }
        else { selectedIDs.formUnion(visible) }
        updateNavigationButtons()
        tableView.reloadData()
    }

    @objc private func showBatchActions() {
        guard !selectedIDs.isEmpty else { return }
        let alert = UIAlertController(title: "批量处理 \(selectedIDs.count) 个区域", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "开启预加载", style: .default) { [weak self] _ in self?.setPreload(true) })
        alert.addAction(UIAlertAction(title: "关闭预加载", style: .default) { [weak self] _ in self?.setPreload(false) })
        alert.addAction(UIAlertAction(title: "删除所选区域…", style: .destructive) { [weak self] _ in self?.confirmDelete(ids: Array(self?.selectedIDs ?? [])) })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(alert, animated: true)
    }

    private func setPreload(_ enabled: Bool) {
        var values = records
        for index in values.indices where selectedIDs.contains(values[index].stableID) {
            values[index].area.preload = enabled
        }
        cancelBatch()
        save(values, message: "已批量\(enabled ? "开启" : "关闭")预加载。")
    }

    private func confirmDelete(ids: [String]) {
        guard !ids.isEmpty else { return }
        let alert = UIAlertController(title: "删除常加载区域？", message: "将删除 \(ids.count) 个区域，不会删除其中的区块数据。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let idSet = Set(ids)
            self.isBatchMode = false
            self.selectedIDs.removeAll()
            self.save(self.records.filter { !idSet.contains($0.stableID) }, message: "已删除 \(ids.count) 个常加载区域。")
        })
        present(alert, animated: true)
    }
}
