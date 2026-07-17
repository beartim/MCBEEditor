import Foundation

struct BedrockMapRegion: Hashable {
    var minimumX: Int64
    var minimumZ: Int64
    var maximumX: Int64
    var maximumZ: Int64
    let dimension: Int32

    init(minimumX: Int64, minimumZ: Int64, maximumX: Int64, maximumZ: Int64, dimension: Int32) {
        self.minimumX = min(minimumX, maximumX)
        self.minimumZ = min(minimumZ, maximumZ)
        self.maximumX = max(minimumX, maximumX)
        self.maximumZ = max(minimumZ, maximumZ)
        self.dimension = dimension
    }

    var width: Int64 { maximumX - minimumX + 1 }
    var depth: Int64 { maximumZ - minimumZ + 1 }
    var blockCount2D: Int64 { width * depth }
    var coordinateText: String { "X \(minimumX)…\(maximumX)，Z \(minimumZ)…\(maximumZ)" }

    func contains(x: Int64, z: Int64) -> Bool {
        x >= minimumX && x <= maximumX && z >= minimumZ && z <= maximumZ
    }

    func intersects(_ other: BedrockMapRegion) -> Bool {
        dimension == other.dimension &&
        maximumX >= other.minimumX && other.maximumX >= minimumX &&
        maximumZ >= other.minimumZ && other.maximumZ >= minimumZ
    }

    var minimumChunkX: Int32 { MapCoordinate.chunk(fromBlock: minimumX) }
    var maximumChunkX: Int32 { MapCoordinate.chunk(fromBlock: maximumX) }
    var minimumChunkZ: Int32 { MapCoordinate.chunk(fromBlock: minimumZ) }
    var maximumChunkZ: Int32 { MapCoordinate.chunk(fromBlock: maximumZ) }

    var chunkCount: Int {
        let xCount = Int(Int64(maximumChunkX) - Int64(minimumChunkX) + 1)
        let zCount = Int(Int64(maximumChunkZ) - Int64(minimumChunkZ) + 1)
        return max(0, xCount * zCount)
    }

    var isChunkAligned: Bool {
        minimumX == MapCoordinate.blockOrigin(ofChunk: minimumChunkX) &&
        minimumZ == MapCoordinate.blockOrigin(ofChunk: minimumChunkZ) &&
        maximumX == MapCoordinate.blockOrigin(ofChunk: maximumChunkX) + 15 &&
        maximumZ == MapCoordinate.blockOrigin(ofChunk: maximumChunkZ) + 15
    }

    var expandedToChunkBounds: BedrockMapRegion {
        BedrockMapRegion(
            minimumX: MapCoordinate.blockOrigin(ofChunk: minimumChunkX),
            minimumZ: MapCoordinate.blockOrigin(ofChunk: minimumChunkZ),
            maximumX: MapCoordinate.blockOrigin(ofChunk: maximumChunkX) + 15,
            maximumZ: MapCoordinate.blockOrigin(ofChunk: maximumChunkZ) + 15,
            dimension: dimension
        )
    }

    var chunkPositions: [ChunkPosition] {
        var values = [ChunkPosition]()
        values.reserveCapacity(chunkCount)
        for z in minimumChunkZ...maximumChunkZ {
            for x in minimumChunkX...maximumChunkX {
                values.append(ChunkPosition(x: x, z: z, dimension: dimension))
            }
        }
        return values
    }

    func localRanges(in chunk: ChunkPosition) -> (x: ClosedRange<Int>, z: ClosedRange<Int>)? {
        guard chunk.dimension == dimension else { return nil }
        let originX = MapCoordinate.blockOrigin(ofChunk: chunk.x)
        let originZ = MapCoordinate.blockOrigin(ofChunk: chunk.z)
        let minLocalX = Int(max(0, minimumX - originX))
        let maxLocalX = Int(min(15, maximumX - originX))
        let minLocalZ = Int(max(0, minimumZ - originZ))
        let maxLocalZ = Int(min(15, maximumZ - originZ))
        guard minLocalX <= maxLocalX, minLocalZ <= maxLocalZ else { return nil }
        return (minLocalX...maxLocalX, minLocalZ...maxLocalZ)
    }

    func translated(toMinimumX x: Int64, minimumZ z: Int64, dimension targetDimension: Int32? = nil) -> BedrockMapRegion {
        BedrockMapRegion(
            minimumX: x,
            minimumZ: z,
            maximumX: x + width - 1,
            maximumZ: z + depth - 1,
            dimension: targetDimension ?? dimension
        )
    }
}
