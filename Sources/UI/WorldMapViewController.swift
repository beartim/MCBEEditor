import UIKit

private struct MapRenderCancelled: Error {}

private final class MapRenderToken {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}

private struct MapViewportAnchor {
  let blockX: Double
  let blockZ: Double
  let zoomScale: CGFloat
}

private struct MapDimensionViewportState {
  let centerX: Int32
  let centerZ: Int32
  let anchor: MapViewportAnchor
}

private struct MapViewportRenderRequest {
  let centerX: Int32
  let centerZ: Int32
  let anchor: MapViewportAnchor
  let sideChunks: Int
  let requiredMinimumChunkX: Int64
  let requiredMaximumChunkX: Int64
  let requiredMinimumChunkZ: Int64
  let requiredMaximumChunkZ: Int64
}

private enum MapSpawnKind: Equatable {
  case world
  case player

  var displayName: String {
    switch self {
    case .world: return "世界出生点"
    case .player: return "玩家出生点"
    }
  }
}

private struct MapSpawnCoordinate {
  let stableID: String
  let kind: MapSpawnKind
  let name: String
  let source: String
  let x: Int64
  let y: Int64?
  let z: Int64
  let dimension: Int32
  let forced: Bool?
}

private struct MapSpawnHit {
  let spawn: MapSpawnCoordinate
  let localX: CGFloat
  let localZ: CGFloat
}

private struct MapWorldObjectHit {
  let object: BedrockWorldObject
  let localX: CGFloat
  let localZ: CGFloat
  let isNormallyVisible: Bool
}

private struct MapPlayerCoordinate {
  let record: PlayerNBTRecord
  let position: PlayerCurrentPosition
  let isLocal: Bool
  let uniqueID: Int64?

  var stableID: String { "player:\(record.keyText)" }
}

private struct MapPlayerHit {
  let player: MapPlayerCoordinate
  let localX: CGFloat
  let localZ: CGFloat
}

private struct MapHardcodedSpawnerHit {
  let area: HardcodedSpawnerArea
  let ownerChunk: ChunkPosition
  let areaIndex: Int

  var stableID: String {
    "\(ownerChunk.dimension):\(ownerChunk.x):\(ownerChunk.z):\(areaIndex)"
  }
}

private struct MapVillageHit {
  let feature: VillageMapFeature

  var stableID: String { feature.stableID }
}

private struct MapVillagePOILink: Hashable {
  let entityStableID: String
  let entityLocalX: CGFloat
  let entityLocalZ: CGFloat
  let point: VillageMapPoint
}

private struct MapVillagePOIHit {
  let village: MapVillageHit
  let point: VillageMapPoint
}

private struct RenderedMapRegion {
  let image: UIImage
  let names: [String]
  let heights: [Int16]
  let decoded: Int
  let errors: [String]
  let cacheHits: Int
  let cacheMisses: Int
  let sampleStride: Int
  let sampledChunkCount: Int
  let spawnHits: [MapSpawnHit]
  let playerHits: [MapPlayerHit]
  let worldObjectHits: [MapWorldObjectHit]
  let hardcodedSpawnerHits: [MapHardcodedSpawnerHit]
  let villageHits: [MapVillageHit]
  let playerCount: Int
  let entityCount: Int
  let blockEntityCount: Int
  let hardcodedSpawnerCount: Int
  let villageCount: Int
  let tickingAreaCount: Int
  let tickingDefinedChunkCount: Int
  let visibleTickingChunkCount: Int
}

private final class MapObjectOverlayView: UIView {
  private let villageBoundsLayer = CAShapeLayer()
  private let villageCenterLayer = CAShapeLayer()
  private let villagePOILinkLayer = CAShapeLayer()
  private let villagePOILayer = CAShapeLayer()
  private let entityLayer = CAShapeLayer()
  private let blockEntityLayer = CAShapeLayer()
  private let localPlayerLayer = CAShapeLayer()
  private let onlinePlayerLayer = CAShapeLayer()
  private let hardcodedSpawnerLayer = CAShapeLayer()
  private let worldSpawnLayer = CAShapeLayer()
  private let worldSpawnGlyphLayer = CAShapeLayer()
  private let playerSpawnLayer = CAShapeLayer()
  private let playerSpawnGlyphLayer = CAShapeLayer()
  private let selectedVillageLayer = CAShapeLayer()
  private let selectedSpawnerLayer = CAShapeLayer()
  private let selectedObjectLayer = CAShapeLayer()
  private let selectedBlockLayer = CAShapeLayer()
  private let selectedChunkLayer = CAShapeLayer()
  private let buildHeightLimitLayer = CAShapeLayer()
  private var selectedObjectID: String?

  private var allLayers: [CAShapeLayer] {
    [
      villageBoundsLayer, villageCenterLayer, villagePOILinkLayer, villagePOILayer,
      entityLayer, blockEntityLayer, localPlayerLayer, onlinePlayerLayer, hardcodedSpawnerLayer,
      worldSpawnLayer, worldSpawnGlyphLayer, playerSpawnLayer, playerSpawnGlyphLayer,
      selectedVillageLayer,
      selectedSpawnerLayer, selectedObjectLayer, selectedBlockLayer,
      selectedChunkLayer, buildHeightLimitLayer,
    ]
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    clipsToBounds = true

    villageBoundsLayer.fillColor = UIColor.clear.cgColor
    villageBoundsLayer.strokeColor = UIColor.systemGreen.cgColor
    villageBoundsLayer.lineWidth = 2.0
    villageBoundsLayer.lineDashPattern = [9, 5]
    villageBoundsLayer.lineJoin = .round
    villageBoundsLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(villageBoundsLayer)

    villageCenterLayer.fillColor = UIColor.systemOrange.cgColor
    villageCenterLayer.strokeColor = UIColor.white.cgColor
    villageCenterLayer.lineWidth = 1.3
    villageCenterLayer.lineJoin = .round
    villageCenterLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(villageCenterLayer)

    villagePOILinkLayer.fillColor = UIColor.systemPurple.cgColor
    villagePOILinkLayer.strokeColor = UIColor.systemPurple.withAlphaComponent(0.88).cgColor
    villagePOILinkLayer.lineWidth = 2.0
    villagePOILinkLayer.lineCap = .round
    villagePOILinkLayer.lineJoin = .round
    villagePOILinkLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(villagePOILinkLayer)

    villagePOILayer.fillColor = UIColor.systemPurple.cgColor
    villagePOILayer.strokeColor = UIColor.white.cgColor
    villagePOILayer.lineWidth = 1.0
    villagePOILayer.lineJoin = .round
    villagePOILayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(villagePOILayer)

    configure(entityLayer, fill: .systemBlue)
    configure(blockEntityLayer, fill: .systemTeal)
    configure(localPlayerLayer, fill: .systemYellow)
    configure(onlinePlayerLayer, fill: .systemBlue)

    hardcodedSpawnerLayer.fillColor = UIColor.systemPink.withAlphaComponent(0.10).cgColor
    hardcodedSpawnerLayer.strokeColor = UIColor.systemPink.cgColor
    hardcodedSpawnerLayer.lineWidth = 2.2
    hardcodedSpawnerLayer.lineDashPattern = [7, 4]
    hardcodedSpawnerLayer.lineJoin = .round
    hardcodedSpawnerLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(hardcodedSpawnerLayer)

    configure(worldSpawnLayer, fill: .systemYellow)
    worldSpawnGlyphLayer.fillColor = UIColor.clear.cgColor
    worldSpawnGlyphLayer.strokeColor = UIColor.black.cgColor
    worldSpawnGlyphLayer.lineWidth = 1.4
    worldSpawnGlyphLayer.lineCap = .round
    worldSpawnGlyphLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(worldSpawnGlyphLayer)

    configure(playerSpawnLayer, fill: .systemGreen)
    playerSpawnGlyphLayer.fillColor = UIColor.clear.cgColor
    playerSpawnGlyphLayer.strokeColor = UIColor.black.cgColor
    playerSpawnGlyphLayer.lineWidth = 1.25
    playerSpawnGlyphLayer.lineCap = .round
    playerSpawnGlyphLayer.lineJoin = .round
    playerSpawnGlyphLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(playerSpawnGlyphLayer)

    configureSelectionLayer(
      selectedVillageLayer, fill: UIColor.systemYellow.withAlphaComponent(0.12), dash: [10, 4])
    configureSelectionLayer(
      selectedSpawnerLayer, fill: UIColor.systemYellow.withAlphaComponent(0.16), dash: [6, 3])
    configureSelectionLayer(selectedObjectLayer, fill: .systemYellow, dash: nil)
    configureSelectionLayer(
      selectedBlockLayer, fill: UIColor.systemYellow.withAlphaComponent(0.28), dash: nil)

    selectedChunkLayer.fillColor = UIColor.systemOrange.withAlphaComponent(0.12).cgColor
    selectedChunkLayer.strokeColor = UIColor.systemOrange.cgColor
    selectedChunkLayer.lineWidth = 3.0
    selectedChunkLayer.shadowColor = UIColor.black.cgColor
    selectedChunkLayer.shadowOpacity = 0.75
    selectedChunkLayer.shadowRadius = 2
    selectedChunkLayer.shadowOffset = .zero
    selectedChunkLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(selectedChunkLayer)

    buildHeightLimitLayer.fillColor = UIColor.clear.cgColor
    buildHeightLimitLayer.strokeColor = UIColor.systemRed.cgColor
    buildHeightLimitLayer.lineWidth = 2.0
    buildHeightLimitLayer.lineDashPattern = [8, 5]
    buildHeightLimitLayer.lineCap = .round
    buildHeightLimitLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(buildHeightLimitLayer)

    villageBoundsLayer.zPosition = 10
    entityLayer.zPosition = 30
    blockEntityLayer.zPosition = 31
    localPlayerLayer.zPosition = 33
    onlinePlayerLayer.zPosition = 34
    hardcodedSpawnerLayer.zPosition = 35
    villageCenterLayer.zPosition = 60
    villagePOILinkLayer.zPosition = 80
    worldSpawnLayer.zPosition = 90
    worldSpawnGlyphLayer.zPosition = 91
    playerSpawnLayer.zPosition = 92
    playerSpawnGlyphLayer.zPosition = 93
    villagePOILayer.zPosition = 95
    selectedVillageLayer.zPosition = 100
    selectedSpawnerLayer.zPosition = 101
    selectedObjectLayer.zPosition = 102
    selectedBlockLayer.zPosition = 103
    selectedChunkLayer.zPosition = 104
    buildHeightLimitLayer.zPosition = 110
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    for shapeLayer in allLayers { shapeLayer.frame = bounds }
  }

  private func configure(_ shapeLayer: CAShapeLayer, fill: UIColor) {
    shapeLayer.fillColor = fill.cgColor
    shapeLayer.strokeColor = UIColor.white.cgColor
    shapeLayer.lineWidth = 1.35
    shapeLayer.lineJoin = .round
    shapeLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(shapeLayer)
  }

  private func configureSelectionLayer(_ shapeLayer: CAShapeLayer, fill: UIColor, dash: [NSNumber]?)
  {
    shapeLayer.fillColor = fill.cgColor
    shapeLayer.strokeColor = UIColor.white.cgColor
    shapeLayer.lineWidth = 3.0
    shapeLayer.lineDashPattern = dash
    shapeLayer.lineJoin = .round
    shapeLayer.shadowColor = UIColor.black.cgColor
    shapeLayer.shadowOpacity = 0.8
    shapeLayer.shadowRadius = 2
    shapeLayer.shadowOffset = .zero
    shapeLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(shapeLayer)
  }

  func clear() {
    for shapeLayer in allLayers { shapeLayer.path = nil }
    selectedVillageLayer.removeAnimation(forKey: "selected-village-blink")
    selectedSpawnerLayer.removeAnimation(forKey: "selected-spawner-blink")
    selectedObjectLayer.removeAnimation(forKey: "selected-object-blink")
    selectedBlockLayer.removeAnimation(forKey: "selected-block-blink")
    selectedChunkLayer.removeAnimation(forKey: "selected-chunk-blink")
  }

  func updateBuildHeightLimits(
    minimumRenderedY: Int64,
    maximumRenderedY: Int64,
    dimension: Int32,
    imageView: UIView,
    visible: Bool
  ) {
    clear()
    guard visible, maximumRenderedY >= minimumRenderedY,
      imageView.bounds.width > 0, imageView.bounds.height > 0
    else { return }

    let limits: (minimum: Int64, maximumExclusive: Int64)
    switch BedrockDimension(rawValue: dimension) {
    case .nether?:
      limits = (0, 128)
    case .end?:
      limits = (0, 256)
    default:
      limits = (-64, 320)
    }

    let span = CGFloat(maximumRenderedY - minimumRenderedY + 1)
    guard span > 0 else { return }
    let path = UIBezierPath()
    func appendLimit(_ worldY: Int64) {
      let fromTop = CGFloat(maximumRenderedY - worldY + 1) / span
      let imageY = fromTop * imageView.bounds.height
      let left = imageView.convert(CGPoint(x: 0, y: imageY), to: self)
      let right = imageView.convert(CGPoint(x: imageView.bounds.width, y: imageY), to: self)
      guard max(left.y, right.y) >= bounds.minY - 2, min(left.y, right.y) <= bounds.maxY + 2 else { return }
      path.move(to: left)
      path.addLine(to: right)
    }
    appendLimit(limits.minimum)
    appendLimit(limits.maximumExclusive)
    buildHeightLimitLayer.path = path.cgPath
  }

  func setSelectedObjectID(_ stableID: String?) {
    selectedObjectID = stableID
    if stableID == nil {
      selectedObjectLayer.path = nil
      selectedObjectLayer.removeAnimation(forKey: "selected-object-blink")
    }
  }

  func updateCrossSection(
    spawnHits: [MapSpawnHit],
    playerHits: [MapPlayerHit],
    worldObjectHits: [MapWorldObjectHit],
    hardcodedSpawnerHits: [MapHardcodedSpawnerHit],
    selectedObjectID: String?,
    selectedSpawnerID: String?,
    selectedBlock: BedrockBlockRecord?,
    axis: MapSliceAxis,
    fixedX: Int64,
    fixedZ: Int64,
    minimumHorizontal: Int64,
    minimumY: Int64,
    maximumY: Int64,
    sideBlocks: Int,
    currentDimension: Int32,
    imageView: UIView,
    showBuildHeightLimits: Bool
  ) {
    guard axis != .y, sideBlocks > 0, maximumY >= minimumY,
      imageView.bounds.width > 0, imageView.bounds.height > 0
    else {
      clear()
      return
    }

    let entityPath = UIBezierPath()
    let blockEntityPath = UIBezierPath()
    let localPlayerPath = UIBezierPath()
    let onlinePlayerPath = UIBezierPath()
    let hardcodedSpawnerPath = UIBezierPath()
    let selectedSpawnerPath = UIBezierPath()
    let worldSpawnPath = UIBezierPath()
    let worldSpawnGlyphPath = UIBezierPath()
    let playerSpawnPath = UIBezierPath()
    let playerSpawnGlyphPath = UIBezierPath()
    let selectedPath = UIBezierPath()
    let selectedBlockPath = UIBezierPath()
    let heightPath = UIBezierPath()
    var hasSelectedPath = false
    var hasSelectedSpawnerPath = false
    var hasSelectedBlockPath = false

    func point(localHorizontal: CGFloat, localVertical: CGFloat) -> CGPoint {
      let imagePoint = CGPoint(
        x: localHorizontal / CGFloat(sideBlocks) * imageView.bounds.width,
        y: localVertical / CGFloat(sideBlocks) * imageView.bounds.height
      )
      return imageView.convert(imagePoint, to: self)
    }

    func appendStar(center: CGPoint, to path: UIBezierPath) {
      let outerRadius: CGFloat = 8
      let innerRadius: CGFloat = 3.5
      let star = UIBezierPath()
      for index in 0..<10 {
        let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
        let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
        let p = CGPoint(
          x: center.x + cos(angle) * radius,
          y: center.y + sin(angle) * radius
        )
        if index == 0 { star.move(to: p) } else { star.addLine(to: p) }
      }
      star.close()
      path.append(star)
    }

    for hit in playerHits {
      let center = point(localHorizontal: hit.localX, localVertical: hit.localZ)
      guard bounds.insetBy(dx: -18, dy: -18).contains(center) else { continue }
      appendStar(center: center, to: hit.player.isLocal ? localPlayerPath : onlinePlayerPath)
    }

    for hit in worldObjectHits {
      let center = point(localHorizontal: hit.localX, localVertical: hit.localZ)
      guard bounds.insetBy(dx: -16, dy: -16).contains(center) else { continue }
      if hit.isNormallyVisible {
        if hit.object.kind == .entity {
          entityPath.append(
            UIBezierPath(ovalIn: CGRect(x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11)))
        } else {
          blockEntityPath.append(
            UIBezierPath(
              roundedRect: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10),
              cornerRadius: 1.5))
        }
      }
      if hit.object.stableID == selectedObjectID {
        hasSelectedPath = true
        let rect = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
        if hit.object.kind == .entity {
          selectedPath.append(UIBezierPath(ovalIn: rect))
        } else {
          selectedPath.append(UIBezierPath(roundedRect: rect, cornerRadius: 2.5))
        }
      }
    }

    for hit in spawnHits {
      let center = point(localHorizontal: hit.localX, localVertical: hit.localZ)
      guard bounds.insetBy(dx: -18, dy: -18).contains(center) else { continue }
      switch hit.spawn.kind {
      case .world:
        worldSpawnPath.append(
          UIBezierPath(ovalIn: CGRect(x: center.x - 6.5, y: center.y - 6.5, width: 13, height: 13)))
        worldSpawnGlyphPath.move(to: CGPoint(x: center.x - 3.2, y: center.y))
        worldSpawnGlyphPath.addLine(to: CGPoint(x: center.x + 3.2, y: center.y))
        worldSpawnGlyphPath.move(to: CGPoint(x: center.x, y: center.y - 3.2))
        worldSpawnGlyphPath.addLine(to: CGPoint(x: center.x, y: center.y + 3.2))
      case .player:
        playerSpawnPath.append(
          UIBezierPath(ovalIn: CGRect(x: center.x - 6.5, y: center.y - 6.5, width: 13, height: 13)))
        playerSpawnGlyphPath.append(
          UIBezierPath(ovalIn: CGRect(x: center.x - 1.8, y: center.y - 3.6, width: 3.6, height: 3.6)))
        playerSpawnGlyphPath.move(to: CGPoint(x: center.x - 3.2, y: center.y + 3.5))
        playerSpawnGlyphPath.addQuadCurve(
          to: CGPoint(x: center.x + 3.2, y: center.y + 3.5),
          controlPoint: CGPoint(x: center.x, y: center.y - 0.4))
      }
    }

    for hit in hardcodedSpawnerHits {
      let area = hit.area
      let planeIntersects: Bool
      let horizontalMinimum: Int64
      let horizontalMaximum: Int64
      switch axis {
      case .x:
        planeIntersects = fixedX >= Int64(area.minimumX) && fixedX <= Int64(area.maximumX)
        horizontalMinimum = Int64(area.minimumZ)
        horizontalMaximum = Int64(area.maximumZ)
      case .z:
        planeIntersects = fixedZ >= Int64(area.minimumZ) && fixedZ <= Int64(area.maximumZ)
        horizontalMinimum = Int64(area.minimumX)
        horizontalMaximum = Int64(area.maximumX)
      case .y:
        planeIntersects = false
        horizontalMinimum = 0
        horizontalMaximum = -1
      }
      guard planeIntersects else { continue }
      let clippedH0 = max(horizontalMinimum, minimumHorizontal)
      let clippedH1 = min(horizontalMaximum, minimumHorizontal + Int64(sideBlocks) - 1)
      let clippedY0 = max(Int64(area.minimumY), minimumY)
      let clippedY1 = min(Int64(area.maximumY), maximumY)
      guard clippedH0 <= clippedH1, clippedY0 <= clippedY1 else { continue }
      let topLeft = point(
        localHorizontal: CGFloat(clippedH0 - minimumHorizontal),
        localVertical: CGFloat(maximumY - clippedY1))
      let bottomRight = point(
        localHorizontal: CGFloat(clippedH1 - minimumHorizontal + 1),
        localVertical: CGFloat(maximumY - clippedY0 + 1))
      let rect = CGRect(
        x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
        width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y)
      ).insetBy(dx: 1, dy: 1)
      if rect.width > 1, rect.height > 1 {
        hardcodedSpawnerPath.append(UIBezierPath(rect: rect))
        if hit.stableID == selectedSpawnerID {
          selectedSpawnerPath.append(UIBezierPath(rect: rect.insetBy(dx: -2, dy: -2)))
          hasSelectedSpawnerPath = true
        }
      }
    }

    if let block = selectedBlock, block.dimension == currentDimension {
      // The X/Z picker selects along the axis perpendicular to the visible
      // plane. Even when the chosen block is deeper than the displayed slice,
      // its horizontal/Y projection is still the point the user tapped, so
      // keep that point highlighted and blinking on the section.
      let horizontal = axis == .x ? block.z : block.x
      if horizontal >= minimumHorizontal,
        horizontal < minimumHorizontal + Int64(sideBlocks),
        Int64(block.y) >= minimumY, Int64(block.y) <= maximumY
      {
        let topLeft = point(
          localHorizontal: CGFloat(horizontal - minimumHorizontal),
          localVertical: CGFloat(maximumY - Int64(block.y)))
        let bottomRight = point(
          localHorizontal: CGFloat(horizontal - minimumHorizontal + 1),
          localVertical: CGFloat(maximumY - Int64(block.y) + 1))
        var rect = CGRect(
          x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
          width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y)
        )
        if rect.width < 12 { rect = rect.insetBy(dx: -(12 - rect.width) / 2, dy: 0) }
        if rect.height < 12 { rect = rect.insetBy(dx: 0, dy: -(12 - rect.height) / 2) }
        selectedBlockPath.append(UIBezierPath(rect: rect.insetBy(dx: -1, dy: -1)))
        hasSelectedBlockPath = true
      }
    }

    if showBuildHeightLimits {
      let limits: (minimum: Int64, maximumExclusive: Int64)
      switch BedrockDimension(rawValue: currentDimension) {
      case .nether?: limits = (0, 128)
      case .end?: limits = (0, 256)
      default: limits = (-64, 320)
      }
      let span = CGFloat(maximumY - minimumY + 1)
      func appendLimit(_ y: Int64) {
        let imageY = CGFloat(maximumY - y + 1) / span * imageView.bounds.height
        let left = imageView.convert(CGPoint(x: 0, y: imageY), to: self)
        let right = imageView.convert(CGPoint(x: imageView.bounds.width, y: imageY), to: self)
        guard max(left.y, right.y) >= bounds.minY - 2,
          min(left.y, right.y) <= bounds.maxY + 2 else { return }
        heightPath.move(to: left)
        heightPath.addLine(to: right)
      }
      appendLimit(limits.minimum)
      appendLimit(limits.maximumExclusive)
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    villageBoundsLayer.path = nil
    villageCenterLayer.path = nil
    villagePOILinkLayer.path = nil
    villagePOILayer.path = nil
    selectedVillageLayer.path = nil
    selectedChunkLayer.path = nil
    entityLayer.path = entityPath.cgPath
    blockEntityLayer.path = blockEntityPath.cgPath
    localPlayerLayer.path = localPlayerPath.cgPath
    onlinePlayerLayer.path = onlinePlayerPath.cgPath
    hardcodedSpawnerLayer.path = hardcodedSpawnerPath.cgPath
    worldSpawnLayer.path = worldSpawnPath.cgPath
    worldSpawnGlyphLayer.path = worldSpawnGlyphPath.cgPath
    playerSpawnLayer.path = playerSpawnPath.cgPath
    playerSpawnGlyphLayer.path = playerSpawnGlyphPath.cgPath
    selectedSpawnerLayer.path = hasSelectedSpawnerPath ? selectedSpawnerPath.cgPath : nil
    selectedObjectLayer.path = hasSelectedPath ? selectedPath.cgPath : nil
    selectedBlockLayer.path = hasSelectedBlockPath ? selectedBlockPath.cgPath : nil
    buildHeightLimitLayer.path = heightPath.cgPath
    CATransaction.commit()

    self.selectedObjectID = selectedObjectID
    updateBlink(layer: selectedVillageLayer, key: "selected-village-blink", enabled: false, duration: 0.62)
    updateBlink(
      layer: selectedSpawnerLayer, key: "selected-spawner-blink", enabled: hasSelectedSpawnerPath,
      duration: 0.54)
    updateBlink(
      layer: selectedObjectLayer, key: "selected-object-blink", enabled: hasSelectedPath,
      duration: 0.48)
    updateBlink(
      layer: selectedBlockLayer, key: "selected-block-blink", enabled: hasSelectedBlockPath,
      duration: 0.42)
    updateBlink(layer: selectedChunkLayer, key: "selected-chunk-blink", enabled: false, duration: 0.58)
  }

  func update(
    spawnHits: [MapSpawnHit],
    playerHits: [MapPlayerHit],
    worldObjectHits: [MapWorldObjectHit],
    hardcodedSpawnerHits: [MapHardcodedSpawnerHit],
    villageHits: [MapVillageHit],
    villagePOILinks: [MapVillagePOILink],
    selectedObjectID: String?,
    selectedVillageID: String?,
    selectedVillageEntityIDs: Set<String>,
    selectedSpawnerID: String?,
    selectedBlock: BedrockBlockRecord?,
    selectedChunk: ChunkPosition?,
    currentDimension: Int32,
    startBlockX: Int64,
    startBlockZ: Int64,
    sideBlocks: Int,
    imageView: UIView
  ) {
    guard sideBlocks > 0, imageView.bounds.width > 0, imageView.bounds.height > 0 else {
      clear()
      return
    }
    // The red building-height lines are a cross-section-only overlay. Clear
    // them explicitly when returning to the normal Y-axis top-down map.
    buildHeightLimitLayer.path = nil

    let entityPath = UIBezierPath()
    let blockEntityPath = UIBezierPath()
    let localPlayerPath = UIBezierPath()
    let onlinePlayerPath = UIBezierPath()
    let hardcodedSpawnerPath = UIBezierPath()
    let villageBoundsPath = UIBezierPath()
    let villageCenterPath = UIBezierPath()
    let villagePOILinkPath = UIBezierPath()
    let villagePOIPath = UIBezierPath()
    let selectedVillagePath = UIBezierPath()
    let selectedSpawnerPath = UIBezierPath()
    let worldSpawnPath = UIBezierPath()
    let worldSpawnGlyphPath = UIBezierPath()
    let playerSpawnPath = UIBezierPath()
    let playerSpawnGlyphPath = UIBezierPath()
    let selectedPath = UIBezierPath()
    var hasSelectedPath = false
    var hasSelectedVillagePath = false
    var hasSelectedSpawnerPath = false

    func point(localX: CGFloat, localZ: CGFloat) -> CGPoint {
      let imagePoint = CGPoint(
        x: localX / CGFloat(sideBlocks) * imageView.bounds.width,
        y: localZ / CGFloat(sideBlocks) * imageView.bounds.height
      )
      return imageView.convert(imagePoint, to: self)
    }

    func clippedRect(minX: Int64, minZ: Int64, maxX: Int64, maxZ: Int64) -> CGRect? {
      let minimumLocalX = CGFloat(minX - startBlockX)
      let minimumLocalZ = CGFloat(minZ - startBlockZ)
      let maximumLocalX = CGFloat(maxX - startBlockX + 1)
      let maximumLocalZ = CGFloat(maxZ - startBlockZ + 1)
      guard maximumLocalX > 0, maximumLocalZ > 0,
        minimumLocalX < CGFloat(sideBlocks), minimumLocalZ < CGFloat(sideBlocks)
      else { return nil }
      let topLeft = point(localX: max(0, minimumLocalX), localZ: max(0, minimumLocalZ))
      let bottomRight = point(
        localX: min(CGFloat(sideBlocks), maximumLocalX),
        localZ: min(CGFloat(sideBlocks), maximumLocalZ)
      )
      let rect = CGRect(
        x: min(topLeft.x, bottomRight.x),
        y: min(topLeft.y, bottomRight.y),
        width: abs(bottomRight.x - topLeft.x),
        height: abs(bottomRight.y - topLeft.y)
      ).insetBy(dx: 1, dy: 1)
      return rect.width > 1 && rect.height > 1 ? rect : nil
    }

    func unclippedRect(minX: Int64, minZ: Int64, maxX: Int64, maxZ: Int64) -> CGRect? {
      let minimumLocalX = CGFloat(minX - startBlockX)
      let minimumLocalZ = CGFloat(minZ - startBlockZ)
      let maximumLocalX = CGFloat(maxX - startBlockX + 1)
      let maximumLocalZ = CGFloat(maxZ - startBlockZ + 1)
      guard maximumLocalX > 0, maximumLocalZ > 0,
        minimumLocalX < CGFloat(sideBlocks), minimumLocalZ < CGFloat(sideBlocks)
      else { return nil }
      let topLeft = point(localX: minimumLocalX, localZ: minimumLocalZ)
      let bottomRight = point(localX: maximumLocalX, localZ: maximumLocalZ)
      let rect = CGRect(
        x: min(topLeft.x, bottomRight.x),
        y: min(topLeft.y, bottomRight.y),
        width: abs(bottomRight.x - topLeft.x),
        height: abs(bottomRight.y - topLeft.y)
      ).insetBy(dx: 1, dy: 1)
      return rect.width > 1 && rect.height > 1 ? rect : nil
    }

    for hit in villageHits {
      let feature = hit.feature
      if let villageBounds = feature.bounds,
        let rect = clippedRect(
          minX: villageBounds.minimumX, minZ: villageBounds.minimumZ,
          maxX: villageBounds.maximumX, maxZ: villageBounds.maximumZ
        )
      {
        villageBoundsPath.append(UIBezierPath(rect: rect))
        if hit.stableID == selectedVillageID {
          selectedVillagePath.append(UIBezierPath(rect: rect.insetBy(dx: -2, dy: -2)))
          hasSelectedVillagePath = true
        }
      }
      if let center = feature.center {
        let localX = CGFloat(center.x - startBlockX) + 0.5
        let localZ = CGFloat(center.z - startBlockZ) + 0.5
        let p = point(localX: localX, localZ: localZ)
        if bounds.insetBy(dx: -18, dy: -18).contains(p) {
          let diamond = UIBezierPath()
          diamond.move(to: CGPoint(x: p.x, y: p.y - 7))
          diamond.addLine(to: CGPoint(x: p.x + 7, y: p.y))
          diamond.addLine(to: CGPoint(x: p.x, y: p.y + 7))
          diamond.addLine(to: CGPoint(x: p.x - 7, y: p.y))
          diamond.close()
          villageCenterPath.append(diamond)
          if hit.stableID == selectedVillageID, !hasSelectedVillagePath {
            selectedVillagePath.append(
              UIBezierPath(ovalIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)))
            hasSelectedVillagePath = true
          }
        }
      }
      for poi in feature.pointsOfInterest {
        let localX = CGFloat(poi.x - startBlockX) + 0.5
        let localZ = CGFloat(poi.z - startBlockZ) + 0.5
        let p = point(localX: localX, localZ: localZ)
        if bounds.insetBy(dx: -12, dy: -12).contains(p) {
          villagePOIPath.append(
            UIBezierPath(
              roundedRect: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7),
              cornerRadius: 1.2))
        }
      }
    }

    for link in villagePOILinks {
      let source = point(localX: link.entityLocalX, localZ: link.entityLocalZ)
      let destination = point(
        localX: CGFloat(link.point.x - startBlockX) + 0.5,
        localZ: CGFloat(link.point.z - startBlockZ) + 0.5
      )
      guard bounds.insetBy(dx: -20, dy: -20).contains(source),
        bounds.insetBy(dx: -20, dy: -20).contains(destination)
      else { continue }
      let dx = destination.x - source.x
      let dy = destination.y - source.y
      let length = hypot(dx, dy)
      guard length > 5 else { continue }
      let ux = dx / length
      let uy = dy / length
      let lineStart = CGPoint(x: source.x + ux * 7, y: source.y + uy * 7)
      let tip = CGPoint(x: destination.x - ux * 5, y: destination.y - uy * 5)
      villagePOILinkPath.move(to: lineStart)
      villagePOILinkPath.addLine(to: tip)
      let perpendicular = CGPoint(x: -uy, y: ux)
      let arrowLength: CGFloat = 6
      let arrowWidth: CGFloat = 3.5
      let base = CGPoint(x: tip.x - ux * arrowLength, y: tip.y - uy * arrowLength)
      villagePOILinkPath.move(to: tip)
      villagePOILinkPath.addLine(
        to: CGPoint(
          x: base.x + perpendicular.x * arrowWidth, y: base.y + perpendicular.y * arrowWidth))
      villagePOILinkPath.addLine(
        to: CGPoint(
          x: base.x - perpendicular.x * arrowWidth, y: base.y - perpendicular.y * arrowWidth))
      villagePOILinkPath.close()
    }

    func appendStar(center: CGPoint, to path: UIBezierPath) {
      let outerRadius: CGFloat = 8
      let innerRadius: CGFloat = 3.5
      let star = UIBezierPath()
      for index in 0..<10 {
        let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
        let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
        let point = CGPoint(
          x: center.x + cos(angle) * radius,
          y: center.y + sin(angle) * radius
        )
        if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
      }
      star.close()
      path.append(star)
    }

    for hit in playerHits {
      let center = point(localX: hit.localX, localZ: hit.localZ)
      guard bounds.insetBy(dx: -18, dy: -18).contains(center) else { continue }
      appendStar(center: center, to: hit.player.isLocal ? localPlayerPath : onlinePlayerPath)
    }

    for hit in worldObjectHits {
      let center = point(localX: hit.localX, localZ: hit.localZ)
      guard bounds.insetBy(dx: -16, dy: -16).contains(center) else { continue }
      if hit.isNormallyVisible {
        if hit.object.kind == .entity {
          entityPath.append(
            UIBezierPath(
              ovalIn: CGRect(x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11)))
        } else {
          blockEntityPath.append(
            UIBezierPath(
              roundedRect: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10),
              cornerRadius: 1.5))
        }
      }
      if hit.object.stableID == selectedObjectID
        || selectedVillageEntityIDs.contains(hit.object.stableID)
      {
        hasSelectedPath = true
        if hit.object.kind == .entity {
          selectedPath.append(
            UIBezierPath(ovalIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)))
        } else {
          selectedPath.append(
            UIBezierPath(
              roundedRect: CGRect(x: center.x - 7.5, y: center.y - 7.5, width: 15, height: 15),
              cornerRadius: 2.5))
        }
      }
    }

    for hit in hardcodedSpawnerHits {
      let area = hit.area
      guard
        let rect = clippedRect(
          minX: Int64(area.minimumX), minZ: Int64(area.minimumZ),
          maxX: Int64(area.maximumX), maxZ: Int64(area.maximumZ)
        )
      else { continue }
      hardcodedSpawnerPath.append(UIBezierPath(rect: rect))
      if hit.stableID == selectedSpawnerID {
        selectedSpawnerPath.append(UIBezierPath(rect: rect.insetBy(dx: -2, dy: -2)))
        hasSelectedSpawnerPath = true
      }
    }

    for hit in spawnHits {
      let center = point(localX: hit.localX, localZ: hit.localZ)
      guard bounds.insetBy(dx: -18, dy: -18).contains(center) else { continue }
      switch hit.spawn.kind {
      case .world:
        worldSpawnPath.append(
          UIBezierPath(ovalIn: CGRect(x: center.x - 6.5, y: center.y - 6.5, width: 13, height: 13)))
        worldSpawnGlyphPath.move(to: CGPoint(x: center.x - 3.2, y: center.y))
        worldSpawnGlyphPath.addLine(to: CGPoint(x: center.x + 3.2, y: center.y))
        worldSpawnGlyphPath.move(to: CGPoint(x: center.x, y: center.y - 3.2))
        worldSpawnGlyphPath.addLine(to: CGPoint(x: center.x, y: center.y + 3.2))
      case .player:
        playerSpawnPath.append(
          UIBezierPath(ovalIn: CGRect(x: center.x - 6.5, y: center.y - 6.5, width: 13, height: 13)))
        playerSpawnGlyphPath.append(
          UIBezierPath(
            ovalIn: CGRect(x: center.x - 1.8, y: center.y - 3.6, width: 3.6, height: 3.6)))
        playerSpawnGlyphPath.move(to: CGPoint(x: center.x - 3.2, y: center.y + 3.5))
        playerSpawnGlyphPath.addQuadCurve(
          to: CGPoint(x: center.x + 3.2, y: center.y + 3.5),
          controlPoint: CGPoint(x: center.x, y: center.y - 0.4))
      }
    }

    var hasSelectedBlockPath = false
    let selectedBlockPath = UIBezierPath()
    if let block = selectedBlock {
      let localX = CGFloat(block.x - startBlockX)
      let localZ = CGFloat(block.z - startBlockZ)
      if localX >= 0, localZ >= 0, localX < CGFloat(sideBlocks), localZ < CGFloat(sideBlocks) {
        let topLeft = point(localX: localX, localZ: localZ)
        let bottomRight = point(localX: localX + 1, localZ: localZ + 1)
        var rect = CGRect(
          x: min(topLeft.x, bottomRight.x),
          y: min(topLeft.y, bottomRight.y),
          width: abs(bottomRight.x - topLeft.x),
          height: abs(bottomRight.y - topLeft.y)
        )
        if rect.width < 12 { rect = rect.insetBy(dx: -(12 - rect.width) / 2, dy: 0) }
        if rect.height < 12 { rect = rect.insetBy(dx: 0, dy: -(12 - rect.height) / 2) }
        selectedBlockPath.append(UIBezierPath(rect: rect.insetBy(dx: -1, dy: -1)))
        hasSelectedBlockPath = true
      }
    }

    var hasSelectedChunkPath = false
    let selectedChunkPath = UIBezierPath()
    if let chunk = selectedChunk, chunk.dimension == currentDimension {
      let chunkBlockX = Int64(chunk.x) * 16
      let chunkBlockZ = Int64(chunk.z) * 16
      let localX = CGFloat(chunkBlockX - startBlockX)
      let localZ = CGFloat(chunkBlockZ - startBlockZ)
      if localX + 16 > 0, localZ + 16 > 0, localX < CGFloat(sideBlocks),
        localZ < CGFloat(sideBlocks)
      {
        let topLeft = point(localX: localX, localZ: localZ)
        let bottomRight = point(localX: localX + 16, localZ: localZ + 16)
        let rect = CGRect(
          x: min(topLeft.x, bottomRight.x),
          y: min(topLeft.y, bottomRight.y),
          width: abs(bottomRight.x - topLeft.x),
          height: abs(bottomRight.y - topLeft.y)
        ).insetBy(dx: -1.5, dy: -1.5)
        selectedChunkPath.append(UIBezierPath(rect: rect))
        hasSelectedChunkPath = true
      }
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    villageBoundsLayer.path = villageBoundsPath.cgPath
    villageCenterLayer.path = villageCenterPath.cgPath
    villagePOILinkLayer.path = villagePOILinkPath.cgPath
    villagePOILayer.path = villagePOIPath.cgPath
    entityLayer.path = entityPath.cgPath
    blockEntityLayer.path = blockEntityPath.cgPath
    localPlayerLayer.path = localPlayerPath.cgPath
    onlinePlayerLayer.path = onlinePlayerPath.cgPath
    hardcodedSpawnerLayer.path = hardcodedSpawnerPath.cgPath
    worldSpawnLayer.path = worldSpawnPath.cgPath
    worldSpawnGlyphLayer.path = worldSpawnGlyphPath.cgPath
    playerSpawnLayer.path = playerSpawnPath.cgPath
    playerSpawnGlyphLayer.path = playerSpawnGlyphPath.cgPath
    selectedVillageLayer.path = hasSelectedVillagePath ? selectedVillagePath.cgPath : nil
    selectedSpawnerLayer.path = hasSelectedSpawnerPath ? selectedSpawnerPath.cgPath : nil
    selectedObjectLayer.path = hasSelectedPath ? selectedPath.cgPath : nil
    selectedBlockLayer.path = hasSelectedBlockPath ? selectedBlockPath.cgPath : nil
    selectedChunkLayer.path = hasSelectedChunkPath ? selectedChunkPath.cgPath : nil
    CATransaction.commit()

    self.selectedObjectID = selectedObjectID
    updateBlink(
      layer: selectedVillageLayer, key: "selected-village-blink", enabled: hasSelectedVillagePath,
      duration: 0.62)
    updateBlink(
      layer: selectedSpawnerLayer, key: "selected-spawner-blink", enabled: hasSelectedSpawnerPath,
      duration: 0.54)
    updateBlink(
      layer: selectedObjectLayer, key: "selected-object-blink", enabled: hasSelectedPath,
      duration: 0.48)
    updateBlink(
      layer: selectedBlockLayer, key: "selected-block-blink", enabled: hasSelectedBlockPath,
      duration: 0.42)
    updateBlink(
      layer: selectedChunkLayer, key: "selected-chunk-blink", enabled: hasSelectedChunkPath,
      duration: 0.58)
  }

  private func updateBlink(
    layer: CAShapeLayer, key: String, enabled: Bool, duration: CFTimeInterval
  ) {
    if !enabled {
      layer.removeAnimation(forKey: key)
    } else if layer.animation(forKey: key) == nil {
      let animation = CABasicAnimation(keyPath: "opacity")
      animation.fromValue = 1.0
      animation.toValue = 0.16
      animation.duration = duration
      animation.autoreverses = true
      animation.repeatCount = .infinity
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      layer.add(animation, forKey: key)
    }
  }
}

