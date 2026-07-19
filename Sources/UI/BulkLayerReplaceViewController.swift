import UIKit

final class BulkLayerReplaceViewController: UIViewController {
    private let session: WorldSession
    private let chunk: ChunkPosition?
    private let region: BedrockMapRegion?
    private let chunks: [ChunkPosition]?
    private let targetLayerControl = UISegmentedControl(items: ["层 0", "层 1"])
    private let includeAirSwitch = UISwitch()
    private let layer0Editor = BlockSearchReplaceNBTEditorView(layerIndex: 0, mode: .replacement)
    private let layer1Editor = BlockSearchReplaceNBTEditorView(layerIndex: 1, mode: .replacement)
    private let editorContainer = UIView()
    private let queue = DispatchQueue(label: "com.wzn.mcbeeditor.bulk-layer-replace", qos: .userInitiated)

    var onComplete: ((String) -> Void)?

    init(session: WorldSession, chunk: ChunkPosition) {
        self.session = session
        self.chunk = chunk
        self.region = nil
        self.chunks = nil
        super.init(nibName: nil, bundle: nil)
        title = "批量层0层1替换"
    }

    init(session: WorldSession, region: BedrockMapRegion) {
        self.session = session
        self.chunk = nil
        self.region = region
        self.chunks = nil
        super.init(nibName: nil, bundle: nil)
        title = "区域批量层0层1替换"
    }

    init(session: WorldSession, chunks: [ChunkPosition]) {
        self.session = session
        self.chunk = nil
        self.region = nil
        self.chunks = chunks
        super.init(nibName: nil, bundle: nil)
        title = "所选区块批量层0层1替换"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        targetLayerControl.selectedSegmentIndex = 1
        targetLayerControl.addTarget(self, action: #selector(targetLayerChanged), for: .valueChanged)
        includeAirSwitch.isOn = false

        let dimensionValue = chunk?.dimension ?? region?.dimension ?? chunks?.first?.dimension ?? 0
        let dimension = BedrockDimension(rawValue: dimensionValue)?.displayName ?? "维度 \(dimensionValue)"
        let info = UILabel()
        info.font = .preferredFont(forTextStyle: .headline)
        info.numberOfLines = 0
        if let chunk = chunk {
            info.text = "\(dimension) 区块 (\(chunk.x), \(chunk.z))"
        } else if let region = region {
            info.text = "\(dimension) \(region.coordinateText)；\(region.width)×\(region.depth) 方块"
        } else if let chunks = chunks {
            let dimensionCount = Set(chunks.map(\.dimension)).count
            info.text = dimensionCount == 1
                ? "\(dimension) · 已选择 \(chunks.count) 个区块"
                : "已选择 \(chunks.count) 个区块 · \(dimensionCount) 个维度"
        }

        let targetRow = labelledRow(title: "批量替换层", control: targetLayerControl)
        let airRow = labelledRow(title: "选择双层皆为空气的方块", control: includeAirSwitch)
        let note = UILabel()
        note.numberOfLines = 0
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        if let chunks = chunks {
            note.text = "默认仅处理所选 \(chunks.count) 个区块中层 0 或层 1 至少一层非空气的位置。开启后，每个现有 SubChunk 的全部 4096 个位置都会参与。缺失的目标层会自动创建。"
        } else {
            note.text = region == nil
                ? "默认仅处理层 0 或层 1 至少一层非空气的位置。开启后，当前区块现有 SubChunk 内全部 4096 个位置都会参与。缺失的目标层会自动创建。"
                : "默认仅处理框选 X-Z 范围内层 0 或层 1 至少一层非空气的位置。开启后，框选范围在现有 SubChunk 中的全部高度位置都会参与。框外方块保持不变，缺失的目标层会自动创建。"
        }

        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        for editor in [layer0Editor, layer1Editor] {
            editor.translatesAutoresizingMaskIntoConstraints = false
            editorContainer.addSubview(editor)
            NSLayoutConstraint.activate([
                editor.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
                editor.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
                editor.topAnchor.constraint(equalTo: editorContainer.topAnchor),
                editor.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor)
            ])
        }
        editorContainer.heightAnchor.constraint(equalToConstant: 310).isActive = true

        let replaceButton = blueButton(
            title: chunks != nil ? "执行所选区块批量替换" : (region == nil ? "执行批量替换" : "执行框选区域批量替换"),
            action: #selector(confirmBulkReplace)
        )

        let content = UIStackView(arrangedSubviews: [info, targetRow, airRow, note, editorContainer, replaceButton])
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        targetLayerChanged()
    }

