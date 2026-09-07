import UIKit

enum MapSliceAxis: Int, CaseIterable {
  case x = 0
  case y = 1
  case z = 2

  var displayName: String {
    switch self {
    case .x: return "X"
    case .y: return "Y"
    case .z: return "Z"
    }
  }
}

struct BedrockCrossSectionResult {
  let image: UIImage
  let decodedSubChunks: Int
  let errors: [String]
  let sampleStride: Int
  let minimumHorizontal: Int64
  let minimumY: Int64
  let maximumY: Int64
}

struct BedrockBlockAxisLineResult {
  let axis: MapSliceAxis
  let blocks: [BedrockBlockRecord]
  let diagnostics: [String]
}

extension ChunkSurfaceRenderer {
  /// Renders a vertical X or Z slice. The horizontal axis is the other world
  /// horizontal coordinate and the vertical screen axis is Y, with larger Y
  /// values at the top of the image.
  func renderCrossSection(
    axis: MapSliceAxis,
    fixedX: Int64,
    fixedZ: Int64,
    centerY: Int32,
    sideBlocks: Int,
    dimension: Int32,
    mode: MapRenderMode,
    drawSubChunkGrid: Bool,
    shouldCancel: () -> Bool
  ) throws -> BedrockCrossSectionResult {
    guard axis == .x || axis == .z else {
      throw MCBEEditorError.malformedData("Y 轴俯视图应使用普通地图渲染器")
    }
    let side = max(16, sideBlocks)
    let maximumRasterSide = 2048
    let sampleStride = max(1, Int(ceil(Double(side) / Double(maximumRasterSide))))
    let rasterSide = Int(ceil(Double(side) / Double(sampleStride)))
    let half = side / 2
    let minimumY = Int64(centerY) - Int64(half)
    let maximumY = minimumY + Int64(side) - 1
    let minimumHorizontal: Int64
    switch axis {
    case .x: minimumHorizontal = fixedZ - Int64(half)
    case .z: minimumHorizontal = fixedX - Int64(half)
    case .y: minimumHorizontal = 0
    }

    var errors = [String]()
    var decoded = 0
    var chunkCache = [ChunkPosition: [Int8: BedrockSubChunk]]()

    func localCoordinate(_ value: Int64, chunk: Int32) -> Int {
      Int(value - MapCoordinate.blockOrigin(ofChunk: chunk))
    }

    func floorDiv16(_ value: Int64) -> Int64 {
      if value >= 0 { return value / 16 }
      return -(((-value) + 15) / 16)
    }

    func stateName(horizontal: Int64, y: Int64) throws -> String {
      let worldX = axis == .x ? fixedX : horizontal
      let worldZ = axis == .z ? fixedZ : horizontal
      let chunkX = MapCoordinate.chunk(fromBlock: worldX)
      let chunkZ = MapCoordinate.chunk(fromBlock: worldZ)
      let position = ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension)
      let byY: [Int8: BedrockSubChunk]
      if let cached = chunkCache[position] {
        byY = cached
      } else {
        do {
          let records = try BedrockChunkSubChunkAccess.records(database: database, position: position)
          decoded += records.count
          let mapped = Dictionary(uniqueKeysWithValues: records.map { ($0.yIndex, $0.subChunk) })
          chunkCache[position] = mapped
          byY = mapped
        } catch {
          errors.append("区块 (\(chunkX),\(chunkZ))：\(error.localizedDescription)")
          chunkCache[position] = [:]
          return "minecraft:air"
        }
      }

      let subY64 = floorDiv16(y)
      guard subY64 >= Int64(Int8.min), subY64 <= Int64(Int8.max),
        let subChunk = byY[Int8(subY64)]
      else { return "minecraft:air" }
      let localY = Int(y - subY64 * 16)
      let localX = localCoordinate(worldX, chunk: chunkX)
      let localZ = localCoordinate(worldZ, chunk: chunkZ)
      let states = subChunk.storages.compactMap { $0.blockState(x: localX, y: localY, z: localZ) }
      let primary = states.first(where: { !$0.isAir }) ?? states.first
      return primary?.name ?? "minecraft:air"
    }

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let image = try UIGraphicsImageRenderer(
      size: CGSize(width: rasterSide, height: rasterSide), format: format
    ).image { context in
      let cg = context.cgContext
      cg.interpolationQuality = .none
      cg.setAllowsAntialiasing(false)
      cg.setShouldAntialias(false)
      UIColor.systemGray5.setFill()
      context.fill(CGRect(x: 0, y: 0, width: rasterSide, height: rasterSide))

      for row in 0..<rasterSide {
        if shouldCancel() { return }
        let y = maximumY - Int64(min(side - 1, row * sampleStride))
        for column in 0..<rasterSide {
          if shouldCancel() { return }
          let horizontal = minimumHorizontal + Int64(min(side - 1, column * sampleStride))
          let name: String
          do {
            name = try stateName(horizontal: horizontal, y: y)
          } catch {
            name = "minecraft:air"
          }
          crossSectionColor(for: name, y: Int32(clamping: y), mode: mode).setFill()
          context.fill(CGRect(x: column, y: row, width: 1, height: 1))
        }
      }

      if drawSubChunkGrid {
        cg.setStrokeColor(UIColor.label.withAlphaComponent(0.34).cgColor)
        cg.setLineWidth(1)
        let scale = CGFloat(rasterSide) / CGFloat(side)

        let horizontalEnd = minimumHorizontal + Int64(side)
        var boundary = floorDiv16(minimumHorizontal) * 16
        if boundary < minimumHorizontal { boundary += 16 }
        while boundary <= horizontalEnd {
          let x = CGFloat(boundary - minimumHorizontal) * scale
          cg.move(to: CGPoint(x: x, y: 0))
          cg.addLine(to: CGPoint(x: x, y: CGFloat(rasterSide)))
          boundary += 16
        }

        var yBoundary = floorDiv16(minimumY) * 16
        if yBoundary < minimumY { yBoundary += 16 }
        while yBoundary <= maximumY + 1 {
          let yPosition = CGFloat(maximumY - yBoundary + 1) * scale
          cg.move(to: CGPoint(x: 0, y: yPosition))
          cg.addLine(to: CGPoint(x: CGFloat(rasterSide), y: yPosition))
          yBoundary += 16
        }
        cg.strokePath()
      }
    }
    if shouldCancel() { throw MapRenderCancelledBridge.cancelled }
    return BedrockCrossSectionResult(
      image: image, decodedSubChunks: decoded, errors: errors, sampleStride: sampleStride,
      minimumHorizontal: minimumHorizontal, minimumY: minimumY, maximumY: maximumY)
  }

  func blockAxisLine(
    axis: MapSliceAxis,
    fixedY: Int32,
    fixedX: Int64,
    fixedZ: Int64,
    minimumCoordinate: Int64,
    maximumCoordinate: Int64,
    dimension: Int32
  ) throws -> BedrockBlockAxisLineResult {
    guard axis == .x || axis == .z else {
      throw MCBEEditorError.malformedData("仅 X/Z 轴支持水平方块选择")
    }
    let lower = min(minimumCoordinate, maximumCoordinate)
    let upper = max(minimumCoordinate, maximumCoordinate)
    let maximumRows: Int64 = 8192
    let cappedLower = max(lower, upper - maximumRows + 1)
    var diagnostics = [String]()
    if cappedLower != lower {
      diagnostics.append("轴向范围过大，选择器仅显示靠近正方向的最后 \(maximumRows) 个方块。")
    }

    var chunkCache = [ChunkPosition: [Int8: BedrockSubChunk]]()
    var blocks = [BedrockBlockRecord]()
    blocks.reserveCapacity(Int(upper - cappedLower + 1))

    func floorDiv16(_ value: Int64) -> Int64 {
      if value >= 0 { return value / 16 }
      return -(((-value) + 15) / 16)
    }
    let subY64 = floorDiv16(Int64(fixedY))
    let localY = Int(Int64(fixedY) - subY64 * 16)

    for coordinate in stride(from: upper, through: cappedLower, by: -1) {
      let worldX = axis == .x ? coordinate : fixedX
      let worldZ = axis == .z ? coordinate : fixedZ
      let chunkX = MapCoordinate.chunk(fromBlock: worldX)
      let chunkZ = MapCoordinate.chunk(fromBlock: worldZ)
      let position = ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension)
      let byY: [Int8: BedrockSubChunk]
      if let cached = chunkCache[position] {
        byY = cached
      } else {
        do {
          let records = try BedrockChunkSubChunkAccess.records(database: database, position: position)
          let mapped = Dictionary(uniqueKeysWithValues: records.map { ($0.yIndex, $0.subChunk) })
          chunkCache[position] = mapped
          byY = mapped
        } catch {
          diagnostics.append("区块 (\(chunkX),\(chunkZ))：\(error.localizedDescription)")
          chunkCache[position] = [:]
          byY = [:]
        }
      }
      let subChunk = (subY64 >= Int64(Int8.min) && subY64 <= Int64(Int8.max))
        ? byY[Int8(subY64)] : nil
      let localX = Int(worldX - MapCoordinate.blockOrigin(ofChunk: chunkX))
      let localZ = Int(worldZ - MapCoordinate.blockOrigin(ofChunk: chunkZ))
      let layers = subChunk?.storages.compactMap {
        $0.blockState(x: localX, y: localY, z: localZ)
      } ?? []
      blocks.append(BedrockBlockRecord(
        x: worldX,
        y: fixedY,
        z: worldZ,
        dimension: dimension,
        layers: layers,
        isGenerated: subChunk != nil
      ))
    }
    return BedrockBlockAxisLineResult(axis: axis, blocks: blocks, diagnostics: diagnostics)
  }
}

/// Private map-render cancellation lives in WorldMapViewController.swift. This
/// bridge lets the chunk helper stop cleanly without exposing UI-private types.
enum MapRenderCancelledBridge: Error { case cancelled }
