import Foundation

struct BedrockBlockSearchHit: Hashable {
    let x: Int64
    let y: Int32
    let z: Int64
    let dimension: Int32
    let layer0Name: String
    let layer1Name: String
    let matchedLayers: [Int]

    var coordinateText: String { "X=\(x) Y=\(y) Z=\(z)" }
    var dimensionName: String { BedrockDimension(rawValue: dimension)?.displayName ?? "维度 \(dimension)" }
    var blockDescription: String {
        let names = matchedLayers.map { layer in layer == 0 ? "层0 \(layer0Name)" : "层1 \(layer1Name)" }
        return names.isEmpty ? "层0 \(layer0Name) · 层1 \(layer1Name)" : names.joined(separator: " · ")
    }
}

struct BedrockBlockSearchScanResult {
    let hits: [BedrockBlockSearchHit]
    let skippedSubChunkCount: Int
    let truncated: Bool
}

extension BedrockChunkStore {
    func searchBlocks(
        in position: ChunkPosition,
        coordinatedOperation operation: BedrockCoordinatedBlockOperation,
        maximumResults: Int = 20_000
    ) throws -> BedrockBlockSearchScanResult {
        try searchBlocks(in: [position], region: nil, coordinatedOperation: operation, maximumResults: maximumResults)
    }

    func searchBlocks(
        in chunks: [ChunkPosition],
        coordinatedOperation operation: BedrockCoordinatedBlockOperation,
        maximumResults: Int = 20_000
    ) throws -> BedrockBlockSearchScanResult {
        try searchBlocks(in: chunks, region: nil, coordinatedOperation: operation, maximumResults: maximumResults)
    }

    func searchBlocks(
        in region: BedrockMapRegion,
        coordinatedOperation operation: BedrockCoordinatedBlockOperation,
        maximumResults: Int = 20_000
    ) throws -> BedrockBlockSearchScanResult {
        try searchBlocks(in: region.chunkPositions, region: region, coordinatedOperation: operation, maximumResults: maximumResults)
    }

    private func searchBlocks(
        in chunks: [ChunkPosition],
        region: BedrockMapRegion?,
        coordinatedOperation operation: BedrockCoordinatedBlockOperation,
        maximumResults: Int
    ) throws -> BedrockBlockSearchScanResult {
        guard operation.searchLayer0 != nil || operation.searchLayer1 != nil else {
            throw MCBEEditorError.malformedData("至少填写层 0 或层 1 的搜索条件")
        }
        let database = try session.database()
        var hits = [BedrockBlockSearchHit]()
        var skipped = 0
        var truncated = false

        chunkLoop: for position in chunks {
            var prefix = Data()
            prefix.appendLE(position.x)
            prefix.appendLE(position.z)
            let entries = try database.entries(prefix: prefix, includeValues: true, limit: 0)
            let ranges = region?.localRanges(in: position)
            let xRange = ranges?.x ?? 0...15
            let zRange = ranges?.z ?? 0...15
            for entry in entries {
                guard let parsed = BedrockDBKey.parse(entry.key), parsed.position == position,
                      parsed.recordType == .subChunk, let yIndex = parsed.subChunkIndex,
                      let raw = entry.value else { continue }
                do {
                    let subChunk = try BedrockSubChunk.decode(raw, keyYIndex: yIndex)
                    let matches = try subChunk.matchingBlocks(
                        coordinatedOperation: operation,
                        localXRange: xRange,
                        localZRange: zRange
                    )
                    for match in matches {
                        if hits.count >= maximumResults {
                            truncated = true
                            break chunkLoop
                        }
                        hits.append(BedrockBlockSearchHit(
                            x: MapCoordinate.absoluteBlock(chunk: position.x, local: match.localX),
                            y: Int32(Int(yIndex) * 16 + match.localY),
                            z: MapCoordinate.absoluteBlock(chunk: position.z, local: match.localZ),
                            dimension: position.dimension,
                            layer0Name: match.layer0.name,
                            layer1Name: match.layer1.name,
                            matchedLayers: match.matchedLayers
                        ))
                    }
                } catch MCBEEditorError.unsupported {
                    skipped += 1
                }
            }
        }
        hits.sort {
            if $0.dimension != $1.dimension { return $0.dimension < $1.dimension }
            if $0.x != $1.x { return $0.x < $1.x }
            if $0.z != $1.z { return $0.z < $1.z }
            return $0.y < $1.y
        }
        return BedrockBlockSearchScanResult(hits: hits, skippedSubChunkCount: skipped, truncated: truncated)
    }
}
