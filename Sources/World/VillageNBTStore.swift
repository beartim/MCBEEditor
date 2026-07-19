import Foundation

enum VillageNBTRecordKind: String, CaseIterable {
  case legacy = "LEGACY"
  case info = "INFO"
  case poi = "POI"
  case dwellers = "DWELLERS"
  case players = "PLAYERS"
  case other = "OTHER"

  var displayName: String {
    switch self {
    case .legacy: return "旧版村庄信息"
    case .info: return "村庄信息"
    case .poi: return "兴趣点"
    case .dwellers: return "村庄居民"
    case .players: return "玩家声望"
    case .other: return "其他村庄数据"
    }
  }

  var iconName: String {
    switch self {
    case .legacy: return "house.fill"
    case .info: return "info.circle.fill"
    case .poi: return "mappin.and.ellipse"
    case .dwellers: return "person.3.fill"
    case .players: return "person.crop.circle.badge.checkmark"
    case .other: return "doc.text.magnifyingglass"
    }
  }

  var sortOrder: Int {
    switch self {
    case .info: return 0
    case .poi: return 1
    case .dwellers: return 2
    case .players: return 3
    case .legacy: return 4
    case .other: return 5
    }
  }
}

struct VillageNBTRecord: Hashable {
  let key: Data
  let keyText: String
  let villageIdentifier: String
  let kind: VillageNBTRecordKind
  let documentIndex: Int
  let documentCount: Int
  let documentPath: [NBTPathComponent]
  let document: NBTDocument
  let encoding: NBTEncoding
  let rawValueSize: Int
  let legacyVillageIndex: Int?

  static func == (lhs: VillageNBTRecord, rhs: VillageNBTRecord) -> Bool {
    lhs.key == rhs.key && lhs.documentIndex == rhs.documentIndex
      && lhs.documentPath == rhs.documentPath
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(key)
    hasher.combine(documentIndex)
    hasher.combine(documentPath)
  }

  var shortVillageIdentifier: String {
    guard villageIdentifier.count > 20 else { return villageIdentifier }
    return "\(villageIdentifier.prefix(10))…\(villageIdentifier.suffix(7))"
  }

  var villageDisplayName: String {
    if let legacyVillageIndex = legacyVillageIndex {
      return "旧版村庄 \(legacyVillageIndex + 1)"
    }
    if villageIdentifier == "legacy" { return "旧版村庄数据" }
    return "村庄 \(shortVillageIdentifier)"
  }

  var displayName: String {
    var value = kind.displayName
    if documentCount > 1 { value += " [\(documentIndex + 1)/\(documentCount)]" }
    return value
  }

  var detailDescription: String {
    var parts = [String]()
    if !document.rootName.isEmpty { parts.append("根 \(document.rootName)") }
    if !documentPath.isEmpty { parts.append(Self.pathText(documentPath)) }
    parts.append(ByteCountFormatter.string(fromByteCount: Int64(rawValueSize), countStyle: .file))
    parts.append(keyText)
    return parts.joined(separator: " · ")
  }

  var stableID: String {
    "\(key.hexString):\(documentIndex):\(Self.pathText(documentPath))"
  }

  private static func pathText(_ path: [NBTPathComponent]) -> String {
    guard !path.isEmpty else { return "/" }
    return path.reduce(into: "") { result, component in
      switch component {
      case .compound(let name): result += "/\(name)"
      case .list(let index): result += "[\(index)]"
      }
    }
  }
}

struct VillageMapPoint: Hashable {
  let x: Int64
  let y: Int64
  let z: Int64
  let label: String
  let linkedEntityIDs: [Int64]

  init(x: Int64, y: Int64, z: Int64, label: String, linkedEntityIDs: [Int64] = []) {
    self.x = x
    self.y = y
    self.z = z
    self.label = label
    self.linkedEntityIDs = Array(Set(linkedEntityIDs)).sorted()
  }

  var coordinateKey: String { "\(x):\(y):\(z)" }
  var horizontalCoordinateKey: String { "\(x):\(z)" }

  func mergingLinkedEntityIDs(_ ids: [Int64]) -> VillageMapPoint {
    VillageMapPoint(x: x, y: y, z: z, label: label, linkedEntityIDs: linkedEntityIDs + ids)
  }
}

struct VillagePlayerReputation: Hashable {
  let playerIdentifier: String
  let value: Int64
}

enum VillageResidentEntityKind: String, CaseIterable {
  case villager
  case cat
  case ironGolem
  case other

  var displayName: String {
    switch self {
    case .villager: return "村民实体"
    case .cat: return "猫实体"
    case .ironGolem: return "铁傀儡实体"
    case .other: return "其他居民实体"
    }
  }

  var iconName: String {
    switch self {
    case .villager: return "person.3.fill"
    case .cat: return "pawprint.fill"
    case .ironGolem: return "shield.fill"
    case .other: return "questionmark.circle.fill"
    }
  }
}

struct VillageResidentResolution {
  let requestedUniqueIDs: [Int64]
  let entities: [BedrockWorldObject]
  let unresolvedUniqueIDs: [Int64]
  let diagnostics: [String]

  func entities(of kind: VillageResidentEntityKind) -> [BedrockWorldObject] {
    entities.filter { VillageNBTStore.residentKind(for: $0) == kind }
  }
}

struct VillageMapBounds: Hashable {
  let minimumX: Int64
  let minimumZ: Int64
  let maximumX: Int64
  let maximumZ: Int64

