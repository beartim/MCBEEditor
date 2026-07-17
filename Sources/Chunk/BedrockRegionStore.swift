import Foundation

struct BedrockRegionMutationResult {
    let processedChunkCount: Int
    let changedChunkCount: Int
    let skippedChunkCount: Int
    let detailCount: Int
}

struct BedrockRegionCopyResult {
    let source: BedrockMapRegion
    let destination: BedrockMapRegion
    let writtenSubChunkCount: Int
    let copiedBlockStateCount: Int
    let copiedRecordCount: Int
    let copiedBiomeCellCount: Int
    let copiedBlockEntityCount: Int
    let skippedLegacyStateCount: Int
    let usedWholeChunkCopy: Bool
}

extension BedrockChunkStore {
    func replaceBlocks(
        in region: BedrockMapRegion,
        coordinatedOperation operation: BedrockCoordinatedBlockOperation
    ) throws -> BedrockChunkReplaceResult {
        guard operation.searchLayer0 != nil || operation.searchLayer1 != nil else {
            throw BlocktopographError.malformedData("至少填写层 0 或层 1 的搜索条件")
        }
        let database = try session.database()
        var puts = [(key: Data, value: Data)]()
        var matched = 0
        var skipped = 0

        for chunk in region.chunkPositions {
            guard let ranges = region.localRanges(in: chunk) else { continue }
            for record in try regionSubChunkRecords(at: chunk, database: database) {
                do {
                    let decoded = try BedrockSubChunk.decode(record.value, keyYIndex: record.y)
                    let result = try decoded.replacingBlocks(
                        coordinatedOperation: operation,
                        localXRange: ranges.x,
                        localZRange: ranges.z
                    )
                    guard result.matchedBlockCount > 0 else { continue }
                    puts.append((record.key, try result.subChunk.encodePersistent()))
                    matched += result.matchedBlockCount
                } catch BlocktopographError.unsupported {
                    skipped += 1
                }
            }
        }

        guard !puts.isEmpty else {
            if skipped > 0 {
                throw BlocktopographError.unsupported("区域内没有匹配方块；另有 \(skipped) 个旧版或不支持的 SubChunk 被跳过")
            }
            throw BlocktopographError.unsupported("区域内没有匹配搜索条件的方块")
        }
        try database.applyBatch(puts: puts, deletes: [], sync: true)
        return BedrockChunkReplaceResult(
            matchedBlockCount: matched,
            modifiedSubChunkCount: puts.count,
            skippedSubChunkCount: skipped
        )
    }


    func bulkReplaceLayer(
        in region: BedrockMapRegion,
        layer: Int,
        replacement: BedrockBlockReplacement,
        includeCompletelyAirCells: Bool
    ) throws -> BedrockChunkBulkLayerResult {
        guard replacement.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw BlocktopographError.malformedData("批量替换必须填写目标方块 name")
        }
        let database = try session.database()
        var puts = [(key: Data, value: Data)]()
        var affected = 0
        var skipped = 0

        for chunk in region.chunkPositions {
            guard let ranges = region.localRanges(in: chunk) else { continue }
            for record in try regionSubChunkRecords(at: chunk, database: database) {
                do {
                    let decoded = try BedrockSubChunk.decode(record.value, keyYIndex: record.y)
                    let result = try decoded.bulkReplacingLayer(
                        layer,
                        replacement: replacement,
                        includeCompletelyAirCells: includeCompletelyAirCells,
                        localXRange: ranges.x,
                        localZRange: ranges.z
                    )
                    guard result.changed else { continue }
                    puts.append((record.key, try result.subChunk.encodePersistent()))
                    affected += result.affectedBlockCount
                } catch BlocktopographError.unsupported {
                    skipped += 1
                }
            }
        }

