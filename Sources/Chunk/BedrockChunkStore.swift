import Foundation

struct BedrockChunkSummary: Hashable {
    let position: ChunkPosition
    let recordCount: Int
    let subChunkCount: Int
    let minimumSubChunkY: Int8?
    let maximumSubChunkY: Int8?
    let hasBlockEntities: Bool
    let hasLegacyEntities: Bool
    let hasActorDigest: Bool
    let biomeRecordType: ChunkRecordType?
    let hasHardcodedSpawners: Bool

    var coordinateText: String { "(\(position.x), \(position.z))" }

    var detailText: String {
        var parts = ["记录 \(recordCount)", "SubChunk \(subChunkCount)"]
        if let minimumSubChunkY = minimumSubChunkY, let maximumSubChunkY = maximumSubChunkY {
            parts.append("Y \(minimumSubChunkY)…\(maximumSubChunkY)")
        }
        if let biomeRecordType = biomeRecordType { parts.append("生物群系 \(biomeRecordType.displayName)") }
        if hasHardcodedSpawners { parts.append("HardcodedSpawners") }
        if hasBlockEntities { parts.append("方块实体") }
        if hasLegacyEntities { parts.append("旧实体") }
        if hasActorDigest { parts.append("Actor 索引") }
        return parts.joined(separator: " · ")
    }
}

struct BedrockChunkCopyResult {
    let copiedRecordCount: Int
    let removedDestinationRecordCount: Int
    let skippedRecordTypes: [ChunkRecordType]
}

struct BedrockChunkClearResult {
    let deletedChunkRecordCount: Int
    let deletedDigestCount: Int
    let deletedActorCount: Int
    let createdMetadataRecordCount: Int
    let versionRecordType: ChunkRecordType
}

struct BedrockChunkRegenerateResult {
    let deletedChunkRecordCount: Int
    let deletedDigestCount: Int
    let deletedActorCount: Int
}

struct BedrockChunkReplaceResult {
    let matchedBlockCount: Int
    let modifiedSubChunkCount: Int
    let skippedSubChunkCount: Int
}

struct BedrockChunkBulkLayerResult {
    let affectedBlockCount: Int
    let modifiedSubChunkCount: Int
    let skippedSubChunkCount: Int
}


final class BedrockChunkStore {
    let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func listChunks() throws -> [BedrockChunkSummary] {
        struct Accumulator {
            var records = 0
            var subChunkYs = [Int8]()
            var hasBlockEntities = false
            var hasLegacyEntities = false
            var hasActorDigest = false
            var biomeRecordType: ChunkRecordType?
            var hasHardcodedSpawners = false
        }

        let entries = try session.database().entries(prefix: nil, includeValues: false, limit: 0)
        var chunks = [ChunkPosition: Accumulator]()
        for entry in entries {
            if let key = BedrockDBKey.parse(entry.key) {
                var value = chunks[key.position] ?? Accumulator()
                value.records += 1
                if key.recordType == .subChunk, let y = key.subChunkIndex { value.subChunkYs.append(y) }
                if key.recordType == .blockEntity { value.hasBlockEntities = true }
                if key.recordType == .entity { value.hasLegacyEntities = true }
                if [.data3D, .data2D, .data2DLegacy].contains(key.recordType) {
                    if value.biomeRecordType == nil || key.recordType == .data3D {
                        value.biomeRecordType = key.recordType
                    }
                }
                if key.recordType == .hardcodedSpawners { value.hasHardcodedSpawners = true }
                chunks[key.position] = value
            } else if let position = Self.parseActorDigestKey(entry.key) {
                var value = chunks[position] ?? Accumulator()
                value.records += 1
                value.hasActorDigest = true
                chunks[position] = value
            }
        }
        return chunks.map { position, accumulator in
            BedrockChunkSummary(
                position: position,
                recordCount: accumulator.records,
                subChunkCount: accumulator.subChunkYs.count,
                minimumSubChunkY: accumulator.subChunkYs.min(),
                maximumSubChunkY: accumulator.subChunkYs.max(),
                hasBlockEntities: accumulator.hasBlockEntities,
                hasLegacyEntities: accumulator.hasLegacyEntities,
                hasActorDigest: accumulator.hasActorDigest,
                biomeRecordType: accumulator.biomeRecordType,
                hasHardcodedSpawners: accumulator.hasHardcodedSpawners
            )
        }.sorted {
            if $0.position.dimension != $1.position.dimension { return $0.position.dimension < $1.position.dimension }
            if $0.position.z != $1.position.z { return $0.position.z < $1.position.z }
            return $0.position.x < $1.position.x
        }
    }