  var width: Int64 { maximumX - minimumX + 1 }
  var depth: Int64 { maximumZ - minimumZ + 1 }
  var area: Int64 { max(Int64(1), width) * max(Int64(1), depth) }
  var centerX: Double { (Double(minimumX) + Double(maximumX)) / 2 }
  var centerZ: Double { (Double(minimumZ) + Double(maximumZ)) / 2 }

  func contains(x: Int64, z: Int64) -> Bool {
    x >= minimumX && x <= maximumX && z >= minimumZ && z <= maximumZ
  }
}

struct VillageMapFeature {
  let identifier: String
  let dimension: Int32
  let center: VillageMapPoint?
  let radius: Int64?
  let bounds: VillageMapBounds?
  let pointsOfInterest: [VillageMapPoint]
  let playerReputations: [VillagePlayerReputation]
  let dwellerUniqueIDs: [Int64]
  let residentEntities: [BedrockWorldObject]
  let unresolvedDwellerUniqueIDs: [Int64]
  let infoRecord: VillageNBTRecord

  var stableID: String { "\(dimension):\(identifier):\(infoRecord.stableID)" }
  var displayName: String { infoRecord.villageDisplayName }
  var villagerEntities: [BedrockWorldObject] {
    residentEntities.filter { VillageNBTStore.residentKind(for: $0) == .villager }
  }
  var catEntities: [BedrockWorldObject] {
    residentEntities.filter { VillageNBTStore.residentKind(for: $0) == .cat }
  }
  var ironGolemEntities: [BedrockWorldObject] {
    residentEntities.filter { VillageNBTStore.residentKind(for: $0) == .ironGolem }
  }
  var villagerCount: Int { villagerEntities.count }

  func contains(x: Int64, z: Int64) -> Bool {
    bounds?.contains(x: x, z: z) == true
  }
}

struct VillageNBTScanResult {
  let records: [VillageNBTRecord]
  let diagnostics: [String]
}

struct VillageMapScanResult {
  let features: [VillageMapFeature]
  let diagnostics: [String]
}

final class VillageNBTStore {
  static let legacyKey = Data("mVillages".utf8)
  static let modernPrefix = Data("VILLAGE_".utf8)

  private let session: WorldSession
  var worldSession: WorldSession { session }

  init(session: WorldSession) {
    self.session = session
  }

  func records() throws -> [VillageNBTRecord] {
    try scanRecords().records
  }

  func scanRecords() throws -> VillageNBTScanResult {
    let database = try session.database()
    var entries = [(key: Data, value: Data)]()

    if let legacy = try database.get(Self.legacyKey) {
      entries.append((Self.legacyKey, legacy))
    }
    for entry in try database.entries(prefix: Self.modernPrefix, includeValues: true, limit: 0) {
      if let value = entry.value { entries.append((entry.key, value)) }
    }

    var result = [VillageNBTRecord]()
    var diagnostics = [String]()
    for entry in entries {
      let keyText = String(data: entry.key, encoding: .utf8) ?? "0x\(entry.key.hexString)"
      do {
        let decoded = try ConsecutiveNBTCodec.decode(entry.value)
        let metadata = Self.metadata(for: entry.key, keyText: keyText)
        for (index, decodedRecord) in decoded.enumerated() {
          if metadata.kind == .legacy {
            let split = Self.legacyVillageRecords(
              key: entry.key,
              keyText: keyText,
              documentIndex: index,
              documentCount: decoded.count,
              decodedRecord: decodedRecord,
              rawValueSize: entry.value.count
            )
            if split.isEmpty {
              result.append(
                VillageNBTRecord(
                  key: entry.key,
                  keyText: keyText,
                  villageIdentifier: "legacy",
                  kind: .legacy,
                  documentIndex: index,
                  documentCount: decoded.count,
                  documentPath: [],
                  document: decodedRecord.document,
                  encoding: decodedRecord.encoding,
                  rawValueSize: entry.value.count,
                  legacyVillageIndex: nil
                ))
            } else {
              result.append(contentsOf: split)
            }
          } else {
            result.append(
              VillageNBTRecord(
                key: entry.key,
                keyText: keyText,
                villageIdentifier: metadata.identifier,
                kind: metadata.kind,
                documentIndex: index,
                documentCount: decoded.count,
                documentPath: [],
                document: decodedRecord.document,
                encoding: decodedRecord.encoding,
                rawValueSize: entry.value.count,
                legacyVillageIndex: nil
              ))
          }
        }
      } catch {
        diagnostics.append("\(keyText)：\(error.localizedDescription)")
      }
    }

    result.sort { lhs, rhs in
      let villageOrder = lhs.villageIdentifier.localizedCaseInsensitiveCompare(
        rhs.villageIdentifier)
      if villageOrder != .orderedSame { return villageOrder == .orderedAscending }
      if lhs.kind.sortOrder != rhs.kind.sortOrder { return lhs.kind.sortOrder < rhs.kind.sortOrder }
      if lhs.keyText != rhs.keyText { return lhs.keyText < rhs.keyText }
      if lhs.documentIndex != rhs.documentIndex { return lhs.documentIndex < rhs.documentIndex }
      return lhs.stableID < rhs.stableID
    }
    return VillageNBTScanResult(records: result, diagnostics: diagnostics)
  }

