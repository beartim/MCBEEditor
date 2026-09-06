import Foundation

struct BedrockLegacyChunkUpgradePlan {
    let metadataPuts: [(key: Data, value: Data)]
    let metadataDeletes: [Data]
    let subChunkPuts: [(key: Data, value: Data)]
    let paletteVersion: Int32
}

/// Converts a legacy numeric-ID chunk to a modern block-state chunk without
/// leaving a Version/SubChunk mismatch. All legacy SubChunks in the chunk are
/// upgraded together, while the old 2D biome map is expanded vertically into
/// Data3D so Minecraft can load the resulting v9 records.
enum BedrockLegacyChunkUpgrade {
    static func plan(
        database: MojangLevelDB,
        position: ChunkPosition,
        preferredPaletteVersion: Int32? = nil
    ) throws -> BedrockLegacyChunkUpgradePlan {
        let dimensionProfile = try BedrockEmptyChunk.profile(
            database: database,
            dimension: position.dimension,
            preferLegacy: false,
            preferredPaletteVersion: preferredPaletteVersion
        )
        let paletteVersion = try BedrockEmptyChunk.preferredBlockPaletteVersion(
            database: database, at: position, fallback: dimensionProfile.blockPaletteVersion
        )
        let terrainData = try modernTerrainData(
            database: database,
            position: position,
            fallbackProfile: dimensionProfile
        )

        let versionValue: Data = dimensionProfile.versionRecordType == .version
            ? dimensionProfile.versionValue
            : Data([40])
        var finalized = Data()
        finalized.appendLE(Int32(2))

        let versionKey = BedrockDBKey(position: position, recordType: .version, subChunkIndex: nil).encoded()
        let finalizedKey = BedrockDBKey(position: position, recordType: .finalizedState, subChunkIndex: nil).encoded()
        let data3DKey = BedrockDBKey(position: position, recordType: .data3D, subChunkIndex: nil).encoded()
        let metadataPuts = [
            (key: versionKey, value: versionValue),
            (key: finalizedKey, value: finalized),
            (key: data3DKey, value: terrainData)
        ]
        var metadataDeletes = [
            BedrockDBKey(position: position, recordType: .legacyVersion, subChunkIndex: nil).encoded(),
            BedrockDBKey(position: position, recordType: .data2D, subChunkIndex: nil).encoded(),
            BedrockDBKey(position: position, recordType: .data2DLegacy, subChunkIndex: nil).encoded()
        ]

        var subChunkPuts = [(key: Data, value: Data)]()
        var convertedY = Set<Int8>()

        // Pre-Anvil worlds (for example PE 0.10.x) store all 16×128×16
        // terrain in one 0x30 value. Convert its eight virtual slices when a
        // modern block state forces an explicit chunk upgrade.
        let legacyTerrainKey = BedrockDBKey(
            position: position, recordType: .legacyTerrain, subChunkIndex: nil
        ).encoded()
        if let raw = try database.get(legacyTerrainKey) {
            let terrain = try BedrockLegacyTerrain.decode(raw)
            for rawY in 0..<8 {
                let y = Int8(rawY)
                let legacy = try terrain.subChunk(yIndex: y)
                let upgraded = try legacy.upgradedToModern(paletteVersion: paletteVersion)
                let key = BedrockDBKey.subChunk(
                    x: position.x, z: position.z, dimension: position.dimension, index: y
                )
                subChunkPuts.append((key: key, value: try upgraded.encodePersistent()))
                convertedY.insert(y)
            }
            metadataDeletes.append(legacyTerrainKey)
        }

        // v0/v2...v7 store their second block layer in one chunk-wide
        // LegacyBlockExtraData (0x34) value. Merge that virtual layer before
        // conversion so a v9 upgrade cannot drop snow/water/overlap blocks.
        let extraKey = BedrockDBKey(
            position: position, recordType: .legacyBlockExtraData, subChunkIndex: nil
        ).encoded()
        let extraRaw = try database.get(extraKey)
        let extraData = try extraRaw.map(BedrockLegacyBlockExtraData.decode)
        var numericByY = [Int8: BedrockSubChunk]()
        for rawY in Int(Int8.min)...Int(Int8.max) {
            guard let y = Int8(exactly: rawY), !convertedY.contains(y) else { continue }
            let key = BedrockDBKey.subChunk(
                x: position.x, z: position.z, dimension: position.dimension, index: y
            )
            guard let raw = try database.get(key) else { continue }
            let decoded = try BedrockSubChunk.decode(raw, keyYIndex: y)
            guard decoded.isLegacyNumeric else { continue }
            numericByY[y] = decoded
        }

        // Preserve extra-only slices too (for example an omitted all-air
        // primary 0x2F plus non-air entries in 0x34).
        if let extraData {
            let fallbackVersion = numericByY.values.first?.version ?? 0
            for y in extraData.subChunkYIndices where numericByY[y] == nil && !convertedY.contains(y) {
                guard (0...15).contains(Int(y)) else { continue }
                numericByY[y] = try BedrockSubChunk.emptyLegacy(version: fallbackVersion, yIndex: y)
            }
        }

        var upgradedNumeric = false
        for y in numericByY.keys.sorted() {
            guard var decoded = numericByY[y] else { continue }
            if let layer1 = extraData?.storage(subChunkY: y) {
                var storages = decoded.storages
                let air = BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
                while storages.isEmpty { storages.append(.airFilled(with: air)) }
                if storages.count == 1 { storages.append(layer1) } else { storages[1] = layer1 }
                decoded = BedrockSubChunk(
                    version: decoded.version, yIndex: decoded.yIndex,
                    storages: storages, trailingData: decoded.trailingData
                )
            }
            let upgraded = try decoded.upgradedToModern(paletteVersion: paletteVersion)
            let key = BedrockDBKey.subChunk(
                x: position.x, z: position.z, dimension: position.dimension, index: y
            )
            subChunkPuts.append((key: key, value: try upgraded.encodePersistent()))
            convertedY.insert(y)
            upgradedNumeric = true
        }
        if upgradedNumeric, extraRaw != nil {
            metadataDeletes.append(extraKey)
        }

        return BedrockLegacyChunkUpgradePlan(
            metadataPuts: metadataPuts,
            metadataDeletes: metadataDeletes,
            subChunkPuts: subChunkPuts,
            paletteVersion: paletteVersion
        )
    }

