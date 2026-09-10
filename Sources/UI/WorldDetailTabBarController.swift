import UIKit

final class WorldDetailTabBarController: UITabBarController, UITabBarControllerDelegate {
    private let session: WorldSession
    private weak var mapController: WorldMapViewController?
    private weak var commandController: WorldCommandViewController?
    private var didCheckSharedCommandFile = false
    private let commandTabIndex = 4
    private var sharedCommandBatchRunning = false

    init(world: ImportedWorld) {
        self.session = WorldSession(world: world)
        super.init(nibName: nil, bundle: nil)
        title = world.name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let mapController = WorldMapViewController(session: session)
        self.mapController = mapController
        let map = UINavigationController(rootViewController: mapController)

        let entitiesController = EntityBrowserViewController(session: session) { [weak self, weak mapController] object in
            self?.selectedIndex = 0
            mapController?.locate(worldObject: object)
        }
        let entities = UINavigationController(rootViewController: entitiesController)
        entities.tabBarItem = UITabBarItem(title: "实体", image: UIImage(systemName: "person.3"), tag: 1)

        let chunksController = ChunkListViewController(session: session, initialDimension: 0)
        chunksController.onSelectChunk = { [weak self, weak mapController] position in
            self?.selectedIndex = 0
            mapController?.selectChunkFromChunkTab(position)
        }
        chunksController.onSelectTickingArea = { [weak self, weak mapController] position in
            self?.selectedIndex = 0
            mapController?.selectTickingAreaFromChunkTab(position)
        }
        chunksController.onChunkMutation = { [weak mapController] message, preferredPosition in
            mapController?.handleChunkMutationFromChunkTab(message: message, preferredPosition: preferredPosition)
        }
        let chunks = UINavigationController(rootViewController: chunksController)
        chunks.tabBarItem = UITabBarItem(title: "区块", image: UIImage(systemName: "square.grid.3x3"), tag: 2)

        let nbt = UINavigationController(rootViewController: NBTMenuViewController(session: session))
        let commandController = WorldCommandViewController(session: session)
        self.commandController = commandController
        let commands = UINavigationController(rootViewController: commandController)
        let tools = UINavigationController(rootViewController: WorldToolsViewController(session: session))

        // Preserve the previously requested “实体” second tab. The former map
        // toolbar chunk list now has its own dedicated “区块” tab.
        for navigation in [map, entities, chunks, nbt, commands, tools] {
            navigation.navigationBar.prefersLargeTitles = false
            navigation.viewControllers.first?.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeWorkspace)
            )
        }
        viewControllers = [map, entities, chunks, nbt, commands, tools]
        delegate = self

        // If Command.txt exists, the command terminal is the first workspace
        // page shown. This happens even for an empty file, matching the shared
        // folder workflow and avoiding a visible map -> command tab jump.
        if SharedCommandFileStore.commandFileExists {
            selectedIndex = commandTabIndex
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didCheckSharedCommandFile else { return }
        didCheckSharedCommandFile = true
        offerSharedCommandFileIfNeeded()
    }

    private func offerSharedCommandFileIfNeeded() {
        guard SharedCommandFileStore.commandFileExists else { return }
        selectedIndex = commandTabIndex
        commandController?.loadViewIfNeeded()

        let lines: [SharedCommandFileLine]
        do {
            lines = try SharedCommandFileStore.readCommandLines()
        } catch {
            showError(error, title: "无法读取 Commands/Command.txt")
            return
        }
        guard !lines.isEmpty else { return }

        let alert = UIAlertController(
            title: "检测到 Command.txt",
            message: "检测到 \(lines.count) 条非空命令。是否执行？确认后会先检查全部命令语法；只要任意一行存在语法错误，本文件中的所有命令都不会执行。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "不执行", style: .cancel))
        alert.addAction(UIAlertAction(title: "检查并执行", style: .default) { [weak self] _ in
            self?.validateAndExecuteSharedCommands(lines)
        })
        present(alert, animated: true)
    }

    private func validateAndExecuteSharedCommands(_ lines: [SharedCommandFileLine]) {
        setSharedCommandBatchNavigationLocked(true)
        let validationOverlay = showBusy("正在检查 Command.txt 语法…")
        view.isUserInteractionEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var parsed = [ValidatedSharedWorldCommand]()
            parsed.reserveCapacity(lines.count)
            var syntaxErrors = [(lineNumber: Int, rawText: String, message: String)]()

            for line in lines {
                do {
                    parsed.append(ValidatedSharedWorldCommand(
                        lineNumber: line.lineNumber,
                        rawText: line.text,
                        command: try WorldCommandParser.parse(line.text)
                    ))
                } catch {
                    syntaxErrors.append((
                        lineNumber: line.lineNumber,
                        rawText: line.text,
                        message: error.localizedDescription
                    ))
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                validationOverlay.removeFromSuperview()

                if !syntaxErrors.isEmpty {
                    self.setSharedCommandBatchNavigationLocked(false)
                    self.view.isUserInteractionEnabled = true
                    let maximumDisplayedErrors = 12
                    let details = syntaxErrors.prefix(maximumDisplayedErrors).map { item in
                        "第 \(item.lineNumber) 行：\(item.rawText)\n\(item.message)"
                    }.joined(separator: "\n\n")
                    let hiddenCount = max(0, syntaxErrors.count - maximumDisplayedErrors)
                    let suffix = hiddenCount > 0
                        ? "\n\n另外还有 \(hiddenCount) 处语法错误。"
                        : ""
                    let alert = UIAlertController(
                        title: "Command.txt 语法检查失败",
                        message: "发现 \(syntaxErrors.count) 处语法错误，未执行任何命令。\n\n\(details)\(suffix)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert, animated: true)
                    return
                }

                guard let commandController = self.commandController else {
                    self.setSharedCommandBatchNavigationLocked(false)
                    self.view.isUserInteractionEnabled = true
                    self.showError(
                        MCBEEditorError.unsupported("命令栏目尚未准备完成"),
                        title: "无法执行 Command.txt"
                    )
                    return
                }

                self.mapController?.prepareForSharedCommandBatch()
                self.selectedIndex = self.commandTabIndex
                self.setSharedCommandBatchNavigationLocked(true)
                // Syntax checking used a modal busy shield. Once execution starts,
                // restore interaction so the terminal can scroll while its own
                // running state disables command input; only leaving this tab is locked.
                self.view.isUserInteractionEnabled = true
                commandController.executeValidatedSharedCommands(parsed) { [weak self] in
                    guard let self = self else { return }
                    self.setSharedCommandBatchNavigationLocked(false)
                    self.view.isUserInteractionEnabled = true
                }
            }
        }
    }


    private func setSharedCommandBatchNavigationLocked(_ locked: Bool) {
        sharedCommandBatchRunning = locked
        if locked { selectedIndex = commandTabIndex }
        isModalInPresentation = locked

        if let items = tabBar.items {
            for (index, item) in items.enumerated() {
                item.isEnabled = !locked || index == commandTabIndex
            }
        }
        for case let navigation as UINavigationController in viewControllers ?? [] {
            navigation.viewControllers.first?.navigationItem.leftBarButtonItem?.isEnabled = !locked
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        shouldSelect viewController: UIViewController
    ) -> Bool {
        guard sharedCommandBatchRunning else { return true }
        guard let controllers = viewControllers,
              let index = controllers.firstIndex(where: { $0 === viewController }) else { return false }
        return index == commandTabIndex
    }

    func showMapBlockSearchHit(
        _ hit: BedrockBlockSearchHit,
        result: BedrockBlockSearchScanResult,
        viewedState: BlockSearchViewedState
    ) {
        session.rememberBlockSearchResult(result, viewedState: viewedState)
        selectedIndex = 0
        if let mapNavigation = viewControllers?.first as? UINavigationController {
            mapNavigation.popToRootViewController(animated: false)
        }
        session.requestMapBlockSelection(x: hit.x, y: hit.y, z: hit.z, dimension: hit.dimension)
    }

    func showRememberedBlockSearchResults() {
        guard let result = session.rememberedBlockSearchResult,
              let viewedState = session.rememberedBlockSearchViewedState,
              let mapNavigation = viewControllers?.first as? UINavigationController else { return }
        selectedIndex = 0
        mapNavigation.popToRootViewController(animated: false)
        mapNavigation.pushViewController(
            BlockSearchResultsViewController(session: session, result: result, viewedState: viewedState),
            animated: true
        )
    }

    @objc private func closeWorkspace() {
        guard !sharedCommandBatchRunning else { return }
        dismiss(animated: true)
    }

    deinit { session.close() }
}