  func mapFeatures() throws -> VillageMapScanResult {
    let scan = try scanRecords()
    let grouped = Dictionary(grouping: scan.records, by: \.villageIdentifier)

    struct Seed {
      let identifier: String
      let dimension: Int32
      let center: VillageMapPoint?
      let radius: Int64?
      let bounds: VillageMapBounds?
      let pointsOfInterest: [VillageMapPoint]
      let playerReputations: [VillagePlayerReputation]
      let dwellerUniqueIDs: [Int64]
      let infoRecord: VillageNBTRecord
    }

    var seeds = [Seed]()
    for identifier in grouped.keys.sorted() {
      guard let records = grouped[identifier], !records.isEmpty else { continue }
      let primary =
        records.first(where: { $0.kind == .info })
        ?? records.first(where: { $0.kind == .legacy })
        ?? records[0]

      let dimension = records.compactMap { Self.dimension(in: $0.document.root) }.first ?? 0
      var center = records.compactMap { Self.center(in: $0.document.root) }.first
      let radius = records.compactMap { Self.radius(in: $0.document.root) }.first
      var bounds = records.compactMap { Self.bounds(in: $0.document.root) }.first

      var points = [VillageMapPoint]()
      for record in records where record.kind == .poi || record.kind == .legacy {
        points.append(contentsOf: Self.pointsOfInterest(in: record.document.root))
      }
      points = Self.deduplicated(points)

      let dwellerRecords = records.filter { $0.kind == .dwellers || $0.kind == .legacy }
      let bindings = dwellerRecords.flatMap { Self.dwellerBindings(in: $0.document.root) }
      points = Self.applying(bindings: bindings, to: points)
      let dwellerUniqueIDs = Array(
        Set(
          dwellerRecords.flatMap {
            Self.dwellerUniqueIDs(
              in: $0.document.root,
              rootIsDwellersRecord: $0.kind == .dwellers
            )
          }
        )
      ).sorted()

      let reputationRecords = records.filter { $0.kind == .players || $0.kind == .legacy }
      let playerReputations = Self.deduplicatedReputations(
        reputationRecords.flatMap { Self.playerReputations(in: $0.document.root) }
      )

      if center == nil, let bounds = bounds {
        center = VillageMapPoint(
          x: Int64(bounds.centerX.rounded()), y: 0,
          z: Int64(bounds.centerZ.rounded()), label: "村庄中心"
        )
      }
      if center == nil, !points.isEmpty {
        center = VillageMapPoint(
          x: Int64((Double(points.map(\.x).reduce(0, +)) / Double(points.count)).rounded()),
          y: Int64((Double(points.map(\.y).reduce(0, +)) / Double(points.count)).rounded()),
          z: Int64((Double(points.map(\.z).reduce(0, +)) / Double(points.count)).rounded()),
          label: "推断中心"
        )
      }
      if bounds == nil, let center = center, let radius = radius {
        bounds = VillageMapBounds(
          minimumX: center.x - radius, minimumZ: center.z - radius,
          maximumX: center.x + radius, maximumZ: center.z + radius
        )
      }
      if bounds == nil,
        let minimumX = points.map(\.x).min(),
        let minimumZ = points.map(\.z).min(),
        let maximumX = points.map(\.x).max(),
        let maximumZ = points.map(\.z).max()
      {
        bounds = VillageMapBounds(
          minimumX: minimumX - 1,
          minimumZ: minimumZ - 1,
          maximumX: maximumX + 1,
          maximumZ: maximumZ + 1
        )
      }
      if bounds == nil, let center = center {
        bounds = VillageMapBounds(
          minimumX: center.x - 1, minimumZ: center.z - 1,
          maximumX: center.x + 1, maximumZ: center.z + 1
        )
      }

      guard center != nil || bounds != nil || !points.isEmpty else { continue }
      seeds.append(
        Seed(
          identifier: identifier,
          dimension: dimension,
          center: center,
          radius: radius,
          bounds: bounds,
          pointsOfInterest: points,
          playerReputations: playerReputations,
          dwellerUniqueIDs: dwellerUniqueIDs,
          infoRecord: primary
        ))
    }

    let requestedIDs = Set(seeds.flatMap(\.dwellerUniqueIDs))
    let residentResolution = try resolveResidentEntities(uniqueIDs: requestedIDs)
    let entityByID = Dictionary(
      residentResolution.entities.compactMap { object in object.uniqueID.map { ($0, object) } },
      uniquingKeysWith: { first, _ in first }
    )
    let unresolved = Set(residentResolution.unresolvedUniqueIDs)

    var features = seeds.map { seed in
      VillageMapFeature(
        identifier: seed.identifier,
        dimension: seed.dimension,
        center: seed.center,
        radius: seed.radius,
        bounds: seed.bounds,
        pointsOfInterest: seed.pointsOfInterest,
        playerReputations: seed.playerReputations,
        dwellerUniqueIDs: seed.dwellerUniqueIDs,
        residentEntities: seed.dwellerUniqueIDs.compactMap { entityByID[$0] },
        unresolvedDwellerUniqueIDs: seed.dwellerUniqueIDs.filter { unresolved.contains($0) },
        infoRecord: seed.infoRecord
      )
    }
    features.sort { lhs, rhs in
      if lhs.dimension != rhs.dimension { return lhs.dimension < rhs.dimension }
      let lx = lhs.center?.x ?? lhs.bounds?.minimumX ?? 0
      let rx = rhs.center?.x ?? rhs.bounds?.minimumX ?? 0
      if lx != rx { return lx < rx }
      let lz = lhs.center?.z ?? lhs.bounds?.minimumZ ?? 0
      let rz = rhs.center?.z ?? rhs.bounds?.minimumZ ?? 0
      return lz < rz
    }
    return VillageMapScanResult(
      features: features,
      diagnostics: scan.diagnostics + residentResolution.diagnostics
    )
  }

