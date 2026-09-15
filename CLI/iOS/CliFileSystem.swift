import Foundation
import CryptoKit
import Darwin

enum CliFileSystem {
    private static let manager = FileManager.default

    static func entries(_ root: URL) throws -> [URL] {
        var pending = [root], result = [URL]()
        while let directory = pending.popLast() {
            for entry in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let type = try manager.attributesOfItem(atPath: entry.path)[.type] as? FileAttributeType
                guard type == .typeDirectory || type == .typeRegular else {
                    throw CliError.file("世界目录包含链接或非常规文件：\(entry.path)")
                }
                result.append(entry)
                if type == .typeDirectory { pending.append(entry) }
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    static func isDirectory(_ path: URL) -> Bool {
        var directory: ObjCBool = false
        return manager.fileExists(atPath: path.path, isDirectory: &directory) && directory.boolValue
    }

    private static func relativePath(of entry: URL, under root: URL) throws -> String {
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let entryURL = entry.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = rootURL.pathComponents
        let entryComponents = entryURL.pathComponents

        guard entryComponents.count > rootComponents.count else {
            throw CliError.file("世界目录条目无法转换为相对路径：\(entry.path)")
        }
        for index in rootComponents.indices {
            let lhs = rootComponents[index].precomposedStringWithCanonicalMapping
            let rhs = entryComponents[index].precomposedStringWithCanonicalMapping
            guard lhs.caseInsensitiveCompare(rhs) == .orderedSame else {
                throw CliError.file("世界目录条目不属于源目录：\(entry.path)")
            }
        }
        return entryComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    static func copyWorld(_ source: URL, to destination: URL) throws {
        if CliWorldPaths.sameOrInside(destination, source) { throw CliError.file("工作副本不能位于源世界内部。") }
        let items = try entries(source)
        try manager.createDirectory(at: destination, withIntermediateDirectories: false)
        for entry in items {
            let relative = try relativePath(of: entry, under: source)
            if relative.lowercased() == "db/lock" { continue }
            let target = destination.appendingPathComponent(relative)
            if isDirectory(entry) {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: entry, to: target)
                let mode = (try manager.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
                try manager.setAttributes([.posixPermissions: mode | 0o200], ofItemAtPath: target.path)
            }
        }
    }

    static func stamp(_ source: URL) throws -> Data {
        let type = try manager.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType
        if type == .typeRegular { return try fileHash(source) }
        guard type == .typeDirectory else { throw CliError.file("原位更新来源不是普通文件或目录。") }
        var hash = SHA256()
        for entry in try entries(source) {
            let directory = isDirectory(entry)
            let relative = try relativePath(of: entry, under: source)
            hash.update(data: Data(((directory ? "D:" : "F:") + relative + "\0").utf8))
            if !directory { hash.update(data: try fileHash(entry)) }
        }
        return Data(hash.finalize())
    }

    private static func fileHash(_ file: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { handle.closeFile() }
        var hash = SHA256()
        while true {
            let bytes = try handle.read(upToCount: 1_048_576) ?? Data()
            if bytes.isEmpty { break }
            hash.update(data: bytes)
        }
        return Data(hash.finalize())
    }

    static func publishFile(_ temporary: URL, to destination: URL, overwrite: Bool) throws {
        // The temporary is in the destination directory: rename replaces atomically;
        // link publishes without clobbering an output created after preflight.
        let status = temporary.path.withCString { source in
            destination.path.withCString { target in
                overwrite ? Darwin.rename(source, target) : Darwin.link(source, target)
            }
        }
        guard status == 0 else { throw CliError.file("保存失败：\(String(cString: strerror(errno)))；\(destination.path)") }
        if !overwrite { try manager.removeItem(at: temporary) }
    }
}
