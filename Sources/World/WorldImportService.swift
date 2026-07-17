import Foundation

final class WorldImportService {
    static let supportedArchiveExtensions: Set<String> = ["mcworld", "zip"]

    private let store: WorldStore
    private let manager = FileManager.default

    init(store: WorldStore = .shared) {
        self.store = store
    }

    func importURL(_ sourceURL: URL) throws -> ImportedWorld {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let destination = store.worldsURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let staging = store.rootURL.appendingPathComponent("Import-\(id.uuidString)", isDirectory: true)
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let kind: ImportedWorld.SourceKind
            if values.isDirectory == true {
                kind = .folder
                try coordinatedRead(url: sourceURL) { coordinatedURL in
                    try copyDirectoryContents(from: coordinatedURL, to: staging)
                }
            } else if Self.supportedArchiveExtensions.contains(sourceURL.pathExtension.lowercased()) {
                kind = .mcworld
                let localArchive = store.rootURL.appendingPathComponent("Import-\(id.uuidString).mcworld")
                try? manager.removeItem(at: localArchive)
                try coordinatedRead(url: sourceURL) { coordinatedURL in
                    try manager.copyItem(at: coordinatedURL, to: localArchive)
                }
                defer { try? manager.removeItem(at: localArchive) }
                try MiniZipArchive.extract(archiveURL: localArchive, to: staging)
            } else {
                throw BlocktopographError.invalidWorld("请选择 .mcworld、ZIP 世界文件或包含 level.dat 与 db 的世界目录")
            }

            let root = try locateWorldRoot(in: staging)
            try validateWorld(at: root)
            try? manager.removeItem(at: destination)
            try manager.moveItem(at: root, to: destination)
            if root != staging { try? manager.removeItem(at: staging) }

            let name = readWorldName(at: destination) ?? sourceURL.deletingPathExtension().lastPathComponent
            let world = ImportedWorld(
                id: id,
                name: name.isEmpty ? "未命名世界" : name,
                relativePath: "Worlds/\(id.uuidString)",
                importedAt: Date(),
                sourceKind: kind
            )
            try store.add(world)
            return world
        } catch {
            try? manager.removeItem(at: staging)
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    func sharedImportCandidates() throws -> [URL] {
        guard let documentsURL = manager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw BlocktopographError.io("无法访问 App 的 Documents 目录")
        }

        var candidates: [URL] = []
        let topLevel = try manager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for url in topLevel {
            if url.lastPathComponent == "Inbox" {
                let inboxItems = (try? manager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                candidates.append(contentsOf: inboxItems.filter(isPotentialImportURL))
            } else if isPotentialImportURL(url) {
                candidates.append(url)
            }
        }

        return Array(Set(candidates)).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    func exportWorld(_ world: ImportedWorld) throws -> URL {
        let source = store.worldURL(for: world)
        try validateWorld(at: source)
        let safeName = world.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let output = manager.temporaryDirectory.appendingPathComponent(
            "\(safeName)-\(UUID().uuidString.prefix(8)).mcworld"
        )
        try? manager.removeItem(at: output)
        try MiniZipArchive.create(from: source, to: output)
        return output
    }

    private func isPotentialImportURL(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
            return false
        }
        if values.isDirectory == true {
            if isValidWorld(at: url) { return true }
            let children = (try? manager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return children.filter(isValidWorld).count == 1
        }
        return values.isRegularFile == true && Self.supportedArchiveExtensions.contains(url.pathExtension.lowercased())
    }

    private func isValidWorld(at url: URL) -> Bool {
        manager.fileExists(atPath: url.appendingPathComponent("level.dat").path) &&
        manager.fileExists(atPath: url.appendingPathComponent("db", isDirectory: true).path)
    }

    private func validateWorld(at url: URL) throws {
        guard manager.fileExists(atPath: url.appendingPathComponent("level.dat").path) else {
            throw BlocktopographError.invalidWorld("缺少 level.dat")
        }
        guard manager.fileExists(atPath: url.appendingPathComponent("db", isDirectory: true).path) else {
            throw BlocktopographError.invalidWorld("缺少 db 目录")
        }
    }

    private func locateWorldRoot(in staging: URL) throws -> URL {
        if manager.fileExists(atPath: staging.appendingPathComponent("level.dat").path) { return staging }
        let children = try manager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let candidates = children.filter {
            manager.fileExists(atPath: $0.appendingPathComponent("level.dat").path)
        }
        guard candidates.count == 1 else {
            throw BlocktopographError.invalidWorld("压缩包或所选目录中未找到唯一世界根目录")
        }
        return candidates[0]
    }

    private func readWorldName(at url: URL) -> String? {
        let nameURL = url.appendingPathComponent("levelname.txt")
        if let text = try? String(contentsOf: nameURL, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let document = try? WorldDocument(rootURL: url).readLevelDat(),
           let levelName = document.document.root.stringValue(named: "LevelName") {
            return levelName
        }
        return nil
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        let children = try manager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for child in children {
            try manager.copyItem(at: child, to: destination.appendingPathComponent(child.lastPathComponent))
        }
    }

    private func coordinatedRead(url: URL, operation: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do { try operation(coordinatedURL) } catch { operationError = error }
        }
        if let coordinationError = coordinationError { throw coordinationError }
        if let operationError = operationError { throw operationError }
    }
}
