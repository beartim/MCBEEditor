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
    projectionDepth: Int = 128,
    pixelsPerBlock: Int = 1,
    maximumRasterSide: Int = 2048,
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
    let rasterPixelsPerSample = max(1, pixelsPerBlock)
    let rasterLimit = max(256, maximumRasterSide)
    let longest = max(horizontalBlockCount, verticalBlockCount)
    let minimumStride = max(
      1,
      Int(ceil(
        Double(longest * rasterPixelsPerSample) / Double(rasterLimit)
      ))
    )
    // Keep the sampling stride power-of-two whenever downsampling is needed.
    // For the common 1/2/4/8/16 strides this keeps 16-block SubChunk
    // boundaries exactly on sampled-cell edges instead of drifting through
    // the middle of a sampled block.
    var sampleStride = 1
    while sampleStride < minimumStride, sampleStride <= Int.max / 2 {
      sampleStride *= 2
    }
    let rasterColumns = Int(ceil(Double(horizontalBlockCount) / Double(sampleStride)))
    let rasterRows = Int(ceil(Double(verticalBlockCount) / Double(sampleStride)))
    let rasterWidth = rasterColumns * rasterPixelsPerSample
    let rasterHeight = rasterRows * rasterPixelsPerSample

    struct CachedChunkData {
      let subChunks: [Int8: BedrockSubChunk]
      let biomeDocument: BedrockBiomeDocument?
      let legacyTerrain: BedrockLegacyTerrain?
    }
    struct Sample {
      let blockName: String
      let legacyID: UInt16?
      let legacyData: UInt8?
      let hasSubChunk: Bool
      let biomeID: UInt32?
      let chunkX: Int32
      let chunkZ: Int32
    }

    let rayDepth = max(1, projectionDepth)

    var errors = [String]()
    var decoded = 0
    var chunkCache = [ChunkPosition: CachedChunkData]()

    func localCoordinate(_ value: Int64, chunk: Int32) -> Int {
      Int(value - MapCoordinate.blockOrigin(ofChunk: chunk))
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

    func isAir(_ blockName: String) -> Bool {
      BedrockBlockMapColorCatalog.isAir(blockName)
    }

    func sampleAt(worldX: Int64, worldZ: Int64, y: Int64) -> Sample {
      let chunkX = MapCoordinate.chunk(fromBlock: worldX)
      let chunkZ = MapCoordinate.chunk(fromBlock: worldZ)
      let position = ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension)
      let cached = loadChunk(position)
      let subY64 = MapCoordinate.floorDiv16(y)
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
      // Missing SubChunk records are intentionally preserved as "not generated".
      // Some worlds contain large vertical gaps whose parent chunk exists but the
      // individual SubChunk was never generated, so chunk-level generation state
      // must not be used as an air fallback here.
      return Sample(
        blockName: primary?.name ?? "minecraft:air",
        legacyID: primary?.legacyID,
        legacyData: primary?.legacyData,
        hasSubChunk: subChunk != nil,
        biomeID: biomeID,
        chunkX: chunkX,
        chunkZ: chunkZ
      )
    }

    /// X/Z block views are orthographic projections rather than a one-block
    /// paper-thin slice. Look from the current section plane toward the
    /// negative axis for 128 blocks, so structures immediately behind the
    /// plane remain visible without changing the section's horizontal/Y
    /// coordinate system. Property modes intentionally keep reading the exact
    /// plane selected by the user.
    func sample(horizontal: Int64, y: Int64) -> Sample {
      let planeX = axis == .x ? fixedX : horizontal
      let planeZ = axis == .z ? fixedZ : horizontal

      if mode == .biome || mode == .tickingAreas || mode == .slime {
        return sampleAt(worldX: planeX, worldZ: planeZ, y: y)
      }

      // Traverse coordinates from the largest X/Z toward the negative axis.
      // This makes the projected pixel explicitly prefer the largest-coordinate
      // non-air block in the 128-block slab instead of depending on incidental
      // loop/fallback order.
      let maximumProjectionCoordinate = axis == .x ? fixedX : fixedZ
      let minimumProjectionCoordinate = maximumProjectionCoordinate - Int64(rayDepth - 1)
      var fallback: Sample?
      for coordinate in stride(
        from: maximumProjectionCoordinate,
        through: minimumProjectionCoordinate,
        by: -1
      ) {
        let worldX = axis == .x ? coordinate : horizontal
        let worldZ = axis == .z ? coordinate : horizontal
        let value = sampleAt(worldX: worldX, worldZ: worldZ, y: y)
        if fallback == nil { fallback = value }

        if mode == .xray {
          if BedrockBlockIdentifier.isHighlightedOre(value.blockName) { return value }
        } else if !isAir(value.blockName) {
          return value
        }
      }
      return fallback ?? sampleAt(worldX: planeX, worldZ: planeZ, y: y)
    }

    func planeHasSubChunk(horizontal: Int64, y: Int64) -> Bool {
      let worldX = axis == .x ? fixedX : horizontal
      let worldZ = axis == .z ? fixedZ : horizontal
      let chunkX = MapCoordinate.chunk(fromBlock: worldX)
      let chunkZ = MapCoordinate.chunk(fromBlock: worldZ)
      let position = ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension)
      let subY64 = MapCoordinate.floorDiv16(y)
      guard subY64 >= Int64(Int8.min), subY64 <= Int64(Int8.max) else { return false }
      return loadChunk(position).subChunks[Int8(subY64)] != nil
    }

    let worldToRaster = CGFloat(rasterPixelsPerSample) / CGFloat(sampleStride)

    func rasterEdge(_ blockOffset: Int64) -> CGFloat {
      CGFloat(Double(blockOffset) / Double(sampleStride)
        * Double(rasterPixelsPerSample))
    }

    /// Missing-section texture is built from exact world SubChunk cells rather
    /// than sampled pixels. Its rectangle edges therefore use the exact same
    /// world-to-raster transform as the 16-block grid and cannot drift away
    /// from the grid when the viewport origin or sample stride changes.
    func ungeneratedPlaneSubChunkRects() -> [CGRect] {
      guard showUngeneratedSubChunks || transparentUngeneratedSubChunks else { return [] }
      var rects = [CGRect]()
      let horizontalEndExclusive = maximumHorizontal + 1
      let verticalEndExclusive = maximumY + 1

      var horizontalCellStart = MapCoordinate.floorDiv16(minimumHorizontal) * 16
      while horizontalCellStart < horizontalEndExclusive {
        let clippedHorizontalStart = max(horizontalCellStart, minimumHorizontal)
        let clippedHorizontalEnd = min(horizontalCellStart + 16, horizontalEndExclusive)
        if clippedHorizontalEnd > clippedHorizontalStart {
          var verticalCellStart = MapCoordinate.floorDiv16(minimumY) * 16
          while verticalCellStart < verticalEndExclusive {
            let clippedYStart = max(verticalCellStart, minimumY)
            let clippedYEnd = min(verticalCellStart + 16, verticalEndExclusive)
            if clippedYEnd > clippedYStart,
              !planeHasSubChunk(horizontal: clippedHorizontalStart, y: clippedYStart)
            {
              let x0 = rasterEdge(clippedHorizontalStart - minimumHorizontal)
              let x1 = rasterEdge(clippedHorizontalEnd - minimumHorizontal)
              let y0 = rasterEdge(verticalEndExclusive - clippedYEnd)
              let y1 = rasterEdge(verticalEndExclusive - clippedYStart)
              rects.append(CGRect(
                x: min(x0, x1), y: min(y0, y1),
                width: abs(x1 - x0), height: abs(y1 - y0)
              ))
            }
            verticalCellStart += 16
          }
        }
        horizontalCellStart += 16
      }
      return rects
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
        return crossSectionColor(
          for: value.blockName, legacyID: value.legacyID, legacyData: value.legacyData,
          y: Int32(clamping: y), mode: mode
        )
      }
    }

    let exactUngeneratedRects = ungeneratedPlaneSubChunkRects()

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

      for row in 0..<rasterRows {
        if shouldCancel() { return }
        let y = maximumY - Int64(min(verticalBlockCount - 1, row * sampleStride))
        for column in 0..<rasterColumns {
          if shouldCancel() { return }
          let horizontal = minimumHorizontal + Int64(min(horizontalBlockCount - 1, column * sampleStride))
          let value = sample(horizontal: horizontal, y: y)
          let rect = CGRect(
            x: CGFloat(column * rasterPixelsPerSample),
            y: CGFloat(row * rasterPixelsPerSample),
            width: CGFloat(rasterPixelsPerSample),
            height: CGFloat(rasterPixelsPerSample)
          )
          color(for: value, y: y).setFill()
          context.fill(rect)
        }
      }

      if transparentUngeneratedSubChunks, !exactUngeneratedRects.isEmpty {
        for rect in exactUngeneratedRects where !rect.isEmpty { cg.clear(rect) }
      }

      if showUngeneratedSubChunks, !exactUngeneratedRects.isEmpty {
        for rect in exactUngeneratedRects where !rect.isEmpty {
          UIColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1).setFill()
          context.fill(rect)
        }

        let validRects = exactUngeneratedRects.filter { !$0.isEmpty }
        if !validRects.isEmpty {
          let minX = validRects.map(\.minX).min() ?? 0
          let minY = validRects.map(\.minY).min() ?? 0
          let maxX = validRects.map(\.maxX).max() ?? 0
          let maxY = validRects.map(\.maxY).max() ?? 0
          let textureBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
          if !textureBounds.isEmpty {
            let renderedSubChunkSide = 16.0 * worldToRaster
            let spacing = max(2.0, renderedSubChunkSide * 0.5)
            let lineWidth = max(
              1.0,
              (renderedSubChunkSide * 0.075).rounded(.toNearestOrAwayFromZero)
            )
            let margin = textureBounds.width + textureBounds.height + lineWidth * 4
            let minimumIntercept = textureBounds.minY - textureBounds.maxX - margin
            let maximumIntercept = textureBounds.maxY - textureBounds.minX + margin

            cg.saveGState()
            let clip = CGMutablePath()
            for rect in validRects { clip.addRect(rect) }
            cg.addPath(clip)
            cg.clip()
            cg.setShouldAntialias(true)
            cg.setAllowsAntialiasing(true)
            cg.setLineCap(.square)
            cg.setLineJoin(.miter)
            cg.setStrokeColor(UIColor(white: 0.66, alpha: 1).cgColor)
            cg.setLineWidth(lineWidth)

            // Anchor hatch phase in world coordinates. The same SubChunk keeps
            // the same diagonal phase while panning/zooming, so hatch boundaries
            // stay registered with the 16-block grid instead of sliding over it.
            let worldAnchorIntercept = CGFloat(
              Double(maximumY) + 1.0 + Double(minimumHorizontal)
            ) * worldToRaster
            var intercept = worldAnchorIntercept
              + floor((minimumIntercept - worldAnchorIntercept) / spacing) * spacing
            cg.beginPath()
            while intercept <= maximumIntercept {
              cg.move(to: CGPoint(
                x: textureBounds.minX - margin,
                y: textureBounds.minX - margin + intercept
              ))
              cg.addLine(to: CGPoint(
                x: textureBounds.maxX + margin,
                y: textureBounds.maxX + margin + intercept
              ))
              intercept += spacing
            }
            cg.strokePath()
            cg.restoreGState()
          }
        }
      }

      if drawSubChunkGrid {
        // Match the Y-map grid exactly, and draw it after missing-section hatch
        // so the 16-block boundaries remain visible on top of the texture.
        cg.setShouldAntialias(false)
        cg.setAllowsAntialiasing(false)
        cg.setStrokeColor(UIColor.label.withAlphaComponent(0.28).cgColor)
        cg.setLineWidth(max(0.15, worldToRaster * 0.15))

        let horizontalEndExclusive = maximumHorizontal + 1
        var boundary = MapCoordinate.floorDiv16(minimumHorizontal) * 16
        if boundary < minimumHorizontal { boundary += 16 }
        while boundary <= horizontalEndExclusive {
          let x = rasterEdge(boundary - minimumHorizontal)
          if x >= 0, x <= CGFloat(rasterWidth) {
            cg.move(to: CGPoint(x: x, y: 0))
            cg.addLine(to: CGPoint(x: x, y: CGFloat(rasterHeight)))
          }
          boundary += 16
        }

        var yBoundary = MapCoordinate.floorDiv16(minimumY) * 16
        if yBoundary < minimumY { yBoundary += 16 }
        while yBoundary <= maximumY + 1 {
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

    let subY64 = MapCoordinate.floorDiv16(Int64(fixedY))
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
