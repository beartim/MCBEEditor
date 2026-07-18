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
            guard count <= 16 else { throw BlocktopographError.malformedData("SubChunk v8 storage 数量无效：\(count)") }
            var storages = [SubChunkStorage]()
            for _ in 0..<count { storages.append(try decodePalettedStorage(cursor: &cursor)) }
            return BedrockSubChunk(version: version, yIndex: keyYIndex, storages: storages, trailingData: try cursor.readData(count: cursor.remaining))
        case 9:
            let count = Int(try cursor.readByte())
            let y = Int8(bitPattern: try cursor.readByte())
            guard count <= 16 else { throw BlocktopographError.malformedData("SubChunk v9 storage 数量无效：\(count)") }
            var storages = [SubChunkStorage]()
            for _ in 0..<count { storages.append(try decodePalettedStorage(cursor: &cursor)) }
            return BedrockSubChunk(version: version, yIndex: y, storages: storages, trailingData: try cursor.readData(count: cursor.remaining))
        case 0, 2...7:
            return try decodeLegacy(data, version: version, keyYIndex: keyYIndex)
        default:
            throw BlocktopographError.unsupported("SubChunk 版本 \(version)")
        }
    }

    private static func decodePalettedStorage(cursor: inout BinaryCursor) throws -> SubChunkStorage {
        let header = try cursor.readByte()
        let bitsPerBlock = Int(header >> 1)
        let isRuntimePalette = (header & 1) != 0
        guard !isRuntimePalette else {
            throw BlocktopographError.unsupported("网络运行时调色板不能从世界数据库独立解析")
        }
        let allowed = [0, 1, 2, 3, 4, 5, 6, 8, 16]
        guard allowed.contains(bitsPerBlock) else {
            throw BlocktopographError.malformedData("每方块位数无效：\(bitsPerBlock)")
        }

        var indices = Array(repeating: UInt16(0), count: 4096)
        if bitsPerBlock > 0 {
            let entriesPerWord = 32 / bitsPerBlock
            let wordCount = (4096 + entriesPerWord - 1) / entriesPerWord
            let mask: UInt32 = bitsPerBlock == 32 ? UInt32.max : (UInt32(1) << UInt32(bitsPerBlock)) - 1
            var outputIndex = 0
            for _ in 0..<wordCount {
                let word = try cursor.readUInt32LE()
                for slot in 0..<entriesPerWord where outputIndex < 4096 {
                    let shift = UInt32(slot * bitsPerBlock)
                    indices[outputIndex] = UInt16(truncatingIfNeeded: (word >> shift) & mask)
                    outputIndex += 1
                }
            }
        }

        let paletteCount = Int(try cursor.readInt32LE())
        guard paletteCount > 0, paletteCount <= 65_536 else {
            throw BlocktopographError.malformedData("调色板大小无效：\(paletteCount)")
        }
        var palette = [BedrockBlockState]()
        palette.reserveCapacity(paletteCount)
        for _ in 0..<paletteCount {
            let document = try BedrockNBTCodec.decodeDocument(cursor: &cursor, encoding: .littleEndian, maximumDepth: 64)
            guard document.root.type == .compound else {
                throw BlocktopographError.malformedData("方块状态不是 Compound")
            }
            palette.append(BedrockBlockState(nbt: document.root, legacyID: nil, legacyData: nil))
        }
        if let maxIndex = indices.max(), Int(maxIndex) >= palette.count {
            throw BlocktopographError.malformedData("调色板索引越界：\(maxIndex) >= \(palette.count)")
        }
        return SubChunkStorage(bitsPerBlock: bitsPerBlock, palette: palette, indices: indices)
    }

    private static func decodeLegacy(_ data: Data, version: UInt8, keyYIndex: Int8?) throws -> BedrockSubChunk {
        guard data.count >= 1 + 4096 else {
            throw BlocktopographError.malformedData("旧版 SubChunk 长度不足")
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
