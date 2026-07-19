import UIKit

final class HardcodedSpawnersViewController: UITableViewController {
  private let session: WorldSession
  private let chunk: ChunkPosition
  private let store: BedrockChunkStore
  private let queue = DispatchQueue(
    label: "com.wzn.mcbeeditor.hardcoded-spawners", qos: .userInitiated)
  private var record: BedrockChunkStore.HardcodedSpawnersRecord?
  private var dirty = false
  private let initialAreaIndex: Int?
  private var didOpenInitialArea = false
  var onSave: ((String) -> Void)?

  init(session: WorldSession, chunk: ChunkPosition, selectedAreaIndex: Int? = nil) {
    self.session = session
    self.chunk = chunk
    self.initialAreaIndex = selectedAreaIndex
    self.store = BedrockChunkStore(session: session)
    super.init(style: .insetGrouped)
    title = "HardcodedSpawners"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(confirmSave)),
      UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addArea)),
    ]
    navigationItem.rightBarButtonItems?.first?.isEnabled = false
    loadRecord()
  }

  private func loadRecord() {
    let overlay = showBusy("读取 HardcodedSpawners…")
    queue.async { [weak self] in
      guard let self = self else { return }
      do {
        let value = try self.store.hardcodedSpawnersRecord(at: self.chunk)
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.record = value
          self.dirty = false
          self.navigationItem.rightBarButtonItems?.first?.isEnabled = false
          self.tableView.reloadData()
          self.openInitialAreaIfNeeded()
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "读取 HardcodedSpawners 失败")
        }
      }
    }
  }

  override func numberOfSections(in tableView: UITableView) -> Int { 1 }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    record?.document.areas.count ?? 0
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    let dimension =
      BedrockDimension(rawValue: chunk.dimension)?.displayName ?? "维度 \(chunk.dimension)"
    return "\(dimension) 区块 (\(chunk.x), \(chunk.z))"
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    if record?.document.areas.isEmpty != false {
      return "没有记录。点击右上角＋可以创建；保存空列表会删除 HardcodedSpawners 键。"
    }
    return "记录格式为最小坐标、最大坐标和刷怪类型。点击编辑，左滑删除，完成后保存。"
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "Spawner")
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: "Spawner")
    guard let area = record?.document.areas[indexPath.row] else { return cell }
    cell.textLabel?.text = area.kind.displayName
    cell.detailTextLabel?.text = area.rangeText
    cell.imageView?.image = UIImage(systemName: "scope")
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    editArea(at: indexPath.row)
  }

  private func editArea(at index: Int) {
    guard let current = record, current.document.areas.indices.contains(index) else { return }
    let area = current.document.areas[index]
    openEditor(area: area) { [weak self] replacement in
      guard let self = self, var current = self.record,
        current.document.areas.indices.contains(index)
      else { return }
      current.document.areas[index] = replacement
      self.record = current
      self.markDirty()
      let indexPath = IndexPath(row: index, section: 0)
      if self.tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
        self.tableView.reloadRows(at: [indexPath], with: .automatic)
      } else {
        self.tableView.reloadData()
      }
    }
  }

  private func openInitialAreaIfNeeded() {
    guard !didOpenInitialArea, let index = initialAreaIndex else { return }
    didOpenInitialArea = true
    guard record?.document.areas.indices.contains(index) == true else {
      navigationItem.prompt = "地图中选中的刷怪区域已发生变化，请重新选择。"
      return
    }
    let indexPath = IndexPath(row: index, section: 0)
    tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
    DispatchQueue.main.async { [weak self] in self?.editArea(at: index) }
  }

  override func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    let action = UIContextualAction(style: .destructive, title: "删除") {
      [weak self] _, _, completion in
      guard let self = self, var current = self.record else {
        completion(false)
        return
      }
      current.document.areas.remove(at: indexPath.row)
      self.record = current
      self.markDirty()
      self.tableView.deleteRows(at: [indexPath], with: .automatic)
      completion(true)
    }
    let configuration = UISwipeActionsConfiguration(actions: [action])
    configuration.performsFirstActionWithFullSwipe = false
    return configuration
  }

  @objc private func addArea() {
    let blockX = chunk.x * 16
    let blockZ = chunk.z * 16
    let area = HardcodedSpawnerArea(
      minimumX: blockX,
      minimumY: 0,
      minimumZ: blockZ,
      maximumX: blockX + 15,
      maximumY: 255,
      maximumZ: blockZ + 15,
      kind: .netherFortress
    )
    openEditor(area: area) { [weak self] replacement in
      guard let self = self, var current = self.record else { return }
      current.document.areas.append(replacement)
      self.record = current
      self.markDirty()
      self.tableView.reloadData()
    }
  }

  private func openEditor(
    area: HardcodedSpawnerArea, completion: @escaping (HardcodedSpawnerArea) -> Void
  ) {
    let editor = HardcodedSpawnerAreaEditorViewController(area: area)
    editor.onCommit = completion
    navigationController?.pushViewController(editor, animated: true)
  }

  private func markDirty() {
    dirty = true
    navigationItem.rightBarButtonItems?.first?.isEnabled = true
    title = "HardcodedSpawners •"
  }

  @objc private func confirmSave() {
    guard dirty else { return }
    let alert = UIAlertController(
      title: "保存 HardcodedSpawners？",
      message: "将直接修改当前区块的 0x39 记录。请确保 Minecraft 已完全退出。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "保存", style: .destructive) { [weak self] _ in self?.save() })
    present(alert, animated: true)
  }

  private func save() {
    guard let record = record else { return }
    let overlay = showBusy("写入 HardcodedSpawners…")
    queue.async { [weak self] in
      guard let self = self else { return }
      do {
        try self.store.saveHardcodedSpawnersRecord(record)
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.dirty = false
          self.title = "HardcodedSpawners"
          self.navigationItem.rightBarButtonItems?.first?.isEnabled = false
          let message =
            record.document.areas.isEmpty
            ? "已删除 HardcodedSpawners 记录。"
            : "已保存 \(record.document.areas.count) 个 HardcodedSpawners 区域。"
          self.navigationItem.prompt = message
          self.onSave?(message)
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "保存 HardcodedSpawners 失败")
        }
      }
    }
  }
}

