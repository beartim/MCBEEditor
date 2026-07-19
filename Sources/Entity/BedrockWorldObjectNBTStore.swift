import Foundation

struct BedrockWorldObjectSaveResult {
  let moved: Bool
  let uniqueIDChanged: Bool
  let destinationDimension: Int32
  let destinationChunkX: Int32
  let destinationChunkZ: Int32
  let destinationUniqueID: Int64?
}

struct BedrockWorldObjectCreateResult {
  let kind: BedrockWorldObjectKind
  let dimension: Int32
  let chunkX: Int32
  let chunkZ: Int32
  let uniqueID: Int64?
  let source: BedrockWorldObjectSource
}

final class BedrockWorldObjectNBTStore {
  private enum EntityCreationStorageMode {
    case legacyChunkEntity
    case modernActor
  }

  private struct DatabaseChange {
    let key: Data
    let originalValue: Data?
    let newValue: Data?
    let label: String
  }

  private let session: WorldSession

  init(session: WorldSession) {
    self.session = session
  }

  /// Returns every consecutive root stored in the same LevelDB value as the
  /// selected object. This is used by the long-press continuous-NBT export.
  func sourceDocuments(for object: BedrockWorldObject) throws -> [NBTDocument] {
    let database = try session.database()
    let key: Data
    switch object.storage {
    case .modernActor(let actorKey, _, _, _): key = actorKey
    case .chunkRecord(let sourceKey, _, _): key = sourceKey
    }
    guard let raw = try database.get(key) else {
      throw MCBEEditorError.unsupported("对象的源 NBT 记录已经不存在。")
    }
    let documents = try ConsecutiveNBTCodec.decode(raw).map { $0.document }
    guard !documents.isEmpty else {
      throw MCBEEditorError.malformedData("对象源记录不包含可导出的 NBT 根标签。")
    }
    return documents
  }

  /// Returns only the selected object's root NBT, even when several legacy
  /// entities share one consecutive-NBT LevelDB value.
  func document(for object: BedrockWorldObject) throws -> NBTDocument {
    let database = try session.database()
    let key: Data
    let preferredIndex: Int
    switch object.storage {
    case .modernActor(let actorKey, _, let recordIndex, _):
      key = actorKey
      preferredIndex = recordIndex
    case .chunkRecord(let sourceKey, let recordIndex, _):
      key = sourceKey
      preferredIndex = recordIndex
    }
    guard let raw = try database.get(key) else {
      throw MCBEEditorError.unsupported("对象的源 NBT 记录已经不存在。")
    }
    let records = try ConsecutiveNBTCodec.decode(raw)
    let index = try locateRecord(object: object, in: records, preferredIndex: preferredIndex)
    return records[index].document
  }

  func save(object: BedrockWorldObject, document: NBTDocument) throws
    -> BedrockWorldObjectSaveResult
  {
    try validateDocument(document, for: object)
    switch object.storage {
    case .modernActor(let actorKey, let digestKey, let recordIndex, _):
      return try saveModernActor(
        object: object,
        document: document,
        actorKey: actorKey,
        digestKey: digestKey,
        recordIndex: recordIndex
      )
    case .chunkRecord(let key, let recordIndex, _):
      return try saveChunkRecord(
        object: object,
        document: document,
        sourceKey: key,
        recordIndex: recordIndex
      )
    }
  }

  func delete(object: BedrockWorldObject) throws {
    _ = try delete(objects: [object])
  }

  /// Deletes a scanned set in one LevelDB batch. Multiple legacy entities may
  /// share one consecutive-NBT value; rewriting that value once per entity makes
  /// later scanned indexes stale and used to produce partial `kill @e` results.
  @discardableResult
  func delete(objects: [BedrockWorldObject]) throws -> Int {
    guard !objects.isEmpty else { return 0 }
    let database = try session.database()
    var puts = [(key: Data, value: Data)]()
    var deletes = Set<Data>()
    var removedIDs = Set<Int64>()
    var deletedCount = 0

    var chunkGroups = [Data: [(BedrockWorldObject, Int)]]()
    var actorGroups = [Data: [(BedrockWorldObject, Int)]]()
    for object in objects {
      switch object.storage {
      case .chunkRecord(let key, let recordIndex, _):
        chunkGroups[key, default: []].append((object, recordIndex))
      case .modernActor(let actorKey, _, let recordIndex, _):
        actorGroups[actorKey, default: []].append((object, recordIndex))
      }
    }

    for (key, group) in chunkGroups {
      guard let original = try database.get(key) else {
        throw MCBEEditorError.malformedData("区块实体记录已不存在，请重新扫描。")
      }
      var records = try ConsecutiveNBTCodec.decode(original)
      var indexes = Set<Int>()
      for (object, preferredIndex) in group {
        indexes.insert(
          try locateRecord(object: object, in: records, preferredIndex: preferredIndex))
        if let id = object.uniqueID { removedIDs.insert(id) }
      }
      for index in indexes.sorted(by: >) { records.remove(at: index) }
      deletedCount += indexes.count
      if records.isEmpty {
        deletes.insert(key)
      } else {
        puts.append((key: key, value: try ConsecutiveNBTCodec.encode(records)))
      }
    }

    for (key, group) in actorGroups {
      guard let original = try database.get(key) else {
        throw MCBEEditorError.malformedData("actorprefix 记录已不存在，请重新扫描。")
      }
      var records = try ConsecutiveNBTCodec.decode(original)
      var indexes = Set<Int>()
      for (object, preferredIndex) in group {
        indexes.insert(
          try locateRecord(object: object, in: records, preferredIndex: preferredIndex))
        if let id = object.uniqueID { removedIDs.insert(id) }
      }
      for index in indexes.sorted(by: >) { records.remove(at: index) }
      deletedCount += indexes.count
      if records.isEmpty {
        deletes.insert(key)
      } else {
        puts.append((key: key, value: try ConsecutiveNBTCodec.encode(records)))
      }
    }

    if !removedIDs.isEmpty {
      for entry in try database.entries(prefix: Data("digp".utf8), includeValues: true) {
        guard let raw = entry.value else { continue }
        var ids = try decodeActorIDs(raw)
        let originalCount = ids.count
        ids.removeAll { removedIDs.contains($0) }
        guard ids.count != originalCount else { continue }
        if ids.isEmpty {
          deletes.insert(entry.key)
        } else {
          puts.append((key: entry.key, value: encodeActorIDs(ids)))
        }
      }
    }

    try database.applyBatch(puts: puts, deletes: Array(deletes), sync: true)
    return deletedCount
  }

