import Foundation

struct BedrockBlockRecord {
    let x: Int64
    let y: Int32
    let z: Int64
    let dimension: Int32
    let layers: [BedrockBlockState]
    let isGenerated: Bool

    var primaryState: BedrockBlockState {
        layers.first(where: { !$0.isAir })
            ?? layers.first
            ?? BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
    }

    var name: String { primaryState.name }

    static let editableLayerCount = 2

    func stateForEditing(layer index: Int) -> BedrockBlockState {
        if layers.indices.contains(index) { return layers[index] }
        let version = layers.compactMap(\.paletteVersion).first
        return .editableAir(version: version)
    }

    var stateDescription: String {
        let descriptions = layers.enumerated().compactMap { index, state -> String? in
            guard !state.isAir || layers.count == 1 else { return nil }
            let properties = state.statePropertiesDescription
            let prefix = layers.count > 1 ? "图层 \(index)：" : ""
            return properties.isEmpty
                ? "\(prefix)\(state.identifierDescription)"
                : "\(prefix)\(state.identifierDescription)\n\(properties)"
        }
        if !descriptions.isEmpty { return descriptions.joined(separator: "\n\n") }
        return isGenerated ? "minecraft:air\n无方块状态" : "minecraft:air\n该 SubChunk 尚未生成"
    }

    var coordinateDescription: String { "X=\(x)  Y=\(y)  Z=\(z)" }

    var chunkDescription: String {
        let chunkX = MapCoordinate.chunk(fromBlock: x)
        let chunkZ = MapCoordinate.chunk(fromBlock: z)
        let localX = Int(x - MapCoordinate.blockOrigin(ofChunk: chunkX))
        let localZ = Int(z - MapCoordinate.blockOrigin(ofChunk: chunkZ))
        return "区块 (\(chunkX), \(chunkZ))；局部 (\(localX), \(Int(y) & 15), \(localZ))"
    }
}

struct BedrockBlockColumnResult {
    let blocks: [BedrockBlockRecord]
    let diagnostics: [String]

    func block(atY y: Int32) -> BedrockBlockRecord? {
        blocks.first(where: { $0.y == y })
    }
}

extension ChunkSurfaceRenderer {
    func blockColumn(blockX: Int64, blockZ: Int64, dimension: Int32) throws -> BedrockBlockColumnResult {
        let chunkX = MapCoordinate.chunk(fromBlock: blockX)
        let chunkZ = MapCoordinate.chunk(fromBlock: blockZ)
        let localX = Int(blockX - MapCoordinate.blockOrigin(ofChunk: chunkX))
        let localZ = Int(blockZ - MapCoordinate.blockOrigin(ofChunk: chunkZ))
        let position = ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension)
        var blocks = [BedrockBlockRecord]()
        var diagnostics = [String]()

        let records: [BedrockStoredSubChunk]
        do {
            records = try BedrockChunkSubChunkAccess.records(database: database, position: position)
        } catch {
            diagnostics.append("地形：\(error.localizedDescription)")
            records = []
        }
        let byY = Dictionary(uniqueKeysWithValues: records.map { ($0.yIndex, $0.subChunk) })

        // Keep the normal editor range visible even for missing cells, but also
        // extend to any valid logical Y actually present in the database.
        let minimumY = min(-4, Int(records.map(\.yIndex).min() ?? -4))
        let maximumY = max(19, Int(records.map(\.yIndex).max() ?? 19))
        blocks.reserveCapacity((maximumY - minimumY + 1) * 16)

        for subChunkY in stride(from: maximumY, through: minimumY, by: -1) {
            let yIndex = Int8(clamping: subChunkY)
            guard let subChunk = byY[yIndex] else {
                for localY in stride(from: 15, through: 0, by: -1) {
                    blocks.append(BedrockBlockRecord(
                        x: blockX,
                        y: Int32(subChunkY * 16 + localY),
                        z: blockZ,
                        dimension: dimension,
                        layers: [],
                        isGenerated: false
                    ))
                }
                continue
            }

            for localY in stride(from: 15, through: 0, by: -1) {
                let layers = subChunk.storages.compactMap { $0.blockState(x: localX, y: localY, z: localZ) }
                blocks.append(BedrockBlockRecord(
                    x: blockX,
                    y: Int32(subChunkY * 16 + localY),
                    z: blockZ,
                    dimension: dimension,
                    layers: layers,
                    isGenerated: true
                ))
            }
        }
        return BedrockBlockColumnResult(blocks: blocks, diagnostics: diagnostics)
    }

    func block(blockX: Int64, y: Int32, blockZ: Int64, dimension: Int32) throws -> BedrockBlockRecord {
        let result = try blockColumn(blockX: blockX, blockZ: blockZ, dimension: dimension)
        guard let block = result.block(atY: y) else {
            throw MCBEEditorError.malformedData("Y 坐标超出当前 Bedrock 高度范围：\(y)")
        }
        return block
    }
}