    private static func modernTerrainData(
        database: MojangLevelDB,
        position: ChunkPosition,
        fallbackProfile: BedrockEmptyChunkProfile
    ) throws -> Data {
        let data3DKey = BedrockDBKey(position: position, recordType: .data3D, subChunkIndex: nil).encoded()
        if let existing = try database.get(data3DKey) { return existing }

        for type in [ChunkRecordType.data2D, .data2DLegacy] {
            let key = BedrockDBKey(position: position, recordType: type, subChunkIndex: nil).encoded()
            if let raw = try database.get(key),
               let document = try? BedrockBiomeDocument.decode(recordType: type, data: raw) {
                return try document.expandedToData3D().encoded()
            }
        }

        let legacyTerrainKey = BedrockDBKey(
            position: position, recordType: .legacyTerrain, subChunkIndex: nil
        ).encoded()
        if let raw = try database.get(legacyTerrainKey) {
            let terrain = try BedrockLegacyTerrain.decode(raw)
            var ids = [UInt32]()
            var auxiliary = Data()
            var heights = [Int16]()
            ids.reserveCapacity(256)
            auxiliary.reserveCapacity(256 * 3)
            heights.reserveCapacity(256)
            for index in 0..<256 {
                let sample = index * 4
                ids.append(UInt32(terrain.biomeColors[sample]))
                auxiliary.append(terrain.biomeColors.subdata(in: (sample + 1)..<(sample + 4)))
                heights.append(Int16(terrain.heightMap[index]))
            }
            let document = BedrockBiomeDocument(
                format: .data2DLegacy,
                heightMap: heights,
                layers: [BedrockBiomeLayer(baseY: nil, biomeIDs: ids, isAbsent: false)],
                legacyAuxiliaryBytes: auxiliary
            )
            return try document.expandedToData3D().encoded()
        }

        if fallbackProfile.terrainRecordType == .data3D,
           let value = fallbackProfile.terrainValue {
            return value
        }
        if let type = fallbackProfile.terrainRecordType,
           let value = fallbackProfile.terrainValue,
           let document = try? BedrockBiomeDocument.decode(recordType: type, data: value) {
            return try document.expandedToData3D().encoded()
        }

        return try BedrockBiomeDocument.emptyData3D().encoded()
    }
}

