import Foundation

/// Bedrock stores player experience as `PlayerLevel` plus
/// `PlayerLevelProgress`. There is no persistent total-XP tag. The total is
/// derived with Minecraft's level curve and is converted back to those two
/// fields whenever it is edited.
struct BedrockPlayerExperience {
    static let maximumLevel: Int32 = 24_791

    var level: Int32
    var progress: Float

    init(level: Int32, progress: Float) {
        self.level = min(Self.maximumLevel, max(0, level))
        self.progress = min(1, max(0, progress.isFinite ? progress : 0))
    }

    /// The integer total XP represented by the stored level and progress.
    /// Existing worlds can contain small floating-point drift, so the points
    /// inside the current bar are recovered by rounding to the nearest point.
    var total: Int64 {
        let base = Self.totalRequired(toReach: level)
        let needed = Int64(Self.pointsRequiredForNextLevel(level))
        let fraction = min(1, max(0, Double(progress)))
        let inside = Int64((fraction * Double(needed)).rounded(.toNearestOrAwayFromZero))
        return min(Self.maximumTotal, base + min(needed, max(0, inside)))
    }

    static var maximumTotal: Int64 {
        totalRequired(toReach: maximumLevel) + Int64(pointsRequiredForNextLevel(maximumLevel))
    }

    /// Converts a total XP amount into the canonical Bedrock level/progress
    /// pair. Binary search avoids precision loss at high levels.
    static func fromTotal(_ total: Int64) throws -> BedrockPlayerExperience {
        guard total >= 0, total <= maximumTotal else {
            throw MCBEEditorError.malformedData("经验总数必须是 0～\(maximumTotal) 的整数")
        }

        var low: Int32 = 0
        var high = maximumLevel
        while low < high {
            let middle = low + (high - low + 1) / 2
            if totalRequired(toReach: middle) <= total {
                low = middle
            } else {
                high = middle - 1
            }
        }

        let base = totalRequired(toReach: low)
        let needed = pointsRequiredForNextLevel(low)
        let remaining = total - base
        let progress = needed > 0 ? Float(Double(remaining) / Double(needed)) : 0
        return BedrockPlayerExperience(level: low, progress: progress)
    }

    /// XP required to move from `level` to `level + 1`.
    static func pointsRequiredForNextLevel(_ level: Int32) -> Int32 {
        let value = max(0, level)
        switch value {
        case 0...15:
            return 2 * value + 7
        case 16...30:
            return 5 * value - 38
        default:
            return 9 * value - 158
        }
    }

    /// Total XP required to stand exactly at the beginning of `level`.
    static func totalRequired(toReach level: Int32) -> Int64 {
        let value = Int64(min(maximumLevel, max(0, level)))
        switch value {
        case 0...16:
            return value * value + 6 * value
        case 17...31:
            return (5 * value * value - 81 * value + 720) / 2
        default:
            return (9 * value * value - 325 * value + 4_440) / 2
        }
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
            throw MCBEEditorError.malformedData("玩家 NBT 根必须是 Compound")
        }
        return BedrockPlayerExperience(
            level: try integer(named: "PlayerLevel", in: tags, default: 0),
            progress: try floating(named: "PlayerLevelProgress", in: tags, default: 0)
        )
    }

    static func document(_ source: NBTDocument, setting experience: BedrockPlayerExperience) throws -> NBTDocument {
        guard case .compound(var tags) = source.root else {
            throw MCBEEditorError.malformedData("玩家 NBT 根必须是 Compound")
        }

        // Remove fields written by older MCBEEditor builds. Bedrock does
        // not use them for player XP and leaving them behind is misleading.
        remove(names: ["XpTotal", "XpLevel", "XpP"], from: &tags)
        set(name: "PlayerLevel", value: .int(experience.level), in: &tags)
        set(name: "PlayerLevelProgress", value: .float(experience.progress), in: &tags)
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
        default: throw MCBEEditorError.malformedData("玩家 \(name) 标签必须是数字类型")
        }
        guard let result = Int32(exactly: raw) else {
            throw MCBEEditorError.malformedData("玩家 \(name) 超出 Int32 范围")
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
        default: throw MCBEEditorError.malformedData("玩家 \(name) 标签必须是数字类型")
        }
    }

    private static func remove(names: Set<String>, from tags: inout [NBTNamedTag]) {
        let lowered = Set(names.map { $0.lowercased() })
        tags.removeAll { lowered.contains($0.name.lowercased()) }
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
