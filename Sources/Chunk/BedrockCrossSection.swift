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
  let horizontalBlockCount: Int
  let verticalBlockCount: Int
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
    showUngeneratedSubChunks: Bool = false,
    transparentUngeneratedSubChunks: Bool = false,
    tickingAreas: [BedrockTickingArea] = [],
    horizontalRange: ClosedRange<Int64>? = nil,
    verticalRange: ClosedRange<Int64>? = nil,
    shouldCancel: () -> Bool
  ) throws -> BedrockCrossSectionResult {
    guard axis == .x || axis == .z else {
      throw MCBEEditorError.malformedData("Y 轴俯视图应使用普通地图渲染器")
    }
    let side = max(16, sideBlocks)
    let half = side / 2
    let defaultMinimumY = Int64(centerY) - Int64(half)
    let defaultMaximumY = defaultMinimumY + Int64(side) - 1
    let defaultMinimumHorizontal: Int64
    switch axis {
    case .x: defaultMinimumHorizontal = fixedZ - Int64(half)
    case .z: defaultMinimumHorizontal = fixedX - Int64(half)
    case .y: defaultMinimumHorizontal = 0
    }
    let minimumHorizontal = horizontalRange?.lowerBound ?? defaultMinimumHorizontal
    let maximumHorizontal = horizontalRange?.upperBound ?? (defaultMinimumHorizontal + Int64(side) - 1)
    let minimumY = verticalRange?.lowerBound ?? defaultMinimumY
    let maximumY = verticalRange?.upperBound ?? defaultMaximumY
    guard maximumHorizontal >= minimumHorizontal, maximumY >= minimumY else {
      throw MCBEEditorError.malformedData("剖面范围无效")
    }
    let horizontalBlockCount64 = maximumHorizontal - minimumHorizontal + 1
    let verticalBlockCount64 = maximumY - minimumY + 1
    guard horizontalBlockCount64 <= Int64(Int.max), verticalBlockCount64 <= Int64(Int.max) else {
      throw MCBEEditorError.unsupported("剖面范围过大")
    }
    let horizontalBlockCount = Int(horizontalBlockCount64)
    let verticalBlockCount = Int(verticalBlockCount64)
    let maximumRasterSide = 2048
    let longest = max(horizontalBlockCount, verticalBlockCount)
    let sampleStride = max(1, Int(ceil(Double(longest) / Double(maximumRasterSide))))
    let rasterWidth = Int(ceil(Double(horizontalBlockCount) / Double(sampleStride)))
    let rasterHeight = Int(ceil(Double(verticalBlockCount) / Double(sampleStride)))

    struct CachedChunkData {
      let subChunks: [Int8: BedrockSubChunk]
      let biomeDocument: BedrockBiomeDocument?
      let legacyTerrain: BedrockLegacyTerrain?
    }
    struct Sample {
      let blockName: String
      let hasSubChunk: Bool
      let biomeID: UInt32?
      let chunkX: Int32
      let chunkZ: Int32
    }

    var errors = [String]()
    var decoded = 0
    var chunkCache = [ChunkPosition: CachedChunkData]()

    func localCoordinate(_ value: Int64, chunk: Int32) -> Int {
      Int(value - MapCoordinate.blockOrigin(ofChunk: chunk))
    }

    func floorDiv16(_ value: Int64) -> Int64 {
      if value >= 0 { return value / 16 }
      return -(((-value) + 15) / 16)
    }

    func loadChunk(_ position: ChunkPosition) -> CachedChunkData {
      if let cached = chunkCache[position] { return cached }
      var byY = [Int8: BedrockSubChunk]()
      do {
        let records = try BedrockChunkSubChunkAccess.records(database: database, position: position)
        decoded += records.count
        byY = Dictionary(uniqueKeysWithValues: records.map { ($0.yIndex, $0.subChunk) })
      } catch {
        errors.append("区块 (\(position.x),\(position.z)) 地形：\(error.localizedDescription)")
      }

      var biomeDocument: BedrockBiomeDocument?
      var legacyTerrain: BedrockLegacyTerrain?
      if mode == .biome {
        do {
          for type in [ChunkRecordType.data3D, .data2D, .data2DLegacy] {
            let key = BedrockDBKey(position: position, recordType: type, subChunkIndex: nil).encoded()
            if let raw = try database.get(key) {
              biomeDocument = try BedrockBiomeDocument.decode(recordType: type, data: raw)
              break
            }
          }
          if biomeDocument == nil {
            let key = BedrockDBKey(position: position, recordType: .legacyTerrain, subChunkIndex: nil).encoded()
            if let raw = try database.get(key) { legacyTerrain = try BedrockLegacyTerrain.decode(raw) }
          }
        } catch {
          errors.append("区块 (\(position.x),\(position.z)) 生物群系：\(error.localizedDescription)")
        }
      }
      let value = CachedChunkData(subChunks: byY, biomeDocument: biomeDocument, legacyTerrain: legacyTerrain)
      chunkCache[position] = value
      return value
    }

    func sample(horizontal: Int64, y: Int64) -> Sample {
      let worldX = axis == .x ? fixedX : horizontal
      let worldZ = axis == .z ? fixedZ : horizontal
      let chunkX = MapCoordinate.chunk(fromBlock: worldX)
      let chunkZ = MapCoordinate.chunk(fromBlock: worldZ)
      let position = ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension)
      let cached = loadChunk(position)
      let subY64 = floorDiv16(y)
      let subChunk: BedrockSubChunk?
      if subY64 >= Int64(Int8.min), subY64 <= Int64(Int8.max) {
        subChunk = cached.subChunks[Int8(subY64)]
      } else {
        subChunk = nil
      }
      let localX = localCoordinate(worldX, chunk: chunkX)
      let localZ = localCoordinate(worldZ, chunk: chunkZ)
      let localY = Int(y - subY64 * 16)
      let states = subChunk?.storages.compactMap {
        $0.blockState(x: localX, y: localY, z: localZ)
      } ?? []
      let primary = states.first(where: { !$0.isAir }) ?? states.first
      let biomeID = cached.biomeDocument?.biomeID(localX: localX, y: Int(y), localZ: localZ)
        ?? cached.legacyTerrain?.biomeID(localX: localX, localZ: localZ)
      return Sample(
        blockName: primary?.name ?? "minecraft:air",
        hasSubChunk: subChunk != nil,
        biomeID: biomeID,
        chunkX: chunkX,
        chunkZ: chunkZ
      )
    }

    func color(for value: Sample, y: Int64) -> UIColor {
      switch mode {
      case .biome:
        return BedrockBiomeCatalog.color(for: value.biomeID ?? UInt32.max)
      case .tickingAreas:
        let active = tickingAreas.contains {
          $0.dimension == dimension && $0.contains(chunkX: value.chunkX, chunkZ: value.chunkZ)
        }
        return active
          ? UIColor(red: 0.26, green: 0.70, blue: 0.28, alpha: 1)
          : UIColor(white: 0.24, alpha: 1)
      case .slime:
        return BedrockSlimeChunk.isSlimeChunk(x: value.chunkX, z: value.chunkZ)
          ? UIColor(red: 0.25, green: 0.72, blue: 0.25, alpha: 1)
          : UIColor(white: 0.24, alpha: 1)
      default:
        return crossSectionColor(for: value.blockName, y: Int32(clamping: y), mode: mode)
      }
    }

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = !transparentUngeneratedSubChunks
    let image = try UIGraphicsImageRenderer(
      size: CGSize(width: CGFloat(rasterWidth), height: CGFloat(rasterHeight)), format: format
    ).image { context in
      let cg = context.cgContext
      cg.interpolationQuality = .none
      cg.setAllowsAntialiasing(false)
      cg.setShouldAntialias(false)
      UIColor.systemGray5.setFill()
      context.fill(CGRect(x: 0, y: 0, width: CGFloat(rasterWidth), height: CGFloat(rasterHeight)))

      for row in 0..<rasterHeight {
        if shouldCancel() { return }
        let y = maximumY - Int64(min(verticalBlockCount - 1, row * sampleStride))
        for column in 0..<rasterWidth {
          if shouldCancel() { return }
          let horizontal = minimumHorizontal + Int64(min(horizontalBlockCount - 1, column * sampleStride))
          let value = sample(horizontal: horizontal, y: y)
          if transparentUngeneratedSubChunks, !value.hasSubChunk {
            cg.clear(CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1))
            continue
          }
          color(for: value, y: y).setFill()
          context.fill(CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1))
          if showUngeneratedSubChunks, !value.hasSubChunk {
            // Fixed-world-density diagonal texture marks missing SubChunks,
            // independent of raster downsampling and zoom level.
            let phase = Int((horizontal &+ y) & 7)
            if phase == 0 || phase == 1 {
              UIColor.label.withAlphaComponent(0.28).setFill()
              context.fill(CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1))
            }
          }
        }
      }

      if drawSubChunkGrid {
        cg.setStrokeColor(UIColor.label.withAlphaComponent(0.38).cgColor)
        cg.setLineWidth(1)
        // Align every line to a rendered sample-cell edge. Using the old
        // side->raster floating scale could put a 16-block boundary through
        // the middle of a sampled pixel when sampleStride > 1.
        func rasterEdge(_ blockOffset: Int64) -> CGFloat {
          let value = Double(blockOffset) / Double(sampleStride)
          return CGFloat(round(value))
        }

        let horizontalEndExclusive = maximumHorizontal + 1
        var boundary = floorDiv16(minimumHorizontal) * 16
        if boundary < minimumHorizontal { boundary += 16 }
        while boundary <= horizontalEndExclusive {
          let x = rasterEdge(boundary - minimumHorizontal)
          if x >= 0, x <= CGFloat(rasterWidth) {
            cg.move(to: CGPoint(x: x, y: 0))
            cg.addLine(to: CGPoint(x: x, y: CGFloat(rasterHeight)))
          }
          boundary += 16
        }

        var yBoundary = floorDiv16(minimumY) * 16
        if yBoundary < minimumY { yBoundary += 16 }
        while yBoundary <= maximumY + 1 {
          // A boundary at Y=k is the edge between blocks k-1 and k. Because
          // larger Y is at the top, its top-origin block offset is maxY-k+1.
          let yPosition = rasterEdge(maximumY - yBoundary + 1)
          if yPosition >= 0, yPosition <= CGFloat(rasterHeight) {
            cg.move(to: CGPoint(x: 0, y: yPosition))
            cg.addLine(to: CGPoint(x: CGFloat(rasterWidth), y: yPosition))
          }
          yBoundary += 16
        }
        cg.strokePath()
      }
    }
    if shouldCancel() { throw MapRenderCancelledBridge.cancelled }
    return BedrockCrossSectionResult(
      image: image, decodedSubChunks: decoded, errors: errors, sampleStride: sampleStride,
      minimumHorizontal: minimumHorizontal, minimumY: minimumY, maximumY: maximumY,
      horizontalBlockCount: horizontalBlockCount, verticalBlockCount: verticalBlockCount)
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
