import Foundation

enum BedrockWorldObjectKind: Int, CaseIterable {
    case entity
    case blockEntity

    var displayName: String {
        switch self {
        case .entity: return "实体"
        case .blockEntity: return "方块实体"
        }
    }
}

enum BedrockWorldObjectSource: String {
    case modernActor = "actorprefix"
    case legacyChunkEntity = "区块 Entity(0x32)"
    case blockEntity = "区块 BlockEntity(0x31)"
}

enum BedrockWorldObjectStorage {
    case modernActor(actorKey: Data, digestKey: Data, recordIndex: Int, encoding: NBTEncoding)
    case chunkRecord(key: Data, recordIndex: Int, encoding: NBTEncoding)

    var primaryKey: Data {
        switch self {
        case .modernActor(let actorKey, _, _, _): return actorKey
        case .chunkRecord(let key, _, _): return key
        }
    }

    var recordIndex: Int {
        switch self {
        case .modernActor(_, _, let recordIndex, _): return recordIndex
        case .chunkRecord(_, let recordIndex, _): return recordIndex
        }
    }

    var encoding: NBTEncoding {
        switch self {
        case .modernActor(_, _, _, let encoding): return encoding
        case .chunkRecord(_, _, let encoding): return encoding
        }
    }
}

struct BedrockWorldObjectPosition {
    let x: Double
    let y: Double
    let z: Double

    var blockX: Int64 { Int64(floor(x)) }
    var blockY: Int32 { Int32(clamping: Int64(floor(y))) }
    var blockZ: Int64 { Int64(floor(z)) }
}

struct BedrockWorldObject {
    let stableID: String
    let kind: BedrockWorldObjectKind
    let identifier: String
    let customName: String?
    let position: BedrockWorldObjectPosition?
    let dimension: Int32
    let chunkX: Int32
    let chunkZ: Int32
    let source: BedrockWorldObjectSource
    let uniqueID: Int64?
    let itemCount: Int
    let document: NBTDocument
    let rawData: Data
    let storage: BedrockWorldObjectStorage

    var displayName: String {
        if let customName = customName?.trimmingCharacters(in: .whitespacesAndNewlines), !customName.isEmpty {
            return customName
        }
        let value = identifier.isEmpty ? kind.displayName : identifier
        return value.hasPrefix("minecraft:") ? String(value.dropFirst("minecraft:".count)) : value
    }

    var coordinateText: String {
        guard let position = position else { return "区块 (\(chunkX), \(chunkZ))；无坐标字段" }
        return "X=\(format(position.x)) Y=\(format(position.y)) Z=\(format(position.z))；区块 (\(chunkX), \(chunkZ))"
    }

    var subtitle: String {
        let items = itemCount > 0 ? "；物品 \(itemCount)" : ""
        return "\(coordinateText)；\(source.rawValue)\(items)"
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value { return String(Int64(value)) }
        return String(format: "%.2f", value)
    }
}

struct BedrockWorldObjectScanResult {
    let objects: [BedrockWorldObject]
    let diagnostics: [String]
    let actorDigestCount: Int
    let actorRecordCount: Int
    let legacyEntityRecordCount: Int
    let blockEntityRecordCount: Int

    static let empty = BedrockWorldObjectScanResult(
        objects: [],
        diagnostics: [],
        actorDigestCount: 0,
        actorRecordCount: 0,
        legacyEntityRecordCount: 0,
        blockEntityRecordCount: 0
    )
}

extension NBTValue {
    var numericDoubleValue: Double? {
        switch self {
        case .byte(let value): return Double(value)
        case .short(let value): return Double(value)
        case .int(let value): return Double(value)
        case .long(let value): return Double(value)
        case .float(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    var numericInt64Value: Int64? {
        switch self {
        case .byte(let value): return Int64(value)
        case .short(let value): return Int64(value)
        case .int(let value): return Int64(value)
        case .long(let value): return value
        case .float(let value): return Int64(value)
        case .double(let value): return Int64(value)
        default: return nil
        }
    }

    var listValues: [NBTValue]? {
        guard case .list(_, let values) = self else { return nil }
        return values
    }

    func value(namedAny names: [String]) -> NBTValue? {
        guard case .compound(let tags) = self else { return nil }
        for name in names {
            if let exact = tags.first(where: { $0.name == name }) { return exact.value }
        }
        let lowered = Set(names.map { $0.lowercased() })
        return tags.first(where: { lowered.contains($0.name.lowercased()) })?.value
    }

    func stringValue(namedAny names: [String]) -> String? {
        guard let value = value(namedAny: names) else { return nil }
        if case .string(let text) = value { return text }
        return nil
    }

    func numberValue(namedAny names: [String]) -> Double? {
        value(namedAny: names)?.numericDoubleValue
    }

    func int64Value(namedAny names: [String]) -> Int64? {
        value(namedAny: names)?.numericInt64Value
    }
}
