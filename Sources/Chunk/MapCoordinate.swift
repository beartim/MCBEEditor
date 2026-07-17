import Foundation

enum MapCoordinate {
    static let blocksPerChunk: Int64 = 16

    static func chunk<T: BinaryInteger>(fromBlock coordinate: T) -> Int32 {
        let value = Int64(clamping: coordinate)
        let quotient = value / blocksPerChunk
        let remainder = value % blocksPerChunk
        let floored = remainder < 0 ? quotient - 1 : quotient
        return Int32(clamping: floored)
    }

    static func blockOrigin(ofChunk chunk: Int32) -> Int64 {
        Int64(chunk) * blocksPerChunk
    }

    static func absoluteBlock(chunk: Int32, local: Int) -> Int64 {
        blockOrigin(ofChunk: chunk) + Int64(local)
    }

    /// Convert a non-negative distance stored in blocks to the chunk count used
    /// by commands such as `/tickingarea add circle`. Partial chunks round up.
    static func chunkDistance(fromBlockDistance distance: Int64) -> Int32 {
        let nonnegative = max(0, distance)
        return Int32(clamping: (nonnegative + blocksPerChunk - 1) / blocksPerChunk)
    }

    static func blockDistance(fromChunkDistance distance: Int64) -> Int64 {
        max(0, distance) * blocksPerChunk
    }
}