  /// Migrates the non-canonical overworld digest keys written by v1.1.3-v1.1.5.
  /// Bedrock uses `digp + chunkX + chunkZ` in the overworld; appending a zero
  /// dimension makes the record visible to this editor but invisible to the game.
  @discardableResult
  func repairAppCreatedOverworldActorDigests() throws -> Int {
    try repairAppCreatedOverworldActorDigests(database: session.database())
  }

  func prepareEntityDocument(
    _ source: NBTDocument,
    fallbackIdentifier: String,
    position: BedrockWorldObjectPosition,
    dimension: Int32,
    uniqueID: Int64
  ) throws -> NBTDocument {
    let identifier = BedrockEntityCommonNBT.identifier(in: source.root) ?? fallbackIdentifier
    let database = try session.database()
    let mode = try preferredEntityCreationStorage(
      template: nil,
      chunkX: MapCoordinate.chunk(fromBlock: position.blockX),
      chunkZ: MapCoordinate.chunk(fromBlock: position.blockZ),
      dimension: dimension,
      database: database
    )
    return try makeCreationDocument(
      kind: .entity,
      identifier: identifier,
      position: position,
      dimension: dimension,
      uniqueID: uniqueID,
      template: source,
      templateIdentifier: BedrockEntityCommonNBT.identifier(in: source.root),
      entityStorageMode: mode
    )
  }

  func createEntity(from document: NBTDocument) throws -> BedrockWorldObjectCreateResult {
    guard let identifier = BedrockEntityCommonNBT.identifier(in: document.root),
      let position = BedrockEntityCommonNBT.position(in: document.root),
      let dimension = BedrockEntityCommonNBT.dimension(in: document.root),
      let uniqueID = BedrockEntityCommonNBT.uniqueID(in: document.root)
    else {
      throw MCBEEditorError.malformedData("实体 NBT 必须包含可识别的实体 ID、Pos、DimensionId 和 UniqueID。")
    }
    return try create(
      kind: .entity,
      identifier: identifier,
      position: position,
      dimension: dimension,
      uniqueID: uniqueID,
      template: nil,
      templateDocument: document
    )
  }

  func suggestedUniqueID() throws -> Int64 {
    let database = try session.database()
    for _ in 0..<128 {
      let candidate = Int64.random(in: 1...Int64.max)
      if try isEntityUniqueIDAvailable(candidate, excluding: nil, database: database) {
        return candidate
      }
    }
    throw MCBEEditorError.unsupported("无法生成未占用的实体 UniqueID，请手动填写。")
  }

  func create(
    kind: BedrockWorldObjectKind,
    identifier: String,
    position: BedrockWorldObjectPosition,
    dimension: Int32,
    uniqueID: Int64?,
    template: BedrockWorldObject?,
    templateDocument: NBTDocument? = nil
  ) throws -> BedrockWorldObjectCreateResult {
    let rawIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedIdentifier: String
    if kind == .entity {
      trimmedIdentifier =
        BedrockDataValueCatalog.entityIdentifier(forRawValue: rawIdentifier) ?? rawIdentifier
    } else {
      trimmedIdentifier = rawIdentifier
    }
    guard !trimmedIdentifier.isEmpty else {
      throw MCBEEditorError.malformedData("实体或方块实体 ID 不能为空。")
    }
    guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
      throw MCBEEditorError.malformedData("坐标必须是有限数字。")
    }
    if let template = template, template.kind != kind {
      throw MCBEEditorError.unsupported("模板类型与要创建的对象类型不一致。")
    }

