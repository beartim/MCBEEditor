import Foundation

/// The legacy second block layer stored beside numeric-ID SubChunks as
/// LevelChunkTag 0x34. Unlike v8/v9, v0/v2...v7 have only one block layer in
/// the 0x2F value; overlapping/waterlogged/extra blocks are persisted here.
///
/// Persistent value:
///   int32 count
///   repeated count times:
///     uint32 location  (x/z/y packed; high 16 bits historically unused)
///     uint8  blockID
///     uint8  blockData
///   optional unknown trailing bytes (preserved verbatim)
struct BedrockLegacyBlockExtraEntry: Equatable {
    let location: UInt32
    let blockID: UInt8
    let blockData: UInt8

    var x: Int { Int((location >> 12) & 0x0F) }
    var z: Int { Int((location >> 8) & 0x0F) }
    var absoluteY: Int { Int(location & 0xFF) }
    var subChunkY: Int8 { Int8(absoluteY >> 4) }
    var localY: Int { absoluteY & 0x0F }
    var linearIndex: Int { (x << 8) | (z << 4) | localY }

    static func location(x: Int, absoluteY: Int, z: Int) throws -> UInt32 {
        guard (0..<16).contains(x), (0..<16).contains(z), (0..<256).contains(absoluteY) else {
            throw MCBEEditorError.malformedData("LegacyBlockExtraData 坐标超出旧格式范围")
        }
        return UInt32((x << 12) | (z << 8) | absoluteY)
    }
}

struct BedrockLegacyBlockExtraData: Equatable {
    var entries: [BedrockLegacyBlockExtraEntry]
    var trailingData: Data

    static let empty = BedrockLegacyBlockExtraData(entries: [], trailingData: Data())

    static func decode(_ data: Data) throws -> BedrockLegacyBlockExtraData {
        var cursor = BinaryCursor(data: data)
        let signedCount = try cursor.readInt32LE()
        guard signedCount >= 0 else {
            throw MCBEEditorError.malformedData("LegacyBlockExtraData 条目数量为负数")
        }
        let count = Int(signedCount)
        guard count <= cursor.remaining / 6 else {
            throw MCBEEditorError.malformedData("LegacyBlockExtraData 条目数量超过剩余数据")
        }
        var entries = [BedrockLegacyBlockExtraEntry]()
        entries.reserveCapacity(count)
        for _ in 0..<count {
            let location = try cursor.readUInt32LE()
            let blockID = try cursor.readByte()
            let blockData = try cursor.readByte()
            entries.append(BedrockLegacyBlockExtraEntry(
                location: location, blockID: blockID, blockData: blockData
            ))
        }
        let trailing = try cursor.readData(count: cursor.remaining)
        return BedrockLegacyBlockExtraData(entries: entries, trailingData: trailing)
    }

    func encodePersistent() throws -> Data {
        guard entries.count <= Int(Int32.max) else {
            throw MCBEEditorError.malformedData("LegacyBlockExtraData 条目数量过多")
        }
        var writer = BinaryWriter()
        writer.writeInt32LE(Int32(entries.count))
        for entry in entries {
            writer.writeUInt32LE(entry.location)
            writer.writeByte(entry.blockID)
            writer.writeByte(entry.blockData)
        }
        writer.writeData(trailingData)
        return writer.data
    }

    var subChunkYIndices: Set<Int8> {
        Set(entries.map(\.subChunkY))
    }

    /// Builds the virtual layer-1 storage for one old numeric SubChunk.
    /// Nil means there are no extra blocks in this Y slice and no second layer
    /// needs to be materialised in the editor.
    func storage(subChunkY: Int8) -> SubChunkStorage? {
        let matching = entries.filter { $0.subChunkY == subChunkY }
        guard !matching.isEmpty else { return nil }

        let air = BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
        var palette = [air]
        var paletteLookup: [UInt16: UInt16] = [0: 0]
        var indices = Array(repeating: UInt16(0), count: 4096)
        for entry in matching {
            let pair = (UInt16(entry.blockID) << 8) | UInt16(entry.blockData)
            let paletteIndex: UInt16
            if let existing = paletteLookup[pair] {
                paletteIndex = existing
            } else {
                paletteIndex = UInt16(palette.count)
                paletteLookup[pair] = paletteIndex
                palette.append(BedrockBlockState(
                    nbt: nil, legacyID: UInt16(entry.blockID), legacyData: entry.blockData
                ))
            }
            indices[entry.linearIndex] = paletteIndex
        }
        return SubChunkStorage(bitsPerBlock: 8, palette: palette, indices: indices)
    }

    /// Replaces only the entries belonging to one virtual SubChunk Y. Entries
    /// from all other slices and any unknown trailing bytes remain untouched.
    mutating func replaceStorage(subChunkY: Int8, with storage: SubChunkStorage?) throws {
        guard (0...15).contains(Int(subChunkY)) else {
            throw MCBEEditorError.unsupported("LegacyBlockExtraData 只能表示 Y=0…255")
        }
        entries.removeAll { $0.subChunkY == subChunkY }
        guard let storage else { return }
        guard storage.indices.count == 4096, !storage.palette.isEmpty else {
            throw MCBEEditorError.malformedData("LegacyBlockExtraData layer 1 storage 无效")
        }

        var newEntries = [BedrockLegacyBlockExtraEntry]()
        newEntries.reserveCapacity(256)
        for x in 0..<16 {
            for z in 0..<16 {
                for localY in 0..<16 {
                    let index = (x << 8) | (z << 4) | localY
                    let paletteIndex = Int(storage.indices[index])
                    guard storage.palette.indices.contains(paletteIndex) else {
                        throw MCBEEditorError.malformedData("LegacyBlockExtraData 调色板索引越界")
                    }
                    let state = storage.palette[paletteIndex]
                    if state.isAir { continue }
                    guard let legacyID = state.legacyID, legacyID <= 255 else {
                        throw MCBEEditorError.unsupported("LegacyBlockExtraData 只能写入 0…255 数字 ID")
                    }
                    // 0x34 stores a full UInt8 data value (unlike the packed
                    // 4-bit metadata in v0/v2...v7 layer 0). Preserve all 256
                    // values so old extra-layer records round-trip losslessly.
                    let data = state.legacyData ?? 0
                    let absoluteY = Int(subChunkY) * 16 + localY
                    let location = try BedrockLegacyBlockExtraEntry.location(
                        x: x, absoluteY: absoluteY, z: z
                    )
                    newEntries.append(BedrockLegacyBlockExtraEntry(
                        location: location, blockID: UInt8(legacyID), blockData: data
                    ))
                }
            }
        }
        newEntries.sort { $0.location < $1.location }
        entries.append(contentsOf: newEntries)
    }
}
