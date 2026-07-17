import UIKit

final class WorldDetailTabBarController: UITabBarController {
    private let session: WorldSession
    private weak var mapController: WorldMapViewController?

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

        let nbt = UINavigationController(rootViewController: NBTMenuViewController(session: session))
        let tools = UINavigationController(rootViewController: WorldToolsViewController(session: session))

        // Preserve the previously requested “实体” second tab. The former map
        // toolbar chunk list now has its own dedicated “区块” tab.
        for navigation in [map, entities, chunks, nbt, tools] {
            navigation.navigationBar.prefersLargeTitles = false
            navigation.viewControllers.first?.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeWorkspace)
            )
        }
        viewControllers = [map, entities, chunks, nbt, tools]
    }


    func showMapBlockSearchHit(_ hit: BedrockBlockSearchHit, result: BedrockBlockSearchScanResult) {
        session.rememberBlockSearchResult(result)
        selectedIndex = 0
        if let mapNavigation = viewControllers?.first as? UINavigationController {
            mapNavigation.popToRootViewController(animated: false)
        }
        session.requestMapBlockSelection(x: hit.x, y: hit.y, z: hit.z, dimension: hit.dimension)
    }

    func showRememberedBlockSearchResults() {
        guard let result = session.rememberedBlockSearchResult,
              let mapNavigation = viewControllers?.first as? UINavigationController else { return }
        selectedIndex = 0
        mapNavigation.popToRootViewController(animated: false)
        mapNavigation.pushViewController(
            BlockSearchResultsViewController(session: session, result: result),
            animated: true
        )
    }

    @objc private func closeWorkspace() { dismiss(animated: true) }

    deinit { session.close() }
}
