import Foundation

struct ImportedWorld: Codable, Hashable {
    enum SourceKind: String, Codable {
        case mcworld
        case folder
    }

    let id: UUID
    var name: String
    let relativePath: String
    let importedAt: Date
    let sourceKind: SourceKind
}

final class WorldStore {
    static let shared = WorldStore()

    private let manager = FileManager.default
    private let lock = NSLock()
    let rootURL: URL
    let worldsURL: URL
    let metadataRootURL: URL
    private let indexURL: URL
    private var storedWorlds: [ImportedWorld] = []

    var worlds: [ImportedWorld] {
        lock.lock()
        defer { lock.unlock() }
        return storedWorlds
    }

    private init() {
        let applicationSupport = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = applicationSupport.appendingPathComponent("Blocktopograph", isDirectory: true)
        worldsURL = rootURL.appendingPathComponent("Worlds", isDirectory: true)
        metadataRootURL = rootURL.appendingPathComponent("Metadata", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("worlds.json")
        try? manager.createDirectory(at: worldsURL, withIntermediateDirectories: true)
        try? manager.createDirectory(at: metadataRootURL, withIntermediateDirectories: true)
        load()
    }

    func worldURL(for world: ImportedWorld) -> URL {
        rootURL.appendingPathComponent(world.relativePath, isDirectory: true)
    }

    func metadataURL(for world: ImportedWorld) -> URL {
        metadataRootURL.appendingPathComponent(world.id.uuidString, isDirectory: true)
    }

    func add(_ world: ImportedWorld) throws {
        lock.lock()
        defer { lock.unlock() }
        storedWorlds.append(world)
        storedWorlds.sort { $0.importedAt > $1.importedAt }
        do {
            try saveLocked()
        } catch {
            storedWorlds.removeAll { $0.id == world.id }
            throw error
        }
    }

    func remove(_ world: ImportedWorld) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = worldURL(for: world)
        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        let metadata = metadataURL(for: world)
        if manager.fileExists(atPath: metadata.path) { try? manager.removeItem(at: metadata) }
        let previous = storedWorlds
        storedWorlds.removeAll { $0.id == world.id }
        do {
            try saveLocked()
        } catch {
            storedWorlds = previous
            throw error
        }
    }

    func rename(_ world: ImportedWorld, to requestedName: String) throws {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BlocktopographError.io("世界名称不能为空") }
        try writeWorldName(name, at: worldURL(for: world))

        lock.lock()
        defer { lock.unlock() }
        guard let index = storedWorlds.firstIndex(where: { $0.id == world.id }) else { return }
        let previous = storedWorlds[index].name
        storedWorlds[index].name = name
        do {
            try saveLocked()
        } catch {
            storedWorlds[index].name = previous
            throw error
        }
    }

    func duplicate(_ world: ImportedWorld) throws -> ImportedWorld {
        let source = worldURL(for: world)
        guard manager.fileExists(atPath: source.path) else {
            throw BlocktopographError.io("原世界目录不存在")
        }

        let id = UUID()
        let destination = worldsURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let name = uniqueCopyName(for: world.name)
        try? manager.removeItem(at: destination)

        do {
            try manager.copyItem(at: source, to: destination)
            try writeWorldName(name, at: destination)
            let copy = ImportedWorld(
                id: id,
                name: name,
                relativePath: "Worlds/\(id.uuidString)",
                importedAt: Date(),
                sourceKind: world.sourceKind
            )
            let sourceMetadata = metadataURL(for: world)
            let destinationMetadata = metadataURL(for: copy)
            if manager.fileExists(atPath: sourceMetadata.path) {
                try? manager.removeItem(at: destinationMetadata)
                try manager.copyItem(at: sourceMetadata, to: destinationMetadata)
            }
            try add(copy)
            return copy
        } catch {
            try? manager.removeItem(at: destination)
            try? manager.removeItem(at: metadataRootURL.appendingPathComponent(id.uuidString, isDirectory: true))
            throw error
        }
    }

    private func uniqueCopyName(for sourceName: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let names = Set(storedWorlds.map { $0.name })
        let base = "\(sourceName) 副本"
        if !names.contains(base) { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func writeWorldName(_ name: String, at rootURL: URL) throws {
        let document = WorldDocument(rootURL: rootURL)
        var levelDat = try document.readLevelDat()
        guard case .compound(var tags) = levelDat.document.root else {
            throw BlocktopographError.malformedData("level.dat 根节点不是 Compound")
        }
        if let index = tags.firstIndex(where: { $0.name == "LevelName" }) {
            tags[index].value = .string(name)
        } else {
            tags.append(NBTNamedTag(name: "LevelName", value: .string(name)))
        }
        levelDat.document.root = .compound(tags)
        try document.writeLevelDat(levelDat)
        try AtomicFile.write(Data(name.utf8), to: rootURL.appendingPathComponent("levelname.txt"))
    }

    private func load() {
        do {
            let data = try Data(contentsOf: indexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            storedWorlds = try decoder.decode([ImportedWorld].self, from: data)
            storedWorlds = storedWorlds.filter { manager.fileExists(atPath: worldURL(for: $0).path) }
        } catch {
            storedWorlds = []
        }
    }

    private func saveLocked() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(storedWorlds)
        try AtomicFile.write(data, to: indexURL)
    }
}
