import Foundation

final class BedrockWorldObjectScanner {
    private let database: MojangLevelDB

    init(database: MojangLevelDB) {
        self.database = database
    }

    func scanRegion(
        centerX: Int32,
        centerZ: Int32,
        dimension: Int32,
        radius: Int,
        includeEntities: Bool,
        includeBlockEntities: Bool,
        maximumObjects: Int = 5_000,
        shouldCancel: () -> Bool = { false }
    ) throws -> BedrockWorldObjectScanResult {
        guard includeEntities || includeBlockEntities else { return .empty }

        var objects = [BedrockWorldObject]()
        var diagnostics = [String]()
        var seenActors = Set<Int64>()
        var actorDigestCount = 0
        var actorRecordCount = 0
        var legacyEntityRecordCount = 0
        var blockEntityRecordCount = 0

        outer: for chunkZ in (centerZ - Int32(radius))...(centerZ + Int32(radius)) {
            for chunkX in (centerX - Int32(radius))...(centerX + Int32(radius)) {
                if shouldCancel() { break outer }
                if objects.count >= maximumObjects {
                    diagnostics.append("达到 \(maximumObjects) 个对象的安全上限，结果已截断。")
                    break outer
                }

                if includeBlockEntities {
                    let key = BedrockDBKey(
                        position: ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension),
                        recordType: .blockEntity,
                        subChunkIndex: nil
                    ).encoded()
                    if let data = try database.get(key) {
                        blockEntityRecordCount += 1
                        do {
                            let decoded = try decodeObjects(
                                data: data,
                                kind: .blockEntity,
                                dimension: dimension,
                                chunkX: chunkX,
                                chunkZ: chunkZ,
                                source: .blockEntity,
                                actorID: nil,
                                storageKey: key,
                                digestKey: nil
                            )
                            objects.append(contentsOf: decoded.prefix(max(0, maximumObjects - objects.count)))
                        } catch {
                            diagnostics.append("方块实体 (\(chunkX),\(chunkZ))：\(error.localizedDescription)")
                        }
                    }
                }

                guard includeEntities else { continue }

                // Legacy worlds store consecutive actor NBT roots under the
                // ordinary chunk Entity record (tag 0x32).
                let legacyKey = BedrockDBKey(
                    position: ChunkPosition(x: chunkX, z: chunkZ, dimension: dimension),
                    recordType: .entity,
                    subChunkIndex: nil
                ).encoded()
                if let data = try database.get(legacyKey) {
                    legacyEntityRecordCount += 1
                    do {
                        let decoded = try decodeObjects(
                            data: data,
                            kind: .entity,
                            dimension: dimension,
                            chunkX: chunkX,
                            chunkZ: chunkZ,
                            source: .legacyChunkEntity,
                            actorID: nil,
                            storageKey: legacyKey,
                            digestKey: nil
                        )
                        objects.append(contentsOf: decoded.prefix(max(0, maximumObjects - objects.count)))
                    } catch {
                        diagnostics.append("旧实体 (\(chunkX),\(chunkZ))：\(error.localizedDescription)")
                    }
                }

                // Modern worlds store a digest per chunk and one actorprefix
                // value per unique actor. Try both current and old overworld
                // chunk-key forms because Bedrock can retain either in old worlds.
                var digestEntry: (key: Data, data: Data)?
                for digestKey in actorDigestKeys(x: chunkX, z: chunkZ, dimension: dimension) {
                    if let found = try database.get(digestKey) {
                        digestEntry = (digestKey, found)
                        break
                    }
                }
                guard let digestEntry = digestEntry else { continue }
                let digest = digestEntry.data
                actorDigestCount += 1

                if digest.count % 8 != 0 {
                    diagnostics.append("实体摘要 (\(chunkX),\(chunkZ)) 长度 \(digest.count) 不是 8 的倍数。")
                }
                let usable = digest.count - digest.count % 8
                var offset = 0
                while offset < usable {
                    if shouldCancel() { break outer }
                    let actorID = try littleEndianInt64(digest, at: offset)
                    offset += 8
                    guard seenActors.insert(actorID).inserted else { continue }
                    guard objects.count < maximumObjects else { break outer }
                    let actorStorageKey = actorKey(id: actorID)
                    guard let actorData = try database.get(actorStorageKey) else {
                        diagnostics.append("摘要引用的 actorprefix 记录不存在：\(actorID)")
                        continue
                    }
                    actorRecordCount += 1
                    do {
                        let decoded = try decodeObjects(
                            data: actorData,
                            kind: .entity,
                            dimension: dimension,
                            chunkX: chunkX,
                            chunkZ: chunkZ,
                            source: .modernActor,
                            actorID: actorID,
                            storageKey: actorStorageKey,
                            digestKey: digestEntry.key
                        )
                        objects.append(contentsOf: decoded.prefix(max(0, maximumObjects - objects.count)))
                    } catch {
                        diagnostics.append("实体 \(actorID)：\(error.localizedDescription)")
                    }
                }
            }
        }

