import Foundation

enum BedrockBiomeFormat: String {
    case data3D = "Data3D"
    case data2D = "Data2D"
    case data2DLegacy = "Data2DLegacy"

    var recordType: ChunkRecordType {
        switch self {
        case .data3D: return .data3D
        case .data2D: return .data2D
        case .data2DLegacy: return .data2DLegacy
        }
    }
}

struct BedrockBiomeLayer: Equatable {
    /// Nil for 2D biome maps. Data3D layers use the inclusive base Y.
    let baseY: Int?
    var biomeIDs: [UInt32]
    var isAbsent: Bool

    var coordinateCount: Int { biomeIDs.count }
    var uniqueBiomeIDs: [UInt32] { Array(Set(biomeIDs)).sorted() }

    func coordinateText(for index: Int) -> String {
        guard index >= 0 && index < biomeIDs.count else { return "" }
        if let baseY = baseY {
            // Bedrock paletted biome storage follows the same X-Z-Y ordering as
            // block storage: index = x * 256 + z * 16 + localY.
            let x = index / 256
            let remainder = index % 256
            let z = remainder / 16
            let y = baseY + remainder % 16
            return "x=\(x) y=\(y) z=\(z)"
        }
        let x = index % 16
        let z = index / 16
        return "x=\(x) z=\(z)"
    }
}

struct BedrockBiomeDocument: Equatable {
    var format: BedrockBiomeFormat
    var heightMap: [Int16]
    var layers: [BedrockBiomeLayer]

    /// Data2DLegacy stores three auxiliary bytes after every biome byte. They
    /// are preserved byte-for-byte while the biome ID byte remains editable.
    private var legacyAuxiliaryBytes: Data
    private var trailingData: Data

    init(
        format: BedrockBiomeFormat,
        heightMap: [Int16],
        layers: [BedrockBiomeLayer],
        legacyAuxiliaryBytes: Data = Data(),
        trailingData: Data = Data()
    ) {
        self.format = format
        self.heightMap = heightMap
        self.layers = layers
        self.legacyAuxiliaryBytes = legacyAuxiliaryBytes
        self.trailingData = trailingData
    }