private final class HardcodedSpawnerAreaEditorViewController: UIViewController, UITextFieldDelegate
{
  private var area: HardcodedSpawnerArea
  private let fields = (0..<6).map { _ in UITextField() }
  private let kindControl = UISegmentedControl(items: ["要塞", "沼泽小屋", "神殿", "前哨站", "自定义"])
  private let customKindField = UITextField()
  var onCommit: ((HardcodedSpawnerArea) -> Void)?

  init(area: HardcodedSpawnerArea) {
    self.area = area
    super.init(nibName: nil, bundle: nil)
    title = "刷怪区域"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "完成", style: .done, target: self, action: #selector(commit))

    let labels = ["最小 X", "最小 Y", "最小 Z", "最大 X", "最大 Y", "最大 Z"]
    let values = [
      area.minimumX, area.minimumY, area.minimumZ, area.maximumX, area.maximumY, area.maximumZ,
    ]
    var rows = [UIView]()
    for index in fields.indices {
      let field = fields[index]
      field.borderStyle = .roundedRect
      field.keyboardType = .numbersAndPunctuation
      field.text = String(values[index])
      field.delegate = self
      rows.append(labelled(labels[index], field))
    }
    kindControl.selectedSegmentIndex = segmentIndex(for: area.kind)
    kindControl.addTarget(self, action: #selector(kindChanged), for: .valueChanged)
    customKindField.borderStyle = .roundedRect
    customKindField.keyboardType = .numberPad
    customKindField.placeholder = "0…255"
    customKindField.text = String(area.kind.rawValue)
    customKindField.delegate = self
    customKindField.isHidden = kindControl.selectedSegmentIndex != 4

    let help = UILabel()
    help.numberOfLines = 0
    help.font = .preferredFont(forTextStyle: .footnote)
    help.textColor = .secondaryLabel
    help.text = "HardcodedSpawners 的坐标是绝对方块坐标。未知类型会按原始 UInt8 数值保存。"

    let stack = UIStackView(
      arrangedSubviews: [labelled("刷怪类型", kindControl), labelled("自定义类型", customKindField)] + rows
        + [help])
    stack.axis = .vertical
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
    ])
  }

  private func labelled(_ title: String, _ content: UIView) -> UIView {
    let label = UILabel()
    label.text = title
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.textColor = .secondaryLabel
    let stack = UIStackView(arrangedSubviews: [label, content])
    stack.axis = .vertical
    stack.spacing = 5
    return stack
  }

  private func segmentIndex(for kind: HardcodedSpawnerKind) -> Int {
    switch kind {
    case .netherFortress: return 0
    case .swampHut: return 1
    case .oceanMonument: return 2
    case .pillagerOutpost: return 3
    case .custom: return 4
    }
  }

  @objc private func kindChanged() {
    customKindField.isHidden = kindControl.selectedSegmentIndex != 4
  }

  @objc private func commit() {
    let parsedValues = fields.map {
      Int32($0.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
    guard parsedValues.count == 6, parsedValues.allSatisfy({ $0 != nil }) else {
      showError(MCBEEditorError.malformedData("六个坐标必须是有效 Int32"))
      return
    }
    let values = parsedValues.compactMap { $0 }
    let kind: HardcodedSpawnerKind
    switch kindControl.selectedSegmentIndex {
    case 0: kind = .netherFortress
    case 1: kind = .swampHut
    case 2: kind = .oceanMonument
    case 3: kind = .pillagerOutpost
    default:
      guard
        let raw = UInt8(customKindField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
      else {
        showError(MCBEEditorError.malformedData("自定义类型必须是 0…255"))
        return
      }
      kind = .custom(raw)
    }
    do {
      let result = try HardcodedSpawnerArea(
        minimumX: values[0], minimumY: values[1], minimumZ: values[2],
        maximumX: values[3], maximumY: values[4], maximumZ: values[5],
        kind: kind
      ).validated()
      onCommit?(result)
      navigationController?.popViewController(animated: true)
    } catch {
      showError(error, title: "区域参数无效")
    }
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    return true
  }
}