extension BedrockBiomeDocument {
    func expandedToData3D(minimumY: Int = -64, maximumY: Int = 319) -> BedrockBiomeDocument {
        if format == .data3D { return self }
        let horizontal = layers.first?.biomeIDs ?? Array(repeating: UInt32(0), count: 256)
        var outputLayers = [BedrockBiomeLayer]()
        var baseY = minimumY
        while baseY <= maximumY {
            var values = Array(repeating: UInt32(0), count: 4096)
            for x in 0..<16 {
                for z in 0..<16 {
                    let biome = horizontal.indices.contains(z * 16 + x) ? horizontal[z * 16 + x] : 0
                    for localY in 0..<16 {
                        values[(x << 8) | (z << 4) | localY] = biome
                    }
                }
            }
            outputLayers.append(BedrockBiomeLayer(baseY: baseY, biomeIDs: values, isAbsent: false))
            baseY += 16
        }
        return BedrockBiomeDocument(format: .data3D, heightMap: heightMap, layers: outputLayers)
    }

    static func emptyData3D(minimumY: Int = -64, maximumY: Int = 319) -> BedrockBiomeDocument {
        let source = BedrockBiomeDocument(
            format: .data2D,
            heightMap: Array(repeating: Int16(0), count: 256),
            layers: [BedrockBiomeLayer(baseY: nil, biomeIDs: Array(repeating: 0, count: 256), isAbsent: false)]
        )
        return source.expandedToData3D(minimumY: minimumY, maximumY: maximumY)
    }
}

extension BedrockSubChunk {
    func upgradedToModern(paletteVersion: Int32?) throws -> BedrockSubChunk {
        guard isLegacyNumeric else { return self }
        _ = paletteVersion ?? BedrockBlockState.defaultPaletteVersion
        let sourceStorages = storages.isEmpty
            ? [SubChunkStorage(bitsPerBlock: 0, palette: [BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)], indices: Array(repeating: 0, count: 4096))]
            : storages
        var converted = [SubChunkStorage]()
        converted.reserveCapacity(sourceStorages.count)
        for storage in sourceStorages {
            var palette = [BedrockBlockState]()
            var lookup = [Data: UInt16]()
            var remap = [UInt16: UInt16]()
            for (oldIndex, state) in storage.palette.enumerated() {
                // Never discard legacyData. Known ID/meta combinations are
                // converted to structured states; unknown metadata remains as
                // a versioned historical `val` entry so Bedrock can upgrade it
                // instead of MCBEEditor inventing states: {}.
                let modern = BedrockLegacyBlockStateConverter.stateForNumeric(state)
                let encoded = try BedrockNBTCodec.encode(
                    NBTDocument(rootName: "", root: modern.nbt ?? .compound([])),
                    encoding: .littleEndian
                )
                let newIndex: UInt16
                if let existing = lookup[encoded] {
                    newIndex = existing
                } else {
                    guard palette.count < Int(UInt16.max) else {
                        throw MCBEEditorError.unsupported("升级旧版 SubChunk 时调色板条目过多")
                    }
                    newIndex = UInt16(palette.count)
                    palette.append(modern)
                    lookup[encoded] = newIndex
                }
                remap[UInt16(oldIndex)] = newIndex
            }
            let indices = storage.indices.map { remap[$0] ?? 0 }
            converted.append(SubChunkStorage(
                bitsPerBlock: try modernBitsRequired(paletteCount: palette.count),
                palette: palette,
                indices: indices
            ))
        }
        return BedrockSubChunk(version: 9, yIndex: yIndex, storages: converted, trailingData: Data())
    }

    private func modernBitsRequired(paletteCount: Int) throws -> Int {
        guard paletteCount > 0 else { throw MCBEEditorError.malformedData("升级后的方块调色板不能为空") }
        if paletteCount == 1 { return 0 }
        let required = Int(ceil(log2(Double(paletteCount))))
        for bits in [1, 2, 3, 4, 5, 6, 8, 16] where bits >= required { return bits }
        throw MCBEEditorError.unsupported("升级后的方块调色板过大")
    }
}
