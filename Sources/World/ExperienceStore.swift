import Foundation

struct BedrockPlayerExperience {
    static let maximumLevel: Int32 = 24_791

    var total: Int32
    var level: Int32
    var progress: Float

    init(total: Int32, level: Int32, progress: Float) {
        self.total = total
        self.level = min(Self.maximumLevel, max(0, level))
        self.progress = min(1, max(0, progress))
    }
}

struct PlayerExperienceRecord {
    let player: PlayerNBTRecord
    let uniqueID: Int64?
    let experience: BedrockPlayerExperience
}

final class ExperienceStore {
    private let session: WorldSession
    private let playerStore: PlayerNBTStore

    init(session: WorldSession) {
        self.session = session
        self.playerStore = PlayerNBTStore(session: session)
    }

    func records() throws -> [PlayerExperienceRecord] {
        try playerStore.records().map { record in
            PlayerExperienceRecord(
                player: record,
                uniqueID: Self.uniqueID(in: record),
                experience: try Self.read(from: record.document)
            )
        }
    }

    func save(_ experience: BedrockPlayerExperience, for record: PlayerNBTRecord) throws {
        let document = try Self.document(record.document, setting: experience)
        try playerStore.save(record: record, document: document)
    }

    func saveBatch(_ values: [(record: PlayerNBTRecord, experience: BedrockPlayerExperience)]) throws {
        guard !values.isEmpty else { return }
        let puts = try values.map { pair -> (key: Data, value: Data) in
            let document = try Self.document(pair.record.document, setting: pair.experience)
            return (pair.record.key, try BedrockNBTCodec.encode(document, encoding: .littleEndian))
        }
        try session.database().applyBatch(puts: puts, deletes: [], sync: true)
    }

    static func read(from document: NBTDocument) throws -> BedrockPlayerExperience {
        guard case .compound(let tags) = document.root else {
            throw BlocktopographError.malformedData("玩家 NBT 根必须是 Compound")
        }
        return BedrockPlayerExperience(
            total: try integer(named: "XpTotal", in: tags, default: 0),
            level: try integer(named: "XpLevel", in: tags, default: 0),
            progress: try floating(named: "XpP", in: tags, default: 0)
        )
    }

    static func document(_ source: NBTDocument, setting experience: BedrockPlayerExperience) throws -> NBTDocument {
        guard case .compound(var tags) = source.root else {
            throw BlocktopographError.malformedData("玩家 NBT 根必须是 Compound")
        }
        set(name: "XpTotal", value: .int(experience.total), in: &tags)
        set(name: "XpLevel", value: .int(experience.level), in: &tags)
        set(name: "XpP", value: .float(experience.progress), in: &tags)
        return NBTDocument(rootName: source.rootName, root: .compound(tags))
    }

    static func uniqueID(in record: PlayerNBTRecord) -> Int64? {
        if let value = record.document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"]) {
            return value
        }
        for prefix in ["player_server_", "player_"] where record.keyText.hasPrefix(prefix) {
            if let value = Int64(record.keyText.dropFirst(prefix.count)) { return value }
        }
        return nil
    }

    private static func integer(named name: String, in tags: [NBTNamedTag], default defaultValue: Int32) throws -> Int32 {
        guard let value = tags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value else {
            return defaultValue
        }
        let raw: Int64
        switch value {
        case .byte(let number): raw = Int64(number)
        case .short(let number): raw = Int64(number)
        case .int(let number): raw = Int64(number)
        case .long(let number): raw = number
        case .float(let number): raw = Int64(number)
        case .double(let number): raw = Int64(number)
        default: throw BlocktopographError.malformedData("玩家 \(name) 标签必须是数字类型")
        }
        guard let result = Int32(exactly: raw) else {
            throw BlocktopographError.malformedData("玩家 \(name) 超出 Int32 范围")
        }
        return result
    }

    private static func floating(named name: String, in tags: [NBTNamedTag], default defaultValue: Float) throws -> Float {
        guard let value = tags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value else {
            return defaultValue
        }
        switch value {
        case .byte(let number): return Float(number)
        case .short(let number): return Float(number)
        case .int(let number): return Float(number)
        case .long(let number): return Float(number)
        case .float(let number): return number
        case .double(let number): return Float(number)
        default: throw BlocktopographError.malformedData("玩家 \(name) 标签必须是数字类型")
        }
    }

    private static func set(name: String, value: NBTValue, in tags: inout [NBTNamedTag]) {
        let matches = tags.indices.filter { tags[$0].name.caseInsensitiveCompare(name) == .orderedSame }
        if let first = matches.first {
            tags[first] = NBTNamedTag(name: name, value: value)
            for index in matches.dropFirst().reversed() { tags.remove(at: index) }
        } else {
            tags.append(NBTNamedTag(name: name, value: value))
        }
    }
}