    func summary(at position: ChunkPosition) throws -> BedrockChunkSummary {
        let records = try rawChunkRecords(at: position, includeValues: false)
        var subChunkYs = [Int8]()
        var hasBlockEntities = false
        var hasLegacyEntities = false
        var biomeRecordType: ChunkRecordType?
        var hasHardcodedSpawners = false

        for record in records {
            guard let parsed = BedrockDBKey.parse(record.key), parsed.position == position else { continue }
            if parsed.recordType == .subChunk, let y = parsed.subChunkIndex { subChunkYs.append(y) }
            if parsed.recordType == .blockEntity { hasBlockEntities = true }
            if parsed.recordType == .entity { hasLegacyEntities = true }
            if [.data3D, .data2D, .data2DLegacy].contains(parsed.recordType) {
                if biomeRecordType == nil || parsed.recordType == .data3D { biomeRecordType = parsed.recordType }
            }
            if parsed.recordType == .hardcodedSpawners { hasHardcodedSpawners = true }
        }

        let database = try session.database()
        var digestCount = 0
        for key in Self.actorDigestKeys(for: position) where try database.get(key) != nil {
            digestCount += 1
        }
        return BedrockChunkSummary(
            position: position,
            recordCount: records.count + digestCount,
            subChunkCount: subChunkYs.count,
            minimumSubChunkY: subChunkYs.min(),
            maximumSubChunkY: subChunkYs.max(),
            hasBlockEntities: hasBlockEntities,
            hasLegacyEntities: hasLegacyEntities,
            hasActorDigest: digestCount > 0,
            biomeRecordType: biomeRecordType,
            hasHardcodedSpawners: hasHardcodedSpawners
        )
    }

    func copyChunk(from source: ChunkPosition, to destination: ChunkPosition) throws -> BedrockChunkCopyResult {
        guard source != destination else {
            throw MCBEEditorError.malformedData("源区块与目标区块不能相同")
        }
        let database = try session.database()
        let sourceRecords = try standardRecords(at: source, includeValues: true)
        let copyableTypes = Self.copyableRecordTypes
        let copyable = sourceRecords.filter { copyableTypes.contains($0.parsed.recordType) }
        guard !copyable.isEmpty else {
            throw MCBEEditorError.unsupported("源区块没有可复制的现代区块记录")
        }

        let destinationRecords = try standardRecords(at: destination, includeValues: true)
            .filter { copyableTypes.contains($0.parsed.recordType) }

        let dx = Int64(destination.x - source.x) * 16
        let dz = Int64(destination.z - source.z) * 16
        var puts = [(key: Data, value: Data)]()
        for record in copyable {
            guard var value = record.value else { continue }
            if record.parsed.recordType == .blockEntity {
                value = try offsetBlockEntities(value, deltaX: dx, deltaZ: dz)
            }
            let targetKey = BedrockDBKey(
                position: destination,
                recordType: record.parsed.recordType,
                subChunkIndex: record.parsed.subChunkIndex
            ).encoded()
            puts.append((targetKey, value))
        }
        try database.applyBatch(
            puts: puts,
            deletes: destinationRecords.map(\.key),
            sync: true
        )

        let skipped = Array(Set(sourceRecords.map(\.parsed.recordType)).subtracting(copyableTypes))
            .sorted { $0.rawValue < $1.rawValue }
        return BedrockChunkCopyResult(
            copiedRecordCount: puts.count,
            removedDestinationRecordCount: destinationRecords.count,
            skippedRecordTypes: skipped
        )
    }