  func residentResolution(villageIdentifier: String) throws -> VillageResidentResolution {
    let scan = try scanRecords()
    let records = scan.records.filter { $0.villageIdentifier == villageIdentifier }
    let dwellerRecords = records.filter { $0.kind == .dwellers || $0.kind == .legacy }
    let uniqueIDs = Set(
      dwellerRecords.flatMap { record in
        Self.dwellerUniqueIDs(
          in: record.document.root,
          rootIsDwellersRecord: record.kind == .dwellers
        )
      })
    let resolution = try resolveResidentEntities(uniqueIDs: uniqueIDs)
    return VillageResidentResolution(
      requestedUniqueIDs: resolution.requestedUniqueIDs,
      entities: resolution.entities,
      unresolvedUniqueIDs: resolution.unresolvedUniqueIDs,
      diagnostics: scan.diagnostics + resolution.diagnostics
    )
  }

  private func resolveResidentEntities(uniqueIDs: Set<Int64>) throws -> VillageResidentResolution {
    guard !uniqueIDs.isEmpty else {
      return VillageResidentResolution(
        requestedUniqueIDs: [], entities: [], unresolvedUniqueIDs: [], diagnostics: []
      )
    }
    let result = try BedrockWorldObjectScanner(database: try session.database())
      .scanEntities(uniqueIDs: uniqueIDs)
    let resolvedIDs = Set(result.objects.compactMap(\.uniqueID))
    return VillageResidentResolution(
      requestedUniqueIDs: uniqueIDs.sorted(),
      entities: result.objects,
      unresolvedUniqueIDs: uniqueIDs.filter { !resolvedIDs.contains($0) }.sorted(),
      diagnostics: result.diagnostics
    )
  }

  static func residentKind(for object: BedrockWorldObject) -> VillageResidentEntityKind {
    guard object.kind == .entity else { return .other }
    let identifier = object.identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let localName =
      identifier.split(separator: ":", omittingEmptySubsequences: true).last.map(String.init)
      ?? identifier
    switch localName {
    case "villager", "villager_v2": return .villager
    case "cat": return .cat
    case "iron_golem", "irongolem": return .ironGolem
    default: return .other
    }
  }

  func save(record: VillageNBTRecord, document: NBTDocument) throws {
    let database = try session.database()
    guard let current = try database.get(record.key) else {
      throw MCBEEditorError.malformedData("村庄记录已不存在，请返回列表重新读取。")
    }
    var decoded = try ConsecutiveNBTCodec.decode(current)
    guard decoded.indices.contains(record.documentIndex) else {
      throw MCBEEditorError.malformedData("村庄记录中的 NBT 数量已经变化，请返回列表重新读取。")
    }
    if record.documentPath.isEmpty {
      decoded[record.documentIndex].document = document
    } else {
      var container = decoded[record.documentIndex].document
      container.root = try NBTTreeMutation.replacingValue(
        at: record.documentPath,
        in: container.root,
        with: document.root
      )
      decoded[record.documentIndex].document = container
    }
    let encoded = try ConsecutiveNBTCodec.encode(decoded)
    try database.put(encoded, for: record.key, sync: true)
  }

  func encodedDocument(record: VillageNBTRecord, document: NBTDocument) throws -> Data {
    try BedrockNBTCodec.encode(document, encoding: record.encoding)
  }

  private static func metadata(for key: Data, keyText: String) -> (
    identifier: String, kind: VillageNBTRecordKind
  ) {
    if key == legacyKey { return ("legacy", .legacy) }
    guard key.starts(with: modernPrefix) else { return (keyText, .other) }

    let body = Data(key.dropFirst(modernPrefix.count))
    let suffixes: [(Data, VillageNBTRecordKind)] = [
      (Data("_DWELLERS".utf8), .dwellers),
      (Data("_PLAYERS".utf8), .players),
      (Data("_INFO".utf8), .info),
      (Data("_POI".utf8), .poi),
    ]
    for (suffix, kind) in suffixes
    where body.count >= suffix.count && body.suffix(suffix.count) == suffix {
      let identifierData = Data(body.dropLast(suffix.count))
      let identifier =
        String(data: identifierData, encoding: .utf8)
        ?? "0x\(identifierData.hexString)"
      return (identifier.isEmpty ? keyText : identifier, kind)
    }
    let identifier = String(data: body, encoding: .utf8) ?? "0x\(body.hexString)"
    return (identifier.isEmpty ? keyText : identifier, .other)
  }

  private struct LegacyCandidate {
    let path: [NBTPathComponent]
    let value: NBTValue
  }

  private static func legacyVillageRecords(
    key: Data,
    keyText: String,
    documentIndex: Int,
    documentCount: Int,
    decodedRecord: ConsecutiveNBTRecord,
    rawValueSize: Int
  ) -> [VillageNBTRecord] {
    let candidates = legacyCandidates(
      in: decodedRecord.document.root, path: [], nameHint: decodedRecord.document.rootName)
    return candidates.enumerated().map { offset, candidate in
      let center = self.center(in: candidate.value)
      let explicitIdentifier = identifier(in: candidate.value)
      let identifier =
        explicitIdentifier
        ?? center.map { "legacy-\(documentIndex)-\(offset)-\($0.x)-\($0.z)" }
        ?? "legacy-\(documentIndex)-\(offset)"
      return VillageNBTRecord(
        key: key,
        keyText: keyText,
        villageIdentifier: identifier,
        kind: .legacy,
        documentIndex: documentIndex,
        documentCount: documentCount,
        documentPath: candidate.path,
        document: NBTDocument(rootName: "Village \(offset + 1)", root: candidate.value),
        encoding: decodedRecord.encoding,
        rawValueSize: rawValueSize,
        legacyVillageIndex: offset
      )
    }
  }