    static func decode(recordType: ChunkRecordType, data: Data) throws -> BedrockBiomeDocument {
        let format: BedrockBiomeFormat
        switch recordType {
        case .data3D: format = .data3D
        case .data2D: format = .data2D
        case .data2DLegacy: format = .data2DLegacy
        default:
            throw BlocktopographError.unsupported("\(recordType.displayName) 不是可编辑的生物群系记录")
        }
        guard data.count >= 512 else {
            throw BlocktopographError.malformedData("\(format.rawValue) 少于 512 字节高度图")
        }

        var cursor = BinaryCursor(data: data)
        var heights = [Int16]()
        heights.reserveCapacity(256)
        for _ in 0..<256 { heights.append(try cursor.readInt16LE()) }

        switch format {
        case .data2D:
            guard cursor.remaining >= 256 else {
                throw BlocktopographError.malformedData("Data2D 缺少 256 个生物群系 ID")
            }
            var ids = [UInt32]()
            ids.reserveCapacity(256)
            for _ in 0..<256 { ids.append(UInt32(try cursor.readByte())) }
            let trailing = try cursor.readData(count: cursor.remaining)
            return BedrockBiomeDocument(
                format: format,
                heightMap: heights,
                layers: [BedrockBiomeLayer(baseY: nil, biomeIDs: ids, isAbsent: false)],
                trailingData: trailing
            )

        case .data2DLegacy:
            guard cursor.remaining >= 1024 else {
                throw BlocktopographError.malformedData("Data2DLegacy 缺少 256×4 生物群系记录")
            }
            var ids = [UInt32]()
            ids.reserveCapacity(256)
            var auxiliary = Data()
            auxiliary.reserveCapacity(256 * 3)
            for _ in 0..<256 {
                ids.append(UInt32(try cursor.readByte()))
                auxiliary.append(try cursor.readData(count: 3))
            }
            let trailing = try cursor.readData(count: cursor.remaining)
            return BedrockBiomeDocument(
                format: format,
                heightMap: heights,
                layers: [BedrockBiomeLayer(baseY: nil, biomeIDs: ids, isAbsent: false)],
                legacyAuxiliaryBytes: auxiliary,
                trailingData: trailing
            )

        case .data3D:
            var layers = [BedrockBiomeLayer]()
            var baseY = -64
            while !cursor.isAtEnd {
                let header = try cursor.readByte()
                if header == 0xff {
                    layers.append(BedrockBiomeLayer(
                        baseY: baseY,
                        biomeIDs: Array(repeating: 0, count: 4096),
                        isAbsent: true
                    ))
                    baseY += 16
                    continue
                }

                let bits = Int(header >> 1)
                guard [0, 1, 2, 3, 4, 5, 6, 8, 16].contains(bits) else {
                    throw BlocktopographError.unsupported("Data3D 生物群系位宽 \(bits) 不受支持")
                }

                var paletteIndices = [Int](repeating: 0, count: 4096)
                var palette = [UInt32]()
                if bits == 0 {
                    palette = [try cursor.readUInt32LE()]
                } else {
                    let valuesPerWord = 32 / bits
                    let wordCount = (4096 + valuesPerWord - 1) / valuesPerWord
                    let mask: UInt32 = bits == 32 ? UInt32.max : (UInt32(1) << UInt32(bits)) - 1
                    var outputIndex = 0
                    for _ in 0..<wordCount {
                        let word = try cursor.readUInt32LE()
                        for slot in 0..<valuesPerWord where outputIndex < 4096 {
                            paletteIndices[outputIndex] = Int((word >> UInt32(slot * bits)) & mask)
                            outputIndex += 1
                        }
                    }
                    let paletteCount = Int(try cursor.readInt32LE())
                    guard paletteCount > 0 && paletteCount <= 65_536 else {
                        throw BlocktopographError.malformedData("Data3D 调色板长度无效：\(paletteCount)")
                    }
                    palette.reserveCapacity(paletteCount)
                    for _ in 0..<paletteCount { palette.append(try cursor.readUInt32LE()) }
                }

                var values = [UInt32]()
                values.reserveCapacity(4096)
                for index in paletteIndices {
                    guard palette.indices.contains(index) else {
                        throw BlocktopographError.malformedData("Data3D 生物群系索引 \(index) 超出调色板")
                    }
                    values.append(palette[index])
                }
                layers.append(BedrockBiomeLayer(baseY: baseY, biomeIDs: values, isAbsent: false))
                baseY += 16
            }
            return BedrockBiomeDocument(format: format, heightMap: heights, layers: layers)
        }
    }

    func encoded() throws -> Data {
        guard heightMap.count == 256 else {
            throw BlocktopographError.malformedData("生物群系高度图必须包含 256 项")
        }
        var writer = BinaryWriter()
        for value in heightMap { writer.writeInt16LE(value) }

        switch format {
        case .data2D:
            guard layers.count == 1, layers[0].biomeIDs.count == 256 else {
                throw BlocktopographError.malformedData("Data2D 必须包含 256 个生物群系 ID")
            }
            for id in layers[0].biomeIDs {
                guard id <= UInt32(UInt8.max) else {
                    throw BlocktopographError.malformedData("Data2D 生物群系 ID \(id) 超出 UInt8")
                }
                writer.writeByte(UInt8(id))
            }
            writer.writeData(trailingData)

        case .data2DLegacy:
            guard layers.count == 1, layers[0].biomeIDs.count == 256,
                  legacyAuxiliaryBytes.count == 256 * 3 else {
                throw BlocktopographError.malformedData("Data2DLegacy 数据长度无效")
            }
            for index in 0..<256 {
                let id = layers[0].biomeIDs[index]
                guard id <= UInt32(UInt8.max) else {
                    throw BlocktopographError.malformedData("Data2DLegacy 生物群系 ID \(id) 超出 UInt8")
                }
                writer.writeByte(UInt8(id))
                let start = index * 3
                writer.writeData(legacyAuxiliaryBytes.subdata(in: start..<(start + 3)))
            }
            writer.writeData(trailingData)

        case .data3D:
            for layer in layers {
                guard layer.biomeIDs.count == 4096 else {
                    throw BlocktopographError.malformedData("Data3D 每层必须包含 4096 个生物群系 ID")
                }
                if layer.isAbsent {
                    writer.writeByte(0xff)
                    continue
                }
                try Self.encodePalettedLayer(layer.biomeIDs, into: &writer)
            }
        }
        return writer.data
    }

