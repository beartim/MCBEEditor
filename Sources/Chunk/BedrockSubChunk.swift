import Foundation

struct BedrockBlockState {
    /// Fallback block-state schema version used when a world does not yet
    /// contain a palette from which the exact version can be inferred.
    static let defaultPaletteVersion: Int32 = 18_153_728 // 1.21.1.0

    let nbt: NBTValue?
    let legacyID: UInt16?
    let legacyData: UInt8?

    var name: String {
        if let nbt = nbt {
            return nbt.stringValue(named: "name")
                ?? nbt.stringValue(named: "Name")
                ?? "minecraft:unknown"
        }
        if let legacyID = legacyID {
            return BedrockLegacyBlockCatalog.identifier(forNumericID: legacyID)
                ?? "legacy:\(legacyID):\(legacyData ?? 0)"
        }
        return "minecraft:unknown"
    }

    var identifierDescription: String {
        guard let legacyID = legacyID else { return name }
        return "\(name) · 数字 ID \(legacyID):\(legacyData ?? 0)"
    }

    var isAir: Bool {
        let value = name.lowercased()
        return value == "minecraft:air" || value == "minecraft:cave_air" || value == "minecraft:void_air" || value == "legacy:0:0"
    }

    var paletteVersion: Int32? {
        nbt?.intValue(named: "version") ?? nbt?.intValue(named: "Version")
    }

    static func editableAir(version: Int32?) -> BedrockBlockState {
        var tags = [
            NBTNamedTag(name: "name", value: .string("minecraft:air")),
            NBTNamedTag(name: "states", value: .compound([]))
        ]
        tags.append(NBTNamedTag(name: "version", value: .int(version ?? defaultPaletteVersion)))
        return BedrockBlockState(nbt: .compound(tags), legacyID: nil, legacyData: nil)
    }
}

extension BedrockSubChunk {
    /// Creates a format-complete numeric-ID SubChunk for v0/v2...v7.
    /// The 4,096-byte tail reserves the two legacy light nibble arrays.
    static func emptyLegacy(version: UInt8, yIndex: Int8?) throws -> BedrockSubChunk {
        guard [UInt8(0), 2, 3, 4, 5, 6, 7].contains(version) else {
            throw MCBEEditorError.unsupported("SubChunk v\(version) 不是旧版数字 ID 格式")
        }
        let air = BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
        return BedrockSubChunk(
            version: version,
            yIndex: yIndex,
            storages: [SubChunkStorage(
                bitsPerBlock: 8,
                palette: [air],
                indices: Array(repeating: UInt16(0), count: 4096)
            )],
            // SkyLight + BlockLight, each 2,048 packed nibbles. Existing records
            // preserve their exact bytes; zeros are only used for newly-created
            // empty legacy records and can be recalculated by the game.
            trailingData: Data(repeating: 0, count: 4096)
        )
    }
}

struct SubChunkStorage {
    let bitsPerBlock: Int
    let palette: [BedrockBlockState]
    let indices: [UInt16]

    func blockState(x: Int, y: Int, z: Int) -> BedrockBlockState? {
        guard (0..<16).contains(x), (0..<16).contains(y), (0..<16).contains(z) else { return nil }
        let index = (x << 8) | (z << 4) | y
        guard index < indices.count else { return nil }
        let paletteIndex = Int(indices[index])
        guard paletteIndex < palette.count else { return nil }
        return palette[paletteIndex]
    }
}

struct BedrockSubChunk {
    let version: UInt8
    let yIndex: Int8?
    let storages: [SubChunkStorage]
    let trailingData: Data