  private static func legacyCandidates(
    in value: NBTValue,
    path: [NBTPathComponent],
    nameHint: String
  ) -> [LegacyCandidate] {
    var result = [LegacyCandidate]()
    switch value {
    case .list(_, let values):
      let normalizedHint = normalized(nameHint)
      let villageListNames: Set<String> = [
        "villages", "mvillages", "villagecollection", "villagelist",
      ]
      let looksLikeVillageList = path.isEmpty || villageListNames.contains(normalizedHint)
      if looksLikeVillageList, !values.isEmpty,
        values.allSatisfy({
          if case .compound = $0 { return true }
          return false
        })
      {
        for (index, child) in values.enumerated() {
          result.append(LegacyCandidate(path: path + [.list(index)], value: child))
        }
        return result
      }
      for (index, child) in values.enumerated() {
        result.append(
          contentsOf: legacyCandidates(in: child, path: path + [.list(index)], nameHint: nameHint))
      }
    case .compound(let tags):
      for tag in tags {
        result.append(
          contentsOf: legacyCandidates(
            in: tag.value,
            path: path + [.compound(tag.name)],
            nameHint: tag.name
          ))
      }
    default:
      break
    }
    return result
  }

  private static func identifier(in root: NBTValue) -> String? {
    let preferred = ["villageuuid", "uuid", "villageid", "uniqueid"]
    let values = namedValues(in: root)
    for name in preferred {
      if let entry = values.first(where: { normalized($0.name) == name }),
        let text = scalarText(entry.value)
      {
        return text
      }
    }
    return nil
  }

  private static func dimension(in root: NBTValue) -> Int32? {
    let names = ["dimension", "dimensionid", "dimensionindex", "dim"]
    for entry in namedValues(in: root) where names.contains(normalized(entry.name)) {
      if let value = integer(entry.value) { return Int32(clamping: value) }
      guard let text = scalarText(entry.value)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty
      else { continue }
      if let value = Int32(text) { return value }
      let value = normalized(text)
      if value == "overworld" || value.hasSuffix("minecraftoverworld") {
        return BedrockDimension.overworld.rawValue
      }
      if value == "nether" || value.hasSuffix("minecraftnether") {
        return BedrockDimension.nether.rawValue
      }
      if value == "end" || value == "theend" || value.hasSuffix("minecrafttheend") {
        return BedrockDimension.end.rawValue
      }
    }
    return nil
  }

  private static func radius(in root: NBTValue) -> Int64? {
    let names = ["radius", "villageradius"]
    for entry in namedValues(in: root) where names.contains(normalized(entry.name)) {
      if let value = integer(entry.value), value >= 0 { return value }
    }
    return nil
  }

  private static func center(in root: NBTValue) -> VillageMapPoint? {
    let centerNames = [
      "center", "villagecenter", "centerpos", "centerposition", "villagecenterpos",
    ]
    for entry in namedValues(in: root) {
      let name = normalized(entry.name)
      if centerNames.contains(name), let vector = vector(entry.value) {
        return VillageMapPoint(x: vector.0, y: vector.1, z: vector.2, label: "村庄中心")
      }
    }

    if case .compound(let tags) = root,
      let vector = xyz(in: tags, prefixes: ["center", "villagecenter", "c"])
    {
      return VillageMapPoint(x: vector.0, y: vector.1, z: vector.2, label: "村庄中心")
    }
    return nil
  }

  private static func bounds(in root: NBTValue) -> VillageMapBounds? {
    // Modern Bedrock village INFO records store the authoritative boundary
    // directly as X0/Z0 -> X1/Z1. Prefer those four fields over radius- or
    // POI-derived fallbacks so the drawn range matches the village NBT.
    if let coordinateBounds = coordinateBounds(in: root) {
      return coordinateBounds
    }

    let entries = namedValues(in: root)
    var minimum: (Int64, Int64, Int64)?
    var maximum: (Int64, Int64, Int64)?
    for entry in entries {
      let name = normalized(entry.name)
      if ["min", "minimum", "minpos", "minimumposition", "lower", "lowercorner"].contains(name),
        let value = vector(entry.value)
      {
        minimum = value
      }
      if ["max", "maximum", "maxpos", "maximumposition", "upper", "uppercorner"].contains(name),
        let value = vector(entry.value)
      {
        maximum = value
      }
    }
    if let minimum = minimum, let maximum = maximum {
      return VillageMapBounds(
        minimumX: min(minimum.0, maximum.0),
        minimumZ: min(minimum.2, maximum.2),
        maximumX: max(minimum.0, maximum.0),
        maximumZ: max(minimum.2, maximum.2)
      )
    }

    if case .compound(let tags) = root {
      let minX = scalar(namedAny: ["MinX", "minX", "MinimumX", "minimumX"], in: tags)
      let minZ = scalar(namedAny: ["MinZ", "minZ", "MinimumZ", "minimumZ"], in: tags)
      let maxX = scalar(namedAny: ["MaxX", "maxX", "MaximumX", "maximumX"], in: tags)
      let maxZ = scalar(namedAny: ["MaxZ", "maxZ", "MaximumZ", "maximumZ"], in: tags)
      if let minX = minX, let minZ = minZ, let maxX = maxX, let maxZ = maxZ {
        return VillageMapBounds(
          minimumX: min(minX, maxX),
          minimumZ: min(minZ, maxZ),
          maximumX: max(minX, maxX),
          maximumZ: max(minZ, maxZ)
        )
      }
    }
    return nil
  }