final class WorldMapViewController: UIViewController, UIScrollViewDelegate, UITextFieldDelegate,
  UIGestureRecognizerDelegate
{
  private let session: WorldSession
  private let scrollView = UIScrollView()
  private let imageView = UIImageView()
  private let objectOverlayView = MapObjectOverlayView()
  private let selectionOverlayView = MapSelectionOverlayView()
  private let blockDetailPanel = MapBlockDetailPanelView()
  private var detailPanelWidthConstraint: NSLayoutConstraint!
  private var imageWidthConstraint: NSLayoutConstraint!
  private var imageHeightConstraint: NSLayoutConstraint!
  private let basePointsPerBlock: CGFloat = 32
  private let panMarginFactor: CGFloat = 0.75
  // The render window is derived entirely from the current viewport and
  // zoom level. A two-chunk border remains preloaded around the visible
  // area. There is no application-defined chunk-side limit: zooming out
  // expands the rendered region to cover the current viewport.
  private let minimumDynamicSideChunks = 3
  private let dynamicPreloadBorderChunks = 2
  // These are only the initial gesture bounds. They expand by a factor of
  // two whenever the user reaches either edge, so there is no fixed zoom
  // range while avoiding one huge jump on the first pinch.
  private let initialMinimumZoomScale: CGFloat = 0.08
  private let initialMaximumZoomScale: CGFloat = 32
  private let zoomRangeGrowthFactor: CGFloat = 2
  // Do not mutate UIScrollView's zoom limits continuously while a pinch is
  // in progress. iPhone UIScrollView can shift contentOffset aggressively
  // when minimumZoomScale changes under an active gesture. Instead widen the
  // usable range once at gesture start; further gestures can widen it again.
  private let userGestureZoomRangeFactor: CGFloat = 4096
  // Raster and per-block metadata are detail limits, not world-extent
  // limits. Large regions continue to include every requested chunk but are
  // composited at a lower pixel density; taps read the selected column from
  // LevelDB when the per-block cache is intentionally omitted.
  private let maximumMapRasterSidePixels: CGFloat = 8_192
  // Keep UIKit view/layer geometry finite even when the represented world
  // extent grows without a chunk limit. The raw UIScrollView zoom is
  // renormalized so the user-visible points-per-block stays unchanged.
  private let maximumMapCanvasSidePoints: CGFloat = 65_536
  private let maximumPerBlockMetadataSide = 2_048
  private let maximumDecodedChunksPerAxis = 64
  private let maximumBedrockChunkSpan =
    Int(Int64(Int32.max) - Int64(Int32.min) + 1)
  private var canvasPointsPerBlock: CGFloat = 32
  private let xField = UITextField()
  private let yField = UITextField()
  private let zField = UITextField()
  private let sliceAxisControl = UISegmentedControl(items: MapSliceAxis.allCases.map(\.displayName))
  private let coordinateModeControl = UISegmentedControl(items: ["区块坐标", "方块坐标"])
  private let dimensionControl = UISegmentedControl(
    items: BedrockDimension.allCases.map(\.displayName))
  private let modeControl = UISegmentedControl(items: MapRenderMode.allCases.map(\.displayName))
  private let autoRenderSwitch = UISwitch()
  private let gridSwitch = UISwitch()
  private let chunkSelectionSwitch = UISwitch()
  private let statusLabel = UILabel()
  private let zoomLabel = UILabel()
  private weak var gridOptionTitleLabel: UILabel?

  private lazy var shareButton = UIBarButtonItem(
    barButtonSystemItem: .action,
    target: self,
    action: #selector(shareRenderedMap)
  )
  private lazy var cancelSelectionButton: UIBarButtonItem = {
    let item = UIBarButtonItem(
      image: UIImage(systemName: "xmark.circle"),
      style: .plain,
      target: self,
      action: #selector(cancelAllSelections)
    )
    item.accessibilityLabel = "取消全部选择"
    return item
  }()
  private lazy var overlayButton = UIBarButtonItem(
    image: UIImage(systemName: "person.2.square.stack"),
    style: .plain,
    target: self,
    action: #selector(showOverlayOptions)
  )
  private lazy var zoomButton = UIBarButtonItem(
    image: UIImage(systemName: "magnifyingglass"),
    style: .plain,
    target: self,
    action: #selector(showZoomOptions)
  )
  private lazy var selectionButtonView: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "viewfinder"), for: .normal)
    button.addTarget(self, action: #selector(toggleSelectionMode), for: .touchUpInside)
    button.accessibilityLabel = "框选"
    button.widthAnchor.constraint(equalToConstant: 32).isActive = true
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    return button
  }()
  private lazy var selectionButton = UIBarButtonItem(customView: selectionButtonView)

  private let chunkCache = ChunkSurfaceCache()
  private let renderQueue = DispatchQueue(
    label: "com.wzn.mcbeeditor.map-render", qos: .userInitiated)
  private let chunkMenuQueue = DispatchQueue(
    label: "com.wzn.mcbeeditor.map-chunk-menu", qos: .userInitiated)
  private var chunkRenderer: ChunkSurfaceRenderer?
  private var activeRenderToken: MapRenderToken?
  private var panDebounceWorkItem: DispatchWorkItem?

  private var lastBlockNames: [String] = []
  private var lastBlockHeights: [Int16] = []
  private var lastRenderedImage: UIImage?
  private var lastErrors: [String] = []
  private var lastSpawnHits = [MapSpawnHit]()
  private var lastPlayerHits = [MapPlayerHit]()
  private var lastWorldObjectHits: [MapWorldObjectHit] = []
  private var lastHardcodedSpawnerHits: [MapHardcodedSpawnerHit] = []
  private var lastVillageHits: [MapVillageHit] = []
  private var renderedSideChunks = 5
  private var lastCenterX: Int32 = 0
  private var lastCenterZ: Int32 = 0
  private var activeDimension: Int32 = BedrockDimension.overworld.rawValue
  private var dimensionViewportStates = [Int32: MapDimensionViewportState]()
  private var renderedLeftChunks: Int { max(0, (renderedSideChunks - 1) / 2) }
  private var renderedRightChunks: Int { max(0, renderedSideChunks - renderedLeftChunks - 1) }
  private var renderedScanRadius: Int { max(renderedLeftChunks, renderedRightChunks) }
  private var renderedStartChunkX64: Int64 { Int64(lastCenterX) - Int64(renderedLeftChunks) }
  private var renderedStartChunkZ64: Int64 { Int64(lastCenterZ) - Int64(renderedLeftChunks) }
  private var renderedStartBlockX: Int64 { renderedStartChunkX64 * 16 }
  private var renderedStartBlockZ: Int64 { renderedStartChunkZ64 * 16 }
  private var currentMode: MapRenderMode = .surface
  private var currentSliceAxis: MapSliceAxis {
    MapSliceAxis(rawValue: sliceAxisControl.selectedSegmentIndex) ?? .y
  }
  private var renderGeneration = 0
  private var isApplyingViewport = false
  private var isRendering = false
  private var spawnX: Int64?
  private var spawnY: Int32?
  private var spawnZ: Int64?
  private var spawnCoordinates = [MapSpawnCoordinate]()
  private var showPlayers = true
  private var showEntities = true
  private var showBlockEntities = true
  private var showHardcodedSpawners = false
  private var showVillages = false
  private var showSpawnPoints = true
  private var showUngeneratedChunks = false
  private var showBuildHeightLimits = true
  private let crossSectionSelectionHalfRange: Int64 = 128
  private let crossSectionObjectPlaneTolerance: Double = 0.99
  private let crossSectionDefaultSideBlocks = 256
  private var sliceCenterY: Int32 = 0
  private var sliceCenterBlockX: Int64 = 0
  private var sliceCenterBlockZ: Int64 = 0
  private var renderedCrossHorizontalStart: Int64 = 0
  private var renderedCrossMinimumY: Int64 = -64
  private var renderedCrossMaximumY: Int64 = 319
  private var isZooming = false
  private var zoomHUDWorkItem: DispatchWorkItem?
  private var isSelectionMode = false
  private var selectionStartPoint: CGPoint?
  private var selectedRegion: BedrockMapRegion?
  private var selectionEdgeDragOrigin: BedrockMapRegion?
  private var selectedWorldObjectID: String?
  private var selectedVillageID: String?
  private var selectedVillageEntityIDs = Set<String>()
  private var selectedSpawnerID: String?
  private var selectedBlock: BedrockBlockRecord?
  private var selectedChunk: ChunkPosition?
  private var selectionMapPanOrigin: CGPoint?
  private var selectionPinchOriginZoom: CGFloat?
  private var selectionPinchAnchorContent: CGPoint?
  private lazy var selectionPanGesture: UIPanGestureRecognizer = {
    let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleSelectionPan(_:)))
    gesture.minimumNumberOfTouches = 1
    gesture.maximumNumberOfTouches = 1
    gesture.isEnabled = false
    gesture.delegate = self
    return gesture
  }()
  private lazy var selectionMapPanGesture: UIPanGestureRecognizer = {
    let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleSelectionMapPan(_:)))
    gesture.minimumNumberOfTouches = 2
    gesture.maximumNumberOfTouches = 2
    gesture.isEnabled = false
    gesture.delegate = self
    return gesture
  }()
  private lazy var selectionMapPinchGesture: UIPinchGestureRecognizer = {
    let gesture = UIPinchGestureRecognizer(
      target: self, action: #selector(handleSelectionMapPinch(_:)))
    gesture.isEnabled = false
    gesture.delegate = self
    return gesture
  }()

  init(session: WorldSession) {
    self.session = session
    super.init(nibName: nil, bundle: nil)
    title = "地图"
    tabBarItem = UITabBarItem(title: "地图", image: UIImage(systemName: "map"), tag: 0)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    configureUI()
    blockDetailPanel.onJump = { [weak self] x, y, z in self?.jumpToBlock(x: x, y: y, z: z) }
    blockDetailPanel.onSave = { [weak self] block, layerIndex, document in
      self?.saveBlockNBT(block: block, layerIndex: layerIndex, document: document)
    }
    blockDetailPanel.onCollapsedChanged = { [weak self] collapsed in
      self?.setBlockDetailPanelCollapsed(collapsed, animated: true)
    }
    blockDetailPanel.onReturnToSearchResults = { [weak self] in
      (self?.tabBarController as? WorldDetailTabBarController)?.showRememberedBlockSearchResults()
    }
    setBlockDetailPanelCollapsed(blockDetailPanel.isCollapsed, animated: false)
    navigationItem.rightBarButtonItems = [
      shareButton, overlayButton, selectionButton, zoomButton, cancelSelectionButton,
    ]
    shareButton.isEnabled = false
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(worldDidChange(_:)),
      name: WorldSession.worldDidChangeNotification,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(mapBlockSelectionRequested),
      name: WorldSession.mapBlockSelectionNotification,
      object: session
    )
    loadSpawn()
    _ = restoreMapState()
    jumpToDefaultCenter()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    activeRenderToken?.cancel()
    panDebounceWorkItem?.cancel()
    zoomHUDWorkItem?.cancel()
  }

  @objc private func mapBlockSelectionRequested() {
    guard let coordinate = session.requestedMapBlockCoordinate,
      let dimensionIndex = BedrockDimension.allCases.firstIndex(where: {
        $0.rawValue == coordinate.dimension
      })
    else { return }
    loadViewIfNeeded()
    dimensionControl.selectedSegmentIndex = dimensionIndex
    coordinateModeControl.selectedSegmentIndex = 1
    let x = Int64(coordinate.x.rounded(.towardZero))
    let y = Int32(clamping: Int64(coordinate.y.rounded(.towardZero)))
    let z = Int64(coordinate.z.rounded(.towardZero))
    xField.text = String(x)
    zField.text = String(z)
    jumpToBlock(x: x, y: y, z: z)
  }

  @objc private func worldDidChange(_ notification: Notification) {
    switch WorldSession.changeKind(from: notification) {
    case .databaseMutation:
      refreshAfterDatabaseMutation()
    case .externalReload:
      resetAfterExternalWorldChange()
    }
  }

  private func refreshAfterDatabaseMutation() {
    activeRenderToken?.cancel()
    panDebounceWorkItem?.cancel()
    let anchor = currentViewportAnchor()
    let center = anchor.map { chunkCenter(for: $0) } ?? (lastCenterX, lastCenterZ)

    selectedBlock = nil
    selectedWorldObjectID = nil
    selectedVillageID = nil
    selectedVillageEntityIDs.removeAll()
    selectedSpawnerID = nil
    session.clearRememberedSelections()
    blockDetailPanel.clearBlock()
    objectOverlayView.setSelectedObjectID(nil)
    renderQueue.async { [weak self] in
      self?.chunkRenderer?.clearCache()
      self?.chunkCache.removeAll()
    }
    loadSpawn()

    guard lastRenderedImage != nil else {
      jumpToDefaultCenter()
      return
    }
    render(
      centerX: center.0,
      centerZ: center.1,
      anchor: anchor,
      reason: "世界数据已更新",
      showOverlay: false
    )
  }

  private func resetAfterExternalWorldChange() {
    activeRenderToken?.cancel()
    panDebounceWorkItem?.cancel()
    lastRenderedImage = nil
    lastBlockNames = []
    lastBlockHeights = []
    lastSpawnHits = []
    lastPlayerHits = []
    lastWorldObjectHits = []
    lastHardcodedSpawnerHits = []
    lastVillageHits = []
    selectedWorldObjectID = nil
    selectedVillageID = nil
    selectedVillageEntityIDs.removeAll()
    selectedSpawnerID = nil
    selectedBlock = nil
    selectedChunk = nil
    selectedRegion = nil
    dimensionViewportStates.removeAll()
    activeDimension = BedrockDimension.overworld.rawValue
    modeControl.selectedSegmentIndex = 0
    currentMode = .surface
    session.clearRememberedSelections()
    blockDetailPanel.clearBlock()
    setSelectionMode(false)
    objectOverlayView.clear()
    shareButton.isEnabled = false
    renderQueue.async { [weak self] in
      self?.chunkRenderer = nil
      self?.chunkCache.removeAll()
    }
    loadSpawn()
    jumpToDefaultCenter()
  }

  private func configureUI() {
    let compactPhone = UIDevice.current.userInterfaceIdiom == .phone

    xField.text = "0"
    yField.text = "0"
    zField.text = "0"
    for field in [xField, yField, zField] {
      field.borderStyle = .roundedRect
      field.keyboardType = .numbersAndPunctuation
      field.delegate = self
      field.font = UIFont.systemFont(ofSize: compactPhone ? 12 : 13, weight: .regular)
      field.widthAnchor.constraint(equalToConstant: compactPhone ? 38 : 50).isActive = true
      field.adjustsFontSizeToFitWidth = true
      field.minimumFontSize = compactPhone ? 9 : 10
    }

    sliceAxisControl.selectedSegmentIndex = MapSliceAxis.y.rawValue
    coordinateModeControl.selectedSegmentIndex = 0
    dimensionControl.selectedSegmentIndex = 0
    modeControl.selectedSegmentIndex = 0
    yField.isEnabled = false
    if compactPhone {
      // Six render modes must fit on one portrait-width iPhone row. Keep the
      // meanings intact while using shorter titles for the two longest modes.
      modeControl.setTitle("常加载", forSegmentAt: MapRenderMode.tickingAreas.rawValue)
      modeControl.setTitle("史莱姆", forSegmentAt: MapRenderMode.slime.rawValue)
      sliceAxisControl.setTitleTextAttributes(
        [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .normal)
      coordinateModeControl.setTitleTextAttributes(
        [.font: UIFont.systemFont(ofSize: 12, weight: .medium)], for: .normal)
      dimensionControl.setTitleTextAttributes(
        [.font: UIFont.systemFont(ofSize: 12, weight: .medium)], for: .normal)
      modeControl.setTitleTextAttributes(
        [.font: UIFont.systemFont(ofSize: 10.5, weight: .medium)], for: .normal)
    }
    autoRenderSwitch.isOn = true
    gridSwitch.isOn = true
    chunkSelectionSwitch.isOn = false

    sliceAxisControl.addTarget(self, action: #selector(sliceAxisChanged), for: .valueChanged)
    modeControl.addTarget(self, action: #selector(regionOptionChanged), for: .valueChanged)
    gridSwitch.addTarget(self, action: #selector(regionOptionChanged), for: .valueChanged)
    coordinateModeControl.addTarget(
      self, action: #selector(coordinateModeChanged), for: .valueChanged)
    dimensionControl.addTarget(self, action: #selector(dimensionChanged), for: .valueChanged)
    autoRenderSwitch.addTarget(self, action: #selector(autoRenderChanged), for: .valueChanged)
    chunkSelectionSwitch.addTarget(
      self, action: #selector(chunkSelectionChanged), for: .valueChanged)

    let renderButton = UIButton(type: .system)
    renderButton.setTitle("渲染", for: .normal)
    renderButton.setTitleColor(.white, for: .normal)
    renderButton.backgroundColor = .systemBlue
    renderButton.layer.cornerRadius = 7
    renderButton.layer.masksToBounds = true
    renderButton.titleLabel?.font = UIFont.systemFont(ofSize: compactPhone ? 12 : 13, weight: .regular)
    renderButton.mcbe_enableCompactTitle(minimumScaleFactor: 0.68)
    renderButton.contentEdgeInsets = UIEdgeInsets(
      top: compactPhone ? 3 : 5,
      left: compactPhone ? 5 : 10,
      bottom: compactPhone ? 3 : 5,
      right: compactPhone ? 5 : 10)
    renderButton.setContentHuggingPriority(.required, for: .horizontal)
    renderButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    renderButton.heightAnchor.constraint(equalToConstant: compactPhone ? 28 : 32).isActive = true
    renderButton.addTarget(self, action: #selector(renderFromFields), for: .touchUpInside)

    let centerCoordinateTitle = label("渲染中心坐标")
    // Keep the same descriptive title as iPad.  The phone header now centers
    // a compact intrinsic-width row instead of spreading abbreviated labels
    // across the whole screen, so the full wording fits without ellipsis.
    centerCoordinateTitle.font = UIFont.systemFont(ofSize: compactPhone ? 10.5 : 13, weight: .regular)
    centerCoordinateTitle.numberOfLines = 1
    centerCoordinateTitle.adjustsFontSizeToFitWidth = true
    centerCoordinateTitle.minimumScaleFactor = compactPhone ? 0.62 : 0.70
    centerCoordinateTitle.setContentCompressionResistancePriority(.required, for: .horizontal)

    let coordinateFields = UIStackView(arrangedSubviews: [
      label("X"), xField,
      label("Y"), yField,
      label("Z"), zField,
    ])
    coordinateFields.axis = .horizontal
    coordinateFields.spacing = compactPhone ? 2 : 4
    coordinateFields.alignment = .center
    coordinateFields.setContentHuggingPriority(.required, for: .horizontal)
    coordinateFields.setContentCompressionResistancePriority(.required, for: .horizontal)

    let displayOptions = UIStackView(arrangedSubviews: [
      compactSwitch(title: "自动渲染", control: autoRenderSwitch),
      compactSwitch(title: "区块网格", control: gridSwitch),
      compactSwitch(title: "选择区块", control: chunkSelectionSwitch),
    ])
    displayOptions.axis = .horizontal
    displayOptions.spacing = compactPhone ? 8 : 16
    displayOptions.alignment = .center
    // On portrait iPhone the row now stretches to match the render-controls
    // row width, using equalSpacing so the three switch groups breathe a bit
    // more while both top rows keep the same visual length.
    displayOptions.distribution = .equalSpacing
    displayOptions.setContentHuggingPriority(.required, for: .horizontal)
    displayOptions.setContentCompressionResistancePriority(.required, for: .horizontal)

    let renderControls = UIStackView(arrangedSubviews: [
      centerCoordinateTitle,
      coordinateFields,
      renderButton,
    ])
    renderControls.axis = .horizontal
    renderControls.spacing = compactPhone ? 5 : 9
    renderControls.alignment = .center
    // Match the phone switch row width and distribute the title / XZ editor
    // / button with equalSpacing, so the second row remains readable and has
    // the same visual length as the first row.
    renderControls.distribution = .equalSpacing
    renderControls.setContentHuggingPriority(.required, for: .horizontal)
    renderControls.setContentCompressionResistancePriority(.required, for: .horizontal)

    let flexibleSpacer = UIView()
    flexibleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    flexibleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let coordinates: UIStackView
    if compactPhone {
      // The old single row let the three switch titles collapse to zero width
      // on portrait iPhones. Two shallow rows use essentially the same vertical
      // budget while keeping every label and the X/Z editor visible.
      coordinates = UIStackView(arrangedSubviews: [displayOptions, renderControls])
      coordinates.axis = .vertical
      coordinates.spacing = 10
      // Keep the two phone rows visually aligned and equally long.  The row
      // stacks share a width, then use equalSpacing internally so controls are
      // slightly more spread out without reverting to overly sparse layout.
      displayOptions.widthAnchor.constraint(equalTo: renderControls.widthAnchor).isActive = true
      coordinates.alignment = .center
      coordinates.distribution = .fillEqually
      coordinates.heightAnchor.constraint(equalToConstant: 64).isActive = true
    } else {
      coordinates = UIStackView(arrangedSubviews: [displayOptions, flexibleSpacer, renderControls])
      coordinates.axis = .horizontal
      coordinates.spacing = 12
      coordinates.alignment = .center
      coordinates.distribution = .fill
      coordinates.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    coordinates.isLayoutMarginsRelativeArrangement = true
    coordinates.layoutMargins = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

    let segmentHeight: CGFloat = compactPhone ? 32 : 36
    sliceAxisControl.heightAnchor.constraint(equalToConstant: segmentHeight).isActive = true
    coordinateModeControl.heightAnchor.constraint(equalToConstant: segmentHeight).isActive = true
    dimensionControl.heightAnchor.constraint(equalToConstant: segmentHeight).isActive = true
    modeControl.heightAnchor.constraint(equalToConstant: segmentHeight).isActive = true

    let controls = UIStackView(arrangedSubviews: [
      coordinates, sliceAxisControl, coordinateModeControl, dimensionControl, modeControl,
    ])
    controls.axis = .vertical
    controls.spacing = compactPhone ? 4 : 6
    controls.translatesAutoresizingMaskIntoConstraints = false
    controls.setContentHuggingPriority(.required, for: .vertical)
    controls.setContentCompressionResistancePriority(.required, for: .vertical)
    let coordinatesHeight: CGFloat = compactPhone ? 64 : 44
    let controlsSpacing: CGFloat = compactPhone ? 4 : 6
    controls.heightAnchor.constraint(equalToConstant:
      coordinatesHeight + segmentHeight * 4 + controlsSpacing * 4
    ).isActive = true

    // Keep the map viewport height stable. On compact-width iPhones the old
    // unlimited status label changed from one line ("正在读取…") to many
    // lines after every render. That changed scrollView.bounds.height after
    // applyViewport(), which shifted only the vertical/Z center and could
    // create a self-sustaining Z-decrease/render loop.
    statusLabel.font = traitCollection.horizontalSizeClass == .compact
      ? .systemFont(ofSize: 10.5)
      : .preferredFont(forTextStyle: .footnote)
    statusLabel.textColor = .secondaryLabel
    statusLabel.numberOfLines = 2
    statusLabel.lineBreakMode = .byWordWrapping
    statusLabel.isUserInteractionEnabled = true
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(showRenderDiagnostics)))
    statusLabel.setContentHuggingPriority(.required, for: .vertical)
    statusLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

    scrollView.delegate = self
    // The map supplies its own virtual pan margins. Disable UIKit's automatic
    // safe-area content-inset adjustment so the image/content coordinate
    // transform cannot gain a device-dependent vertical offset on iPhone.
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.minimumZoomScale = initialMinimumZoomScale
    scrollView.maximumZoomScale = initialMaximumZoomScale
    // Virtual content insets already provide room to pan beyond the current
    // rendered image. Elastic bounce is therefore unnecessary and, on iPhone,
    // can feed residual velocity into a freshly resized render canvas.
    scrollView.bounces = false
    scrollView.bouncesZoom = false
    scrollView.alwaysBounceHorizontal = false
    scrollView.alwaysBounceVertical = false
    scrollView.pinchGestureRecognizer?.isEnabled = true
    scrollView.decelerationRate = .fast
    scrollView.backgroundColor = .secondarySystemBackground
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    imageView.contentMode = .scaleToFill
    imageView.layer.magnificationFilter = .nearest
    imageView.layer.minificationFilter = .nearest
    imageView.layer.allowsEdgeAntialiasing = false
    imageView.layer.shouldRasterize = false
    imageView.layer.contentsScale = UIScreen.main.scale
    imageView.clipsToBounds = true
    imageView.isUserInteractionEnabled = true
    imageView.translatesAutoresizingMaskIntoConstraints = false
    let mapTap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
    let mapLongPress = UILongPressGestureRecognizer(
      target: self, action: #selector(handleChunkLongPress(_:)))
    mapLongPress.minimumPressDuration = 0.55
    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(mapDoubleTapped(_:)))
    doubleTap.numberOfTapsRequired = 2
    let twoFingerTap = UITapGestureRecognizer(
      target: self, action: #selector(mapTwoFingerTapped(_:)))
    twoFingerTap.numberOfTouchesRequired = 2
    mapTap.require(toFail: doubleTap)
    imageView.addGestureRecognizer(mapTap)
    imageView.addGestureRecognizer(mapLongPress)
    imageView.addGestureRecognizer(doubleTap)
    imageView.addGestureRecognizer(twoFingerTap)
    scrollView.addSubview(imageView)
    selectionOverlayView.addGestureRecognizer(selectionPanGesture)
    selectionOverlayView.addGestureRecognizer(selectionMapPanGesture)
    selectionOverlayView.addGestureRecognizer(selectionMapPinchGesture)

    zoomLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    zoomLabel.textColor = .white
    zoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.62)
    zoomLabel.textAlignment = .center
    zoomLabel.layer.cornerRadius = 8
    zoomLabel.layer.masksToBounds = true
    zoomLabel.alpha = 0
    zoomLabel.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(controls)
    view.addSubview(statusLabel)
    view.addSubview(scrollView)
    blockDetailPanel.translatesAutoresizingMaskIntoConstraints = false
    blockDetailPanel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    view.addSubview(blockDetailPanel)
    objectOverlayView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(objectOverlayView)
    selectionOverlayView.translatesAutoresizingMaskIntoConstraints = false
    selectionOverlayView.isHidden = true
    selectionOverlayView.onEdgePan = { [weak self] edge, translation, state in
      self?.adjustSelectionEdge(edge, translation: translation, state: state)
    }
    selectionOverlayView.onCoordinatesChanged = { [weak self] x0, z0, x1, z1 in
      self?.setSelectionCoordinates(x0: x0, z0: z0, x1: x1, z1: z1)
    }
    selectionOverlayView.onAlignToChunkBounds = { [weak self] in
      self?.alignSelectionToChunkBounds()
    }
    selectionOverlayView.onShowActions = { [weak self] in self?.presentSelectionActions() }
    view.addSubview(selectionOverlayView)
    view.addSubview(zoomLabel)
    imageWidthConstraint = imageView.widthAnchor.constraint(
      equalToConstant: 80 * basePointsPerBlock)
    imageHeightConstraint = imageView.heightAnchor.constraint(
      equalToConstant: 80 * basePointsPerBlock)
    detailPanelWidthConstraint = blockDetailPanel.widthAnchor.constraint(equalToConstant: 240)
    NSLayoutConstraint.activate([
      controls.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      controls.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
      statusLabel.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
      statusLabel.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
      statusLabel.heightAnchor.constraint(
        equalToConstant: traitCollection.horizontalSizeClass == .compact ? 32 : 38),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: blockDetailPanel.leadingAnchor),
      scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      blockDetailPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      blockDetailPanel.topAnchor.constraint(equalTo: scrollView.topAnchor),
      blockDetailPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      detailPanelWidthConstraint,
      imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      imageWidthConstraint,
      imageHeightConstraint,
      objectOverlayView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      objectOverlayView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      objectOverlayView.topAnchor.constraint(equalTo: scrollView.topAnchor),
      objectOverlayView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      selectionOverlayView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      selectionOverlayView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      selectionOverlayView.topAnchor.constraint(equalTo: scrollView.topAnchor),
      selectionOverlayView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      zoomLabel.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      zoomLabel.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
      zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 74),
      zoomLabel.heightAnchor.constraint(equalToConstant: 32),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let preferredPanelWidth =
      traitCollection.horizontalSizeClass == .regular
      ? min(300, max(240, view.bounds.width * 0.28))
      : min(250, max(200, view.bounds.width * 0.50))
    if !blockDetailPanel.isCollapsed,
      abs(detailPanelWidthConstraint.constant - preferredPanelWidth) > 0.5
    {
      detailPanelWidthConstraint.constant = preferredPanelWidth
    }
    updatePanInsets()
    updateZoomLimits()
    updateObjectOverlay()
    if let region = selectedRegion { updateSelectionOverlay(for: region) }
  }

  private func setBlockDetailPanelCollapsed(_ collapsed: Bool, animated: Bool) {
    guard detailPanelWidthConstraint != nil else { return }
    let expandedWidth =
      traitCollection.horizontalSizeClass == .regular
      ? min(300, max(240, view.bounds.width * 0.28))
      : min(250, max(200, view.bounds.width * 0.50))
    let targetWidth: CGFloat = collapsed ? 48 : expandedWidth
    detailPanelWidthConstraint.constant = targetWidth
    let changes = {
      self.view.layoutIfNeeded()
      self.updateObjectOverlay()
      if let region = self.selectedRegion { self.updateSelectionOverlay(for: region) }
    }
    if animated {
      UIView.animate(withDuration: 0.22, animations: changes)
    } else {
      changes()
    }
  }

  private func label(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
    label.mcbe_enableCompactSingleLineText(minimumScaleFactor: 0.70)
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    return label
  }

  private func compactSwitch(title: String, control: UISwitch) -> UIStackView {
    let compactPhone = UIDevice.current.userInterfaceIdiom == .phone
    let titleLabel = UILabel()
    // Use the same complete wording on iPhone and iPad.  The enclosing phone
    // row is intrinsic-width and centered, so abbreviations are no longer
    // necessary to prevent clipping.
    titleLabel.text = title
    titleLabel.font = UIFont.systemFont(ofSize: compactPhone ? 10.5 : 13, weight: .regular)
    titleLabel.textAlignment = .left
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = compactPhone ? 0.78 : 0.82
    titleLabel.setContentHuggingPriority(compactPhone ? .required : .defaultLow, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    if control === gridSwitch { gridOptionTitleLabel = titleLabel }

    let switchHolder = UIView()
    switchHolder.widthAnchor.constraint(equalToConstant: compactPhone ? 32 : 39).isActive = true
    switchHolder.heightAnchor.constraint(equalToConstant: compactPhone ? 19 : 22).isActive = true
    control.translatesAutoresizingMaskIntoConstraints = false
    control.transform = CGAffineTransform(scaleX: compactPhone ? 0.54 : 0.62, y: compactPhone ? 0.54 : 0.62)
    switchHolder.addSubview(control)
    NSLayoutConstraint.activate([
      control.centerXAnchor.constraint(equalTo: switchHolder.centerXAnchor),
      control.centerYAnchor.constraint(equalTo: switchHolder.centerYAnchor),
    ])

    let stack = UIStackView(arrangedSubviews: [titleLabel, switchHolder])
    stack.axis = .horizontal
    stack.spacing = compactPhone ? 2 : 3
    stack.alignment = .center
    stack.distribution = .fill
    stack.heightAnchor.constraint(equalToConstant: compactPhone ? 22 : 24).isActive = true
    if compactPhone {
      // Do not let UIStackView stretch an individual compact pair. The outer
      // row is responsible for spacing the three complete controls.
      stack.setContentHuggingPriority(.required, for: .horizontal)
      stack.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    return stack
  }

  private func loadSpawn() {
    spawnX = nil
    spawnY = nil
    spawnZ = nil
    spawnCoordinates.removeAll(keepingCapacity: true)
    do {
      let root = try session.document.readLevelDat().document.root
      if let x = root.intValue(named: "SpawnX"), let z = root.intValue(named: "SpawnZ") {
        spawnX = Int64(x)
        spawnZ = Int64(z)
        spawnY = root.intValue(named: "SpawnY")
        spawnCoordinates.append(
          MapSpawnCoordinate(
            stableID: "world:0:\(x):\(spawnY ?? 0):\(z)",
            kind: .world,
            name: "世界出生点",
            source: "level.dat",
            x: Int64(x),
            y: spawnY.map(Int64.init),
            z: Int64(z),
            dimension: BedrockDimension.overworld.rawValue,
            forced: nil
          ))
      }
    } catch {
      // A damaged or unusual level.dat should not prevent manual map use.
    }

    do {
      let playerSpawns = try PlayerNBTStore(session: session).spawnPoints()
      for point in playerSpawns {
        spawnCoordinates.append(
          MapSpawnCoordinate(
            stableID:
              "player:\(point.keyText):\(point.dimension):\(point.x):\(point.y ?? 0):\(point.z)",
            kind: .player,
            name: point.playerName,
            source: point.keyText,
            x: point.x,
            y: point.y,
            z: point.z,
            dimension: point.dimension,
            forced: point.forced
          ))
      }
    } catch {
      // Player data may be absent or partly damaged; the world spawn remains usable.
    }
  }

  private func defaultViewportTarget(
    for dimension: Int32,
    zoomScale: CGFloat
  ) -> (
    centerX: Int32, centerZ: Int32, inputX: Int64, inputZ: Int64, anchor: MapViewportAnchor,
    reason: String
  ) {
    if let local = try? PlayerNBTStore(session: session).localPlayerPosition(),
      local.dimension == dimension
    {
      let inputX = Int64(floor(local.x))
      let inputZ = Int64(floor(local.z))
      return (
        centerX: MapCoordinate.chunk(fromBlock: inputX),
        centerZ: MapCoordinate.chunk(fromBlock: inputZ),
        inputX: inputX,
        inputZ: inputZ,
        anchor: MapViewportAnchor(
          blockX: local.x,
          blockZ: local.z,
          zoomScale: max(zoomScale, CGFloat(0.0001))
        ),
        reason: "本地玩家位置"
      )
    }

    return (
      centerX: 0,
      centerZ: 0,
      inputX: 0,
      inputZ: 0,
      anchor: MapViewportAnchor(
        blockX: 0.5,
        blockZ: 0.5,
        zoomScale: max(zoomScale, CGFloat(0.0001))
      ),
      reason: "维度原点"
    )
  }

  private func renderDefaultCenter(
    for dimension: Int32,
    zoomScale: CGFloat,
    reason: String? = nil,
    showOverlay: Bool
  ) {
    coordinateModeControl.selectedSegmentIndex = 1
    let target = defaultViewportTarget(for: dimension, zoomScale: zoomScale)
    xField.text = String(target.inputX)
    zField.text = String(target.inputZ)
    render(
      centerX: target.centerX,
      centerZ: target.centerZ,
      anchor: target.anchor,
      reason: reason ?? target.reason,
      showOverlay: showOverlay
    )
  }

  private func jumpToDefaultCenter() {
    if let local = try? PlayerNBTStore(session: session).localPlayerPosition(),
      let dimensionIndex = BedrockDimension.allCases.firstIndex(where: {
        $0.rawValue == local.dimension
      })
    {
      dimensionControl.selectedSegmentIndex = dimensionIndex
      activeDimension = local.dimension
      renderDefaultCenter(
        for: local.dimension,
        zoomScale: max(effectiveZoomScale, CGFloat(0.0001)),
        showOverlay: true
      )
      return
    }

    dimensionControl.selectedSegmentIndex = 0
    activeDimension = BedrockDimension.overworld.rawValue
    renderDefaultCenter(
      for: BedrockDimension.overworld.rawValue,
      zoomScale: max(effectiveZoomScale, CGFloat(0.0001)),
      showOverlay: true
    )
  }

  @objc private func sliceAxisChanged() {
    setSelectionMode(false)
    selectedChunk = nil
    chunkSelectionSwitch.setOn(false, animated: false)
    let verticalSlice = currentSliceAxis != .y
    yField.isEnabled = verticalSlice
    chunkSelectionSwitch.isEnabled = !verticalSlice
    selectionButtonView.isEnabled = !verticalSlice
    selectionButtonView.alpha = verticalSlice ? 0.35 : 1.0
    gridOptionTitleLabel?.text = verticalSlice ? "子区块网格" : "区块网格"

    if verticalSlice {
      let originX = MapCoordinate.blockOrigin(ofChunk: lastCenterX) + 8
      let originZ = MapCoordinate.blockOrigin(ofChunk: lastCenterZ) + 8
      if coordinateModeControl.selectedSegmentIndex == 1 {
        sliceCenterBlockX = Int64(xField.text ?? "") ?? originX
        sliceCenterBlockZ = Int64(zField.text ?? "") ?? originZ
      } else {
        sliceCenterBlockX = originX
        sliceCenterBlockZ = originZ
      }
      // X/Z are new vertical-reading modes. Enter them at the conventional
      // Bedrock Y=63 center regardless of the last Y-mode display value.
      sliceCenterY = 63
      yField.text = "63"
    } else {
      // The Y-axis top-down map has no vertical slice center; expose a stable
      // default Y=0 rather than leaking the last X/Z slice Y into the field.
      sliceCenterY = 0
      yField.text = "0"
    }
    updateCoordinateFields(centerX: lastCenterX, centerZ: lastCenterZ, anchor: nil)
    statusLabel.text = verticalSlice
      ? "已切换到 \(currentSliceAxis.displayName) 轴剖面：Y 正方向在上，负方向在下；网格为 16×16 子区块网格。"
      : "已切换到 Y 轴俯视地图。"
    render(
      centerX: lastCenterX, centerZ: lastCenterZ, anchor: nil,
      reason: "切换渲染轴", showOverlay: true)
  }

  @objc private func regionOptionChanged() {
    if currentSliceAxis != .y {
      render(
        centerX: lastCenterX, centerZ: lastCenterZ, anchor: nil,
        reason: "剖面设置", showOverlay: false)
      return
    }
    let anchor = currentViewportAnchor()
    let center = anchor.map { chunkCenter(for: $0) } ?? (lastCenterX, lastCenterZ)
    render(centerX: center.0, centerZ: center.1, anchor: anchor, reason: "图层设置", showOverlay: false)
  }

  @objc private func coordinateModeChanged() {
    updateCoordinateFields(
      centerX: lastCenterX, centerZ: lastCenterZ,
      anchor: currentSliceAxis == .y ? currentViewportAnchor() : nil)
    if currentSliceAxis != .y {
      statusLabel.text = coordinateModeControl.selectedSegmentIndex == 0
        ? "X/Z 剖面中心使用区块坐标；Y 始终使用方块坐标。"
        : "X/Z 剖面中心使用方块坐标；Y 正方向显示在上方。"
    } else {
      statusLabel.text =
        coordinateModeControl.selectedSegmentIndex == 0
        ? "输入区块坐标；地图会按当前缩放和可见范围动态加载区块。"
        : "输入方块坐标；地图会动态加载可见区块，负坐标按数学向下取整。"
    }
  }

  @objc private func dimensionChanged() {
    rememberCurrentViewportState(for: activeDimension)
    setSelectionMode(false)
    selectedBlock = nil
    blockDetailPanel.clearBlock()
    let newDimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    if selectedChunk?.dimension != newDimension { selectedChunk = nil }
    activeDimension = newDimension

    if currentSliceAxis != .y {
      // Every dimension switch starts a vertical slice from Y=63 and a
      // deterministic ±128-block working window. The axis picker uses the
      // same ±128 range; later pan/zoom may expand the rendered viewport.
      sliceCenterY = 63
      yField.text = "63"
      let centerX = MapCoordinate.chunk(fromBlock: sliceCenterBlockX)
      let centerZ = MapCoordinate.chunk(fromBlock: sliceCenterBlockZ)
      render(
        centerX: centerX, centerZ: centerZ, anchor: nil,
        reason: "切换维度", showOverlay: true,
        sideChunksOverride: max(1, crossSectionDefaultSideBlocks / 16)
      )
      return
    }

    if let state = dimensionViewportStates[newDimension] {
      render(
        centerX: state.centerX,
        centerZ: state.centerZ,
        anchor: state.anchor,
        reason: "切换维度",
        showOverlay: true
      )
    } else {
      coordinateModeControl.selectedSegmentIndex = 1
      xField.text = "0"
      zField.text = "0"
      render(
        centerX: 0,
        centerZ: 0,
        anchor: MapViewportAnchor(
          blockX: 0.5,
          blockZ: 0.5,
          zoomScale: max(effectiveZoomScale, CGFloat(0.0001))
        ),
        reason: "首次进入维度原点",
        showOverlay: true
      )
    }
  }

  @objc private func autoRenderChanged() {
    panDebounceWorkItem?.cancel()
    if currentSliceAxis != .y {
      statusLabel.text = autoRenderSwitch.isOn
        ? "剖面自动渲染已开启：拖动会沿剖面横轴和 Y 轴续载，缩放会自动扩大或细化范围。"
        : "剖面自动渲染已关闭；可拖动查看当前剖面，使用坐标和“渲染”按钮跳转。"
    } else {
      statusLabel.text = autoRenderSwitch.isOn
        ? "移动自动渲染已开启：拖动会续载；缩小时会按视口自动扩大区块范围。"
        : "移动自动渲染已关闭；可拖动查看当前区域，使用坐标和“渲染”按钮跳转。"
    }
    saveMapState()
  }

  @objc private func chunkSelectionChanged() {
    if currentSliceAxis != .y {
      chunkSelectionSwitch.setOn(false, animated: true)
      statusLabel.text = "X/Z 剖面模式不支持选择区块；网格已切换为子区块网格。"
      return
    }
    if chunkSelectionSwitch.isOn {
      setSelectionMode(false)
      clearSelectedWorldObject()
      selectedBlock = nil
      blockDetailPanel.clearBlock()
      statusLabel.text = "区块选择已开启：点击地图会选中区块并以橙色边框闪烁。"
    } else {
      statusLabel.text = "区块选择已关闭：点击地图恢复方块列和实体选择。"
    }
    updateObjectOverlay()
    saveMapState()
  }

  @objc private func cancelAllSelections() {
    setSelectionMode(false)
    chunkSelectionSwitch.setOn(false, animated: true)
    selectedWorldObjectID = nil
    selectedVillageID = nil
    selectedVillageEntityIDs.removeAll()
    selectedSpawnerID = nil
    selectedBlock = nil
    selectedChunk = nil
    selectedRegion = nil
    objectOverlayView.setSelectedObjectID(nil)
    session.clearRememberedSelections()
    blockDetailPanel.clearBlock()
    updateObjectOverlay()
    saveMapState()
    statusLabel.text = "已取消当前全部选择。"
  }

  @objc private func renderFromFields() {
    view.endEditing(true)
    guard let inputX = Int64(xField.text ?? ""), let inputZ = Int64(zField.text ?? "") else {
      showError(MCBEEditorError.malformedData("坐标必须是整数"), title: "坐标错误")
      return
    }
    if currentSliceAxis != .y {
      guard let inputY = Int32(yField.text ?? "") else {
        showError(MCBEEditorError.malformedData("Y 坐标必须是整数"), title: "坐标错误")
        return
      }
      sliceCenterY = inputY
    }

    let centerX: Int32
    let centerZ: Int32
    let anchor: MapViewportAnchor?
    if coordinateModeControl.selectedSegmentIndex == 0 {
      centerX = Int32(clamping: inputX)
      centerZ = Int32(clamping: inputZ)
      sliceCenterBlockX = MapCoordinate.blockOrigin(ofChunk: centerX) + 8
      sliceCenterBlockZ = MapCoordinate.blockOrigin(ofChunk: centerZ) + 8
      anchor = nil
    } else {
      centerX = MapCoordinate.chunk(fromBlock: inputX)
      centerZ = MapCoordinate.chunk(fromBlock: inputZ)
      sliceCenterBlockX = inputX
      sliceCenterBlockZ = inputZ
      anchor = currentSliceAxis == .y
        ? MapViewportAnchor(
          blockX: Double(inputX) + 0.5,
          blockZ: Double(inputZ) + 0.5,
          zoomScale: max(effectiveZoomScale, 1)
        )
        : nil
    }
    render(centerX: centerX, centerZ: centerZ, anchor: anchor, reason: "坐标跳转", showOverlay: true)
  }

  private func render(
    centerX: Int32,
    centerZ: Int32,
    anchor: MapViewportAnchor?,
    reason: String,
    showOverlay: Bool,
    sideChunksOverride: Int? = nil
  ) {
    panDebounceWorkItem?.cancel()
    activeRenderToken?.cancel()

    let requestedZoom = max(anchor?.zoomScale ?? effectiveZoomScale, 0.0001)
    let sideChunks = max(
      minimumDynamicSideChunks,
      sideChunksOverride ?? dynamicRenderSideChunks(forZoomScale: requestedZoom)
    )
    let leftChunks = (sideChunks - 1) / 2
    let rightChunks = sideChunks - leftChunks - 1
    let scanRadius = max(leftChunks, rightChunks)
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    if dimension != activeDimension {
      rememberCurrentViewportState(for: activeDimension)
      activeDimension = dimension
    }
    let mode = MapRenderMode.allCases[modeControl.selectedSegmentIndex]
    let generation = renderGeneration + 1
    renderGeneration = generation
    let token = MapRenderToken()
    activeRenderToken = token
    isRendering = true
    shareButton.isEnabled = false
    statusLabel.text = "\(reason)：正在读取 \(sideChunks)×\(sideChunks) 区块…"
    let overlay = showOverlay ? showBusy("解析 \(sideChunks)×\(sideChunks) 区块与调色板…") : nil
    let spawns = showSpawnPoints ? spawnCoordinates.filter { $0.dimension == dimension } : []
    let drawGrid = gridSwitch.isOn
    let includePlayers = showPlayers
    let includeEntities = showEntities
    let includeBlockEntities = showBlockEntities
    let includeHardcodedSpawners = showHardcodedSpawners
    let includeVillages = showVillages

    if currentSliceAxis != .y {
      renderCrossSectionMap(
        centerX: centerX,
        centerZ: centerZ,
        dimension: dimension,
        sideChunks: sideChunks,
        mode: mode,
        drawGrid: drawGrid,
        requestedZoom: requestedZoom,
        generation: generation,
        token: token,
        overlay: overlay,
        reason: reason
      )
      return
    }

    renderQueue.async { [weak self] in
      guard let self = self else { return }
      if token.isCancelled {
        DispatchQueue.main.async { overlay?.removeFromSuperview() }
        return
      }
      do {
        let renderer = try self.rendererForCurrentSession()
        var tickingAreas = [BedrockTickingArea]()
        var tickingDiagnostics = [String]()
        if mode == .tickingAreas {
          do {
            tickingAreas = try TickingAreaStore(session: self.session).records()
              .map(\.area)
              .filter { $0.dimension == dimension }
          } catch {
            tickingDiagnostics.append("常加载区块：\(error.localizedDescription)")
          }
        }
        let villageScan =
          includeVillages
          ? try VillageNBTStore(session: self.session).mapFeatures()
          : VillageMapScanResult(features: [], diagnostics: [])

        let database = try self.session.database()
        var playerCoordinates = [MapPlayerCoordinate]()
        if includePlayers {
          let playerStore = PlayerNBTStore(session: self.session)
          for record in try playerStore.records() {
            guard let position = playerStore.currentPosition(for: record),
              position.dimension == dimension
            else { continue }
            playerCoordinates.append(
              MapPlayerCoordinate(
                record: record,
                position: position,
                isLocal: playerStore.isLocalPlayer(record),
                uniqueID: playerStore.uniqueID(for: record)
              ))
          }
        }
        let scanner = BedrockWorldObjectScanner(database: database)
        var scannedObjects = [BedrockWorldObject]()
        var objectDiagnostics = [String]()

        if includeEntities || includeBlockEntities {
          let objectScan = try scanner.scanRegionAdaptive(
            centerX: centerX,
            centerZ: centerZ,
            dimension: dimension,
            radius: scanRadius,
            includeEntities: includeEntities,
            includeBlockEntities: includeBlockEntities,
            maximumObjects: 20_000,
            shouldCancel: { token.isCancelled }
          )
          scannedObjects.append(contentsOf: objectScan.objects)
          objectDiagnostics.append(contentsOf: objectScan.diagnostics)
        }

        // Village residents are resolved from every Dwellers UniqueID by
        // VillageNBTStore, independent of the visible map window. Keep them
        // in the overlay model so selecting a center can flash villagers and
        // iron golems even when the ordinary entity layer is disabled.
        if includeVillages {
          scannedObjects.append(contentsOf: villageScan.features.flatMap(\.residentEntities))
        }

        let spawnerScan =
          includeHardcodedSpawners
          ? try self.scanHardcodedSpawners(
            database: database,
            centerX: centerX,
            centerZ: centerZ,
            dimension: dimension,
            sideChunks: sideChunks,
            leftChunks: leftChunks,
            shouldCancel: { token.isCancelled }
          )
          : (hits: [MapHardcodedSpawnerHit](), diagnostics: [String]())
        if token.isCancelled { throw MapRenderCancelled() }
        var uniqueObjects = [String: BedrockWorldObject]()
        for object in scannedObjects {
          if let current = uniqueObjects[object.stableID], current.source == .modernActor {
            continue
          }
          uniqueObjects[object.stableID] = object
        }
        let generatedChunkPositions = Set(try BedrockChunkStore(session: self.session).listChunks().filter { summary in
          summary.position.dimension == dimension
            && (summary.hasTerrain || summary.biomeRecordType != nil
                || summary.hasBlockEntities || summary.hasLegacyEntities
                || summary.recordCount > (summary.hasActorDigest ? 1 : 0))
        }.map(\.position))
        let result = try self.renderRegion(
          renderer: renderer,
          centerX: centerX,
          centerZ: centerZ,
          dimension: dimension,
          sideChunks: sideChunks,
          leftChunks: leftChunks,
          mode: mode,
          drawGrid: drawGrid,
          generatedChunkPositions: generatedChunkPositions,
          ungeneratedDisplay: self.showUngeneratedChunks ? .texture : .air,
          spawnCoordinates: spawns,
          playerCoordinates: playerCoordinates,
          worldObjects: Array(uniqueObjects.values),
          displayEntities: includeEntities,
          displayBlockEntities: includeBlockEntities,
          hardcodedSpawnerHits: spawnerScan.hits,
          villageFeatures: villageScan.features,
          tickingAreas: tickingAreas,
          additionalErrors: objectDiagnostics + spawnerScan.diagnostics + villageScan.diagnostics
            + tickingDiagnostics,
          shouldCancel: { token.isCancelled }
        )
        guard !token.isCancelled else { throw MapRenderCancelled() }
        DispatchQueue.main.async {
          overlay?.removeFromSuperview()
          guard generation == self.renderGeneration, self.activeRenderToken === token else {
            return
          }
          self.isRendering = false
          self.updateMapCanvasSize(sideBlocks: sideChunks * 16)
          self.imageView.image = result.image
          self.lastRenderedImage = result.image
          self.lastBlockNames = result.names
          self.lastBlockHeights = result.heights
          self.lastErrors = result.errors
          self.lastSpawnHits = result.spawnHits
          self.lastPlayerHits = result.playerHits
          self.lastWorldObjectHits = result.worldObjectHits
          self.lastHardcodedSpawnerHits = result.hardcodedSpawnerHits
          self.lastVillageHits = result.villageHits
          self.lastCenterX = centerX
          self.lastCenterZ = centerZ
          self.renderedSideChunks = sideChunks
          self.currentMode = mode
          let rememberedAnchor =
            anchor
            ?? MapViewportAnchor(
              blockX: Double(MapCoordinate.blockOrigin(ofChunk: centerX)) + 8,
              blockZ: Double(MapCoordinate.blockOrigin(ofChunk: centerZ)) + 8,
              zoomScale: requestedZoom
            )
          self.dimensionViewportStates[dimension] = MapDimensionViewportState(
            centerX: centerX,
            centerZ: centerZ,
            anchor: rememberedAnchor
          )
          self.shareButton.isEnabled = true
          self.updateCoordinateFields(centerX: centerX, centerZ: centerZ, anchor: anchor)
          self.applyViewport(anchor: anchor)
          self.updateObjectOverlay()
          let diagnosticHint = result.errors.isEmpty ? "" : "；点按状态查看错误"
          let layerDetail: String
          switch mode {
          case .tickingAreas:
            layerDetail =
              "常加载区域 \(result.tickingAreaCount) 个、定义区块 \(result.tickingDefinedChunkCount) 个、当前可见 \(result.visibleTickingChunkCount) 个；绿=普通、橙=预加载、紫=重叠"
          case .slime:
            layerDetail = "绿色为史莱姆区块；按基岩版坐标算法计算，不读取世界种子或已生成区块"
          default:
            layerDetail =
              "缓存命中 \(result.cacheHits)/\(result.cacheHits + result.cacheMisses)；解码 \(result.decoded) 个 SubChunk"
          }
          let samplingDetail =
            result.sampleStride > 1
            ? "；代表采样 \(result.sampledChunkCount) 个区块，步长 \(result.sampleStride)"
            : ""
          if self.traitCollection.horizontalSizeClass == .compact {
            // Keep the compact iPhone status readable within the fixed two-line
            // status area; detailed diagnostics remain available by tapping it.
            self.statusLabel.text =
              "中心(\(centerX),\(centerZ)) · \(sideChunks)×\(sideChunks)区块 · \(mode.displayName) · 玩家\(result.playerCount) 实体\(result.entityCount) 方块实体\(result.blockEntityCount) · 错误\(result.errors.count)"
          } else {
            self.statusLabel.text =
              "中心区块 (\(centerX), \(centerZ))；动态 \(sideChunks)×\(sideChunks)；\(mode.displayName)；\(layerDetail)\(samplingDetail)；玩家 \(result.playerCount)；实体 \(result.entityCount)；方块实体 \(result.blockEntityCount)；刷怪区域 \(result.hardcodedSpawnerCount)；村庄 \(result.villageCount)；错误 \(result.errors.count) 条\(diagnosticHint)。缩放会按视口持续扩展渲染区块；低倍率自动降低位图像素密度，拖动可持续续载。"
          }
          self.saveMapState()
          DispatchQueue.main.async { [weak self] in
            self?.refreshForZoomDrivenRadiusIfNeeded()
          }
        }

        // The viewport already includes a preload border, so no
        // additional hidden border is required.
      } catch is MapRenderCancelled {
        DispatchQueue.main.async {
          overlay?.removeFromSuperview()
          if self.activeRenderToken === token { self.isRendering = false }
        }
      } catch {
        DispatchQueue.main.async {
          overlay?.removeFromSuperview()
          guard generation == self.renderGeneration, self.activeRenderToken === token else {
            return
          }
          self.isRendering = false
          self.lastErrors = [error.localizedDescription]
          self.statusLabel.text = "地图读取失败。点按此处查看详情。"
          self.showError(error, title: "地图渲染失败")
        }
      }
    }
  }

  private func renderCrossSectionMap(
    centerX: Int32,
    centerZ: Int32,
    dimension: Int32,
    sideChunks: Int,
    mode: MapRenderMode,
    drawGrid: Bool,
    requestedZoom: CGFloat,
    generation: Int,
    token: MapRenderToken,
    overlay: UIView?,
    reason: String
  ) {
    let axis = currentSliceAxis
    let fixedX = sliceCenterBlockX
    let fixedZ = sliceCenterBlockZ
    let centerY = sliceCenterY
    let sideBlocks = sideChunks * 16
    let half = sideBlocks / 2
    let minimumHorizontal = axis == .x ? fixedZ - Int64(half) : fixedX - Int64(half)
    let minimumY = Int64(centerY) - Int64(half)
    let maximumY = minimumY + Int64(sideBlocks) - 1
    let includePlayers = showPlayers
    let includeEntities = showEntities
    let includeBlockEntities = showBlockEntities
    let includeHardcodedSpawners = showHardcodedSpawners
    let includeSpawns = showSpawnPoints
    let includeUngeneratedSubChunks = showUngeneratedChunks
    statusLabel.text = "\(reason)：正在读取 \(axis.displayName) 轴 \(sideBlocks)×\(sideBlocks) 方块剖面…"

    renderQueue.async { [weak self] in
      guard let self = self else { return }
      if token.isCancelled {
        DispatchQueue.main.async { overlay?.removeFromSuperview() }
        return
      }
      do {
        let renderer = try self.rendererForCurrentSession()
        let database = try self.session.database()
        var diagnostics = [String]()

        var tickingAreas = [BedrockTickingArea]()
        if mode == .tickingAreas {
          do {
            tickingAreas = try TickingAreaStore(session: self.session).records()
              .map(\.area)
              .filter { $0.dimension == dimension }
          } catch {
            diagnostics.append("常加载区块：\(error.localizedDescription)")
          }
        }

        // Scan the horizontal window surrounding the slice, then project only
        // objects whose block coordinate actually intersects the one-block-thick
        // X/Z plane. Village rendering is intentionally disabled in vertical
        // sections, but all other object layers remain available.
        var playerCoordinates = [MapPlayerCoordinate]()
        if includePlayers {
          let playerStore = PlayerNBTStore(session: self.session)
          for record in try playerStore.records() {
            guard let position = playerStore.currentPosition(for: record),
              position.dimension == dimension
            else { continue }
            playerCoordinates.append(
              MapPlayerCoordinate(
                record: record,
                position: position,
                isLocal: playerStore.isLocalPlayer(record),
                uniqueID: playerStore.uniqueID(for: record)
              ))
          }
        }

        var scannedObjects = [BedrockWorldObject]()
        if includeEntities || includeBlockEntities {
          let scanRadius = max(1, (sideChunks + 1) / 2)
          let objectScan = try BedrockWorldObjectScanner(database: database).scanRegionAdaptive(
            centerX: centerX,
            centerZ: centerZ,
            dimension: dimension,
            radius: scanRadius,
            includeEntities: includeEntities,
            includeBlockEntities: includeBlockEntities,
            maximumObjects: 40_000,
            shouldCancel: { token.isCancelled }
          )
          scannedObjects = objectScan.objects
          diagnostics.append(contentsOf: objectScan.diagnostics)
        }

        let spawnerScan = includeHardcodedSpawners
          ? try self.scanHardcodedSpawners(
            database: database,
            centerX: centerX,
            centerZ: centerZ,
            dimension: dimension,
            sideChunks: sideChunks,
            leftChunks: (sideChunks - 1) / 2,
            shouldCancel: { token.isCancelled }
          )
          : (hits: [MapHardcodedSpawnerHit](), diagnostics: [String]())
        diagnostics.append(contentsOf: spawnerScan.diagnostics)

        if token.isCancelled { throw MapRenderCancelled() }
        let result = try renderer.renderCrossSection(
          axis: axis,
          fixedX: fixedX,
          fixedZ: fixedZ,
          centerY: centerY,
          sideBlocks: sideBlocks,
          dimension: dimension,
          mode: mode,
          drawSubChunkGrid: drawGrid,
          projectionDepth: 128,
          pixelsPerBlock: 4,
          showUngeneratedSubChunks: includeUngeneratedSubChunks,
          tickingAreas: tickingAreas,
          shouldCancel: { token.isCancelled }
        )
        if token.isCancelled { throw MapRenderCancelled() }

        func projectedHorizontalAndVertical(
          worldX: Double, worldY: Double, worldZ: Double, planeTolerance: Double? = nil
        ) -> (CGFloat, CGFloat)? {
          if let planeTolerance = planeTolerance {
            if axis == .x, abs(worldX - Double(fixedX)) > planeTolerance { return nil }
            if axis == .z, abs(worldZ - Double(fixedZ)) > planeTolerance { return nil }
          } else {
            let blockX = Int64(floor(worldX))
            let blockZ = Int64(floor(worldZ))
            if axis == .x, blockX != fixedX { return nil }
            if axis == .z, blockZ != fixedZ { return nil }
          }
          let horizontal = axis == .x ? worldZ : worldX
          let localHorizontal = horizontal - Double(result.minimumHorizontal)
          let localVertical = Double(result.maximumY + 1) - worldY
          guard localHorizontal >= 0, localHorizontal < Double(sideBlocks),
            localVertical >= 0, localVertical < Double(sideBlocks)
          else { return nil }
          return (CGFloat(localHorizontal), CGFloat(localVertical))
        }

        let projectedPlayers = playerCoordinates.compactMap { player -> MapPlayerHit? in
          guard let local = projectedHorizontalAndVertical(
            worldX: player.position.x, worldY: player.position.y, worldZ: player.position.z)
          else { return nil }
          return MapPlayerHit(player: player, localX: local.0, localZ: local.1)
        }

        let projectedObjects = scannedObjects.compactMap { object -> MapWorldObjectHit? in
          guard let position = object.position,
            let local = projectedHorizontalAndVertical(
              worldX: position.x, worldY: position.y, worldZ: position.z,
              planeTolerance: self.crossSectionObjectPlaneTolerance)
          else { return nil }
          let normallyVisible =
            (object.kind == .entity && includeEntities)
            || (object.kind == .blockEntity && includeBlockEntities)
          return MapWorldObjectHit(
            object: object, localX: local.0, localZ: local.1, isNormallyVisible: normallyVisible)
        }

        let projectedSpawns: [MapSpawnHit]
        if includeSpawns {
          projectedSpawns = self.spawnCoordinates.compactMap { spawn in
            guard spawn.dimension == dimension, let y = spawn.y else { return nil }
            let x = Double(spawn.x) + 0.5
            let z = Double(spawn.z) + 0.5
            guard let local = projectedHorizontalAndVertical(
              worldX: x, worldY: Double(y) + 0.5, worldZ: z)
            else { return nil }
            return MapSpawnHit(spawn: spawn, localX: local.0, localZ: local.1)
          }
        } else {
          projectedSpawns = []
        }

        let allErrors = result.errors + diagnostics
        DispatchQueue.main.async {
          overlay?.removeFromSuperview()
          guard generation == self.renderGeneration, self.activeRenderToken === token else { return }
          self.isRendering = false
          self.updateMapCanvasSize(sideBlocks: sideBlocks)
          self.imageView.image = result.image
          self.lastRenderedImage = result.image
          self.lastBlockNames = []
          self.lastBlockHeights = []
          self.lastErrors = allErrors
          self.lastSpawnHits = projectedSpawns
          self.lastPlayerHits = projectedPlayers
          self.lastWorldObjectHits = projectedObjects
          self.lastHardcodedSpawnerHits = spawnerScan.hits
          self.lastVillageHits = []
          self.lastCenterX = centerX
          self.lastCenterZ = centerZ
          self.renderedSideChunks = sideChunks
          self.currentMode = mode
          self.renderedCrossHorizontalStart = result.minimumHorizontal
          self.renderedCrossMinimumY = result.minimumY
          self.renderedCrossMaximumY = result.maximumY
          self.shareButton.isEnabled = true
          self.updateCoordinateFields(centerX: centerX, centerZ: centerZ, anchor: nil)
          self.applyCrossSectionViewport(effectiveZoom: requestedZoom)
          self.updateObjectOverlay()
          let sampling = result.sampleStride > 1 ? "；采样步长 \(result.sampleStride)" : ""
          let layerCounts = "玩家 \(projectedPlayers.count)；实体/方块实体 \(projectedObjects.count)；刷怪区域 \(spawnerScan.hits.count)"
          if self.traitCollection.horizontalSizeClass == .compact {
            self.statusLabel.text =
              "\(axis.displayName)剖面 · 中心(\(fixedX),\(centerY),\(fixedZ)) · \(sideBlocks)×\(sideBlocks)方块 · \(mode.displayName) · 错误\(allErrors.count)"
          } else {
            self.statusLabel.text =
              "\(axis.displayName) 轴剖面；中心方块 (\(fixedX), \(centerY), \(fixedZ))；范围 \(sideBlocks)×\(sideBlocks) 方块；向 \(axis.displayName)- 投影 128 方块；Y 正方向在上；\(mode.displayName)；解码 \(result.decodedSubChunks) 个 SubChunk\(sampling)；\(layerCounts)；错误 \(allErrors.count) 条。"
          }
          self.saveMapState()
        }
      } catch is MapRenderCancelledBridge {
        DispatchQueue.main.async {
          overlay?.removeFromSuperview()
          if self.activeRenderToken === token { self.isRendering = false }
        }
      } catch is MapRenderCancelled {
        DispatchQueue.main.async {
          overlay?.removeFromSuperview()
          if self.activeRenderToken === token { self.isRendering = false }
        }
      } catch {
        DispatchQueue.main.async {
          overlay?.removeFromSuperview()
          guard generation == self.renderGeneration, self.activeRenderToken === token else { return }
          self.isRendering = false
          self.lastErrors = [error.localizedDescription]
          self.statusLabel.text = "剖面读取失败。点按此处查看详情。"
          self.showError(error, title: "剖面渲染失败")
        }
      }
    }
  }

  private func applyCrossSectionViewport(effectiveZoom: CGFloat) {
    isApplyingViewport = true
    view.layoutIfNeeded()
    let requestedRawZoom = rawZoomScale(forEffectiveScale: max(effectiveZoom, 0.0001))
    expandZoomRangeIfNeeded(for: requestedRawZoom)
    let targetZoom = pixelAlignedZoomScale(requestedRawZoom)
    scrollView.setZoomScale(targetZoom, animated: false)
    view.layoutIfNeeded()
    let center = CGPoint(
      x: imageView.bounds.midX * targetZoom - scrollView.bounds.width / 2,
      y: imageView.bounds.midY * targetZoom - scrollView.bounds.height / 2
    )
    scrollView.setContentOffset(clampedContentOffset(center), animated: false)
    alignContentOffsetToDevicePixels()
    DispatchQueue.main.async { [weak self] in
      self?.isApplyingViewport = false
      self?.updateObjectOverlay()
    }
  }

  private func rendererForCurrentSession() throws -> ChunkSurfaceRenderer {
    if let chunkRenderer = chunkRenderer { return chunkRenderer }
    let renderer = ChunkSurfaceRenderer(database: try session.database(), cache: chunkCache)
    chunkRenderer = renderer
    return renderer
  }

  private func scanHardcodedSpawners(
    database: MojangLevelDB,
    centerX: Int32,
    centerZ: Int32,
    dimension: Int32,
    sideChunks: Int,
    leftChunks: Int,
    shouldCancel: () -> Bool
  ) throws -> (hits: [MapHardcodedSpawnerHit], diagnostics: [String]) {
    let rightChunks = sideChunks - leftChunks - 1
    let (directLookupCount, overflow) = sideChunks.multipliedReportingOverflow(by: sideChunks)
    if !overflow, directLookupCount <= 16_384 {
      var positions = [ChunkPosition]()
      positions.reserveCapacity(directLookupCount)
      for dz in -leftChunks...rightChunks {
        for dx in -leftChunks...rightChunks {
          if shouldCancel() { throw MapRenderCancelled() }
          guard let x = MapChunkSamplingPlan.safeChunkCoordinate(center: centerX, offset: dx),
            let z = MapChunkSamplingPlan.safeChunkCoordinate(center: centerZ, offset: dz)
          else { continue }
          positions.append(ChunkPosition(x: x, z: z, dimension: dimension))
        }
      }
      return try scanHardcodedSpawners(database: database, positions: positions)
    }

    // For a very large visible range, scanning all database keys once is much
    // cheaper than issuing one missing-key lookup for every represented chunk.
    let minimumX = Int64(centerX) - Int64(leftChunks)
    let maximumX = Int64(centerX) + Int64(rightChunks)
    let minimumZ = Int64(centerZ) - Int64(leftChunks)
    let maximumZ = Int64(centerZ) + Int64(rightChunks)
    var positions = [ChunkPosition]()
    for entry in try database.entries(includeValues: false) {
      if shouldCancel() { throw MapRenderCancelled() }
      guard let parsed = BedrockDBKey.parse(entry.key),
        parsed.recordType == .hardcodedSpawners,
        parsed.position.dimension == dimension,
        Int64(parsed.position.x) >= minimumX,
        Int64(parsed.position.x) <= maximumX,
        Int64(parsed.position.z) >= minimumZ,
        Int64(parsed.position.z) <= maximumZ
      else { continue }
      positions.append(parsed.position)
    }
    var result = try scanHardcodedSpawners(database: database, positions: positions)
    result.diagnostics.insert("HardcodedSpawners 范围较大，已切换为数据库键索引扫描。", at: 0)
    return result
  }

  private func renderRegion(
    renderer: ChunkSurfaceRenderer,
    centerX: Int32,
    centerZ: Int32,
    dimension: Int32,
    sideChunks: Int,
    leftChunks: Int,
    mode: MapRenderMode,
    drawGrid: Bool,
    generatedChunkPositions: Set<ChunkPosition>,
    ungeneratedDisplay: MapUngeneratedChunkDisplayMode,
    spawnCoordinates: [MapSpawnCoordinate],
    playerCoordinates: [MapPlayerCoordinate],
    worldObjects: [BedrockWorldObject],
    displayEntities: Bool,
    displayBlockEntities: Bool,
    hardcodedSpawnerHits: [MapHardcodedSpawnerHit],
    villageFeatures: [VillageMapFeature],
    tickingAreas: [BedrockTickingArea],
    additionalErrors: [String],
    shouldCancel: () -> Bool
  ) throws -> RenderedMapRegion {
    let rightChunks = sideChunks - leftChunks - 1
    let sideBlocks = sideChunks * 16
    let samplingPlan = MapChunkSamplingPlan.make(
      sideChunks: sideChunks,
      leftChunks: leftChunks,
      maximumSamplesPerAxis: maximumDecodedChunksPerAxis
    )
    let keepsPerBlockMetadata =
      !samplingPlan.isDownsampled
      && sideBlocks <= maximumPerBlockMetadataSide
    var names: [String] =
      keepsPerBlockMetadata
      ? Array(repeating: "minecraft:air", count: sideBlocks * sideBlocks)
      : []
    var heights: [Int16] =
      keepsPerBlockMetadata
      ? Array(repeating: Int16.min, count: sideBlocks * sideBlocks)
      : []
    var chunkImages = [UIImage?](repeating: nil, count: samplingPlan.sampleCount)
    var ungeneratedTiles = [Bool](repeating: false, count: samplingPlan.sampleCount)
    var decoded = 0
    var errors = additionalErrors
    var cacheHits = 0
    var cacheMisses = 0
    var skippedOutOfRangeSamples = 0

    let startChunkX = Int64(centerX) - Int64(leftChunks)
    let startChunkZ = Int64(centerZ) - Int64(leftChunks)
    let endChunkX = Int64(centerX) + Int64(rightChunks)
    let endChunkZ = Int64(centerZ) + Int64(rightChunks)
    let visibleTickingChunkCount =
      mode == .tickingAreas
      ? countVisibleTickingChunks(
        tickingAreas,
        dimension: dimension,
        minimumChunkX: startChunkX,
        maximumChunkX: endChunkX,
        minimumChunkZ: startChunkZ,
        maximumChunkZ: endChunkZ
      )
      : 0

    // Only sampled representative chunks are sorted center-first. The
    // represented world extent remains the full sideChunks × sideChunks.
    let samples = samplingPlan.zAxis.indices.flatMap { zIndex in
      samplingPlan.xAxis.indices.map { xIndex in (xIndex, zIndex) }
    }.sorted { lhs, rhs in
      let lx = samplingPlan.xAxis[lhs.0].representativeOffset
      let lz = samplingPlan.zAxis[lhs.1].representativeOffset
      let rx = samplingPlan.xAxis[rhs.0].representativeOffset
      let rz = samplingPlan.zAxis[rhs.1].representativeOffset
      let leftDistance = Int64(lx) * Int64(lx) + Int64(lz) * Int64(lz)
      let rightDistance = Int64(rx) * Int64(rx) + Int64(rz) * Int64(rz)
      return leftDistance < rightDistance
    }

    for (xIndex, zIndex) in samples {
      if shouldCancel() { throw MapRenderCancelled() }
      let xSample = samplingPlan.xAxis[xIndex]
      let zSample = samplingPlan.zAxis[zIndex]
      let imageIndex = zIndex * samplingPlan.xAxis.count + xIndex

      guard
        let chunkX = MapChunkSamplingPlan.safeChunkCoordinate(
          center: centerX,
          offset: xSample.representativeOffset
        ),
        let chunkZ = MapChunkSamplingPlan.safeChunkCoordinate(
          center: centerZ,
          offset: zSample.representativeOffset
        )
      else {
        skippedOutOfRangeSamples += 1
        continue
      }

      let originX = (xSample.startOffset + leftChunks) * 16
      let originZ = (zSample.startOffset + leftChunks) * 16

      if mode == .tickingAreas {
        let tileMinimumX = MapChunkSamplingPlan.safeChunkCoordinate(
          center: centerX,
          offset: xSample.startOffset
        )
        let tileMaximumX = MapChunkSamplingPlan.safeChunkCoordinate(
          center: centerX,
          offset: xSample.endOffset
        )
        let tileMinimumZ = MapChunkSamplingPlan.safeChunkCoordinate(
          center: centerZ,
          offset: zSample.startOffset
        )
        let tileMaximumZ = MapChunkSamplingPlan.safeChunkCoordinate(
          center: centerZ,
          offset: zSample.endOffset
        )
        let matches: [BedrockTickingArea]
        if let tileMinimumX = tileMinimumX,
          let tileMaximumX = tileMaximumX,
          let tileMinimumZ = tileMinimumZ,
          let tileMaximumZ = tileMaximumZ
        {
          let context = TickingAreaSelectionContext(
            dimension: dimension,
            minimumX: tileMinimumX,
            minimumZ: tileMinimumZ,
            maximumX: tileMaximumX,
            maximumZ: tileMaximumZ
          )
          matches = tickingAreas.filter(context.intersects)
        } else {
          matches = []
        }
        chunkImages[imageIndex] = makeTickingAreaChunkImage(matches: matches)
        if keepsPerBlockMetadata {
          let name = matches.isEmpty ? "mcbeeditor:non_ticking_chunk" : "mcbeeditor:ticking_chunk"
          for localZ in 0..<16 {
            for localX in 0..<16 {
              let destination = (originZ + localZ) * sideBlocks + originX + localX
              names[destination] = name
              heights[destination] = 0
            }
          }
        }
        cacheMisses += 1
        continue
      }

      let lookup = try renderer.renderChunk(x: chunkX, z: chunkZ, dimension: dimension, mode: mode)
      let chunk = lookup.result
      if lookup.cacheHit { cacheHits += 1 } else { cacheMisses += 1 }
      decoded += chunk.decodedSubChunks
      errors.append(contentsOf: chunk.errors.map { "(\(chunkX),\(chunkZ)) \($0)" })
      chunkImages[imageIndex] = chunk.image
      ungeneratedTiles[imageIndex] = !generatedChunkPositions.contains(
        ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension))
      if keepsPerBlockMetadata {
        for localZ in 0..<16 {
          for localX in 0..<16 {
            let source = localZ * 16 + localX
            let destination = (originZ + localZ) * sideBlocks + originX + localX
            names[destination] = chunk.blockNames[source]
            heights[destination] = chunk.blockHeights[source]
          }
        }
      }
    }

    if skippedOutOfRangeSamples > 0 {
      errors.append("有 \(skippedOutOfRangeSamples) 个采样点超出基岩版 Int32 区块坐标范围，已跳过。")
    }

    let startBlockX = startChunkX * 16
    let startBlockZ = startChunkZ * 16
    let endBlockX = startBlockX + Int64(sideBlocks)
    let endBlockZ = startBlockZ + Int64(sideBlocks)
    let spawnHits = spawnCoordinates.compactMap { spawn -> MapSpawnHit? in
      guard spawn.x >= startBlockX, spawn.x < endBlockX,
        spawn.z >= startBlockZ, spawn.z < endBlockZ
      else { return nil }
      return MapSpawnHit(
        spawn: spawn,
        localX: CGFloat(spawn.x - startBlockX) + 0.5,
        localZ: CGFloat(spawn.z - startBlockZ) + 0.5
      )
    }
    let playerHits = playerCoordinates.compactMap { player -> MapPlayerHit? in
      let position = player.position
      let blockX = Int64(floor(position.x))
      let blockZ = Int64(floor(position.z))
      guard blockX >= startBlockX, blockX < endBlockX,
        blockZ >= startBlockZ, blockZ < endBlockZ
      else { return nil }
      return MapPlayerHit(
        player: player,
        localX: CGFloat(position.x - Double(startBlockX)),
        localZ: CGFloat(position.z - Double(startBlockZ))
      )
    }
    let villageResidentStableIDs = Set(villageFeatures.flatMap(\.residentEntities).map(\.stableID))
    let worldObjectHits = worldObjects.compactMap { object -> MapWorldObjectHit? in
      let isNormallyVisible =
        (object.kind == .entity && displayEntities)
        || (object.kind == .blockEntity && displayBlockEntities)
      guard isNormallyVisible || villageResidentStableIDs.contains(object.stableID) else {
        return nil
      }
      guard let position = object.position,
        position.blockX >= startBlockX, position.blockX < endBlockX,
        position.blockZ >= startBlockZ, position.blockZ < endBlockZ
      else { return nil }
      return MapWorldObjectHit(
        object: object,
        localX: CGFloat(position.x - Double(startBlockX)),
        localZ: CGFloat(position.z - Double(startBlockZ)),
        isNormallyVisible: isNormallyVisible
      )
    }

    let visibleHardcodedSpawnerHits = hardcodedSpawnerHits.filter { hit in
      let area = hit.area
      return Int64(area.maximumX) >= startBlockX && Int64(area.minimumX) < endBlockX
        && Int64(area.maximumZ) >= startBlockZ && Int64(area.minimumZ) < endBlockZ
    }
    let villageHits = villageFeatures.compactMap { feature -> MapVillageHit? in
      guard feature.dimension == dimension else { return nil }
      if let villageBounds = feature.bounds {
        guard villageBounds.maximumX >= startBlockX, villageBounds.minimumX < endBlockX,
          villageBounds.maximumZ >= startBlockZ, villageBounds.minimumZ < endBlockZ
        else { return nil }
      } else if let center = feature.center {
        guard center.x >= startBlockX, center.x < endBlockX,
          center.z >= startBlockZ, center.z < endBlockZ
        else { return nil }
      } else {
        guard
          feature.pointsOfInterest.contains(where: {
            $0.x >= startBlockX && $0.x < endBlockX && $0.z >= startBlockZ && $0.z < endBlockZ
          })
        else { return nil }
      }
      return MapVillageHit(feature: feature)
    }

    // The bitmap and decoded-chunk workload are bounded, not the represented
    // world range. Nearest-neighbour stretching preserves crisp chunk colors.
    let logicalSide = CGFloat(sideBlocks)
    let rendererSide = min(logicalSide, maximumMapRasterSidePixels)
    let blockToRenderer = rendererSide / logicalSide
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = ungeneratedDisplay == .air
    if logicalSide <= maximumMapRasterSidePixels {
      format.scale = max(1, min(8, floor(maximumMapRasterSidePixels / logicalSide)))
    } else {
      format.scale = 1
    }
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: rendererSide, height: rendererSide),
      format: format
    ).image { context in
      let cg = context.cgContext
      cg.interpolationQuality = .none
      cg.setAllowsAntialiasing(false)
      cg.setShouldAntialias(false)
      if ungeneratedDisplay == .air {
        UIColor.systemGray5.setFill()
        context.fill(CGRect(x: 0, y: 0, width: rendererSide, height: rendererSide))
      }

      var ungeneratedTextureRects = [CGRect]()
      for (zIndex, zSample) in samplingPlan.zAxis.enumerated() {
        for (xIndex, xSample) in samplingPlan.xAxis.enumerated() {
          let index = zIndex * samplingPlan.xAxis.count + xIndex
          let logicalX = CGFloat(xSample.startOffset + leftChunks) * 16
          let logicalZ = CGFloat(zSample.startOffset + leftChunks) * 16
          let rect = CGRect(
            x: logicalX * blockToRenderer,
            y: logicalZ * blockToRenderer,
            width: CGFloat(xSample.span * 16) * blockToRenderer,
            height: CGFloat(zSample.span * 16) * blockToRenderer
          )
          guard let chunkImage = chunkImages[index] else { continue }
          let isUngenerated = ungeneratedTiles[index]
          if isUngenerated {
            if ungeneratedDisplay == .texture {
              ungeneratedTextureRects.append(rect)
            } else {
              drawUngeneratedChunkPlaceholder(context: cg, in: rect, displayMode: ungeneratedDisplay)
            }
          } else {
            chunkImage.draw(in: rect)
          }
        }
      }

      let renderedChunkSide = 16 * blockToRenderer
      if drawGrid, renderedChunkSide >= 1 {
        cg.setStrokeColor(UIColor.label.withAlphaComponent(0.28).cgColor)
        cg.setLineWidth(max(0.15, blockToRenderer * 0.15))
        for value in 0...sideChunks {
          let position = CGFloat(value) * renderedChunkSide
          cg.move(to: CGPoint(x: position, y: 0))
          cg.addLine(to: CGPoint(x: position, y: rendererSide))
          cg.move(to: CGPoint(x: 0, y: position))
          cg.addLine(to: CGPoint(x: rendererSide, y: position))
        }
        cg.strokePath()
      }
      if ungeneratedDisplay == .texture, !ungeneratedTextureRects.isEmpty {
        drawUngeneratedChunkTexture(
          context: cg,
          rects: ungeneratedTextureRects,
          chunkSide: renderedChunkSide
        )
      }
    }
    return RenderedMapRegion(
      image: image,
      names: names,
      heights: heights,
      decoded: decoded,
      errors: errors,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      sampleStride: samplingPlan.stride,
      sampledChunkCount: samplingPlan.sampleCount,
      spawnHits: spawnHits,
      playerHits: playerHits,
      worldObjectHits: worldObjectHits,
      hardcodedSpawnerHits: visibleHardcodedSpawnerHits,
      villageHits: villageHits,
      playerCount: playerHits.count,
      entityCount: worldObjectHits.filter { $0.isNormallyVisible && $0.object.kind == .entity }
        .count,
      blockEntityCount: worldObjectHits.filter {
        $0.isNormallyVisible && $0.object.kind == .blockEntity
      }.count,
      hardcodedSpawnerCount: visibleHardcodedSpawnerHits.count,
      villageCount: villageHits.count,
      tickingAreaCount: tickingAreas.count,
      tickingDefinedChunkCount: tickingAreas.reduce(0) { partial, area in
        let value = area.chunkCount
        if value == Int.max || partial > Int.max - value { return Int.max }
        return partial + value
      },
      visibleTickingChunkCount: visibleTickingChunkCount
    )
  }

  private func countVisibleTickingChunks(
    _ areas: [BedrockTickingArea],
    dimension: Int32,
    minimumChunkX: Int64,
    maximumChunkX: Int64,
    minimumChunkZ: Int64,
    maximumChunkZ: Int64
  ) -> Int {
    let maximumExactChecks = 250_000
    var checked = 0
    var visible = Set<ChunkPosition>()

    for area in areas where area.dimension == dimension {
      let normalized = area.normalized
      let areaMinimumX: Int64
      let areaMaximumX: Int64
      let areaMinimumZ: Int64
      let areaMaximumZ: Int64
      if normalized.isCircle {
        let center = normalized.centerChunk
        let radius = Int64(normalized.radius)
        areaMinimumX = Int64(center.x) - radius
        areaMaximumX = Int64(center.x) + radius
        areaMinimumZ = Int64(center.z) - radius
        areaMaximumZ = Int64(center.z) + radius
      } else {
        areaMinimumX = Int64(normalized.minimumX)
        areaMaximumX = Int64(normalized.maximumX)
        areaMinimumZ = Int64(normalized.minimumZ)
        areaMaximumZ = Int64(normalized.maximumZ)
      }

      let startX = max(minimumChunkX, areaMinimumX, Int64(Int32.min))
      let endX = min(maximumChunkX, areaMaximumX, Int64(Int32.max))
      let startZ = max(minimumChunkZ, areaMinimumZ, Int64(Int32.min))
      let endZ = min(maximumChunkZ, areaMaximumZ, Int64(Int32.max))
      guard startX <= endX, startZ <= endZ else { continue }

      let width = endX - startX + 1
      let depth = endZ - startZ + 1
      let (candidateCount, overflow) = width.multipliedReportingOverflow(by: depth)
      guard !overflow,
        candidateCount <= Int64(maximumExactChecks - checked)
      else { return Int.max }
      checked += Int(candidateCount)

      for z in startZ...endZ {
        for x in startX...endX {
          let chunkX = Int32(x)
          let chunkZ = Int32(z)
          if normalized.contains(chunkX: chunkX, chunkZ: chunkZ) {
            visible.insert(ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension))
          }
        }
      }
    }
    return visible.count
  }

  private func makeTickingAreaChunkImage(matches: [BedrockTickingArea]) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image {
      context in
      let fill: UIColor
      if matches.count > 1 {
        fill = .systemPurple
      } else if matches.first?.preload == true {
        fill = .systemOrange
      } else if !matches.isEmpty {
        fill = .systemGreen
      } else {
        fill = UIColor(white: 0.20, alpha: 1)
      }
      fill.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
      guard !matches.isEmpty else { return }
      UIColor.white.withAlphaComponent(0.45).setStroke()
      let cg = context.cgContext
      cg.setLineWidth(1)
      cg.stroke(CGRect(x: 0.5, y: 0.5, width: 15, height: 15))
      if matches.first?.isCircle == true {
        UIColor.white.withAlphaComponent(0.25).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 4, y: 4, width: 8, height: 8))
      }
    }
  }

  private func drawSpawnMarker(context: CGContext, hit: MapSpawnHit) {
    let x = hit.localX
    let z = hit.localZ
    let radius: CGFloat = 1.55
    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: 0.45), blur: 0.65,
      color: UIColor.black.withAlphaComponent(0.55).cgColor)
    context.setFillColor(
      (hit.spawn.kind == .world ? UIColor.systemYellow : UIColor.systemGreen).cgColor)
    context.fillEllipse(
      in: CGRect(x: x - radius, y: z - radius, width: radius * 2, height: radius * 2))
    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(0.42)
    context.strokeEllipse(
      in: CGRect(x: x - radius, y: z - radius, width: radius * 2, height: radius * 2))
    context.setStrokeColor(UIColor.black.cgColor)
    context.setLineWidth(0.42)
    switch hit.spawn.kind {
    case .world:
      context.move(to: CGPoint(x: x - 0.75, y: z))
      context.addLine(to: CGPoint(x: x + 0.75, y: z))
      context.move(to: CGPoint(x: x, y: z - 0.75))
      context.addLine(to: CGPoint(x: x, y: z + 0.75))
    case .player:
      context.addEllipse(in: CGRect(x: x - 0.38, y: z - 0.82, width: 0.76, height: 0.76))
      context.move(to: CGPoint(x: x - 0.72, y: z + 0.78))
      context.addCurve(
        to: CGPoint(x: x + 0.72, y: z + 0.78), control1: CGPoint(x: x - 0.42, y: z - 0.10),
        control2: CGPoint(x: x + 0.42, y: z - 0.10))
    }
    context.strokePath()
    context.restoreGState()
  }

  private func drawWorldObject(
    context: CGContext, x: CGFloat, z: CGFloat, kind: BedrockWorldObjectKind
  ) {
    let radius: CGFloat = kind == .entity ? 1.05 : 0.95
    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: 0.35), blur: 0.5,
      color: UIColor.black.withAlphaComponent(0.55).cgColor)
    let color = kind == .entity ? UIColor.systemBlue : UIColor.systemTeal
    context.setFillColor(color.cgColor)
    if kind == .entity {
      context.fillEllipse(
        in: CGRect(x: x - radius, y: z - radius, width: radius * 2, height: radius * 2))
    } else {
      context.fill(CGRect(x: x - radius, y: z - radius, width: radius * 2, height: radius * 2))
    }
    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(0.32)
    if kind == .entity {
      context.strokeEllipse(
        in: CGRect(x: x - radius, y: z - radius, width: radius * 2, height: radius * 2))
    } else {
      context.stroke(CGRect(x: x - radius, y: z - radius, width: radius * 2, height: radius * 2))
    }
    context.restoreGState()
  }

  private func updateMapCanvasSize(sideBlocks: Int) {
    let logicalBlocks = max(16, sideBlocks)
    let unboundedSide = Double(logicalBlocks) * Double(basePointsPerBlock)
    let boundedSide = min(Double(maximumMapCanvasSidePoints), unboundedSide)
    let side = CGFloat(max(Double(basePointsPerBlock * 16), boundedSide))
    canvasPointsPerBlock = side / CGFloat(logicalBlocks)
    if abs(imageWidthConstraint.constant - side) > 0.5 {
      imageWidthConstraint.constant = side
      imageHeightConstraint.constant = side
      view.layoutIfNeeded()
      updatePanInsets()
      updateZoomLimits()
    }
  }

  /// User-visible zoom expressed against `basePointsPerBlock`. UIScrollView's
  /// raw zoom can be much larger after the finite-canvas renormalization.
  private var effectiveZoomScale: CGFloat {
    effectiveZoomScale(forRawScale: max(scrollView.zoomScale, CGFloat.leastNormalMagnitude))
  }

  private func effectiveZoomScale(forRawScale rawScale: CGFloat) -> CGFloat {
    guard basePointsPerBlock > 0 else { return rawScale }
    return max(
      CGFloat.leastNormalMagnitude,
      rawScale * canvasPointsPerBlock / basePointsPerBlock
    )
  }

  private func rawZoomScale(forEffectiveScale effectiveScale: CGFloat) -> CGFloat {
    guard canvasPointsPerBlock > 0 else { return effectiveScale }
    return max(
      CGFloat.leastNormalMagnitude,
      effectiveScale * basePointsPerBlock / canvasPointsPerBlock
    )
  }

  private func updatePanInsets() {
    guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
    // At fit-to-screen zoom the map itself exactly matches the viewport,
    // which otherwise leaves no scroll range. Transparent virtual margins
    // let the viewport center move beyond the current N×N image so the
    // automatic loader can request the next region.
    let horizontal = max(96, scrollView.bounds.width * panMarginFactor)
    let vertical = max(96, scrollView.bounds.height * panMarginFactor)
    let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    if scrollView.contentInset != insets {
      scrollView.contentInset = insets
    }
  }

  private func isVillageVillager(_ object: BedrockWorldObject) -> Bool {
    guard object.kind == .entity else { return false }
    let identifier = object.identifier
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let localName =
      identifier.split(separator: ":", omittingEmptySubsequences: true).last.map(String.init)
      ?? identifier
    return localName == "villager" || localName == "villager_v2"
  }

  private func villagePOILinks(
    villages: [MapVillageHit],
    worldObjects: [MapWorldObjectHit]
  ) -> [MapVillagePOILink] {
    let villagers = worldObjects.filter { hit in
      isVillageVillager(hit.object)
    }
    guard !villagers.isEmpty else { return [] }

    var references = [String: Set<String>]()
    for villager in villagers {
      references[villager.object.stableID] = villageReferencePositionKeys(
        in: villager.object.document.root)
    }

    var seen = Set<String>()
    var result = [MapVillagePOILink]()
    for village in villages {
      for point in village.feature.pointsOfInterest {
        let exactKey = point.coordinateKey
        let horizontalKey = point.horizontalCoordinateKey
        for villager in villagers {
          let idMatches =
            villager.object.uniqueID.map { point.linkedEntityIDs.contains($0) } ?? false
          let positionKeys = references[villager.object.stableID] ?? []
          let positionMatches =
            positionKeys.contains(exactKey) || positionKeys.contains(horizontalKey)
          guard idMatches || positionMatches else { continue }
          let pairKey = "\(villager.object.stableID)|\(exactKey)"
          guard seen.insert(pairKey).inserted else { continue }
          result.append(
            MapVillagePOILink(
              entityStableID: villager.object.stableID,
              entityLocalX: villager.localX,
              entityLocalZ: villager.localZ,
              point: point
            ))
        }
      }
    }
    return result
  }

  private func villageReferencePositionKeys(in root: NBTValue) -> Set<String> {
    let relationshipTerms = ["poi", "home", "bed", "work", "job", "dwelling", "meeting", "station"]
    var result = Set<String>()

    func append(_ vector: (Int64, Int64, Int64)) {
      result.insert("\(vector.0):\(vector.1):\(vector.2)")
      result.insert("\(vector.0):\(vector.2)")
    }

    func walk(_ value: NBTValue, nameHint: String, inheritedRelevant: Bool) {
      switch value {
      case .compound(let tags):
        let normalizedHint = normalizedNBTName(nameHint)
        let isRelevant =
          inheritedRelevant || relationshipTerms.contains(where: { normalizedHint.contains($0) })
        if isRelevant, let vector = mapNBTXYZ(in: tags) { append(vector) }
        for tag in tags {
          let name = normalizedNBTName(tag.name)
          let childRelevant = isRelevant || relationshipTerms.contains(where: { name.contains($0) })
          if childRelevant, let vector = mapNBTVector(tag.value) { append(vector) }
          walk(tag.value, nameHint: tag.name, inheritedRelevant: childRelevant)
        }
      case .list(_, let values):
        for child in values {
          walk(child, nameHint: nameHint, inheritedRelevant: inheritedRelevant)
        }
      default:
        break
      }
    }

    walk(root, nameHint: "", inheritedRelevant: false)
    return result
  }

  private func mapNBTVector(_ value: NBTValue) -> (Int64, Int64, Int64)? {
    switch value {
    case .intArray(let values) where values.count >= 3:
      return (Int64(values[0]), Int64(values[1]), Int64(values[2]))
    case .longArray(let values) where values.count >= 3:
      return (values[0], values[1], values[2])
    case .list(_, let values) where values.count >= 3:
      guard let x = mapNBTInteger(values[0]),
        let y = mapNBTInteger(values[1]),
        let z = mapNBTInteger(values[2])
      else { return nil }
      return (x, y, z)
    case .compound(let tags):
      return mapNBTXYZ(in: tags)
    default:
      return nil
    }
  }

  private func mapNBTXYZ(in tags: [NBTNamedTag]) -> (Int64, Int64, Int64)? {
    let x = tags.first(where: {
      ["x", "posx", "positionx", "blockx"].contains(normalizedNBTName($0.name))
    })
    .flatMap { mapNBTInteger($0.value) }
    let y = tags.first(where: {
      ["y", "posy", "positiony", "blocky"].contains(normalizedNBTName($0.name))
    })
    .flatMap { mapNBTInteger($0.value) }
    let z = tags.first(where: {
      ["z", "posz", "positionz", "blockz"].contains(normalizedNBTName($0.name))
    })
    .flatMap { mapNBTInteger($0.value) }
    guard let x = x, let y = y, let z = z else { return nil }
    return (x, y, z)
  }

  private func mapNBTInteger(_ value: NBTValue) -> Int64? {
    switch value {
    case .byte(let number): return Int64(number)
    case .short(let number): return Int64(number)
    case .int(let number): return Int64(number)
    case .long(let number): return number
    case .float(let number): return Int64(number.rounded())
    case .double(let number): return Int64(number.rounded())
    default: return nil
    }
  }

  private func normalizedNBTName(_ value: String) -> String {
    value.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  private func updateObjectOverlay() {
    guard lastRenderedImage != nil else {
      objectOverlayView.clear()
      return
    }
    if currentSliceAxis != .y {
      objectOverlayView.updateCrossSection(
        spawnHits: lastSpawnHits,
        playerHits: lastPlayerHits,
        worldObjectHits: lastWorldObjectHits,
        hardcodedSpawnerHits: lastHardcodedSpawnerHits,
        selectedObjectID: selectedWorldObjectID,
        selectedSpawnerID: selectedSpawnerID,
        selectedBlock: selectedBlock,
        axis: currentSliceAxis,
        fixedX: sliceCenterBlockX,
        fixedZ: sliceCenterBlockZ,
        minimumHorizontal: renderedCrossHorizontalStart,
        minimumY: renderedCrossMinimumY,
        maximumY: renderedCrossMaximumY,
        sideBlocks: renderedSideChunks * 16,
        currentDimension: BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue,
        imageView: imageView,
        showBuildHeightLimits: showBuildHeightLimits
      )
      return
    }
    let startBlockX = renderedStartBlockX
    let startBlockZ = renderedStartBlockZ
    let poiLinks =
      showVillages && showEntities
      ? villagePOILinks(villages: lastVillageHits, worldObjects: lastWorldObjectHits)
      : []
    objectOverlayView.update(
      spawnHits: lastSpawnHits,
      playerHits: lastPlayerHits,
      worldObjectHits: lastWorldObjectHits,
      hardcodedSpawnerHits: lastHardcodedSpawnerHits,
      villageHits: lastVillageHits,
      villagePOILinks: poiLinks,
      selectedObjectID: selectedWorldObjectID,
      selectedVillageID: selectedVillageID,
      selectedVillageEntityIDs: selectedVillageEntityIDs,
      selectedSpawnerID: selectedSpawnerID,
      selectedBlock: selectedBlock,
      selectedChunk: selectedChunk,
      currentDimension: BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue,
      startBlockX: startBlockX,
      startBlockZ: startBlockZ,
      sideBlocks: renderedSideChunks * 16,
      imageView: imageView
    )
  }

  private func pixelAlignedZoomScale(_ proposedScale: CGFloat) -> CGFloat {
    expandZoomRangeIfNeeded(for: proposedScale)
    let clamped = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale, proposedScale))
    let pixelsPerBlockAtScaleOne = canvasPointsPerBlock * UIScreen.main.scale
    guard pixelsPerBlockAtScaleOne > 0 else { return clamped }

    // Below one device pixel per block, integer-pixel alignment would jump
    // back to a much larger scale and prevent continuous zooming out.
    guard clamped * pixelsPerBlockAtScaleOne >= 1 else { return clamped }
    let aligned = round(clamped * pixelsPerBlockAtScaleOne) / pixelsPerBlockAtScaleOne
    return min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale, aligned))
  }

  private func alignContentOffsetToDevicePixels() {
    let scale = UIScreen.main.scale
    guard scale > 0 else { return }
    let minimumX = -scrollView.contentInset.left
    let minimumY = -scrollView.contentInset.top
    let maximumX = max(
      minimumX,
      scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
    let maximumY = max(
      minimumY,
      scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
    let aligned = CGPoint(
      x: min(maximumX, max(minimumX, round(scrollView.contentOffset.x * scale) / scale)),
      y: min(maximumY, max(minimumY, round(scrollView.contentOffset.y * scale) / scale))
    )
    if abs(aligned.x - scrollView.contentOffset.x) > 0.001
      || abs(aligned.y - scrollView.contentOffset.y) > 0.001
    {
      scrollView.setContentOffset(aligned, animated: false)
    }
  }

  private func currentViewportAnchor() -> MapViewportAnchor? {
    guard currentSliceAxis == .y else { return nil }
    guard lastRenderedImage != nil, imageView.bounds.width > 0, imageView.bounds.height > 0 else {
      return nil
    }
    let sideBlocks = Double(renderedSideChunks * 16)
    let rawZoom = max(scrollView.zoomScale, CGFloat.leastNormalMagnitude)
    let centerContentX = scrollView.contentOffset.x + scrollView.bounds.width / 2
    let centerContentZ = scrollView.contentOffset.y + scrollView.bounds.height / 2
    let pointX = centerContentX / rawZoom
    let pointZ = centerContentZ / rawZoom
    let localBlockX = Double(pointX / imageView.bounds.width) * sideBlocks
    let localBlockZ = Double(pointZ / imageView.bounds.height) * sideBlocks
    return MapViewportAnchor(
      blockX: Double(renderedStartBlockX) + localBlockX,
      blockZ: Double(renderedStartBlockZ) + localBlockZ,
      zoomScale: effectiveZoomScale(forRawScale: rawZoom)
    )
  }

  private func chunkCenter(for anchor: MapViewportAnchor) -> (Int32, Int32) {
    (chunkCoordinate(from: anchor.blockX), chunkCoordinate(from: anchor.blockZ))
  }

  private func chunkCoordinate(from block: Double) -> Int32 {
    let value = floor(block / 16.0)
    if value <= Double(Int32.min) { return Int32.min }
    if value >= Double(Int32.max) { return Int32.max }
    return Int32(value)
  }

  private func applyViewport(anchor: MapViewportAnchor?) {
    isApplyingViewport = true
    view.layoutIfNeeded()
    let requestedEffectiveZoom = anchor?.zoomScale ?? 1
    let requestedRawZoom = rawZoomScale(forEffectiveScale: requestedEffectiveZoom)
    expandZoomRangeIfNeeded(for: requestedRawZoom)
    let targetZoom = pixelAlignedZoomScale(requestedRawZoom)
    scrollView.setZoomScale(targetZoom, animated: false)
    view.layoutIfNeeded()

    let sideBlocks = Double(renderedSideChunks * 16)
    let targetX = anchor?.blockX ?? Double(MapCoordinate.blockOrigin(ofChunk: lastCenterX)) + 8
    let targetZ = anchor?.blockZ ?? Double(MapCoordinate.blockOrigin(ofChunk: lastCenterZ)) + 8
    let localX = (targetX - Double(renderedStartBlockX)) / sideBlocks
    let localZ = (targetZ - Double(renderedStartBlockZ)) / sideBlocks
    let contentX = CGFloat(localX) * imageView.bounds.width * targetZoom
    let contentZ = CGFloat(localZ) * imageView.bounds.height * targetZoom
    let minOffsetX = -scrollView.contentInset.left
    let minOffsetZ = -scrollView.contentInset.top
    let maxOffsetX = max(
      minOffsetX,
      scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
    let maxOffsetZ = max(
      minOffsetZ,
      scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
    let offset = CGPoint(
      x: min(maxOffsetX, max(minOffsetX, contentX - scrollView.bounds.width / 2)),
      y: min(maxOffsetZ, max(minOffsetZ, contentZ - scrollView.bounds.height / 2))
    )
    scrollView.setContentOffset(offset, animated: false)
    alignContentOffsetToDevicePixels()
    DispatchQueue.main.async { [weak self] in
      self?.isApplyingViewport = false
      self?.updateObjectOverlay()
    }
  }

  private func updateCoordinateFields(centerX: Int32, centerZ: Int32, anchor: MapViewportAnchor?) {
    yField.text = String(sliceCenterY)
    if currentSliceAxis != .y {
      if coordinateModeControl.selectedSegmentIndex == 0 {
        xField.text = String(MapCoordinate.chunk(fromBlock: sliceCenterBlockX))
        zField.text = String(MapCoordinate.chunk(fromBlock: sliceCenterBlockZ))
      } else {
        xField.text = String(sliceCenterBlockX)
        zField.text = String(sliceCenterBlockZ)
      }
      return
    }
    if coordinateModeControl.selectedSegmentIndex == 0 {
      xField.text = String(centerX)
      zField.text = String(centerZ)
    } else if let anchor = anchor {
      xField.text = String(Int64(floor(anchor.blockX)))
      zField.text = String(Int64(floor(anchor.blockZ)))
    } else {
      xField.text = String(MapCoordinate.blockOrigin(ofChunk: centerX) + 8)
      zField.text = String(MapCoordinate.blockOrigin(ofChunk: centerZ) + 8)
    }
  }

  private var isMapInteractionActive: Bool {
    scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating || isZooming
      || selectionMapPanOrigin != nil || selectionPinchOriginZoom != nil
  }

  private func cancelInFlightRenderForUserInteraction() {
    panDebounceWorkItem?.cancel()
    panDebounceWorkItem = nil
    guard let token = activeRenderToken else { return }
    token.cancel()
    // Detach immediately so an old render can never apply its saved anchor
    // after the user has started a new pan/pinch. This was the main source of
    // the self-propelling map-center loop seen on iPhone.
    activeRenderToken = nil
    isRendering = false
    shareButton.isEnabled = lastRenderedImage != nil
  }

  private func scheduleAutoRender(immediate: Bool = false, zoomDriven: Bool = false) {
    guard (autoRenderSwitch.isOn || zoomDriven), lastRenderedImage != nil else { return }
    panDebounceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self = self, (self.autoRenderSwitch.isOn || zoomDriven),
        self.lastRenderedImage != nil
      else { return }
      // UIScrollView can still report isTracking for one or two run-loop turns
      // after scrollViewDidEndZooming/DidEndDragging on iPhone. Do not drop the
      // refresh request in that window: retry after the gesture is truly idle.
      if self.isApplyingViewport || self.isMapInteractionActive {
        self.scheduleAutoRender(immediate: true, zoomDriven: zoomDriven)
        return
      }
      guard !self.isRendering else { return }
      self.autoRenderAtViewportCenter(zoomDrivenOnly: zoomDriven)
    }
    panDebounceWorkItem = item
    DispatchQueue.main.asyncAfter(
      deadline: .now() + (immediate ? 0.06 : 0.28),
      execute: item
    )
  }

  private func currentViewportRenderRequest() -> MapViewportRenderRequest? {
    guard lastRenderedImage != nil, imageView.bounds.width > 0, imageView.bounds.height > 0,
      scrollView.bounds.width > 0, scrollView.bounds.height > 0
    else { return nil }

    let rawZoom = max(scrollView.zoomScale, CGFloat.leastNormalMagnitude)
    guard rawZoom.isFinite, rawZoom > 0 else { return nil }
    let sideBlocks = Double(renderedSideChunks * 16)
    let imageWidth = Double(imageView.bounds.width)
    let imageHeight = Double(imageView.bounds.height)
    guard imageWidth > 0, imageHeight > 0 else { return nil }

    // Convert the entire visible rectangle, including any part currently in
    // the virtual pan margin, back into world block coordinates. This is more
    // reliable than deriving the dynamic radius from zoom alone and guarantees
    // that a zoom-out requests enough chunks to fill the whole viewport.
    let minPointX = Double(scrollView.contentOffset.x / rawZoom)
    let maxPointX = Double((scrollView.contentOffset.x + scrollView.bounds.width) / rawZoom)
    let minPointZ = Double(scrollView.contentOffset.y / rawZoom)
    let maxPointZ = Double((scrollView.contentOffset.y + scrollView.bounds.height) / rawZoom)

    let worldX0 = Double(renderedStartBlockX) + minPointX / imageWidth * sideBlocks
    let worldX1 = Double(renderedStartBlockX) + maxPointX / imageWidth * sideBlocks
    let worldZ0 = Double(renderedStartBlockZ) + minPointZ / imageHeight * sideBlocks
    let worldZ1 = Double(renderedStartBlockZ) + maxPointZ / imageHeight * sideBlocks
    guard worldX0.isFinite, worldX1.isFinite, worldZ0.isFinite, worldZ1.isFinite else {
      return nil
    }

    let minimumBlockX = min(worldX0, worldX1)
    let maximumBlockX = max(worldX0, worldX1)
    let minimumBlockZ = min(worldZ0, worldZ1)
    let maximumBlockZ = max(worldZ0, worldZ1)
    let centerBlockX = (minimumBlockX + maximumBlockX) / 2
    let centerBlockZ = (minimumBlockZ + maximumBlockZ) / 2
    let centerX = chunkCoordinate(from: centerBlockX)
    let centerZ = chunkCoordinate(from: centerBlockZ)

    func chunk64(_ block: Double) -> Int64 {
      let value = floor(block / 16.0)
      if value <= Double(Int32.min) { return Int64(Int32.min) }
      if value >= Double(Int32.max) { return Int64(Int32.max) }
      return Int64(value)
    }

    // maxBlock is an exclusive viewport edge. nextDown avoids counting a new
    // chunk when the right/bottom edge lands exactly on a chunk boundary.
    let maxBlockXForChunk = maximumBlockX > minimumBlockX ? maximumBlockX.nextDown : maximumBlockX
    let maxBlockZForChunk = maximumBlockZ > minimumBlockZ ? maximumBlockZ.nextDown : maximumBlockZ
    let visibleMinimumChunkX = chunk64(minimumBlockX)
    let visibleMaximumChunkX = chunk64(maxBlockXForChunk)
    let visibleMinimumChunkZ = chunk64(minimumBlockZ)
    let visibleMaximumChunkZ = chunk64(maxBlockZForChunk)
    let border = Int64(dynamicPreloadBorderChunks)
    let lowerLimit = Int64(Int32.min)
    let upperLimit = Int64(Int32.max)
    let requiredMinimumChunkX = max(lowerLimit, visibleMinimumChunkX - border)
    let requiredMaximumChunkX = min(upperLimit, visibleMaximumChunkX + border)
    let requiredMinimumChunkZ = max(lowerLimit, visibleMinimumChunkZ - border)
    let requiredMaximumChunkZ = min(upperLimit, visibleMaximumChunkZ + border)

    let centerX64 = Int64(centerX)
    let centerZ64 = Int64(centerZ)
    let leftNeedX = max(Int64(0), centerX64 - requiredMinimumChunkX)
    let rightNeedX = max(Int64(0), requiredMaximumChunkX - centerX64)
    let leftNeedZ = max(Int64(0), centerZ64 - requiredMinimumChunkZ)
    let rightNeedZ = max(Int64(0), requiredMaximumChunkZ - centerZ64)
    let sideCandidates: [Int64] = [
      Int64(minimumDynamicSideChunks),
      2 * leftNeedX + 1,
      2 * rightNeedX,
      2 * leftNeedZ + 1,
      2 * rightNeedZ,
    ]
    var requiredSide64 = sideCandidates.max() ?? Int64(minimumDynamicSideChunks)
    requiredSide64 = min(requiredSide64, Int64(maximumBedrockChunkSpan))

    return MapViewportRenderRequest(
      centerX: centerX,
      centerZ: centerZ,
      anchor: MapViewportAnchor(
        blockX: centerBlockX,
        blockZ: centerBlockZ,
        zoomScale: effectiveZoomScale(forRawScale: rawZoom)
      ),
      sideChunks: Int(requiredSide64),
      requiredMinimumChunkX: requiredMinimumChunkX,
      requiredMaximumChunkX: requiredMaximumChunkX,
      requiredMinimumChunkZ: requiredMinimumChunkZ,
      requiredMaximumChunkZ: requiredMaximumChunkZ
    )
  }

  private func renderedRegionContains(_ request: MapViewportRenderRequest) -> Bool {
    let minimumX = Int64(lastCenterX) - Int64(renderedLeftChunks)
    let maximumX = Int64(lastCenterX) + Int64(renderedRightChunks)
    let minimumZ = Int64(lastCenterZ) - Int64(renderedLeftChunks)
    let maximumZ = Int64(lastCenterZ) + Int64(renderedRightChunks)
    return request.requiredMinimumChunkX >= minimumX
      && request.requiredMaximumChunkX <= maximumX
      && request.requiredMinimumChunkZ >= minimumZ
      && request.requiredMaximumChunkZ <= maximumZ
  }

  private func autoRenderAtViewportCenter(zoomDrivenOnly: Bool = false) {
    guard !isApplyingViewport, !isMapInteractionActive, !isRendering else { return }
    if currentSliceAxis != .y {
      autoRenderCrossSectionAtViewportCenter(zoomDrivenOnly: zoomDrivenOnly)
      return
    }
    guard let request = currentViewportRenderRequest() else { return }

    let containsViewport = renderedRegionContains(request)
    let needsExpansion = request.sideChunks > renderedSideChunks
    // When the user zooms back in after a very wide sampled render, shrink
    // only after a 2× hysteresis threshold so high-detail chunks return
    // without oscillating between adjacent sizes on every tiny pinch.
    let needsDetailRefinement = request.sideChunks * 2 < renderedSideChunks
    if zoomDrivenOnly {
      guard needsExpansion || needsDetailRefinement else { return }
    } else {
      guard autoRenderSwitch.isOn,
        !containsViewport || needsExpansion || needsDetailRefinement
      else { return }
    }

    let targetSideChunks: Int
    if needsExpansion || needsDetailRefinement {
      targetSideChunks = request.sideChunks
    } else {
      // Pure panning keeps the current window size and only recenters when the
      // visible area reaches the preload boundary. This removes the old
      // one-chunk-at-a-time render chase that could amplify tiny Z drift.
      targetSideChunks = renderedSideChunks
    }

    updateCoordinateFields(
      centerX: request.centerX,
      centerZ: request.centerZ,
      anchor: request.anchor
    )
    let reason: String
    if needsExpansion {
      reason = "缩放扩展"
    } else if needsDetailRefinement {
      reason = "缩放细化"
    } else {
      reason = "移动续载"
    }
    render(
      centerX: request.centerX,
      centerZ: request.centerZ,
      anchor: request.anchor,
      reason: reason,
      showOverlay: false,
      sideChunksOverride: targetSideChunks
    )
  }


  private func autoRenderCrossSectionAtViewportCenter(zoomDrivenOnly: Bool) {
    guard currentSliceAxis != .y,
      lastRenderedImage != nil,
      imageView.bounds.width > 0,
      imageView.bounds.height > 0,
      scrollView.bounds.width > 0,
      scrollView.bounds.height > 0
    else { return }

    let rawZoom = max(scrollView.zoomScale, CGFloat.leastNormalMagnitude)
    guard rawZoom.isFinite, rawZoom > 0 else { return }
    let sideBlocks = Double(renderedSideChunks * 16)
    let imageWidth = Double(imageView.bounds.width)
    let imageHeight = Double(imageView.bounds.height)
    guard sideBlocks > 0, imageWidth > 0, imageHeight > 0 else { return }

    let minPointH = Double(scrollView.contentOffset.x / rawZoom)
    let maxPointH = Double((scrollView.contentOffset.x + scrollView.bounds.width) / rawZoom)
    let minPointV = Double(scrollView.contentOffset.y / rawZoom)
    let maxPointV = Double((scrollView.contentOffset.y + scrollView.bounds.height) / rawZoom)

    let horizontal0 = Double(renderedCrossHorizontalStart) + minPointH / imageWidth * sideBlocks
    let horizontal1 = Double(renderedCrossHorizontalStart) + maxPointH / imageWidth * sideBlocks
    let y0 = Double(renderedCrossMaximumY) - minPointV / imageHeight * sideBlocks
    let y1 = Double(renderedCrossMaximumY) - maxPointV / imageHeight * sideBlocks
    guard horizontal0.isFinite, horizontal1.isFinite, y0.isFinite, y1.isFinite else { return }

    let visibleMinHorizontal = min(horizontal0, horizontal1)
    let visibleMaxHorizontal = max(horizontal0, horizontal1)
    let visibleMinY = min(y0, y1)
    let visibleMaxY = max(y0, y1)
    let viewportHorizontalCenter = (visibleMinHorizontal + visibleMaxHorizontal) / 2
    let viewportYCenter = (visibleMinY + visibleMaxY) / 2

    let requestedSide = max(
      minimumDynamicSideChunks,
      dynamicRenderSideChunks(forZoomScale: effectiveZoomScale(forRawScale: rawZoom))
    )
    let needsExpansion = requestedSide > renderedSideChunks
    let needsDetailRefinement = requestedSide * 2 < renderedSideChunks

    // Reload before the viewport reaches the current image edge. This mirrors
    // the top-down map preload border, but in a slice the two movable axes are
    // horizontal-world-coordinate and Y rather than X/Z.
    let currentMinHorizontal = Double(renderedCrossHorizontalStart)
    let currentMaxHorizontal = currentMinHorizontal + sideBlocks
    let currentMinY = Double(renderedCrossMinimumY)
    let currentMaxYExclusive = Double(renderedCrossMaximumY) + 1
    let preload = min(sideBlocks * 0.25, Double(dynamicPreloadBorderChunks * 16))
    let needsRecentering =
      visibleMinHorizontal < currentMinHorizontal + preload
      || visibleMaxHorizontal > currentMaxHorizontal - preload
      || visibleMinY < currentMinY + preload
      || visibleMaxY > currentMaxYExclusive - preload

    if zoomDrivenOnly {
      guard needsExpansion || needsDetailRefinement else { return }
    } else {
      guard autoRenderSwitch.isOn,
        needsRecentering || needsExpansion || needsDetailRefinement
      else { return }
    }

    func clampedInt64(_ value: Double) -> Int64 {
      if value <= Double(Int64.min) { return Int64.min }
      if value >= Double(Int64.max) { return Int64.max }
      return Int64(floor(value))
    }

    let horizontalCenter = clampedInt64(viewportHorizontalCenter)
    sliceCenterY = Int32(clamping: clampedInt64(viewportYCenter))
    switch currentSliceAxis {
    case .x:
      sliceCenterBlockZ = horizontalCenter
    case .z:
      sliceCenterBlockX = horizontalCenter
    case .y:
      return
    }
    let centerX = MapCoordinate.chunk(fromBlock: sliceCenterBlockX)
    let centerZ = MapCoordinate.chunk(fromBlock: sliceCenterBlockZ)
    updateCoordinateFields(centerX: centerX, centerZ: centerZ, anchor: nil)

    let targetSideChunks = (needsExpansion || needsDetailRefinement)
      ? requestedSide : renderedSideChunks
    let reason: String
    if needsExpansion {
      reason = "剖面缩放扩展"
    } else if needsDetailRefinement {
      reason = "剖面缩放细化"
    } else {
      reason = "剖面移动续载"
    }
    render(
      centerX: centerX,
      centerZ: centerZ,
      anchor: nil,
      reason: reason,
      showOverlay: false,
      sideChunksOverride: targetSideChunks
    )
  }

  private func mapPosition(at point: CGPoint) -> (
    localX: Int, localZ: Int, absoluteX: Int64, absoluteZ: Int64
  )? {
    guard currentSliceAxis == .y else { return nil }
    let side = renderedSideChunks * 16
    guard lastRenderedImage != nil, imageView.bounds.width > 0, imageView.bounds.height > 0 else {
      return nil
    }
    let localX = min(side - 1, max(0, Int(point.x / imageView.bounds.width * CGFloat(side))))
    let localZ = min(side - 1, max(0, Int(point.y / imageView.bounds.height * CGFloat(side))))
    return (
      localX,
      localZ,
      renderedStartBlockX + Int64(localX),
      renderedStartBlockZ + Int64(localZ)
    )
  }

  private func crossSectionWorldObjectHit(at imagePoint: CGPoint) -> MapWorldObjectHit? {
    guard currentSliceAxis != .y, lastRenderedImage != nil,
      imageView.bounds.width > 0, imageView.bounds.height > 0
    else { return nil }
    let sideBlocks = CGFloat(renderedSideChunks * 16)
    guard sideBlocks > 0 else { return nil }
    let tapPoint = imageView.convert(imagePoint, to: objectOverlayView)
    var best: (hit: MapWorldObjectHit, distance: CGFloat)?
    for hit in lastWorldObjectHits where hit.isNormallyVisible {
      let projectedInImage = CGPoint(
        x: hit.localX / sideBlocks * imageView.bounds.width,
        y: hit.localZ / sideBlocks * imageView.bounds.height
      )
      let projected = imageView.convert(projectedInImage, to: objectOverlayView)
      let dx = projected.x - tapPoint.x
      let dy = projected.y - tapPoint.y
      let distance = sqrt(dx * dx + dy * dy)
      if best == nil || distance < best!.distance { best = (hit, distance) }
    }
    guard let best = best, best.distance <= 18 else { return nil }
    return best.hit
  }

  private func crossSectionPosition(at point: CGPoint) -> (x: Int64, y: Int32, z: Int64)? {
    guard currentSliceAxis != .y, lastRenderedImage != nil,
      imageView.bounds.width > 0, imageView.bounds.height > 0
    else { return nil }
    let side = renderedSideChunks * 16
    let localHorizontal = min(
      side - 1, max(0, Int(point.x / imageView.bounds.width * CGFloat(side))))
    let localVertical = min(
      side - 1, max(0, Int(point.y / imageView.bounds.height * CGFloat(side))))
    let horizontal = renderedCrossHorizontalStart + Int64(localHorizontal)
    let worldY = renderedCrossMaximumY - Int64(localVertical)
    switch currentSliceAxis {
    case .x:
      return (sliceCenterBlockX, Int32(clamping: worldY), horizontal)
    case .z:
      return (horizontal, Int32(clamping: worldY), sliceCenterBlockZ)
    case .y:
      return nil
    }
  }

  private func crossSectionHardcodedSpawnerHit(
    at position: (x: Int64, y: Int32, z: Int64)
  ) -> MapHardcodedSpawnerHit? {
    guard showHardcodedSpawners else { return nil }
    let y = Int64(position.y)
    return lastHardcodedSpawnerHits.filter { hit in
      position.x >= Int64(hit.area.minimumX) && position.x <= Int64(hit.area.maximumX)
        && y >= Int64(hit.area.minimumY) && y <= Int64(hit.area.maximumY)
        && position.z >= Int64(hit.area.minimumZ) && position.z <= Int64(hit.area.maximumZ)
    }.min { lhs, rhs in
      let lhsVolume = max(Int64(1), Int64(lhs.area.maximumX) - Int64(lhs.area.minimumX) + 1)
        * max(Int64(1), Int64(lhs.area.maximumY) - Int64(lhs.area.minimumY) + 1)
        * max(Int64(1), Int64(lhs.area.maximumZ) - Int64(lhs.area.minimumZ) + 1)
      let rhsVolume = max(Int64(1), Int64(rhs.area.maximumX) - Int64(rhs.area.minimumX) + 1)
        * max(Int64(1), Int64(rhs.area.maximumY) - Int64(rhs.area.minimumY) + 1)
        * max(Int64(1), Int64(rhs.area.maximumZ) - Int64(rhs.area.minimumZ) + 1)
      return lhsVolume < rhsVolume
    }
  }

  private func showBlockAxisLine(
    at position: (x: Int64, y: Int32, z: Int64)
  ) {
    let axis = currentSliceAxis
    guard axis == .x || axis == .z else { return }
    let centerCoordinate = axis == .x ? sliceCenterBlockX : sliceCenterBlockZ
    // Mineral view reads exactly the same negative-axis slab as the X/Z xray
    // projection: current X/Z through current X/Z-128 (both endpoints). Other
    // block modes keep the existing ±128 line so users can manually inspect
    // either side of the selected plane.
    let minimumCoordinate = centerCoordinate - crossSectionSelectionHalfRange
    let maximumCoordinate = currentMode == .xray
      ? centerCoordinate
      : centerCoordinate + crossSectionSelectionHalfRange
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let overlay = showBusy("读取 \(axis.displayName) 轴方块…")
    renderQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let result = try self.rendererForCurrentSession().blockAxisLine(
          axis: axis,
          fixedY: position.y,
          fixedX: position.x,
          fixedZ: position.z,
          minimumCoordinate: minimumCoordinate,
          maximumCoordinate: maximumCoordinate,
          dimension: dimension
        )
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          let initial = axis == .x ? position.x : position.z
          let picker = BlockAxisPickerViewController(
            result: result,
            initialCoordinate: initial,
            automaticSelectionMaximumCoordinate: centerCoordinate,
            preferHighlightedOre: self.currentMode == .xray
          ) { [weak self] block in
            self?.selectBlock(block)
          }
          let navigation = UINavigationController(rootViewController: picker)
          navigation.modalPresentationStyle = .formSheet
          self.present(navigation, animated: true)
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "无法读取 \(axis.displayName) 轴方块")
        }
      }
    }
  }

  @objc private func toggleSelectionMode() {
    guard currentSliceAxis == .y else {
      statusLabel.text = "X/Z 剖面模式不支持地图区域框选。"
      return
    }
    setSelectionMode(!isSelectionMode)
  }

  private func setSelectionMode(_ enabled: Bool) {
    if enabled { chunkSelectionSwitch.setOn(false, animated: true) }
    isSelectionMode = enabled
    selectionButtonView.tintColor = enabled ? .systemBlue : view.tintColor
    scrollView.panGestureRecognizer.isEnabled = true
    selectionOverlayView.isHidden = !enabled
    if !enabled {
      selectionStartPoint = nil
      selectionEdgeDragOrigin = nil
      selectionMapPanOrigin = nil
      selectionPinchOriginZoom = nil
      selectionPinchAnchorContent = nil
      selectedRegion = nil
      selectionOverlayView.clear()
    } else if let region = selectedRegion {
      updateSelectionOverlay(for: region)
    } else {
      selectionOverlayView.setBackgroundPassThrough(false)
    }
    updateSelectionGestureAvailability()
    updateSelectionButtonBlinking()
    if isViewLoaded {
      statusLabel.text =
        enabled
        ? "框选模式：单指拖出选区；两指可移动或缩放地图。选区建立后禁止重新框选，可拖动四边或输入坐标调整。"
        : "已退出框选模式。"
    }
  }

  private func updateSelectionGestureAvailability() {
    let canDraw = isSelectionMode && selectedRegion == nil
    selectionPanGesture.isEnabled = canDraw
    // Before the selection exists the overlay owns the touches, so two-finger
    // gestures explicitly move/zoom the underlying map. After selection the
    // overlay passes empty-space touches through to UIScrollView natively.
    selectionMapPanGesture.isEnabled = canDraw
    selectionMapPinchGesture.isEnabled = canDraw
    selectionOverlayView.setBackgroundPassThrough(isSelectionMode && selectedRegion != nil)
  }

  private func updateSelectionButtonBlinking() {
    let key = "selection-mode-blink"
    if isSelectionMode {
      guard selectionButtonView.layer.animation(forKey: key) == nil else { return }
      let animation = CABasicAnimation(keyPath: "opacity")
      animation.fromValue = 1.0
      animation.toValue = 0.20
      animation.duration = 0.55
      animation.autoreverses = true
      animation.repeatCount = .infinity
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      selectionButtonView.layer.add(animation, forKey: key)
    } else {
      selectionButtonView.layer.removeAnimation(forKey: key)
      selectionButtonView.alpha = 1
    }
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
    -> Bool
  {
    if gestureRecognizer === selectionPanGesture || gestureRecognizer === selectionMapPanGesture
      || gestureRecognizer === selectionMapPinchGesture,
      selectionOverlayView.containsInteractiveControl(touch.view)
    {
      return false
    }
    return true
  }

  @objc private func handleSelectionPan(_ recognizer: UIPanGestureRecognizer) {
    guard isSelectionMode, selectedRegion == nil else { return }
    let point = recognizer.location(in: selectionOverlayView)
    switch recognizer.state {
    case .began:
      selectionStartPoint = point
      selectionOverlayView.setBackgroundPassThrough(false)
      selectionOverlayView.show(rect: CGRect(x: point.x, y: point.y, width: 1, height: 1))
    case .changed:
      guard let start = selectionStartPoint else { return }
      selectionOverlayView.show(
        rect: CGRect(
          x: min(start.x, point.x),
          y: min(start.y, point.y),
          width: abs(point.x - start.x),
          height: abs(point.y - start.y)
        ))
    case .ended:
      guard let start = selectionStartPoint else { return }
      selectionStartPoint = nil
      completeSelection(from: start, to: point)
    case .cancelled, .failed:
      selectionStartPoint = nil
      if selectedRegion == nil { selectionOverlayView.clear() }
    default:
      break
    }
  }

  @objc private func handleSelectionMapPan(_ recognizer: UIPanGestureRecognizer) {
    guard isSelectionMode, selectedRegion == nil else { return }
    switch recognizer.state {
    case .began:
      cancelInFlightRenderForUserInteraction()
      selectionMapPanOrigin = scrollView.contentOffset
    case .changed:
      guard let origin = selectionMapPanOrigin else { return }
      let translation = recognizer.translation(in: selectionOverlayView)
      let proposed = CGPoint(x: origin.x - translation.x, y: origin.y - translation.y)
      scrollView.setContentOffset(clampedContentOffset(proposed), animated: false)
      updateObjectOverlay()
    case .ended, .cancelled, .failed:
      selectionMapPanOrigin = nil
      alignContentOffsetToDevicePixels()
      updateObjectOverlay()
      scheduleAutoRender(immediate: true)
      saveMapState()
    default:
      break
    }
  }

  @objc private func handleSelectionMapPinch(_ recognizer: UIPinchGestureRecognizer) {
    guard isSelectionMode, selectedRegion == nil else { return }
    let location = recognizer.location(in: selectionOverlayView)
    switch recognizer.state {
    case .began:
      cancelInFlightRenderForUserInteraction()
      prepareZoomRangeForUserGesture()
      let zoom = max(scrollView.zoomScale, 0.0001)
      selectionPinchOriginZoom = zoom
      selectionPinchAnchorContent = CGPoint(
        x: (scrollView.contentOffset.x + location.x) / zoom,
        y: (scrollView.contentOffset.y + location.y) / zoom
      )
      isZooming = true
      panDebounceWorkItem?.cancel()
      showZoomHUD()
    case .changed:
      guard let originZoom = selectionPinchOriginZoom,
        let anchor = selectionPinchAnchorContent
      else { return }
      let proposedScale = originZoom * recognizer.scale
      let target = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale, proposedScale))
      isApplyingViewport = true
      scrollView.setZoomScale(target, animated: false)
      let proposed = CGPoint(
        x: anchor.x * target - location.x,
        y: anchor.y * target - location.y
      )
      scrollView.setContentOffset(clampedContentOffset(proposed), animated: false)
      isApplyingViewport = false
      updateObjectOverlay()
      showZoomHUD()
    case .ended, .cancelled, .failed:
      let aligned = pixelAlignedZoomScale(scrollView.zoomScale)
      if abs(aligned - scrollView.zoomScale) > 0.0001 {
        isApplyingViewport = true
        scrollView.setZoomScale(aligned, animated: false)
        isApplyingViewport = false
      }
      selectionPinchOriginZoom = nil
      selectionPinchAnchorContent = nil
      alignContentOffsetToDevicePixels()
      updateObjectOverlay()
      isZooming = false
      showZoomHUD(autoHide: true)
      saveMapState()
      refreshForZoomDrivenRadiusIfNeeded()
    default:
      break
    }
  }

  private func clampedContentOffset(_ proposed: CGPoint) -> CGPoint {
    let minimumX = -scrollView.contentInset.left
    let minimumY = -scrollView.contentInset.top
    let maximumX = max(
      minimumX,
      scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
    let maximumY = max(
      minimumY,
      scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
    return CGPoint(
      x: min(maximumX, max(minimumX, proposed.x)),
      y: min(maximumY, max(minimumY, proposed.y))
    )
  }

  private func completeSelection(from start: CGPoint, to end: CGPoint) {
    let rawRect = CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )
    guard rawRect.width >= 8, rawRect.height >= 8 else {
      selectedRegion = nil
      selectionOverlayView.clear()
      statusLabel.text = "框选区域过小，请重新拖动。"
      return
    }
    guard let region = region(fromOverlayRect: rawRect) else {
      selectedRegion = nil
      selectionOverlayView.clear()
      statusLabel.text = "框选区域没有覆盖地图。"
      return
    }
    selectedRegion = region
    updateSelectionOverlay(for: region)
    updateSelectionGestureAvailability()
    statusLabel.text =
      "已选择 \(region.coordinateText)，共 \(region.width)×\(region.depth) 方块；已禁止重新框选，可拖动四条边、输入坐标或移动缩放地图。"
    presentSelectionActions()
  }

  private func region(fromOverlayRect rawRect: CGRect) -> BedrockMapRegion? {
    let imageFrame = imageView.convert(imageView.bounds, to: selectionOverlayView)
    let visibleRect = rawRect.standardized.intersection(imageFrame)
    guard !visibleRect.isNull, visibleRect.width > 0, visibleRect.height > 0,
      imageView.bounds.width > 0, imageView.bounds.height > 0
    else { return nil }
    let first = selectionOverlayView.convert(
      CGPoint(x: visibleRect.minX, y: visibleRect.minY), to: imageView)
    let second = selectionOverlayView.convert(
      CGPoint(x: visibleRect.maxX, y: visibleRect.maxY), to: imageView)
    let side = CGFloat(renderedSideChunks * 16)
    let minLocalX = max(0, min(side, min(first.x, second.x) / imageView.bounds.width * side))
    let maxLocalX = max(0, min(side, max(first.x, second.x) / imageView.bounds.width * side))
    let minLocalZ = max(0, min(side, min(first.y, second.y) / imageView.bounds.height * side))
    let maxLocalZ = max(0, min(side, max(first.y, second.y) / imageView.bounds.height * side))
    let startBlockX = renderedStartBlockX
    let startBlockZ = renderedStartBlockZ
    let minX = startBlockX + Int64(floor(minLocalX))
    let maxX = startBlockX + Int64(max(0, Int(ceil(maxLocalX)) - 1))
    let minZ = startBlockZ + Int64(floor(minLocalZ))
    let maxZ = startBlockZ + Int64(max(0, Int(ceil(maxLocalZ)) - 1))
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    return BedrockMapRegion(
      minimumX: minX, minimumZ: minZ, maximumX: maxX, maximumZ: maxZ, dimension: dimension)
  }

  private func overlayRect(for region: BedrockMapRegion) -> CGRect? {
    guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return nil }
    let side = CGFloat(renderedSideChunks * 16)
    let startBlockX = renderedStartBlockX
    let startBlockZ = renderedStartBlockZ
    let x0 = CGFloat(region.minimumX - startBlockX) / side * imageView.bounds.width
    let x1 = CGFloat(region.maximumX - startBlockX + 1) / side * imageView.bounds.width
    let z0 = CGFloat(region.minimumZ - startBlockZ) / side * imageView.bounds.height
    let z1 = CGFloat(region.maximumZ - startBlockZ + 1) / side * imageView.bounds.height
    let first = imageView.convert(CGPoint(x: x0, y: z0), to: selectionOverlayView)
    let second = imageView.convert(CGPoint(x: x1, y: z1), to: selectionOverlayView)
    let rect = CGRect(
      x: min(first.x, second.x),
      y: min(first.y, second.y),
      width: abs(second.x - first.x),
      height: abs(second.y - first.y)
    ).intersection(selectionOverlayView.bounds)
    return rect.isNull || rect.width <= 0 || rect.height <= 0 ? nil : rect
  }

  private func updateSelectionOverlay(for region: BedrockMapRegion) {
    guard isSelectionMode else { return }
    if let rect = overlayRect(for: region) {
      selectionOverlayView.show(rect: rect, region: region)
      selectionOverlayView.setBackgroundPassThrough(selectedRegion != nil)
    } else {
      // Preserve the logical selection while it is temporarily outside
      // the visible viewport; moving back will show it again.
      selectionOverlayView.clear()
      selectionOverlayView.setBackgroundPassThrough(selectedRegion != nil)
    }
  }

  private var renderedMapRegion: BedrockMapRegion {
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let sideBlocks = Int64(renderedSideChunks) * 16
    return BedrockMapRegion(
      minimumX: renderedStartBlockX,
      minimumZ: renderedStartBlockZ,
      maximumX: renderedStartBlockX + sideBlocks - 1,
      maximumZ: renderedStartBlockZ + sideBlocks - 1,
      dimension: dimension
    )
  }

  private func setSelectionCoordinates(x0: Int64, z0: Int64, x1: Int64, z1: Int64) {
    guard isSelectionMode else { return }
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let region = BedrockMapRegion(
      minimumX: x0, minimumZ: z0, maximumX: x1, maximumZ: z1, dimension: dimension)
    let mapBounds = renderedMapRegion
    guard region.minimumX >= mapBounds.minimumX, region.maximumX <= mapBounds.maximumX,
      region.minimumZ >= mapBounds.minimumZ, region.maximumZ <= mapBounds.maximumZ
    else {
      if let current = selectedRegion { selectionOverlayView.updateCoordinateFields(current) }
      statusLabel.text = "输入范围超出当前已渲染地图（\(mapBounds.coordinateText)），请先移动或扩大地图后再框选。"
      return
    }
    selectedRegion = region
    updateSelectionOverlay(for: region)
    updateSelectionGestureAvailability()
    statusLabel.text = "已输入选择范围：\(region.coordinateText)。"
  }

  private func alignSelectionToChunkBounds() {
    guard isSelectionMode, let current = selectedRegion else { return }
    let aligned = current.expandedToChunkBounds
    selectedRegion = aligned
    selectionEdgeDragOrigin = nil
    updateSelectionOverlay(for: aligned)
    updateSelectionGestureAvailability()
    statusLabel.text =
      "已向外对齐区块边界：\(aligned.coordinateText)，覆盖 \(aligned.chunkCount) 个完整区块。"
  }

  private func adjustSelectionEdge(
    _ edge: MapSelectionEdge, translation: CGPoint, state: UIGestureRecognizer.State
  ) {
    guard isSelectionMode, let current = selectedRegion else { return }
    if state == .began {
      selectionEdgeDragOrigin = current
      return
    }
    guard state == .changed || state == .ended, var region = selectionEdgeDragOrigin else {
      if state == .cancelled || state == .failed { selectionEdgeDragOrigin = nil }
      return
    }
    let imageFrame = imageView.convert(imageView.bounds, to: selectionOverlayView)
    let side = CGFloat(renderedSideChunks * 16)
    guard imageFrame.width > 0, imageFrame.height > 0 else { return }
    let deltaX = Int64((translation.x / imageFrame.width * side).rounded())
    let deltaZ = Int64((translation.y / imageFrame.height * side).rounded())
    let mapBounds = renderedMapRegion
    switch edge {
    case .left:
      region.minimumX = max(mapBounds.minimumX, min(region.maximumX, region.minimumX + deltaX))
    case .right:
      region.maximumX = min(mapBounds.maximumX, max(region.minimumX, region.maximumX + deltaX))
    case .top:
      region.minimumZ = max(mapBounds.minimumZ, min(region.maximumZ, region.minimumZ + deltaZ))
    case .bottom:
      region.maximumZ = min(mapBounds.maximumZ, max(region.minimumZ, region.maximumZ + deltaZ))
    }
    selectedRegion = region
    updateSelectionOverlay(for: region)
    statusLabel.text = "选择范围：\(region.coordinateText)，大小 \(region.width)×\(region.depth)。"
    if state == .ended { selectionEdgeDragOrigin = nil }
  }

  private func presentSelectionActions() {
    guard isSelectionMode, let region = selectedRegion else { return }
    let aligned = region.expandedToChunkBounds
    var message =
      "\(region.coordinateText)；\(region.width)×\(region.depth) 方块；涉及 \(region.chunkCount) 个区块。"
    if !region.isChunkAligned {
      message += " 清空和重新生成会向外扩展为 \(aligned.coordinateText)。"
    }
    let alert = UIAlertController(title: "框选区域操作", message: message, preferredStyle: .actionSheet)
    alert.addAction(
      UIAlertAction(title: "常加载区域编辑…", style: .default) { [weak self] _ in
        guard let self = self else { return }
        let context = TickingAreaSelectionContext(region: region)
        let controller = TickingAreaListViewController(
          session: self.session,
          initialDimension: region.dimension,
          selectionContext: context
        )
        controller.onSelectChunk = { [weak self] position in
          guard let self = self else { return }
          self.navigationController?.popToViewController(self, animated: true)
          self.selectChunk(position, centerMap: true)
        }
        controller.onMutation = { [weak self] mutationMessage in
          guard let self = self else { return }
          self.navigationItem.prompt = mutationMessage
          self.scheduleAutoRender(immediate: true)
        }
        self.setSelectionMode(false)
        self.navigationController?.pushViewController(controller, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "查看区域内实体…", style: .default) { [weak self] _ in
        self?.scanAndShowSelectionObjects(region: region)
      })
    alert.addAction(
      UIAlertAction(title: "复制区域内容到等大区域…", style: .default) { [weak self] _ in
        guard let self = self else { return }
        let controller = MapRegionCopyViewController(session: self.session, source: region)
        controller.onComplete = { [weak self] message, destination in
          self?.handleChunkMutation(
            message: message,
            preferredPosition: ChunkPosition(
              x: destination.minimumChunkX, z: destination.minimumChunkZ,
              dimension: destination.dimension)
          )
        }
        self.setSelectionMode(false)
        self.navigationController?.pushViewController(controller, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "区域内方块搜索替换…", style: .default) { [weak self] _ in
        guard let self = self else { return }
        let controller = ChunkSearchReplaceViewController(session: self.session, region: region)
        controller.onComplete = { [weak self] message in
          self?.handleChunkMutation(message: message, preferredPosition: nil)
        }
        self.setSelectionMode(false)
        self.navigationController?.pushViewController(controller, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "生物群系修改…", style: .default) { [weak self] _ in
        guard let self = self else { return }
        let controller = MapRegionBiomeViewController(session: self.session, region: region)
        controller.onComplete = { [weak self] message in
          self?.handleChunkMutation(message: message, preferredPosition: nil)
        }
        self.setSelectionMode(false)
        self.navigationController?.pushViewController(controller, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "HardcodedSpawners 修改…", style: .default) { [weak self] _ in
        guard let self = self else { return }
        let controller = MapRegionHardcodedSpawnersViewController(
          session: self.session, region: region)
        controller.onMutation = { [weak self] message in
          self?.handleChunkMutation(message: message, preferredPosition: nil)
        }
        self.setSelectionMode(false)
        self.navigationController?.pushViewController(controller, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "清空区域…", style: .destructive) { [weak self] _ in
        self?.confirmRegionDestructiveAction(region: region, regenerate: false)
      })
    alert.addAction(
      UIAlertAction(title: "重新生成区域…", style: .destructive) { [weak self] _ in
        self?.confirmRegionDestructiveAction(region: region, regenerate: true)
      })
    alert.addAction(UIAlertAction(title: "继续调整范围", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = selectionOverlayView
      popover.sourceRect =
        selectionOverlayView.selectionRect ?? CGRect(x: 8, y: 8, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func scanAndShowSelectionObjects(region: BedrockMapRegion) {
    let overlay = showBusy("扫描区域内实体与方块实体…")
    let centerX = Int32((Int64(region.minimumChunkX) + Int64(region.maximumChunkX)) / 2)
    let centerZ = Int32((Int64(region.minimumChunkZ) + Int64(region.maximumChunkZ)) / 2)
    let radiusX = max(
      abs(Int(region.maximumChunkX - centerX)), abs(Int(centerX - region.minimumChunkX)))
    let radiusZ = max(
      abs(Int(region.maximumChunkZ - centerZ)), abs(Int(centerZ - region.minimumChunkZ)))
    let radius = max(radiusX, radiusZ)
    chunkMenuQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let scanner = BedrockWorldObjectScanner(database: try self.session.database())
        let result = try scanner.scanRegionAdaptive(
          centerX: centerX,
          centerZ: centerZ,
          dimension: region.dimension,
          radius: radius,
          includeEntities: true,
          includeBlockEntities: true,
          maximumObjects: 100_000
        )
        let objects = result.objects.filter { object in
          guard object.dimension == region.dimension, let position = object.position else {
            return false
          }
          return region.contains(x: position.blockX, z: position.blockZ)
        }
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showSelectionObjects(region: region, objects: objects)
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "读取区域实体失败")
        }
      }
    }
  }

  private func showSelectionObjects(region: BedrockMapRegion, objects: [BedrockWorldObject]) {
    let controller = MapSelectionResultsViewController(
      session: session,
      objects: objects,
      boundsText: region.coordinateText,
      onSelect: { [weak self] object in
        guard let self = self else { return }
        self.navigationController?.popToViewController(self, animated: true)
        self.selectWorldObject(object)
      },
      onLocate: { [weak self] object in
        guard let self = self else { return }
        self.navigationController?.popToViewController(self, animated: true)
        self.locate(worldObject: object)
      }
    )
    setSelectionMode(false)
    navigationController?.pushViewController(controller, animated: true)
  }

  private func confirmRegionDestructiveAction(region: BedrockMapRegion, regenerate: Bool) {
    let aligned = region.expandedToChunkBounds
    let actionName = regenerate ? "重新生成" : "清空"
    let explanation =
      regenerate
      ? "将删除扩展范围内全部区块记录和关联 Actor，使 Minecraft 按种子重新生成。"
      : "将删除扩展范围内全部区块记录和关联 Actor，再写入已生成的纯空气区块。"
    let alert = UIAlertController(
      title: "\(actionName)区域？",
      message:
        "实际操作范围：\(aligned.coordinateText)，共 \(aligned.chunkCount) 个完整区块。\n\(explanation)此操作不会自动备份。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: actionName, style: .destructive) { [weak self] _ in
        self?.performRegionDestructiveAction(region: region, regenerate: regenerate)
      })
    present(alert, animated: true)
  }

  private func performRegionDestructiveAction(region: BedrockMapRegion, regenerate: Bool) {
    let actionName = regenerate ? "重新生成" : "清空"
    let overlay = showBusy("\(actionName)区域区块…")
    chunkMenuQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let store = BedrockChunkStore(session: self.session)
        let result = regenerate ? try store.regenerateRegion(region) : try store.clearRegion(region)
        let message =
          "已\(actionName) \(result.changedChunkCount) 个区块，跳过 \(result.skippedChunkCount) 个无记录区块。"
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.setSelectionMode(false)
          self.handleChunkMutation(message: message, preferredPosition: nil)
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "\(actionName)区域失败")
        }
      }
    }
  }

  private func selectWorldObject(_ object: BedrockWorldObject) {
    selectedVillageID = nil
    selectedVillageEntityIDs.removeAll()
    selectedSpawnerID = nil
    selectedBlock = nil
    blockDetailPanel.clearBlock()
    selectedWorldObjectID = object.stableID
    session.rememberSelectedWorldObject(object)
    objectOverlayView.setSelectedObjectID(object.stableID)
    updateObjectOverlay()
    statusLabel.text = "已选中 \(object.kind.displayName)：\(object.displayName)；图标正在闪烁。"
  }

  private func clearSelectedWorldObject() {
    guard selectedWorldObjectID != nil else { return }
    selectedWorldObjectID = nil
    objectOverlayView.setSelectedObjectID(nil)
    updateObjectOverlay()
  }

  @objc private func mapTapped(_ recognizer: UITapGestureRecognizer) {
    let imagePoint = recognizer.location(in: imageView)
    guard !isSelectionMode else { return }
    if currentSliceAxis != .y {
      if let hit = crossSectionWorldObjectHit(at: imagePoint) {
        selectWorldObject(hit.object)
        showWorldObjectDetails(hit.object)
        return
      }
      if let player = mapPlayerHits(at: imagePoint).first {
        showPlayerDetails(player.player)
        return
      }
      if let spawn = spawnPointHits(at: imagePoint).first {
        showSpawnInformation(spawn.spawn)
        return
      }
      guard let blockPosition = crossSectionPosition(at: imagePoint) else { return }
      if let spawner = crossSectionHardcodedSpawnerHit(at: blockPosition) {
        openHardcodedSpawnerEditor(spawner)
        return
      }
      showBlockAxisLine(at: blockPosition)
      return
    }
    guard let position = mapPosition(at: imagePoint) else { return }
    selectedVillageID = nil
    selectedVillageEntityIDs.removeAll()
    selectedSpawnerID = nil

    // Purple POIs remain foreground controls. Spawn markers can occupy the
    // same screen location as a village point, so overlapping candidates are
    // presented together instead of making one item impossible to select.
    let poiHit = pointOfInterestHit(at: imagePoint)
    let centerHit = villageCenterHit(at: imagePoint)
    let spawnHits = spawnPointHits(at: imagePoint)
    let playerHits = mapPlayerHits(at: imagePoint)
    let optionCount =
      (poiHit == nil ? 0 : 1) + (centerHit == nil ? 0 : 1) + spawnHits.count + playerHits.count

    if optionCount > 1 {
      if spawnHits.isEmpty, playerHits.isEmpty,
        let poiHit = poiHit,
        let centerHit = centerHit,
        poiHit.village.stableID == centerHit.stableID,
        let center = centerHit.feature.center,
        center.x == poiHit.point.x,
        center.z == poiHit.point.z
      {
        presentVillageCenterPOIChoice(poiHit: poiHit, centerHit: centerHit, sourcePoint: imagePoint)
      } else {
        presentMapPointChoice(
          poiHit: poiHit,
          centerHit: centerHit,
          spawnHits: spawnHits,
          playerHits: playerHits,
          sourcePoint: imagePoint
        )
      }
      return
    }
    if let poiHit = poiHit {
      selectPointOfInterestBlock(poiHit)
      return
    }
    if let centerHit = centerHit {
      showVillageCenterInformation(centerHit)
      return
    }
    if let hit = playerHits.first {
      showPlayerDetails(hit.player)
      return
    }
    if let hit = spawnHits.first {
      showSpawnInformation(hit.spawn)
      return
    }

    if chunkSelectionSwitch.isOn {
      let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
      selectChunk(
        ChunkPosition(
          x: MapCoordinate.chunk(fromBlock: position.absoluteX),
          z: MapCoordinate.chunk(fromBlock: position.absoluteZ),
          dimension: dimension
        ), centerMap: false)
      return
    }

    if let hit = nearestWorldObject(
      localX: CGFloat(position.localX) + 0.5, localZ: CGFloat(position.localZ) + 0.5)
    {
      selectWorldObject(hit.object)
      showWorldObjectDetails(hit.object)
      return
    }

    clearSelectedWorldObject()
    let side = renderedSideChunks * 16
    let index = position.localZ * side + position.localX
    let initialY: Int32? =
      lastBlockHeights.indices.contains(index) && lastBlockHeights[index] != Int16.min
      ? Int32(lastBlockHeights[index])
      : 0
    showBlockColumn(x: position.absoluteX, z: position.absoluteZ, initialY: initialY)
  }

  @objc private func handleChunkLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, !isSelectionMode else { return }
    let point = recognizer.location(in: imageView)
    guard let mapPosition = mapPosition(at: point) else { return }

    let village = villageHit(atX: mapPosition.absoluteX, z: mapPosition.absoluteZ)
    let spawner = hardcodedSpawnerHit(atX: mapPosition.absoluteX, z: mapPosition.absoluteZ)
    if village != nil || spawner != nil {
      if let village = village, let spawner = spawner {
        let alert = UIAlertController(
          title: "选择地图对象",
          message: "此位置同时位于村庄和 HardcodedSpawners 区域内。",
          preferredStyle: .actionSheet
        )
        alert.addAction(
          UIAlertAction(title: "编辑 \(village.feature.displayName)", style: .default) {
            [weak self] _ in
            self?.openVillageEditor(village)
          })
        alert.addAction(
          UIAlertAction(title: "编辑 \(spawner.area.kind.displayName)", style: .default) {
            [weak self] _ in
            self?.openHardcodedSpawnerEditor(spawner)
          })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
          popover.sourceView = imageView
          popover.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        }
        present(alert, animated: true)
      } else if let village = village {
        openVillageEditor(village)
      } else if let spawner = spawner {
        openHardcodedSpawnerEditor(spawner)
      }
      return
    }

    guard chunkSelectionSwitch.isOn, selectedChunk != nil else {
      statusLabel.text = "长按村庄或 HardcodedSpawners 可直接编辑；要打开区块菜单，请先开启区块选择并点按区块。"
      return
    }
    openChunkMenu(at: mapPosition, sourcePoint: point)
  }

  private func pointOfInterestHit(at imagePoint: CGPoint) -> MapVillagePOIHit? {
    guard showVillages, imageView.bounds.width > 0, imageView.bounds.height > 0 else { return nil }
    let sideBlocks = CGFloat(renderedSideChunks * 16)
    let startBlockX = renderedStartBlockX
    let startBlockZ = renderedStartBlockZ
    let tap = imageView.convert(imagePoint, to: objectOverlayView)
    var candidates = [(hit: MapVillagePOIHit, distance: CGFloat)]()
    for village in lastVillageHits {
      for point in village.feature.pointsOfInterest {
        let localX = CGFloat(point.x - startBlockX) + 0.5
        let localZ = CGFloat(point.z - startBlockZ) + 0.5
        let candidateInImage = CGPoint(
          x: localX / sideBlocks * imageView.bounds.width,
          y: localZ / sideBlocks * imageView.bounds.height
        )
        let candidate = imageView.convert(candidateInImage, to: objectOverlayView)
        let distance = hypot(candidate.x - tap.x, candidate.y - tap.y)
        if distance <= 12 {
          candidates.append((MapVillagePOIHit(village: village, point: point), distance))
        }
      }
    }
    return candidates.min { lhs, rhs in
      if abs(lhs.distance - rhs.distance) > 0.01 { return lhs.distance < rhs.distance }
      return (lhs.hit.village.feature.bounds?.area ?? Int64.max)
        < (rhs.hit.village.feature.bounds?.area ?? Int64.max)
    }?.hit
  }

  private func mapPlayerHits(at imagePoint: CGPoint) -> [MapPlayerHit] {
    guard showPlayers, imageView.bounds.width > 0, imageView.bounds.height > 0 else { return [] }
    let sideBlocks = CGFloat(renderedSideChunks * 16)
    let tap = imageView.convert(imagePoint, to: objectOverlayView)
    return lastPlayerHits.compactMap { hit -> (MapPlayerHit, CGFloat)? in
      let candidateInImage = CGPoint(
        x: hit.localX / sideBlocks * imageView.bounds.width,
        y: hit.localZ / sideBlocks * imageView.bounds.height
      )
      let candidate = imageView.convert(candidateInImage, to: objectOverlayView)
      let distance = hypot(candidate.x - tap.x, candidate.y - tap.y)
      return distance <= 15 ? (hit, distance) : nil
    }
    .sorted { lhs, rhs in
      if abs(lhs.1 - rhs.1) > 0.01 { return lhs.1 < rhs.1 }
      if lhs.0.player.isLocal != rhs.0.player.isLocal { return lhs.0.player.isLocal }
      return lhs.0.player.record.displayName.localizedCaseInsensitiveCompare(
        rhs.0.player.record.displayName) == .orderedAscending
    }
    .map(\.0)
  }

  private func spawnPointHits(at imagePoint: CGPoint) -> [MapSpawnHit] {
    guard showSpawnPoints, imageView.bounds.width > 0, imageView.bounds.height > 0 else {
      return []
    }
    let sideBlocks = CGFloat(renderedSideChunks * 16)
    let tap = imageView.convert(imagePoint, to: objectOverlayView)
    return lastSpawnHits.compactMap { hit -> (MapSpawnHit, CGFloat)? in
      let candidateInImage = CGPoint(
        x: hit.localX / sideBlocks * imageView.bounds.width,
        y: hit.localZ / sideBlocks * imageView.bounds.height
      )
      let candidate = imageView.convert(candidateInImage, to: objectOverlayView)
      let distance = hypot(candidate.x - tap.x, candidate.y - tap.y)
      return distance <= 14 ? (hit, distance) : nil
    }
    .sorted { lhs, rhs in
      if abs(lhs.1 - rhs.1) > 0.01 { return lhs.1 < rhs.1 }
      if lhs.0.spawn.kind != rhs.0.spawn.kind { return lhs.0.spawn.kind == .world }
      return lhs.0.spawn.name.localizedCaseInsensitiveCompare(rhs.0.spawn.name) == .orderedAscending
    }
    .map(\.0)
  }

  private func presentMapPointChoice(
    poiHit: MapVillagePOIHit?,
    centerHit: MapVillageHit?,
    spawnHits: [MapSpawnHit],
    playerHits: [MapPlayerHit],
    sourcePoint: CGPoint
  ) {
    let alert = UIAlertController(
      title: "选择查看项目",
      message: "此位置附近有多个可查看的地图对象。",
      preferredStyle: .actionSheet
    )
    if let centerHit = centerHit {
      alert.addAction(
        UIAlertAction(title: "查看村庄中心", style: .default) { [weak self] _ in
          self?.showVillageCenterInformation(centerHit)
        })
    }
    if let poiHit = poiHit {
      alert.addAction(
        UIAlertAction(title: "查看兴趣点方块", style: .default) { [weak self] _ in
          self?.selectPointOfInterestBlock(poiHit)
        })
    }
    for hit in playerHits.prefix(12) {
      let role = hit.player.isLocal ? "本地玩家" : "在线玩家"
      alert.addAction(
        UIAlertAction(title: "查看\(role) · \(hit.player.record.displayName)", style: .default) {
          [weak self] _ in
          self?.showPlayerDetails(hit.player)
        })
    }
    for hit in spawnHits.prefix(12) {
      let title = hit.spawn.kind == .world ? "查看世界出生点" : "查看玩家出生点 · \(hit.spawn.name)"
      alert.addAction(
        UIAlertAction(title: title, style: .default) { [weak self] _ in
          self?.showSpawnInformation(hit.spawn)
        })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = imageView
      popover.sourceRect = CGRect(x: sourcePoint.x, y: sourcePoint.y, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func showPlayerDetails(_ player: MapPlayerCoordinate) {
    let position = player.position
    let dimension =
      BedrockDimension(rawValue: position.dimension)?.displayName ?? "维度 \(position.dimension)"
    let uniqueIDText = player.uniqueID.map(String.init) ?? "未知"
    let role = player.isLocal ? "本地玩家" : "在线玩家"
    let coordinateText = String(format: "X=%.2f Y=%.2f Z=%.2f", position.x, position.y, position.z)
    let message = [
      "identifier：minecraft:player",
      "UniqueID：\(uniqueIDText)",
      "类型：\(role)",
      "维度：\(dimension)",
      "坐标：\(coordinateText)",
      "来源：\(player.record.keyText)",
    ].joined(separator: "\n")
    let alert = UIAlertController(
      title: player.record.displayName, message: message, preferredStyle: .actionSheet)
    alert.addAction(
      UIAlertAction(title: "编辑 NBT", style: .default) { [weak self] _ in
        guard let self = self else { return }
        let store = PlayerNBTStore(session: self.session)
        let controller = PlayerNBTEditorViewController(record: player.record, store: store) {
          [weak self] in
          self?.session.invalidateAfterExternalChange()
        }
        self.navigationController?.pushViewController(controller, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "定位到玩家", style: .default) { [weak self] _ in
        self?.locate(player: player)
      })
    alert.addAction(
      UIAlertAction(title: "复制坐标", style: .default) { _ in
        UIPasteboard.general.string = coordinateText
      })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = imageView
      popover.sourceRect = CGRect(
        x: imageView.bounds.midX, y: imageView.bounds.midY, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func locate(player: MapPlayerCoordinate) {
    guard
      let dimensionIndex = BedrockDimension.allCases.firstIndex(where: {
        $0.rawValue == player.position.dimension
      })
    else { return }
    dimensionControl.selectedSegmentIndex = dimensionIndex
    coordinateModeControl.selectedSegmentIndex = 1
    let x = Int64(floor(player.position.x))
    let z = Int64(floor(player.position.z))
    xField.text = String(x)
    zField.text = String(z)
    render(
      centerX: MapCoordinate.chunk(fromBlock: x),
      centerZ: MapCoordinate.chunk(fromBlock: z),
      anchor: MapViewportAnchor(
        blockX: player.position.x,
        blockZ: player.position.z,
        zoomScale: max(effectiveZoomScale, 1)
      ),
      reason: "定位玩家",
      showOverlay: true
    )
  }

  private func showSpawnInformation(_ spawn: MapSpawnCoordinate) {
    let dimension =
      BedrockDimension(rawValue: spawn.dimension)?.displayName ?? "维度 \(spawn.dimension)"
    let yText = spawn.y.map(String.init) ?? "未知"
    var lines = [
      "类型：\(spawn.kind.displayName)",
      "名称：\(spawn.name)",
      "维度：\(dimension)",
      "坐标：X=\(spawn.x)，Y=\(yText)，Z=\(spawn.z)",
      "来源：\(spawn.source)",
    ]
    if let forced = spawn.forced {
      let forcedText = forced ? "是" : "否"
      lines.append("强制出生：\(forcedText)")
    }
    let alert = UIAlertController(
      title: spawn.kind.displayName,
      message: lines.joined(separator: "\n"),
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "完成", style: .default))
    present(alert, animated: true)
  }

  private func villageCenterHit(at imagePoint: CGPoint) -> MapVillageHit? {
    guard showVillages, imageView.bounds.width > 0, imageView.bounds.height > 0 else { return nil }
    let sideBlocks = CGFloat(renderedSideChunks * 16)
    let startBlockX = renderedStartBlockX
    let startBlockZ = renderedStartBlockZ
    let tap = imageView.convert(imagePoint, to: objectOverlayView)
    var candidates = [(hit: MapVillageHit, distance: CGFloat)]()
    for hit in lastVillageHits {
      guard let center = hit.feature.center else { continue }
      let localX = CGFloat(center.x - startBlockX) + 0.5
      let localZ = CGFloat(center.z - startBlockZ) + 0.5
      let candidateInImage = CGPoint(
        x: localX / sideBlocks * imageView.bounds.width,
        y: localZ / sideBlocks * imageView.bounds.height
      )
      let candidate = imageView.convert(candidateInImage, to: objectOverlayView)
      let distance = hypot(candidate.x - tap.x, candidate.y - tap.y)
      if distance <= 13 { candidates.append((hit, distance)) }
    }
    return candidates.min { lhs, rhs in
      if abs(lhs.distance - rhs.distance) > 0.01 { return lhs.distance < rhs.distance }
      return (lhs.hit.feature.bounds?.area ?? Int64.max)
        < (rhs.hit.feature.bounds?.area ?? Int64.max)
    }?.hit
  }

  private func presentVillageCenterPOIChoice(
    poiHit: MapVillagePOIHit,
    centerHit: MapVillageHit,
    sourcePoint: CGPoint
  ) {
    let alert = UIAlertController(
      title: "选择查看项目",
      message: "村庄中心与兴趣点方块位于同一坐标。",
      preferredStyle: .actionSheet
    )
    alert.addAction(
      UIAlertAction(title: "查看村庄中心", style: .default) { [weak self] _ in
        self?.showVillageCenterInformation(centerHit)
      })
    alert.addAction(
      UIAlertAction(title: "查看兴趣点方块", style: .default) { [weak self] _ in
        self?.selectPointOfInterestBlock(poiHit)
      })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = imageView
      popover.sourceRect = CGRect(x: sourcePoint.x, y: sourcePoint.y, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  private func selectPointOfInterestBlock(_ hit: MapVillagePOIHit) {
    selectedVillageID = nil
    selectedVillageEntityIDs.removeAll()
    selectedSpawnerID = nil
    selectedWorldObjectID = nil
    selectedChunk = nil
    objectOverlayView.setSelectedObjectID(nil)

    let point = hit.point
    guard (-64...319).contains(Int(point.y)) else {
      showBlockColumn(
        x: point.x,
        z: point.z,
        initialY: nil,
        annotation: "兴趣点方块"
      )
      return
    }

    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let overlay = showBusy("读取兴趣点方块 (\(point.x), \(point.y), \(point.z))…")
    renderQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let block = try self.rendererForCurrentSession().block(
          blockX: point.x,
          y: Int32(clamping: point.y),
          blockZ: point.z,
          dimension: dimension
        )
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.selectBlock(block, annotation: "兴趣点方块")
          self.statusLabel.text = "已优先选中兴趣点方块 \(block.coordinateDescription)：\(block.name)。"
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "无法读取兴趣点方块")
        }
      }
    }
  }

  private func showVillageCenterInformation(_ hit: MapVillageHit) {
    selectedVillageID = hit.stableID
    selectedVillageEntityIDs = Set(
      (hit.feature.villagerEntities + hit.feature.ironGolemEntities).map(\.stableID)
    )
    selectedSpawnerID = nil
    selectedWorldObjectID = nil
    selectedBlock = nil
    objectOverlayView.setSelectedObjectID(nil)
    blockDetailPanel.clearBlock()
    updateObjectOverlay()

    guard let center = hit.feature.center else { return }
    let reputationText: String
    if hit.feature.playerReputations.isEmpty {
      reputationText = "0"
    } else {
      reputationText = hit.feature.playerReputations.map {
        "\($0.playerIdentifier)：\($0.value)"
      }.joined(separator: "\n")
    }
    let message =
      "村庄中心坐标：X=\(center.x)，Y=\(center.y)，Z=\(center.z)\n玩家声望：\(reputationText)\n村民数目：\(hit.feature.villagerCount)"
    let alert = UIAlertController(
      title: hit.feature.displayName, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
    present(alert, animated: true)
    statusLabel.text =
      "已查看 \(hit.feature.displayName)；其 \(hit.feature.villagerEntities.count) 个村民和 \(hit.feature.ironGolemEntities.count) 个铁傀儡正在闪烁。"
  }

  private func villageHit(atX x: Int64, z: Int64) -> MapVillageHit? {
    let containing = lastVillageHits.filter { hit in
      hit.feature.contains(x: x, z: z)
    }
    if let smallest = containing.min(by: {
      ($0.feature.bounds?.area ?? Int64.max) < ($1.feature.bounds?.area ?? Int64.max)
    }) {
      return smallest
    }

    let proximity: Double = 3.0
    return lastVillageHits.min { lhs, rhs in
      villageDistance(lhs, x: x, z: z) < villageDistance(rhs, x: x, z: z)
    }.flatMap { villageDistance($0, x: x, z: z) <= proximity ? $0 : nil }
  }

  private func villageDistance(_ hit: MapVillageHit, x: Int64, z: Int64) -> Double {
    let points = ([hit.feature.center].compactMap { $0 } + hit.feature.pointsOfInterest)
    guard !points.isEmpty else { return .greatestFiniteMagnitude }
    return points.map { point in
      hypot(Double(point.x - x), Double(point.z - z))
    }.min() ?? .greatestFiniteMagnitude
  }

  private func hardcodedSpawnerHit(atX x: Int64, z: Int64) -> MapHardcodedSpawnerHit? {
    lastHardcodedSpawnerHits.filter { hit in
      x >= Int64(hit.area.minimumX) && x <= Int64(hit.area.maximumX)
        && z >= Int64(hit.area.minimumZ) && z <= Int64(hit.area.maximumZ)
    }.min { lhs, rhs in
      let lhsWidth = Int64(lhs.area.maximumX) - Int64(lhs.area.minimumX) + 1
      let lhsDepth = Int64(lhs.area.maximumZ) - Int64(lhs.area.minimumZ) + 1
      let rhsWidth = Int64(rhs.area.maximumX) - Int64(rhs.area.minimumX) + 1
      let rhsDepth = Int64(rhs.area.maximumZ) - Int64(rhs.area.minimumZ) + 1
      let lhsArea = max(Int64(1), lhsWidth) * max(Int64(1), lhsDepth)
      let rhsArea = max(Int64(1), rhsWidth) * max(Int64(1), rhsDepth)
      return lhsArea < rhsArea
    }
  }

  private func openVillageEditor(_ hit: MapVillageHit) {
    selectedVillageID = hit.stableID
    selectedVillageEntityIDs.removeAll()
    selectedSpawnerID = nil
    selectedWorldObjectID = nil
    objectOverlayView.setSelectedObjectID(nil)
    updateObjectOverlay()
    statusLabel.text = "已选中 \(hit.feature.displayName)，正在显示信息、兴趣点、居民和声望。"
    let controller = VillageNBTListViewController(
      session: session,
      villageIdentifier: hit.feature.identifier,
      villageDisplayName: hit.feature.displayName,
      onSave: { [weak self] in
        guard let self = self else { return }
        self.selectedVillageID = nil
        self.selectedVillageEntityIDs.removeAll()
        self.refreshObjectOverlays(reason: "村庄 NBT 已更新")
      }
    )
    navigationController?.pushViewController(controller, animated: true)
  }

  private func openHardcodedSpawnerEditor(_ hit: MapHardcodedSpawnerHit) {
    selectedSpawnerID = hit.stableID
    selectedVillageID = nil
    selectedVillageEntityIDs.removeAll()
    selectedWorldObjectID = nil
    objectOverlayView.setSelectedObjectID(nil)
    updateObjectOverlay()
    statusLabel.text = "已选中 \(hit.area.kind.displayName) 刷怪区域，边框正在闪烁。"
    let controller = HardcodedSpawnersViewController(
      session: session,
      chunk: hit.ownerChunk,
      selectedAreaIndex: hit.areaIndex
    )
    controller.onSave = { [weak self] _ in
      guard let self = self else { return }
      self.selectedSpawnerID = nil
      self.refreshObjectOverlays(reason: "HardcodedSpawners 已更新")
    }
    navigationController?.pushViewController(controller, animated: true)
  }

  private func openChunkMenu(
    at mapPosition: (localX: Int, localZ: Int, absoluteX: Int64, absoluteZ: Int64),
    sourcePoint point: CGPoint
  ) {
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let position = ChunkPosition(
      x: MapCoordinate.chunk(fromBlock: mapPosition.absoluteX),
      z: MapCoordinate.chunk(fromBlock: mapPosition.absoluteZ),
      dimension: dimension
    )
    if selectedChunk != position { selectChunk(position, centerMap: false) }

    let overlay = showBusy("读取区块菜单…")
    chunkMenuQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let summary = try BedrockChunkStore(session: self.session).summary(at: position)
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          ChunkActionMenu.present(
            from: self,
            session: self.session,
            summary: summary,
            sourceView: self.imageView,
            sourceRect: CGRect(x: point.x, y: point.y, width: 1, height: 1),
            onSelect: { [weak self] selected in self?.selectChunk(selected, centerMap: false) },
            onMutation: { [weak self] message, preferredPosition in
              self?.handleChunkMutation(message: message, preferredPosition: preferredPosition)
            }
          )
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "无法读取区块菜单")
        }
      }
    }
  }

  func selectChunkFromChunkTab(_ position: ChunkPosition) {
    loadViewIfNeeded()
    selectChunk(position, centerMap: true)
  }

  func selectTickingAreaFromChunkTab(_ position: ChunkPosition) {
    loadViewIfNeeded()
    if let index = MapRenderMode.allCases.firstIndex(of: .tickingAreas) {
      modeControl.selectedSegmentIndex = index
    }
    selectChunk(position, centerMap: true)
  }

  func handleChunkMutationFromChunkTab(message: String, preferredPosition: ChunkPosition?) {
    loadViewIfNeeded()
    handleChunkMutation(message: message, preferredPosition: preferredPosition)
  }

  private func selectChunk(_ position: ChunkPosition, centerMap: Bool) {
    selectedChunk = position
    selectedVillageID = nil
    selectedVillageEntityIDs.removeAll()
    selectedSpawnerID = nil
    selectedBlock = nil
    blockDetailPanel.clearBlock()
    clearSelectedWorldObject()
    if let dimensionIndex = BedrockDimension.allCases.firstIndex(where: {
      $0.rawValue == position.dimension
    }) {
      dimensionControl.selectedSegmentIndex = dimensionIndex
    }
    chunkSelectionSwitch.setOn(true, animated: true)
    if centerMap {
      coordinateModeControl.selectedSegmentIndex = 0
      xField.text = String(position.x)
      zField.text = String(position.z)
      let blockX = Double(MapCoordinate.blockOrigin(ofChunk: position.x)) + 8
      let blockZ = Double(MapCoordinate.blockOrigin(ofChunk: position.z)) + 8
      render(
        centerX: position.x,
        centerZ: position.z,
        anchor: MapViewportAnchor(
          blockX: blockX, blockZ: blockZ,
          zoomScale: max(effectiveZoomScale, CGFloat.leastNormalMagnitude)),
        reason: "选择区块",
        showOverlay: true
      )
    } else {
      updateObjectOverlay()
    }
    statusLabel.text = "已选中区块 (\(position.x), \(position.z))；橙色边框正在闪烁，长按该区块可打开区块菜单。"
  }

  private func handleChunkMutation(message: String, preferredPosition: ChunkPosition?) {
    renderQueue.async { [weak self] in
      self?.chunkCache.removeAll()
      self?.chunkRenderer?.clearCache()
    }
    selectedBlock = nil
    blockDetailPanel.clearBlock()
    if let preferredPosition = preferredPosition {
      selectedChunk = preferredPosition
      if let dimensionIndex = BedrockDimension.allCases.firstIndex(where: {
        $0.rawValue == preferredPosition.dimension
      }) {
        dimensionControl.selectedSegmentIndex = dimensionIndex
      }
    } else {
      selectedChunk = nil
    }
    statusLabel.text = message
    render(
      centerX: preferredPosition?.x ?? lastCenterX,
      centerZ: preferredPosition?.z ?? lastCenterZ,
      anchor: nil,
      reason: "区块数据已更新",
      showOverlay: false
    )
  }

  private func showBlockColumn(x: Int64, z: Int64, initialY: Int32?, annotation: String? = nil) {
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let overlay = showBusy("读取 X=\(x)、Z=\(z) 的 Y 轴方块…")
    renderQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let result = try self.rendererForCurrentSession().blockColumn(
          blockX: x, blockZ: z, dimension: dimension)
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          let picker = BlockColumnPickerViewController(result: result, initialY: initialY) {
            [weak self] block in
            self?.selectBlock(block, annotation: annotation)
          }
          let navigation = UINavigationController(rootViewController: picker)
          navigation.modalPresentationStyle = .formSheet
          self.present(navigation, animated: true)
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "无法读取方块列")
        }
      }
    }
  }

  private func selectBlock(_ block: BedrockBlockRecord, annotation: String? = nil) {
    selectedWorldObjectID = nil
    objectOverlayView.setSelectedObjectID(nil)
    selectedBlock = block
    session.rememberSelectedBlock(x: block.x, y: block.y, z: block.z, dimension: block.dimension)
    blockDetailPanel.show(block: block, annotation: annotation)
    blockDetailPanel.setReturnToSearchResultsAvailable(session.rememberedBlockSearchResult != nil)
    updateObjectOverlay()
    statusLabel.text = "已选中方块 \(block.coordinateDescription)：\(block.name)；地图图标正在闪烁。"
  }

  private func saveBlockNBT(block: BedrockBlockRecord, layerIndex: Int, document: NBTDocument) {
    let overlay = showBusy("写回方块 NBT…")
    renderQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let result = try BedrockBlockNBTStore(session: self.session).save(
          block: block,
          storageIndex: layerIndex,
          document: document
        )
        self.chunkCache.removeAll()
        self.chunkRenderer?.clearCache()
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.selectedBlock = result.block
          self.blockDetailPanel.markSaved(block: result.block, layerIndex: layerIndex)
          self.updateObjectOverlay()
          self.statusLabel.text = "已保存方块 NBT：\(result.block.coordinateDescription)。"
          self.render(
            centerX: self.lastCenterX,
            centerZ: self.lastCenterZ,
            anchor: self.currentViewportAnchor(),
            reason: "方块 NBT 已修改",
            showOverlay: false
          )
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.blockDetailPanel.showSaveError(error)
        }
      }
    }
  }

  private func jumpToBlock(x: Int64, y: Int32, z: Int64) {
    guard (-64...319).contains(Int(y)) else {
      showError(MCBEEditorError.malformedData("当前版本支持的 Y 范围为 -64…319"), title: "方块坐标错误")
      return
    }
    view.endEditing(true)
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let overlay = showBusy("读取方块 (\(x), \(y), \(z))…")
    renderQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let block = try self.rendererForCurrentSession().block(
          blockX: x, y: y, blockZ: z, dimension: dimension)
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.coordinateModeControl.selectedSegmentIndex = 1
          self.xField.text = String(x)
          self.yField.text = String(y)
          self.zField.text = String(z)
          self.sliceCenterBlockX = x
          self.sliceCenterY = y
          self.sliceCenterBlockZ = z
          self.selectBlock(block)
          self.render(
            centerX: MapCoordinate.chunk(fromBlock: x),
            centerZ: MapCoordinate.chunk(fromBlock: z),
            anchor: MapViewportAnchor(
              blockX: Double(x) + 0.5, blockZ: Double(z) + 0.5,
              zoomScale: max(self.effectiveZoomScale, 1)),
            reason: "方块跳转",
            showOverlay: true
          )
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "无法读取方块")
        }
      }
    }
  }

  @objc private func mapDoubleTapped(_ recognizer: UITapGestureRecognizer) {
    let point = recognizer.location(in: imageView)
    let proposedScale = scrollView.zoomScale * 2
    expandZoomRangeIfNeeded(for: proposedScale)
    zoom(to: proposedScale, around: point, animated: true)
  }

  @objc private func mapTwoFingerTapped(_ recognizer: UITapGestureRecognizer) {
    let point = recognizer.location(in: imageView)
    let proposedScale = scrollView.zoomScale / 2
    expandZoomRangeIfNeeded(for: proposedScale)
    zoom(to: proposedScale, around: point, animated: true)
  }

  private func nearestWorldObject(localX: CGFloat, localZ: CGFloat) -> MapWorldObjectHit? {
    let nearest = lastWorldObjectHits.filter(\.isNormallyVisible).min { lhs, rhs in
      worldObjectDistance(lhs, fromX: localX, z: localZ)
        < worldObjectDistance(rhs, fromX: localX, z: localZ)
    }
    guard let nearest = nearest, worldObjectDistance(nearest, fromX: localX, z: localZ) <= 1.8
    else { return nil }
    return nearest
  }

  private func worldObjectDistance(_ hit: MapWorldObjectHit, fromX x: CGFloat, z: CGFloat)
    -> CGFloat
  {
    let dx = hit.localX - x
    let dz = hit.localZ - z
    return sqrt(dx * dx + dz * dz)
  }

  private func showWorldObjectDetails(_ object: BedrockWorldObject) {
    let dimension =
      BedrockDimension(rawValue: object.dimension)?.displayName ?? "维度 \(object.dimension)"
    var message =
      "\(object.identifier)\n\(dimension)；\(object.coordinateText)\n来源：\(object.source.rawValue)"
    if let uniqueID = object.uniqueID { message += "\nUniqueID：\(uniqueID)" }
    if object.itemCount > 0 { message += "\n物品槽：\(object.itemCount)" }
    let alert = UIAlertController(
      title: object.displayName, message: message, preferredStyle: .actionSheet)
    alert.addAction(
      UIAlertAction(title: "编辑 NBT", style: .default) { [weak self] _ in
        guard let self = self else { return }
        let controller = WorldObjectNBTEditorViewController(
          object: object,
          session: self.session,
          onSave: { [weak self] in self?.session.invalidateAfterExternalChange() }
        )
        self.navigationController?.pushViewController(controller, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "定位到对象", style: .default) { [weak self] _ in
        self?.locate(worldObject: object)
      })
    alert.addAction(
      UIAlertAction(title: "复制坐标", style: .default) { _ in
        UIPasteboard.general.string = object.coordinateText
      })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = imageView
      popover.sourceRect = CGRect(
        x: imageView.bounds.midX, y: imageView.bounds.midY, width: 1, height: 1)
    }
    present(alert, animated: true)
  }

  func locate(worldObject: BedrockWorldObject) {
    loadViewIfNeeded()
    selectedWorldObjectID = worldObject.stableID
    session.rememberSelectedWorldObject(worldObject)
    objectOverlayView.setSelectedObjectID(worldObject.stableID)
    guard let position = worldObject.position,
      let dimensionIndex = BedrockDimension.allCases.firstIndex(where: {
        $0.rawValue == worldObject.dimension
      })
    else {
      showError(MCBEEditorError.malformedData("该对象没有可定位坐标"), title: "无法定位")
      return
    }
    dimensionControl.selectedSegmentIndex = dimensionIndex
    coordinateModeControl.selectedSegmentIndex = 1
    xField.text = String(position.blockX)
    zField.text = String(position.blockZ)
    render(
      centerX: MapCoordinate.chunk(fromBlock: position.blockX),
      centerZ: MapCoordinate.chunk(fromBlock: position.blockZ),
      anchor: MapViewportAnchor(
        blockX: position.x, blockZ: position.z, zoomScale: max(effectiveZoomScale, 1)),
      reason: "定位\(worldObject.kind.displayName)",
      showOverlay: true
    )
  }

  @objc private func showOverlayOptions() {
    let verticalSlice = currentSliceAxis != .y
    let alert = UIAlertController(
      title: "地图对象图层",
      message: verticalSlice
        ? "X/Z 剖面会显示与当前切面相交的玩家、实体、方块实体、HardcodedSpawners 与出生点；村庄图层在剖面模式隐藏。未生成纹理按 SubChunk 显示，红色虚线为建筑高度限制。"
        : "黄色五角星为本地玩家，蓝色五角星为在线玩家；蓝色圆点为实体，青色方块为方块实体，粉色虚线框为 HardcodedSpawners；绿色虚线框为村庄边界，橙色菱形为村庄中心，紫色方块为兴趣点。黄色标记为世界出生点，绿色标记为玩家出生点；未生成区块纹理会以固定密度显示。",
      preferredStyle: .actionSheet
    )
    let playerTitle = showPlayers ? "✓ 显示玩家" : "显示玩家"
    let entityTitle = showEntities ? "✓ 显示实体" : "显示实体"
    let blockTitle = showBlockEntities ? "✓ 显示方块实体" : "显示方块实体"
    let spawnTitle = showSpawnPoints ? "✓ 显示出生点" : "显示出生点"
    let spawnerTitle = showHardcodedSpawners ? "✓ 显示 HardcodedSpawners" : "显示 HardcodedSpawners"
    let villageTitle = showVillages ? "✓ 显示村庄" : "显示村庄"
    let ungeneratedTitle: String
    if verticalSlice {
      ungeneratedTitle = showUngeneratedChunks ? "✓ 显示未生成子区块" : "显示未生成子区块"
    } else {
      ungeneratedTitle = showUngeneratedChunks ? "✓ 显示未生成区块" : "显示未生成区块"
    }
    let heightLimitTitle = showBuildHeightLimits ? "✓ 显示建筑高度限制" : "显示建筑高度限制"
    alert.addAction(
      UIAlertAction(title: playerTitle, style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.showPlayers.toggle()
        self.refreshObjectOverlays(reason: "玩家图层")
      })
    alert.addAction(
      UIAlertAction(title: entityTitle, style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.showEntities.toggle()
        self.refreshObjectOverlays(reason: "实体图层")
      })
    alert.addAction(
      UIAlertAction(title: blockTitle, style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.showBlockEntities.toggle()
        self.refreshObjectOverlays(reason: "方块实体图层")
      })
    alert.addAction(
      UIAlertAction(title: spawnTitle, style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.showSpawnPoints.toggle()
        self.refreshObjectOverlays(reason: "出生点图层")
      })
    alert.addAction(
      UIAlertAction(title: spawnerTitle, style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.showHardcodedSpawners.toggle()
        if !self.showHardcodedSpawners { self.selectedSpawnerID = nil }
        self.refreshObjectOverlays(reason: "HardcodedSpawners 图层")
      })
    if !verticalSlice {
      alert.addAction(
        UIAlertAction(title: villageTitle, style: .default) { [weak self] _ in
          guard let self = self else { return }
          self.showVillages.toggle()
          if !self.showVillages {
            self.selectedVillageID = nil
            self.selectedVillageEntityIDs.removeAll()
          }
          self.refreshObjectOverlays(reason: "村庄图层")
        })
    }
    alert.addAction(
      UIAlertAction(title: ungeneratedTitle, style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.showUngeneratedChunks.toggle()
        self.saveMapState()
        let anchor = self.currentViewportAnchor()
        let center = anchor.map { self.chunkCenter(for: $0) } ?? (self.lastCenterX, self.lastCenterZ)
        self.render(
          centerX: center.0,
          centerZ: center.1,
          anchor: anchor,
          reason: verticalSlice ? "未生成子区块图层" : "未生成区块图层",
          showOverlay: false
        )
      })
    if currentSliceAxis != .y {
      alert.addAction(
        UIAlertAction(title: heightLimitTitle, style: .default) { [weak self] _ in
          guard let self = self else { return }
          self.showBuildHeightLimits.toggle()
          self.saveMapState()
          self.updateObjectOverlay()
        })
    }
    alert.addAction(
      UIAlertAction(title: "全部显示", style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.showPlayers = true
        self.showEntities = true
        self.showBlockEntities = true
        self.showHardcodedSpawners = true
        if !verticalSlice { self.showVillages = true }
        self.showSpawnPoints = true
        self.showUngeneratedChunks = true
        self.showBuildHeightLimits = true
        self.saveMapState()
        let anchor = self.currentViewportAnchor()
        let center = anchor.map { self.chunkCenter(for: $0) } ?? (self.lastCenterX, self.lastCenterZ)
        self.render(centerX: center.0, centerZ: center.1, anchor: anchor, reason: "对象图层", showOverlay: false)
      })
    alert.addAction(
      UIAlertAction(title: "全部隐藏", style: .destructive) { [weak self] _ in
        guard let self = self else { return }
        self.showPlayers = false
        self.showEntities = false
        self.showBlockEntities = false
        self.showHardcodedSpawners = false
        self.showVillages = false
        self.showSpawnPoints = false
        self.showUngeneratedChunks = false
        self.showBuildHeightLimits = false
        self.selectedSpawnerID = nil
        self.selectedVillageID = nil
        self.selectedVillageEntityIDs.removeAll()
        self.saveMapState()
        let anchor = self.currentViewportAnchor()
        let center = anchor.map { self.chunkCenter(for: $0) } ?? (self.lastCenterX, self.lastCenterZ)
        self.render(centerX: center.0, centerZ: center.1, anchor: anchor, reason: "对象图层", showOverlay: false)
      })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.popoverPresentationController?.barButtonItem = overlayButton
    present(alert, animated: true)
  }

  private func refreshObjectOverlays(reason: String) {
    saveMapState()
    let anchor = currentViewportAnchor()
    render(
      centerX: lastCenterX, centerZ: lastCenterZ, anchor: anchor, reason: reason, showOverlay: false
    )
  }

  @objc private func showZoomOptions() {
    let alert = UIAlertController(
      title: "地图缩放", message: "可直接双指捏合缩放；双击放大，两指轻点缩小。", preferredStyle: .actionSheet)
    alert.addAction(
      UIAlertAction(title: "适合屏幕", style: .default) { [weak self] _ in
        self?.setFitZoom(animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "100%", style: .default) { [weak self] _ in
        self?.setZoomScale(1, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "200%", style: .default) { [weak self] _ in
        self?.setZoomScale(2, animated: true)
      })
    alert.addAction(
      UIAlertAction(title: "400%", style: .default) { [weak self] _ in
        self?.setZoomScale(4, animated: true)
      })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.popoverPresentationController?.barButtonItem = zoomButton
    present(alert, animated: true)
  }

  /// Calculates the dynamic chunk window from the actual viewport and zoom.
  /// No fixed side-length cap is applied; the returned window grows with the
  /// visible area while retaining a two-chunk preload border.
  private func dynamicRenderSideChunks(forZoomScale zoomScale: CGFloat) -> Int {
    guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else {
      return minimumDynamicSideChunks
    }
    let safeZoom = max(CGFloat.leastNormalMagnitude, zoomScale)
    let pointsPerBlock = Double(basePointsPerBlock * safeZoom)
    guard pointsPerBlock.isFinite, pointsPerBlock > 0 else { return minimumDynamicSideChunks }

    let visibleBlocksWide = ceil(Double(scrollView.bounds.width) / pointsPerBlock)
    let visibleBlocksHigh = ceil(Double(scrollView.bounds.height) / pointsPerBlock)
    let visibleChunksDouble = ceil(max(visibleBlocksWide, visibleBlocksHigh) / 16.0)
    guard visibleChunksDouble.isFinite else { return Int.max / 32 }

    let numericMaximum = min(Int64(Int.max / 32), Int64(maximumBedrockChunkSpan))
    let visibleChunks = Int64(min(Double(numericMaximum), max(0, visibleChunksDouble)))
    let desiredSide = max(
      Int64(minimumDynamicSideChunks), visibleChunks + Int64(dynamicPreloadBorderChunks * 2))
    return Int(min(numericMaximum, desiredSide))
  }

  private func refreshForZoomDrivenRadiusIfNeeded() {
    // Defer until UIKit fully releases the pinch/tracking state. The old
    // immediate guard often saw isTracking == true in scrollViewDidEndZooming
    // and silently discarded the only zoom-out expansion request.
    scheduleAutoRender(immediate: true, zoomDriven: true)
  }

  private func updateZoomLimits() {
    guard scrollView.bounds.width > 0, scrollView.bounds.height > 0,
      imageView.bounds.width > 0, imageView.bounds.height > 0
    else { return }
    expandZoomRangeIfNeeded(for: max(scrollView.zoomScale, CGFloat.leastNormalMagnitude))
  }

  private func expandZoomRangeIfNeeded(for proposedScale: CGFloat) {
    guard proposedScale.isFinite, proposedScale > 0 else { return }
    var minimum = max(CGFloat.leastNormalMagnitude, scrollView.minimumZoomScale)
    var maximum = max(minimum * zoomRangeGrowthFactor, scrollView.maximumZoomScale)

    while proposedScale <= minimum * 1.001,
      minimum > CGFloat.leastNormalMagnitude * zoomRangeGrowthFactor
    {
      minimum /= zoomRangeGrowthFactor
    }
    while proposedScale >= maximum / 1.001,
      maximum < CGFloat.greatestFiniteMagnitude / zoomRangeGrowthFactor
    {
      maximum *= zoomRangeGrowthFactor
    }

    scrollView.minimumZoomScale = minimum
    scrollView.maximumZoomScale = maximum
  }

  private func prepareZoomRangeForUserGesture() {
    let current = max(scrollView.zoomScale, CGFloat.leastNormalMagnitude)
    let lower = max(
      CGFloat.leastNormalMagnitude, current / max(userGestureZoomRangeFactor, 2))
    let upper: CGFloat
    if current < CGFloat.greatestFiniteMagnitude / max(userGestureZoomRangeFactor, 2) {
      upper = current * max(userGestureZoomRangeFactor, 2)
    } else {
      upper = CGFloat.greatestFiniteMagnitude
    }
    if lower < scrollView.minimumZoomScale { scrollView.minimumZoomScale = lower }
    if upper > scrollView.maximumZoomScale { scrollView.maximumZoomScale = upper }
  }

  private func setFitZoom(animated: Bool) {
    guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
    let rawFit = min(
      scrollView.bounds.width / imageView.bounds.width,
      scrollView.bounds.height / imageView.bounds.height)
    expandZoomRangeIfNeeded(for: rawFit)
    let target = pixelAlignedZoomScale(rawFit)
    scrollView.setZoomScale(target, animated: animated)
    showZoomHUD(autoHide: true)
    saveMapState()
  }

  /// Sets the user-visible scale. The raw scroll-view scale is derived from
  /// the current finite canvas normalization.
  private func setZoomScale(_ scale: CGFloat, animated: Bool) {
    let rawScale = rawZoomScale(forEffectiveScale: max(scale, CGFloat.leastNormalMagnitude))
    expandZoomRangeIfNeeded(for: rawScale)
    let target = pixelAlignedZoomScale(rawScale)
    scrollView.setZoomScale(target, animated: animated)
    showZoomHUD(autoHide: true)
    saveMapState()
  }

  private func zoom(to scale: CGFloat, around point: CGPoint, animated: Bool) {
    expandZoomRangeIfNeeded(for: scale)
    let target = pixelAlignedZoomScale(scale)
    let width = scrollView.bounds.width / target
    let height = scrollView.bounds.height / target
    let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
    scrollView.zoom(to: rect, animated: animated)
    showZoomHUD(autoHide: true)
    saveMapState()
  }

  private func showZoomHUD(autoHide: Bool = false) {
    zoomHUDWorkItem?.cancel()
    zoomLabel.text = String(format: "  %.0f%%  ", effectiveZoomScale * 100)
    UIView.animate(withDuration: 0.12) { self.zoomLabel.alpha = 1 }
    guard autoHide else { return }
    let item = DispatchWorkItem { [weak self] in
      UIView.animate(withDuration: 0.25) { self?.zoomLabel.alpha = 0 }
    }
    zoomHUDWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
  }

  @objc private func showRenderDiagnostics() {
    let message: String
    if lastErrors.isEmpty {
      message = "本次渲染没有记录到区块解析错误。灰色区域通常表示区块尚未生成；矿物图层中的黑色表示该列没有找到支持的矿物。"
    } else {
      let shown = lastErrors.prefix(30).joined(separator: "\n")
      let suffix = lastErrors.count > 30 ? "\n…另有 \(lastErrors.count - 30) 条" : ""
      message = shown + suffix
    }
    let alert = UIAlertController(title: "地图解析诊断", message: message, preferredStyle: .alert)
    alert.addAction(
      UIAlertAction(title: "复制", style: .default) { _ in UIPasteboard.general.string = message })
    alert.addAction(
      UIAlertAction(title: "清除区块缓存", style: .destructive) { [weak self] _ in
        guard let self = self else { return }
        self.renderQueue.async { self.chunkCache.removeAll() }
        self.statusLabel.text = "区块缓存已清除；下次渲染会重新读取数据库。"
      })
    alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
    present(alert, animated: true)
  }

  private func drawHardcodedSpawner(
    context: CGContext,
    area: HardcodedSpawnerArea,
    startBlockX: Int64,
    startBlockZ: Int64
  ) {
    let minimumX = CGFloat(Int64(area.minimumX) - startBlockX)
    let minimumZ = CGFloat(Int64(area.minimumZ) - startBlockZ)
    let maximumX = CGFloat(Int64(area.maximumX) - startBlockX + 1)
    let maximumZ = CGFloat(Int64(area.maximumZ) - startBlockZ + 1)
    let rect = CGRect(
      x: minimumX,
      y: minimumZ,
      width: maximumX - minimumX,
      height: maximumZ - minimumZ
    )
    context.saveGState()
    context.setFillColor(UIColor.systemPink.withAlphaComponent(0.10).cgColor)
    context.fill(rect)
    context.setStrokeColor(UIColor.systemPink.cgColor)
    context.setLineWidth(0.38)
    context.setLineDash(phase: 0, lengths: [1.2, 0.7])
    context.stroke(rect)
    context.restoreGState()
  }

  private func drawVillage(
    context: CGContext,
    feature: VillageMapFeature,
    startBlockX: Int64,
    startBlockZ: Int64
  ) {
    context.saveGState()
    if let villageBounds = feature.bounds {
      let rect = CGRect(
        x: CGFloat(villageBounds.minimumX - startBlockX),
        y: CGFloat(villageBounds.minimumZ - startBlockZ),
        width: CGFloat(villageBounds.width),
        height: CGFloat(villageBounds.depth)
      )
      context.setStrokeColor(UIColor.systemGreen.cgColor)
      context.setLineWidth(0.38)
      context.setLineDash(phase: 0, lengths: [1.5, 0.9])
      context.stroke(rect)
    }
    context.setLineDash(phase: 0, lengths: [])
    if let center = feature.center {
      let x = CGFloat(center.x - startBlockX) + 0.5
      let z = CGFloat(center.z - startBlockZ) + 0.5
      let radius: CGFloat = 1.25
      context.setFillColor(UIColor.systemOrange.cgColor)
      context.setStrokeColor(UIColor.white.cgColor)
      context.setLineWidth(0.28)
      context.beginPath()
      context.move(to: CGPoint(x: x, y: z - radius))
      context.addLine(to: CGPoint(x: x + radius, y: z))
      context.addLine(to: CGPoint(x: x, y: z + radius))
      context.addLine(to: CGPoint(x: x - radius, y: z))
      context.closePath()
      context.drawPath(using: .fillStroke)
    }
    context.restoreGState()
  }

  private func drawVillagePOILinks(
    context: CGContext,
    links: [MapVillagePOILink],
    startBlockX: Int64,
    startBlockZ: Int64
  ) {
    context.saveGState()
    context.setStrokeColor(UIColor.systemPurple.withAlphaComponent(0.88).cgColor)
    context.setFillColor(UIColor.systemPurple.cgColor)
    context.setLineWidth(0.34)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for link in links {
      let source = CGPoint(x: link.entityLocalX, y: link.entityLocalZ)
      let destination = CGPoint(
        x: CGFloat(link.point.x - startBlockX) + 0.5,
        y: CGFloat(link.point.z - startBlockZ) + 0.5
      )
      let dx = destination.x - source.x
      let dy = destination.y - source.y
      let length = hypot(dx, dy)
      guard length > 1.4 else { continue }
      let ux = dx / length
      let uy = dy / length
      let start = CGPoint(x: source.x + ux * 1.2, y: source.y + uy * 1.2)
      let tip = CGPoint(x: destination.x - ux * 0.75, y: destination.y - uy * 0.75)
      context.move(to: start)
      context.addLine(to: tip)
      context.strokePath()

      let perpendicular = CGPoint(x: -uy, y: ux)
      let base = CGPoint(x: tip.x - ux * 0.9, y: tip.y - uy * 0.9)
      context.beginPath()
      context.move(to: tip)
      context.addLine(
        to: CGPoint(x: base.x + perpendicular.x * 0.48, y: base.y + perpendicular.y * 0.48))
      context.addLine(
        to: CGPoint(x: base.x - perpendicular.x * 0.48, y: base.y - perpendicular.y * 0.48))
      context.closePath()
      context.fillPath()
    }
    context.restoreGState()
  }

  private func drawVillagePOIs(
    context: CGContext,
    villages: [MapVillageHit],
    startBlockX: Int64,
    startBlockZ: Int64
  ) {
    context.saveGState()
    context.setFillColor(UIColor.systemPurple.cgColor)
    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(0.2)
    for hit in villages {
      for poi in hit.feature.pointsOfInterest {
        let x = CGFloat(poi.x - startBlockX) + 0.5
        let z = CGFloat(poi.z - startBlockZ) + 0.5
        let rect = CGRect(x: x - 0.55, y: z - 0.55, width: 1.1, height: 1.1)
        context.fill(rect)
        context.stroke(rect)
      }
    }
    context.restoreGState()
  }


  private func drawUngeneratedChunkAirBase(context: CGContext, in rect: CGRect) {
    context.setFillColor(UIColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1).cgColor)
    context.fill(rect)
  }

  private func drawUngeneratedChunkPlaceholder(
    context: CGContext,
    in rect: CGRect,
    displayMode: MapUngeneratedChunkDisplayMode
  ) {
    switch displayMode {
    case .transparent:
      break
    case .air:
      drawUngeneratedChunkAirBase(context: context, in: rect)
    case .texture:
      drawUngeneratedChunkTexture(context: context, rects: [rect], chunkSide: min(rect.width, rect.height))
    }
  }

  private func drawUngeneratedChunkTexture(
    context: CGContext,
    rects: [CGRect],
    chunkSide: CGFloat
  ) {
    let validRects = rects.filter { $0.width > 0 && $0.height > 0 }
    guard !validRects.isEmpty, chunkSide > 0 else { return }

    for rect in validRects {
      drawUngeneratedChunkAirBase(context: context, in: rect)
    }

    let minX = validRects.map(\.minX).min() ?? 0
    let minY = validRects.map(\.minY).min() ?? 0
    let maxX = validRects.map(\.maxX).max() ?? 0
    let maxY = validRects.map(\.maxY).max() ?? 0
    let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    guard !bounds.isEmpty else { return }

    let spacing = max(2.0, chunkSide * 0.5)
    let lineWidth = max(1.0, (chunkSide * 0.075).rounded(.toNearestOrAwayFromZero))
    let margin = bounds.width + bounds.height + lineWidth * 4
    let minIntercept = bounds.minY - bounds.maxX - margin
    let maxIntercept = bounds.maxY - bounds.minX + margin

    func alignedStart(for value: CGFloat, step: CGFloat) -> CGFloat {
      return floor(value / step) * step
    }

    context.saveGState()
    let clip = CGMutablePath()
    for rect in validRects {
      let alignedMinX = rect.minX.rounded(.toNearestOrAwayFromZero)
      let alignedMaxX = rect.maxX.rounded(.toNearestOrAwayFromZero)
      let alignedMinY = rect.minY.rounded(.toNearestOrAwayFromZero)
      let alignedMaxY = rect.maxY.rounded(.toNearestOrAwayFromZero)
      clip.addRect(
        CGRect(
          x: alignedMinX,
          y: alignedMinY,
          width: max(1, alignedMaxX - alignedMinX),
          height: max(1, alignedMaxY - alignedMinY)
        )
      )
    }
    context.addPath(clip)
    context.clip()
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.setLineCap(.square)
    context.setLineJoin(.miter)
    context.setStrokeColor(UIColor(white: 0.66, alpha: 1.0).cgColor)
    context.setLineWidth(lineWidth)

    let start = alignedStart(for: minIntercept, step: spacing)
    var intercept = start
    context.beginPath()
    while intercept <= maxIntercept {
      context.move(to: CGPoint(x: bounds.minX - margin, y: bounds.minX - margin + intercept))
      context.addLine(to: CGPoint(x: bounds.maxX + margin, y: bounds.maxX + margin + intercept))
      intercept += spacing
    }
    context.strokePath()
    context.restoreGState()
  }


  private func composeExportImage(
    base: UIImage,
    startBlockX: Int64,
    startBlockZ: Int64,
    worldObjectHits: [MapWorldObjectHit],
    hardcodedSpawnerHits: [MapHardcodedSpawnerHit],
    villageHits: [MapVillageHit],
    spawnHits: [MapSpawnHit],
    layers: MapImageExportLayers
  ) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = layers.ungeneratedDisplay == .air
    format.scale = base.scale
    return UIGraphicsImageRenderer(size: base.size, format: format).image { context in
      context.cgContext.interpolationQuality = .none
      base.draw(in: CGRect(origin: .zero, size: base.size))

      if layers.villages {
        for hit in villageHits {
          drawVillage(
            context: context.cgContext,
            feature: hit.feature,
            startBlockX: startBlockX,
            startBlockZ: startBlockZ
          )
        }
      }
      if layers.hardcodedSpawners {
        for hit in hardcodedSpawnerHits {
          drawHardcodedSpawner(
            context: context.cgContext,
            area: hit.area,
            startBlockX: startBlockX,
            startBlockZ: startBlockZ
          )
        }
      }
      if layers.blockEntities {
        for hit in worldObjectHits where hit.isNormallyVisible && hit.object.kind == .blockEntity {
          drawWorldObject(
            context: context.cgContext, x: hit.localX, z: hit.localZ, kind: .blockEntity)
        }
      }
      if layers.entities {
        for hit in worldObjectHits where hit.isNormallyVisible && hit.object.kind == .entity {
          drawWorldObject(context: context.cgContext, x: hit.localX, z: hit.localZ, kind: .entity)
        }
      }
      if layers.spawnPoints {
        for hit in spawnHits { drawSpawnMarker(context: context.cgContext, hit: hit) }
      }
      if layers.villages && layers.entities {
        drawVillagePOILinks(
          context: context.cgContext,
          links: villagePOILinks(villages: villageHits, worldObjects: worldObjectHits),
          startBlockX: startBlockX,
          startBlockZ: startBlockZ
        )
      }
      if layers.villages {
        drawVillagePOIs(
          context: context.cgContext,
          villages: villageHits,
          startBlockX: startBlockX,
          startBlockZ: startBlockZ
        )
      }
    }
  }

  @objc private func shareRenderedMap() {
    let verticalSlice = currentSliceAxis != .y
    let controller = MapExportOptionsViewController(
      layers: MapImageExportLayers(
        entities: showEntities,
        blockEntities: showBlockEntities,
        hardcodedSpawners: showHardcodedSpawners,
        villages: verticalSlice ? false : showVillages,
        spawnPoints: showSpawnPoints,
        grid: false,
        ungeneratedDisplay: verticalSlice ? .air : .transparent
      ),
      hasSelectedRegion: !verticalSlice && isSelectionMode && selectedRegion != nil,
      isCrossSection: verticalSlice
    )
    controller.onExport = { [weak self] scope, layers in
      self?.startMapImageExport(scope: scope, layers: layers)
    }
    let navigation = UINavigationController(rootViewController: controller)
    navigation.modalPresentationStyle = .formSheet
    present(navigation, animated: true)
  }

  private func startMapImageExport(scope: MapImageExportScope, layers: MapImageExportLayers) {
    guard lastRenderedImage != nil else {
      showError(MCBEEditorError.unsupported("请先渲染地图。"), title: "无法导出地图")
      return
    }
    if currentSliceAxis != .y {
      startCrossSectionImageExport(scope: scope, layers: layers)
      return
    }

    let busyText: String
    switch scope {
    case .selectedRegion: busyText = "正在生成当前框选区域图片…"
    case .currentRegion: busyText = "正在生成当前地图图片…"
    case .loadedDimension: busyText = "正在读取当前维度全部已加载区域…"
    }
    let overlay = showBusy(busyText)
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let dimensionName = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].displayName
    let mode = currentMode
    let drawGrid = layers.grid
    let centerX = lastCenterX
    let centerZ = lastCenterZ
    let sideChunks = renderedSideChunks
    let leftChunks = renderedLeftChunks
    let scanRadius = renderedScanRadius
    let selectedExportRegion = isSelectionMode ? selectedRegion : nil
    let selectedSpawns =
      layers.spawnPoints ? spawnCoordinates.filter { $0.dimension == dimension } : []

    renderQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let renderer = try self.rendererForCurrentSession()
        let database = try self.session.database()
        let villageFeatures =
          layers.villages
          ? try VillageNBTStore(session: self.session).mapFeatures().features.filter {
            $0.dimension == dimension
          }
          : []
        let exportTickingAreas: [BedrockTickingArea]
        if mode == .tickingAreas {
          exportTickingAreas = try TickingAreaStore(session: self.session)
            .records()
            .map { $0.area }
            .filter { $0.dimension == dimension }
        } else {
          exportTickingAreas = []
        }

        let image: UIImage
        let exportSuffix: String
        switch scope {
        case .selectedRegion, .currentRegion:
          let exportCenterX: Int32
          let exportCenterZ: Int32
          let exportSideChunks: Int
          let exportLeftChunks: Int
          let exportScanRadius: Int
          let cropRegion: BedrockMapRegion?

          if scope == .selectedRegion {
            guard let region = selectedExportRegion, region.dimension == dimension else {
              throw MCBEEditorError.unsupported("当前没有可导出的框选区域。")
            }
            let widthChunks = Int(Int64(region.maximumChunkX) - Int64(region.minimumChunkX) + 1)
            let depthChunks = Int(Int64(region.maximumChunkZ) - Int64(region.minimumChunkZ) + 1)
            let side = max(1, max(widthChunks, depthChunks))
            let left = (side - 1) / 2
            exportSideChunks = side
            exportLeftChunks = left
            exportCenterX = Int32(clamping: Int64(region.minimumChunkX) + Int64(left))
            exportCenterZ = Int32(clamping: Int64(region.minimumChunkZ) + Int64(left))
            exportScanRadius = max(left, side - left - 1)
            cropRegion = region
          } else {
            exportCenterX = centerX
            exportCenterZ = centerZ
            exportSideChunks = sideChunks
            exportLeftChunks = leftChunks
            exportScanRadius = scanRadius
            cropRegion = nil
          }

          var objects = [BedrockWorldObject]()
          if layers.entities || layers.blockEntities {
            let scan = try BedrockWorldObjectScanner(database: database).scanRegionAdaptive(
              centerX: exportCenterX,
              centerZ: exportCenterZ,
              dimension: dimension,
              radius: exportScanRadius,
              includeEntities: layers.entities,
              includeBlockEntities: layers.blockEntities,
              maximumObjects: 100_000
            )
            objects = scan.objects
          }
          if layers.villages {
            objects.append(contentsOf: villageFeatures.flatMap(\.residentEntities))
          }
          let uniqueObjects = Dictionary(
            objects.map { ($0.stableID, $0) },
            uniquingKeysWith: { current, candidate in
              current.source == .modernActor ? current : candidate
            }
          ).map(\.value)
          let spawnerScan =
            layers.hardcodedSpawners
            ? try self.scanHardcodedSpawners(
              database: database,
              centerX: exportCenterX,
              centerZ: exportCenterZ,
              dimension: dimension,
              sideChunks: exportSideChunks,
              leftChunks: exportLeftChunks,
              shouldCancel: { false }
            )
            : (hits: [MapHardcodedSpawnerHit](), diagnostics: [String]())
          let generatedChunkPositions = Set(try BedrockChunkStore(session: self.session).listChunks().filter { summary in
            summary.position.dimension == dimension
              && (summary.hasTerrain || summary.biomeRecordType != nil
                  || summary.hasBlockEntities || summary.hasLegacyEntities
                  || summary.recordCount > (summary.hasActorDigest ? 1 : 0))
          }.map(\.position))
          let rendered = try self.renderRegion(
            renderer: renderer,
            centerX: exportCenterX,
            centerZ: exportCenterZ,
            dimension: dimension,
            sideChunks: exportSideChunks,
            leftChunks: exportLeftChunks,
            mode: mode,
            drawGrid: drawGrid,
            generatedChunkPositions: generatedChunkPositions,
            ungeneratedDisplay: layers.ungeneratedDisplay,
            spawnCoordinates: selectedSpawns,
            playerCoordinates: [],
            worldObjects: uniqueObjects,
            displayEntities: layers.entities,
            displayBlockEntities: layers.blockEntities,
            hardcodedSpawnerHits: spawnerScan.hits,
            villageFeatures: villageFeatures,
            tickingAreas: exportTickingAreas,
            additionalErrors: spawnerScan.diagnostics,
            shouldCancel: { false }
          )
          let startBlockX = MapCoordinate.blockOrigin(
            ofChunk: exportCenterX - Int32(exportLeftChunks))
          let startBlockZ = MapCoordinate.blockOrigin(
            ofChunk: exportCenterZ - Int32(exportLeftChunks))
          let composed = self.composeExportImage(
            base: rendered.image,
            startBlockX: startBlockX,
            startBlockZ: startBlockZ,
            worldObjectHits: rendered.worldObjectHits,
            hardcodedSpawnerHits: rendered.hardcodedSpawnerHits,
            villageHits: rendered.villageHits,
            spawnHits: rendered.spawnHits,
            layers: layers
          )
          if let region = cropRegion {
            image = try self.cropMapExportImage(
              composed,
              startBlockX: startBlockX,
              startBlockZ: startBlockZ,
              sideBlocks: exportSideChunks * 16,
              region: region
            )
            exportSuffix =
              "selection-\(region.minimumX)-\(region.minimumZ)-\(region.maximumX)-\(region.maximumZ)"
          } else {
            image = composed
            exportSuffix = "current-\(centerX)-\(centerZ)"
          }

        case .loadedDimension:
          let summaries = try BedrockChunkStore(session: self.session).listChunks().filter {
            $0.position.dimension == dimension
              && ($0.hasTerrain || $0.biomeRecordType != nil)
          }
          guard !summaries.isEmpty else {
            throw MCBEEditorError.unsupported("当前维度没有可导出的已加载区块。")
          }
          let positions: [ChunkPosition] = summaries.map { $0.position }
          let base = try self.renderLoadedDimensionBase(
            renderer: renderer,
            positions: positions,
            mode: mode,
            drawGrid: drawGrid,
            ungeneratedDisplay: layers.ungeneratedDisplay
          )

          var objects = [BedrockWorldObject]()
          if layers.entities || layers.blockEntities {
            let scan = try BedrockWorldObjectScanner(database: database).scanAll(
              dimensions: Set([dimension]),
              includeEntities: layers.entities,
              includeBlockEntities: layers.blockEntities,
              maximumObjects: 1_000_000
            )
            objects = scan.objects
          }
          if layers.villages {
            objects.append(contentsOf: villageFeatures.flatMap(\.residentEntities))
          }
          let uniqueObjects = Dictionary(
            objects.map { ($0.stableID, $0) },
            uniquingKeysWith: { current, candidate in
              current.source == .modernActor ? current : candidate
            }
          ).map(\.value)
          let worldHits = self.makeExportWorldObjectHits(
            objects: uniqueObjects,
            villages: villageFeatures,
            startBlockX: base.startBlockX,
            startBlockZ: base.startBlockZ,
            widthBlocks: base.widthBlocks,
            heightBlocks: base.heightBlocks,
            layers: layers
          )
          let spawnerHits =
            layers.hardcodedSpawners
            ? try self.scanHardcodedSpawners(
              database: database,
              positions: summaries.filter { $0.hasHardcodedSpawners }.map { $0.position }
            ).hits
            : []
          let villageHits = self.makeExportVillageHits(
            features: villageFeatures,
            startBlockX: base.startBlockX,
            startBlockZ: base.startBlockZ,
            widthBlocks: base.widthBlocks,
            heightBlocks: base.heightBlocks
          )
          let spawnHits = selectedSpawns.compactMap { spawn -> MapSpawnHit? in
            guard spawn.x >= base.startBlockX,
              spawn.x < base.startBlockX + Int64(base.widthBlocks),
              spawn.z >= base.startBlockZ,
              spawn.z < base.startBlockZ + Int64(base.heightBlocks)
            else { return nil }
            return MapSpawnHit(
              spawn: spawn,
              localX: CGFloat(spawn.x - base.startBlockX) + 0.5,
              localZ: CGFloat(spawn.z - base.startBlockZ) + 0.5
            )
          }
          image = self.composeExportImage(
            base: base.image,
            startBlockX: base.startBlockX,
            startBlockZ: base.startBlockZ,
            worldObjectHits: worldHits,
            hardcodedSpawnerHits: spawnerHits,
            villageHits: villageHits,
            spawnHits: spawnHits,
            layers: layers
          )
          exportSuffix = "all-loaded"
        }

        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.shareMapImage(
            image,
            filename: "MCBEEditor-\(dimensionName)-\(mode.displayName)-\(exportSuffix).png"
          )
        }
      } catch {
        DispatchQueue.main.async {
          overlay.removeFromSuperview()
          self.showError(error, title: "导出地图失败")
        }
      }
    }
  }

  private func startCrossSectionImageExport(
    scope: MapImageExportScope,
    layers: MapImageExportLayers
  ) {
    let axis = currentSliceAxis
    guard axis == .x || axis == .z else { return }
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let dimensionName = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].displayName
    let mode = currentMode
    let fixedX = sliceCenterBlockX
    let fixedZ = sliceCenterBlockZ
    let centerY = sliceCenterY
    let drawGrid = layers.grid
    let includeBuildLimits = showBuildHeightLimits
    let currentHorizontalRange = renderedCrossHorizontalStart...(
      renderedCrossHorizontalStart + Int64(renderedSideChunks * 16) - 1)
    let currentVerticalRange = renderedCrossMinimumY...renderedCrossMaximumY
    let busy = showBusy(
      scope == .loadedDimension ? "正在遍历全部已加载剖面…" : "正在生成当前剖面图片…")

    renderQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        let renderer = try self.rendererForCurrentSession()
        let database = try self.session.database()
        let allSummaries = try BedrockChunkStore(session: self.session).listChunks().filter {
          $0.position.dimension == dimension
            && ($0.hasTerrain || $0.biomeRecordType != nil || $0.hasBlockEntities
                || $0.hasLegacyEntities || $0.recordCount > ($0.hasActorDigest ? 1 : 0))
        }
        let horizontalRange: ClosedRange<Int64>
        let verticalRange: ClosedRange<Int64>
        let exportSuffix: String
        let intersectingSummaries: [BedrockChunkSummary]

        if scope == .loadedDimension {
          let projectionMaximum = axis == .x ? fixedX : fixedZ
          let projectionNegativeDistance: Int64 = mode == .xray ? 128 : 127
          let projectionMinimum = projectionMaximum - projectionNegativeDistance
          let minimumFixedChunk = MapCoordinate.chunk(fromBlock: projectionMinimum)
          let maximumFixedChunk = MapCoordinate.chunk(fromBlock: projectionMaximum)
          intersectingSummaries = allSummaries.filter {
            let fixedChunkCoordinate = axis == .x ? $0.position.x : $0.position.z
            return fixedChunkCoordinate >= minimumFixedChunk
              && fixedChunkCoordinate <= maximumFixedChunk
          }
          guard !intersectingSummaries.isEmpty else {
            throw MCBEEditorError.unsupported("当前剖面没有已加载区块。")
          }
          let horizontalChunks = intersectingSummaries.map {
            axis == .x ? $0.position.z : $0.position.x
          }
          guard let minimumChunk = horizontalChunks.min(), let maximumChunk = horizontalChunks.max()
          else { throw MCBEEditorError.unsupported("当前剖面没有已加载区块。") }
          horizontalRange = MapCoordinate.blockOrigin(ofChunk: minimumChunk)...(
            MapCoordinate.blockOrigin(ofChunk: maximumChunk) + 15)

          var minimumSubY: Int64?
          var maximumSubY: Int64?
          for summary in intersectingSummaries {
            let records = try BedrockChunkSubChunkAccess.records(
              database: database, position: summary.position)
            for record in records {
              let base = Int64(record.yIndex) * 16
              minimumSubY = min(minimumSubY ?? base, base)
              maximumSubY = max(maximumSubY ?? (base + 15), base + 15)
            }
          }
          if let minimumSubY = minimumSubY, let maximumSubY = maximumSubY {
            verticalRange = minimumSubY...maximumSubY
          } else {
            switch BedrockDimension(rawValue: dimension) {
            case .nether?: verticalRange = 0...127
            case .end?: verticalRange = 0...255
            default: verticalRange = -64...319
            }
          }
          exportSuffix = "all-loaded-\(axis.displayName.lowercased())"
        } else {
          intersectingSummaries = allSummaries
          horizontalRange = currentHorizontalRange
          verticalRange = currentVerticalRange
          exportSuffix = "current-\(axis.displayName.lowercased())-\(axis == .x ? fixedX : fixedZ)"
        }

        let horizontalCount = horizontalRange.upperBound - horizontalRange.lowerBound + 1
        let verticalCount = verticalRange.upperBound - verticalRange.lowerBound + 1
        guard horizontalCount > 0, verticalCount > 0,
          horizontalCount <= 200_000, verticalCount <= 20_000
        else {
          throw MCBEEditorError.unsupported("剖面跨度过大，无法生成单张图片。")
        }

        var tickingAreas = [BedrockTickingArea]()
        if mode == .tickingAreas {
          tickingAreas = try TickingAreaStore(session: self.session).records()
            .map(\.area).filter { $0.dimension == dimension }
        }

        let rendered = try renderer.renderCrossSection(
          axis: axis,
          fixedX: fixedX,
          fixedZ: fixedZ,
          centerY: centerY,
          sideBlocks: max(16, renderedSideChunks * 16),
          dimension: dimension,
          mode: mode,
          drawSubChunkGrid: drawGrid,
          projectionDepth: 128,
          pixelsPerBlock: 4,
          maximumRasterSide: 4096,
          showUngeneratedSubChunks: layers.ungeneratedDisplay == .texture,
          transparentUngeneratedSubChunks: layers.ungeneratedDisplay == .transparent,
          airUngeneratedSubChunks: layers.ungeneratedDisplay == .air,
          tickingAreas: tickingAreas,
          horizontalRange: horizontalRange,
          verticalRange: verticalRange,
          shouldCancel: { false }
        )

        var objects = [BedrockWorldObject]()
        if layers.entities || layers.blockEntities {
          let scan = try BedrockWorldObjectScanner(database: database).scanAll(
            dimensions: Set([dimension]),
            includeEntities: layers.entities,
            includeBlockEntities: layers.blockEntities,
            maximumObjects: 1_000_000
          )
          objects = scan.objects
        }

        let spawnerHits: [MapHardcodedSpawnerHit]
        if layers.hardcodedSpawners {
          let spawnerPositions = allSummaries.filter(\.hasHardcodedSpawners).map(\.position)
          spawnerHits = try self.scanHardcodedSpawners(
            database: database, positions: spawnerPositions).hits
        } else {
          spawnerHits = []
        }

        let image = self.composeCrossSectionExportImage(
          base: rendered.image,
          axis: axis,
          fixedX: fixedX,
          fixedZ: fixedZ,
          minimumHorizontal: horizontalRange.lowerBound,
          maximumHorizontal: horizontalRange.upperBound,
          minimumY: verticalRange.lowerBound,
          maximumY: verticalRange.upperBound,
          dimension: dimension,
          objects: objects,
          hardcodedSpawnerHits: spawnerHits,
          spawnCoordinates: layers.spawnPoints
            ? self.spawnCoordinates.filter { $0.dimension == dimension } : [],
          layers: layers,
          showBuildHeightLimits: includeBuildLimits
        )

        DispatchQueue.main.async {
          busy.removeFromSuperview()
          self.shareMapImage(
            image,
            filename: "MCBEEditor-\(dimensionName)-\(mode.displayName)-\(exportSuffix).png"
          )
        }
      } catch {
        DispatchQueue.main.async {
          busy.removeFromSuperview()
          self.showError(error, title: "导出剖面失败")
        }
      }
    }
  }

  private func composeCrossSectionExportImage(
    base: UIImage,
    axis: MapSliceAxis,
    fixedX: Int64,
    fixedZ: Int64,
    minimumHorizontal: Int64,
    maximumHorizontal: Int64,
    minimumY: Int64,
    maximumY: Int64,
    dimension: Int32,
    objects: [BedrockWorldObject],
    hardcodedSpawnerHits: [MapHardcodedSpawnerHit],
    spawnCoordinates: [MapSpawnCoordinate],
    layers: MapImageExportLayers,
    showBuildHeightLimits: Bool
  ) -> UIImage {
    let horizontalCount = CGFloat(maximumHorizontal - minimumHorizontal + 1)
    let verticalCount = CGFloat(maximumY - minimumY + 1)
    guard horizontalCount > 0, verticalCount > 0 else { return base }
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = false
    format.scale = base.scale
    return UIGraphicsImageRenderer(size: base.size, format: format).image { context in
      base.draw(in: CGRect(origin: .zero, size: base.size))
      let cg = context.cgContext
      let scaleX = base.size.width / horizontalCount
      let scaleY = base.size.height / verticalCount

      func point(horizontal: Double, y: Double) -> CGPoint {
        CGPoint(
          x: CGFloat(horizontal - Double(minimumHorizontal)) * scaleX,
          y: CGFloat(Double(maximumY + 1) - y) * scaleY
        )
      }

      for object in objects {
        guard let position = object.position else { continue }
        let planeDistance = axis == .x
          ? abs(position.x - Double(fixedX))
          : abs(position.z - Double(fixedZ))
        guard planeDistance <= crossSectionObjectPlaneTolerance else { continue }
        let horizontal = axis == .x ? position.z : position.x
        guard horizontal >= Double(minimumHorizontal), horizontal < Double(maximumHorizontal + 1),
          position.y >= Double(minimumY), position.y < Double(maximumY + 1)
        else { continue }
        let p = point(horizontal: horizontal, y: position.y)
        if object.kind == .entity, layers.entities {
          UIColor.systemBlue.setFill()
          cg.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        } else if object.kind == .blockEntity, layers.blockEntities {
          UIColor.systemTeal.setFill()
          cg.fill(CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
        }
      }

      if layers.hardcodedSpawners {
        cg.saveGState()
        cg.setStrokeColor(UIColor.systemPink.cgColor)
        cg.setLineWidth(1.5)
        cg.setLineDash(phase: 0, lengths: [6, 4])
        for hit in hardcodedSpawnerHits {
          let area = hit.area
          let intersects = axis == .x
            ? fixedX >= Int64(area.minimumX) && fixedX <= Int64(area.maximumX)
            : fixedZ >= Int64(area.minimumZ) && fixedZ <= Int64(area.maximumZ)
          guard intersects else { continue }
          let h0 = axis == .x ? Int64(area.minimumZ) : Int64(area.minimumX)
          let h1 = axis == .x ? Int64(area.maximumZ) : Int64(area.maximumX)
          let clippedH0 = max(h0, minimumHorizontal)
          let clippedH1 = min(h1, maximumHorizontal)
          let clippedY0 = max(Int64(area.minimumY), minimumY)
          let clippedY1 = min(Int64(area.maximumY), maximumY)
          guard clippedH0 <= clippedH1, clippedY0 <= clippedY1 else { continue }
          let a = point(horizontal: Double(clippedH0), y: Double(clippedY1 + 1))
          let b = point(horizontal: Double(clippedH1 + 1), y: Double(clippedY0))
          cg.stroke(CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(b.x - a.x), height: abs(b.y - a.y)))
        }
        cg.restoreGState()
      }

      if layers.spawnPoints {
        for spawn in spawnCoordinates {
          guard let y = spawn.y else { continue }
          let blockOnPlane = axis == .x ? spawn.x == fixedX : spawn.z == fixedZ
          guard blockOnPlane else { continue }
          let horizontal = axis == .x ? spawn.z : spawn.x
          guard horizontal >= minimumHorizontal, horizontal <= maximumHorizontal,
            y >= minimumY, y <= maximumY
          else { continue }
          let p = point(horizontal: Double(horizontal) + 0.5, y: Double(y) + 0.5)
          (spawn.kind == .world ? UIColor.systemYellow : UIColor.systemGreen).setFill()
          cg.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }
      }

      if showBuildHeightLimits {
        let limits: (Int64, Int64)
        switch BedrockDimension(rawValue: dimension) {
        case .nether?: limits = (0, 128)
        case .end?: limits = (0, 256)
        default: limits = (-64, 320)
        }
        cg.saveGState()
        cg.setStrokeColor(UIColor.systemRed.cgColor)
        cg.setLineWidth(1.5)
        cg.setLineDash(phase: 0, lengths: [8, 5])
        for y in [limits.0, limits.1] {
          let p = point(horizontal: Double(minimumHorizontal), y: Double(y))
          if p.y >= -2, p.y <= base.size.height + 2 {
            cg.move(to: CGPoint(x: 0, y: p.y))
            cg.addLine(to: CGPoint(x: base.size.width, y: p.y))
          }
        }
        cg.strokePath()
        cg.restoreGState()
      }
    }
  }

  private func cropMapExportImage(
    _ image: UIImage,
    startBlockX: Int64,
    startBlockZ: Int64,
    sideBlocks: Int,
    region: BedrockMapRegion
  ) throws -> UIImage {
    guard sideBlocks > 0, image.size.width > 0, image.size.height > 0 else {
      throw MCBEEditorError.malformedData("地图导出裁剪尺寸无效。")
    }
    let scaleX = image.size.width / CGFloat(sideBlocks)
    let scaleZ = image.size.height / CGFloat(sideBlocks)
    let cropRect = CGRect(
      x: CGFloat(region.minimumX - startBlockX) * scaleX,
      y: CGFloat(region.minimumZ - startBlockZ) * scaleZ,
      width: CGFloat(region.width) * scaleX,
      height: CGFloat(region.depth) * scaleZ
    ).intersection(CGRect(origin: .zero, size: image.size))
    guard !cropRect.isNull, cropRect.width > 0, cropRect.height > 0 else {
      throw MCBEEditorError.unsupported("框选区域不在本次渲染范围内。")
    }

    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = false
    format.scale = image.scale
    return UIGraphicsImageRenderer(size: cropRect.size, format: format).image { _ in
      image.draw(at: CGPoint(x: -cropRect.minX, y: -cropRect.minY))
    }
  }

  private func renderLoadedDimensionBase(
    renderer: ChunkSurfaceRenderer,
    positions: [ChunkPosition],
    mode: MapRenderMode,
    drawGrid: Bool,
    ungeneratedDisplay: MapUngeneratedChunkDisplayMode
  ) throws -> (
    image: UIImage, startBlockX: Int64, startBlockZ: Int64, widthBlocks: Int, heightBlocks: Int
  ) {
    guard let minimumX = positions.map(\.x).min(), let maximumX = positions.map(\.x).max(),
      let minimumZ = positions.map(\.z).min(), let maximumZ = positions.map(\.z).max()
    else {
      throw MCBEEditorError.unsupported("没有可导出的区块。")
    }
    let widthChunks = Int64(maximumX) - Int64(minimumX) + 1
    let heightChunks = Int64(maximumZ) - Int64(minimumZ) + 1
    let widthBlocks64 = widthChunks * 16
    let heightBlocks64 = heightChunks * 16
    guard widthBlocks64 > 0, heightBlocks64 > 0,
      widthBlocks64 <= 200_000, heightBlocks64 <= 200_000
    else {
      throw MCBEEditorError.unsupported("已加载区域跨度过大，无法生成单张图片。")
    }
    let widthBlocks = Int(widthBlocks64)
    let heightBlocks = Int(heightBlocks64)
    let longest = CGFloat(max(widthBlocks, heightBlocks))
    let outputScale = min(4.0, max(0.02, 6144.0 / max(longest, 1)))
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = ungeneratedDisplay == .air
    format.scale = outputScale
    let positionSet = Set(positions)
    var images = [(position: ChunkPosition, image: UIImage)]()
    images.reserveCapacity(positions.count)
    for position in positions.sorted(by: { lhs, rhs in
      lhs.z == rhs.z ? lhs.x < rhs.x : lhs.z < rhs.z
    }) {
      let result = try renderer.renderChunk(
        x: position.x, z: position.z, dimension: position.dimension, mode: mode
      ).result
      images.append((position, result.image))
    }
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: widthBlocks, height: heightBlocks),
      format: format
    ).image { context in
      context.cgContext.interpolationQuality = .none
      context.cgContext.setAllowsAntialiasing(false)
      if ungeneratedDisplay == .air {
        UIColor.systemGray5.setFill()
        context.fill(CGRect(x: 0, y: 0, width: widthBlocks, height: heightBlocks))
      }
      var ungeneratedTextureRects = [CGRect]()
      if ungeneratedDisplay != .transparent {
        for z in minimumZ...maximumZ {
          for x in minimumX...maximumX {
            let position = ChunkPosition(x: x, z: z, dimension: positions.first?.dimension ?? 0)
            guard !positionSet.contains(position) else { continue }
            let rect = CGRect(
              x: Int(Int64(x) - Int64(minimumX)) * 16,
              y: Int(Int64(z) - Int64(minimumZ)) * 16,
              width: 16,
              height: 16
            )
            if ungeneratedDisplay == .texture {
              ungeneratedTextureRects.append(rect)
            } else {
              drawUngeneratedChunkPlaceholder(context: context.cgContext, in: rect, displayMode: ungeneratedDisplay)
            }
          }
        }
      }
      for item in images {
        let x = Int(Int64(item.position.x) - Int64(minimumX)) * 16
        let z = Int(Int64(item.position.z) - Int64(minimumZ)) * 16
        item.image.draw(in: CGRect(x: x, y: z, width: 16, height: 16))
      }
      if drawGrid {
        context.cgContext.setStrokeColor(UIColor.label.withAlphaComponent(0.34).cgColor)
        context.cgContext.setLineWidth(max(0.18, 1.0 / max(outputScale, 0.02)))
        for z in minimumZ...maximumZ {
          for x in minimumX...maximumX {
            let rect = CGRect(
              x: Int(Int64(x) - Int64(minimumX)) * 16,
              y: Int(Int64(z) - Int64(minimumZ)) * 16,
              width: 16,
              height: 16
            )
            context.cgContext.stroke(rect)
          }
        }
      }
      if ungeneratedDisplay == .texture, !ungeneratedTextureRects.isEmpty {
        drawUngeneratedChunkTexture(
          context: context.cgContext,
          rects: ungeneratedTextureRects,
          chunkSide: 16
        )
      }
    }
    return (
      image,
      MapCoordinate.blockOrigin(ofChunk: minimumX),
      MapCoordinate.blockOrigin(ofChunk: minimumZ),
      widthBlocks,
      heightBlocks
    )
  }

  private func makeExportWorldObjectHits(
    objects: [BedrockWorldObject],
    villages: [VillageMapFeature],
    startBlockX: Int64,
    startBlockZ: Int64,
    widthBlocks: Int,
    heightBlocks: Int,
    layers: MapImageExportLayers
  ) -> [MapWorldObjectHit] {
    let endBlockX = startBlockX + Int64(widthBlocks)
    let endBlockZ = startBlockZ + Int64(heightBlocks)
    let residentIDs = Set(villages.flatMap(\.residentEntities).map(\.stableID))
    return objects.compactMap { object in
      let normallyVisible =
        (object.kind == .entity && layers.entities)
        || (object.kind == .blockEntity && layers.blockEntities)
      guard normallyVisible || residentIDs.contains(object.stableID),
        let position = object.position,
        position.blockX >= startBlockX, position.blockX < endBlockX,
        position.blockZ >= startBlockZ, position.blockZ < endBlockZ
      else { return nil }
      return MapWorldObjectHit(
        object: object,
        localX: CGFloat(position.x - Double(startBlockX)),
        localZ: CGFloat(position.z - Double(startBlockZ)),
        isNormallyVisible: normallyVisible
      )
    }
  }

  private func makeExportVillageHits(
    features: [VillageMapFeature],
    startBlockX: Int64,
    startBlockZ: Int64,
    widthBlocks: Int,
    heightBlocks: Int
  ) -> [MapVillageHit] {
    let endBlockX = startBlockX + Int64(widthBlocks)
    let endBlockZ = startBlockZ + Int64(heightBlocks)
    return features.compactMap { feature in
      if let bounds = feature.bounds {
        guard bounds.maximumX >= startBlockX, bounds.minimumX < endBlockX,
          bounds.maximumZ >= startBlockZ, bounds.minimumZ < endBlockZ
        else { return nil }
      } else if let center = feature.center {
        guard center.x >= startBlockX, center.x < endBlockX,
          center.z >= startBlockZ, center.z < endBlockZ
        else { return nil }
      } else if !feature.pointsOfInterest.contains(where: {
        $0.x >= startBlockX && $0.x < endBlockX && $0.z >= startBlockZ && $0.z < endBlockZ
      }) {
        return nil
      }
      return MapVillageHit(feature: feature)
    }
  }

  private func scanHardcodedSpawners(
    database: MojangLevelDB,
    positions: [ChunkPosition]
  ) throws -> (hits: [MapHardcodedSpawnerHit], diagnostics: [String]) {
    var hits = [MapHardcodedSpawnerHit]()
    var diagnostics = [String]()
    for position in positions {
      let key = BedrockDBKey(position: position, recordType: .hardcodedSpawners, subChunkIndex: nil)
        .encoded()
      guard let raw = try database.get(key) else { continue }
      do {
        let document = try HardcodedSpawnersDocument.decode(raw)
        for (index, area) in document.areas.enumerated() {
          hits.append(MapHardcodedSpawnerHit(area: area, ownerChunk: position, areaIndex: index))
        }
      } catch {
        diagnostics.append(
          "HardcodedSpawners (\(position.x),\(position.z)): \(error.localizedDescription)")
      }
    }
    return (hits, diagnostics)
  }

  private func shareMapImage(_ image: UIImage, filename: String) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    do {
      guard let data = image.pngData() else { throw MCBEEditorError.io("无法编码 PNG") }
      try data.write(to: url, options: .atomic)

      // Share exactly one item: the named PNG file. Passing both UIImage and
      // URL makes UIActivityViewController treat them as two separate items,
      // so destinations such as AirDrop/Files/Photos can show two identical
      // images. The .png URL is sufficient for the system share sheet and
      // keeps image-specific activities such as Save Image available.
      let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      controller.popoverPresentationController?.barButtonItem = shareButton
      if let popover = controller.popoverPresentationController, popover.barButtonItem == nil {
        popover.sourceView = view
        popover.sourceRect = CGRect(
          x: view.bounds.midX, y: view.bounds.minY + 1, width: 1, height: 1)
      }
      present(controller, animated: true)
    } catch {
      showError(error, title: "导出地图失败")
    }
  }

  private var mapStatePrefix: String { "MCBEEditor.Map.\(session.world.id.uuidString)." }

  /// Restores display preferences only. Viewport center, selected dimension
  /// and zoom are intentionally session-local and are never restored after
  /// the world workspace is closed.
  @discardableResult
  private func restoreMapState() -> Bool {
    let defaults = UserDefaults.standard
    modeControl.selectedSegmentIndex = 0
    defaults.removeObject(forKey: mapStatePrefix + "mode")
    coordinateModeControl.selectedSegmentIndex = min(
      1, max(0, defaults.integer(forKey: mapStatePrefix + "coordinateMode")))
    if defaults.object(forKey: mapStatePrefix + "autoRender") != nil {
      autoRenderSwitch.isOn = defaults.bool(forKey: mapStatePrefix + "autoRender")
      gridSwitch.isOn = defaults.bool(forKey: mapStatePrefix + "grid")
      chunkSelectionSwitch.isOn = defaults.bool(forKey: mapStatePrefix + "chunkSelection")
    }
    if defaults.object(forKey: mapStatePrefix + "showPlayers") != nil {
      showPlayers = defaults.bool(forKey: mapStatePrefix + "showPlayers")
    } else {
      showPlayers = true
    }
    if defaults.object(forKey: mapStatePrefix + "showEntities") != nil {
      showEntities = defaults.bool(forKey: mapStatePrefix + "showEntities")
      showBlockEntities = defaults.bool(forKey: mapStatePrefix + "showBlockEntities")
      showHardcodedSpawners = defaults.bool(forKey: mapStatePrefix + "showHardcodedSpawners")
      showVillages = defaults.bool(forKey: mapStatePrefix + "showVillages")
      if defaults.object(forKey: mapStatePrefix + "showSpawnPoints") != nil {
        showSpawnPoints = defaults.bool(forKey: mapStatePrefix + "showSpawnPoints")
      }
      if defaults.object(forKey: mapStatePrefix + "showUngeneratedChunks") != nil {
        showUngeneratedChunks = defaults.bool(forKey: mapStatePrefix + "showUngeneratedChunks")
      }
      if defaults.object(forKey: mapStatePrefix + "showBuildHeightLimits") != nil {
        showBuildHeightLimits = defaults.bool(forKey: mapStatePrefix + "showBuildHeightLimits")
      } else {
        showBuildHeightLimits = true
      }
    } else {
      showBuildHeightLimits = true
    }
    for key in ["centerX", "centerZ", "dimension", "radius", "zoomScale"] {
      defaults.removeObject(forKey: mapStatePrefix + key)
    }
    return true
  }

  private func saveMapState() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: mapStatePrefix + "mode")
    defaults.set(
      coordinateModeControl.selectedSegmentIndex, forKey: mapStatePrefix + "coordinateMode")
    defaults.set(autoRenderSwitch.isOn, forKey: mapStatePrefix + "autoRender")
    defaults.set(gridSwitch.isOn, forKey: mapStatePrefix + "grid")
    defaults.set(chunkSelectionSwitch.isOn, forKey: mapStatePrefix + "chunkSelection")
    defaults.set(showPlayers, forKey: mapStatePrefix + "showPlayers")
    defaults.set(showEntities, forKey: mapStatePrefix + "showEntities")
    defaults.set(showBlockEntities, forKey: mapStatePrefix + "showBlockEntities")
    defaults.set(showHardcodedSpawners, forKey: mapStatePrefix + "showHardcodedSpawners")
    defaults.set(showVillages, forKey: mapStatePrefix + "showVillages")
    defaults.set(showSpawnPoints, forKey: mapStatePrefix + "showSpawnPoints")
    defaults.set(showUngeneratedChunks, forKey: mapStatePrefix + "showUngeneratedChunks")
    defaults.set(showBuildHeightLimits, forKey: mapStatePrefix + "showBuildHeightLimits")
    for key in ["centerX", "centerZ", "dimension", "radius", "zoomScale"] {
      defaults.removeObject(forKey: mapStatePrefix + key)
    }
  }

  private func rememberCurrentViewportState(for dimension: Int32) {
    guard currentSliceAxis == .y, lastRenderedImage != nil else { return }
    let anchor =
      currentViewportAnchor()
      ?? MapViewportAnchor(
        blockX: Double(MapCoordinate.blockOrigin(ofChunk: lastCenterX)) + 8,
        blockZ: Double(MapCoordinate.blockOrigin(ofChunk: lastCenterZ)) + 8,
        zoomScale: max(effectiveZoomScale, CGFloat(0.0001))
      )
    let center = chunkCenter(for: anchor)
    dimensionViewportStates[dimension] = MapDimensionViewportState(
      centerX: center.0,
      centerZ: center.1,
      anchor: anchor
    )
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    cancelInFlightRenderForUserInteraction()
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    updateObjectOverlay()
    if let region = selectedRegion { updateSelectionOverlay(for: region) }
    // Never start a new database render while UIKit still owns gesture or
    // deceleration velocity. Rendering resizes the canvas, and resizing a
    // decelerating UIScrollView can amplify contentOffset into a runaway pan.
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate {
      alignContentOffsetToDevicePixels()
      updateObjectOverlay()
      if let region = selectedRegion { updateSelectionOverlay(for: region) }
      scheduleAutoRender(immediate: true)
    }
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    alignContentOffsetToDevicePixels()
    updateObjectOverlay()
    if let region = selectedRegion { updateSelectionOverlay(for: region) }
    scheduleAutoRender(immediate: true)
  }

  func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
    cancelInFlightRenderForUserInteraction()
    // Stop any residual pan velocity before the pinch starts and widen the
    // zoom range once, rather than changing minimumZoomScale every frame.
    scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    prepareZoomRangeForUserGesture()
    isZooming = true
    showZoomHUD()
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    updateObjectOverlay()
    if let region = selectedRegion { updateSelectionOverlay(for: region) }
    guard !isApplyingViewport else { return }
    showZoomHUD(autoHide: !isZooming)
  }

  func scrollViewDidEndZooming(
    _ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat
  ) {
    let alignedScale = pixelAlignedZoomScale(scale)
    if abs(alignedScale - scrollView.zoomScale) > 0.0001 {
      isApplyingViewport = true
      scrollView.setZoomScale(alignedScale, animated: false)
      isApplyingViewport = false
    }
    alignContentOffsetToDevicePixels()
    updateObjectOverlay()
    if let region = selectedRegion { updateSelectionOverlay(for: region) }
    isZooming = false
    saveMapState()
    showZoomHUD(autoHide: true)
    refreshForZoomDrivenRadiusIfNeeded()
  }

  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    alignContentOffsetToDevicePixels()
    updateObjectOverlay()
    if let region = selectedRegion { updateSelectionOverlay(for: region) }
    refreshForZoomDrivenRadiusIfNeeded()
    scheduleAutoRender(immediate: true)
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    renderFromFields()
    return true
  }
}
