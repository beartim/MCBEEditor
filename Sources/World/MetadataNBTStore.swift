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

struct MetadataNBTRename {
    let record: MetadataNBTRecord
    let newKeyText: String
}

final class MetadataNBTStore {
    private let session: WorldSession
    var worldSession: WorldSession { session }

    static let exactKeys: [String] = [
        "AutonomousEntities", "BiomeData", "mVillages", "Nether", "Overworld", "TheEnd",
        "portals", "dimension0", "scoreboard", "mobevents", "schedulerWT"
    ]
    private static let exactKeySet = Set(exactKeys)

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

    func contains(keyText: String) throws -> Bool {
        let normalized = try Self.validatedKeyText(keyText)
        return try session.database().get(Data(normalized.utf8)) != nil
    }

    func save(record: MetadataNBTRecord, roots: [ConsecutiveNBTRecord]) throws {
        guard !roots.isEmpty else {
            throw MCBEEditorError.malformedData("至少需要保留一个 NBT 根标签")
        }
        let encoded = try ConsecutiveNBTCodec.encode(roots)
        try session.database().put(encoded, for: record.key, sync: true)
    }

    @discardableResult
    func create(keyText: String, documents: [NBTDocument], overwrite: Bool = false) throws -> MetadataNBTRecord {
        guard !documents.isEmpty else {
            throw MCBEEditorError.malformedData("至少需要一个 NBT 根标签")
        }
        let normalized = try Self.validatedKeyText(keyText)
        let key = Data(normalized.utf8)
        let database = try session.database()
        if !overwrite, try database.get(key) != nil {
            throw MCBEEditorError.malformedData("已存在同名元数据键：\(normalized)")
        }
        let roots = documents.map {
            ConsecutiveNBTRecord(document: $0, rawData: Data(), encoding: .littleEndian)
        }
        let encoded = try ConsecutiveNBTCodec.encode(roots)
        try database.put(encoded, for: key, sync: true)
        guard try database.get(key) == encoded else {
            throw MCBEEditorError.malformedData("元数据写入后未能从 LevelDB 读回")
        }
        return Self.makeRecord(key: key, value: encoded)
    }

    func rename(record: MetadataNBTRecord, to newKeyText: String, overwrite: Bool = false) throws {
        let normalized = try Self.validatedKeyText(newKeyText)
        let targetKey = Data(normalized.utf8)
        guard targetKey != record.key else { return }
        let database = try session.database()
        if !overwrite, try database.get(targetKey) != nil {
            throw MCBEEditorError.malformedData("已存在同名元数据键：\(normalized)")
        }
        try database.applyBatch(
            puts: [(key: targetKey, value: record.rawData)],
            deletes: [record.key],
            sync: true
        )
    }

    func delete(record: MetadataNBTRecord) throws {
        try session.database().delete(record.key, sync: true)
    }

    @discardableResult
    func delete(records: [MetadataNBTRecord]) throws -> Int {
        let keys = Array(Set(records.map(\.key)))
        guard !keys.isEmpty else { return 0 }
        try session.database().applyBatch(puts: [], deletes: keys, sync: true)
        return keys.count
    }

    /// Atomically renames several metadata keys while preserving each raw value byte-for-byte.
    /// Destination keys must be unique. Existing non-selected destination keys are rejected.
    func renameBatch(_ renames: [MetadataNBTRename]) throws {
        guard !renames.isEmpty else { return }

        var normalized = [(record: MetadataNBTRecord, keyText: String, key: Data)]()
        normalized.reserveCapacity(renames.count)
        for item in renames {
            let text = try Self.validatedKeyText(item.newKeyText)
            normalized.append((item.record, text, Data(text.utf8)))
        }

        let sourceKeys = Set(normalized.map { $0.record.key })
        let destinationKeys = normalized.map(\.key)
        guard Set(destinationKeys).count == destinationKeys.count else {
            throw MCBEEditorError.malformedData("批量重命名后产生了重复的元数据键")
        }

        let database = try session.database()
        for item in normalized where !sourceKeys.contains(item.key) {
            if try database.get(item.key) != nil {
                throw MCBEEditorError.malformedData("目标元数据键已存在：\(item.keyText)")
            }
        }

        let changed = normalized.filter { $0.key != $0.record.key }
        guard !changed.isEmpty else { return }
        try database.applyBatch(
            puts: changed.map { (key: $0.key, value: $0.record.rawData) },
            deletes: changed.map { $0.record.key },
            sync: true
        )
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

    static func validatedKeyText(_ key: String) throws -> String {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw MCBEEditorError.malformedData("元数据键不能为空")
        }
        guard !clean.contains("\0"), !clean.contains("\n"), !clean.contains("\r") else {
            throw MCBEEditorError.malformedData("元数据键包含无效字符")
        }
        guard isMetadataKey(clean) else {
            throw MCBEEditorError.unsupported(
                "“\(clean)”不属于当前支持的世界元数据键。可使用固定元数据键或 map_* 地图键。"
            )
        }
        return clean
    }

    static func isMetadataKey(_ key: String) -> Bool {
        exactKeySet.contains(key) || key.hasPrefix("map_")
    }

    static func creationHint(existingKeys: Set<String> = []) -> String {
        let available = exactKeys.filter { !existingKeys.contains($0) }
        let fixed = available.isEmpty ? "固定元数据键均已存在" : "可新建：" + available.joined(separator: "、")
        return "\(fixed)；地图数据使用 map_<ID>。"
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
        if let index = exactKeys.firstIndex(of: key) { return String(format: "%03d", index) }
        if key.hasPrefix("map_") { return "100_\(key)" }
        return "999_\(key)"
    }
}
