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

/// Unified access to independent SubChunkPrefix records, their legacy 0x34
/// second block layer, and pre-0.17 LegacyTerrain records. The rest of the
/// editor therefore sees a coordinate-oriented block model while persistence
/// remains faithful to each historical format.
enum BedrockChunkSubChunkAccess {
    static func records(database: MojangLevelDB, position: ChunkPosition) throws -> [BedrockStoredSubChunk] {
        var prefix = Data()
        prefix.appendLE(position.x)
        prefix.appendLE(position.z)
        let entries = try database.entries(prefix: prefix, includeValues: true, limit: 0)

        var output = [BedrockStoredSubChunk]()
        var occupied = Set<Int8>()
        var legacyTerrainRecord: (key: Data, value: Data)?
        var extraData: BedrockLegacyBlockExtraData?
        var observedNumericVersion: UInt8?

        for entry in entries {
            guard let parsed = BedrockDBKey.parse(entry.key), parsed.position == position, let raw = entry.value else { continue }
            if parsed.recordType == .subChunk, let keyY = parsed.subChunkIndex {
                let decoded = try BedrockSubChunk.decode(raw, keyYIndex: keyY)
                let logicalY = decoded.yIndex ?? keyY
                if decoded.isLegacyNumeric {
                    observedNumericVersion = observedNumericVersion ?? decoded.version
                }
                output.append(BedrockStoredSubChunk(yIndex: logicalY, subChunk: decoded, backing: .subChunk(key: entry.key)))
                occupied.insert(logicalY)
            } else if parsed.recordType == .legacyTerrain {
                legacyTerrainRecord = (entry.key, raw)
            } else if parsed.recordType == .legacyBlockExtraData {
                extraData = try BedrockLegacyBlockExtraData.decode(raw)
            }
        }

        // Attach 0x34 as virtual layer 1 only to v0/v2...v7 0x2F records.
        // LegacyTerrain is a separate pre-Anvil format and must not inherit the
        // SubChunk-specific 0x34 coordinate interpretation.
        if let extraData {
            output = output.map { record in
                guard record.subChunk.isLegacyNumeric,
                      case .subChunk = record.backing,
                      let layer1 = extraData.storage(subChunkY: record.yIndex) else { return record }
                return BedrockStoredSubChunk(
                    yIndex: record.yIndex,
                    subChunk: record.subChunk.withLegacyExtraLayer(layer1),
                    backing: record.backing
                )
            }

            // An all-air primary SubChunk can be absent while 0x34 still has
            // extra blocks. Expose such slices instead of silently hiding the
            // second layer. Materialising/editing them later creates a numeric
            // 0x2F layer-0 record using the observed legacy version (or v0).
            let fallbackVersion = observedNumericVersion ?? 0
            for y in extraData.subChunkYIndices.sorted() where !occupied.contains(y) {
                guard (0...15).contains(Int(y)), let layer1 = extraData.storage(subChunkY: y) else { continue }
                var base = try BedrockSubChunk.emptyLegacy(version: fallbackVersion, yIndex: y)
                base = base.withLegacyExtraLayer(layer1)
                let key = BedrockDBKey.subChunk(
                    x: position.x, z: position.z, dimension: position.dimension, index: y
                )
                output.append(BedrockStoredSubChunk(yIndex: y, subChunk: base, backing: .subChunk(key: key)))
                occupied.insert(y)
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
            var decoded = try BedrockSubChunk.decode(raw, keyYIndex: yIndex)
            let logicalY = decoded.yIndex ?? yIndex
            if logicalY == yIndex {
                if decoded.isLegacyNumeric,
                   let extra = try legacyExtra(database: database, position: position),
                   let layer1 = extra.storage(subChunkY: logicalY) {
                    decoded = decoded.withLegacyExtraLayer(layer1)
                }
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

        // Covers extra-only slices and the rare compatibility case where early
        // v9 migrations retain a historical key suffix while carrying absolute
        // Y inside the value.
        return try records(database: database, position: position).first(where: { $0.yIndex == yIndex })
    }

    /// Produces persistent writes for coordinate-keyed edited SubChunks.
    /// - LegacyTerrain slices are merged back into their one 0x30 value.
    /// - Numeric v0/v2...v7 storage 0 is written to 0x2F and virtual storage 1
    ///   is written to the chunk-wide 0x34 LegacyBlockExtraData value.
    /// - Modern storages are written to their normal 0x2F value.
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
        let extraKey = BedrockDBKey(position: position, recordType: .legacyBlockExtraData, subChunkIndex: nil).encoded()
        let hasLegacyTerrainBacking = existing.contains { record in
            if case .legacyTerrain = record.backing { return true }
            return false
        }

        if hasLegacyTerrainBacking {
            for y in edited.keys where !(0...7).contains(Int(y)) {
                throw MCBEEditorError.unsupported("LegacyTerrain 世界只保存 Y=0…127；不能直接创建 SubChunk Y=\(y)")
            }
        }

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

        let existingExtraRaw = try database.get(extraKey)
        var extraData = try existingExtraRaw.map(BedrockLegacyBlockExtraData.decode) ?? .empty
        var touchedExtra = false
        var puts = [(key: Data, value: Data)]()
        var touchedLegacyTerrain = false

        for y in edited.keys.sorted() {
            guard let subChunk = edited[y] else { continue }
            if let record = byY[y] {
                switch record.backing {
                case .subChunk(let key):
                    if subChunk.isLegacyNumeric {
                        guard (0...15).contains(Int(y)) else {
                            throw MCBEEditorError.unsupported("LegacyBlockExtraData 只能表示 Y=0…255")
                        }
                        let physical = subChunk.legacyPrimaryLayerOnly()
                        puts.append((key, try physical.encodePersistent()))
                        let layer1 = subChunk.storages.count > 1 ? subChunk.storages[1] : nil
                        try extraData.replaceStorage(subChunkY: y, with: layer1)
                        touchedExtra = true
                    } else {
                        puts.append((key, try subChunk.encodePersistent()))
                        // If this slice used to be numeric, its old 0x34 layer
                        // has either been migrated into the modern storages or
                        // intentionally cleared. Do not leave stale data behind.
                        if record.subChunk.isLegacyNumeric, (0...15).contains(Int(y)) {
                            try extraData.replaceStorage(subChunkY: y, with: nil)
                            touchedExtra = true
                        }
                    }
                case .legacyTerrain:
                    guard var terrain = legacyTerrain else {
                        throw MCBEEditorError.malformedData("LegacyTerrain 写回时原记录不存在")
                    }
                    try terrain.replaceSubChunk(yIndex: y, with: subChunk)
                    legacyTerrain = terrain
                    touchedLegacyTerrain = true
                }
            } else {
                let key = BedrockDBKey.subChunk(
                    x: position.x, z: position.z, dimension: position.dimension, index: y
                )
                if subChunk.isLegacyNumeric {
                    let physical = subChunk.legacyPrimaryLayerOnly()
                    puts.append((key, try physical.encodePersistent()))
                    let layer1 = subChunk.storages.count > 1 ? subChunk.storages[1] : nil
                    try extraData.replaceStorage(subChunkY: y, with: layer1)
                    touchedExtra = true
                } else {
                    puts.append((key, try subChunk.encodePersistent()))
                }
            }
        }
        if touchedLegacyTerrain, let terrain = legacyTerrain {
            puts.append((legacyKey, try terrain.encodePersistent()))
        }
        if touchedExtra {
            // persistentPuts returns puts only. Keep a valid zero-count 0x34
            // record when the last entry is removed rather than requiring an
            // out-of-band delete; whole-chunk modernisation explicitly deletes
            // the legacy key.
            puts.append((extraKey, try extraData.encodePersistent()))
        }
        return puts
    }

    private static func legacyExtra(
        database: MojangLevelDB, position: ChunkPosition
    ) throws -> BedrockLegacyBlockExtraData? {
        let key = BedrockDBKey(
            position: position, recordType: .legacyBlockExtraData, subChunkIndex: nil
        ).encoded()
        guard let raw = try database.get(key) else { return nil }
        return try BedrockLegacyBlockExtraData.decode(raw)
    }
}

private extension BedrockSubChunk {
    func withLegacyExtraLayer(_ layer1: SubChunkStorage) -> BedrockSubChunk {
        guard isLegacyNumeric else { return self }
        var updated = storages
        if updated.isEmpty {
            let air = BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
            updated = [.airFilled(with: air)]
        }
        if updated.count == 1 { updated.append(layer1) }
        else { updated[1] = layer1 }
        return BedrockSubChunk(
            version: version, yIndex: yIndex, storages: updated,
            trailingData: trailingData, rawPersistentData: rawPersistentData
        )
    }

    func legacyPrimaryLayerOnly() -> BedrockSubChunk {
        guard isLegacyNumeric else { return self }
        let primary: [SubChunkStorage] = storages.first.map { [$0] } ?? []
        return BedrockSubChunk(
            version: version, yIndex: yIndex, storages: primary,
            trailingData: trailingData, rawPersistentData: rawPersistentData
        )
    }
}
