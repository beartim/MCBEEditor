import UIKit

final class MapRegionCopyViewController: UIViewController, UITextFieldDelegate {
    private let session: WorldSession
    private let source: BedrockMapRegion
    private let xField = UITextField()
    private let zField = UITextField()
    private let dimensionControl = UISegmentedControl(items: BedrockDimension.allCases.map(\.displayName))
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.region-copy", qos: .userInitiated)
    var onComplete: ((String, BedrockMapRegion) -> Void)?

    init(session: WorldSession, source: BedrockMapRegion) {
        self.session = session
        self.source = source
        super.init(nibName: nil, bundle: nil)
        title = "复制区域"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "复制", style: .done, target: self, action: #selector(confirmCopy))
        for field in [xField, zField] {
            field.borderStyle = .roundedRect
            field.keyboardType = .numbersAndPunctuation
            field.delegate = self
        }
        xField.text = String(source.minimumX)
        zField.text = String(source.minimumZ)
        dimensionControl.selectedSegmentIndex = BedrockDimension.allCases.firstIndex(where: { $0.rawValue == source.dimension }) ?? 0

        let summary = UILabel()
        summary.numberOfLines = 0
        summary.font = .preferredFont(forTextStyle: .headline)
        summary.text = "源区域：\(source.coordinateText)\n大小：\(source.width) × \(source.depth) 方块"

        let help = UILabel()
        help.numberOfLines = 0
        help.font = .preferredFont(forTextStyle: .footnote)
        help.textColor = .secondaryLabel
        help.text = "只需输入目标区域左上角 X0、Z0；X1、Z1 会按源区域大小自动计算。复制层 0/层 1 的全部垂直方块状态，并复制生物群系与方块实体；不会复制普通实体、刻计划或 HardcodedSpawners。目标区域已有内容会被覆盖。"

        let stack = UIStackView(arrangedSubviews: [
            summary,
            labelled("目标维度", dimensionControl),
            labelled("目标 X0", xField),
            labelled("目标 Z0", zField),
            help
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }

    private func labelled(_ title: String, _ control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    @objc private func confirmCopy() {
        guard let x = Int64(xField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              let z = Int64(zField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else {
            showError(MCBEEditorError.malformedData("请输入有效的目标 X0、Z0"))
            return
        }
        let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
        let destination = source.translated(toMinimumX: x, minimumZ: z, dimension: dimension)
        let alert = UIAlertController(
            title: "覆盖目标区域？",
            message: "目标区域为 \(destination.coordinateText)，大小与源区域相同。该操作不会自动备份。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "复制", style: .destructive) { [weak self] _ in
            self?.performCopy(x: x, z: z, dimension: dimension)
        })
        present(alert, animated: true)
    }

    private func performCopy(x: Int64, z: Int64, dimension: Int32) {
        let overlay = showBusy("复制区域方块状态…")
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try BedrockChunkStore(session: self.session).copyRegion(
                    self.source,
                    toMinimumX: x,
                    minimumZ: z,
                    dimension: dimension
                )
                var message: String
                if result.usedWholeChunkCopy {
                    message = "区域已按完整区块复制，共写入 \(result.copiedRecordCount) 条地形、生物群系、方块实体和区块状态记录。"
                } else {
                    message = "已复制 \(result.copiedBlockStateCount) 个方块层状态，写回 \(result.writtenSubChunkCount) 个 SubChunk。"
                    if result.copiedBiomeCellCount > 0 { message += " 同时复制 \(result.copiedBiomeCellCount) 个生物群系位置。" }
                    if result.copiedBlockEntityCount > 0 { message += " 同时复制 \(result.copiedBlockEntityCount) 个方块实体。" }
                }
                if result.skippedLegacyStateCount > 0 {
                    message += " 跳过 \(result.skippedLegacyStateCount) 个旧版数字 ID 状态。"
                }
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.onComplete?(message, result.destination)
                    let alert = UIAlertController(title: "复制完成", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "复制区域失败")
                }
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

final class MapRegionBiomeViewController: UIViewController {
    private let session: WorldSession
    private let region: BedrockMapRegion
    private let selectedLabel = UILabel()
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.region-biome", qos: .userInitiated)
    private var selectedID: UInt32?
    var onComplete: ((String) -> Void)?

    init(session: WorldSession, region: BedrockMapRegion) {
        self.session = session
        self.region = region
        super.init(nibName: nil, bundle: nil)
        title = "区域生物群系"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "应用", style: .done, target: self, action: #selector(confirmApply))
        navigationItem.rightBarButtonItem?.isEnabled = false

        let summary = UILabel()
        summary.numberOfLines = 0
        summary.font = .preferredFont(forTextStyle: .headline)
        summary.text = "范围：\(region.coordinateText)\n涉及 \(region.chunkCount) 个区块"

        selectedLabel.numberOfLines = 0
        selectedLabel.text = "尚未选择生物群系 ID"
        selectedLabel.textColor = .secondaryLabel

        let choose = UIButton(type: .system)
        choose.setTitle("选择生物群系 ID…", for: .normal)
        choose.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        choose.addTarget(self, action: #selector(chooseBiome), for: .touchUpInside)

        let help = UILabel()
        help.numberOfLines = 0
        help.font = .preferredFont(forTextStyle: .footnote)
        help.textColor = .secondaryLabel
        help.text = "Data2D 修改选区内的水平格；Data3D 修改所有已保存垂直层中的选区列。不存在的生物群系记录和缺失 Data3D 层会被跳过。"

        let stack = UIStackView(arrangedSubviews: [summary, selectedLabel, choose, help])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }

    @objc private func chooseBiome() {
        let picker = BiomeIDPickerViewController(currentID: selectedID)
        picker.onSelect = { [weak self] id in
            self?.selectedID = id
            self?.selectedLabel.text = "ID \(id) · \(BedrockBiomeCatalog.displayName(for: id))\n\(BedrockBiomeCatalog.identifier(for: id) ?? "未知 identifier")"
            self?.selectedLabel.textColor = .label
            self?.navigationItem.rightBarButtonItem?.isEnabled = true
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    @objc private func confirmApply() {
        guard let id = selectedID else { return }
        let alert = UIAlertController(
            title: "修改区域生物群系？",
            message: "将把选区内所有可编辑生物群系位置设置为 ID \(id)。此操作不会自动备份。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "应用", style: .destructive) { [weak self] _ in self?.apply(id) })
        present(alert, animated: true)
    }

    private func apply(_ id: UInt32) {
        let overlay = showBusy("写入区域生物群系…")
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try BedrockChunkStore(session: self.session).setBiomeID(id, in: self.region)
                let message = "已修改 \(result.changedChunkCount) 个区块、\(result.detailCount) 个生物群系位置；跳过 \(result.skippedChunkCount) 个无记录区块。"
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.onComplete?(message)
                    self.navigationItem.prompt = message
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "区域生物群系修改失败")
                }
            }
        }
    }
}

final class MapRegionHardcodedSpawnersViewController: UITableViewController {
    private let session: WorldSession
    private let region: BedrockMapRegion
    private let store: BedrockChunkStore
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.region-hardcoded-spawners", qos: .userInitiated)
    private var summaries = [BedrockChunkSummary]()
    var onMutation: ((String) -> Void)?

    init(session: WorldSession, region: BedrockMapRegion) {
        self.session = session
        self.region = region
        self.store = BedrockChunkStore(session: session)
        super.init(style: .insetGrouped)
        title = "区域 HardcodedSpawners"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.prompt = region.coordinateText
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(loadChunks))
        loadChunks()
    }

    @objc private func loadChunks() {
        let overlay = showBusy("读取选区区块…")
        queue.async { [weak self] in
            guard let self = self else { return }
            var values = [BedrockChunkSummary]()
            for position in self.region.chunkPositions {
                if let summary = try? self.store.summary(at: position) { values.append(summary) }
            }
            DispatchQueue.main.async {
                overlay.removeFromSuperview()
                self.summaries = values
                self.tableView.reloadData()
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { summaries.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "点击区块进入 HardcodedSpawners 编辑页。没有记录的区块也可创建新区域。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let summary = summaries[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "RegionSpawnerChunk") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "RegionSpawnerChunk")
        cell.textLabel?.text = "区块 (\(summary.position.x), \(summary.position.z))"
        cell.detailTextLabel?.text = summary.hasHardcodedSpawners ? "已有 HardcodedSpawners" : "没有记录，可创建"
        cell.imageView?.image = UIImage(systemName: summary.hasHardcodedSpawners ? "scope" : "plus.square")
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let summary = summaries[indexPath.row]
        let controller = HardcodedSpawnersViewController(session: session, chunk: summary.position)
        controller.onSave = { [weak self] message in
            self?.onMutation?(message)
            self?.loadChunks()
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}