    /// Replaces every raw record for the coordinate with a minimal, valid
    /// generated chunk skeleton. This mirrors Android MCBEEditor's
    /// createEmpty flow: remove the full chunk first, then write only a
    /// finalized generator stage and a compatible version record. With no
    /// SubChunk records present, every block is air while Minecraft still
    /// treats the coordinate as an already generated chunk.
    func clearChunk(_ position: ChunkPosition) throws -> BedrockChunkClearResult {
        let database = try session.database()
        let chunkRecords = try rawChunkRecords(at: position, includeValues: true)
        let actorRecords = try actorRecordsForRemoval(at: position, database: database)

        guard !chunkRecords.isEmpty || !actorRecords.digestKeys.isEmpty else {
            throw MCBEEditorError.unsupported("该区块没有可清空的记录")
        }

        let parsedTypes = Set(chunkRecords.compactMap { BedrockDBKey.parse($0.key)?.recordType })
        let preferLegacy = parsedTypes.contains(.legacyVersion) && !parsedTypes.contains(.version)
        let profile = try BedrockEmptyChunk.profile(
            database: database, dimension: position.dimension, preferLegacy: preferLegacy
        )
        let metadata = BedrockEmptyChunk.metadataRecords(at: position, profile: profile)

        var deleteKeys = Set(chunkRecords.map(\.key))
        deleteKeys.formUnion(actorRecords.digestKeys)
        deleteKeys.formUnion(actorRecords.actorKeys)
        try database.applyBatch(
            puts: metadata.map { ($0.key, $0.value) },
            deletes: Array(deleteKeys),
            sync: true
        )

        return BedrockChunkClearResult(
            deletedChunkRecordCount: chunkRecords.count,
            deletedDigestCount: actorRecords.digestKeys.count,
            deletedActorCount: actorRecords.actorKeys.count,
            createdMetadataRecordCount: metadata.count,
            versionRecordType: metadata.first?.recordType ?? .legacyVersion
        )
    }

    /// Implements the Android MCBEEditor removeFullChunk behavior using raw
    /// chunk-prefix deletion rather than a whitelist of known tags. This is
    /// important because modern Bedrock adds tags such as ConversionData,
    /// GenerationSeed, blending metadata and LegacyVersion. Leaving any of those
    /// records behind can make Minecraft treat the coordinate as an already
    /// generated empty chunk instead of regenerating it from the seed.
    func regenerateChunk(_ position: ChunkPosition) throws -> BedrockChunkRegenerateResult {
        let database = try session.database()
        let chunkRecords = try rawChunkRecords(at: position, includeValues: true)
        let actorRecords = try actorRecordsForRemoval(at: position, database: database)

        var deleteKeys = Set(chunkRecords.map(\.key))
        deleteKeys.formUnion(actorRecords.digestKeys)
        deleteKeys.formUnion(actorRecords.actorKeys)
        guard !deleteKeys.isEmpty else {
            throw MCBEEditorError.unsupported("该区块已经处于未生成状态")
        }

        try database.applyBatch(puts: [], deletes: Array(deleteKeys), sync: true)
        return BedrockChunkRegenerateResult(
            deletedChunkRecordCount: chunkRecords.count,
            deletedDigestCount: actorRecords.digestKeys.count,
            deletedActorCount: actorRecords.actorKeys.count
        )
    }

    struct BiomeRecord {
        let key: Data
        var document: BedrockBiomeDocument
    }

    func biomeRecord(at position: ChunkPosition) throws -> BiomeRecord? {
        let records = try standardRecords(at: position, includeValues: true)
        let preference: [ChunkRecordType] = [.data3D, .data2D, .data2DLegacy]
        for type in preference {
            guard let record = records.first(where: { $0.parsed.recordType == type }),
                  let data = record.value else { continue }
            return BiomeRecord(
                key: record.key,
                document: try BedrockBiomeDocument.decode(recordType: type, data: data)
            )
        }
        return nil
    }

    func saveBiomeRecord(_ record: BiomeRecord) throws {
        try session.database().put(try record.document.encoded(), for: record.key, sync: true)
    }

    struct HardcodedSpawnersRecord {
        let key: Data
        var document: HardcodedSpawnersDocument
        let existed: Bool
    }

    func hardcodedSpawnersRecord(at position: ChunkPosition) throws -> HardcodedSpawnersRecord {
        let key = BedrockDBKey(
            position: position,
            recordType: .hardcodedSpawners,
            subChunkIndex: nil
        ).encoded()
        if let data = try session.database().get(key) {
            return HardcodedSpawnersRecord(
                key: key,
                document: try HardcodedSpawnersDocument.decode(data),
                existed: true
            )
        }
        return HardcodedSpawnersRecord(
            key: key,
            document: HardcodedSpawnersDocument(areas: []),
            existed: false
        )
    }

