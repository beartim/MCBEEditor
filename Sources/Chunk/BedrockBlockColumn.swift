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
        var blocks = [BedrockBlockRecord]()
        var diagnostics = [String]()
        blocks.reserveCapacity(384)

        for subChunkY in stride(from: 19, through: -4, by: -1) {
            let key = BedrockDBKey.subChunk(x: chunkX, z: chunkZ, dimension: dimension, index: Int8(subChunkY))
            guard let raw = try database.get(key) else {
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

            do {
                let subChunk = try BedrockSubChunk.decode(raw, keyYIndex: Int8(subChunkY))
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
            } catch {
                diagnostics.append("SubChunk Y=\(subChunkY)：\(error.localizedDescription)")
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