    let database = try session.database()
    switch kind {
    case .entity:
      let actorID: Int64
      if let uniqueID = uniqueID {
        actorID = uniqueID
      } else {
        actorID = try suggestedUniqueID()
      }
      guard actorID != 0 else {
        throw MCBEEditorError.malformedData("实体 UniqueID 不能为 0。")
      }
      guard try isEntityUniqueIDAvailable(actorID, excluding: nil, database: database) else {
        throw MCBEEditorError.unsupported("UniqueID \(actorID) 已被其他实体占用。")
      }

      let chunkX = MapCoordinate.chunk(fromBlock: position.blockX)
      let chunkZ = MapCoordinate.chunk(fromBlock: position.blockZ)
      let storageMode = try preferredEntityCreationStorage(
        template: template,
        chunkX: chunkX,
        chunkZ: chunkZ,
        dimension: dimension,
        database: database
      )
      let document = try makeCreationDocument(
        kind: kind,
        identifier: trimmedIdentifier,
        position: position,
        dimension: dimension,
        uniqueID: actorID,
        template: templateDocument ?? template?.document,
        templateIdentifier: template?.identifier
          ?? templateDocument.flatMap { BedrockEntityCommonNBT.identifier(in: $0.root) },
        entityStorageMode: storageMode
      )

      switch storageMode {
      case .legacyChunkEntity:
        let entityKey = BedrockDBKey(
          position: ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension),
          recordType: .entity,
          subChunkIndex: nil
        ).encoded()
        let original = try database.get(entityKey)
        var records = try original.map(ConsecutiveNBTCodec.decode) ?? []
        let encoding = records.first?.encoding ?? template?.storage.encoding ?? .littleEndian
        let raw = try BedrockNBTCodec.encode(document, encoding: encoding)
        records.append(ConsecutiveNBTRecord(document: document, rawData: raw, encoding: encoding))
        try database.put(try ConsecutiveNBTCodec.encode(records), for: entityKey, sync: true)
        return BedrockWorldObjectCreateResult(
          kind: kind,
          dimension: dimension,
          chunkX: chunkX,
          chunkZ: chunkZ,
          uniqueID: actorID,
          source: .legacyChunkEntity
        )

      case .modernActor:
        _ = try repairAppCreatedOverworldActorDigests(database: database)
        let encoding = template?.storage.encoding ?? .littleEndian
        let actorValue = try BedrockNBTCodec.encode(document, encoding: encoding)
        let actorKey = makeActorKey(id: actorID)
        let digestKey = makeDigestKey(
          x: chunkX,
          z: chunkZ,
          dimension: dimension
        )
        let currentDigest = try database.get(digestKey)
        var actorIDs = try currentDigest.map(decodeActorIDs) ?? []
        if !actorIDs.contains(actorID) { actorIDs.append(actorID) }

        try database.applyBatch(
          puts: [
            (key: actorKey, value: actorValue),
            (key: digestKey, value: encodeActorIDs(actorIDs)),
          ],
          deletes: [],
          sync: true
        )
        return BedrockWorldObjectCreateResult(
          kind: kind,
          dimension: dimension,
          chunkX: chunkX,
          chunkZ: chunkZ,
          uniqueID: actorID,
          source: .modernActor
        )
      }

