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
  private var selectedObjectID: String?

  private var allLayers: [CAShapeLayer] {
    [
      villageBoundsLayer, villageCenterLayer, villagePOILinkLayer, villagePOILayer,
      entityLayer, blockEntityLayer, localPlayerLayer, onlinePlayerLayer, hardcodedSpawnerLayer,
      worldSpawnLayer, worldSpawnGlyphLayer, playerSpawnLayer, playerSpawnGlyphLayer,
      selectedVillageLayer,
      selectedSpawnerLayer, selectedObjectLayer, selectedBlockLayer,
      selectedChunkLayer,
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

  func setSelectedObjectID(_ stableID: String?) {
    selectedObjectID = stableID
    if stableID == nil {
      selectedObjectLayer.path = nil
      selectedObjectLayer.removeAnimation(forKey: "selected-object-blink")
    }
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
  private let zField = UITextField()
  private let coordinateModeControl = UISegmentedControl(items: ["区块坐标", "方块坐标"])
  private let dimensionControl = UISegmentedControl(
    items: BedrockDimension.allCases.map(\.displayName))
  private let modeControl = UISegmentedControl(items: MapRenderMode.allCases.map(\.displayName))
  private let autoRenderSwitch = UISwitch()
  private let gridSwitch = UISwitch()
  private let chunkSelectionSwitch = UISwitch()
  private let statusLabel = UILabel()
  private let zoomLabel = UILabel()

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
    xField.text = "0"
    zField.text = "0"
    for field in [xField, zField] {
      field.borderStyle = .roundedRect
      field.keyboardType = .numbersAndPunctuation
      field.delegate = self
      field.font = UIFont.systemFont(ofSize: 13, weight: .regular)
      field.widthAnchor.constraint(equalToConstant: 50).isActive = true
    }

    coordinateModeControl.selectedSegmentIndex = 0
    dimensionControl.selectedSegmentIndex = 0
    modeControl.selectedSegmentIndex = 0
    autoRenderSwitch.isOn = true
    gridSwitch.isOn = true
    chunkSelectionSwitch.isOn = false

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
    renderButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .regular)
    renderButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
    renderButton.setContentHuggingPriority(.required, for: .horizontal)
    renderButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    renderButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
    renderButton.addTarget(self, action: #selector(renderFromFields), for: .touchUpInside)

    let centerCoordinateTitle = label("渲染中心坐标")
    centerCoordinateTitle.font = UIFont.systemFont(ofSize: 13, weight: .regular)
    centerCoordinateTitle.numberOfLines = 1
    centerCoordinateTitle.adjustsFontSizeToFitWidth = true
    centerCoordinateTitle.minimumScaleFactor = 0.75
    centerCoordinateTitle.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

    let coordinateFields = UIStackView(arrangedSubviews: [
      label("X"), xField,
      label("Z"), zField,
    ])
    coordinateFields.axis = .horizontal
    coordinateFields.spacing = 4
    coordinateFields.alignment = .center
    coordinateFields.setContentHuggingPriority(.required, for: .horizontal)
    coordinateFields.setContentCompressionResistancePriority(.required, for: .horizontal)

    let displayOptions = UIStackView(arrangedSubviews: [
      compactSwitch(title: "自动渲染", control: autoRenderSwitch),
      compactSwitch(title: "区块网格", control: gridSwitch),
      compactSwitch(title: "选择区块", control: chunkSelectionSwitch),
    ])
    displayOptions.axis = .horizontal
    displayOptions.spacing = 14
    displayOptions.alignment = .center
    displayOptions.distribution = .fill
    displayOptions.setContentHuggingPriority(.required, for: .horizontal)
    displayOptions.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

    let renderControls = UIStackView(arrangedSubviews: [
      centerCoordinateTitle,
      coordinateFields,
      renderButton,
    ])
    renderControls.axis = .horizontal
    renderControls.spacing = 7
    renderControls.alignment = .center
    renderControls.distribution = .fill
    renderControls.setContentHuggingPriority(.required, for: .horizontal)
    renderControls.setContentCompressionResistancePriority(.required, for: .horizontal)

    let flexibleSpacer = UIView()
    flexibleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    flexibleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let coordinates = UIStackView(arrangedSubviews: [
      displayOptions, flexibleSpacer, renderControls,
    ])
    coordinates.axis = .horizontal
    coordinates.spacing = 12
    coordinates.alignment = .center
    coordinates.distribution = .fill
    coordinates.isLayoutMarginsRelativeArrangement = true
    coordinates.layoutMargins = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
    coordinates.heightAnchor.constraint(equalToConstant: 44).isActive = true

    coordinateModeControl.heightAnchor.constraint(equalToConstant: 36).isActive = true
    dimensionControl.heightAnchor.constraint(equalToConstant: 36).isActive = true
    modeControl.heightAnchor.constraint(equalToConstant: 36).isActive = true

    let controls = UIStackView(arrangedSubviews: [
      coordinates, coordinateModeControl, dimensionControl, modeControl,
    ])
    controls.axis = .vertical
    controls.spacing = 6
    controls.translatesAutoresizingMaskIntoConstraints = false
    controls.setContentHuggingPriority(.required, for: .vertical)
    controls.setContentCompressionResistancePriority(.required, for: .vertical)
    controls.heightAnchor.constraint(equalToConstant: 44 + 36 * 3 + 6 * 3).isActive = true

    statusLabel.font = .preferredFont(forTextStyle: .footnote)
    statusLabel.textColor = .secondaryLabel
    statusLabel.numberOfLines = 0
    statusLabel.isUserInteractionEnabled = true
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(showRenderDiagnostics)))
    statusLabel.setContentHuggingPriority(.required, for: .vertical)
    statusLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

    scrollView.delegate = self
    scrollView.minimumZoomScale = initialMinimumZoomScale
    scrollView.maximumZoomScale = initialMaximumZoomScale
    scrollView.bouncesZoom = true
    scrollView.alwaysBounceHorizontal = true
    scrollView.alwaysBounceVertical = true
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
      : min(220, max(176, view.bounds.width * 0.42))
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
      : min(220, max(176, view.bounds.width * 0.42))
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
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    return label
  }

  private func compactSwitch(title: String, control: UISwitch) -> UIStackView {
    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
    titleLabel.textAlignment = .left
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = 0.82
    titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let switchHolder = UIView()
    switchHolder.widthAnchor.constraint(equalToConstant: 39).isActive = true
    switchHolder.heightAnchor.constraint(equalToConstant: 22).isActive = true
    control.translatesAutoresizingMaskIntoConstraints = false
    control.transform = CGAffineTransform(scaleX: 0.62, y: 0.62)
    switchHolder.addSubview(control)
    NSLayoutConstraint.activate([
      control.centerXAnchor.constraint(equalTo: switchHolder.centerXAnchor),
      control.centerYAnchor.constraint(equalTo: switchHolder.centerYAnchor),
    ])

    let stack = UIStackView(arrangedSubviews: [titleLabel, switchHolder])
    stack.axis = .horizontal
    stack.spacing = 3
    stack.alignment = .center
    stack.distribution = .fill
    stack.heightAnchor.constraint(equalToConstant: 24).isActive = true
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

  @objc private func regionOptionChanged() {
    let anchor = currentViewportAnchor()
    let center = anchor.map { chunkCenter(for: $0) } ?? (lastCenterX, lastCenterZ)
    render(centerX: center.0, centerZ: center.1, anchor: anchor, reason: "图层设置", showOverlay: false)
  }

  @objc private func coordinateModeChanged() {
    updateCoordinateFields(
      centerX: lastCenterX, centerZ: lastCenterZ, anchor: currentViewportAnchor())
    statusLabel.text =
      coordinateModeControl.selectedSegmentIndex == 0
      ? "输入区块坐标；地图会按当前缩放和可见范围动态加载区块。"
      : "输入方块坐标；地图会动态加载可见区块，负坐标按数学向下取整。"
  }

  @objc private func dimensionChanged() {
    rememberCurrentViewportState(for: activeDimension)
    setSelectionMode(false)
    selectedBlock = nil
    blockDetailPanel.clearBlock()
    let newDimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    if selectedChunk?.dimension != newDimension { selectedChunk = nil }
    activeDimension = newDimension

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
    statusLabel.text =
      autoRenderSwitch.isOn
      ? "移动自动渲染已开启：拖动会续载；缩小时会按视口自动扩大区块范围。"
      : "移动自动渲染已关闭；可拖动查看当前区域，使用坐标和“渲染”按钮跳转。"
    saveMapState()
  }

  @objc private func chunkSelectionChanged() {
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

    let centerX: Int32
    let centerZ: Int32
    let anchor: MapViewportAnchor?
    if coordinateModeControl.selectedSegmentIndex == 0 {
      centerX = Int32(clamping: inputX)
      centerZ = Int32(clamping: inputZ)
      anchor = nil
    } else {
      centerX = MapCoordinate.chunk(fromBlock: inputX)
      centerZ = MapCoordinate.chunk(fromBlock: inputZ)
      // The rendered image is still chunk-aligned, but the viewport must
      // center on the exact block requested instead of the chunk center.
      anchor = MapViewportAnchor(
        blockX: Double(inputX) + 0.5,
        blockZ: Double(inputZ) + 0.5,
        zoomScale: max(effectiveZoomScale, 1)
      )
    }
    render(centerX: centerX, centerZ: centerZ, anchor: anchor, reason: "坐标跳转", showOverlay: true)
  }

  private func render(
    centerX: Int32,
    centerZ: Int32,
    anchor: MapViewportAnchor?,
    reason: String,
    showOverlay: Bool
  ) {
    panDebounceWorkItem?.cancel()
    activeRenderToken?.cancel()

    let requestedZoom = max(anchor?.zoomScale ?? effectiveZoomScale, 0.0001)
    let sideChunks = dynamicRenderSideChunks(forZoomScale: requestedZoom)
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
        let result = try self.renderRegion(
          renderer: renderer,
          centerX: centerX,
          centerZ: centerZ,
          dimension: dimension,
          sideChunks: sideChunks,
          leftChunks: leftChunks,
          mode: mode,
          drawGrid: drawGrid,
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
          self.statusLabel.text =
            "中心区块 (\(centerX), \(centerZ))；动态 \(sideChunks)×\(sideChunks)；\(mode.displayName)；\(layerDetail)\(samplingDetail)；玩家 \(result.playerCount)；实体 \(result.entityCount)；方块实体 \(result.blockEntityCount)；刷怪区域 \(result.hardcodedSpawnerCount)；村庄 \(result.villageCount)；错误 \(result.errors.count) 条\(diagnosticHint)。缩放会按视口持续扩展渲染区块；低倍率自动降低位图像素密度，拖动可持续续载。"
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
    format.opaque = true
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
      UIColor.systemGray5.setFill()
      context.fill(CGRect(x: 0, y: 0, width: rendererSide, height: rendererSide))

      for (zIndex, zSample) in samplingPlan.zAxis.enumerated() {
        for (xIndex, xSample) in samplingPlan.xAxis.enumerated() {
          guard let chunkImage = chunkImages[zIndex * samplingPlan.xAxis.count + xIndex] else {
            continue
          }
          let logicalX = CGFloat(xSample.startOffset + leftChunks) * 16
          let logicalZ = CGFloat(zSample.startOffset + leftChunks) * 16
          chunkImage.draw(
            in: CGRect(
              x: logicalX * blockToRenderer,
              y: logicalZ * blockToRenderer,
              width: CGFloat(xSample.span * 16) * blockToRenderer,
              height: CGFloat(zSample.span * 16) * blockToRenderer
            )
          )
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

  private func scheduleAutoRender(immediate: Bool = false) {
    guard autoRenderSwitch.isOn, !isApplyingViewport, !isZooming, lastRenderedImage != nil else {
      return
    }
    panDebounceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in self?.autoRenderAtViewportCenter() }
    panDebounceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0.02 : 0.28), execute: item)
  }

  private func autoRenderAtViewportCenter() {
    guard autoRenderSwitch.isOn, !isApplyingViewport, !isZooming,
      let anchor = currentViewportAnchor()
    else { return }
    let center = chunkCenter(for: anchor)
    let requiredSideChunks = dynamicRenderSideChunks(forZoomScale: anchor.zoomScale)
    let centerChanged = center.0 != lastCenterX || center.1 != lastCenterZ
    let sideChanged = requiredSideChunks != renderedSideChunks
    guard centerChanged || sideChanged else { return }
    updateCoordinateFields(centerX: center.0, centerZ: center.1, anchor: anchor)
    let reason = centerChanged ? "移动续载" : "缩放续载"
    render(centerX: center.0, centerZ: center.1, anchor: anchor, reason: reason, showOverlay: false)
  }

  private func mapPosition(at point: CGPoint) -> (
    localX: Int, localZ: Int, absoluteX: Int64, absoluteZ: Int64
  )? {
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

  @objc private func toggleSelectionMode() {
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
      selectionMapPanOrigin = scrollView.contentOffset
      panDebounceWorkItem?.cancel()
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
      expandZoomRangeIfNeeded(for: proposedScale)
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
    guard !isSelectionMode, let position = mapPosition(at: imagePoint) else { return }
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
          self.zField.text = String(z)
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
    let alert = UIAlertController(
      title: "地图对象图层",
      message:
        "黄色五角星为本地玩家，蓝色五角星为在线玩家；蓝色圆点为实体，青色方块为方块实体，粉色虚线框为 HardcodedSpawners；绿色虚线框为村庄边界，橙色菱形为村庄中心，紫色方块为兴趣点。黄色标记为世界出生点，绿色标记为玩家出生点。玩家与出生点图层默认开启。",
      preferredStyle: .actionSheet
    )
    let playerTitle = showPlayers ? "✓ 显示玩家" : "显示玩家"
    let entityTitle = showEntities ? "✓ 显示实体" : "显示实体"
    let blockTitle = showBlockEntities ? "✓ 显示方块实体" : "显示方块实体"
    let spawnTitle = showSpawnPoints ? "✓ 显示出生点" : "显示出生点"
    let spawnerTitle = showHardcodedSpawners ? "✓ 显示 HardcodedSpawners" : "显示 HardcodedSpawners"
    let villageTitle = showVillages ? "✓ 显示村庄" : "显示村庄"
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
    alert.addAction(
      UIAlertAction(title: "全部显示", style: .default) { [weak self] _ in
        guard let self = self else { return }
        self.showPlayers = true
        self.showEntities = true
        self.showBlockEntities = true
        self.showHardcodedSpawners = true
        self.showVillages = true
        self.showSpawnPoints = true
        self.refreshObjectOverlays(reason: "对象图层")
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
        self.selectedSpawnerID = nil
        self.selectedVillageID = nil
        self.selectedVillageEntityIDs.removeAll()
        self.refreshObjectOverlays(reason: "对象图层")
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
    guard !isRendering, !isApplyingViewport, let anchor = currentViewportAnchor() else { return }
    let requiredSideChunks = dynamicRenderSideChunks(forZoomScale: anchor.zoomScale)
    guard requiredSideChunks != renderedSideChunks else {
      scheduleAutoRender(immediate: true)
      return
    }
    let center = chunkCenter(for: anchor)
    updateCoordinateFields(centerX: center.0, centerZ: center.1, anchor: anchor)
    render(centerX: center.0, centerZ: center.1, anchor: anchor, reason: "缩放续载", showOverlay: false)
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
    format.opaque = true
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
    let controller = MapExportOptionsViewController(
      layers: MapImageExportLayers(
        entities: showEntities,
        blockEntities: showBlockEntities,
        hardcodedSpawners: showHardcodedSpawners,
        villages: showVillages,
        spawnPoints: showSpawnPoints
      )
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
    let overlay = showBusy(scope == .currentRegion ? "正在生成当前地图图片…" : "正在读取当前维度全部已加载区域…")
    let dimension = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].rawValue
    let dimensionName = BedrockDimension.allCases[dimensionControl.selectedSegmentIndex].displayName
    let mode = currentMode
    let drawGrid = gridSwitch.isOn
    let centerX = lastCenterX
    let centerZ = lastCenterZ
    let sideChunks = renderedSideChunks
    let leftChunks = renderedLeftChunks
    let scanRadius = renderedScanRadius
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
        case .currentRegion:
          var objects = [BedrockWorldObject]()
          if layers.entities || layers.blockEntities {
            let scan = try BedrockWorldObjectScanner(database: database).scanRegionAdaptive(
              centerX: centerX,
              centerZ: centerZ,
              dimension: dimension,
              radius: scanRadius,
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
              centerX: centerX,
              centerZ: centerZ,
              dimension: dimension,
              sideChunks: sideChunks,
              leftChunks: leftChunks,
              shouldCancel: { false }
            )
            : (hits: [MapHardcodedSpawnerHit](), diagnostics: [String]())
          let rendered = try self.renderRegion(
            renderer: renderer,
            centerX: centerX,
            centerZ: centerZ,
            dimension: dimension,
            sideChunks: sideChunks,
            leftChunks: leftChunks,
            mode: mode,
            drawGrid: drawGrid,
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
          let startBlockX = MapCoordinate.blockOrigin(ofChunk: centerX - Int32(leftChunks))
          let startBlockZ = MapCoordinate.blockOrigin(ofChunk: centerZ - Int32(leftChunks))
          image = self.composeExportImage(
            base: rendered.image,
            startBlockX: startBlockX,
            startBlockZ: startBlockZ,
            worldObjectHits: rendered.worldObjectHits,
            hardcodedSpawnerHits: rendered.hardcodedSpawnerHits,
            villageHits: rendered.villageHits,
            spawnHits: rendered.spawnHits,
            layers: layers
          )
          exportSuffix = "current-\(centerX)-\(centerZ)"

        case .loadedDimension:
          let summaries = try BedrockChunkStore(session: self.session).listChunks().filter {
            $0.position.dimension == dimension
              && ($0.subChunkCount > 0 || $0.biomeRecordType != nil)
          }
          guard !summaries.isEmpty else {
            throw MCBEEditorError.unsupported("当前维度没有可导出的已加载区块。")
          }
          let positions: [ChunkPosition] = summaries.map { $0.position }
          let base = try self.renderLoadedDimensionBase(
            renderer: renderer,
            positions: positions,
            mode: mode,
            drawGrid: drawGrid
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

  private func renderLoadedDimensionBase(
    renderer: ChunkSurfaceRenderer,
    positions: [ChunkPosition],
    mode: MapRenderMode,
    drawGrid: Bool
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
    format.opaque = true
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
      UIColor.systemGray5.setFill()
      context.fill(CGRect(x: 0, y: 0, width: widthBlocks, height: heightBlocks))
      for item in images {
        let x = Int(Int64(item.position.x) - Int64(minimumX)) * 16
        let z = Int(Int64(item.position.z) - Int64(minimumZ)) * 16
        item.image.draw(in: CGRect(x: x, y: z, width: 16, height: 16))
      }
      if drawGrid {
        context.cgContext.setStrokeColor(UIColor.label.withAlphaComponent(0.34).cgColor)
        context.cgContext.setLineWidth(max(0.18, 1.0 / max(outputScale, 0.02)))
        for position in positionSet {
          let x = Int(Int64(position.x) - Int64(minimumX)) * 16
          let z = Int(Int64(position.z) - Int64(minimumZ)) * 16
          context.cgContext.stroke(CGRect(x: x, y: z, width: 16, height: 16))
        }
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
      let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      controller.popoverPresentationController?.barButtonItem = shareButton
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
    for key in ["centerX", "centerZ", "dimension", "radius", "zoomScale"] {
      defaults.removeObject(forKey: mapStatePrefix + key)
    }
  }

  private func rememberCurrentViewportState(for dimension: Int32) {
    guard lastRenderedImage != nil else { return }
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

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    updateObjectOverlay()
    if let region = selectedRegion { updateSelectionOverlay(for: region) }
    guard scrollView.isDragging || scrollView.isDecelerating else { return }
    scheduleAutoRender()
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
    isZooming = true
    panDebounceWorkItem?.cancel()
    showZoomHUD()
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    expandZoomRangeIfNeeded(for: scrollView.zoomScale)
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

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    renderFromFields()
    return true
  }
}
