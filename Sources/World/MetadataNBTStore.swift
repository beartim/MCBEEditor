import Foundation

struct MetadataNBTRecord {
    let key: Data
    let keyText: String
    let displayName: String
    let rawData: Data
    let roots: [ConsecutiveNBTRecord]?
    let decodeError: String?

    var detailText: String {
        var parts = [ByteCountFormatter.string(fromByteCount: Int64(rawData.count), countStyle: .file)]
        if let roots = roots { parts.insert("NBT 根标签 \(roots.count)", at: 0) }
        else { parts.insert("无法解析为 NBT", at: 0) }
        return parts.joined(separator: " · ")
    }
}

final class MetadataNBTStore {
    private let session: WorldSession

    private static let exactKeys: Set<String> = [
        "AutonomousEntities", "BiomeData", "mVillages", "Nether", "Overworld", "TheEnd",
        "portals", "dimension0", "scoreboard", "mobevents", "schedulerWT"
    ]

    init(session: WorldSession) {
        self.session = session
    }

    func records() throws -> [MetadataNBTRecord] {
        let database = try session.database()
        return try database.entries(includeValues: true, limit: 0).compactMap { entry in
            guard let value = entry.value,
                  let keyText = String(data: entry.key, encoding: .utf8),
                  Self.isMetadataKey(keyText) else { return nil }
            return Self.makeRecord(key: entry.key, value: value)
        }.sorted { lhs, rhs in
            Self.sortKey(lhs.keyText) < Self.sortKey(rhs.keyText)
        }
    }

    func record(for key: Data) throws -> MetadataNBTRecord? {
        guard let value = try session.database().get(key) else { return nil }
        return Self.makeRecord(key: key, value: value)
    }

    func save(record: MetadataNBTRecord, roots: [ConsecutiveNBTRecord]) throws {
        guard !roots.isEmpty else {
            throw MCBEEditorError.malformedData("至少需要保留一个 NBT 根标签")
        }
        let encoded = try ConsecutiveNBTCodec.encode(roots)
        try session.database().put(encoded, for: record.key, sync: true)
    }

    static func makeRecord(key: Data, value: Data) -> MetadataNBTRecord {
        let keyText = String(data: key, encoding: .utf8) ?? "0x\(key.hexString)"
        do {
            let roots = try ConsecutiveNBTCodec.decode(value)
            guard !roots.isEmpty else {
                return MetadataNBTRecord(key: key, keyText: keyText, displayName: displayName(keyText), rawData: value, roots: nil, decodeError: "NBT 值为空")
            }
            return MetadataNBTRecord(key: key, keyText: keyText, displayName: displayName(keyText), rawData: value, roots: roots, decodeError: nil)
        } catch {
            return MetadataNBTRecord(key: key, keyText: keyText, displayName: displayName(keyText), rawData: value, roots: nil, decodeError: error.localizedDescription)
        }
    }

    static func isMetadataKey(_ key: String) -> Bool {
        exactKeys.contains(key) || key.hasPrefix("map_")
    }

    private static func displayName(_ key: String) -> String {
        switch key {
        case "AutonomousEntities": return "自主实体"
        case "BiomeData": return "生物群系数据"
        case "mVillages": return "旧版村庄"
        case "Nether": return "下界元数据"
        case "Overworld": return "主世界元数据"
        case "TheEnd": return "末地元数据"
        case "portals": return "传送门"
        case "dimension0": return "维度 0"
        case "scoreboard": return "计分板"
        case "mobevents": return "生物事件"
        case "schedulerWT": return "计划刻"
        default:
            if key.hasPrefix("map_") { return "地图 \(String(key.dropFirst(4)))" }
            return key
        }
    }

    private static func sortKey(_ key: String) -> String {
        let order = [
            "AutonomousEntities", "BiomeData", "mVillages", "Nether", "Overworld", "TheEnd",
            "portals", "dimension0", "scoreboard", "mobevents", "schedulerWT"
        ]
        if let index = order.firstIndex(of: key) { return String(format: "%03d", index) }
        if key.hasPrefix("map_") { return "100_\(key)" }
        return "999_\(key)"
    }
}