    static func decode(_ data: Data, keyYIndex: Int8? = nil) throws -> BedrockSubChunk {
        var cursor = BinaryCursor(data: data)
        let version = try cursor.readByte()
        switch version {
        case 1:
            let storage = try decodePalettedStorage(cursor: &cursor)
            return BedrockSubChunk(version: version, yIndex: keyYIndex, storages: [storage], trailingData: try cursor.readData(count: cursor.remaining))
        case 8:
            let count = Int(try cursor.readByte())
            guard count <= 16 else { throw MCBEEditorError.malformedData("SubChunk v8 storage 数量无效：\(count)") }
            var storages = [SubChunkStorage]()
            for _ in 0..<count { storages.append(try decodePalettedStorage(cursor: &cursor)) }
            return BedrockSubChunk(version: version, yIndex: keyYIndex, storages: storages, trailingData: try cursor.readData(count: cursor.remaining))
        case 9:
            let count = Int(try cursor.readByte())
            let y = Int8(bitPattern: try cursor.readByte())
            guard count <= 16 else { throw MCBEEditorError.malformedData("SubChunk v9 storage 数量无效：\(count)") }
            var storages = [SubChunkStorage]()
            for _ in 0..<count { storages.append(try decodePalettedStorage(cursor: &cursor)) }
            return BedrockSubChunk(version: version, yIndex: y, storages: storages, trailingData: try cursor.readData(count: cursor.remaining))
        case 0, 2...7:
            return try decodeLegacy(data, version: version, keyYIndex: keyYIndex)
        default:
            throw MCBEEditorError.unsupported("SubChunk 版本 \(version)")
        }
    }

    private static func decodePalettedStorage(cursor: inout BinaryCursor) throws -> SubChunkStorage {
        let header = try cursor.readByte()
        let bitsPerBlock = Int(header >> 1)
        let isRuntimePalette = (header & 1) != 0
        guard !isRuntimePalette else {
            throw MCBEEditorError.unsupported("网络运行时调色板不能从世界数据库独立解析")
        }
        let allowed = [0, 1, 2, 3, 4, 5, 6, 8, 16]
        guard allowed.contains(bitsPerBlock) else {
            throw MCBEEditorError.malformedData("每方块位数无效：\(bitsPerBlock)")
        }

        var indices = Array(repeating: UInt16(0), count: 4096)

        // Persistence storage type 0 is a special single-value encoding. It
        // contains the one NBT palette entry directly and does NOT carry the
        // int32 palette-size field used by non-zero bit widths. This form is
        // common for all-air/all-one-block v1/v8/v9 SubChunks.
        if bitsPerBlock == 0 {
            let document = try BedrockNBTCodec.decodeDocument(
                cursor: &cursor, encoding: .littleEndian, maximumDepth: 64
            )
            guard document.root.type == .compound else {
                throw MCBEEditorError.malformedData("方块状态不是 Compound")
            }
            return SubChunkStorage(
                bitsPerBlock: 0,
                palette: [BedrockBlockState(nbt: document.root, legacyID: nil, legacyData: nil)],
                indices: indices
            )
        }

        let entriesPerWord = 32 / bitsPerBlock
        let wordCount = (4096 + entriesPerWord - 1) / entriesPerWord
        let mask: UInt32 = (UInt32(1) << UInt32(bitsPerBlock)) - 1
        var outputIndex = 0
        for _ in 0..<wordCount {
            let word = try cursor.readUInt32LE()
            for slot in 0..<entriesPerWord where outputIndex < 4096 {
                let shift = UInt32(slot * bitsPerBlock)
                indices[outputIndex] = UInt16(truncatingIfNeeded: (word >> shift) & mask)
                outputIndex += 1
            }
        }

        let paletteCount = Int(try cursor.readInt32LE())
        guard paletteCount > 0, paletteCount <= 65_536 else {
            throw MCBEEditorError.malformedData("调色板大小无效：\(paletteCount)")
        }
        var palette = [BedrockBlockState]()
        palette.reserveCapacity(paletteCount)
        for _ in 0..<paletteCount {
            let document = try BedrockNBTCodec.decodeDocument(cursor: &cursor, encoding: .littleEndian, maximumDepth: 64)
            guard document.root.type == .compound else {
                throw MCBEEditorError.malformedData("方块状态不是 Compound")
            }
            palette.append(BedrockBlockState(nbt: document.root, legacyID: nil, legacyData: nil))
        }
        if let maxIndex = indices.max(), Int(maxIndex) >= palette.count {
            throw MCBEEditorError.malformedData("调色板索引越界：\(maxIndex) >= \(palette.count)")
        }
        return SubChunkStorage(bitsPerBlock: bitsPerBlock, palette: palette, indices: indices)
    }

