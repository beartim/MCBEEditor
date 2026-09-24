import Foundation

enum MapCoordinate {
    static let blocksPerChunk: Int64 = 16

    /// Inclusive ray bounds shared by rendering and automatic block selection.
    /// Saturate at the coordinate limits instead of wrapping or trapping.
    static func projectionRange(
        plane: Int64, depth: Int, towardPositive: Bool = false,
        restrictToChunk: Bool = false
    ) -> ClosedRange<Int64> {
        if restrictToChunk {
            let origin = floorDiv16(plane) * blocksPerChunk
            return origin...(origin + (blocksPerChunk - 1))
        }
        let distance = Int64(max(1, depth) - 1)
        if towardPositive {
            let (end, overflow) = plane.addingReportingOverflow(distance)
            return plane...(overflow ? Int64.max : end)
        }
        let (start, overflow) = plane.subtractingReportingOverflow(distance)
        return (overflow ? Int64.min : start)...plane
    }

    static func floorDiv16<T: BinaryInteger>(_ coordinate: T) -> Int64 {
        let value = Int64(clamping: coordinate)
        let quotient = value / blocksPerChunk
        let remainder = value % blocksPerChunk
        return remainder < 0 ? quotient - 1 : quotient
    }

    static func chunk<T: BinaryInteger>(fromBlock coordinate: T) -> Int32 {
        Int32(clamping: floorDiv16(coordinate))
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
        let whole = nonnegative / blocksPerChunk
        return Int32(clamping: whole + (nonnegative % blocksPerChunk == 0 ? 0 : 1))
    }

    static func blockDistance(fromChunkDistance distance: Int64) -> Int64 {
        min(max(0, distance), Int64.max / blocksPerChunk) * blocksPerChunk
    }
}