  private static func coordinateBounds(in root: NBTValue) -> VillageMapBounds? {
    func find(in value: NBTValue) -> VillageMapBounds? {
      switch value {
      case .compound(let tags):
        let x0 = scalar(namedAny: ["X0"], in: tags)
        let z0 = scalar(namedAny: ["Z0"], in: tags)
        let x1 = scalar(namedAny: ["X1"], in: tags)
        let z1 = scalar(namedAny: ["Z1"], in: tags)
        if let x0 = x0, let z0 = z0, let x1 = x1, let z1 = z1 {
          return VillageMapBounds(
            minimumX: min(x0, x1),
            minimumZ: min(z0, z1),
            maximumX: max(x0, x1),
            maximumZ: max(z0, z1)
          )
        }
        for tag in tags {
          if let result = find(in: tag.value) { return result }
        }
      case .list(_, let values):
        for child in values {
          if let result = find(in: child) { return result }
        }
      default:
        break
      }
      return nil
    }
    return find(in: root)
  }

  private static func pointsOfInterest(in root: NBTValue) -> [VillageMapPoint] {
    var result = [VillageMapPoint]()
    collectPoints(
      in: root,
      nameHint: "",
      inheritedLinkedEntityIDs: [],
      into: &result
    )
    return deduplicated(result)
  }

  private static func collectPoints(
    in value: NBTValue,
    nameHint: String,
    inheritedLinkedEntityIDs: [Int64],
    into result: inout [VillageMapPoint]
  ) {
    switch value {
    case .compound(let tags):
      let label = pointLabel(in: tags) ?? (nameHint.isEmpty ? "兴趣点" : nameHint)
      var linkedIDs = inheritedLinkedEntityIDs + linkedEntityIDs(in: tags)
      if let implicitID = numericIdentifier(from: nameHint) {
        linkedIDs.append(implicitID)
      }
      linkedIDs = Array(Set(linkedIDs)).sorted()

      if let coordinates = xyz(in: tags, prefixes: ["", "pos", "position", "blockpos"]) {
        result.append(
          VillageMapPoint(
            x: coordinates.0,
            y: coordinates.1,
            z: coordinates.2,
            label: label,
            linkedEntityIDs: linkedIDs
          ))
      }
      for tag in tags {
        let name = normalized(tag.name)
        if name.contains("pos") || name.contains("position") || name.contains("location")
          || name.contains("center")
        {
          if let coordinates = vector(tag.value) {
            result.append(
              VillageMapPoint(
                x: coordinates.0,
                y: coordinates.1,
                z: coordinates.2,
                label: label,
                linkedEntityIDs: linkedIDs
              ))
          }
        }
        // POI entries keep VillagerID on the parent while X/Y/Z live
        // inside `instances`. Propagate the relationship to descendants.
        collectPoints(
          in: tag.value,
          nameHint: tag.name,
          inheritedLinkedEntityIDs: linkedIDs,
          into: &result
        )
      }
    case .list(_, let values):
      for child in values {
        collectPoints(
          in: child,
          nameHint: nameHint,
          inheritedLinkedEntityIDs: inheritedLinkedEntityIDs,
          into: &result
        )
      }
    default:
      break
    }
  }

  private static func pointLabel(in tags: [NBTNamedTag]) -> String? {
    let preferred = ["type", "name", "id", "identifier", "block", "blockname", "poitype"]
    for name in preferred {
      if let tag = tags.first(where: { normalized($0.name) == name }),
        let text = scalarText(tag.value), !text.isEmpty
      {
        return text
      }
    }
    return nil
  }

  private struct VillageDwellerBinding {
    let entityID: Int64
    let positions: [VillageMapPoint]
  }

  private static func linkedEntityIDs(in tags: [NBTNamedTag]) -> [Int64] {
    let relationshipTerms = [
      "owner", "occupant", "dweller", "villager", "resident", "actor", "member",
    ]
    var result = [Int64]()
    for tag in tags {
      let name = normalized(tag.name)
      let isRelationship = relationshipTerms.contains(where: { name.contains($0) })
      let isExplicitEntityID = [
        "actoruniqueid", "entityuniqueid", "owneruniqueid", "occupantuniqueid", "dwelleruniqueid",
        "villageruniqueid", "residentuniqueid",
      ].contains(name)
      guard isRelationship || isExplicitEntityID else { continue }
      result.append(contentsOf: numericValues(in: tag.value))
    }
    return Array(Set(result)).sorted()
  }