    private static func decodeLegacy(_ data: Data, version: UInt8, keyYIndex: Int8?) throws -> BedrockSubChunk {
        guard data.count >= 1 + 4096 else {
            throw MCBEEditorError.malformedData("旧版 SubChunk 长度不足")
        }
        let ids = data.subdata(in: 1..<(1 + 4096))
        let metadataStart = 1 + 4096
        let hasMetadata = data.count >= metadataStart + 2048
        let metadata = hasMetadata ? data.subdata(in: metadataStart..<(metadataStart + 2048)) : Data()

        var paletteMap = [UInt32: UInt16]()
        var palette = [BedrockBlockState]()
        var indices = Array(repeating: UInt16(0), count: 4096)
        for index in 0..<4096 {
            let id = UInt16(ids[index])
            let packed = hasMetadata ? metadata[index / 2] : 0
            let meta: UInt8 = index % 2 == 0 ? packed & 0x0f : packed >> 4
            let key = (UInt32(id) << 8) | UInt32(meta)
            let paletteIndex: UInt16
            if let existing = paletteMap[key] {
                paletteIndex = existing
            } else {
                paletteIndex = UInt16(palette.count)
                paletteMap[key] = paletteIndex
                palette.append(BedrockBlockState(nbt: nil, legacyID: id, legacyData: meta))
            }
            indices[index] = paletteIndex
        }
        let storage = SubChunkStorage(bitsPerBlock: 8, palette: palette, indices: indices)
        let consumed = hasMetadata ? metadataStart + 2048 : metadataStart
        let trailing = consumed < data.count ? data.subdata(in: consumed..<data.count) : Data()
        return BedrockSubChunk(version: version, yIndex: keyYIndex, storages: [storage], trailingData: trailing)
    }
}


