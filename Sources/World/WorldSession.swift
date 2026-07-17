import Foundation

struct WorldSelectionCoordinate {
    let x: Double
    let y: Double
    let z: Double
    let dimension: Int32

    var blockDescription: String {
        "X=\(format(x)) Y=\(format(y)) Z=\(format(z))"
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int64(value)) : String(format: "%.2f", value)
    }
}

final class WorldSession {
    static let worldDidChangeNotification = Notification.Name("BlocktopographWorldSessionDidChange")
    static let mapBlockSelectionNotification = Notification.Name("BlocktopographMapBlockSelectionRequested")

    let world: ImportedWorld
    let document: WorldDocument
    private var cachedDatabase: MojangLevelDB?
    private var selectedBlockCoordinateStorage: WorldSelectionCoordinate?
    private var selectedWorldObjectCoordinateStorage: WorldSelectionCoordinate?
    private var requestedMapBlockCoordinateStorage: WorldSelectionCoordinate?
    private var blockSearchResultStorage: BedrockBlockSearchScanResult?
    private let lock = NSLock()

    init(world: ImportedWorld, store: WorldStore = .shared) {
        self.world = world
        self.document = WorldDocument(rootURL: store.worldURL(for: world))
    }

    func database() throws -> MojangLevelDB {
        lock.lock()
        defer { lock.unlock() }
        if let cachedDatabase = cachedDatabase { return cachedDatabase }
        let opened = try document.openDatabase(readOnly: false)
        cachedDatabase = opened
        return opened
    }

    var selectedBlockCoordinate: WorldSelectionCoordinate? {
        lock.lock()
        defer { lock.unlock() }
        return selectedBlockCoordinateStorage
    }

    var selectedWorldObjectCoordinate: WorldSelectionCoordinate? {
        lock.lock()
        defer { lock.unlock() }
        return selectedWorldObjectCoordinateStorage
    }

    var requestedMapBlockCoordinate: WorldSelectionCoordinate? {
        lock.lock()
        defer { lock.unlock() }
        return requestedMapBlockCoordinateStorage
    }

    var rememberedBlockSearchResult: BedrockBlockSearchScanResult? {
        lock.lock()
        defer { lock.unlock() }
        return blockSearchResultStorage
    }

    func rememberSelectedBlock(x: Int64, y: Int32, z: Int64, dimension: Int32) {
        lock.lock()
        selectedBlockCoordinateStorage = WorldSelectionCoordinate(
            x: Double(x), y: Double(y), z: Double(z), dimension: dimension
        )
        lock.unlock()
    }

    func rememberSelectedWorldObject(_ object: BedrockWorldObject) {
        guard let position = object.position else { return }
        lock.lock()
        selectedWorldObjectCoordinateStorage = WorldSelectionCoordinate(
            x: position.x, y: position.y, z: position.z, dimension: object.dimension
        )
        lock.unlock()
    }

    func rememberBlockSearchResult(_ result: BedrockBlockSearchScanResult) {
        lock.lock()
        blockSearchResultStorage = result
        lock.unlock()
    }

    func requestMapBlockSelection(x: Int64, y: Int32, z: Int64, dimension: Int32) {
        lock.lock()
        requestedMapBlockCoordinateStorage = WorldSelectionCoordinate(x: Double(x), y: Double(y), z: Double(z), dimension: dimension)
        lock.unlock()
        NotificationCenter.default.post(name: Self.mapBlockSelectionNotification, object: self)
    }

    func clearRememberedSelections() {
        lock.lock()
        selectedBlockCoordinateStorage = nil
        selectedWorldObjectCoordinateStorage = nil
        requestedMapBlockCoordinateStorage = nil
        blockSearchResultStorage = nil
        lock.unlock()
    }

    func close() {
        lock.lock()
        cachedDatabase?.close()
        cachedDatabase = nil
        lock.unlock()
    }

    func invalidateAfterExternalChange() {
        close()
        NotificationCenter.default.post(name: Self.worldDidChangeNotification, object: self)
    }

    deinit { close() }
}
