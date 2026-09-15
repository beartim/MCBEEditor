import Foundation

final class CliWorldWorkspace {
    let session: WorldSession
    let sessionRoot: URL
    let worldRoot: URL
    private let paths: CliWorldPaths
    private let archiveContainer: URL?
    private var sourceStamp: Data?
    private let manager = FileManager.default

    private init(paths: CliWorldPaths, root: URL, world: URL, container: URL?, stamp: Data?) {
        self.paths = paths
        sessionRoot = root
        worldRoot = world
        archiveContainer = container
        sourceStamp = stamp
        session = WorldSession(rootURL: world, displayName: paths.source.deletingPathExtension().lastPathComponent)
    }

    static func open(_ paths: CliWorldPaths, inPlace: Bool) throws -> CliWorldWorkspace {
        let manager = FileManager.default
        let stamp = inPlace ? try CliFileSystem.stamp(paths.source) : nil
        try manager.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        let root = paths.cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let world: URL, container: URL?
            if paths.isDirectory {
                world = root.appendingPathComponent("World", isDirectory: true)
                container = nil
                try validateWorld(paths.source)
                try CliFileSystem.copyWorld(paths.source, to: world)
            } else {
                let extracted = root.appendingPathComponent("Container", isDirectory: true)
                try MiniZipArchive.extract(archiveURL: paths.source, to: extracted)
                world = try locateWorld(extracted)
                container = extracted
            }
            try validateWorld(world)
            let workspace = CliWorldWorkspace(paths: paths, root: root, world: world, container: container, stamp: stamp)
            _ = try workspace.session.document.readLevelDat()
            if inPlace { try workspace.requireUnchangedSource() }
            return workspace
        } catch {
            try? manager.removeItem(at: root)
            throw error
        }
    }

    private static func validateWorld(_ root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("level.dat").path),
              CliFileSystem.isDirectory(root.appendingPathComponent("db")) else {
            throw CliError.file("所选世界缺少 level.dat 或 db 文件夹。")
        }
    }

    private static func locateWorld(_ container: URL) throws -> URL {
        if (try? validateWorld(container)) != nil { return container }
        let candidates = try CliFileSystem.entries(container).filter {
            CliFileSystem.isDirectory($0) && (try? validateWorld($0)) != nil
        }
        guard let minimum = candidates.map({ $0.pathComponents.count }).min() else {
            throw CliError.file("压缩包中未找到 Bedrock 世界根目录。")
        }
        let roots = candidates.filter { $0.pathComponents.count == minimum }
        guard roots.count == 1 else { throw CliError.file("压缩包中找到多个世界根目录，无法确定要编辑的世界。") }
        return roots[0]
    }

    func export(to destination: URL, overwrite: Bool) throws {
        session.close()
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".mcbe-cli-\(UUID().uuidString).mcworld")
        defer { try? manager.removeItem(at: temporary) }
        // Save-as follows the GUI export rule: export only the selected world root and
        // filter editor-private metadata. In-place archive commits preserve the original container.
        try MiniZipArchive.create(from: worldRoot, to: temporary)
        try CliFileSystem.publishFile(temporary, to: destination, overwrite: overwrite)
    }

    func commitInPlace(notice: (String) -> Void) throws {
        guard sourceStamp != nil else { throw CliError.file("当前会话未选择原位更新。") }
        session.close()
        let parent = paths.source.deletingLastPathComponent()
        if let container = archiveContainer {
            let temporary = parent.appendingPathComponent(".mcbe-cli-\(UUID().uuidString).mcworld")
            defer { try? manager.removeItem(at: temporary) }
            let prefix = worldRoot.path == container.path ? "" : String(worldRoot.path.dropFirst(container.path.count + 1)) + "/"
            try MiniZipArchive.create(from: container, to: temporary, preserveAllFiles: true,
                                      excludingPaths: [prefix + "db/LOCK"])
            try requireUnchangedSource()
            try CliFileSystem.publishFile(temporary, to: paths.source, overwrite: true)
            sourceStamp = try CliFileSystem.stamp(paths.source)
        } else {
            let staged = parent.appendingPathComponent(".mcbe-cli-next-\(UUID().uuidString)", isDirectory: true)
            let backup = parent.appendingPathComponent(".mcbe-cli-original-\(UUID().uuidString)", isDirectory: true)
            defer { try? manager.removeItem(at: staged) }
            try CliFileSystem.copyWorld(worldRoot, to: staged)
            try requireUnchangedSource()
            notice("原位替换前的恢复目录：\(backup.path)")
            try manager.moveItem(at: paths.source, to: backup)
            do { try manager.moveItem(at: staged, to: paths.source) }
            catch let publishError {
                do { try manager.moveItem(at: backup, to: paths.source) }
                catch let rollbackError {
                    throw CliError.file("原位提交及回滚失败；原世界保留在 \(backup.path)；提交：\(publishError.localizedDescription)；回滚：\(rollbackError.localizedDescription)")
                }
                throw publishError
            }
            do { try manager.removeItem(at: backup) }
            catch { notice("原位更新已完成；旧世界清理失败，仍保留在 \(backup.path)：\(error.localizedDescription)") }
            sourceStamp = try CliFileSystem.stamp(paths.source)
        }
    }

    private func requireUnchangedSource() throws {
        if sourceStamp != (try CliFileSystem.stamp(paths.source)) {
            throw CliError.file("原存档在本次处理期间发生变化，已拒绝原位提交；可从保留的工作副本另存为。")
        }
    }

    func finish(preserve: Bool, notice: (String) -> Void) {
        session.close()
        if !preserve {
            do { try manager.removeItem(at: sessionRoot) }
            catch { notice("工作副本清理失败：\(error.localizedDescription)") }
        }
        if manager.fileExists(atPath: worldRoot.path) {
            notice("工作副本已保留：\(worldRoot.path)\n可将此路径作为下一次 --world 的输入继续处理或重新导出。")
        }
    }

    deinit { session.close() }
}
