import UIKit

final class ChunkListViewController: UITableViewController, UISearchResultsUpdating {
    private let session: WorldSession
    private let initialDimension: Int32
    private let store: BedrockChunkStore
    private let workQueue = DispatchQueue(label: "com.wzn.blocktopograph.chunk-manager", qos: .userInitiated)
    private let dimensionControl = UISegmentedControl(items: ["全部"] + BedrockDimension.allCases.map(\.displayName))
    private var summaries = [BedrockChunkSummary]()
    private var filtered = [BedrockChunkSummary]()
    private var query = ""
    private var isBatchMode = false
    private var batchSelection = Set<ChunkPosition>()

    var onSelectChunk: ((ChunkPosition) -> Void)?
    var onSelectTickingArea: ((ChunkPosition) -> Void)?
    var onChunkMutation: ((String, ChunkPosition?) -> Void)?

    init(session: WorldSession, initialDimension: Int32) {
        self.session = session
        self.initialDimension = initialDimension
        self.store = BedrockChunkStore(session: session)
        super.init(style: .insetGrouped)
        title = "区块"
        tabBarItem = UITabBarItem(title: "区块", image: UIImage(systemName: "square.grid.3x3"), tag: 2)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Chunk")
        tableView.rowHeight = 62
        updateNavigationButtons()
        let search = UISearchController(searchResultsController: nil)
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "搜索 X、Z、维度或记录类型"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        dimensionControl.selectedSegmentIndex = BedrockDimension.allCases.firstIndex(where: { $0.rawValue == initialDimension }).map { $0 + 1 } ?? 0
        dimensionControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        let wrapper = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 52))
        dimensionControl.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(dimensionControl)
        NSLayoutConstraint.activate([
            dimensionControl.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            dimensionControl.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            dimensionControl.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])
        tableView.tableHeaderView = wrapper
        reloadChunks()
    }

    private func updateNavigationButtons() {
        if isBatchMode {
            let cancel = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelBatchMode))
            let visible = Set(filtered.map(\.position))
            let allVisibleSelected = !visible.isEmpty && visible.isSubset(of: batchSelection)
            let selectAll = UIBarButtonItem(
                title: allVisibleSelected ? "取消全选" : "全选",
                style: .plain,
                target: self,
                action: #selector(toggleBatchSelectAll)
            )
            let process = UIBarButtonItem(title: "处理", style: .done, target: self, action: #selector(showBatchActions))
            process.isEnabled = !batchSelection.isEmpty
            navigationItem.rightBarButtonItems = [process, selectAll, cancel]
            navigationItem.prompt = "批量处理：已选择 \(batchSelection.count) 个区块"
        } else {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reloadChunks)),
                UIBarButtonItem(title: "批量", style: .plain, target: self, action: #selector(beginBatchMode)),
                UIBarButtonItem(title: "常加载", style: .plain, target: self, action: #selector(showTickingAreas))
            ]
            navigationItem.prompt = nil
        }
    }

    @objc private func showTickingAreas() {
        let selectedDimension: Int32 = dimensionControl.selectedSegmentIndex == 0
            ? initialDimension
            : BedrockDimension.allCases[dimensionControl.selectedSegmentIndex - 1].rawValue
        let controller = TickingAreaListViewController(session: session, initialDimension: selectedDimension)
        controller.onSelectChunk = { [weak self] position in
            if let callback = self?.onSelectTickingArea { callback(position) }
            else { self?.onSelectChunk?(position) }
        }
        controller.onMutation = { [weak self] message in
            self?.onChunkMutation?(message, nil)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func beginBatchMode() {
        isBatchMode = true
        batchSelection.removeAll()
        tableView.allowsMultipleSelection = false
        updateNavigationButtons()
        tableView.reloadData()
    }

    @objc private func toggleBatchSelectAll() {
        let visible = Set(filtered.map(\.position))
        if !visible.isEmpty, visible.isSubset(of: batchSelection) {
            batchSelection.subtract(visible)
        } else {
            batchSelection.formUnion(visible)
        }
        tableView.reloadData()
        updateNavigationButtons()
    }

    @objc private func cancelBatchMode() {
        finishBatchMode()
    }

    private func finishBatchMode() {
        isBatchMode = false
        batchSelection.removeAll()
        tableView.allowsMultipleSelection = false
        for indexPath in tableView.indexPathsForSelectedRows ?? [] {
            tableView.deselectRow(at: indexPath, animated: false)
        }
        updateNavigationButtons()
        tableView.reloadData()
    }

    private var selectedBatchChunks: [ChunkPosition] {
        batchSelection.sorted { lhs, rhs in
            if lhs.dimension != rhs.dimension { return lhs.dimension < rhs.dimension }
            if lhs.z != rhs.z { return lhs.z < rhs.z }
            return lhs.x < rhs.x
        }
    }

    @objc private func reloadChunks() {
        let overlay = showBusy("扫描世界中所有区块键…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let values = try self.store.listChunks()
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.summaries = values
                    let available = Set(values.map(\.position))
                    self.batchSelection.formIntersection(available)
                    self.applyFilter()
                    self.title = "区块列表（\(values.count)）"
                    self.updateNavigationButtons()
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "无法读取区块列表")
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
        let selectedDimension: Int32? = dimensionControl.selectedSegmentIndex == 0
            ? nil
            : BedrockDimension.allCases[dimensionControl.selectedSegmentIndex - 1].rawValue
        filtered = summaries.filter { summary in
            if let selectedDimension = selectedDimension, summary.position.dimension != selectedDimension { return false }
            guard !query.isEmpty else { return true }
            let dimension = BedrockDimension(rawValue: summary.position.dimension)?.displayName ?? "维度 \(summary.position.dimension)"
            let text = "\(summary.position.x) \(summary.position.z) \(dimension) \(summary.detailText)"
            return text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        tableView.reloadData()
        updateNavigationButtons()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Chunk", for: indexPath)
        let summary = filtered[indexPath.row]
        let dimension = BedrockDimension(rawValue: summary.position.dimension)?.displayName ?? "维度 \(summary.position.dimension)"
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.text = "\(dimension)  \(summary.coordinateText)\n\(summary.detailText)"
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.accessoryType = isBatchMode
            ? (batchSelection.contains(summary.position) ? .checkmark : .none)
            : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let summary = filtered[indexPath.row]
        if isBatchMode {
            tableView.deselectRow(at: indexPath, animated: true)
            if batchSelection.contains(summary.position) {
                batchSelection.remove(summary.position)
            } else {
                batchSelection.insert(summary.position)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
            updateNavigationButtons()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        showActions(for: summary, sourceView: tableView.cellForRow(at: indexPath))
    }

    override func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isBatchMode else { return nil }
        let summary = filtered[indexPath.row]
        let select = UIContextualAction(style: .normal, title: "选择") { [weak self] _, _, done in
            self?.selectOnMap(summary.position)
            done(true)
        }
        select.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [select])
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isBatchMode else { return nil }
        let summary = filtered[indexPath.row]
        let clear = UIContextualAction(style: .destructive, title: "清空") { [weak self] _, source, done in
            guard let self = self else { done(false); return }
            ChunkActionMenu.confirmClear(
                from: self,
                session: self.session,
                summary: summary,
                sourceView: source,
                onMutation: { [weak self] message, position in
                    self?.onChunkMutation?(message, position)
                    self?.reloadChunks()
                }
            )
            done(true)
        }
        let manage = UIContextualAction(style: .normal, title: "管理") { [weak self] _, source, done in
            self?.showActions(for: summary, sourceView: source)
            done(true)
        }
        manage.backgroundColor = .systemIndigo
        return UISwipeActionsConfiguration(actions: [clear, manage])
    }

    @objc private func showBatchActions() {
        let chunks = selectedBatchChunks
        guard !chunks.isEmpty else { return }
        let alert = UIAlertController(
            title: "批量处理 \(chunks.count) 个区块",
            message: "所有操作只作用于当前勾选的区块；可跨维度选择。修改世界前请确保 Minecraft 已完全退出。",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "方块搜索替换…", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let controller = ChunkSearchReplaceViewController(session: self.session, chunks: chunks)
            controller.onComplete = { [weak self] message in self?.completeBatchMutation(message) }
            self.navigationController?.pushViewController(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "批量层0层1替换…", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let controller = BulkLayerReplaceViewController(session: self.session, chunks: chunks)
            controller.onComplete = { [weak self] message in self?.completeBatchMutation(message) }
            self.navigationController?.pushViewController(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "统一修改生物群系…", style: .default) { [weak self] _ in
            self?.chooseBatchBiome(for: chunks)
        })
        alert.addAction(UIAlertAction(title: "常加载区域编辑…", style: .default) { [weak self] _ in
            self?.prepareTickingArea(from: chunks)
        })
        alert.addAction(UIAlertAction(title: "删除 HardcodedSpawners…", style: .destructive) { [weak self] _ in
            self?.confirmBatchMutation(.deleteHardcodedSpawners, chunks: chunks)
        })
        alert.addAction(UIAlertAction(title: "清空所选区块…", style: .destructive) { [weak self] _ in
            self?.confirmBatchMutation(.clear, chunks: chunks)
        })
        alert.addAction(UIAlertAction(title: "重新生成所选区块…", style: .destructive) { [weak self] _ in
            self?.confirmBatchMutation(.regenerate, chunks: chunks)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(alert, animated: true)
    }

    private func prepareTickingArea(from chunks: [ChunkPosition]) {
        guard let context = TickingAreaSelectionContext(chunks: chunks) else {
            showError(BlocktopographError.unsupported("一次只能编辑同一维度区块对应的常加载区域"), title: "维度不一致")
            return
        }
        finishBatchMode()
        let controller = TickingAreaListViewController(
            session: session,
            initialDimension: context.dimension,
            selectionContext: context
        )
        controller.onSelectChunk = { [weak self] position in
            if let callback = self?.onSelectTickingArea { callback(position) }
            else { self?.onSelectChunk?(position) }
        }
        controller.onMutation = { [weak self] message in
            self?.onChunkMutation?(message, context.suggestedArea.centerChunk)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private enum BatchMutationKind {
        case deleteHardcodedSpawners
        case clear
        case regenerate

        var title: String {
            switch self {
            case .deleteHardcodedSpawners: return "删除 HardcodedSpawners"
            case .clear: return "清空区块"
            case .regenerate: return "重新生成区块"
            }
        }
    }

    private func chooseBatchBiome(for chunks: [ChunkPosition]) {
        let picker = BiomeIDPickerViewController(currentID: nil, selectionEnabled: true)
        picker.onSelect = { [weak self] id in
            self?.confirmBatchBiome(id: id, chunks: chunks)
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func confirmBatchBiome(id: UInt32, chunks: [ChunkPosition]) {
        let name = BedrockBiomeCatalog.displayName(for: id)
        let alert = UIAlertController(
            title: "统一设置生物群系？",
            message: "将所选 \(chunks.count) 个区块的全部可编辑生物群系位置设为 ID \(id)（\(name)）。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "执行", style: .destructive) { [weak self] _ in
            self?.performBatchBiome(id: id, chunks: chunks)
        })
        present(alert, animated: true)
    }

    private func performBatchBiome(id: UInt32, chunks: [ChunkPosition]) {
        let overlay = showBusy("批量修改生物群系…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                var changed = 0
                var skipped = 0
                var cells = 0
                for chunk in chunks {
                    let originX = MapCoordinate.blockOrigin(ofChunk: chunk.x)
                    let originZ = MapCoordinate.blockOrigin(ofChunk: chunk.z)
                    let region = BedrockMapRegion(
                        minimumX: originX, minimumZ: originZ,
                        maximumX: originX + 15, maximumZ: originZ + 15,
                        dimension: chunk.dimension
                    )
                    do {
                        let result = try self.store.setBiomeID(id, in: region)
                        changed += result.changedChunkCount
                        skipped += result.skippedChunkCount
                        cells += result.detailCount
                    } catch BlocktopographError.unsupported {
                        skipped += 1
                    }
                }
                guard changed > 0 else {
                    throw BlocktopographError.unsupported("所选区块中没有可修改的生物群系记录")
                }
                let message = "已修改 \(changed) 个区块、\(cells) 个生物群系位置；跳过 \(skipped) 个区块。"
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.completeBatchMutation(message)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "批量修改生物群系失败")
                }
            }
        }
    }

    private func confirmBatchMutation(_ kind: BatchMutationKind, chunks: [ChunkPosition]) {
        let detail: String
        switch kind {
        case .deleteHardcodedSpawners:
            detail = "删除所选区块中的 0x39 HardcodedSpawners 记录。"
        case .clear:
            detail = "删除区块数据与关联实体，并写入纯空气区块。"
        case .regenerate:
            detail = "删除区块数据与关联实体，使 Minecraft 按种子重新生成。"
        }
        let alert = UIAlertController(
            title: "\(kind.title)？",
            message: "共 \(chunks.count) 个区块。\(detail)此操作不会自动备份。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "执行", style: .destructive) { [weak self] _ in
            self?.performBatchMutation(kind, chunks: chunks)
        })
        present(alert, animated: true)
    }

    private func performBatchMutation(_ kind: BatchMutationKind, chunks: [ChunkPosition]) {
        let overlay = showBusy("\(kind.title)…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                var changed = 0
                var skipped = 0
                for chunk in chunks {
                    do {
                        switch kind {
                        case .deleteHardcodedSpawners:
                            var record = try self.store.hardcodedSpawnersRecord(at: chunk)
                            guard record.existed else { skipped += 1; continue }
                            record.document.areas.removeAll()
                            try self.store.saveHardcodedSpawnersRecord(record)
                        case .clear:
                            _ = try self.store.clearChunk(chunk)
                        case .regenerate:
                            _ = try self.store.regenerateChunk(chunk)
                        }
                        changed += 1
                    } catch BlocktopographError.unsupported {
                        skipped += 1
                    }
                }
                guard changed > 0 else {
                    throw BlocktopographError.unsupported("所选区块中没有可执行该操作的记录")
                }
                let message = "已\(kind.title) \(changed) 个区块；跳过 \(skipped) 个区块。"
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.completeBatchMutation(message)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "\(kind.title)失败")
                }
            }
        }
    }

    private func completeBatchMutation(_ message: String) {
        onChunkMutation?(message, nil)
        finishBatchMode()
        reloadChunks()
        navigationItem.prompt = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.navigationItem.prompt == message { self?.navigationItem.prompt = nil }
        }
    }

    private func showActions(for summary: BedrockChunkSummary, sourceView: UIView?) {
        ChunkActionMenu.present(
            from: self,
            session: session,
            summary: summary,
            sourceView: sourceView,
            sourceRect: sourceView?.bounds,
            onSelect: { [weak self] position in self?.selectOnMap(position) },
            onMutation: { [weak self] message, position in
                self?.onChunkMutation?(message, position)
                self?.reloadChunks()
            }
        )
    }

    private func selectOnMap(_ position: ChunkPosition) {
        onSelectChunk?(position)
        navigationController?.popViewController(animated: true)
    }


}


