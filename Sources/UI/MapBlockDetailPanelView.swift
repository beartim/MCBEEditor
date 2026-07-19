import UIKit

final class MapBlockDetailPanelView: UIView, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate {
    let xField = UITextField()
    let yField = UITextField()
    let zField = UITextField()
    let jumpButton = UIButton(type: .system)
    var onJump: ((Int64, Int32, Int64) -> Void)?
    var onSave: ((BedrockBlockRecord, Int, NBTDocument) -> Void)?
    var onCollapsedChanged: ((Bool) -> Void)?
    var onReturnToSearchResults: (() -> Void)?

    private let titleLabel = UILabel()
    private let collapseButton = UIButton(type: .system)
    private let bodyStack = UIStackView()
    private let collapsedSpacer = UIView()
    private(set) var isCollapsed = false
    private let coordinateLabel = UILabel()
    private let placeholderLabel = UILabel()
    private let layerControl = UISegmentedControl(items: [])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let addButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let returnToSearchButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let batchButton = UIButton(type: .system)
    private let actionsStack = UIStackView()
    private let batchActionsStack = UIStackView()
    private let batchSelectAllButton = UIButton(type: .system)
    private let batchCopyButton = UIButton(type: .system)
    private let batchExportButton = UIButton(type: .system)
    private let batchDeleteButton = UIButton(type: .system)
    private let batchCancelButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private var block: BedrockBlockRecord?
    private var document: NBTDocument?
    private var rows = [NBTNode]()
    private var expanded = Set<[NBTPathComponent]>()
    private var selectedLayerIndex = 0
    private var dirty = false
    private var selectionAnnotation: String?
    private var isBatchSelecting = false
    private var batchSelectedPaths = Set<[NBTPathComponent]>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1 / UIScreen.main.scale
        configureUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureUI() {
        titleLabel.text = "方块 NBT"
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        collapseButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        collapseButton.accessibilityLabel = "展开方块 NBT 侧栏"
        collapseButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        collapseButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        collapseButton.addTarget(self, action: #selector(toggleCollapsed), for: .touchUpInside)

        for (field, placeholder) in [(xField, "X"), (yField, "Y"), (zField, "Z")] {
            field.placeholder = placeholder
            field.borderStyle = .roundedRect
            field.keyboardType = .numbersAndPunctuation
            field.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.delegate = self
            field.accessibilityLabel = "方块坐标 \(placeholder)"
        }
        jumpButton.setTitle("跳转并查看", for: .normal)
        jumpButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        jumpButton.setTitleColor(.white, for: .normal)
        jumpButton.backgroundColor = .systemBlue
        jumpButton.layer.cornerRadius = 8
        jumpButton.layer.masksToBounds = true
        jumpButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        jumpButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        jumpButton.addTarget(self, action: #selector(jump), for: .touchUpInside)

        let coordinateRow = UIStackView(arrangedSubviews: [xField, yField, zField])
        coordinateRow.axis = .horizontal
        coordinateRow.spacing = 6
        coordinateRow.distribution = .fillEqually
        coordinateRow.heightAnchor.constraint(equalToConstant: 36).isActive = true

        coordinateLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        coordinateLabel.textColor = .secondaryLabel
        coordinateLabel.numberOfLines = 0

        placeholderLabel.text = "点按地图方块或输入 X、Y、Z。\n\n选择后，这里以 NBT 树展示方块名称、版本和全部 states；长按标签可增、删、改。"
        placeholderLabel.font = .preferredFont(forTextStyle: .footnote)
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.numberOfLines = 0

        layerControl.addTarget(self, action: #selector(layerChanged), for: .valueChanged)
        layerControl.isHidden = true

        addButton.setTitle("增加根标签", for: .normal)
        addButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        addButton.addTarget(self, action: #selector(addToRoot), for: .touchUpInside)
        saveButton.setTitle("保存方块", for: .normal)
        saveButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        saveButton.addTarget(self, action: #selector(saveBlock), for: .touchUpInside)
        returnToSearchButton.setTitle("返回搜索结果", for: .normal)
        returnToSearchButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        returnToSearchButton.addTarget(self, action: #selector(returnToSearchResults), for: .touchUpInside)
        returnToSearchButton.isHidden = true
        exportButton.setTitle("导出", for: .normal)
        exportButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        exportButton.addTarget(self, action: #selector(exportCurrentNBT), for: .touchUpInside)
        batchButton.setTitle("选择", for: .normal)
        batchButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        batchButton.addTarget(self, action: #selector(beginBatchSelection), for: .touchUpInside)
        actionsStack.addArrangedSubview(addButton)
        actionsStack.addArrangedSubview(saveButton)
        actionsStack.addArrangedSubview(returnToSearchButton)
        actionsStack.addArrangedSubview(exportButton)
        actionsStack.addArrangedSubview(batchButton)
        actionsStack.axis = .horizontal
        actionsStack.spacing = 6
        actionsStack.distribution = .fillEqually

        batchSelectAllButton.setTitle("全选", for: .normal)
        batchCopyButton.setTitle("复制", for: .normal)
        batchExportButton.setTitle("导出", for: .normal)
        batchDeleteButton.setTitle("删除", for: .normal)
        batchDeleteButton.setTitleColor(.systemRed, for: .normal)
        batchCancelButton.setTitle("取消", for: .normal)
        for button in [batchSelectAllButton, batchCopyButton, batchExportButton, batchDeleteButton, batchCancelButton] {
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            batchActionsStack.addArrangedSubview(button)
        }
        batchSelectAllButton.addTarget(self, action: #selector(toggleBatchSelectAll), for: .touchUpInside)
        batchCopyButton.addTarget(self, action: #selector(copyBatchSelection), for: .touchUpInside)
        batchExportButton.addTarget(self, action: #selector(exportBatchSelection), for: .touchUpInside)
        batchDeleteButton.addTarget(self, action: #selector(deleteBatchSelection), for: .touchUpInside)
        batchCancelButton.addTarget(self, action: #selector(cancelBatchSelection), for: .touchUpInside)
        batchActionsStack.axis = .horizontal
        batchActionsStack.spacing = 6
        batchActionsStack.distribution = .fillEqually
        batchActionsStack.isHidden = true

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 50
        tableView.backgroundColor = .tertiarySystemBackground
        tableView.layer.cornerRadius = 8
        tableView.tableFooterView = UIView()
        tableView.setContentHuggingPriority(.defaultLow, for: .vertical)
        tableView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        let headerSpacer = UIView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [titleLabel, headerSpacer, collapseButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 4

        for arranged in [
            coordinateRow, jumpButton, separator(), placeholderLabel, coordinateLabel,
            layerControl, actionsStack, batchActionsStack, tableView, statusLabel
        ] {
            bodyStack.addArrangedSubview(arranged)
        }
        bodyStack.axis = .vertical
        bodyStack.spacing = 7

        collapsedSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        collapsedSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let stack = UIStackView(arrangedSubviews: [header, bodyStack, collapsedSpacer])
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -9)
        ])
        clearBlock()
    }

    func setReturnToSearchResultsAvailable(_ available: Bool) {
        returnToSearchButton.isHidden = !available
    }

    @objc private func returnToSearchResults() {
        onReturnToSearchResults?()
    }

    @objc private func toggleCollapsed() {
        setCollapsed(!isCollapsed, animated: true)
    }

    func setCollapsed(_ collapsed: Bool, animated: Bool, notify: Bool = true) {
        guard collapsed != isCollapsed || bodyStack.isHidden != collapsed else { return }
        isCollapsed = collapsed
        let changes = {
            self.bodyStack.isHidden = collapsed
            self.collapsedSpacer.isHidden = !collapsed
            self.titleLabel.isHidden = collapsed
            self.collapseButton.setImage(UIImage(systemName: collapsed ? "chevron.left" : "chevron.right"), for: .normal)
            self.collapseButton.accessibilityLabel = collapsed ? "展开方块 NBT 侧栏" : "收缩方块 NBT 侧栏"
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.20, animations: changes)
        } else {
            changes()
        }
        if notify { onCollapsedChanged?(collapsed) }
    }

    private func fieldLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.widthAnchor.constraint(equalToConstant: 14).isActive = true
        return label
    }

    private func separator() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return view
    }

    func show(block: BedrockBlockRecord, preferredLayer: Int = 0, annotation: String? = nil) {
        cancelBatchSelection()
        setCollapsed(false, animated: true)
        self.block = block
        selectionAnnotation = annotation
        titleLabel.text = annotation.map { "方块 NBT · \($0)" } ?? "方块 NBT"
        xField.text = String(block.x)
        yField.text = String(block.y)
        zField.text = String(block.z)
        let dimension = BedrockDimension(rawValue: block.dimension)?.displayName ?? "维度 \(block.dimension)"
        let annotationLine = annotation.map { "\($0)\n" } ?? ""
        coordinateLabel.text = "\(annotationLine)\(dimension)\n\(block.coordinateDescription)\n\(block.chunkDescription)"
        coordinateLabel.isHidden = false
        placeholderLabel.isHidden = true

        layerControl.removeAllSegments()
        for index in 0..<BedrockBlockRecord.editableLayerCount {
            layerControl.insertSegment(withTitle: "层 \(index)", at: index, animated: false)
        }
        selectedLayerIndex = min(max(0, preferredLayer), BedrockBlockRecord.editableLayerCount - 1)
        layerControl.selectedSegmentIndex = selectedLayerIndex
        layerControl.isHidden = false
        actionsStack.isHidden = false
        loadSelectedLayer()
    }

    func clearBlock() {
        cancelBatchSelection()
        setCollapsed(true, animated: true)
        block = nil
        selectionAnnotation = nil
        titleLabel.text = "方块 NBT"
        document = nil
        rows = []
        expanded = [[]]
        dirty = false
        coordinateLabel.text = nil
        coordinateLabel.isHidden = true
        placeholderLabel.isHidden = false
        layerControl.isHidden = true
        actionsStack.isHidden = true
        addButton.isEnabled = false
        saveButton.isEnabled = false
        exportButton.isEnabled = false
        tableView.isHidden = true
        statusLabel.text = nil
        tableView.reloadData()
    }

    func markSaved(block: BedrockBlockRecord, layerIndex: Int) {
        self.block = block
        selectedLayerIndex = min(max(0, layerIndex), BedrockBlockRecord.editableLayerCount - 1)
        dirty = false
        loadSelectedLayer()
        statusLabel.text = "已写回 SubChunk"
    }

    func showSaveError(_ error: Error) {
        saveButton.isEnabled = dirty
        statusLabel.text = "保存失败：\(error.localizedDescription)"
        owningViewController?.showError(error, title: "保存方块 NBT 失败")
    }

    private func loadSelectedLayer() {
        cancelBatchSelection()
        guard let block = block, (0..<BedrockBlockRecord.editableLayerCount).contains(selectedLayerIndex) else {
            document = nil
            rows = []
            tableView.reloadData()
            return
        }
        let layerExists = block.layers.indices.contains(selectedLayerIndex)
        let state = block.stateForEditing(layer: selectedLayerIndex)
        if let root = state.nbt {
            document = NBTDocument(rootName: "", root: root)
            expanded = [[]]
            dirty = false
            statusLabel.text = layerExists
                ? "长按标签可增加、修改、重命名或删除；保存会直接写入 SubChunk。"
                : "层 \(selectedLayerIndex) 当前不存在，按空气层显示；修改并保存后会创建该层。"
            rebuildRows()
            return
        }

        if let legacyID = state.legacyID {
            let legacyData = state.legacyData ?? 0
            document = NBTDocument(rootName: "", root: .compound([
                NBTNamedTag(name: "legacy_id", value: .int(Int32(legacyID))),
                NBTNamedTag(name: "legacy_data", value: .byte(Int8(legacyData))),
                NBTNamedTag(name: "name", value: .string(state.name))
            ]))
            expanded = [[]]
            dirty = false
            statusLabel.text = "旧版数字 ID 方块：可修改 legacy_id（0…255）和 legacy_data（0…15）；name 用于对照，也可填写旧版字符串 ID。保存会直接重写旧版 SubChunk。"
            rebuildRows()
            return
        }

        document = nil
        rows = []
        tableView.isHidden = false
        addButton.isEnabled = false
        saveButton.isEnabled = false
        exportButton.isEnabled = false
        statusLabel.text = "该图层没有可编辑的方块状态。"
        tableView.reloadData()
    }

    private func rebuildRows() {
        rows.removeAll(keepingCapacity: true)
        if let root = document?.root { appendChildren(of: root, path: [], depth: 0) }
        addButton.isEnabled = document?.root.type == .compound || document?.root.type == .list
        saveButton.isEnabled = dirty
        exportButton.isEnabled = document != nil
        tableView.isHidden = document == nil
        let visiblePaths = Set(rows.map(\.path))
        batchSelectedPaths.formIntersection(visiblePaths)
        updateBatchButtons()
        tableView.reloadData()
    }

    private func appendChildren(of value: NBTValue, path: [NBTPathComponent], depth: Int) {
        switch value {
        case .compound(let tags):
            for tag in tags {
                let childPath = path + [.compound(tag.name)]
                let node = NBTNode(path: childPath, name: tag.name, value: tag.value, depth: depth)
                rows.append(node)
                if expanded.contains(childPath) { appendChildren(of: tag.value, path: childPath, depth: depth + 1) }
            }
        case .list(_, let values):
            for (index, child) in values.enumerated() {
                let childPath = path + [.list(index)]
                let node = NBTNode(path: childPath, name: "[\(index)]", value: child, depth: depth)
                rows.append(node)
                if expanded.contains(childPath) { appendChildren(of: child, path: childPath, depth: depth + 1) }
            }
        default:
            break
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let node = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "BlockNBTCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BlockNBTCell")
        cell.indentationLevel = node.depth
        cell.indentationWidth = 13
        cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        cell.detailTextLabel?.font = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.imageView?.image = NBTTagIcon.image(for: node.value.type)
        cell.imageView?.contentMode = .center
        let marker = node.hasChildren ? (expanded.contains(node.path) ? "▾" : "▸") : " "
        cell.textLabel?.text = "\(marker) \(node.name)"
        cell.detailTextLabel?.text = "\(node.value.type.displayName) · \(node.value.summary)"
        cell.accessoryType = isBatchSelecting
            ? (batchSelectedPaths.contains(node.path) ? .checkmark : .none)
            : (node.hasChildren ? .none : .disclosureIndicator)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let node = rows[indexPath.row]
        if isBatchSelecting {
            if batchSelectedPaths.contains(node.path) {
                batchSelectedPaths.remove(node.path)
            } else {
                batchSelectedPaths.insert(node.path)
            }
            updateBatchButtons()
            tableView.reloadData()
            return
        }
        if node.hasChildren {
            if expanded.contains(node.path) { expanded.remove(node.path) } else { expanded.insert(node.path) }
            rebuildRows()
        } else {
            edit(node)
        }
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isBatchSelecting, rows.indices.contains(indexPath.row) else { return nil }
        let node = rows[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            var actions = [UIAction]()
            if case .compound = node.value {
                actions.append(UIAction(title: "增加子标签", image: UIImage(systemName: "plus")) { [weak self] _ in
                    guard let self = self else { return }
                    guard let presenter = self.owningViewController else { return }
                    NBTEditingUI.presentAdd(from: presenter, container: node.value, sourceView: tableView.cellForRow(at: indexPath)) { [weak self] name, value, replacingExisting in
                        self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
                    }
                })
            } else if case .list = node.value {
                actions.append(UIAction(title: "增加列表元素", image: UIImage(systemName: "plus")) { [weak self] _ in
                    guard let self = self else { return }
                    guard let presenter = self.owningViewController else { return }
                    NBTEditingUI.presentAdd(from: presenter, container: node.value, sourceView: tableView.cellForRow(at: indexPath)) { [weak self] name, value, replacingExisting in
                        self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
                    }
                })
            }
            if node.value.isDirectlyEditable {
                actions.append(UIAction(title: "修改值", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in self?.edit(node) })
            }
            if case .compound? = node.path.last {
                actions.append(UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in
                    guard let self = self, let presenter = self.owningViewController else { return }
                    NBTEditingUI.presentRename(from: presenter, currentName: node.name) { [weak self] name in self?.rename(node, to: name) }
                })
            }
            if let presenter = self.owningViewController {
                actions.append(contentsOf: NBTEditingUI.clipboardActions(
                    from: presenter,
                    node: node,
                    sourceView: tableView.cellForRow(at: indexPath)
                ) { [weak self] name, value, replacingExisting in
                    self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
                })
            }
            actions.append(UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                guard let self = self, let presenter = self.owningViewController else { return }
                NBTEditingUI.confirmDelete(from: presenter, nodeName: node.name) { [weak self] in self?.delete(node) }
            })
            return UIMenu(title: node.pathDescription, children: actions)
        }
    }

    @objc private func beginBatchSelection() {
        guard !rows.isEmpty else { return }
        isBatchSelecting = true
        batchSelectedPaths.removeAll()
        actionsStack.isHidden = true
        batchActionsStack.isHidden = false
        updateBatchButtons()
        tableView.reloadData()
    }

    @objc private func cancelBatchSelection() {
        isBatchSelecting = false
        batchSelectedPaths.removeAll()
        batchActionsStack.isHidden = true
        actionsStack.isHidden = block == nil
        updateBatchButtons()
        tableView.reloadData()
    }

    @objc private func toggleBatchSelectAll() {
        let visible = Set(rows.map(\.path))
        if !visible.isEmpty, visible.isSubset(of: batchSelectedPaths) {
            batchSelectedPaths.subtract(visible)
        } else {
            batchSelectedPaths.formUnion(visible)
        }
        updateBatchButtons()
        tableView.reloadData()
    }

    @objc private func copyBatchSelection() {
        guard let presenter = owningViewController else { return }
        let selected = rows.filter { batchSelectedPaths.contains($0.path) }
        guard !selected.isEmpty else { return }
        NBTEditingUI.copyTags(selected, from: presenter)
        statusLabel.text = "已复制 \(selected.count) 个 NBT 标签"
    }

    @objc private func exportBatchSelection() {
        guard let presenter = owningViewController else { return }
        let selected = rows.filter { batchSelectedPaths.contains($0.path) }
        guard !selected.isEmpty else { return }
        let base = block.map { "block-\($0.x)-\($0.y)-\($0.z)-selected" } ?? "block-nbt-selected"
        NBTExportUI.presentFormatChooser(
            from: presenter,
            documents: NBTExportUI.documents(from: selected),
            baseFilename: base,
            allowMCStructure: selected.count == 1,
            sourceView: batchExportButton
        )
    }

    @objc private func deleteBatchSelection() {
        guard let presenter = owningViewController, var document = document else { return }
        let selected = rows.filter { batchSelectedPaths.contains($0.path) }
        let paths = NBTTreeMutation.normalizedDeletionPaths(selected.map(\.path))
        guard !paths.isEmpty else { return }
        let alert = UIAlertController(
            title: "删除所选 NBT 标签？",
            message: "将删除 \(paths.count) 个标签及其全部子标签。保存方块后才会写回 SubChunk。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            do {
                document.root = try NBTTreeMutation.deleting(at: paths, in: document.root)
                self.document = document
                self.batchSelectedPaths.removeAll()
                self.expanded = [[]]
                self.dirty = true
                self.rebuildRows()
                self.statusLabel.text = "已删除 \(paths.count) 个 NBT 标签；请保存方块。"
            } catch {
                presenter.showError(error, title: "批量删除失败")
            }
        })
        presenter.present(alert, animated: true)
    }

    private func updateBatchButtons() {
        let visible = Set(rows.map(\.path))
        let allSelected = !visible.isEmpty && visible.isSubset(of: batchSelectedPaths)
        batchSelectAllButton.setTitle(allSelected ? "取消全选" : "全选", for: .normal)
        batchCopyButton.isEnabled = !batchSelectedPaths.isEmpty
        batchExportButton.isEnabled = !batchSelectedPaths.isEmpty
        batchDeleteButton.isEnabled = !batchSelectedPaths.isEmpty
        batchButton.isEnabled = !rows.isEmpty
    }

    @objc private func exportCurrentNBT() {
        guard let presenter = owningViewController, let document = document else { return }
        let base = block.map { "block-\($0.x)-\($0.y)-\($0.z)-layer-\(selectedLayerIndex)" } ?? "block-nbt"
        NBTExportUI.presentFormatChooser(
            from: presenter,
            documents: [document],
            baseFilename: base,
            sourceView: exportButton
        )
    }

    @objc private func addToRoot() {
        guard let root = document?.root, let presenter = owningViewController else { return }
        NBTEditingUI.presentAddOrPaste(from: presenter, container: root, sourceView: addButton) { [weak self] name, value, replacingExisting in
            self?.add(value: value, name: name, to: [], replacingExisting: replacingExisting)
        }
    }

    private func add(value: NBTValue, name: String?, to path: [NBTPathComponent], replacingExisting: Bool = false) {
        guard var document = document else { return }
        do {
            document.root = try NBTTreeMutation.adding(value, named: name, to: path, in: document.root, replacingExisting: replacingExisting)
            self.document = document
            expanded.insert(path)
            dirty = true
            rebuildRows()
        } catch { owningViewController?.showError(error, title: "增加失败") }
    }

    private func edit(_ node: NBTNode) {
        guard let presenter = owningViewController else { return }
        NBTEditingUI.presentEdit(from: presenter, node: node) { [weak self] replacement in
            guard let self = self, var document = self.document else { return }
            do {
                document.root = try NBTTreeMutation.replacingValue(at: node.path, in: document.root, with: replacement)
                self.document = document
                self.dirty = true
                self.rebuildRows()
            } catch { presenter.showError(error, title: "修改失败") }
        }
    }

    private func rename(_ node: NBTNode, to name: String) {
        guard var document = document else { return }
        do {
            document.root = try NBTTreeMutation.renaming(at: node.path, to: name, in: document.root)
            self.document = document
            expanded = [[]]
            dirty = true
            rebuildRows()
        } catch { owningViewController?.showError(error, title: "重命名失败") }
    }

    private func delete(_ node: NBTNode) {
        guard var document = document else { return }
        do {
            document.root = try NBTTreeMutation.deleting(at: node.path, in: document.root)
            self.document = document
            expanded = Set(expanded.filter { !$0.starts(with: node.path) })
            dirty = true
            rebuildRows()
        } catch { owningViewController?.showError(error, title: "删除失败") }
    }

    @objc private func saveBlock() {
        guard let block = block, let document = document, dirty else { return }
        saveButton.isEnabled = false
        statusLabel.text = "正在写回 SubChunk…"
        onSave?(block, selectedLayerIndex, document)
    }

    @objc private func layerChanged() {
        guard layerControl.selectedSegmentIndex >= 0 else { return }
        if dirty {
            let alert = UIAlertController(title: "放弃当前修改？", message: "切换图层会丢弃尚未保存的方块 NBT 修改。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
                guard let self = self else { return }
                self.layerControl.selectedSegmentIndex = self.selectedLayerIndex
            })
            alert.addAction(UIAlertAction(title: "放弃并切换", style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                self.selectedLayerIndex = self.layerControl.selectedSegmentIndex
                self.loadSelectedLayer()
            })
            owningViewController?.present(alert, animated: true)
        } else {
            selectedLayerIndex = layerControl.selectedSegmentIndex
            loadSelectedLayer()
        }
    }

    @objc private func jump() {
        endEditing(true)
        guard let x = Int64(xField.text ?? ""),
              let y = Int32(yField.text ?? ""),
              let z = Int64(zField.text ?? "") else {
            owningViewController?.showError(MCBEEditorError.malformedData("X、Y、Z 必须是整数"), title: "方块坐标错误")
            return
        }
        onJump?(x, y, z)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === xField { yField.becomeFirstResponder() }
        else if textField === yField { zField.becomeFirstResponder() }
        else { textField.resignFirstResponder(); jump() }
        return true
    }

    private var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
