import Foundation

struct WorldInfoRow {
    let title: String
    let value: String
}

final class WorldInspector {
    private struct FileStats {
        var size: Int64 = 0
        var count: Int = 0
    }

    func inspect(session: WorldSession) throws -> [WorldInfoRow] {
        let file = try session.document.readLevelDat()
        let root = file.document.root
        let stats = try fileStats(at: session.document.rootURL)
        let dbStats = try fileStats(at: session.document.databaseURL)

        let database = try session.database()
        let playerCount = try PlayerNBTStore(session: session).records().count
        let entityScan = try BedrockWorldObjectScanner(database: database).scanAll(
            dimensions: nil,
            includeEntities: true,
            includeBlockEntities: false,
            maximumObjects: 1_000_000
        )
        let entityCount = entityScan.objects.filter { $0.kind == .entity }.count
        let databaseKeys = try database.entries(includeValues: false, limit: 0).map(\.key)
        let chunkCount = Set(databaseKeys.compactMap { BedrockDBKey.parse($0)?.position }).count
        let villageRecords = try VillageNBTStore(session: session).records()
        let villageCount = Set(villageRecords.map(\.villageIdentifier)).count

        var rows = [WorldInfoRow]()
        rows.append(WorldInfoRow(title: "名称", value: root.stringValue(named: "LevelName") ?? session.world.name))
        rows.append(WorldInfoRow(title: "玩家数目", value: String(playerCount)))
        rows.append(WorldInfoRow(title: "实体数目", value: String(entityCount)))
        rows.append(WorldInfoRow(title: "区块数目", value: String(chunkCount)))
        rows.append(WorldInfoRow(title: "村庄数目", value: String(villageCount)))
        rows.append(WorldInfoRow(title: "level.dat 版本", value: String(file.version)))
        appendInt(named: "StorageVersion", title: "存储版本", root: root, to: &rows)
        appendInt(named: "NetworkVersion", title: "网络版本", root: root, to: &rows)
        if let gameType = root.intValue(named: "GameType") { rows.append(WorldInfoRow(title: "游戏模式", value: gameTypeName(gameType))) }
        if let difficulty = root.intValue(named: "Difficulty") { rows.append(WorldInfoRow(title: "难度", value: difficultyName(difficulty))) }
        if let x = root.intValue(named: "SpawnX"), let y = root.intValue(named: "SpawnY"), let z = root.intValue(named: "SpawnZ") {
            rows.append(WorldInfoRow(title: "出生点", value: "\(x), \(y), \(z)"))
        }
        if let lastPlayed = integer64(named: "LastPlayed", root: root) { rows.append(WorldInfoRow(title: "最后游玩", value: formatTimestamp(lastPlayed))) }
        rows.append(WorldInfoRow(title: "世界大小", value: ByteCountFormatter.string(fromByteCount: stats.size, countStyle: .file)))
        rows.append(WorldInfoRow(title: "数据库大小", value: ByteCountFormatter.string(fromByteCount: dbStats.size, countStyle: .file)))
        rows.append(WorldInfoRow(title: "文件数量", value: String(stats.count)))
        return rows
    }

    private func fileStats(at url: URL) throws -> FileStats {
        var result = FileStats()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return result }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            result.count += 1
            result.size += Int64(values.fileSize ?? 0)
        }
        return result
    }

    private func appendInt(named name: String, title: String, root: NBTValue, to rows: inout [WorldInfoRow]) {
        if let value = root.intValue(named: name) { rows.append(WorldInfoRow(title: title, value: String(value))) }
    }
    private func integer64(named name: String, root: NBTValue) -> Int64? {
        guard let value = root.compoundValue(named: name) else { return nil }
        switch value { case .long(let n): return n; case .int(let n): return Int64(n); default: return nil }
    }
    private func formatTimestamp(_ value: Int64) -> String {
        guard value > 0 else { return String(value) }
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(value)))
    }
    private func gameTypeName(_ value: Int32) -> String {
        switch value { case 0: return "生存（0）"; case 1: return "创造（1）"; case 2: return "冒险（2）"; case 3: return "旁观（3）"; default: return "未知（\(value)）" }
    }
    private func difficultyName(_ value: Int32) -> String {
        switch value { case 0: return "和平（0）"; case 1: return "简单（1）"; case 2: return "普通（2）"; case 3: return "困难（3）"; default: return "未知（\(value)）" }
    }
}