    func saveHardcodedSpawnersRecord(_ record: HardcodedSpawnersRecord) throws {
        let database = try session.database()
        if record.document.areas.isEmpty {
            let exists = record.existed ? true : (try database.get(record.key)) != nil
            if exists {
                try database.delete(record.key, sync: true)
            }
        } else {
            try database.put(try record.document.encoded(), for: record.key, sync: true)
        }
    }

    func replaceBlocks(
        in position: ChunkPosition,
        coordinatedOperation operation: BedrockCoordinatedBlockOperation
    ) throws -> BedrockChunkReplaceResult {
        guard operation.searchLayer0 != nil || operation.searchLayer1 != nil else {
            throw MCBEEditorError.malformedData("至少填写层 0 或层 1 的搜索条件")
        }

        let records = try standardRecords(at: position, includeValues: true)
            .filter { $0.parsed.recordType == .subChunk }
        guard !records.isEmpty else {
            throw MCBEEditorError.unsupported("该区块没有 SubChunk 记录")
        }

        var puts = [(key: Data, value: Data)]()
        var matched = 0
        var skipped = 0
        for record in records {
            guard let raw = record.value else { continue }
            do {
                let decoded = try BedrockSubChunk.decode(raw, keyYIndex: record.parsed.subChunkIndex)
                let result = try decoded.replacingBlocks(coordinatedOperation: operation)
                guard result.matchedBlockCount > 0 else { continue }
                puts.append((record.key, try result.subChunk.encodePersistent()))
                matched += result.matchedBlockCount
            } catch MCBEEditorError.unsupported {
                skipped += 1
            }
        }
        guard !puts.isEmpty else {
            if skipped > 0 {
                throw MCBEEditorError.unsupported("没有匹配方块；另有 \(skipped) 个旧版或不支持的 SubChunk 被跳过")
            }
            throw MCBEEditorError.unsupported("当前区块没有匹配搜索条件的方块")
        }
        try session.database().applyBatch(puts: puts, deletes: [], sync: true)
        return BedrockChunkReplaceResult(
            matchedBlockCount: matched,
            modifiedSubChunkCount: puts.count,
            skippedSubChunkCount: skipped
        )
    }

    func replaceBlocks(
        in position: ChunkPosition,
        criteria: BedrockBlockSearchCriteria,
        replacement: BedrockBlockReplacement
    ) throws -> BedrockChunkReplaceResult {
        let operations = criteria.layers.sorted().map { layer in
            BedrockLayerBlockOperation(
                layer: layer,
                criteria: BedrockBlockSearchCriteria(
                    nameContains: criteria.nameContains,
                    stateCriteria: criteria.stateCriteria,
                    layers: [layer]
                ),
                replacement: replacement
            )
        }
        return try replaceBlocks(in: position, operations: operations)
    }

    func replaceBlocks(
        in position: ChunkPosition,
        operations: [BedrockLayerBlockOperation]
    ) throws -> BedrockChunkReplaceResult {
        guard !operations.isEmpty else {
            throw MCBEEditorError.malformedData("至少填写层 0 或层 1 的搜索条件")
        }
        for operation in operations {
            guard (0..<BedrockBlockRecord.editableLayerCount).contains(operation.layer) else {
                throw MCBEEditorError.malformedData("只支持层 0 和层 1")
            }
            guard !operation.criteria.isEmpty else {
                throw MCBEEditorError.malformedData("层 \(operation.layer) 至少填写一个 name 或 states 搜索条件")
            }
        }

        let records = try standardRecords(at: position, includeValues: true)
            .filter { $0.parsed.recordType == .subChunk }
        guard !records.isEmpty else {
            throw MCBEEditorError.unsupported("该区块没有 SubChunk 记录")
        }

        var puts = [(key: Data, value: Data)]()
        var matched = 0
        var skipped = 0
        for record in records {
            guard let raw = record.value else { continue }
            do {
                let decoded = try BedrockSubChunk.decode(raw, keyYIndex: record.parsed.subChunkIndex)
                let result = try decoded.replacingBlocks(operations: operations)
                guard result.matchedBlockCount > 0 else { continue }
                puts.append((record.key, try result.subChunk.encodePersistent()))
                matched += result.matchedBlockCount
            } catch MCBEEditorError.unsupported {
                skipped += 1
            }
        }
        guard !puts.isEmpty else {
            if skipped > 0 {
                throw MCBEEditorError.unsupported("没有匹配方块；另有 \(skipped) 个旧版或不支持的 SubChunk 被跳过")
            }
            throw MCBEEditorError.unsupported("当前区块没有匹配搜索条件的方块")
        }
        try session.database().applyBatch(puts: puts, deletes: [], sync: true)
        return BedrockChunkReplaceResult(
            matchedBlockCount: matched,
            modifiedSubChunkCount: puts.count,
            skippedSubChunkCount: skipped
        )
    }

