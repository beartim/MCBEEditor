import Foundation

struct BedrockEmptyChunkRecord: Equatable {
    let key: Data
    let value: Data
    let recordType: ChunkRecordType
}

struct BedrockEmptyChunkProfile: Equatable {
    let versionRecordType: ChunkRecordType
    let versionValue: Data
    let blockPaletteVersion: Int32
    /// Preferred persistent SubChunk encoding used by this dimension/world.
    /// LegacyVersion/Data2D worlds may still use paletted v8 SubChunks.
    let subChunkVersion: UInt8
    /// True for pre-Anvil LevelDB worlds whose terrain is stored as one
    /// 0x30 LegacyTerrain value per 16×128×16 chunk instead of 0x2F records.
    let usesLegacyTerrain: Bool
    let terrainRecordType: ChunkRecordType?
    let terrainValue: Data?

    static let modernDefault = BedrockEmptyChunkProfile(
        versionRecordType: .version,
        versionValue: Data([40]),
        blockPaletteVersion: 18_153_728,
        subChunkVersion: 9,
        usesLegacyTerrain: false,
        terrainRecordType: nil,
        terrainValue: nil
    )

    static let legacyDefault = BedrockEmptyChunkProfile(
        versionRecordType: .legacyVersion,
        versionValue: Data([15]),
        blockPaletteVersion: 18_153_728,
        subChunkVersion: 7,
        usesLegacyTerrain: false,
        terrainRecordType: nil,
        terrainValue: nil
    )
}

/// Metadata for a minimal generated air chunk. Modern SubChunk v9 data must be
/// paired with the current Version (0x2c) family rather than the pre-extended-
/// height LegacyVersion (0x76) record. When possible we copy the exact version
/// byte and block-state version already used by the world.
enum BedrockEmptyChunk {
    static let currentBlockPaletteVersion: Int32 = 18_153_728 // 1.21.1.0