enum ChunkActionMenu {
    private static let queue = DispatchQueue(label: "com.wzn.blocktopograph.chunk-actions", qos: .userInitiated)

    static func present(
        from presenter: UIViewController,
        session: WorldSession,
        summary: BedrockChunkSummary,
        sourceView: UIView?,
        sourceRect: CGRect?,
        onSelect: ((ChunkPosition) -> Void)?,
        onMutation: @escaping (String, ChunkPosition?) -> Void
    ) {
        let dimension = BedrockDimension(rawValue: summary.position.dimension)?.displayName ?? "维度 \(summary.position.dimension)"
        let detail = summary.recordCount == 0 ? "未找到已生成的区块记录" : summary.detailText
        let alert = UIAlertController(
            title: "\(dimension) \(summary.coordinateText)",
            message: detail,
            preferredStyle: .actionSheet
        )
        if let onSelect = onSelect {
            alert.addAction(UIAlertAction(title: "在地图中选择并闪烁", style: .default) { _ in
                onSelect(summary.position)
            })
        }
        alert.addAction(UIAlertAction(title: "复制区块内容…", style: .default) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            let controller = ChunkCopyViewController(session: session, source: summary.position)
            controller.onComplete = { message, destination in onMutation(message, destination) }
            presenter.navigationController?.pushViewController(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "方块搜索替换…", style: .default) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            let controller = ChunkSearchReplaceViewController(session: session, chunk: summary.position)
            controller.onComplete = { message in onMutation(message, summary.position) }
            presenter.navigationController?.pushViewController(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "生物群系…", style: .default) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            let controller = ChunkBiomeEditorViewController(session: session, chunk: summary.position)
            controller.onSave = { message in onMutation(message, summary.position) }
            presenter.navigationController?.pushViewController(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "常加载区域编辑…", style: .default) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            let context = TickingAreaSelectionContext(chunk: summary.position)
            let controller = TickingAreaListViewController(
                session: session,
                initialDimension: summary.position.dimension,
                selectionContext: context
            )
            controller.onSelectChunk = { position in onSelect?(position) }
            controller.onMutation = { message in onMutation(message, summary.position) }
            presenter.navigationController?.pushViewController(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "HardcodedSpawners…", style: .default) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            let controller = HardcodedSpawnersViewController(session: session, chunk: summary.position)
            controller.onSave = { message in onMutation(message, summary.position) }
            presenter.navigationController?.pushViewController(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "清空区块…", style: .destructive) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            confirmClear(
                from: presenter,
                session: session,
                summary: summary,
                sourceView: sourceView,
                onMutation: onMutation
            )
        })
        alert.addAction(UIAlertAction(title: "重新生成区块…", style: .destructive) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            confirmRegenerate(
                from: presenter,
                session: session,
                summary: summary,
                sourceView: sourceView,
                onMutation: onMutation
            )
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            let anchor = sourceView ?? presenter.view!
            popover.sourceView = anchor
            popover.sourceRect = sourceRect ?? anchor.bounds
        }
        presenter.present(alert, animated: true)
    }

    static func confirmClear(
        from presenter: UIViewController,
        session: WorldSession,
        summary: BedrockChunkSummary,
        sourceView: UIView? = nil,
        onMutation: @escaping (String, ChunkPosition?) -> Void
    ) {
        let message = "将先按“重新生成区块”相同规则完整删除该坐标全部原始记录与关联 Actor，再写入一个最小的已生成纯空气区块：仅保留兼容版本记录和 FinalizedState=2，不写入任何 SubChunk、方块实体、实体、刻或生物群系记录。Minecraft 会把该坐标视为已经生成的空气区块，而不是重新按种子生成。此操作不会自动备份。"
        let alert = UIAlertController(title: "清空区块 \(summary.coordinateText)？", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            let overlay = presenter.showBusy("清空区块…")
            queue.async {
                do {
                    let result = try BedrockChunkStore(session: session).clearChunk(summary.position)
                    let digest = result.deletedDigestCount > 0 ? "、\(result.deletedDigestCount) 条 digp" : ""
                    let actors = result.deletedActorCount > 0 ? "、\(result.deletedActorCount) 个 Actor" : ""
                    let resultMessage = "已删除 \(result.deletedChunkRecordCount) 条旧区块记录\(digest)\(actors)，并创建 \(result.createdMetadataRecordCount) 条纯空气区块元数据（\(result.versionRecordType.displayName) + FinalizedState）。"
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        onMutation(resultMessage, summary.position)
                    }
                } catch {
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        presenter.showError(error, title: "清空区块失败")
                    }
                }
            }
        })
        presenter.present(alert, animated: true)
    }

    static func confirmRegenerate(
        from presenter: UIViewController,
        session: WorldSession,
        summary: BedrockChunkSummary,
        sourceView: UIView? = nil,
        onMutation: @escaping (String, ChunkPosition?) -> Void
    ) {
        let message = "将按安卓版 Blocktopograph 的原始区块前缀规则，删除该坐标全部已知和未知区块记录，包括 ConversionData、GenerationSeed、混合数据、LegacyVersion、digp 索引及其 Actor。Minecraft 下一次加载该位置时会把它视为从未生成，并依据当前种子和游戏版本重新生成。请确保 Minecraft 已完全退出；此操作不会自动备份。"
        let alert = UIAlertController(title: "重新生成区块 \(summary.coordinateText)？", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重新生成", style: .destructive) { [weak presenter] _ in
            guard let presenter = presenter else { return }
            let overlay = presenter.showBusy("将区块设为未生成…")
            queue.async {
                do {
                    let result = try BedrockChunkStore(session: session).regenerateChunk(summary.position)
                    let digest = result.deletedDigestCount > 0 ? "、\(result.deletedDigestCount) 条 digp" : ""
                    let actors = result.deletedActorCount > 0 ? "、\(result.deletedActorCount) 个 Actor" : ""
                    let resultMessage = "已完整移除 \(result.deletedChunkRecordCount) 条原始区块记录\(digest)\(actors)。Minecraft 下次加载时会依据种子重新生成。"
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        onMutation(resultMessage, summary.position)
                    }
                } catch {
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        presenter.showError(error, title: "重新生成区块失败")
                    }
                }
            }
        })
        presenter.present(alert, animated: true)
    }
}