    case .blockEntity:
      let document = try makeCreationDocument(
        kind: kind,
        identifier: trimmedIdentifier,
        position: position,
        dimension: dimension,
        uniqueID: nil,
        template: templateDocument ?? template?.document,
        templateIdentifier: template?.identifier,
        entityStorageMode: nil
      )
      let chunkX = MapCoordinate.chunk(fromBlock: position.blockX)
      let chunkZ = MapCoordinate.chunk(fromBlock: position.blockZ)
      let key = BedrockDBKey(
        position: ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension),
        recordType: .blockEntity,
        subChunkIndex: nil
      ).encoded()
      let original = try database.get(key)
      var records = try original.map(ConsecutiveNBTCodec.decode) ?? []
      if records.contains(where: { record in
        guard let existing = extractPosition(root: record.document.root, kind: .blockEntity) else {
          return false
        }
        return existing.blockX == position.blockX && existing.blockY == position.blockY
          && existing.blockZ == position.blockZ
      }) {
        throw MCBEEditorError.unsupported("该方块坐标已经存在方块实体。请先编辑或删除原记录。")
      }
      let encoding = records.first?.encoding ?? template?.storage.encoding ?? .littleEndian
      let raw = try BedrockNBTCodec.encode(document, encoding: encoding)
      records.append(ConsecutiveNBTRecord(document: document, rawData: raw, encoding: encoding))
      try database.put(try ConsecutiveNBTCodec.encode(records), for: key, sync: true)
      return BedrockWorldObjectCreateResult(
        kind: kind,
        dimension: dimension,
        chunkX: chunkX,
        chunkZ: chunkZ,
        uniqueID: nil,
        source: .blockEntity
      )
    }
  }

  private func saveModernActor(
    object: BedrockWorldObject,
    document: NBTDocument,
    actorKey: Data,
    digestKey: Data,
    recordIndex: Int
  ) throws -> BedrockWorldObjectSaveResult {
    guard let originalActorID = object.uniqueID else {
      throw MCBEEditorError.malformedData("现代实体缺少 ActorUniqueID，无法安全写回。")
    }
    let editedActorID =
      document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"])
      ?? originalActorID
    guard editedActorID != 0 else {
      throw MCBEEditorError.malformedData("实体 UniqueID 不能为 0。")
    }

    let database = try session.database()
    let targetActorKey = makeActorKey(id: editedActorID)
    if targetActorKey != actorKey, try database.get(targetActorKey) != nil {
      throw MCBEEditorError.unsupported("UniqueID \(editedActorID) 已存在对应的 actorprefix 记录。")
    }
    if editedActorID != originalActorID,
      try !isEntityUniqueIDAvailable(editedActorID, excluding: object, database: database)
    {
      throw MCBEEditorError.unsupported("UniqueID \(editedActorID) 已被其他实体占用。")
    }

    guard let currentActorData = try database.get(actorKey) else {
      throw MCBEEditorError.malformedData("actorprefix 记录已不存在，请重新扫描实体。")
    }
    var actorRecords = try ConsecutiveNBTCodec.decode(currentActorData)
    let locatedIndex = try locateRecord(
      object: object, in: actorRecords, preferredIndex: recordIndex)
    let sourceEncoding = actorRecords[locatedIndex].encoding
    let editedRaw = try BedrockNBTCodec.encode(document, encoding: sourceEncoding)

    let destination = destination(for: object, document: document)
    let moved =
      destination.dimension != object.dimension || destination.chunkX != object.chunkX
      || destination.chunkZ != object.chunkZ
    let uniqueIDChanged = editedActorID != originalActorID

    var changes = [DatabaseChange]()
    if targetActorKey == actorKey {
      actorRecords[locatedIndex].document = document
      actorRecords[locatedIndex].rawData = editedRaw
      changes.append(
        DatabaseChange(
          key: actorKey,
          originalValue: currentActorData,
          newValue: try ConsecutiveNBTCodec.encode(actorRecords),
          label: "actorprefix"
        ))
    } else {
      actorRecords.remove(at: locatedIndex)
      let remainingValue = actorRecords.isEmpty ? nil : try ConsecutiveNBTCodec.encode(actorRecords)
      changes.append(
        DatabaseChange(
          key: actorKey,
          originalValue: currentActorData,
          newValue: remainingValue,
          label: "原 actorprefix"
        ))
      changes.append(
        DatabaseChange(
          key: targetActorKey,
          originalValue: nil,
          newValue: editedRaw,
          label: "目标 actorprefix"
        ))
    }

    let destinationDigestKey = makeDigestKey(
      x: destination.chunkX,
      z: destination.chunkZ,
      dimension: destination.dimension
    )
    try appendDigestChanges(
      sourceKey: digestKey,
      destinationKey: destinationDigestKey,
      originalID: originalActorID,
      editedID: editedActorID,
      database: database,
      changes: &changes
    )

    try commit(changes, database: database)
    return BedrockWorldObjectSaveResult(
      moved: moved,
      uniqueIDChanged: uniqueIDChanged,
      destinationDimension: destination.dimension,
      destinationChunkX: destination.chunkX,
      destinationChunkZ: destination.chunkZ,
      destinationUniqueID: editedActorID
    )
  }

  private func appendDigestChanges(
    sourceKey: Data,
    destinationKey: Data,
    originalID: Int64,
    editedID: Int64,
    database: MojangLevelDB,
    changes: inout [DatabaseChange]
  ) throws {
    if sourceKey.isEmpty {
      let targetOriginal = try database.get(destinationKey)
      var targetIDs = try targetOriginal.map(decodeActorIDs) ?? []
      if !targetIDs.contains(editedID) { targetIDs.append(editedID) }
      changes.append(
        DatabaseChange(
          key: destinationKey,
          originalValue: targetOriginal,
          newValue: encodeActorIDs(targetIDs),
          label: "目标 digp"
        ))
      return
    }

    if sourceKey == destinationKey {
      guard let currentDigest = try database.get(sourceKey) else {
        throw MCBEEditorError.malformedData("实体 digp 摘要已不存在，请重新扫描实体。")
      }
      var ids = try decodeActorIDs(currentDigest)
      guard ids.contains(originalID) else {
        throw MCBEEditorError.malformedData("digp 摘要不再引用原 UniqueID，请重新扫描后再编辑。")
      }
      ids.removeAll { $0 == originalID || $0 == editedID }
      ids.append(editedID)
      changes.append(
        DatabaseChange(
          key: sourceKey,
          originalValue: currentDigest,
          newValue: encodeActorIDs(ids),
          label: "digp"
        ))
      return
    }

    guard let sourceOriginal = try database.get(sourceKey) else {
      throw MCBEEditorError.malformedData("原 digp 摘要已不存在，请重新扫描实体。")
    }
    var sourceIDs = try decodeActorIDs(sourceOriginal)
    guard sourceIDs.contains(originalID) else {
      throw MCBEEditorError.malformedData("原 digp 摘要不再引用此实体，请重新扫描后再编辑。")
    }
    sourceIDs.removeAll { $0 == originalID }

    let targetOriginal = try database.get(destinationKey)
    var targetIDs = try targetOriginal.map(decodeActorIDs) ?? []
    targetIDs.removeAll { $0 == editedID }
    targetIDs.append(editedID)

    changes.append(
      DatabaseChange(
        key: destinationKey,
        originalValue: targetOriginal,
        newValue: encodeActorIDs(targetIDs),
        label: "目标 digp"
      ))
    changes.append(
      DatabaseChange(
        key: sourceKey,
        originalValue: sourceOriginal,
        newValue: sourceIDs.isEmpty ? nil : encodeActorIDs(sourceIDs),
        label: "原 digp"
      ))
  }

  private func saveChunkRecord(
    object: BedrockWorldObject,
    document: NBTDocument,
    sourceKey: Data,
    recordIndex: Int
  ) throws -> BedrockWorldObjectSaveResult {
    let database = try session.database()
    if object.kind == .entity,
      let originalID = object.uniqueID,
      let editedID = document.root.int64Value(namedAny: [
        "UniqueID", "UniqueId", "uniqueID", "uniqueId",
      ]),
      editedID != originalID,
      try !isEntityUniqueIDAvailable(editedID, excluding: object, database: database)
    {
      throw MCBEEditorError.unsupported("UniqueID \(editedID) 已被其他实体占用。")
    }

    guard let sourceData = try database.get(sourceKey) else {
      throw MCBEEditorError.malformedData("区块对象记录已不存在，请重新扫描。")
    }
    var sourceRecords = try ConsecutiveNBTCodec.decode(sourceData)
    let locatedIndex = try locateRecord(
      object: object, in: sourceRecords, preferredIndex: recordIndex)
    let sourceEncoding = sourceRecords[locatedIndex].encoding

    let destination = destination(for: object, document: document)
    let moved =
      destination.dimension != object.dimension || destination.chunkX != object.chunkX
      || destination.chunkZ != object.chunkZ
    let recordType: ChunkRecordType = object.kind == .blockEntity ? .blockEntity : .entity
    let targetKey = BedrockDBKey(
      position: ChunkPosition(
        x: destination.chunkX,
        z: destination.chunkZ,
        dimension: destination.dimension
      ),
      recordType: recordType,
      subChunkIndex: nil
    ).encoded()

    if !moved || targetKey == sourceKey {
      sourceRecords[locatedIndex].document = document
      sourceRecords[locatedIndex].rawData = try BedrockNBTCodec.encode(
        document, encoding: sourceEncoding)
      let changes = [
        DatabaseChange(
          key: sourceKey,
          originalValue: sourceData,
          newValue: try ConsecutiveNBTCodec.encode(sourceRecords),
          label: object.kind.displayName
        )
      ]
      try commit(changes, database: database)
      return BedrockWorldObjectSaveResult(
        moved: false,
        uniqueIDChanged: object.uniqueID
          != document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"]),
        destinationDimension: destination.dimension,
        destinationChunkX: destination.chunkX,
        destinationChunkZ: destination.chunkZ,
        destinationUniqueID: document.root.int64Value(namedAny: [
          "UniqueID", "UniqueId", "uniqueID", "uniqueId",
        ])
      )
    }

    sourceRecords.remove(at: locatedIndex)
    let newSourceData = sourceRecords.isEmpty ? nil : try ConsecutiveNBTCodec.encode(sourceRecords)
    let targetOriginal = try database.get(targetKey)
    var targetRecords = try targetOriginal.map(ConsecutiveNBTCodec.decode) ?? []
    let targetEncoding = targetRecords.first?.encoding ?? sourceEncoding
    let editedRaw = try BedrockNBTCodec.encode(document, encoding: targetEncoding)
    targetRecords.append(
      ConsecutiveNBTRecord(document: document, rawData: editedRaw, encoding: targetEncoding))

    let changes = [
      DatabaseChange(
        key: targetKey,
        originalValue: targetOriginal,
        newValue: try ConsecutiveNBTCodec.encode(targetRecords),
        label: "目标区块对象记录"
      ),
      DatabaseChange(
        key: sourceKey,
        originalValue: sourceData,
        newValue: newSourceData,
        label: "原区块对象记录"
      ),
    ]
    try commit(changes, database: database)
    return BedrockWorldObjectSaveResult(
      moved: true,
      uniqueIDChanged: object.uniqueID
        != document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"]),
      destinationDimension: destination.dimension,
      destinationChunkX: destination.chunkX,
      destinationChunkZ: destination.chunkZ,
      destinationUniqueID: document.root.int64Value(namedAny: [
        "UniqueID", "UniqueId", "uniqueID", "uniqueId",
      ])
    )
  }

  private func locateRecord(
    object: BedrockWorldObject,
    in records: [ConsecutiveNBTRecord],
    preferredIndex: Int
  ) throws -> Int {
    if records.indices.contains(preferredIndex), records[preferredIndex].rawData == object.rawData {
      return preferredIndex
    }
    if let uniqueID = object.uniqueID,
      let index = records.firstIndex(where: {
        $0.document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"])
          == uniqueID
      })
    {
      return index
    }
    if let position = object.position,
      let index = records.firstIndex(where: { record in
        let candidate = extractPosition(root: record.document.root, kind: object.kind)
        let identifier = record.document.root.stringValue(namedAny: [
          "identifier", "Identifier", "id", "Id",
        ])
        return identifier == object.identifier && candidate?.blockX == position.blockX
          && candidate?.blockY == position.blockY && candidate?.blockZ == position.blockZ
      })
    {
      return index
    }
    throw MCBEEditorError.malformedData("对象记录已经变化，无法确认要修改的 NBT。请返回列表重新扫描。")
  }

  private func validateDocument(_ document: NBTDocument, for object: BedrockWorldObject) throws {
    guard case .compound = document.root else {
      throw MCBEEditorError.malformedData("实体与方块实体的 NBT 根必须是 Compound。")
    }
    guard object.kind == .entity else { return }
    let originalDocumentID = object.document.root.int64Value(namedAny: [
      "UniqueID", "UniqueId", "uniqueID", "uniqueId",
    ])
    let editedID = document.root.int64Value(namedAny: [
      "UniqueID", "UniqueId", "uniqueID", "uniqueId",
    ])
    if originalDocumentID != nil && editedID == nil {
      throw MCBEEditorError.unsupported("UniqueID 可以修改，但不能删除或重命名。")
    }
    if let editedID = editedID, editedID == 0 {
      throw MCBEEditorError.malformedData("实体 UniqueID 不能为 0。")
    }
  }

  private func destination(
    for object: BedrockWorldObject,
    document: NBTDocument
  ) -> (dimension: Int32, chunkX: Int32, chunkZ: Int32) {
    let position = extractPosition(root: document.root, kind: object.kind) ?? object.position
    let dimension = extractDimension(root: document.root, fallback: object.dimension)
    return (
      dimension,
      position.map { MapCoordinate.chunk(fromBlock: $0.blockX) } ?? object.chunkX,
      position.map { MapCoordinate.chunk(fromBlock: $0.blockZ) } ?? object.chunkZ
    )
  }

  private func preferredEntityCreationStorage(
    template: BedrockWorldObject?,
    chunkX: Int32,
    chunkZ: Int32,
    dimension: Int32,
    database: MojangLevelDB
  ) throws -> EntityCreationStorageMode {
    // A copied legacy entity must remain in the legacy per-chunk record.
    // This is especially important for worlds last opened before the
    // modern actor-storage migration in Bedrock 1.18.20/1.18.30.
    if template?.source == .legacyChunkEntity { return .legacyChunkEntity }

    let entries = try database.entries(includeValues: false, limit: 0)

    // ActorDigestVersion is the authoritative marker for a world that has
    // completed the modern actor-storage migration. A bare digp/actorprefix
    // pair is not sufficient because older MCBEEditor builds may have
    // created those records inside an otherwise legacy world.
    if entries.contains(where: { entry in
      BedrockDBKey.parse(entry.key)?.recordType == .actorDigestVersion
    }) {
      return .modernActor
    }

    let legacyKey = BedrockDBKey(
      position: ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension),
      recordType: .entity,
      subChunkIndex: nil
    ).encoded()
    if try database.get(legacyKey) != nil
      || entries.contains(where: { entry in
        BedrockDBKey.parse(entry.key)?.recordType == .entity
      })
    {
      return .legacyChunkEntity
    }

    let targetDigestKey = makeDigestKey(x: chunkX, z: chunkZ, dimension: dimension)
    if let digest = try database.get(targetDigestKey),
      try digestContainsExistingActor(digest, database: database)
    {
      return .modernActor
    }

    if template?.source == .modernActor { return .modernActor }
    return .modernActor
  }

  private func digestContainsExistingActor(_ digest: Data, database: MojangLevelDB) throws -> Bool {
    guard digest.count % 8 == 0 else { return false }
    for actorID in try decodeActorIDs(digest) {
      if try database.get(makeActorKey(id: actorID)) != nil { return true }
    }
    return false
  }

  private func makeCreationDocument(
    kind: BedrockWorldObjectKind,
    identifier: String,
    position: BedrockWorldObjectPosition,
    dimension: Int32,
    uniqueID: Int64?,
    template: NBTDocument?,
    templateIdentifier: String?,
    entityStorageMode: EntityCreationStorageMode?
  ) throws -> NBTDocument {
    var document: NBTDocument
    if let template = template {
      document = template
      guard case .compound = document.root else {
        throw MCBEEditorError.malformedData("模板 NBT 根不是 Compound。")
      }
    } else {
      switch kind {
      case .entity:
        var identityTags = [NBTNamedTag]()
        if entityStorageMode == .legacyChunkEntity {
          guard let numeric = BedrockDataValueCatalog.entity(forIdentifier: identifier)?.id,
            numeric <= Int(Int16.max)
          else {
            throw MCBEEditorError.unsupported("旧式区块 Entity 需要可转换的数字实体 ID；请从同类旧实体复制，或使用数据值表中的实体 ID。")
          }
          identityTags.append(NBTNamedTag(name: "id", value: .short(Int16(numeric))))
        } else {
          identityTags.append(NBTNamedTag(name: "identifier", value: .string(identifier)))
        }
        identityTags.append(
          contentsOf: BedrockEntityCommonNBT.tags(
            identifier: identifier,
            position: position,
            dimension: dimension,
            uniqueID: uniqueID ?? 0
          ))
        document = NBTDocument(rootName: "", root: .compound(identityTags))
      case .blockEntity:
        document = NBTDocument(
          rootName: "",
          root: .compound([
            NBTNamedTag(name: "id", value: .string(identifier)),
            NBTNamedTag(name: "x", value: .int(Int32(clamping: position.blockX))),
            NBTNamedTag(name: "y", value: .int(position.blockY)),
            NBTNamedTag(name: "z", value: .int(Int32(clamping: position.blockZ))),
          ]))
      }
    }

    switch kind {
    case .entity:
      document.root = try BedrockEntityCommonNBT.addingMissingTopLevel(
        BedrockEntityCommonNBT.tags(
          identifier: identifier,
          position: position,
          dimension: dimension,
          uniqueID: uniqueID ?? 0
        ),
        to: document.root
      )
      let previousIdentifier =
        document.root.stringValue(namedAny: ["identifier", "Identifier", "id", "Id"])
        ?? templateIdentifier
      document.root = try updateEntityIdentity(
        in: document.root,
        identifier: identifier,
        previousIdentifier: previousIdentifier,
        storageMode: entityStorageMode ?? .modernActor
      )
      document.root = ensureEntityDefinition(
        in: document.root,
        identifier: identifier,
        replacing: previousIdentifier
      )
      document.root = setTopLevelTag(
        in: document.root,
        names: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"],
        preferredName: "UniqueID",
        value: .long(uniqueID ?? 0)
      )
      document.root = setTopLevelTag(
        in: document.root,
        names: ["Pos", "pos", "Position", "position"],
        preferredName: "Pos",
        value: .list(
          .float,
          [
            .float(Float(position.x)), .float(Float(position.y)), .float(Float(position.z)),
          ])
      )
      document.root = setTopLevelTag(
        in: document.root,
        names: ["DimensionId", "DimensionID", "Dimension", "dimension"],
        preferredName: "DimensionId",
        value: .int(dimension)
      )
    case .blockEntity:
      document.root = setTopLevelTag(
        in: document.root,
        names: ["id", "Id", "identifier", "Identifier"],
        preferredName: "id",
        value: .string(identifier)
      )
      document.root = setTopLevelTag(
        in: document.root, names: ["x", "X"], preferredName: "x",
        value: .int(Int32(clamping: position.blockX)))
      document.root = setTopLevelTag(
        in: document.root, names: ["y", "Y"], preferredName: "y", value: .int(position.blockY))
      document.root = setTopLevelTag(
        in: document.root, names: ["z", "Z"], preferredName: "z",
        value: .int(Int32(clamping: position.blockZ)))
    }
    return document
  }

  private func updateEntityIdentity(
    in root: NBTValue,
    identifier: String,
    previousIdentifier: String?,
    storageMode: EntityCreationStorageMode
  ) throws -> NBTValue {
    guard case .compound(var tags) = root else { return root }
    let identifierNames: Set<String> = ["identifier"]
    let idNames: Set<String> = ["id"]
    let sameIdentifier = previousIdentifier?.caseInsensitiveCompare(identifier) == .orderedSame
    let mappedID = BedrockDataValueCatalog.entity(forIdentifier: identifier)?.id
    var foundIdentityTag = false
    var foundNumericID = false

    for index in tags.indices {
      let name = tags[index].name.lowercased()
      if identifierNames.contains(name) {
        tags[index].value = .string(identifier)
        foundIdentityTag = true
        continue
      }
      guard idNames.contains(name) else { continue }
      foundIdentityTag = true
      switch tags[index].value {
      case .string:
        tags[index].value = .string(identifier)
      case .byte, .short, .int, .long:
        foundNumericID = true
        if sameIdentifier {
          // Preserve unusual legacy/runtime numeric IDs when copying
          // the same entity. Definitions remain the authoritative
          // namespaced identifier for such records.
          continue
        }
        guard let mappedID = mappedID else {
          throw MCBEEditorError.unsupported("实体 \(identifier) 没有可用的旧版数字 ID，不能替换数字 id 标签。")
        }
        tags[index].value = entityNumericIDValue(mappedID, preserving: tags[index].value)
      default:
        tags[index].value = .string(identifier)
      }
    }

    switch storageMode {
    case .legacyChunkEntity where !foundNumericID:
      guard let mappedID = mappedID, mappedID <= Int(Int16.max) else {
        throw MCBEEditorError.unsupported("旧式区块 Entity 需要可转换的数字实体 ID。")
      }
      tags.append(NBTNamedTag(name: "id", value: .short(Int16(mappedID))))
    case .modernActor where !foundIdentityTag:
      tags.append(NBTNamedTag(name: "identifier", value: .string(identifier)))
    default:
      break
    }
    return .compound(tags)
  }

  private func entityNumericIDValue(_ id: Int, preserving original: NBTValue) -> NBTValue {
    switch original {
    case .byte where id <= Int(Int8.max): return .byte(Int8(id))
    case .short where id <= Int(Int16.max): return .short(Int16(id))
    case .long: return .long(Int64(id))
    default: return .int(Int32(id))
    }
  }

  private func setTopLevelTag(
    in root: NBTValue,
    names: [String],
    preferredName: String,
    value: NBTValue
  ) -> NBTValue {
    guard case .compound(var tags) = root else { return root }
    let lowered = Set(names.map { $0.lowercased() })
    if let index = tags.firstIndex(where: { lowered.contains($0.name.lowercased()) }) {
      tags[index].value = value
    } else {
      tags.append(NBTNamedTag(name: preferredName, value: value))
    }
    return .compound(tags)
  }

  private func isEntityUniqueIDAvailable(
    _ uniqueID: Int64,
    excluding object: BedrockWorldObject?,
    database: MojangLevelDB
  ) throws -> Bool {
    let key = makeActorKey(id: uniqueID)
    if let object = object,
      case .modernActor(let currentKey, _, _, _) = object.storage,
      currentKey == key
    {
      // The selected modern actor owns this key.
    } else if try database.get(key) != nil {
      return false
    }

    for entry in try database.entries(includeValues: false, limit: 0) {
      guard let parsed = BedrockDBKey.parse(entry.key), parsed.recordType == .entity else {
        continue
      }
      guard let data = try database.get(entry.key),
        let records = try? ConsecutiveNBTCodec.decode(data)
      else { continue }
      for record in records {
        guard
          record.document.root.int64Value(namedAny: [
            "UniqueID", "UniqueId", "uniqueID", "uniqueId",
          ]) == uniqueID
        else { continue }
        if let object = object,
          case .chunkRecord(let sourceKey, _, _) = object.storage,
          sourceKey == entry.key,
          record.rawData == object.rawData
        {
          continue
        }
        return false
      }
    }
    return true
  }

  private func extractPosition(root: NBTValue, kind: BedrockWorldObjectKind)
    -> BedrockWorldObjectPosition?
  {
    if let values = root.value(namedAny: ["Pos", "pos", "Position", "position"])?.listValues,
      values.count >= 3,
      let x = values[0].numericDoubleValue,
      let y = values[1].numericDoubleValue,
      let z = values[2].numericDoubleValue
    {
      return BedrockWorldObjectPosition(x: x, y: y, z: z)
    }
    let xNames = kind == .blockEntity ? ["x", "X"] : ["x", "X", "PosX", "posX"]
    let yNames = kind == .blockEntity ? ["y", "Y"] : ["y", "Y", "PosY", "posY"]
    let zNames = kind == .blockEntity ? ["z", "Z"] : ["z", "Z", "PosZ", "posZ"]
    guard let x = root.numberValue(namedAny: xNames),
      let y = root.numberValue(namedAny: yNames),
      let z = root.numberValue(namedAny: zNames)
    else { return nil }
    return BedrockWorldObjectPosition(x: x, y: y, z: z)
  }

  private func extractDimension(root: NBTValue, fallback: Int32) -> Int32 {
    guard
      let raw = root.int64Value(namedAny: ["DimensionId", "DimensionID", "Dimension", "dimension"])
    else {
      return fallback
    }
    return Int32(clamping: raw)
  }

  private func decodeActorIDs(_ data: Data) throws -> [Int64] {
    guard data.count % 8 == 0 else {
      throw MCBEEditorError.malformedData("digp 摘要长度 \(data.count) 不是 8 的倍数。")
    }
    var values = [Int64]()
    values.reserveCapacity(data.count / 8)
    var offset = 0
    while offset < data.count {
      var bits: UInt64 = 0
      for index in 0..<8 {
        bits |= UInt64(data[offset + index]) << UInt64(index * 8)
      }
      values.append(Int64(bitPattern: bits))
      offset += 8
    }
    return values
  }

  private func encodeActorIDs(_ ids: [Int64]) -> Data {
    var data = Data()
    for id in ids {
      let bits = UInt64(bitPattern: id)
      for shift in stride(from: 0, through: 56, by: 8) {
        data.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
      }
    }
    return data
  }

  private func makeActorKey(id: Int64) -> Data {
    var key = Data("actorprefix".utf8)
    let bits = UInt64(bitPattern: id)
    for shift in stride(from: 0, through: 56, by: 8) {
      key.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
    }
    return key
  }

  private func makeDigestKey(
    x: Int32,
    z: Int32,
    dimension: Int32
  ) -> Data {
    var key = Data("digp".utf8)
    key.appendLE(x)
    key.appendLE(z)
    // The digest suffix must be the exact Bedrock chunk key. Overworld
    // chunk keys omit DimensionID; Nether and End keys include it.
    if dimension != 0 { key.appendLE(dimension) }
    return key
  }

  private func repairAppCreatedOverworldActorDigests(database: MojangLevelDB) throws -> Int {
    let prefix = Data("digp".utf8)
    var mergedByCanonicalKey = [Data: [Int64]]()
    var invalidKeys = [Data]()

    for entry in try database.entries(prefix: prefix, includeValues: true) {
      let key = entry.key
      guard key.count == 16, littleEndianInt32(key, at: 12) == 0 else { continue }
      guard let invalidValue = entry.value else { continue }
      let canonicalKey = Data(key.prefix(12))
      var ids: [Int64]
      if let cached = mergedByCanonicalKey[canonicalKey] {
        ids = cached
      } else {
        let canonicalValue = try database.get(canonicalKey)
        ids = try canonicalValue.map(decodeActorIDs) ?? []
      }
      for actorID in try decodeActorIDs(invalidValue) where !ids.contains(actorID) {
        ids.append(actorID)
      }
      mergedByCanonicalKey[canonicalKey] = ids
      invalidKeys.append(key)
    }

    guard !invalidKeys.isEmpty else { return 0 }
    let puts = mergedByCanonicalKey.map { (key: $0.key, value: encodeActorIDs($0.value)) }
    try database.applyBatch(puts: puts, deletes: invalidKeys, sync: true)
    return invalidKeys.count
  }

  private func littleEndianInt32(_ data: Data, at offset: Int) -> Int32? {
    guard offset >= 0, offset + 4 <= data.count else { return nil }
    var bits: UInt32 = 0
    for index in 0..<4 {
      bits |= UInt32(data[offset + index]) << UInt32(index * 8)
    }
    return Int32(bitPattern: bits)
  }

  private func ensureEntityDefinition(
    in root: NBTValue,
    identifier: String,
    replacing previousIdentifier: String?
  ) -> NBTValue {
    guard case .compound(var tags) = root else { return root }
    let definition = "+\(identifier)"
    let previousDefinition = previousIdentifier.map { "+\($0)" }
    if let index = tags.firstIndex(where: {
      $0.name.caseInsensitiveCompare("definitions") == .orderedSame
    }),
      case .list(.string, let currentValues) = tags[index].value
    {
      var values = [NBTValue]()
      var inserted = false
      for value in currentValues {
        guard case .string(let text) = value else {
          values.append(value)
          continue
        }
        if text == definition {
          if !inserted {
            values.append(.string(definition))
            inserted = true
          }
          continue
        }
        if previousDefinition != definition, text == previousDefinition { continue }
        values.append(value)
      }
      if !inserted { values.insert(.string(definition), at: 0) }
      tags[index].value = .list(.string, values)
    } else {
      tags.append(NBTNamedTag(name: "definitions", value: .list(.string, [.string(definition)])))
    }
    return .compound(tags)
  }

  private func commit(_ changes: [DatabaseChange], database: MojangLevelDB) throws {
    var puts = [(key: Data, value: Data)]()
    var deletes = [Data]()
    var seen = Set<Data>()
    for change in changes.reversed() where seen.insert(change.key).inserted {
      if let value = change.newValue {
        puts.append((key: change.key, value: value))
      } else {
        deletes.append(change.key)
      }
    }
    try database.applyBatch(puts: puts, deletes: deletes, sync: true)
  }
}