extension BedrockBlockState {
    var stateProperties: [(String, String)] {
        guard let nbt = nbt,
              case .compound(let tags)? = nbt.compoundValue(named: "states") else {
            return []
        }
        return tags
            .map { ($0.name, $0.value.summary) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    var statePropertiesDescription: String {
        let properties = stateProperties
        guard !properties.isEmpty else { return "无方块状态" }
        return properties.map { "\($0.0) = \($0.1)" }.joined(separator: "\n")
    }
}

// MARK: - Pre-Anvil Bedrock LegacyTerrain (LevelChunkTag 0x30)

/// Chunk storage used by very old Pocket/Bedrock worlds (including 0.10.x).
/// One LevelDB value stores the complete 16×128×16 terrain column instead of
/// eight independent SubChunkPrefix records.
///
/// Persistent layout (83,200 bytes):
///   32,768 BlockIDs, 16,384 Data nibbles, 16,384 SkyLight nibbles,
///   16,384 BlockLight nibbles, 256 height-map bytes and 1,024 biome/color bytes.
///
/// MCBEEditor exposes the terrain internally as eight virtual numeric-ID v0
/// SubChunks. Only BlockIDs/Data are changed by block editing; light, height
/// map and biome/color bytes are preserved byte-for-byte on write-back.

// MARK: - Persistent SubChunk encoding

extension BedrockSubChunk {
    func encodePersistent() throws -> Data {
        if [UInt8(0), 2, 3, 4, 5, 6, 7].contains(version) {
            return try encodeLegacyPersistent()
        }
        guard [UInt8(1), 8, 9].contains(version) else {
            throw MCBEEditorError.unsupported("SubChunk v\(version) 暂不支持重新编码")
        }
        if version == 1, storages.count != 1 {
            throw MCBEEditorError.malformedData("SubChunk v1 必须恰好包含一个 storage")
        }
        guard storages.count <= Int(UInt8.max) else {
            throw MCBEEditorError.malformedData("SubChunk storage 数量过多")
        }

        var writer = BinaryWriter()
        writer.writeByte(version)
        if version == 8 || version == 9 {
            writer.writeByte(UInt8(storages.count))
        }
        if version == 9 {
            writer.writeByte(UInt8(bitPattern: yIndex ?? 0))
        }
        for storage in storages {
            try Self.encode(storage: storage, writer: &writer)
        }
        writer.writeData(trailingData)
        return writer.data
    }

    private func encodeLegacyPersistent() throws -> Data {
        guard storages.count == 1 else {
            throw MCBEEditorError.malformedData("旧版 SubChunk 必须恰好包含一个 storage")
        }
        let storage = storages[0]
        guard storage.indices.count == 4096, !storage.palette.isEmpty else {
            throw MCBEEditorError.malformedData("旧版 SubChunk 方块数据无效")
        }

        var ids = Data(repeating: 0, count: 4096)
        var metadata = Data(repeating: 0, count: 2048)
        for blockIndex in 0..<4096 {
            let paletteIndex = Int(storage.indices[blockIndex])
            guard storage.palette.indices.contains(paletteIndex),
                  let legacyID = storage.palette[paletteIndex].legacyID,
                  legacyID <= 255 else {
                throw MCBEEditorError.malformedData("旧版 SubChunk 调色板包含非数字 ID 方块")
            }
            let legacyData = storage.palette[paletteIndex].legacyData ?? 0
            guard legacyData <= 15 else {
                throw MCBEEditorError.malformedData("旧版方块数据值必须为 0…15")
            }
            ids[blockIndex] = UInt8(legacyID)
            let metadataIndex = blockIndex / 2
            if blockIndex % 2 == 0 {
                metadata[metadataIndex] = (metadata[metadataIndex] & 0xf0) | legacyData
            } else {
                metadata[metadataIndex] = (metadata[metadataIndex] & 0x0f) | (legacyData << 4)
            }
        }

        var output = Data([version])
        output.append(ids)
        output.append(metadata)
        output.append(trailingData)
        return output
    }

    private static func encode(storage: SubChunkStorage, writer: inout BinaryWriter) throws {
        let bits = storage.bitsPerBlock
        let allowed = [0, 1, 2, 3, 4, 5, 6, 8, 16]
        guard allowed.contains(bits) else {
            throw MCBEEditorError.malformedData("不支持的每方块位数：\(bits)")
        }
        guard storage.indices.count == 4096 else {
            throw MCBEEditorError.malformedData("storage 必须包含 4096 个方块索引")
        }
        guard !storage.palette.isEmpty, storage.palette.count <= Int(Int32.max) else {
            throw MCBEEditorError.malformedData("方块调色板大小无效")
        }
        let capacity = bits == 0 ? 1 : (1 << bits)
        guard storage.palette.count <= capacity else {
            throw MCBEEditorError.malformedData("调色板大小超过 \(bits) 位索引容量")
        }

        // Persistence palette: low bit is 0. The high seven bits store bits-per-block.
        writer.writeByte(UInt8(bits << 1))

        // Type 0 persists exactly one NBT state directly. Unlike non-zero
        // storage types, there is no int32 palette count in this encoding.
        if bits == 0 {
            guard storage.palette.count == 1, let nbt = storage.palette[0].nbt else {
                throw MCBEEditorError.malformedData("0 位 storage 必须恰好包含一个现代方块状态")
            }
            writer.writeData(try BedrockNBTCodec.encode(
                NBTDocument(rootName: "", root: nbt),
                encoding: .littleEndian
            ))
            return
        }

        let entriesPerWord = 32 / bits
        let wordCount = (4096 + entriesPerWord - 1) / entriesPerWord
        let mask: UInt32 = (UInt32(1) << UInt32(bits)) - 1
        for wordIndex in 0..<wordCount {
            var word: UInt32 = 0
            for slot in 0..<entriesPerWord {
                let sourceIndex = wordIndex * entriesPerWord + slot
                guard sourceIndex < storage.indices.count else { break }
                let paletteIndex = UInt32(storage.indices[sourceIndex])
                guard paletteIndex < UInt32(storage.palette.count) else {
                    throw MCBEEditorError.malformedData("方块调色板索引越界：\(paletteIndex)")
                }
                word |= (paletteIndex & mask) << UInt32(slot * bits)
            }
            writer.writeUInt32LE(word)
        }

        writer.writeInt32LE(Int32(storage.palette.count))
        for state in storage.palette {
            guard let nbt = state.nbt else {
                throw MCBEEditorError.unsupported("现代持久化调色板不能写入旧版数字 ID 方块")
            }
            writer.writeData(try BedrockNBTCodec.encode(
                NBTDocument(rootName: "", root: nbt),
                encoding: .littleEndian
            ))
        }
    }
}

struct BedrockLegacyTerrain {
    static let blockIDCount = 32_768
    static let nibbleCount = 16_384
    static let heightMapCount = 256
    static let biomeColorCount = 1_024
    static let persistentByteCount = 83_200

    var blockIDs: Data
    var dataValues: Data
    var skyLight: Data
    var blockLight: Data
    var heightMap: Data
    var biomeColors: Data
    var trailingData: Data

    static var emptyPersistentData: Data {
        var output = Data(repeating: 0, count: persistentByteCount)
        // SkyLight occupies the third 16,384-byte nibble array and an empty
        // exposed column is naturally full-bright. Other fields remain zero.
        let skyStart = blockIDCount + nibbleCount
        output.replaceSubrange(skyStart..<(skyStart + nibbleCount), with: repeatElement(UInt8(0xff), count: nibbleCount))
        return output
    }

    static func empty() -> BedrockLegacyTerrain {
        // Keep this constructor and the raw empty record byte-identical.
        // Decode is infallible for the fixed-size buffer, but spell the fields
        // out to avoid a throwing API in callers constructing empty chunks.
        BedrockLegacyTerrain(
            blockIDs: Data(repeating: 0, count: blockIDCount),
            dataValues: Data(repeating: 0, count: nibbleCount),
            // Air columns are initially exposed to full skylight; block light is zero.
            skyLight: Data(repeating: 0xff, count: nibbleCount),
            blockLight: Data(repeating: 0, count: nibbleCount),
            heightMap: Data(repeating: 0, count: heightMapCount),
            biomeColors: Data(repeating: 0, count: biomeColorCount),
            trailingData: Data()
        )
    }

    static func decode(_ data: Data) throws -> BedrockLegacyTerrain {
        guard data.count >= persistentByteCount else {
            throw MCBEEditorError.malformedData("LegacyTerrain 长度不足：\(data.count)，至少需要 \(persistentByteCount) 字节")
        }
        var offset = 0
        func take(_ count: Int) -> Data {
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }
        let ids = take(blockIDCount)
        let metadata = take(nibbleCount)
        let sky = take(nibbleCount)
        let block = take(nibbleCount)
        let heights = take(heightMapCount)
        let biomes = take(biomeColorCount)
        let trailing = offset < data.count ? data.subdata(in: offset..<data.count) : Data()
        return BedrockLegacyTerrain(
            blockIDs: ids,
            dataValues: metadata,
            skyLight: sky,
            blockLight: block,
            heightMap: heights,
            biomeColors: biomes,
            trailingData: trailing
        )
    }

    func encodePersistent() throws -> Data {
        guard blockIDs.count == Self.blockIDCount,
              dataValues.count == Self.nibbleCount,
              skyLight.count == Self.nibbleCount,
              blockLight.count == Self.nibbleCount,
              heightMap.count == Self.heightMapCount,
              biomeColors.count == Self.biomeColorCount else {
            throw MCBEEditorError.malformedData("LegacyTerrain 内部字段长度无效")
        }
        var output = Data()
        output.reserveCapacity(Self.persistentByteCount + trailingData.count)
        output.append(blockIDs)
        output.append(dataValues)
        output.append(skyLight)
        output.append(blockLight)
        output.append(heightMap)
        output.append(biomeColors)
        output.append(trailingData)
        return output
    }

    /// Old full-chunk block arrays are X-Z-Y ordered, with Y spanning 0...127.
    private static func terrainBlockIndex(x: Int, y: Int, z: Int) -> Int {
        (x << 11) | (z << 7) | y
    }

    private static func subChunkBlockIndex(x: Int, y: Int, z: Int) -> Int {
        (x << 8) | (z << 4) | y
    }

    private func metadata(at blockIndex: Int) -> UInt8 {
        let packed = dataValues[blockIndex >> 1]
        return blockIndex & 1 == 0 ? packed & 0x0f : packed >> 4
    }

    private mutating func setMetadata(_ value: UInt8, at blockIndex: Int) {
        let byteIndex = blockIndex >> 1
        if blockIndex & 1 == 0 {
            dataValues[byteIndex] = (dataValues[byteIndex] & 0xf0) | (value & 0x0f)
        } else {
            dataValues[byteIndex] = (dataValues[byteIndex] & 0x0f) | ((value & 0x0f) << 4)
        }
    }

    func subChunk(yIndex: Int8) throws -> BedrockSubChunk {
        let slice = Int(yIndex)
        guard (0..<8).contains(slice) else {
            throw MCBEEditorError.malformedData("LegacyTerrain 只包含 SubChunk Y=0…7")
        }

        var paletteMap = [UInt32: UInt16]()
        var palette = [BedrockBlockState]()
        var indices = Array(repeating: UInt16(0), count: 4096)
        for x in 0..<16 {
            for z in 0..<16 {
                for localY in 0..<16 {
                    let absoluteY = slice * 16 + localY
                    let sourceIndex = Self.terrainBlockIndex(x: x, y: absoluteY, z: z)
                    let id = UInt16(blockIDs[sourceIndex])
                    let meta = metadata(at: sourceIndex)
                    let paletteKey = (UInt32(id) << 8) | UInt32(meta)
                    let paletteIndex: UInt16
                    if let existing = paletteMap[paletteKey] {
                        paletteIndex = existing
                    } else {
                        guard palette.count < Int(UInt16.max) else {
                            throw MCBEEditorError.malformedData("LegacyTerrain 数字方块调色板过大")
                        }
                        paletteIndex = UInt16(palette.count)
                        paletteMap[paletteKey] = paletteIndex
                        palette.append(BedrockBlockState(nbt: nil, legacyID: id, legacyData: meta))
                    }
                    indices[Self.subChunkBlockIndex(x: x, y: localY, z: z)] = paletteIndex
                }
            }
        }
        return BedrockSubChunk(
            version: 0,
            yIndex: yIndex,
            storages: [SubChunkStorage(bitsPerBlock: 8, palette: palette, indices: indices)],
            trailingData: Data()
        )
    }

    mutating func replaceSubChunk(yIndex: Int8, with subChunk: BedrockSubChunk) throws {
        let slice = Int(yIndex)
        guard (0..<8).contains(slice) else {
            throw MCBEEditorError.malformedData("LegacyTerrain 只包含 SubChunk Y=0…7")
        }
        guard [UInt8(0), 2, 3, 4, 5, 6, 7].contains(subChunk.version), subChunk.storages.count == 1 else {
            throw MCBEEditorError.unsupported("LegacyTerrain 只能直接写回旧版数字 ID 方块；现代方块状态需要先升级整个区块")
        }
        let storage = subChunk.storages[0]
        guard storage.indices.count == 4096 else {
            throw MCBEEditorError.malformedData("LegacyTerrain 虚拟 SubChunk 必须包含 4096 个方块")
        }
        for x in 0..<16 {
            for z in 0..<16 {
                for localY in 0..<16 {
                    let sourceIndex = Self.subChunkBlockIndex(x: x, y: localY, z: z)
                    let paletteIndex = Int(storage.indices[sourceIndex])
                    guard storage.palette.indices.contains(paletteIndex),
                          let id = storage.palette[paletteIndex].legacyID,
                          id <= 255 else {
                        throw MCBEEditorError.malformedData("LegacyTerrain 不能写入非 0…255 数字 ID 方块")
                    }
                    let meta = storage.palette[paletteIndex].legacyData ?? 0
                    guard meta <= 15 else {
                        throw MCBEEditorError.malformedData("LegacyTerrain 方块数据值必须为 0…15")
                    }
                    let absoluteY = slice * 16 + localY
                    let targetIndex = Self.terrainBlockIndex(x: x, y: absoluteY, z: z)
                    blockIDs[targetIndex] = UInt8(id)
                    setMetadata(meta, at: targetIndex)
                }
            }
        }
    }

    func biomeID(localX: Int, localZ: Int) -> UInt32? {
        guard (0..<16).contains(localX), (0..<16).contains(localZ) else { return nil }
        let offset = (localZ * 16 + localX) * 4
        guard offset < biomeColors.count else { return nil }
        // The first byte in each legacy 4-byte biome/color sample is the biome ID.
        return UInt32(biomeColors[offset])
    }

    func height(localX: Int, localZ: Int) -> Int16? {
        guard (0..<16).contains(localX), (0..<16).contains(localZ) else { return nil }
        let index = localZ * 16 + localX
        guard heightMap.indices.contains(index) else { return nil }
        return Int16(heightMap[index])
    }
}