private final class ChunkCopyViewController: UIViewController, UITextFieldDelegate {
    private let session: WorldSession
    private let source: ChunkPosition
    private let xField = UITextField()
    private let zField = UITextField()
    private let dimensionControl = UISegmentedControl(items: BedrockDimension.allCases.map(\.displayName))
    private let queue = DispatchQueue(label: "com.wzn.blocktopograph.chunk-copy", qos: .userInitiated)
    var onComplete: ((String, ChunkPosition) -> Void)?

    init(session: WorldSession, source: ChunkPosition) {
        self.session = session
        self.source = source
        super.init(nibName: nil, bundle: nil)
        title = "复制区块"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "复制", style: .done, target: self, action: #selector(copyChunk))
        for field in [xField, zField] {
            field.borderStyle = .roundedRect
            field.keyboardType = .numbersAndPunctuation
            field.delegate = self
        }
        xField.placeholder = "目标区块 X"
        zField.placeholder = "目标区块 Z"
        xField.text = String(source.x)
        zField.text = String(source.z)
        dimensionControl.selectedSegmentIndex = BedrockDimension.allCases.firstIndex(where: { $0.rawValue == source.dimension }) ?? 0

        let sourceLabel = UILabel()
        sourceLabel.numberOfLines = 0
        sourceLabel.text = "源区块：\(BedrockDimension(rawValue: source.dimension)?.displayName ?? "维度 \(source.dimension)") (\(source.x), \(source.z))"
        sourceLabel.font = .preferredFont(forTextStyle: .headline)
        let warning = UILabel()
        warning.numberOfLines = 0
        warning.textColor = .secondaryLabel
        warning.text = "复制地形、SubChunk、生物群系、方块实体和区块状态。为避免 UniqueID 冲突，不复制实体、pending ticks、random ticks 和硬编码刷怪记录。目标区块原有可复制记录会直接替换。"
        let stack = UIStackView(arrangedSubviews: [sourceLabel, labelled("目标维度", dimensionControl), labelled("目标 X", xField), labelled("目标 Z", zField), warning])
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

    private func labelled(_ title: String, _ view: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [label, view])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    @objc private func copyChunk() {
        guard let x = Int32(xField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              let z = Int32(zField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else {
            showError(BlocktopographError.malformedData("请输入有效的目标区块 X、Z"))
            return
        }
        let destination = ChunkPosition(
            x: x,
            z: z,
            dimension: BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
        )
        let alert = UIAlertController(title: "覆盖目标区块？", message: "目标区块可复制记录将被直接替换。此操作不会自动备份。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "复制", style: .destructive) { [weak self] _ in self?.performCopy(to: destination) })
        present(alert, animated: true)
    }

    private func performCopy(to destination: ChunkPosition) {
        let overlay = showBusy("复制区块…")
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try BedrockChunkStore(session: self.session).copyChunk(from: self.source, to: destination)
                var message = "已复制 \(result.copiedRecordCount) 条记录，替换目标 \(result.removedDestinationRecordCount) 条记录。"
                if !result.skippedRecordTypes.isEmpty {
                    message += " 未复制：\(result.skippedRecordTypes.map(\.displayName).joined(separator: "、"))。"
                }
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.onComplete?(message, destination)
                    let alert = UIAlertController(title: "复制完成", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: "复制区块失败")
                }
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

final class ChunkSearchReplaceViewController: UIViewController {
    private let session: WorldSession
    private let chunk: ChunkPosition?
    private let region: BedrockMapRegion?
    private let chunks: [ChunkPosition]?
    private let searchLayer0 = BlockSearchReplaceNBTEditorView(layerIndex: 0, mode: .search)
    private let searchLayer1 = BlockSearchReplaceNBTEditorView(layerIndex: 1, mode: .search)
    private let replacementLayer0 = BlockSearchReplaceNBTEditorView(layerIndex: 0, mode: .replacement)
    private let replacementLayer1 = BlockSearchReplaceNBTEditorView(layerIndex: 1, mode: .replacement)
    private let searchScopeControl = UISegmentedControl(items: ["层 0", "层 1", "层 0 和层 1"])
    private let changeLayer1Switch = UISwitch()
    private let searchHelp = UILabel()
    private let replacementHelp = UILabel()
    private let queue = DispatchQueue(label: "com.wzn.blocktopograph.chunk-search-replace", qos: .userInitiated)
    private var lastSearchContentMask = -1
    var onComplete: ((String) -> Void)?

    init(session: WorldSession, chunk: ChunkPosition) {
        self.session = session
        self.chunk = chunk
        self.region = nil
        self.chunks = nil
        super.init(nibName: nil, bundle: nil)
        title = "区块方块搜索替换"
    }

    init(session: WorldSession, region: BedrockMapRegion) {
        self.session = session
        self.chunk = nil
        self.region = region
        self.chunks = nil
        super.init(nibName: nil, bundle: nil)
        title = "区域方块搜索替换"
    }

    init(session: WorldSession, chunks: [ChunkPosition]) {
        self.session = session
        self.chunk = nil
        self.region = nil
        self.chunks = chunks
        super.init(nibName: nil, bundle: nil)
        title = "批量区块方块搜索替换"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "执行替换", style: .done, target: self, action: #selector(confirmReplace)),
            UIBarButtonItem(title: "仅搜索", style: .plain, target: self, action: #selector(searchOnly))
        ]

        searchScopeControl.selectedSegmentIndex = 2
        searchScopeControl.addTarget(self, action: #selector(searchScopeChanged), for: .valueChanged)
        searchLayer0.onContentChanged = { [weak self] in self?.updateSearchScopeAvailability() }
        searchLayer1.onContentChanged = { [weak self] in self?.updateSearchScopeAvailability() }

        changeLayer1Switch.isOn = false
        changeLayer1Switch.addTarget(self, action: #selector(changeLayer1Changed), for: .valueChanged)
        replacementLayer1.setEditorEnabled(false)

        let dimensionValue = chunk?.dimension ?? region?.dimension ?? chunks?.first?.dimension ?? 0
        let dimension = BedrockDimension(rawValue: dimensionValue)?.displayName ?? "维度 \(dimensionValue)"
        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        if let chunk = chunk {
            titleLabel.text = "\(dimension) 区块 (\(chunk.x), \(chunk.z))"
        } else if let region = region {
            titleLabel.text = "\(dimension) \(region.coordinateText)"
        } else if let chunks = chunks {
            let dimensions = Set(chunks.map(\.dimension))
            titleLabel.text = dimensions.count == 1
                ? "\(dimension) · 已选择 \(chunks.count) 个区块"
                : "已选择 \(chunks.count) 个区块 · \(dimensions.count) 个维度"
        }
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let scopeCaption = UILabel()
        scopeCaption.text = "查找范围"
        scopeCaption.font = .preferredFont(forTextStyle: .caption1)
        scopeCaption.textColor = .secondaryLabel
        scopeCaption.textAlignment = .right
        let scopeStack = UIStackView(arrangedSubviews: [scopeCaption, searchScopeControl])
        scopeStack.axis = .vertical
        scopeStack.spacing = 3
        scopeStack.alignment = .fill
        scopeStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 330).isActive = true

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), scopeStack])
        header.axis = .horizontal
        header.spacing = 12
        header.alignment = .center

        searchHelp.numberOfLines = 0
        searchHelp.textColor = .secondaryLabel
        searchHelp.font = .preferredFont(forTextStyle: .footnote)

        replacementHelp.numberOfLines = 0
        replacementHelp.textColor = .secondaryLabel
        replacementHelp.font = .preferredFont(forTextStyle: .footnote)

        let replacementSwitchLabel = UILabel()
        replacementSwitchLabel.text = "是否改变层 1"
        replacementSwitchLabel.font = .preferredFont(forTextStyle: .subheadline)
        let replacementSwitchStack = UIStackView(arrangedSubviews: [replacementSwitchLabel, changeLayer1Switch])
        replacementSwitchStack.axis = .horizontal
        replacementSwitchStack.spacing = 7
        replacementSwitchStack.alignment = .center
        replacementSwitchStack.setContentHuggingPriority(.required, for: .horizontal)

        let replacementHeader = UIStackView(arrangedSubviews: [sectionTitle("替换方块 NBT"), UIView(), replacementSwitchStack])
        replacementHeader.axis = .horizontal
        replacementHeader.spacing = 10
        replacementHeader.alignment = .center

        let searchColumns = makeColumns(searchLayer0, searchLayer1)
        let replacementColumns = makeColumns(replacementLayer0, replacementLayer1)
        let bulkButton = UIButton(type: .system)
        bulkButton.setTitle(chunks != nil ? "所选区块批量层0层1替换" : (region == nil ? "批量层0层1替换" : "框选区域批量层0层1替换"), for: .normal)
        bulkButton.setTitleColor(.white, for: .normal)
        bulkButton.backgroundColor = .systemIndigo
        bulkButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        bulkButton.layer.cornerRadius = 10
        bulkButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        bulkButton.addTarget(self, action: #selector(openBulkLayerReplace), for: .touchUpInside)
        bulkButton.isHidden = false
        let bulkHelp = UILabel()
        bulkHelp.numberOfLines = 0
        bulkHelp.font = .preferredFont(forTextStyle: .footnote)
        bulkHelp.textColor = .secondaryLabel
        if let chunks = chunks {
            bulkHelp.text = "对已选择的 \(chunks.count) 个区块分别覆盖现有 SubChunk 的层 0 或层 1。"
        } else {
            bulkHelp.text = region == nil
                ? "覆盖当前区块所有现有 SubChunk 的层 0 或层 1。"
                : "仅覆盖框选 X-Z 范围在现有 SubChunk 中的层 0 或层 1，框外方块保持不变。"
        }
        bulkHelp.isHidden = false
        let content = UIStackView(arrangedSubviews: [
            header,
            sectionTitle("搜索方块 NBT"),
            searchHelp,
            searchColumns,
            replacementHeader,
            replacementHelp,
            replacementColumns,
            sectionTitle("批量层0层1替换"),
            bulkHelp,
            bulkButton
        ])
        content.axis = .vertical
        content.spacing = 12
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
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        updateSearchScopeAvailability()
        updateReplacementHelp()
    }

    private func makeColumns(_ left: UIView, _ right: UIView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [left, right])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.heightAnchor.constraint(equalToConstant: 300).isActive = true
        return stack
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .title3)
        label.textColor = .label
        return label
    }

    @objc private func searchScopeChanged() {
        updateSearchHelp()
    }

    private func updateSearchScopeAvailability() {
        let has0 = searchLayer0.hasContent
        let has1 = searchLayer1.hasContent
        let mask = (has0 ? 1 : 0) | (has1 ? 2 : 0)
        if mask != lastSearchContentMask {
            switch mask {
            case 1: searchScopeControl.selectedSegmentIndex = 0
            case 2: searchScopeControl.selectedSegmentIndex = 1
            case 3: searchScopeControl.selectedSegmentIndex = 2
            default: searchScopeControl.selectedSegmentIndex = 2
            }
            lastSearchContentMask = mask
        }
        let hasBothCriteria = has0 && has1
        searchScopeControl.isEnabled = !hasBothCriteria
        if hasBothCriteria { searchScopeControl.selectedSegmentIndex = 2 }
        updateSearchHelp()
    }

    private func updateSearchHelp() {
        let has0 = searchLayer0.hasContent
        let has1 = searchLayer1.hasContent
        if has0 && has1 {
            searchHelp.text = "层 0 与层 1 都填写时，查找范围固定为“层 0 和层 1”：同一坐标必须同时满足两列条件。name、states 标签名和值均支持部分匹配。"
        } else if has0 || has1 {
            let source = has0 ? "层 0" : "层 1"
            let target = ["层 0", "层 1", "层 0 和层 1"][max(0, searchScopeControl.selectedSegmentIndex)]
            searchHelp.text = "当前使用\(source)列作为搜索条件，并在\(target)中查找；选择两层时，任意一层匹配即可选中该坐标。"
        } else {
            searchHelp.text = "先在层 0 或层 1 填写搜索条件。只填写一列时可在右上角选择查找层；两列都填写时自动锁定为联合查找。"
        }
    }

    @objc private func changeLayer1Changed() {
        replacementLayer1.setEditorEnabled(changeLayer1Switch.isOn)
        updateReplacementHelp()
    }

    private func updateReplacementHelp() {
        if changeLayer1Switch.isOn {
            replacementHelp.text = "匹配坐标始终应用层 0 替换，并同时改变层 1。层 1 留空会删除该坐标原有层 1（写为空气）；填写后先清空原 states，再写入新 states。"
        } else {
            replacementHelp.text = "匹配坐标只应用层 0 替换。层 1 编辑器已禁用，原层 1 保持不变；原来没有层 1 也不会创建。所有启用的替换均默认清空原 states 后写入。"
        }
    }

    @objc private func openBulkLayerReplace() {
        let controller: BulkLayerReplaceViewController
        if let chunks = chunks {
            controller = BulkLayerReplaceViewController(session: session, chunks: chunks)
        } else if let region = region {
            controller = BulkLayerReplaceViewController(session: session, region: region)
        } else if let chunk = chunk {
            controller = BulkLayerReplaceViewController(session: session, chunk: chunk)
        } else {
            return
        }
        controller.onComplete = { [weak self] message in self?.onComplete?(message) }
        navigationController?.pushViewController(controller, animated: true)
    }


    @objc private func searchOnly() {
        do {
            let plan = try makePlan()
            let overlay = showBusy("扫描方块位置…")
            queue.async { [weak self] in
                guard let self = self else { return }
                do {
                    let store = BedrockChunkStore(session: self.session)
                    let result: BedrockBlockSearchScanResult
                    if let chunks = self.chunks {
                        result = try store.searchBlocks(in: chunks, coordinatedOperation: plan)
                    } else if let region = self.region {
                        result = try store.searchBlocks(in: region, coordinatedOperation: plan)
                    } else if let chunk = self.chunk {
                        result = try store.searchBlocks(in: chunk, coordinatedOperation: plan)
                    } else {
                        throw BlocktopographError.malformedData("缺少搜索范围")
                    }
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        guard !result.hits.isEmpty else {
                            let alert = UIAlertController(title: "未找到方块", message: "当前范围内没有符合搜索条件的方块。", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "确定", style: .default))
                            self.present(alert, animated: true)
                            return
                        }
                        self.navigationController?.pushViewController(
                            BlockSearchResultsViewController(session: self.session, result: result),
                            animated: true
                        )
                    }
                } catch {
                    DispatchQueue.main.async {
                        overlay.removeFromSuperview()
                        self.showError(error, title: "方块搜索失败")
                    }
                }
            }
        } catch {
            showError(error, title: "搜索参数无效")
        }
    }