    mutating func updateBiomeID(layerIndex: Int, valueIndex: Int, id: UInt32) throws {
        guard layers.indices.contains(layerIndex), layers[layerIndex].biomeIDs.indices.contains(valueIndex) else {
            throw BlocktopographError.malformedData("生物群系位置越界")
        }
        layers[layerIndex].biomeIDs[valueIndex] = id
        layers[layerIndex].isAbsent = false
    }

    mutating func fillLayer(_ layerIndex: Int, id: UInt32) throws {
        guard layers.indices.contains(layerIndex) else {
            throw BlocktopographError.malformedData("生物群系层越界")
        }
        layers[layerIndex].biomeIDs = Array(repeating: id, count: layers[layerIndex].biomeIDs.count)
        layers[layerIndex].isAbsent = false
    }

    private static func encodePalettedLayer(_ values: [UInt32], into writer: inout BinaryWriter) throws {
        var palette = [UInt32]()
        var lookup = [UInt32: Int]()
        var indices = [Int]()
        indices.reserveCapacity(values.count)
        for value in values {
            if let index = lookup[value] {
                indices.append(index)
            } else {
                let index = palette.count
                guard index < 65_536 else {
                    throw BlocktopographError.unsupported("Data3D 生物群系调色板超过 65536 项")
                }
                palette.append(value)
                lookup[value] = index
                indices.append(index)
            }
        }

        let bits: Int
        switch palette.count {
        case 0...1: bits = 0
        case 2: bits = 1
        case 3...4: bits = 2
        case 5...8: bits = 3
        case 9...16: bits = 4
        case 17...32: bits = 5
        case 33...64: bits = 6
        case 65...256: bits = 8
        default: bits = 16
        }
        writer.writeByte(UInt8(bits << 1))
        if bits == 0 {
            writer.writeUInt32LE(palette.first ?? 0)
            return
        }

        let valuesPerWord = 32 / bits
        let wordCount = (4096 + valuesPerWord - 1) / valuesPerWord
        for wordIndex in 0..<wordCount {
            var word: UInt32 = 0
            for slot in 0..<valuesPerWord {
                let index = wordIndex * valuesPerWord + slot
                guard index < indices.count else { break }
                word |= UInt32(indices[index]) << UInt32(slot * bits)
            }
            writer.writeUInt32LE(word)
        }
        writer.writeInt32LE(Int32(palette.count))
        for value in palette { writer.writeUInt32LE(value) }
    }
}

extension BedrockBiomeDocument {
    /// Returns the biome numeric ID at one local block coordinate. Data3D uses
    /// the vertical layer containing `y`; 2D formats ignore Y.
    func biomeID(localX: Int, y: Int, localZ: Int) -> UInt32? {
        guard (0..<16).contains(localX), (0..<16).contains(localZ) else { return nil }
        switch format {
        case .data2D, .data2DLegacy:
            guard let layer = layers.first else { return nil }
            let index = localZ * 16 + localX
            return layer.biomeIDs.indices.contains(index) ? layer.biomeIDs[index] : nil
        case .data3D:
            guard let layerIndex = layers.firstIndex(where: { layer in
                guard let baseY = layer.baseY else { return false }
                return y >= baseY && y <= baseY + 15
            }) else {
                // Old or truncated Data3D records may not cover the requested
                // surface height. Use the nearest saved layer rather than
                // hiding the entire biome map.
                let saved = layers.enumerated().filter { !$0.element.isAbsent && $0.element.baseY != nil }
                guard let nearest = saved.min(by: {
                    abs(($0.element.baseY ?? 0) - y) < abs(($1.element.baseY ?? 0) - y)
                }) else { return nil }
                return biomeID(inLayer: nearest.offset, localX: localX, localY: 0, localZ: localZ)
            }
            let baseY = layers[layerIndex].baseY ?? y
            return biomeID(inLayer: layerIndex, localX: localX, localY: y - baseY, localZ: localZ)
        }
    }

    private func biomeID(inLayer layerIndex: Int, localX: Int, localY: Int, localZ: Int) -> UInt32? {
        guard layers.indices.contains(layerIndex), (0..<16).contains(localY) else { return nil }
        let index = localX * 256 + localZ * 16 + localY
        let values = layers[layerIndex].biomeIDs
        return values.indices.contains(index) ? values[index] : nil
    }
}
