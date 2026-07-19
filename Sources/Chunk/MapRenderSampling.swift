import Foundation

struct MapChunkSampleAxis: Equatable {
  let startOffset: Int
  let endOffset: Int
  let representativeOffset: Int

  var span: Int { endOffset - startOffset + 1 }
}

/// Keeps the represented map extent unlimited while bounding the number of
/// LevelDB chunk decodes and temporary images required for one frame. When the
/// logical region becomes very large, one representative chunk is sampled for
/// each tile and stretched across that tile. Taps still read the exact target
/// chunk directly from LevelDB.
struct MapChunkSamplingPlan: Equatable {
  let logicalSideChunks: Int
  let stride: Int
  let xAxis: [MapChunkSampleAxis]
  let zAxis: [MapChunkSampleAxis]

  var sampleCount: Int {
    let (product, overflow) = xAxis.count.multipliedReportingOverflow(by: zAxis.count)
    return overflow ? Int.max : product
  }

  var isDownsampled: Bool { stride > 1 }

  static func make(
    sideChunks: Int,
    leftChunks: Int,
    maximumSamplesPerAxis: Int
  ) -> MapChunkSamplingPlan {
    let side = max(1, sideChunks)
    let left = min(max(0, leftChunks), side - 1)
    let right = side - left - 1
    let maximumSamples = max(1, maximumSamplesPerAxis)
    let stride = max(1, ceilingDivide(side, by: maximumSamples))
    let axis = makeAxis(start: -left, end: right, stride: stride)
    return MapChunkSamplingPlan(
      logicalSideChunks: side,
      stride: stride,
      xAxis: axis,
      zAxis: axis
    )
  }

  static func safeChunkCoordinate(center: Int32, offset: Int) -> Int32? {
    let (value, overflow) = Int64(center).addingReportingOverflow(Int64(offset))
    guard !overflow, value >= Int64(Int32.min), value <= Int64(Int32.max) else {
      return nil
    }
    return Int32(value)
  }

  private static func ceilingDivide(_ value: Int, by divisor: Int) -> Int {
    let quotient = value / divisor
    return quotient + (value % divisor == 0 ? 0 : 1)
  }

  private static func makeAxis(start: Int, end: Int, stride: Int) -> [MapChunkSampleAxis] {
    guard start <= end else { return [] }
    var result = [MapChunkSampleAxis]()
    result.reserveCapacity(ceilingDivide(end - start + 1, by: stride))
    var tileStart = start
    while tileStart <= end {
      let remaining = end - tileStart
      let tileEnd = tileStart + min(stride - 1, remaining)
      let representative: Int
      if tileStart <= 0, tileEnd >= 0 {
        representative = 0
      } else {
        representative = tileStart + (tileEnd - tileStart) / 2
      }
      result.append(
        MapChunkSampleAxis(
          startOffset: tileStart,
          endOffset: tileEnd,
          representativeOffset: representative
        ))
      guard tileEnd < end else { break }
      tileStart = tileEnd + 1
    }
    return result
  }
}