    private func labelledRow(title: String, control: UIView) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        let row = UIStackView(arrangedSubviews: [label, UIView(), control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        return row
    }

    private func blueButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.layer.cornerRadius = 10
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func targetLayerChanged() {
        let layer = targetLayerControl.selectedSegmentIndex
        layer0Editor.isHidden = layer != 0
        layer1Editor.isHidden = layer != 1
    }

    @objc private func confirmBulkReplace() {
        let layer = targetLayerControl.selectedSegmentIndex
        let editor = layer == 0 ? layer0Editor : layer1Editor
        guard editor.explicitBlockName != nil else {
            showError(MCBEEditorError.malformedData("请在层 \(layer) 编辑器中填写目标方块 name"), title: "缺少目标方块")
            return
        }
        let airText = includeAirSwitch.isOn ? "包括双层皆为空气的位置" : "跳过双层皆为空气的位置"
        let targetText: String
        if let chunks = chunks {
            targetText = "所选 \(chunks.count) 个区块的所有现有 SubChunk"
        } else {
            targetText = region == nil ? "当前区块所有现有 SubChunk" : "框选区域覆盖的所有现有 SubChunk"
        }
        let alert = UIAlertController(
            title: "批量替换层 \(layer)？",
            message: "将覆盖\(targetText)中符合选择范围的目标层，\(airText)。程序不会自动备份。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "执行", style: .destructive) { [weak self] _ in
            self?.performBulkReplace(layer: layer, editor: editor)
        })
        present(alert, animated: true)
    }

    private func performBulkReplace(layer: Int, editor: BlockSearchReplaceNBTEditorView) {
        let replacement = editor.makeReplacement()
        let includeAir = includeAirSwitch.isOn
        let overlay = showBusy(chunks != nil ? "批量替换所选区块层 \(layer)…" : (region == nil ? "批量替换层 \(layer)…" : "批量替换框选区域层 \(layer)…"))
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let store = BedrockChunkStore(session: self.session)
                var affectedBlockCount = 0
                var modifiedSubChunkCount = 0
                var skippedSubChunkCount = 0
                var skippedChunks = 0
                if let chunks = self.chunks {
                    for chunk in chunks {
                        do {
                            let result = try store.bulkReplaceLayer(
                                in: chunk,
                                layer: layer,
                                replacement: replacement,
                                includeCompletelyAirCells: includeAir
                            )
                            affectedBlockCount += result.affectedBlockCount
                            modifiedSubChunkCount += result.modifiedSubChunkCount
                            skippedSubChunkCount += result.skippedSubChunkCount
                        } catch MCBEEditorError.unsupported {
                            skippedChunks += 1
                        }
                    }
                    guard modifiedSubChunkCount > 0 else {
                        throw MCBEEditorError.unsupported("所选区块中没有可批量替换的现代 SubChunk")
                    }
                } else {
                    let result: BedrockChunkBulkLayerResult
                    if let region = self.region {
                        result = try store.bulkReplaceLayer(
                            in: region,
                            layer: layer,
                            replacement: replacement,
                            includeCompletelyAirCells: includeAir
                        )
                    } else if let chunk = self.chunk {
                        result = try store.bulkReplaceLayer(
                            in: chunk,
                            layer: layer,
                            replacement: replacement,
                            includeCompletelyAirCells: includeAir
                        )
                    } else {
                        throw MCBEEditorError.malformedData("缺少批量替换范围")
                    }
                    affectedBlockCount = result.affectedBlockCount
                    modifiedSubChunkCount = result.modifiedSubChunkCount
                    skippedSubChunkCount = result.skippedSubChunkCount
                }
                let prefix = self.chunks != nil ? "已在所选区块替换" : (self.region == nil ? "已替换" : "已在框选区域替换")
                var message = "\(prefix)层 \(layer) 的 \(affectedBlockCount) 个方块位置，写回 \(modifiedSubChunkCount) 个 SubChunk；跳过 \(skippedSubChunkCount) 个旧版 SubChunk。"
                if skippedChunks > 0 { message += " \(skippedChunks) 个所选区块没有可处理内容。" }
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.onComplete?(message)
                    self.showCompletion(title: "批量替换完成", message: message)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "批量替换失败")
                }
            }
        }
    }

    private func showCompletion(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