        var uniqueObjects = [BedrockWorldObject]()
        var objectIndex = [String: Int]()
        for object in objects {
            if let existing = objectIndex[object.stableID] {
                // Prefer modern actor records over the legacy per-chunk copy
                // when a transition world happens to contain both.
                if uniqueObjects[existing].source != .modernActor && object.source == .modernActor {
                    uniqueObjects[existing] = object
                }
            } else {
                objectIndex[object.stableID] = uniqueObjects.count
                uniqueObjects.append(object)
            }
        }
        objects = uniqueObjects

        objects.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            if lhs.displayName != rhs.displayName {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            let lp = lhs.position
            let rp = rhs.position
            if lp?.blockZ != rp?.blockZ { return (lp?.blockZ ?? 0) < (rp?.blockZ ?? 0) }
            return (lp?.blockX ?? 0) < (rp?.blockX ?? 0)
        }

        return BedrockWorldObjectScanResult(
            objects: objects,
            diagnostics: diagnostics,
            actorDigestCount: actorDigestCount,
            actorRecordCount: actorRecordCount,
            legacyEntityRecordCount: legacyEntityRecordCount,
            blockEntityRecordCount: blockEntityRecordCount
        )
    }


    /// Scans every entity and block-entity record in the selected dimensions.
    /// Modern actor records are read directly from `actorprefix`; their owning
    /// digp entry supplies the fallback dimension/chunk and preserves editing.
    func scanAll(
        dimensions: Set<Int32>?,
        includeEntities: Bool,
        includeBlockEntities: Bool,
        maximumObjects: Int = 200_000,
        shouldCancel: () -> Bool = { false }
    ) throws -> BedrockWorldObjectScanResult {
        guard includeEntities || includeBlockEntities else { return .empty }

        struct ActorDigestLocation {
            let key: Data
            let dimension: Int32
            let chunkX: Int32
            let chunkZ: Int32
        }

        var objects = [BedrockWorldObject]()
        var diagnostics = [String]()
        var actorDigestCount = 0
        var actorRecordCount = 0
        var legacyEntityRecordCount = 0
        var blockEntityRecordCount = 0
        var digestLocationByActor = [Int64: ActorDigestLocation]()

        func dimensionAllowed(_ dimension: Int32) -> Bool {
            dimensions?.contains(dimension) ?? true
        }

        if includeEntities {
            let digestPrefix = Data("digp".utf8)
            for entry in try database.entries(prefix: digestPrefix, includeValues: true, limit: 0) {
                if shouldCancel() { break }
                guard let value = entry.value else { continue }
                let location: ActorDigestLocation
                if entry.key.count == digestPrefix.count + 8,
                   let x = try? entry.key.littleEndianInt32(at: digestPrefix.count),
                   let z = try? entry.key.littleEndianInt32(at: digestPrefix.count + 4) {
                    location = ActorDigestLocation(key: entry.key, dimension: 0, chunkX: x, chunkZ: z)
                } else if entry.key.count >= digestPrefix.count + 12,
                          let x = try? entry.key.littleEndianInt32(at: digestPrefix.count),
                          let z = try? entry.key.littleEndianInt32(at: digestPrefix.count + 4),
                          let dimension = try? entry.key.littleEndianInt32(at: digestPrefix.count + 8) {
                    location = ActorDigestLocation(key: entry.key, dimension: dimension, chunkX: x, chunkZ: z)
                } else {
                    diagnostics.append("无法解析实体摘要键：\(entry.key.hexString)")
                    continue
                }
                actorDigestCount += 1
                if value.count % 8 != 0 {
                    diagnostics.append("实体摘要 (\(location.chunkX),\(location.chunkZ)) 长度 \(value.count) 不是 8 的倍数。")
                }
                let usable = value.count - value.count % 8
                var offset = 0
                while offset < usable {
                    let actorID = try littleEndianInt64(value, at: offset)
                    offset += 8
                    if digestLocationByActor[actorID] == nil {
                        digestLocationByActor[actorID] = location
                    }
                }
            }

            let actorPrefix = Data("actorprefix".utf8)
            for entry in try database.entries(prefix: actorPrefix, includeValues: true, limit: 0) {
                if shouldCancel() || objects.count >= maximumObjects { break }
                guard entry.key.count >= actorPrefix.count + 8,
                      let actorData = entry.value else { continue }
                let actorID = try littleEndianInt64(entry.key, at: actorPrefix.count)
                guard let location = digestLocationByActor[actorID] else {
                    diagnostics.append("未被 digp 引用的孤立 actorprefix，已忽略：\(actorID)")
                    continue
                }
                if !dimensionAllowed(location.dimension) { continue }
                actorRecordCount += 1
                do {
                    let decoded = try decodeObjects(
                        data: actorData,
                        kind: .entity,
                        dimension: location.dimension,
                        chunkX: location.chunkX,
                        chunkZ: location.chunkZ,
                        source: .modernActor,
                        actorID: actorID,
                        storageKey: entry.key,
                        digestKey: location.key
                    ).filter { dimensionAllowed($0.dimension) }
                    objects.append(contentsOf: decoded.prefix(max(0, maximumObjects - objects.count)))
                } catch {
                    diagnostics.append("实体 \(actorID)：\(error.localizedDescription)")
                }
            }
        }

        if includeBlockEntities || includeEntities {
            // Fetch keys only first. Reading values only for 0x31/0x32 avoids
            // loading every SubChunk payload into memory for a world-wide scan.
            for entry in try database.entries(includeValues: false, limit: 0) {
                if shouldCancel() || objects.count >= maximumObjects { break }
                guard entry.key.count == 9 || entry.key.count == 13,
                      let parsed = BedrockDBKey.parse(entry.key),
                      dimensionAllowed(parsed.position.dimension) else { continue }

                let kind: BedrockWorldObjectKind
                let source: BedrockWorldObjectSource
                switch parsed.recordType {
                case .blockEntity where includeBlockEntities:
                    kind = .blockEntity
                    source = .blockEntity
                    blockEntityRecordCount += 1
                case .entity where includeEntities:
                    kind = .entity
                    source = .legacyChunkEntity
                    legacyEntityRecordCount += 1
                default:
                    continue
                }
                guard let data = try database.get(entry.key) else { continue }
                do {
                    let decoded = try decodeObjects(
                        data: data,
                        kind: kind,
                        dimension: parsed.position.dimension,
                        chunkX: parsed.position.x,
                        chunkZ: parsed.position.z,
                        source: source,
                        actorID: nil,
                        storageKey: entry.key,
                        digestKey: nil
                    ).filter { dimensionAllowed($0.dimension) }
                    objects.append(contentsOf: decoded.prefix(max(0, maximumObjects - objects.count)))
                } catch {
                    let label = kind == .entity ? "旧实体" : "方块实体"
                    diagnostics.append("\(label) (\(parsed.position.x),\(parsed.position.z))：\(error.localizedDescription)")
                }
            }
        }

        if objects.count >= maximumObjects {
            diagnostics.append("达到 \(maximumObjects) 个对象的安全上限，结果已截断。")
        }

        var uniqueObjects = [BedrockWorldObject]()
        var objectIndex = [String: Int]()
        for object in objects {
            if let existing = objectIndex[object.stableID] {
                if uniqueObjects[existing].source != .modernActor && object.source == .modernActor {
                    uniqueObjects[existing] = object
                }
            } else {
                objectIndex[object.stableID] = uniqueObjects.count
                uniqueObjects.append(object)
            }
        }
        uniqueObjects.sort { lhs, rhs in
            if lhs.dimension != rhs.dimension { return lhs.dimension < rhs.dimension }
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            if lhs.displayName != rhs.displayName {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            let lp = lhs.position
            let rp = rhs.position
            if lp?.blockZ != rp?.blockZ { return (lp?.blockZ ?? 0) < (rp?.blockZ ?? 0) }
            if lp?.blockX != rp?.blockX { return (lp?.blockX ?? 0) < (rp?.blockX ?? 0) }
            return (lp?.blockY ?? 0) < (rp?.blockY ?? 0)
        }

        return BedrockWorldObjectScanResult(
            objects: uniqueObjects,
            diagnostics: diagnostics,
            actorDigestCount: actorDigestCount,
            actorRecordCount: actorRecordCount,
            legacyEntityRecordCount: legacyEntityRecordCount,
            blockEntityRecordCount: blockEntityRecordCount
        )
    }

    /// Resolves a specific set of entity UniqueIDs across the whole world.
    /// Modern actor records are addressed directly; unresolved IDs are then
    /// searched in every legacy chunk Entity record.
    func scanEntities(
        uniqueIDs: Set<Int64>,
        shouldCancel: () -> Bool = { false }
    ) throws -> BedrockWorldObjectScanResult {
        guard !uniqueIDs.isEmpty else { return .empty }

        var objects = [BedrockWorldObject]()
        var diagnostics = [String]()
        var actorRecordCount = 0
        var legacyEntityRecordCount = 0
        let digestKeys = try digestKeys(for: uniqueIDs, shouldCancel: shouldCancel)

        for actorID in uniqueIDs.sorted() {
            if shouldCancel() { break }
            let storageKey = actorKey(id: actorID)
            guard let data = try database.get(storageKey) else { continue }
            actorRecordCount += 1
            do {
                let decoded = try decodeObjects(
                    data: data,
                    kind: .entity,
                    dimension: 0,
                    chunkX: 0,
                    chunkZ: 0,
                    source: .modernActor,
                    actorID: actorID,
                    storageKey: storageKey,
                    digestKey: digestKeys[actorID]
                )
                objects.append(contentsOf: decoded.filter { uniqueIDs.contains($0.uniqueID ?? actorID) })
            } catch {
                diagnostics.append("实体 \(actorID)：\(error.localizedDescription)")
            }
        }

        var resolved = Set(objects.compactMap(\.uniqueID))
        let unresolved = uniqueIDs.subtracting(resolved)
        if !unresolved.isEmpty && !shouldCancel() {
            let entries = try database.entries(includeValues: true)
            for entry in entries {
                if shouldCancel() { break }
                guard let parsed = BedrockDBKey.parse(entry.key), parsed.recordType == .entity,
                      let data = entry.value else { continue }
                legacyEntityRecordCount += 1
                do {
                    let decoded = try decodeObjects(
                        data: data,
                        kind: .entity,
                        dimension: parsed.position.dimension,
                        chunkX: parsed.position.x,
                        chunkZ: parsed.position.z,
                        source: .legacyChunkEntity,
                        actorID: nil,
                        storageKey: entry.key,
                        digestKey: nil
                    )
                    for object in decoded {
                        guard let uniqueID = object.uniqueID, unresolved.contains(uniqueID) else { continue }
                        objects.append(object)
                        resolved.insert(uniqueID)
                    }
                    if unresolved.isSubset(of: resolved) { break }
                } catch {
                    diagnostics.append("旧实体 \(parsed.position.x),\(parsed.position.z)：\(error.localizedDescription)")
                }
            }
        }

        let unresolvedIDs = uniqueIDs.subtracting(resolved).sorted()
        if !unresolvedIDs.isEmpty {
            diagnostics.append("未在世界实体中找到 Dwellers ID（实体 UniqueID）：\(unresolvedIDs.map(String.init).joined(separator: ", "))")
        }

        var deduplicated = [String: BedrockWorldObject]()
        for object in objects where object.uniqueID.map(uniqueIDs.contains) == true {
            if let current = deduplicated[object.stableID], current.source == .modernActor { continue }
            deduplicated[object.stableID] = object
        }
        let sorted = deduplicated.values.sorted { lhs, rhs in
            let left = lhs.uniqueID ?? Int64.min
            let right = rhs.uniqueID ?? Int64.min
            if left != right { return left < right }
            return lhs.stableID < rhs.stableID
        }
        return BedrockWorldObjectScanResult(
            objects: sorted,
            diagnostics: diagnostics,
            actorDigestCount: digestKeys.count,
            actorRecordCount: actorRecordCount,
            legacyEntityRecordCount: legacyEntityRecordCount,
            blockEntityRecordCount: 0
        )
    }

    private func digestKeys(
        for uniqueIDs: Set<Int64>,
        shouldCancel: () -> Bool
    ) throws -> [Int64: Data] {
        let prefix = Data("digp".utf8)
        var result = [Int64: Data]()
        for entry in try database.entries(prefix: prefix, includeValues: true) {
            if shouldCancel() { break }
            guard let value = entry.value else { continue }
            let usable = value.count - value.count % 8
            var offset = 0
            while offset < usable {
                let actorID = try littleEndianInt64(value, at: offset)
                offset += 8
                if uniqueIDs.contains(actorID), result[actorID] == nil {
                    result[actorID] = entry.key
                }
            }
            if result.count == uniqueIDs.count { break }
        }
        return result
    }

    private func actorDigestKeys(x: Int32, z: Int32, dimension: Int32) -> [Data] {
        var canonical = Data("digp".utf8)
        canonical.appendLE(x)
        canonical.appendLE(z)
        if dimension != 0 { canonical.appendLE(dimension) }
        guard dimension == 0 else { return [canonical] }

        // Compatibility only: v1.1.3-v1.1.5 incorrectly appended a zero
        // DimensionID in the overworld. Prefer the game-recognized key.
        var nonCanonical = canonical
        nonCanonical.appendLE(Int32(0))
        return [canonical, nonCanonical]
    }

    private func actorKey(id: Int64) -> Data {
        var key = Data("actorprefix".utf8)
        let bits = UInt64(bitPattern: id)
        for shift in stride(from: 0, through: 56, by: 8) {
            key.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
        }
        return key
    }

    private func littleEndianInt64(_ data: Data, at offset: Int) throws -> Int64 {
        guard offset >= 0, offset + 8 <= data.count else {
            throw BlocktopographError.malformedData("实体 ID 越界")
        }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        return Int64(bitPattern: value)
    }

    private func decodeObjects(
        data: Data,
        kind: BedrockWorldObjectKind,
        dimension: Int32,
        chunkX: Int32,
        chunkZ: Int32,
        source: BedrockWorldObjectSource,
        actorID: Int64?,
        storageKey: Data,
        digestKey: Data?
    ) throws -> [BedrockWorldObject] {
        let documents = try ConsecutiveNBTCodec.decode(data)
        return documents.enumerated().map { index, item in
            makeObject(
                document: item.document,
                rawData: item.rawData,
                index: index,
                kind: kind,
                dimension: dimension,
                fallbackChunkX: chunkX,
                fallbackChunkZ: chunkZ,
                source: source,
                actorID: actorID,
                storage: source == .modernActor
                    ? .modernActor(
                        actorKey: storageKey,
                        digestKey: digestKey ?? Data(),
                        recordIndex: index,
                        encoding: item.encoding
                    )
                    : .chunkRecord(
                        key: storageKey,
                        recordIndex: index,
                        encoding: item.encoding
                    )
            )
        }
    }

    private func makeObject(
        document: NBTDocument,
        rawData: Data,
        index: Int,
        kind: BedrockWorldObjectKind,
        dimension: Int32,
        fallbackChunkX: Int32,
        fallbackChunkZ: Int32,
        source: BedrockWorldObjectSource,
        actorID: Int64?,
        storage: BedrockWorldObjectStorage
    ) -> BedrockWorldObject {
        let root = document.root
        let resolvedDimension = extractDimension(root: root) ?? dimension
        let identifier = resolveIdentifier(root: root, kind: kind)
        let customName = root.stringValue(namedAny: ["CustomName", "customName", "Name", "name"])
        let position = extractPosition(root: root, kind: kind)
        let chunkX = position.map { MapCoordinate.chunk(fromBlock: $0.blockX) } ?? fallbackChunkX
        let chunkZ = position.map { MapCoordinate.chunk(fromBlock: $0.blockZ) } ?? fallbackChunkZ
        let uniqueID = actorID ?? root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"])
        let itemCount = countItems(in: root)
        let stableID: String
        if let uniqueID = uniqueID {
            stableID = "actor:\(uniqueID)"
        } else if let position = position {
            stableID = "\(kind.rawValue):\(resolvedDimension):\(position.blockX):\(position.blockY):\(position.blockZ):\(identifier):\(index)"
        } else {
            stableID = "\(kind.rawValue):\(resolvedDimension):\(fallbackChunkX):\(fallbackChunkZ):\(identifier):\(index)"
        }
        return BedrockWorldObject(
            stableID: stableID,
            kind: kind,
            identifier: identifier,
            customName: customName,
            position: position,
            dimension: resolvedDimension,
            chunkX: chunkX,
            chunkZ: chunkZ,
            source: source,
            uniqueID: uniqueID,
            itemCount: itemCount,
            document: document,
            rawData: rawData,
            storage: storage
        )
    }

    private func resolveIdentifier(root: NBTValue, kind: BedrockWorldObjectKind) -> String {
        let primaryNames = ["identifier", "Identifier", "id", "Id"]

        if kind == .entity {
            if let raw = root.stringValue(namedAny: primaryNames) {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    if let numericID = parseEntityNumericID(value) {
                        if let entry = BedrockDataValueCatalog.entity(forNumericID: numericID) {
                            return entry.identifier
                        }
                        if let definition = firstEntityDefinitionIdentifier(root: root) {
                            return definition
                        }
                        return "数字实体ID:\(numericID)"
                    }
                    return value
                }
            }

            if let numericID = root.int64Value(namedAny: primaryNames + ["EntityType", "entityType", "EntityID", "entityID"]) {
                if let entry = BedrockDataValueCatalog.entity(forNumericID: numericID) {
                    return entry.identifier
                }
                if let definition = firstEntityDefinitionIdentifier(root: root) {
                    return definition
                }
                return "数字实体ID:\(numericID)"
            }
        } else if let raw = root.stringValue(namedAny: primaryNames) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }

        return "未知\(kind.displayName)"
    }

    private func parseEntityNumericID(_ rawValue: String) -> Int64? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("0x") {
            return Int64(value.dropFirst(2), radix: 16)
        }
        return Int64(value)
    }

    private func firstEntityDefinitionIdentifier(root: NBTValue) -> String? {
        guard let first = root.value(namedAny: ["definitions", "Definitions"])?.listValues?.first,
              case .string(let rawDefinition) = first else {
            return nil
        }
        var value = rawDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("+") {
            value.removeFirst()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func extractDimension(root: NBTValue) -> Int32? {
        guard let value = root.int64Value(namedAny: ["DimensionId", "DimensionID", "dimensionId", "dimension", "Dimension"]) else {
            return nil
        }
        return Int32(clamping: value)
    }

    private func extractPosition(root: NBTValue, kind: BedrockWorldObjectKind) -> BedrockWorldObjectPosition? {
        if let values = root.value(namedAny: ["Pos", "pos", "Position", "position"])?.listValues,
           values.count >= 3,
           let x = values[0].numericDoubleValue,
           let y = values[1].numericDoubleValue,
           let z = values[2].numericDoubleValue {
            return BedrockWorldObjectPosition(x: x, y: y, z: z)
        }

        let xNames = kind == .blockEntity ? ["x", "X"] : ["x", "X", "PosX", "posX"]
        let yNames = kind == .blockEntity ? ["y", "Y"] : ["y", "Y", "PosY", "posY"]
        let zNames = kind == .blockEntity ? ["z", "Z"] : ["z", "Z", "PosZ", "posZ"]
        guard let x = root.numberValue(namedAny: xNames),
              let y = root.numberValue(namedAny: yNames),
              let z = root.numberValue(namedAny: zNames) else { return nil }
        return BedrockWorldObjectPosition(x: x, y: y, z: z)
    }

    private func countItems(in root: NBTValue) -> Int {
        let candidates = ["Items", "items", "Inventory", "inventory", "Armor", "Mainhand", "Offhand"]
        var count = 0
        for name in candidates {
            guard let values = root.value(namedAny: [name])?.listValues else { continue }
            count += values.reduce(0) { partial, value in
                guard case .compound = value else { return partial + 1 }
                let stackCount = value.int64Value(namedAny: ["Count", "count"]) ?? 1
                return partial + (stackCount > 0 ? 1 : 0)
            }
        }
        return count
    }
}