        guard !puts.isEmpty else {
            if skipped > 0 {
                throw BlocktopographError.unsupported("框选区域内没有可修改的现代 SubChunk；跳过 \(skipped) 个旧版 SubChunk")
            }
            throw BlocktopographError.unsupported("框选区域内没有符合批量选择条件的方块")
        }
        try database.applyBatch(puts: puts, deletes: [], sync: true)
        return BedrockChunkBulkLayerResult(
            affectedBlockCount: affected,
            modifiedSubChunkCount: puts.count,
            skippedSubChunkCount: skipped
        )
    }

    func setBiomeID(_ id: UInt32, in region: BedrockMapRegion) throws -> BedrockRegionMutationResult {
        let database = try session.database()
        var puts = [(key: Data, value: Data)]()
        var changedChunks = 0
        var changedCells = 0
        var skipped = 0

        for chunk in region.chunkPositions {
            guard let ranges = region.localRanges(in: chunk) else { continue }
            guard var record = try biomeRecord(at: chunk) else {
                skipped += 1
                continue
            }
            if record.document.format != .data3D && id > UInt32(UInt8.max) {
                throw BlocktopographError.malformedData("Data2D 生物群系 ID 必须小于等于 255；当前 ID 为 \(id)")
            }
            var changed = 0
            switch record.document.format {
            case .data2D, .data2DLegacy:
                guard !record.document.layers.isEmpty else { continue }
                for z in ranges.z {
                    for x in ranges.x {
                        let index = z * 16 + x
                        if record.document.layers[0].biomeIDs.indices.contains(index) {
                            record.document.layers[0].biomeIDs[index] = id
                            record.document.layers[0].isAbsent = false
                            changed += 1
                        }
                    }
                }
            case .data3D:
                for layerIndex in record.document.layers.indices {
                    guard !record.document.layers[layerIndex].isAbsent else { continue }
                    for x in ranges.x {
                        for z in ranges.z {
                            for y in 0..<16 {
                                let index = x * 256 + z * 16 + y
                                if record.document.layers[layerIndex].biomeIDs.indices.contains(index) {
                                    record.document.layers[layerIndex].biomeIDs[index] = id
                                    changed += 1
                                }
                            }
                        }
                    }
                }
            }
            guard changed > 0 else { continue }
            puts.append((record.key, try record.document.encoded()))
            changedChunks += 1
            changedCells += changed
        }

        guard !puts.isEmpty else {
            throw BlocktopographError.unsupported("选区内没有可修改的生物群系记录")
        }
        try database.applyBatch(puts: puts, deletes: [], sync: true)
        return BedrockRegionMutationResult(
            processedChunkCount: region.chunkCount,
            changedChunkCount: changedChunks,
            skippedChunkCount: skipped,
            detailCount: changedCells
        )
    }

    func clearRegion(_ region: BedrockMapRegion) throws -> BedrockRegionMutationResult {
        try mutateWholeChunks(region.expandedToChunkBounds, regenerate: false)
    }

    func regenerateRegion(_ region: BedrockMapRegion) throws -> BedrockRegionMutationResult {
        try mutateWholeChunks(region.expandedToChunkBounds, regenerate: true)
    }

    private func mutateWholeChunks(_ alignedRegion: BedrockMapRegion, regenerate: Bool) throws -> BedrockRegionMutationResult {
        var changed = 0
        var skipped = 0
        var detail = 0
        for chunk in alignedRegion.chunkPositions {
            do {
                if regenerate {
                    let result = try regenerateChunk(chunk)
                    detail += result.deletedChunkRecordCount + result.deletedDigestCount + result.deletedActorCount
                } else {
                    let result = try clearChunk(chunk)
                    detail += result.deletedChunkRecordCount + result.deletedDigestCount + result.deletedActorCount
                }
                changed += 1
            } catch BlocktopographError.unsupported {
                skipped += 1
            }
        }
        guard changed > 0 else {
            throw BlocktopographError.unsupported(regenerate ? "扩展后的区域内没有可重新生成的区块" : "扩展后的区域内没有可清空的区块")
        }
        return BedrockRegionMutationResult(
            processedChunkCount: alignedRegion.chunkCount,
            changedChunkCount: changed,
            skippedChunkCount: skipped,
            detailCount: detail
        )
    }

    /// Copies layer 0/layer 1 block states for the complete vertical range of
    /// the selected X-Z rectangle. Destination X1/Z1 are derived from the
    /// source size, so the target region is always exactly the same size.
    func copyRegion(
        _ source: BedrockMapRegion,
        toMinimumX targetX: Int64,
        minimumZ targetZ: Int64,
        dimension targetDimension: Int32
    ) throws -> BedrockRegionCopyResult {
        let destination = source.translated(toMinimumX: targetX, minimumZ: targetZ, dimension: targetDimension)
        guard source != destination else {
            throw BlocktopographError.malformedData("源区域与目标区域不能完全相同")
        }

        // Complete chunk-aligned rectangles can use the existing raw-record
        // copier. This is much faster, preserves biome/block-entity records,
        // and avoids decoding millions of individual block states.
        if source.isChunkAligned, destination.isChunkAligned, !source.intersects(destination) {
            var copiedRecords = 0
            let xCount = Int64(source.maximumChunkX) - Int64(source.minimumChunkX) + 1
            let zCount = Int64(source.maximumChunkZ) - Int64(source.minimumChunkZ) + 1
            for dz in 0..<zCount {
                for dx in 0..<xCount {
                    let sourceChunk = ChunkPosition(
                        x: Int32(Int64(source.minimumChunkX) + dx),
                        z: Int32(Int64(source.minimumChunkZ) + dz),
                        dimension: source.dimension
                    )
                    let destinationChunk = ChunkPosition(
                        x: Int32(Int64(destination.minimumChunkX) + dx),
                        z: Int32(Int64(destination.minimumChunkZ) + dz),
                        dimension: destination.dimension
                    )
                    let result = try copyChunk(from: sourceChunk, to: destinationChunk)
                    copiedRecords += result.copiedRecordCount
                }
            }
            return BedrockRegionCopyResult(
                source: source,
                destination: destination,
                writtenSubChunkCount: 0,
                copiedBlockStateCount: 0,
                copiedRecordCount: copiedRecords,
                copiedBiomeCellCount: 0,
                copiedBlockEntityCount: 0,
                skippedLegacyStateCount: 0,
                usedWholeChunkCopy: true
            )
        }

        let database = try session.database()
        struct TargetKey: Hashable {
            let chunkX: Int32
            let chunkZ: Int32
            let dimension: Int32
            let y: Int8
        }
        var edits = [TargetKey: [Int: [Int: BedrockBlockState]]]()
        var copied = 0
        var skippedLegacy = 0

        // Snapshot all source block states before writing anything. This keeps
        // overlapping source/target rectangles deterministic.
        for sourceChunk in source.chunkPositions {
            guard let ranges = source.localRanges(in: sourceChunk) else { continue }
            for record in try regionSubChunkRecords(at: sourceChunk, database: database) {
                let decoded: BedrockSubChunk
                do {
                    decoded = try BedrockSubChunk.decode(record.value, keyYIndex: record.y)
                } catch BlocktopographError.unsupported {
                    continue
                }
                for localX in ranges.x {
                    let absoluteX = MapCoordinate.absoluteBlock(chunk: sourceChunk.x, local: localX)
                    let targetAbsoluteX = destination.minimumX + (absoluteX - source.minimumX)
                    let targetChunkX = MapCoordinate.chunk(fromBlock: targetAbsoluteX)
                    let targetLocalX = Int(targetAbsoluteX - MapCoordinate.blockOrigin(ofChunk: targetChunkX))
                    for localZ in ranges.z {
                        let absoluteZ = MapCoordinate.absoluteBlock(chunk: sourceChunk.z, local: localZ)
                        let targetAbsoluteZ = destination.minimumZ + (absoluteZ - source.minimumZ)
                        let targetChunkZ = MapCoordinate.chunk(fromBlock: targetAbsoluteZ)
                        let targetLocalZ = Int(targetAbsoluteZ - MapCoordinate.blockOrigin(ofChunk: targetChunkZ))
                        let targetKey = TargetKey(chunkX: targetChunkX, chunkZ: targetChunkZ, dimension: targetDimension, y: record.y)
                        for localY in 0..<16 {
                            let targetIndex = (targetLocalX << 8) | (targetLocalZ << 4) | localY
                            for layer in 0..<min(BedrockBlockRecord.editableLayerCount, decoded.storages.count) {
                                guard let state = decoded.storages[layer].blockState(x: localX, y: localY, z: localZ) else { continue }
                                guard state.nbt != nil else {
                                    skippedLegacy += 1
                                    continue
                                }
                                var layers = edits[targetKey] ?? [:]
                                var values = layers[layer] ?? [:]
                                values[targetIndex] = state
                                layers[layer] = values
                                edits[targetKey] = layers
                                copied += 1
                            }
                        }
                    }
                }
            }
        }

        var puts = [(key: Data, value: Data)]()
        puts.reserveCapacity(edits.count + destination.chunkCount * 2)
        for (target, layerEdits) in edits {
            let key = BedrockDBKey.subChunk(x: target.chunkX, z: target.chunkZ, dimension: target.dimension, index: target.y)
            let decoded: BedrockSubChunk
            if let raw = try database.get(key) {
                decoded = try BedrockSubChunk.decode(raw, keyYIndex: target.y)
            } else {
                let version = layerEdits.values.flatMap { $0.values }.compactMap(\.paletteVersion).first
                let air = BedrockBlockState.editableAir(version: version)
                decoded = BedrockSubChunk(
                    version: 9,
                    yIndex: target.y,
                    storages: [.airFilled(with: air)],
                    trailingData: Data()
                )
            }
            let updated = try decoded.replacingBlockStates(layerEdits)
            puts.append((key, try updated.encodePersistent()))
        }
        let writtenSubChunks = puts.count

        let biomeCopy = try copyRegionBiomes(source: source, destination: destination, database: database)
        puts.append(contentsOf: biomeCopy.puts)

        let blockEntityCopy = try copyRegionBlockEntities(source: source, destination: destination, database: database)
        puts.append(contentsOf: blockEntityCopy.puts)

        guard !puts.isEmpty || !blockEntityCopy.deletes.isEmpty else {
            throw BlocktopographError.unsupported("源区域内没有可复制的现代方块、生物群系或方块实体数据")
        }
        try database.applyBatch(puts: puts, deletes: blockEntityCopy.deletes, sync: true)
        return BedrockRegionCopyResult(
            source: source,
            destination: destination,
            writtenSubChunkCount: writtenSubChunks,
            copiedBlockStateCount: copied,
            copiedRecordCount: 0,
            copiedBiomeCellCount: biomeCopy.cellCount,
            copiedBlockEntityCount: blockEntityCopy.copiedCount,
            skippedLegacyStateCount: skippedLegacy,
            usedWholeChunkCopy: false
        )
    }

    private func copyRegionBiomes(
        source: BedrockMapRegion,
        destination: BedrockMapRegion,
        database: MojangLevelDB
    ) throws -> (puts: [(key: Data, value: Data)], cellCount: Int) {
        struct TargetBiome {
            let key: Data
            var document: BedrockBiomeDocument
        }
        var targets = [ChunkPosition: TargetBiome]()
        var changedCells = 0

        for sourceChunk in source.chunkPositions {
            guard let ranges = source.localRanges(in: sourceChunk),
                  let sourceRecord = try biomeRecord(at: sourceChunk) else { continue }
            for localX in ranges.x {
                let absoluteX = MapCoordinate.absoluteBlock(chunk: sourceChunk.x, local: localX)
                let targetAbsoluteX = destination.minimumX + (absoluteX - source.minimumX)
                let targetChunkX = MapCoordinate.chunk(fromBlock: targetAbsoluteX)
                let targetLocalX = Int(targetAbsoluteX - MapCoordinate.blockOrigin(ofChunk: targetChunkX))
                for localZ in ranges.z {
                    let absoluteZ = MapCoordinate.absoluteBlock(chunk: sourceChunk.z, local: localZ)
                    let targetAbsoluteZ = destination.minimumZ + (absoluteZ - source.minimumZ)
                    let targetChunkZ = MapCoordinate.chunk(fromBlock: targetAbsoluteZ)
                    let targetLocalZ = Int(targetAbsoluteZ - MapCoordinate.blockOrigin(ofChunk: targetChunkZ))
                    let targetPosition = ChunkPosition(x: targetChunkX, z: targetChunkZ, dimension: destination.dimension)

                    var target: TargetBiome
                    if let cached = targets[targetPosition] {
                        target = cached
                    } else if let existing = try biomeRecord(at: targetPosition) {
                        target = TargetBiome(key: existing.key, document: existing.document)
                    } else {
                        var blank = sourceRecord.document
                        for layerIndex in blank.layers.indices where !blank.layers[layerIndex].isAbsent {
                            blank.layers[layerIndex].biomeIDs = Array(
                                repeating: 0,
                                count: blank.layers[layerIndex].biomeIDs.count
                            )
                        }
                        let key = BedrockDBKey(
                            position: targetPosition,
                            recordType: blank.format.recordType,
                            subChunkIndex: nil
                        ).encoded()
                        target = TargetBiome(key: key, document: blank)
                    }

                    changedCells += copyBiomeColumn(
                        source: sourceRecord.document,
                        sourceX: localX,
                        sourceZ: localZ,
                        target: &target.document,
                        targetX: targetLocalX,
                        targetZ: targetLocalZ
                    )
                    targets[targetPosition] = target
                }
            }
        }

        let puts = try targets.values.map { target in
            (key: target.key, value: try target.document.encoded())
        }
        return (puts, changedCells)
    }

    private func copyBiomeColumn(
        source: BedrockBiomeDocument,
        sourceX: Int,
        sourceZ: Int,
        target: inout BedrockBiomeDocument,
        targetX: Int,
        targetZ: Int
    ) -> Int {
        let sourceHeightIndex = sourceZ * 16 + sourceX
        let sourceY = source.heightMap.indices.contains(sourceHeightIndex)
            ? Int(source.heightMap[sourceHeightIndex])
            : 64
        let surfaceID = source.biomeID(localX: sourceX, y: sourceY, localZ: sourceZ)
            ?? source.layers.first(where: { !$0.isAbsent })?.biomeIDs.first
            ?? 0

        switch target.format {
        case .data2D, .data2DLegacy:
            guard surfaceID <= UInt32(UInt8.max), !target.layers.isEmpty else { return 0 }
            let index = targetZ * 16 + targetX
            guard target.layers[0].biomeIDs.indices.contains(index) else { return 0 }
            target.layers[0].biomeIDs[index] = surfaceID
            target.layers[0].isAbsent = false
            return 1

        case .data3D:
            var count = 0
            for layerIndex in target.layers.indices {
                guard !target.layers[layerIndex].isAbsent,
                      let baseY = target.layers[layerIndex].baseY else { continue }
                for localY in 0..<16 {
                    let id = source.biomeID(localX: sourceX, y: baseY + localY, localZ: sourceZ) ?? surfaceID
                    let index = targetX * 256 + targetZ * 16 + localY
                    guard target.layers[layerIndex].biomeIDs.indices.contains(index) else { continue }
                    target.layers[layerIndex].biomeIDs[index] = id
                    count += 1
                }
            }
            return count
        }
    }

    private func copyRegionBlockEntities(
        source: BedrockMapRegion,
        destination: BedrockMapRegion,
        database: MojangLevelDB
    ) throws -> (puts: [(key: Data, value: Data)], deletes: [Data], copiedCount: Int) {
        let deltaX = destination.minimumX - source.minimumX
        let deltaZ = destination.minimumZ - source.minimumZ
        var copiedByChunk = [ChunkPosition: [ConsecutiveNBTRecord]]()
        var copiedCount = 0

        // Read and transform source records first so overlapping copies do not
        // consume data already modified earlier in the operation.
        for chunk in source.chunkPositions {
            let key = BedrockDBKey(position: chunk, recordType: .blockEntity, subChunkIndex: nil).encoded()
            guard let raw = try database.get(key) else { continue }
            for var record in try ConsecutiveNBTCodec.decode(raw) {
                guard let coordinate = blockEntityXZ(record.document.root),
                      source.contains(x: coordinate.x, z: coordinate.z) else { continue }
                record.document.root = offsetBlockEntityRoot(record.document.root, deltaX: deltaX, deltaZ: deltaZ)
                record.rawData = Data()
                let targetX = coordinate.x + deltaX
                let targetZ = coordinate.z + deltaZ
                let targetChunk = ChunkPosition(
                    x: MapCoordinate.chunk(fromBlock: targetX),
                    z: MapCoordinate.chunk(fromBlock: targetZ),
                    dimension: destination.dimension
                )
                copiedByChunk[targetChunk, default: []].append(record)
                copiedCount += 1
            }
        }

        var puts = [(key: Data, value: Data)]()
        var deletes = [Data]()
        for targetChunk in destination.chunkPositions {
            let key = BedrockDBKey(position: targetChunk, recordType: .blockEntity, subChunkIndex: nil).encoded()
            var records = [ConsecutiveNBTRecord]()
            if let raw = try database.get(key) {
                records = try ConsecutiveNBTCodec.decode(raw).filter { record in
                    guard let coordinate = blockEntityXZ(record.document.root) else { return true }
                    return !destination.contains(x: coordinate.x, z: coordinate.z)
                }
            }
            records.append(contentsOf: copiedByChunk[targetChunk] ?? [])
            if records.isEmpty {
                if try database.get(key) != nil { deletes.append(key) }
            } else {
                puts.append((key, try ConsecutiveNBTCodec.encode(records)))
            }
        }
        return (puts, deletes, copiedCount)
    }

    private func blockEntityXZ(_ root: NBTValue) -> (x: Int64, z: Int64)? {
        guard case .compound(let tags) = root else { return nil }
        func number(_ names: Set<String>) -> Int64? {
            guard let value = tags.first(where: { names.contains($0.name.lowercased()) })?.value else { return nil }
            switch value {
            case .byte(let number): return Int64(number)
            case .short(let number): return Int64(number)
            case .int(let number): return Int64(number)
            case .long(let number): return number
            case .float(let number): return Int64(number)
            case .double(let number): return Int64(number)
            default: return nil
            }
        }
        guard let x = number(["x", "pairx"]), let z = number(["z", "pairz"]) else { return nil }
        return (x, z)
    }

    private func offsetBlockEntityRoot(_ root: NBTValue, deltaX: Int64, deltaZ: Int64) -> NBTValue {
        guard case .compound(var tags) = root else { return root }
        for index in tags.indices {
            let name = tags[index].name.lowercased()
            if name == "x" || name == "pairx" {
                tags[index].value = offsetNumeric(tags[index].value, by: deltaX)
            } else if name == "z" || name == "pairz" {
                tags[index].value = offsetNumeric(tags[index].value, by: deltaZ)
            }
        }
        return .compound(tags)
    }

    private func offsetNumeric(_ value: NBTValue, by delta: Int64) -> NBTValue {
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

    private struct RegionSubChunkRecord {
        let key: Data
        let value: Data
        let y: Int8
    }

    private func regionSubChunkRecords(at position: ChunkPosition, database: MojangLevelDB) throws -> [RegionSubChunkRecord] {
        var prefix = Data()
        prefix.appendLE(position.x)
        prefix.appendLE(position.z)
        return try database.entries(prefix: prefix, includeValues: true, limit: 0).compactMap { entry in
            guard let parsed = BedrockDBKey.parse(entry.key), parsed.position == position,
                  parsed.recordType == .subChunk, let y = parsed.subChunkIndex,
                  let value = entry.value else { return nil }
            return RegionSubChunkRecord(key: entry.key, value: value, y: y)
        }
    }
}
