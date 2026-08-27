import Foundation

enum BedrockSubChunkBacking: Equatable {
    case subChunk(key: Data)
    case legacyTerrain(key: Data)
}

struct BedrockStoredSubChunk {
    let yIndex: Int8
    let subChunk: BedrockSubChunk
    let backing: BedrockSubChunkBacking
}

/// Unified access to independent SubChunkPrefix records and pre-0.17
/// LegacyTerrain records. This keeps the rest of the editor coordinate-based.
enum BedrockChunkSubChunkAccess {
    static func records(database: MojangLevelDB, position: ChunkPosition) throws -> [BedrockStoredSubChunk] {
        var prefix = Data()
        prefix.appendLE(position.x)
        prefix.appendLE(position.z)
        let entries = try database.entries(prefix: prefix, includeValues: true, limit: 0)

        var output = [BedrockStoredSubChunk]()
        var occupied = Set<Int8>()
        var legacyTerrainRecord: (key: Data, value: Data)?
        for entry in entries {
            guard let parsed = BedrockDBKey.parse(entry.key), parsed.position == position, let raw = entry.value else { continue }
            if parsed.recordType == .subChunk, let keyY = parsed.subChunkIndex {
                let decoded = try BedrockSubChunk.decode(raw, keyYIndex: keyY)
                let logicalY = decoded.yIndex ?? keyY
                output.append(BedrockStoredSubChunk(yIndex: logicalY, subChunk: decoded, backing: .subChunk(key: entry.key)))
                occupied.insert(logicalY)
            } else if parsed.recordType == .legacyTerrain {
                legacyTerrainRecord = (entry.key, raw)
            }
        }

        if let record = legacyTerrainRecord {
            let terrain = try BedrockLegacyTerrain.decode(record.value)
            for rawY in 0..<8 {
                let y = Int8(rawY)
                guard !occupied.contains(y) else { continue }
                output.append(BedrockStoredSubChunk(
                    yIndex: y,
                    subChunk: try terrain.subChunk(yIndex: y),
                    backing: .legacyTerrain(key: record.key)
                ))
            }
        }
        return output.sorted { lhs, rhs in
            if lhs.yIndex != rhs.yIndex { return lhs.yIndex < rhs.yIndex }
            switch (lhs.backing, rhs.backing) {
            case (.subChunk, .legacyTerrain): return true
            case (.legacyTerrain, .subChunk): return false
            default: return false
            }
        }
    }

    static func record(database: MojangLevelDB, position: ChunkPosition, yIndex: Int8) throws -> BedrockStoredSubChunk? {
        // Fast path for the overwhelmingly common key-Y == logical-Y case.
        let key = BedrockDBKey.subChunk(
            x: position.x, z: position.z, dimension: position.dimension, index: yIndex
        )
        if let raw = try database.get(key) {
            let decoded = try BedrockSubChunk.decode(raw, keyYIndex: yIndex)
            let logicalY = decoded.yIndex ?? yIndex
            if logicalY == yIndex {
                return BedrockStoredSubChunk(yIndex: logicalY, subChunk: decoded, backing: .subChunk(key: key))
            }
        }

        if (0...7).contains(Int(yIndex)) {
            let legacyKey = BedrockDBKey(position: position, recordType: .legacyTerrain, subChunkIndex: nil).encoded()
            if let raw = try database.get(legacyKey) {
                let terrain = try BedrockLegacyTerrain.decode(raw)
                return BedrockStoredSubChunk(
                    yIndex: yIndex,
                    subChunk: try terrain.subChunk(yIndex: yIndex),
                    backing: .legacyTerrain(key: legacyKey)
                )
            }
        }

        // Rare compatibility path: early v9 migrations can retain a historical
        // key suffix while carrying the absolute Y inside the value.
        return try records(database: database, position: position).first(where: { $0.yIndex == yIndex })
    }

    /// Produces persistent writes for coordinate-keyed edited SubChunks.
    /// Multiple edits backed by one LegacyTerrain value are merged before
    /// encoding, preventing one edited Y slice from overwriting another.
    static func persistentPuts(
        database: MojangLevelDB,
        position: ChunkPosition,
        edited: [Int8: BedrockSubChunk],
        preferLegacyTerrainIfMissing: Bool = false
    ) throws -> [(key: Data, value: Data)] {
        guard !edited.isEmpty else { return [] }
        let existing = try records(database: database, position: position)
        var byY = [Int8: BedrockStoredSubChunk]()
        for record in existing where byY[record.yIndex] == nil { byY[record.yIndex] = record }

        let legacyKey = BedrockDBKey(position: position, recordType: .legacyTerrain, subChunkIndex: nil).encoded()
        let hasLegacyTerrainBacking = existing.contains { record in
            if case .legacyTerrain = record.backing { return true }
            return false
        }

        // Never silently mix a pre-Anvil 0x30 chunk with a newly-created 0x2F
        // slice. LegacyTerrain has a fixed Y range of 0...127 (virtual Y 0...7).
        if hasLegacyTerrainBacking {
            for y in edited.keys where !(0...7).contains(Int(y)) {
                throw MCBEEditorError.unsupported("LegacyTerrain 世界只保存 Y=0…127；不能直接创建 SubChunk Y=\(y)")
            }
        }

        // Materialising a previously-unloaded chunk in a PE 0.9/0.10-style
        // dimension must create another LegacyTerrain value, not a v0 0x2F
        // record that the old game does not understand.
        if existing.isEmpty && preferLegacyTerrainIfMissing {
            var terrain = BedrockLegacyTerrain.empty()
            for y in edited.keys.sorted() {
                guard (0...7).contains(Int(y)), let subChunk = edited[y] else {
                    throw MCBEEditorError.unsupported("LegacyTerrain 世界只保存 Y=0…127")
                }
                try terrain.replaceSubChunk(yIndex: y, with: subChunk)
            }
            return [(legacyKey, try terrain.encodePersistent())]
        }
        var legacyTerrain: BedrockLegacyTerrain?
        if edited.keys.contains(where: {
            if case .legacyTerrain? = byY[$0]?.backing { return true }
            return false
        }), let raw = try database.get(legacyKey) {
            legacyTerrain = try BedrockLegacyTerrain.decode(raw)
        }

        var puts = [(key: Data, value: Data)]()
        var touchedLegacyTerrain = false
        for y in edited.keys.sorted() {
            guard let subChunk = edited[y] else { continue }
            if let record = byY[y] {
                switch record.backing {
                case .subChunk(let key):
                    puts.append((key, try subChunk.encodePersistent()))
                case .legacyTerrain:
                    guard var terrain = legacyTerrain else {
                        throw MCBEEditorError.malformedData("LegacyTerrain 写回时原记录不存在")
                    }
                    try terrain.replaceSubChunk(yIndex: y, with: subChunk)
                    legacyTerrain = terrain
                    touchedLegacyTerrain = true
                }
            } else {
                puts.append((
                    BedrockDBKey.subChunk(x: position.x, z: position.z, dimension: position.dimension, index: y),
                    try subChunk.encodePersistent()
                ))
            }
        }
        if touchedLegacyTerrain, let terrain = legacyTerrain {
            puts.append((legacyKey, try terrain.encodePersistent()))
        }
        return puts
    }
}
