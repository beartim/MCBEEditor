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
    let terrainRecordType: ChunkRecordType?
    let terrainValue: Data?

    static let modernDefault = BedrockEmptyChunkProfile(
        versionRecordType: .version,
        versionValue: Data([40]),
        blockPaletteVersion: 18_153_728,
        terrainRecordType: nil,
        terrainValue: nil
    )

    static let legacyDefault = BedrockEmptyChunkProfile(
        versionRecordType: .legacyVersion,
        versionValue: Data([15]),
        blockPaletteVersion: 18_153_728,
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
            if paletteVersion == nil, key.recordType == .subChunk,
               let value = entry.value,
               let decoded = try? BedrockSubChunk.decode(value, keyYIndex: key.subChunkIndex) {
                paletteVersion = decoded.storages.flatMap(\.palette).compactMap(\.paletteVersion).first
            }
            if paletteVersion != nil && modernVersion != nil && legacyVersion != nil
                && data3D != nil && (data2D != nil || data2DLegacy != nil) { break }
        }
        let blockVersion = paletteVersion ?? currentBlockPaletteVersion
        let legacyTerrain: (ChunkRecordType?, Data?) = {
            if let data2D { return (.data2D, data2D) }
            if let data2DLegacy { return (.data2DLegacy, data2DLegacy) }
            return (nil, nil)
        }()
        if preferLegacy, let value = legacyVersion {
            return BedrockEmptyChunkProfile(
                versionRecordType: .legacyVersion, versionValue: value, blockPaletteVersion: blockVersion,
                terrainRecordType: legacyTerrain.0, terrainValue: legacyTerrain.1
            )
        }
        if let value = modernVersion {
            return BedrockEmptyChunkProfile(
                versionRecordType: .version, versionValue: value, blockPaletteVersion: blockVersion,
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
                terrainRecordType: legacyTerrain.0, terrainValue: legacyTerrain.1
            )
        }
        return BedrockEmptyChunkProfile(
            versionRecordType: .version,
            versionValue: Data([40]),
            blockPaletteVersion: blockVersion,
            terrainRecordType: data3D == nil ? nil : .data3D,
            terrainValue: data3D
        )
    }

    static func metadataRecords(
        at position: ChunkPosition,
        profile: BedrockEmptyChunkProfile = .modernDefault
    ) -> [BedrockEmptyChunkRecord] {
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