    @objc private func confirmReplace() {
        do {
            let plan = try makePlan()
            let alert = UIAlertController(
                title: chunks != nil ? "执行所选区块搜索替换？" : (region == nil ? "执行区块搜索替换？" : "执行区域搜索替换？"),
                message: plan.confirmationText + " 此操作不会自动备份，建议先退出 Minecraft。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "执行", style: .destructive) { [weak self] _ in
                self?.performReplace(plan: plan)
            })
            present(alert, animated: true)
        } catch {
            showError(error, title: "搜索替换参数无效")
        }
    }

    private func makePlan() throws -> BedrockCoordinatedBlockOperation {
        let criteria0 = searchLayer0.makeSearchCriteria()
        let criteria1 = searchLayer1.makeSearchCriteria()
        guard criteria0 != nil || criteria1 != nil else {
            throw BlocktopographError.malformedData("至少填写层 0 或层 1 的搜索 name / states")
        }

        let scope: BedrockBlockSearchScope
        if criteria0 != nil && criteria1 != nil {
            scope = .both
        } else {
            switch searchScopeControl.selectedSegmentIndex {
            case 0: scope = .layer0
            case 1: scope = .layer1
            default: scope = .both
            }
        }

        return BedrockCoordinatedBlockOperation(
            searchLayer0: criteria0,
            searchLayer1: criteria1,
            searchScope: scope,
            layer0Replacement: replacementLayer0.makeReplacement(),
            changeLayer1: changeLayer1Switch.isOn,
            layer1Replacement: changeLayer1Switch.isOn && replacementLayer1.hasContent
                ? replacementLayer1.makeReplacement()
                : nil
        )
    }

    private func performReplace(plan: BedrockCoordinatedBlockOperation) {
        let overlay = showBusy("扫描 SubChunk，并按坐标联合搜索与替换…")
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let store = BedrockChunkStore(session: self.session)
                var matchedBlockCount = 0
                var modifiedSubChunkCount = 0
                var skippedSubChunkCount = 0
                var skippedChunks = 0
                if let chunks = self.chunks {
                    for chunk in chunks {
                        do {
                            let result = try store.replaceBlocks(in: chunk, coordinatedOperation: plan)
                            matchedBlockCount += result.matchedBlockCount
                            modifiedSubChunkCount += result.modifiedSubChunkCount
                            skippedSubChunkCount += result.skippedSubChunkCount
                        } catch BlocktopographError.unsupported {
                            skippedChunks += 1
                        }
                    }
                    guard matchedBlockCount > 0 else {
                        throw BlocktopographError.unsupported("所选区块中没有匹配搜索条件的方块")
                    }
                } else {
                    let result: BedrockChunkReplaceResult
                    if let region = self.region {
                        result = try store.replaceBlocks(in: region, coordinatedOperation: plan)
                    } else if let chunk = self.chunk {
                        result = try store.replaceBlocks(in: chunk, coordinatedOperation: plan)
                    } else {
                        throw BlocktopographError.malformedData("缺少搜索替换范围")
                    }
                    matchedBlockCount = result.matchedBlockCount
                    modifiedSubChunkCount = result.modifiedSubChunkCount
                    skippedSubChunkCount = result.skippedSubChunkCount
                }
                var message = "已替换 \(matchedBlockCount) 个坐标，写回 \(modifiedSubChunkCount) 个 SubChunk。"
                if skippedSubChunkCount > 0 { message += " 跳过 \(skippedSubChunkCount) 个旧版 SubChunk。" }
                if skippedChunks > 0 { message += " \(skippedChunks) 个所选区块没有匹配内容。" }
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.onComplete?(message)
                    let alert = UIAlertController(title: "搜索替换完成", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    overlay.removeFromSuperview()
                    self.showError(error, title: self.chunks != nil ? "批量区块搜索替换失败" : (self.region == nil ? "区块搜索替换失败" : "区域搜索替换失败"))
                }
            }
        }
    }
}
