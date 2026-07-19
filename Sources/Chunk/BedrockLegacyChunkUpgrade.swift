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
    static func plan(database: MojangLevelDB, position: ChunkPosition) throws -> BedrockLegacyChunkUpgradePlan {
        let dimensionProfile = try BedrockEmptyChunk.profile(
            database: database,
            dimension: position.dimension,
            preferLegacy: false
        )
        let paletteVersion = dimensionProfile.blockPaletteVersion
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
        let metadataDeletes = [
            BedrockDBKey(position: position, recordType: .legacyVersion, subChunkIndex: nil).encoded(),
            BedrockDBKey(position: position, recordType: .data2D, subChunkIndex: nil).encoded(),
            BedrockDBKey(position: position, recordType: .data2DLegacy, subChunkIndex: nil).encoded()
        ]

        var subChunkPuts = [(key: Data, value: Data)]()
        for rawY in Int(Int8.min)...Int(Int8.max) {
            guard let y = Int8(exactly: rawY) else { continue }
            let key = BedrockDBKey.subChunk(
                x: position.x,
                z: position.z,
                dimension: position.dimension,
                index: y
            )
            guard let raw = try database.get(key) else { continue }
            let decoded = try BedrockSubChunk.decode(raw, keyYIndex: y)
            guard decoded.isLegacyNumeric else { continue }
            let upgraded = try decoded.upgradedToModern(paletteVersion: paletteVersion)
            subChunkPuts.append((key: key, value: try upgraded.encodePersistent()))
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
    var isLegacyNumeric: Bool {
        [UInt8(0), 2, 3, 4, 5, 6, 7].contains(version)
    }

    func upgradedToModern(paletteVersion: Int32?) throws -> BedrockSubChunk {
        guard isLegacyNumeric else { return self }
        let version = paletteVersion ?? BedrockBlockState.defaultPaletteVersion
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
                let identifier = BedrockLegacyBlockCatalog.identifier(forNumericID: state.legacyID ?? 0) ?? state.name
                let modern = BedrockBlockState(nbt: .compound([
                    NBTNamedTag(name: "name", value: .string(identifier)),
                    NBTNamedTag(name: "states", value: .compound([])),
                    NBTNamedTag(name: "version", value: .int(version))
                ]), legacyID: nil, legacyData: nil)
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