    static func profile(
        database: MojangLevelDB,
        dimension: Int32,
        preferLegacy: Bool = false
    ) throws -> BedrockEmptyChunkProfile {
        var legacyVersion: Data?
        var modernVersion: Data?
        var paletteVersion: Int32?
        var data3D: Data?
        var data2D: Data?
        var data2DLegacy: Data?
        var subChunkVersionCounts = [UInt8: Int]()
        var legacyTerrainCount = 0
        let entries = try database.entries(includeValues: true, limit: 0)
        for entry in entries {
            guard let key = BedrockDBKey.parse(entry.key), key.position.dimension == dimension else { continue }
            if let value = entry.value, value.count == 1 {
                if key.recordType == .version, modernVersion == nil { modernVersion = value }
                if key.recordType == .legacyVersion, legacyVersion == nil { legacyVersion = value }
            }
            if let value = entry.value {
                if key.recordType == .data3D, data3D == nil { data3D = value }
                if key.recordType == .data2D, data2D == nil { data2D = value }
                if key.recordType == .data2DLegacy, data2DLegacy == nil { data2DLegacy = value }
            }
            if key.recordType == .legacyTerrain {
                legacyTerrainCount += 1
            }
            if key.recordType == .subChunk,
               let value = entry.value,
               let decoded = try? BedrockSubChunk.decode(value, keyYIndex: key.subChunkIndex) {
                subChunkVersionCounts[decoded.version, default: 0] += 1
                if paletteVersion == nil {
                    paletteVersion = decoded.storages.flatMap(\.palette).compactMap(\.paletteVersion).first
                }
            }
            if paletteVersion != nil && modernVersion != nil && legacyVersion != nil
                && data3D != nil && (data2D != nil || data2DLegacy != nil) { break }
        }
        let blockVersion = paletteVersion ?? currentBlockPaletteVersion
        let observedSubChunkVersion = subChunkVersionCounts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }?.key
        // Early LevelDB worlds such as PE 0.9/0.10 store one 83,200-byte
        // LegacyTerrain record per chunk and may have no Version/SubChunk records
        // at all. Do not infer a modern empty-chunk profile just because those
        // later metadata families are absent.
        let subChunkRecordCount = subChunkVersionCounts.values.reduce(0, +)
        // Treat a dimension as pre-Anvil when LegacyTerrain is the dominant
        // terrain family and there is no modern Version record. Weight each
        // 0x30 record as eight virtual Y slices so a stray 0x2F written by an
        // older editor build does not permanently switch a 0.10.x world to the
        // wrong missing-chunk format.
        let usesLegacyTerrain = legacyTerrainCount > 0
            && modernVersion == nil
            && legacyTerrainCount * 8 >= subChunkRecordCount
        if usesLegacyTerrain {
            return BedrockEmptyChunkProfile(
                versionRecordType: .legacyVersion,
                versionValue: legacyVersion ?? Data([0]),
                blockPaletteVersion: blockVersion,
                subChunkVersion: 0,
                usesLegacyTerrain: true,
                terrainRecordType: nil,
                terrainValue: nil
            )
        }
        let legacyTerrain: (ChunkRecordType?, Data?) = {
            if let data2D { return (.data2D, data2D) }
            if let data2DLegacy { return (.data2DLegacy, data2DLegacy) }
            return (nil, nil)
        }()
        if preferLegacy, let value = legacyVersion {
            return BedrockEmptyChunkProfile(
                versionRecordType: .legacyVersion, versionValue: value, blockPaletteVersion: blockVersion,
                subChunkVersion: observedSubChunkVersion ?? 7,
                usesLegacyTerrain: false,
                terrainRecordType: legacyTerrain.0, terrainValue: legacyTerrain.1
            )
        }
        if let value = modernVersion {
            return BedrockEmptyChunkProfile(
                versionRecordType: .version, versionValue: value, blockPaletteVersion: blockVersion,
                subChunkVersion: observedSubChunkVersion ?? 9,
                usesLegacyTerrain: false,
                terrainRecordType: data3D == nil ? nil : .data3D, terrainValue: data3D
            )
        }
        // A legacy-only dimension must stay legacy even when the caller has no
        // block-specific preference. Writing a modern Version record beside a
        // v7 numeric SubChunk (or the reverse) creates a chunk this editor can
        // decode but Minecraft ignores.
        if let value = legacyVersion, modernVersion == nil {
            return BedrockEmptyChunkProfile(
                versionRecordType: .legacyVersion, versionValue: value, blockPaletteVersion: blockVersion,
                subChunkVersion: observedSubChunkVersion ?? 7,
                usesLegacyTerrain: false,
                terrainRecordType: legacyTerrain.0, terrainValue: legacyTerrain.1
            )
        }
        return BedrockEmptyChunkProfile(
            versionRecordType: .version,
            versionValue: Data([40]),
            blockPaletteVersion: blockVersion,
            subChunkVersion: observedSubChunkVersion ?? 9,
            usesLegacyTerrain: false,
            terrainRecordType: data3D == nil ? nil : .data3D,
            terrainValue: data3D
        )
    }

    static func preferredSubChunkVersion(
        database: MojangLevelDB,
        at position: ChunkPosition,
        fallback: UInt8
    ) throws -> UInt8 {
        var counts = [UInt8: Int]()
        let entries = try database.entries(includeValues: true, limit: 0)
        for entry in entries {
            guard let parsed = BedrockDBKey.parse(entry.key), parsed.position == position else { continue }
            if parsed.recordType == .legacyTerrain { return 0 }
            guard parsed.recordType == .subChunk,
                  let raw = entry.value,
                  let decoded = try? BedrockSubChunk.decode(raw, keyYIndex: parsed.subChunkIndex) else { continue }
            counts[decoded.version, default: 0] += 1
        }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }?.key ?? fallback
    }

    static func hasChunkMetadata(database: MojangLevelDB, at position: ChunkPosition) throws -> Bool {
        let metadataTypes: [ChunkRecordType] = [.version, .legacyVersion, .finalizedState, .data3D, .data2D, .data2DLegacy, .legacyTerrain]
        return try database.entries(includeValues: false, limit: 0).contains { entry in
            guard let parsed = BedrockDBKey.parse(entry.key) else { return false }
            return parsed.position == position && metadataTypes.contains(parsed.recordType)
        }
    }

    static func metadataRecords(
        at position: ChunkPosition,
        profile: BedrockEmptyChunkProfile = .modernDefault
    ) -> [BedrockEmptyChunkRecord] {
        if profile.usesLegacyTerrain {
            return [BedrockEmptyChunkRecord(
                key: BedrockDBKey(position: position, recordType: .legacyTerrain, subChunkIndex: nil).encoded(),
                value: BedrockLegacyTerrain.emptyPersistentData,
                recordType: .legacyTerrain
            )]
        }
        let version = BedrockEmptyChunkRecord(
            key: BedrockDBKey(position: position, recordType: profile.versionRecordType, subChunkIndex: nil).encoded(),
            value: profile.versionValue,
            recordType: profile.versionRecordType
        )

        var finalizedValue = Data()
        finalizedValue.appendLE(Int32(2))
        let finalized = BedrockEmptyChunkRecord(
            key: BedrockDBKey(position: position, recordType: .finalizedState, subChunkIndex: nil).encoded(),
            value: finalizedValue,
            recordType: .finalizedState
        )
        var records = [version, finalized]
        if let terrainRecordType = profile.terrainRecordType, let terrainValue = profile.terrainValue {
            records.append(BedrockEmptyChunkRecord(
                key: BedrockDBKey(position: position, recordType: terrainRecordType, subChunkIndex: nil).encoded(),
                value: terrainValue,
                recordType: terrainRecordType
            ))
        }
        return records
    }
}