  /// Extracts entity identifiers from a village DWELLERS record.
  ///
  /// Current Bedrock village data stores each resident's entity identifier in
  /// a numeric `ID` tag. Older/transition worlds may instead use `UniqueID`
  /// or a more explicit `ActorUniqueID`/`EntityUniqueID` spelling. For modern
  /// DWELLERS keys the whole root is resident data; for a legacy mVillages
  /// document, plain `ID` values are accepted only inside a Dwellers-like
  /// subtree so player/POI identifiers are not mistaken for residents.
  static func dwellerUniqueIDs(
    in root: NBTValue,
    rootIsDwellersRecord: Bool = true
  ) -> [Int64] {
    let dwellerContainerNames: Set<String> = [
      "dwellers", "dweller", "residents", "resident",
      "villagers", "villager", "members", "member",
    ]
    let explicitIdentityNames: Set<String> = [
      "uniqueid", "actoruniqueid", "entityuniqueid", "dwelleruniqueid",
      "villageruniqueid", "residentuniqueid", "owneruniqueid",
      "occupantuniqueid", "actorid", "entityid", "dwellerid",
      "villagerid", "residentid",
    ]

    func identifierValues(in value: NBTValue) -> [Int64] {
      if case .string(let text) = value, let parsed = numericIdentifier(from: text) {
        return [parsed]
      }
      return numericValues(in: value)
    }

    var result = [Int64]()
    func walk(_ value: NBTValue, insideDwellers: Bool) {
      switch value {
      case .compound(let tags):
        for tag in tags {
          let name = normalized(tag.name)
          let childInsideDwellers = insideDwellers || dwellerContainerNames.contains(name)
          // The important current-format case is exactly `ID`.
          // Keep the older UniqueID spellings for compatibility.
          if childInsideDwellers
            && (name == "id" || explicitIdentityNames.contains(name) || name.hasSuffix("uniqueid"))
          {
            result.append(contentsOf: identifierValues(in: tag.value))
          }
          walk(tag.value, insideDwellers: childInsideDwellers)
        }
      case .list(_, let values):
        for child in values { walk(child, insideDwellers: insideDwellers) }
      default:
        break
      }
    }

    walk(root, insideDwellers: rootIsDwellersRecord)
    return Array(Set(result)).sorted()
  }

  private static func dwellerBindings(in root: NBTValue) -> [VillageDwellerBinding] {
    let identityNames: Set<String> = [
      "actoruniqueid", "entityuniqueid", "dwelleruniqueid", "villageruniqueid",
      "residentuniqueid", "actorid", "entityid", "dwellerid", "villagerid", "residentid",
      "uniqueid", "id",
    ]
    let positionTerms = ["poi", "home", "bed", "work", "job", "dwelling", "meeting", "station"]
    var result = [VillageDwellerBinding]()

    func walk(_ value: NBTValue, nameHint: String) {
      switch value {
      case .compound(let tags):
        var ids = [Int64]()
        if let implicitID = numericIdentifier(from: nameHint) {
          ids.append(implicitID)
        }
        var positions = [VillageMapPoint]()
        for tag in tags {
          let name = normalized(tag.name)
          if identityNames.contains(name) {
            ids.append(contentsOf: numericValues(in: tag.value))
          }
          if positionTerms.contains(where: { name.contains($0) }),
            let coordinates = vector(tag.value)
          {
            positions.append(
              VillageMapPoint(
                x: coordinates.0,
                y: coordinates.1,
                z: coordinates.2,
                label: tag.name
              ))
          }
        }
        let normalizedHint = normalized(nameHint)
        if positionTerms.contains(where: { normalizedHint.contains($0) }),
          let coordinates = xyz(in: tags, prefixes: ["", "pos", "position", "blockpos"])
        {
          positions.append(
            VillageMapPoint(
              x: coordinates.0,
              y: coordinates.1,
              z: coordinates.2,
              label: nameHint.isEmpty ? "兴趣点" : nameHint
            ))
        }
        ids = Array(Set(ids)).sorted()
        positions = deduplicated(positions)
        for id in ids where !positions.isEmpty {
          result.append(VillageDwellerBinding(entityID: id, positions: positions))
        }
        for tag in tags { walk(tag.value, nameHint: tag.name) }
      case .list(_, let values):
        for child in values { walk(child, nameHint: nameHint) }
      default:
        break
      }
    }

    walk(root, nameHint: "")
    return result
  }

  private static func applying(bindings: [VillageDwellerBinding], to points: [VillageMapPoint])
    -> [VillageMapPoint]
  {
    guard !bindings.isEmpty, !points.isEmpty else { return points }
    var result = points
    for binding in bindings {
      for position in binding.positions {
        if let index = result.firstIndex(where: { $0.coordinateKey == position.coordinateKey })
          ?? result.firstIndex(where: {
            $0.horizontalCoordinateKey == position.horizontalCoordinateKey
          })
        {
          result[index] = result[index].mergingLinkedEntityIDs([binding.entityID])
        }
      }
    }
    return deduplicated(result)
  }

  private static func playerReputations(in root: NBTValue) -> [VillagePlayerReputation] {
    let reputationNames: Set<String> = [
      "reputation", "reputationvalue", "score", "popularity", "value",
    ]
    let identityNames: Set<String> = [
      "playerid", "playeruniqueid", "uniqueid", "uuid", "xuid", "name", "playername", "id",
    ]
    var result = [VillagePlayerReputation]()

    func walk(_ value: NBTValue, nameHint: String, indexHint: Int?) {
      switch value {
      case .compound(let tags):
        let reputation = tags.first(where: {
          let name = normalized($0.name)
          return reputationNames.contains(name) || name.contains("reputation")
        }).flatMap { integer($0.value) }
        if let reputation = reputation {
          let identity =
            tags.first(where: { identityNames.contains(normalized($0.name)) })
            .flatMap { scalarText($0.value) }
            ?? (indexHint.map { "玩家 \($0 + 1)" } ?? (nameHint.isEmpty ? "玩家" : nameHint))
          result.append(VillagePlayerReputation(playerIdentifier: identity, value: reputation))
        }

        let normalizedHint = normalized(nameHint)
        if normalizedHint.contains("player") || normalizedHint.contains("reputation") {
          for tag in tags {
            let tagName = normalized(tag.name)
            guard !reputationNames.contains(tagName), !identityNames.contains(tagName),
              let value = integer(tag.value)
            else { continue }
            result.append(VillagePlayerReputation(playerIdentifier: tag.name, value: value))
          }
        }
        for tag in tags { walk(tag.value, nameHint: tag.name, indexHint: indexHint) }
      case .list(_, let values):
        for (index, child) in values.enumerated() {
          walk(child, nameHint: nameHint, indexHint: index)
        }
      default:
        break
      }
    }

    walk(root, nameHint: "", indexHint: nil)
    return result
  }

