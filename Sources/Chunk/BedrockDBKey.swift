import Foundation

enum BedrockDimension: Int32, CaseIterable {
    case overworld = 0
    case nether = 1
    case end = 2

    var displayName: String {
        switch self {
        case .overworld: return "主世界"
        case .nether: return "下界"
        case .end: return "末地"
        }
    }
}

enum ChunkRecordType: UInt8, CaseIterable {
    case data3D = 0x2b
    case version = 0x2c
    case data2D = 0x2d
    case data2DLegacy = 0x2e
    case subChunk = 0x2f
    case legacyTerrain = 0x30
    case blockEntity = 0x31
    case entity = 0x32
    case pendingTicks = 0x33
    case legacyBlockExtraData = 0x34
    case biomeState = 0x35
    case finalizedState = 0x36
    case conversionData = 0x37
    case borderBlocks = 0x38
    case hardcodedSpawners = 0x39
    case randomTicks = 0x3a
    case checksums = 0x3b
    case generationSeed = 0x3c
    case generatedPreCavesAndCliffsBlending = 0x3d
    case blendingBiomeHeight = 0x3e
    case metadataHash = 0x3f
    case blendingData = 0x40
    case actorDigestVersion = 0x41
    case legacyVersion = 0x76

    var displayName: String {
        switch self {
        case .data3D: return "Data3D"
        case .version: return "Version"
        case .data2D: return "Data2D"
        case .data2DLegacy: return "Data2DLegacy"
        case .subChunk: return "SubChunk"
        case .legacyTerrain: return "LegacyTerrain"
        case .blockEntity: return "BlockEntity"
        case .entity: return "Entity"
        case .pendingTicks: return "PendingTicks"
        case .legacyBlockExtraData: return "LegacyBlockExtraData"
        case .biomeState: return "BiomeState"
        case .finalizedState: return "FinalizedState"
        case .conversionData: return "ConversionData"
        case .borderBlocks: return "BorderBlocks"
        case .hardcodedSpawners: return "HardcodedSpawners"
        case .randomTicks: return "RandomTicks"
        case .checksums: return "Checksums"
        case .generationSeed: return "GenerationSeed"
        case .generatedPreCavesAndCliffsBlending: return "GeneratedPreCavesAndCliffsBlending"
        case .blendingBiomeHeight: return "BlendingBiomeHeight"
        case .metadataHash: return "MetaDataHash"
        case .blendingData: return "BlendingData"
        case .actorDigestVersion: return "ActorDigestVersion"
        case .legacyVersion: return "LegacyVersion"
        }
    }
}

struct ChunkPosition: Hashable {
    let x: Int32
    let z: Int32
    let dimension: Int32
}

struct BedrockDBKey: Hashable {
    let position: ChunkPosition
    let recordType: ChunkRecordType
    let subChunkIndex: Int8?

    static func parse(_ data: Data) -> BedrockDBKey? {
        guard data.count >= 9,
              let x = try? data.littleEndianInt32(at: 0),
              let z = try? data.littleEndianInt32(at: 4) else { return nil }

        if let type = ChunkRecordType(rawValue: data[8]) {
            let subIndex: Int8? = type == .subChunk && data.count >= 10 ? Int8(bitPattern: data[9]) : nil
            return BedrockDBKey(position: ChunkPosition(x: x, z: z, dimension: 0), recordType: type, subChunkIndex: subIndex)
        }
        guard data.count >= 13,
              let dimension = try? data.littleEndianInt32(at: 8),
              let type = ChunkRecordType(rawValue: data[12]) else { return nil }
        let subIndex: Int8? = type == .subChunk && data.count >= 14 ? Int8(bitPattern: data[13]) : nil
        return BedrockDBKey(position: ChunkPosition(x: x, z: z, dimension: dimension), recordType: type, subChunkIndex: subIndex)
    }

    func encoded() -> Data {
        var data = Data()
        data.appendLE(position.x)
        data.appendLE(position.z)
        if position.dimension != 0 { data.appendLE(position.dimension) }
        data.append(recordType.rawValue)
        if recordType == .subChunk, let subChunkIndex = subChunkIndex {
            data.append(UInt8(bitPattern: subChunkIndex))
        }
        return data
    }

    static func subChunk(x: Int32, z: Int32, dimension: Int32, index: Int8) -> Data {
        BedrockDBKey(
            position: ChunkPosition(x: x, z: z, dimension: dimension),
            recordType: .subChunk,
            subChunkIndex: index
        ).encoded()
    }
}


extension BedrockDBKey: CustomStringConvertible {
    var description: String {
        let dimension = BedrockDimension(rawValue: position.dimension)?.displayName ?? "维度 \(position.dimension)"
        if let subChunkIndex = subChunkIndex {
            return "\(dimension) (\(position.x), \(position.z)) \(recordType.displayName) Y=\(subChunkIndex)"
        }
        return "\(dimension) (\(position.x), \(position.z)) \(recordType.displayName)"
    }
}

/// Raw chunk-key matching used by destructive chunk operations.
///
/// Bedrock has both a legacy overworld prefix (`x,z`) and a current
/// dimension-aware prefix (`x,z,dimension`). A one-byte LevelChunkTag follows
/// the prefix; some records append one or two additional bytes (for example a
/// SubChunk Y index). Matching by prefix and bounded suffix length mirrors the
/// Android Blocktopograph `removeFullChunk` implementation and deliberately
/// does not depend on a whitelist of currently known tags.
enum BedrockRawChunkKey {
    static func prefixes(for position: ChunkPosition) -> [Data] {
        var modern = Data()
        modern.appendLE(position.x)
        modern.appendLE(position.z)
        modern.appendLE(position.dimension)

        guard position.dimension == 0 else { return [modern] }
        var legacy = Data()
        legacy.appendLE(position.x)
        legacy.appendLE(position.z)
        return [modern, legacy]
    }

    static func matches(_ key: Data, position: ChunkPosition) -> Bool {
        prefixes(for: position).contains { prefix in
            key.count > prefix.count &&
            key.count <= prefix.count + 3 &&
            key.starts(with: prefix)
        }
    }
}
