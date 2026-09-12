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
    var paletteFormat: BedrockPaletteFormat? = nil

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

    /// An ungenerated slice has no palette of its own. Its editing template
    /// must inherit the actual block format, not the app's modern default.
    /// LegacyVersion metadata alone does not imply numeric-ID blocks: v1/v8
    /// palettes use it too (including the older End test world).
    static func airForMissingSubChunk(
        database: MojangLevelDB,
        at position: ChunkPosition,
        records: [BedrockStoredSubChunk],
        fallbackProfile: BedrockEmptyChunkProfile? = nil
    ) throws -> BedrockBlockState {
        let known = records.filter { !$0.subChunk.isRawPreservedUnknownVersion }
        var counts = [UInt8: Int]()
        for record in known { counts[record.subChunk.version, default: 0] += 1 }
        let version = counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }?.key
        if let version, [UInt8(0), 2, 3, 4, 5, 6, 7].contains(version) {
            return BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
        }
        if let format = BedrockPaletteFormat.detect(known.flatMap { $0.subChunk.storages }
            .filter { $0.persistentKind == .normal }.flatMap(\.palette)) { return format.air }
        let fallback = try fallbackProfile ?? profile(database: database, dimension: position.dimension)
        if version == nil, [UInt8(0), 2, 3, 4, 5, 6, 7].contains(fallback.subChunkVersion) {
            return BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
        }
        return (fallback.paletteFormat ?? BedrockPaletteFormat(usesLegacyVal: false, version: fallback.blockPaletteVersion)).air
    }

    static func profile(
        database: MojangLevelDB,
        dimension: Int32?,
        preferLegacy: Bool = false,
        preferredPaletteVersion: Int32? = nil
    ) throws -> BedrockEmptyChunkProfile {
        var legacyVersion: Data?
        var modernVersion: Data?
        var paletteVersions = [Int32]()
        var paletteFormat: BedrockPaletteFormat?
        var data3D: Data?
        var data2D: Data?
        var data2DLegacy: Data?
        var subChunkVersionCounts = [UInt8: Int]()
        var legacyTerrainCount = 0
        let entries = try database.entries(includeValues: true, limit: 0)
        for entry in entries {
            guard let key = BedrockDBKey.parse(entry.key), (dimension == nil || key.position.dimension == dimension) else { continue }
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
                if !decoded.isRawPreservedUnknownVersion {
                    subChunkVersionCounts[decoded.version, default: 0] += 1
                }
                if let observed = BedrockPaletteFormat.detect(decoded.storages
                    .filter { $0.persistentKind == .normal }.flatMap(\.palette)),
                   paletteFormat == nil || (paletteFormat!.usesLegacyVal && !observed.usesLegacyVal)
                    || (paletteFormat!.usesLegacyVal == observed.usesLegacyVal
                        && (observed.version ?? 0) > (paletteFormat!.version ?? 0)) {
                    paletteFormat = observed
                }
                paletteVersions.append(contentsOf: decoded.storages
                    .filter { $0.persistentKind == .normal }
                    .flatMap(\.palette)
                    .compactMap(\.paletteVersion))
            }
        }
        if dimension != nil && legacyVersion == nil && modernVersion == nil
            && legacyTerrainCount == 0 && subChunkVersionCounts.isEmpty {
            return try profile(database: database, dimension: nil, preferLegacy: preferLegacy,
                               preferredPaletteVersion: preferredPaletteVersion)
        }
        func withPaletteFormat(_ value: BedrockEmptyChunkProfile) -> BedrockEmptyChunkProfile {
            var result = value
            result.paletteFormat = paletteFormat
            return result
        }
        // Same-dimension persisted palettes take precedence; an optional
        // world-wide persisted palette sample is the next fallback. The
        // constant is only a final safety net for truly empty worlds.
        let blockVersion = paletteVersions.max() ?? preferredPaletteVersion ?? currentBlockPaletteVersion
        let observedSubChunkVersion = subChunkVersionCounts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }?.key
        // Early LevelDB worlds such as PE 0.9/0.10 store one 83,200-byte
        // LegacyTerrain record per chunk and may have no Version/SubChunk records
        // at all. Do not infer a modern empty-chunk profile just because those
        // later metadata families are absent.
        let subChunkRecordCount = subChunkVersionCounts.values.reduce(0, +)
        // PE 0.9/0.10 worlds use LegacyTerrain without modern Version/SubChunk records.
        // Detect the persisted Bedrock format directly; do not repair editor-created hybrids.
        let usesLegacyTerrain = legacyTerrainCount > 0
            && modernVersion == nil
            && subChunkRecordCount == 0
        if usesLegacyTerrain {
            return withPaletteFormat(BedrockEmptyChunkProfile(
                versionRecordType: .legacyVersion,
                versionValue: legacyVersion ?? Data([0]),
                blockPaletteVersion: blockVersion,
                subChunkVersion: 0,
                usesLegacyTerrain: true,
                terrainRecordType: nil,
                terrainValue: nil
            ))
        }
        let legacyTerrain: (ChunkRecordType?, Data?) = {
            if let data2D { return (.data2D, data2D) }
            if let data2DLegacy { return (.data2DLegacy, data2DLegacy) }
            return (nil, nil)
        }()
        if preferLegacy, let value = legacyVersion {
            return withPaletteFormat(BedrockEmptyChunkProfile(
                versionRecordType: .legacyVersion, versionValue: value, blockPaletteVersion: blockVersion,
                subChunkVersion: observedSubChunkVersion ?? 7,
                usesLegacyTerrain: false,
                terrainRecordType: legacyTerrain.0, terrainValue: legacyTerrain.1
            ))
        }
        if let value = modernVersion {
            return withPaletteFormat(BedrockEmptyChunkProfile(
                versionRecordType: .version, versionValue: value, blockPaletteVersion: blockVersion,
                subChunkVersion: observedSubChunkVersion ?? 9,
                usesLegacyTerrain: false,
                terrainRecordType: data3D == nil ? legacyTerrain.0 : .data3D, terrainValue: data3D ?? legacyTerrain.1
            ))
        }
        // A legacy-only dimension must stay legacy even when the caller has no
        // block-specific preference. Writing a modern Version record beside a
        // v7 numeric SubChunk (or the reverse) creates a chunk this editor can
        // decode but Minecraft ignores.
        if let value = legacyVersion, modernVersion == nil {
            return withPaletteFormat(BedrockEmptyChunkProfile(
                versionRecordType: .legacyVersion, versionValue: value, blockPaletteVersion: blockVersion,
                subChunkVersion: observedSubChunkVersion ?? 7,
                usesLegacyTerrain: false,
                terrainRecordType: legacyTerrain.0, terrainValue: legacyTerrain.1
            ))
        }
        return withPaletteFormat(BedrockEmptyChunkProfile(
            versionRecordType: .version,
            versionValue: Data([40]),
            blockPaletteVersion: blockVersion,
            subChunkVersion: observedSubChunkVersion ?? 9,
            usesLegacyTerrain: false,
            terrainRecordType: data3D == nil ? nil : .data3D,
            terrainValue: data3D
        ))
    }

    /// Highest block-state version actually persisted in any known v1/v8/v9
    /// SubChunk in this world. This is safer than packing the product version
    /// from level.dat: newer Bedrock releases do not guarantee that the two
    /// version number spaces are identical. Unknown future SubChunks and
    /// BPB=127 sentinels intentionally do not contribute synthetic versions.
    static func persistedBlockPaletteVersion(database: MojangLevelDB) throws -> Int32? {
        var best: Int32?
        let entries = try database.entries(includeValues: true, limit: 0)
        for entry in entries {
            guard let parsed = BedrockDBKey.parse(entry.key), parsed.recordType == .subChunk,
                  let raw = entry.value,
                  let decoded = try? BedrockSubChunk.decode(raw, keyYIndex: parsed.subChunkIndex),
                  !decoded.isRawPreservedUnknownVersion else { continue }
            for storage in decoded.storages where storage.persistentKind == .normal {
                for version in storage.palette.compactMap(\.paletteVersion) {
                    if best == nil || version > best! { best = version }
                }
            }
        }
        return best
    }

    static func preferredSubChunkVersion(
        database: MojangLevelDB,
        at position: ChunkPosition,
        fallback: UInt8
    ) throws -> UInt8 {
        var counts = [UInt8: Int]()
        let entries = try database.entries(prefix: coordinatePrefix(position), includeValues: true, limit: 0)
        for entry in entries {
            guard let parsed = BedrockDBKey.parse(entry.key), parsed.position == position else { continue }
            if parsed.recordType == .legacyTerrain { return 0 }
            guard parsed.recordType == .subChunk,
                  let raw = entry.value,
                  let decoded = try? BedrockSubChunk.decode(raw, keyYIndex: parsed.subChunkIndex),
                  !decoded.isRawPreservedUnknownVersion else { continue }
            counts[decoded.version, default: 0] += 1
        }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }?.key ?? fallback
    }

    private static func coordinatePrefix(_ position: ChunkPosition) -> Data {
        var prefix = Data()
        prefix.appendLE(position.x)
        prefix.appendLE(position.z)
        return prefix
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

    static func missingMetadataRecords(database: MojangLevelDB, at position: ChunkPosition, using metadataProfile: BedrockEmptyChunkProfile? = nil) throws -> [(key: Data, value: Data)] {
        func value(_ type: ChunkRecordType) throws -> Data? {
            try database.get(BedrockDBKey(position: position, recordType: type, subChunkIndex: nil).encoded())
        }
        if try value(.legacyTerrain) != nil { return [] }
        let hasVersion = try value(.version) != nil || value(.legacyVersion) != nil
        let hasFinalized = try value(.finalizedState) != nil
        let hasBiome = try value(.data3D) != nil || value(.data2D) != nil || value(.data2DLegacy) != nil
        if hasVersion && hasFinalized && hasBiome { return [] }
        let detected = try metadataProfile ?? profile(database: database, dimension: position.dimension)
        if detected.usesLegacyTerrain { return [] }
        return metadataRecords(at: position, profile: detected).filter { record in
            switch record.recordType {
            case .version, .legacyVersion: return !hasVersion
            case .finalizedState: return !hasFinalized
            default: return !hasBiome
            }
        }.map { (key: $0.key, value: $0.value) }
    }
}