  private static func deduplicatedReputations(_ values: [VillagePlayerReputation])
    -> [VillagePlayerReputation]
  {
    var latest = [String: VillagePlayerReputation]()
    for value in values {
      latest[value.playerIdentifier] = value
    }
    return latest.values.sorted {
      $0.playerIdentifier.localizedCaseInsensitiveCompare($1.playerIdentifier) == .orderedAscending
    }
  }

  private static func numericIdentifier(from text: String) -> Int64? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("0x") {
      return Int64(trimmed.dropFirst(2), radix: 16)
    }
    return Int64(trimmed)
  }

  private static func numericValues(in value: NBTValue) -> [Int64] {
    if let scalar = integer(value) { return [scalar] }
    switch value {
    case .intArray(let values): return values.map(Int64.init)
    case .longArray(let values): return values
    case .list(_, let values): return values.flatMap(numericValues)
    case .compound(let tags): return tags.flatMap { numericValues(in: $0.value) }
    default: return []
    }
  }

  private static func namedValues(in root: NBTValue) -> [(name: String, value: NBTValue)] {
    var result = [(String, NBTValue)]()
    func walk(_ value: NBTValue) {
      switch value {
      case .compound(let tags):
        for tag in tags {
          result.append((tag.name, tag.value))
          walk(tag.value)
        }
      case .list(_, let values):
        for child in values { walk(child) }
      default:
        break
      }
    }
    walk(root)
    return result
  }

  private static func vector(_ value: NBTValue) -> (Int64, Int64, Int64)? {
    switch value {
    case .intArray(let values) where values.count >= 3:
      return (Int64(values[0]), Int64(values[1]), Int64(values[2]))
    case .longArray(let values) where values.count >= 3:
      return (values[0], values[1], values[2])
    case .list(_, let values) where values.count >= 3:
      guard let x = integer(values[0]), let y = integer(values[1]), let z = integer(values[2])
      else { return nil }
      return (x, y, z)
    case .compound(let tags):
      return xyz(in: tags, prefixes: ["", "pos", "position", "center", "villagecenter"])
    default:
      return nil
    }
  }

  private static func xyz(in tags: [NBTNamedTag], prefixes: [String]) -> (Int64, Int64, Int64)? {
    for prefix in prefixes {
      let normalizedPrefix = normalized(prefix)
      let xNames =
        normalizedPrefix.isEmpty ? ["x"] : ["\(normalizedPrefix)x", "x\(normalizedPrefix)"]
      let yNames =
        normalizedPrefix.isEmpty ? ["y"] : ["\(normalizedPrefix)y", "y\(normalizedPrefix)"]
      let zNames =
        normalizedPrefix.isEmpty ? ["z"] : ["\(normalizedPrefix)z", "z\(normalizedPrefix)"]
      let x = tags.first(where: { xNames.contains(normalized($0.name)) }).flatMap {
        integer($0.value)
      }
      let y = tags.first(where: { yNames.contains(normalized($0.name)) }).flatMap {
        integer($0.value)
      }
      let z = tags.first(where: { zNames.contains(normalized($0.name)) }).flatMap {
        integer($0.value)
      }
      if let x = x, let y = y, let z = z { return (x, y, z) }
    }
    return nil
  }

  private static func scalar(namedAny names: [String], in tags: [NBTNamedTag]) -> Int64? {
    let normalizedNames = Set(names.map(normalized))
    return tags.first(where: { normalizedNames.contains(normalized($0.name)) }).flatMap {
      integer($0.value)
    }
  }

  private static func integer(_ value: NBTValue) -> Int64? {
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

  private static func scalarText(_ value: NBTValue) -> String? {
    switch value {
    case .string(let text): return text
    case .byte(let number): return String(number)
    case .short(let number): return String(number)
    case .int(let number): return String(number)
    case .long(let number): return String(number)
    default: return nil
    }
  }

  private static func normalized(_ name: String) -> String {
    name.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  private static func deduplicated(_ points: [VillageMapPoint]) -> [VillageMapPoint] {
    var order = [String]()
    var merged = [String: VillageMapPoint]()
    for point in points {
      let key = point.coordinateKey
      if let existing = merged[key] {
        let preferredLabel =
          existing.label == "兴趣点" && point.label != "兴趣点" ? point.label : existing.label
        merged[key] = VillageMapPoint(
          x: point.x,
          y: point.y,
          z: point.z,
          label: preferredLabel,
          linkedEntityIDs: existing.linkedEntityIDs + point.linkedEntityIDs
        )
      } else {
        order.append(key)
        merged[key] = point
      }
    }
    return order.compactMap { merged[$0] }
  }
}
