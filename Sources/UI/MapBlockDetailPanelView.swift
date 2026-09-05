import UIKit

final class MapBlockDetailPanelView: UIView, UITextFieldDelegate, UITableViewDataSource,
  UITableViewDelegate
{
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
  private var editingLegacyNumeric = false

  private var isCompactPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

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
    titleLabel.font = isCompactPhone
      ? UIFont.systemFont(ofSize: 17, weight: .semibold)
      : .preferredFont(forTextStyle: .headline)
    titleLabel.mcbe_enableCompactSingleLineText(minimumScaleFactor: 0.72)

    collapseButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
    collapseButton.accessibilityLabel = "展开方块 NBT 侧栏"
    collapseButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
    collapseButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
    collapseButton.addTarget(self, action: #selector(toggleCollapsed), for: .touchUpInside)

    for (field, placeholder) in [(xField, "X"), (yField, "Y"), (zField, "Z")] {
      field.placeholder = placeholder
      field.borderStyle = .roundedRect
      field.keyboardType = .numbersAndPunctuation
      field.font = UIFont.monospacedDigitSystemFont(
        ofSize: isCompactPhone ? 11.5 : 13, weight: .regular)
      field.adjustsFontSizeToFitWidth = true
      field.minimumFontSize = isCompactPhone ? 8.5 : 10
      field.delegate = self
      field.accessibilityLabel = "方块坐标 \(placeholder)"
    }
    jumpButton.setTitle(isCompactPhone ? "查看" : "跳转并查看", for: .normal)
    jumpButton.titleLabel?.font = isCompactPhone
      ? UIFont.systemFont(ofSize: 11.5, weight: .semibold)
      : .preferredFont(forTextStyle: .subheadline)
    jumpButton.mcbe_enableCompactTitle(minimumScaleFactor: 0.68)
    jumpButton.setTitleColor(.white, for: .normal)
    jumpButton.backgroundColor = .systemBlue
    jumpButton.layer.cornerRadius = 8
    jumpButton.layer.masksToBounds = true
    jumpButton.contentEdgeInsets = UIEdgeInsets(
      top: isCompactPhone ? 5 : 8,
      left: isCompactPhone ? 7 : 14,
      bottom: isCompactPhone ? 5 : 8,
      right: isCompactPhone ? 7 : 14)
    jumpButton.heightAnchor.constraint(equalToConstant: isCompactPhone ? 32 : 36).isActive = true
    jumpButton.addTarget(self, action: #selector(jump), for: .touchUpInside)

    let coordinateRow = UIStackView(arrangedSubviews: [xField, yField, zField])
    coordinateRow.axis = .horizontal
    coordinateRow.spacing = isCompactPhone ? 4 : 6
    coordinateRow.distribution = .fillEqually
    coordinateRow.heightAnchor.constraint(equalToConstant: isCompactPhone ? 32 : 36).isActive = true

    coordinateLabel.font = UIFont.monospacedSystemFont(
      ofSize: isCompactPhone ? 9.2 : 11, weight: .regular)
    coordinateLabel.textColor = .secondaryLabel
    coordinateLabel.numberOfLines = isCompactPhone ? 2 : 0
    coordinateLabel.lineBreakMode = .byCharWrapping

    placeholderLabel.text = "点按地图方块或输入 X、Y、Z。\n\n选择后，这里以 NBT 树展示方块名称、版本和全部 states；长按标签可增、删、改。"
    placeholderLabel.font = .preferredFont(forTextStyle: .footnote)
    placeholderLabel.textColor = .secondaryLabel
    placeholderLabel.numberOfLines = 0

    layerControl.addTarget(self, action: #selector(layerChanged), for: .valueChanged)
    if isCompactPhone {
      layerControl.setTitleTextAttributes(
        [.font: UIFont.systemFont(ofSize: 11.5, weight: .medium)], for: .normal)
      layerControl.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }
    layerControl.isHidden = true

    addButton.setTitle(isCompactPhone ? "增加" : "增加根标签", for: .normal)
    addButton.titleLabel?.font = isCompactPhone
      ? UIFont.systemFont(ofSize: 10.5, weight: .regular)
      : .preferredFont(forTextStyle: .caption1)
    addButton.addTarget(self, action: #selector(addToRoot), for: .touchUpInside)
    saveButton.setTitle(isCompactPhone ? "保存" : "保存方块", for: .normal)
    saveButton.titleLabel?.font = isCompactPhone
      ? UIFont.systemFont(ofSize: 10.5, weight: .regular)
      : .preferredFont(forTextStyle: .caption1)
    saveButton.addTarget(self, action: #selector(saveBlock), for: .touchUpInside)
    returnToSearchButton.setTitle(isCompactPhone ? "结果" : "返回搜索结果", for: .normal)
    returnToSearchButton.titleLabel?.font = isCompactPhone
      ? UIFont.systemFont(ofSize: 10.5, weight: .regular)
      : .preferredFont(forTextStyle: .caption1)
    returnToSearchButton.addTarget(
      self, action: #selector(returnToSearchResults), for: .touchUpInside)
    returnToSearchButton.isHidden = true
    exportButton.setTitle("导出", for: .normal)
    exportButton.titleLabel?.font = isCompactPhone
      ? UIFont.systemFont(ofSize: 10.5, weight: .regular)
      : .preferredFont(forTextStyle: .caption1)
    exportButton.addTarget(self, action: #selector(exportCurrentNBT), for: .touchUpInside)
    batchButton.setTitle("选择", for: .normal)
    batchButton.titleLabel?.font = isCompactPhone
      ? UIFont.systemFont(ofSize: 10.5, weight: .regular)
      : .preferredFont(forTextStyle: .caption1)
    batchButton.addTarget(self, action: #selector(beginBatchSelection), for: .touchUpInside)
    actionsStack.addArrangedSubview(addButton)
    actionsStack.addArrangedSubview(saveButton)
    actionsStack.addArrangedSubview(returnToSearchButton)
    actionsStack.addArrangedSubview(exportButton)
    actionsStack.addArrangedSubview(batchButton)
    actionsStack.axis = .horizontal
    actionsStack.spacing = isCompactPhone ? 2 : 6
    actionsStack.distribution = .fillEqually
    for button in [addButton, saveButton, returnToSearchButton, exportButton, batchButton] {
      button.mcbe_enableCompactTitle(minimumScaleFactor: 0.62)
    }

    batchSelectAllButton.setTitle("全选", for: .normal)
    batchCopyButton.setTitle("复制", for: .normal)
    batchExportButton.setTitle("导出", for: .normal)
    batchDeleteButton.setTitle("删除", for: .normal)
    batchDeleteButton.setTitleColor(.systemRed, for: .normal)
    batchCancelButton.setTitle("取消", for: .normal)
    for button in [
      batchSelectAllButton, batchCopyButton, batchExportButton, batchDeleteButton,
      batchCancelButton,
    ] {
      button.titleLabel?.font = isCompactPhone
        ? UIFont.systemFont(ofSize: 9.8, weight: .regular)
        : .preferredFont(forTextStyle: .caption1)
      button.mcbe_enableCompactTitle(minimumScaleFactor: 0.58)
      batchActionsStack.addArrangedSubview(button)
    }
    batchSelectAllButton.addTarget(
      self, action: #selector(toggleBatchSelectAll), for: .touchUpInside)
    batchCopyButton.addTarget(self, action: #selector(copyBatchSelection), for: .touchUpInside)
    batchExportButton.addTarget(self, action: #selector(exportBatchSelection), for: .touchUpInside)
    batchDeleteButton.addTarget(self, action: #selector(deleteBatchSelection), for: .touchUpInside)
    batchCancelButton.addTarget(self, action: #selector(cancelBatchSelection), for: .touchUpInside)
    batchActionsStack.axis = .horizontal
    batchActionsStack.spacing = isCompactPhone ? 2 : 6
    batchActionsStack.distribution = .fillEqually
    batchActionsStack.isHidden = true

    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = isCompactPhone ? 42 : 50
    tableView.backgroundColor = .tertiarySystemBackground
    tableView.layer.cornerRadius = 8
    tableView.tableFooterView = UIView()
    tableView.setContentHuggingPriority(.defaultLow, for: .vertical)
    tableView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    statusLabel.font = isCompactPhone
      ? UIFont.systemFont(ofSize: 9.3, weight: .regular)
      : .preferredFont(forTextStyle: .caption2)
    statusLabel.textColor = .secondaryLabel
    statusLabel.numberOfLines = isCompactPhone ? 2 : 0
    statusLabel.lineBreakMode = .byCharWrapping

    let headerSpacer = UIView()
    headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let header = UIStackView(arrangedSubviews: [titleLabel, headerSpacer, collapseButton])
    header.axis = .horizontal
    header.alignment = .center
    header.spacing = 4

    if isCompactPhone {
      let coordinateAndJumpRow = UIStackView(arrangedSubviews: [coordinateRow, jumpButton])
      coordinateAndJumpRow.axis = .horizontal
      coordinateAndJumpRow.spacing = 4
      coordinateAndJumpRow.alignment = .fill
      coordinateAndJumpRow.distribution = .fill
      jumpButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
      bodyStack.addArrangedSubview(coordinateAndJumpRow)
    } else {
      bodyStack.addArrangedSubview(coordinateRow)
      bodyStack.addArrangedSubview(jumpButton)
    }
    for arranged in [
      separator(), placeholderLabel, coordinateLabel,
      layerControl, actionsStack, batchActionsStack, tableView, statusLabel,
    ] {
      bodyStack.addArrangedSubview(arranged)
    }
    bodyStack.axis = .vertical
    bodyStack.spacing = isCompactPhone ? 4 : 7

    collapsedSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    collapsedSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    let stack = UIStackView(arrangedSubviews: [header, bodyStack, collapsedSpacer])
    stack.axis = .vertical
    stack.spacing = isCompactPhone ? 4 : 7
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    let panelInset: CGFloat = isCompactPhone ? 6 : 9
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: panelInset),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -panelInset),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: panelInset),
      stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -panelInset),
    ])
    clearBlock()
  }


  override func layoutSubviews() {
    super.layoutSubviews()
    guard isCompactPhone, !tableView.isHidden else { return }
    tableView.isScrollEnabled = tableView.contentSize.height > tableView.bounds.height + 1
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
      self.collapseButton.setImage(
        UIImage(systemName: collapsed ? "chevron.left" : "chevron.right"), for: .normal)
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
    let dimension =
      BedrockDimension(rawValue: block.dimension)?.displayName ?? "维度 \(block.dimension)"
    if isCompactPhone {
      let chunkX = MapCoordinate.chunk(fromBlock: block.x)
      let chunkZ = MapCoordinate.chunk(fromBlock: block.z)
      let localX = Int(block.x - MapCoordinate.blockOrigin(ofChunk: chunkX))
      let localZ = Int(block.z - MapCoordinate.blockOrigin(ofChunk: chunkZ))
      let prefix = annotation.map { "\($0) · " } ?? ""
      coordinateLabel.text =
        "\(prefix)\(dimension) · X \(block.x)  Y \(block.y)  Z \(block.z)\n"
        + "区块(\(chunkX),\(chunkZ)) · 局部(\(localX),\(Int(block.y) & 15),\(localZ))"
    } else {
      let annotationLine = annotation.map { "\($0)\n" } ?? ""
      coordinateLabel.text =
        "\(annotationLine)\(dimension)\n\(block.coordinateDescription)\n\(block.chunkDescription)"
    }
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
    editingLegacyNumeric = false
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
    saveButton.isEnabled = dirty && legacyPairValidationError() == nil
    statusLabel.text = "保存失败：\(error.localizedDescription)"
    owningViewController?.showError(error, title: "保存方块 NBT 失败")
  }

  private func loadSelectedLayer() {
    cancelBatchSelection()
    guard let block = block,
      (0..<BedrockBlockRecord.editableLayerCount).contains(selectedLayerIndex)
    else {
      editingLegacyNumeric = false
      document = nil
      rows = []
      tableView.reloadData()
      return
    }
    let layerExists = block.layers.indices.contains(selectedLayerIndex)
    let state = block.stateForEditing(layer: selectedLayerIndex)
    if let root = state.nbt {
      editingLegacyNumeric = false
      document = NBTDocument(rootName: "", root: root)
      expanded = [[]]
      dirty = false
      statusLabel.text =
        layerExists
        ? (isCompactPhone ? "长按标签编辑；修改后点“保存”写回。" : "长按标签可增加、修改、重命名或删除；保存会直接写入 SubChunk。")
        : (isCompactPhone ? "该层不存在；修改后保存会创建。" : "层 \(selectedLayerIndex) 当前不存在，按空气层显示；修改并保存后会创建该层。")
      rebuildRows()
      return
    }

    if let legacyID = state.legacyID {
      editingLegacyNumeric = true
      let legacyData = state.legacyData ?? 0
      document = NBTDocument(
        rootName: "",
        root: .compound([
          NBTNamedTag(name: "legacy_id", value: .int(Int32(legacyID))),
          NBTNamedTag(name: "legacy_data", value: .byte(Int8(legacyData))),
          NBTNamedTag(name: "name", value: .string(state.name)),
        ]))
      expanded = [[]]
      dirty = false
      statusLabel.text = isCompactPhone
        ? "旧版数字 ID：name 🔗 legacy_id；修改任一方会同步。"
        : "旧版数字 ID 方块：name 与 legacy_id 为绑定对照；修改任一方会同步，且不能删除或重命名。没有数字 ID 对照的 name 不能保存。"
      rebuildRows()
      return
    }

    editingLegacyNumeric = false
    document = nil
    rows = []
    tableView.isHidden = false
    addButton.isEnabled = false
    saveButton.isEnabled = false
    exportButton.isEnabled = false
    statusLabel.text = "该图层没有可编辑的方块状态。"
    tableView.reloadData()
  }

  private func isLegacyTopLevelNode(_ node: NBTNode, named expectedName: String) -> Bool {
    guard editingLegacyNumeric, node.path.count == 1,
      case .compound(let actualName) = node.path[0]
    else { return false }
    return actualName.caseInsensitiveCompare(expectedName) == .orderedSame
  }

  private func isProtectedLegacyPairNode(_ node: NBTNode) -> Bool {
    isLegacyTopLevelNode(node, named: "name")
      || isLegacyTopLevelNode(node, named: "legacy_id")
  }

  private func numericValue(_ value: NBTValue) -> Int64? {
    switch value {
    case .byte(let number): return Int64(number)
    case .short(let number): return Int64(number)
    case .int(let number): return Int64(number)
    case .long(let number): return number
    case .float(let number):
      guard number.isFinite, number.rounded() == number else { return nil }
      return Int64(exactly: number)
    case .double(let number):
      guard number.isFinite, number.rounded() == number else { return nil }
      return Int64(exactly: number)
    default: return nil
    }
  }

  private func legacyPairValidationError() -> String? {
    guard editingLegacyNumeric, let document = document,
      case .compound(let tags) = document.root
    else { return nil }

    guard let nameTag = tags.first(where: { $0.name.caseInsensitiveCompare("name") == .orderedSame }),
      case .string(let rawName) = nameTag.value
    else {
      return "name 对照标签缺失或类型不是 String"
    }
    let canonical =
      BedrockLegacyBlockCatalog.blockIdentifier(forRawValue: rawName)
      ?? rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let entry = BedrockLegacyBlockCatalog.block(forIdentifier: canonical) else {
      return "\(rawName) 没有旧版数字 ID 对照"
    }

    guard let idTag = tags.first(where: {
      $0.name.caseInsensitiveCompare("legacy_id") == .orderedSame
    }), let id = numericValue(idTag.value), (0...255).contains(id) else {
      return "legacy_id 必须存在且为 0…255"
    }
    guard id == Int64(entry.id) else {
      return "name 与 legacy_id 不一致"
    }

    if let dataTag = tags.first(where: {
      $0.name.caseInsensitiveCompare("legacy_data") == .orderedSame
    }) {
      guard let data = numericValue(dataTag.value), (0...15).contains(data) else {
        return "legacy_data 必须为 0…15"
      }
    }
    return nil
  }

  private func synchronizeLegacyPair(afterEditing node: NBTNode, replacement: NBTValue) throws {
    guard editingLegacyNumeric, var document = document else { return }

    if isLegacyTopLevelNode(node, named: "name") {
      guard case .string(let rawName) = replacement else {
        throw MCBEEditorError.malformedData("旧版方块 name 必须是 String")
      }
      let canonical =
        BedrockLegacyBlockCatalog.blockIdentifier(forRawValue: rawName)
        ?? rawName.trimmingCharacters(in: .whitespacesAndNewlines)
      if let entry = BedrockLegacyBlockCatalog.block(forIdentifier: canonical) {
        document.root = try NBTTreeMutation.replacingValue(
          at: node.path, in: document.root, with: .string(entry.identifier))
        document.root = try NBTTreeMutation.replacingValue(
          at: [.compound("legacy_id")], in: document.root, with: .int(Int32(entry.id)))
      } else {
        // Keep the user's text visible for inspection, but leave the numeric ID
        // untouched. Validation disables Save until a legacy mapping exists.
        document.root = try NBTTreeMutation.replacingValue(
          at: node.path, in: document.root, with: replacement)
      }
      self.document = document
      return
    }

    if isLegacyTopLevelNode(node, named: "legacy_id") {
      guard let rawID = numericValue(replacement), (0...255).contains(rawID),
        let entry = BedrockLegacyBlockCatalog.block(forNumericID: Int(rawID))
      else {
        throw MCBEEditorError.malformedData("legacy_id 必须是 0…255 的旧版数字 ID")
      }
      document.root = try NBTTreeMutation.replacingValue(
        at: node.path, in: document.root, with: .int(Int32(rawID)))
      document.root = try NBTTreeMutation.replacingValue(
        at: [.compound("name")], in: document.root, with: .string(entry.identifier))
      self.document = document
    }
  }

  private func rebuildRows() {
    rows = document.map { NBTTreeRows.visibleChildren(of: $0.root, expanded: expanded) } ?? []
    addButton.isEnabled = document?.root.type == .compound || document?.root.type == .list
    let legacyError = legacyPairValidationError()
    saveButton.isEnabled = dirty && legacyError == nil
    exportButton.isEnabled = document != nil
    tableView.isHidden = document == nil
    let visiblePaths = Set(rows.map(\.path))
    batchSelectedPaths.formIntersection(visiblePaths)
    if editingLegacyNumeric {
      batchSelectedPaths = Set(
        rows.filter { batchSelectedPaths.contains($0.path) && !isProtectedLegacyPairNode($0) }
          .map(\.path))
      if dirty {
        statusLabel.text = legacyError.map { "不能保存：\($0)" }
          ?? (isCompactPhone ? "name 🔗 legacy_id 已同步；可保存。" : "name 与 legacy_id 已同步，可保存旧版数字 ID 方块。")
      }
    }
    updateBatchButtons()
    tableView.reloadData()
  }

  func numberOfSections(in tableView: UITableView) -> Int { 1 }
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let node = rows[indexPath.row]
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "BlockNBTCell")
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BlockNBTCell")
    cell.indentationLevel = node.depth
    cell.indentationWidth = isCompactPhone ? 10 : 13
    cell.textLabel?.font = UIFont.monospacedSystemFont(
      ofSize: isCompactPhone ? 10.6 : 11.5, weight: .regular)
    cell.detailTextLabel?.font = UIFont.monospacedSystemFont(
      ofSize: isCompactPhone ? 9.4 : 10.5, weight: .regular)
    cell.detailTextLabel?.textColor = .secondaryLabel
    cell.detailTextLabel?.numberOfLines = 2
    cell.detailTextLabel?.lineBreakMode = .byCharWrapping
    cell.imageView?.image = NBTTagIcon.image(for: node.value.type)
    cell.imageView?.contentMode = .center
    let marker = node.hasChildren ? (expanded.contains(node.path) ? "▾" : "▸") : " "
    let linkedMarker = isLegacyTopLevelNode(node, named: "name") ? " 🔗" : ""
    cell.textLabel?.text = "\(marker) \(node.name)\(linkedMarker)"
    cell.detailTextLabel?.text = "\(node.value.type.displayName) · \(node.value.summary)"
    cell.accessoryType =
      isBatchSelecting
      ? (batchSelectedPaths.contains(node.path) ? .checkmark : .none)
      : (node.hasChildren ? .none : .disclosureIndicator)
    cell.mcbe_enableCompactText()
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let node = rows[indexPath.row]
    if isBatchSelecting {
      if isProtectedLegacyPairNode(node) {
        statusLabel.text = "name 与 legacy_id 为绑定字段，不能批量删除。"
        return
      }
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
      if expanded.contains(node.path) {
        expanded.remove(node.path)
      } else {
        expanded.insert(node.path)
      }
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
      let protectedLegacyPair = self.isProtectedLegacyPairNode(node)
      var actions = [UIAction]()
      if case .compound = node.value {
        actions.append(
          UIAction(title: "增加子标签", image: UIImage(systemName: "plus")) { [weak self] _ in
            guard let self = self else { return }
            guard let presenter = self.owningViewController else { return }
            NBTEditingUI.presentAdd(
              from: presenter, container: node.value,
              sourceView: tableView.cellForRow(at: indexPath)
            ) { [weak self] name, value, replacingExisting in
              self?.add(
                value: value, name: name, to: node.path, replacingExisting: replacingExisting)
            }
          })
      } else if case .list = node.value {
        actions.append(
          UIAction(title: "增加列表元素", image: UIImage(systemName: "plus")) { [weak self] _ in
            guard let self = self else { return }
            guard let presenter = self.owningViewController else { return }
            NBTEditingUI.presentAdd(
              from: presenter, container: node.value,
              sourceView: tableView.cellForRow(at: indexPath)
            ) { [weak self] name, value, replacingExisting in
              self?.add(
                value: value, name: name, to: node.path, replacingExisting: replacingExisting)
            }
          })
      }
      if node.value.isDirectlyEditable {
        actions.append(
          UIAction(title: "修改值", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
            self?.edit(node)
          })
      }
      if case .compound? = node.path.last, !protectedLegacyPair {
        actions.append(
          UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in
            guard let self = self, let presenter = self.owningViewController else { return }
            NBTEditingUI.presentRename(from: presenter, currentName: node.name) {
              [weak self] name in self?.rename(node, to: name)
            }
          })
      }
      if let presenter = self.owningViewController {
        actions.append(
          contentsOf: NBTEditingUI.clipboardActions(
            from: presenter,
            node: node,
            sourceView: tableView.cellForRow(at: indexPath)
          ) { [weak self] name, value, replacingExisting in
            self?.add(value: value, name: name, to: node.path, replacingExisting: replacingExisting)
          })
      }
      if protectedLegacyPair {
        actions.append(
          UIAction(
            title: "绑定对照字段", image: UIImage(systemName: "link"),
            attributes: .disabled, handler: { _ in }))
      } else {
        actions.append(
          UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) {
            [weak self] _ in
            guard let self = self, let presenter = self.owningViewController else { return }
            NBTEditingUI.confirmDelete(from: presenter, nodeName: node.name) { [weak self] in
              self?.delete(node)
            }
          })
      }
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
    let visible = Set(rows.filter { !isProtectedLegacyPairNode($0) }.map(\.path))
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
    let selected = rows.filter {
      batchSelectedPaths.contains($0.path) && !isProtectedLegacyPairNode($0)
    }
    let paths = NBTTreeMutation.normalizedDeletionPaths(selected.map(\.path))
    guard !paths.isEmpty else { return }
    let alert = UIAlertController(
      title: "删除所选 NBT 标签？",
      message: "将删除 \(paths.count) 个标签及其全部子标签。保存方块后才会写回 SubChunk。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
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
    let visible = Set(rows.filter { !isProtectedLegacyPairNode($0) }.map(\.path))
    let allSelected = !visible.isEmpty && visible.isSubset(of: batchSelectedPaths)
    batchSelectAllButton.setTitle(allSelected ? "取消全选" : "全选", for: .normal)
    batchCopyButton.isEnabled = !batchSelectedPaths.isEmpty
    batchExportButton.isEnabled = !batchSelectedPaths.isEmpty
    batchDeleteButton.isEnabled = !batchSelectedPaths.isEmpty
    batchButton.isEnabled = !rows.isEmpty
  }

  @objc private func exportCurrentNBT() {
    guard let presenter = owningViewController, let document = document else { return }
    let base =
      block.map { "block-\($0.x)-\($0.y)-\($0.z)-layer-\(selectedLayerIndex)" } ?? "block-nbt"
    NBTExportUI.presentFormatChooser(
      from: presenter,
      documents: [document],
      baseFilename: base,
      sourceView: exportButton
    )
  }

  @objc private func addToRoot() {
    guard let root = document?.root, let presenter = owningViewController else { return }
    NBTEditingUI.presentAddOrPaste(from: presenter, container: root, sourceView: addButton) {
      [weak self] name, value, replacingExisting in
      self?.add(value: value, name: name, to: [], replacingExisting: replacingExisting)
    }
  }

  private func add(
    value: NBTValue, name: String?, to path: [NBTPathComponent], replacingExisting: Bool = false
  ) {
    guard var document = document else { return }
    if editingLegacyNumeric, path.isEmpty,
      let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      ["name", "legacy_id"].contains(normalizedName)
    {
      owningViewController?.showError(
        MCBEEditorError.unsupported("name 与 legacy_id 为绑定字段，已存在时只能修改值，不能通过增加/粘贴替换。"),
        title: "受保护字段")
      return
    }
    do {
      document.root = try NBTTreeMutation.adding(
        value, named: name, to: path, in: document.root, replacingExisting: replacingExisting)
      self.document = document
      expanded.insert(path)
      dirty = true
      rebuildRows()
    } catch { owningViewController?.showError(error, title: "增加失败") }
  }

  private func edit(_ node: NBTNode) {
    guard let presenter = owningViewController else { return }
    NBTEditingUI.presentEdit(from: presenter, node: node) { [weak self] replacement in
      guard let self = self else { return }
      do {
        if self.isProtectedLegacyPairNode(node) {
          try self.synchronizeLegacyPair(afterEditing: node, replacement: replacement)
        } else {
          guard var document = self.document else { return }
          document.root = try NBTTreeMutation.replacingValue(
            at: node.path, in: document.root, with: replacement)
          self.document = document
        }
        self.dirty = true
        self.rebuildRows()
      } catch { presenter.showError(error, title: "修改失败") }
    }
  }

  private func rename(_ node: NBTNode, to name: String) {
    guard !isProtectedLegacyPairNode(node) else {
      owningViewController?.showError(
        MCBEEditorError.unsupported("name 与 legacy_id 为绑定字段，不能重命名。"), title: "受保护字段")
      return
    }
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
    guard !isProtectedLegacyPairNode(node) else {
      owningViewController?.showError(
        MCBEEditorError.unsupported("name 与 legacy_id 为绑定字段，不能删除。"), title: "受保护字段")
      return
    }
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
    if let legacyError = legacyPairValidationError() {
      let error = MCBEEditorError.unsupported(legacyError)
      statusLabel.text = "不能保存：\(legacyError)"
      owningViewController?.showError(error, title: "旧版方块无法保存")
      return
    }
    saveButton.isEnabled = false
    statusLabel.text = "正在写回 SubChunk…"
    onSave?(block, selectedLayerIndex, document)
  }

  @objc private func layerChanged() {
    guard layerControl.selectedSegmentIndex >= 0 else { return }
    if dirty {
      let alert = UIAlertController(
        title: "放弃当前修改？", message: "切换图层会丢弃尚未保存的方块 NBT 修改。", preferredStyle: .alert)
      alert.addAction(
        UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
          guard let self = self else { return }
          self.layerControl.selectedSegmentIndex = self.selectedLayerIndex
        })
      alert.addAction(
        UIAlertAction(title: "放弃并切换", style: .destructive) { [weak self] _ in
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
      let z = Int64(zField.text ?? "")
    else {
      owningViewController?.showError(MCBEEditorError.malformedData("X、Y、Z 必须是整数"), title: "方块坐标错误")
      return
    }
    onJump?(x, y, z)
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if textField === xField {
      yField.becomeFirstResponder()
    } else if textField === yField {
      zField.becomeFirstResponder()
    } else {
      textField.resignFirstResponder()
      jump()
    }
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