    func bulkReplaceLayer(
        in position: ChunkPosition,
        layer: Int,
        replacement: BedrockBlockReplacement,
        includeCompletelyAirCells: Bool
    ) throws -> BedrockChunkBulkLayerResult {
        guard replacement.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MCBEEditorError.malformedData("批量替换必须填写目标方块 name")
        }
        let records = try standardRecords(at: position, includeValues: true).filter { $0.parsed.recordType == .subChunk }
        guard !records.isEmpty else { throw MCBEEditorError.unsupported("该区块没有 SubChunk 记录") }
        var puts = [(key: Data, value: Data)]()
        var affected = 0
        var skipped = 0
        for record in records {
            guard let raw = record.value else { continue }
            do {
                let decoded = try BedrockSubChunk.decode(raw, keyYIndex: record.parsed.subChunkIndex)
                let result = try decoded.bulkReplacingLayer(layer, replacement: replacement, includeCompletelyAirCells: includeCompletelyAirCells)
                guard result.changed else { continue }
                puts.append((record.key, try result.subChunk.encodePersistent()))
                affected += result.affectedBlockCount
            } catch MCBEEditorError.unsupported { skipped += 1 }
        }
        guard !puts.isEmpty else {
            if skipped > 0 { throw MCBEEditorError.unsupported("没有可修改的现代 SubChunk；跳过 \(skipped) 个旧版 SubChunk") }
            throw MCBEEditorError.unsupported("没有符合批量选择条件的方块")
        }
        try session.database().applyBatch(puts: puts, deletes: [], sync: true)
        return BedrockChunkBulkLayerResult(affectedBlockCount: affected, modifiedSubChunkCount: puts.count, skippedSubChunkCount: skipped)
    }


    private struct StandardRecord {
        let key: Data
        let value: Data?
        let parsed: BedrockDBKey
    }

    private func standardRecords(at position: ChunkPosition, includeValues: Bool) throws -> [StandardRecord] {
        var prefix = Data()
        prefix.appendLE(position.x)
        prefix.appendLE(position.z)
        return try session.database().entries(prefix: prefix, includeValues: includeValues, limit: 0).compactMap { item in
            guard let parsed = BedrockDBKey.parse(item.key), parsed.position == position else { return nil }
            return StandardRecord(key: item.key, value: item.value, parsed: parsed)
        }
    }

    private struct RawRecord {
        let key: Data
        let value: Data?
    }

    private struct ActorRemovalRecords {
        let digestKeys: Set<Data>
        let actorKeys: Set<Data>
    }

    /// Returns every raw non-actor chunk record for the coordinate, including
    /// tags unknown to this build. Bedrock stores a one-byte tag after an 8-byte
    /// legacy overworld prefix or a 12-byte dimension-aware prefix; some record
    /// forms append one or two extra bytes (for example SubChunk Y).
    private func rawChunkRecords(at position: ChunkPosition, includeValues: Bool) throws -> [RawRecord] {
        let database = try session.database()
        var found = [Data: RawRecord]()
        for prefix in BedrockRawChunkKey.prefixes(for: position) {
            let entries = try database.entries(prefix: prefix, includeValues: includeValues, limit: 0)
            for item in entries where BedrockRawChunkKey.matches(item.key, position: position) {
                found[item.key] = RawRecord(key: item.key, value: item.value)
            }
        }
        return Array(found.values)
    }

    /// Mirrors Android MCBEEditor's prefix-and-length deletion rule while
    /// supporting both legacy overworld keys and current dimension-aware keys.
    static func isRawChunkRecordKey(_ key: Data, position: ChunkPosition) -> Bool {
        BedrockRawChunkKey.matches(key, position: position)
    }

    private func actorRecordsForRemoval(
        at position: ChunkPosition,
        database: MojangLevelDB
    ) throws -> ActorRemovalRecords {
        var digestKeys = Set<Data>()
        var actorKeys = Set<Data>()
        for digestKey in Self.actorDigestKeys(for: position) {
            guard let digest = try database.get(digestKey) else { continue }
            digestKeys.insert(digestKey)
            guard digest.count % 8 == 0 else {
                // Remove the malformed digest so the chunk no longer references
                // corrupt actor data, but do not guess actor keys from partial IDs.
                continue
            }
            var offset = 0
            while offset < digest.count {
                actorKeys.insert(Self.actorKey(rawID: digest.subdata(in: offset..<(offset + 8))))
                offset += 8
            }
        }
        return ActorRemovalRecords(digestKeys: digestKeys, actorKeys: actorKeys)
    }

    private static func actorKey(rawID: Data) -> Data {
        var key = Data("actorprefix".utf8)
        key.append(rawID)
        return key
    }

    private func offsetBlockEntities(_ data: Data, deltaX: Int64, deltaZ: Int64) throws -> Data {
        var records = try ConsecutiveNBTCodec.decode(data)
        for index in records.indices {
            records[index].document.root = Self.offsetCoordinates(
                records[index].document.root,
                deltaX: deltaX,
                deltaZ: deltaZ
            )
        }
        return try ConsecutiveNBTCodec.encode(records)
    }

    private static func offsetCoordinates(_ value: NBTValue, deltaX: Int64, deltaZ: Int64) -> NBTValue {
        guard case .compound(var tags) = value else { return value }
        let xNames: Set<String> = ["x", "pairx"]
        let zNames: Set<String> = ["z", "pairz"]
        for index in tags.indices {
            let lower = tags[index].name.lowercased()
            if xNames.contains(lower) {
                tags[index].value = offsetNumeric(tags[index].value, by: deltaX)
            } else if zNames.contains(lower) {
                tags[index].value = offsetNumeric(tags[index].value, by: deltaZ)
            }
        }
        return .compound(tags)
    }

    private static func offsetNumeric(_ value: NBTValue, by delta: Int64) -> NBTValue {
        switch value {
        case .byte(let number): return .byte(Int8(clamping: Int64(number) + delta))
        case .short(let number): return .short(Int16(clamping: Int64(number) + delta))
        case .int(let number): return .int(Int32(clamping: Int64(number) + delta))
        case .long(let number): return .long(number &+ delta)
        case .float(let number): return .float(number + Float(delta))
        case .double(let number): return .double(number + Double(delta))
        default: return value
        }
    }

    private static let copyableRecordTypes: Set<ChunkRecordType> = [
        .data3D, .version, .data2D, .data2DLegacy, .subChunk,
        .legacyTerrain, .blockEntity, .legacyBlockExtraData,
        .biomeState, .finalizedState, .borderBlocks, .checksums
    ]

    private static func actorDigestKeys(for position: ChunkPosition) -> [Data] {
        var current = Data("digp".utf8)
        current.appendLE(position.x)
        current.appendLE(position.z)
        current.appendLE(position.dimension)
        guard position.dimension == 0 else { return [current] }
        var legacy = Data("digp".utf8)
        legacy.appendLE(position.x)
        legacy.appendLE(position.z)
        return [current, legacy]
    }

    private static func parseActorDigestKey(_ data: Data) -> ChunkPosition? {
        guard data.count == 12 || data.count == 16,
              data.prefix(4) == Data("digp".utf8),
              let x = try? data.littleEndianInt32(at: 4),
              let z = try? data.littleEndianInt32(at: 8) else { return nil }
        let dimension: Int32
        if data.count == 16 {
            guard let parsed = try? data.littleEndianInt32(at: 12) else { return nil }
            dimension = parsed
        } else {
            dimension = 0
        }
        return ChunkPosition(x: x, z: z, dimension: dimension)
    }
}
