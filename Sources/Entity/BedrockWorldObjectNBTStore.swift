import Foundation

struct BedrockWorldObjectSaveResult {
    let moved: Bool
    let destinationDimension: Int32
    let destinationChunkX: Int32
    let destinationChunkZ: Int32
}

final class BedrockWorldObjectNBTStore {
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

    func save(object: BedrockWorldObject, document: NBTDocument) throws -> BedrockWorldObjectSaveResult {
        try validateIdentity(of: object, editedDocument: document)
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

    private func saveModernActor(
        object: BedrockWorldObject,
        document: NBTDocument,
        actorKey: Data,
        digestKey: Data,
        recordIndex: Int
    ) throws -> BedrockWorldObjectSaveResult {
        guard let actorID = object.uniqueID else {
            throw BlocktopographError.malformedData("现代实体缺少 ActorUniqueID，无法安全写回。")
        }
        guard !digestKey.isEmpty else {
            throw BlocktopographError.malformedData("现代实体缺少 digp 摘要键，无法安全写回。")
        }

        let database = try session.database()
        guard let currentActorData = try database.get(actorKey) else {
            throw BlocktopographError.malformedData("actorprefix 记录已不存在，请重新扫描实体。")
        }
        var actorRecords = try ConsecutiveNBTCodec.decode(currentActorData)
        let locatedIndex = try locateRecord(
            object: object,
            in: actorRecords,
            preferredIndex: recordIndex
        )
        actorRecords[locatedIndex].document = document
        actorRecords[locatedIndex].rawData = try BedrockNBTCodec.encode(
            document,
            encoding: actorRecords[locatedIndex].encoding
        )
        let editedActorData = try ConsecutiveNBTCodec.encode(actorRecords)

        let destination = destination(for: object, document: document)
        let moved = destination.dimension != object.dimension ||
            destination.chunkX != object.chunkX || destination.chunkZ != object.chunkZ

        var changes = [DatabaseChange(
            key: actorKey,
            originalValue: currentActorData,
            newValue: editedActorData,
            label: "actorprefix"
        )]

        if moved {
            guard let currentDigest = try database.get(digestKey) else {
                throw BlocktopographError.malformedData("原 digp 摘要已不存在，请重新扫描实体。")
            }
            var sourceIDs = try decodeActorIDs(currentDigest)
            guard sourceIDs.contains(actorID) else {
                throw BlocktopographError.malformedData("原 digp 摘要不再引用此实体，请重新扫描后再编辑。")
            }
            sourceIDs.removeAll { $0 == actorID }

            let destinationDigestKey = makeDigestKey(
                x: destination.chunkX,
                z: destination.chunkZ,
                dimension: destination.dimension,
                preserveLegacyOverworldForm: digestKey.count == 12 && destination.dimension == 0
            )
            if destinationDigestKey == digestKey {
                // This can only happen when the NBT position changed inside the
                // same chunk, but keep the branch explicit for data safety.
            } else {
                let targetOriginal = try database.get(destinationDigestKey)
                var targetIDs = try targetOriginal.map(decodeActorIDs) ?? []
                if !targetIDs.contains(actorID) { targetIDs.append(actorID) }

                changes.append(DatabaseChange(
                    key: destinationDigestKey,
                    originalValue: targetOriginal,
                    newValue: encodeActorIDs(targetIDs),
                    label: "目标 digp"
                ))
                changes.append(DatabaseChange(
                    key: digestKey,
                    originalValue: currentDigest,
                    newValue: sourceIDs.isEmpty ? nil : encodeActorIDs(sourceIDs),
                    label: "原 digp"
                ))
            }
        }

        try commit(changes, database: database)
        return BedrockWorldObjectSaveResult(
            moved: moved,
            destinationDimension: destination.dimension,
            destinationChunkX: destination.chunkX,
            destinationChunkZ: destination.chunkZ
        )
    }

    private func saveChunkRecord(
        object: BedrockWorldObject,
        document: NBTDocument,
        sourceKey: Data,
        recordIndex: Int
    ) throws -> BedrockWorldObjectSaveResult {
        let database = try session.database()
        guard let sourceData = try database.get(sourceKey) else {
            throw BlocktopographError.malformedData("区块对象记录已不存在，请重新扫描。")
        }
        var sourceRecords = try ConsecutiveNBTCodec.decode(sourceData)
        let locatedIndex = try locateRecord(object: object, in: sourceRecords, preferredIndex: recordIndex)
        let sourceEncoding = sourceRecords[locatedIndex].encoding

        let destination = destination(for: object, document: document)
        let moved = destination.dimension != object.dimension ||
            destination.chunkX != object.chunkX || destination.chunkZ != object.chunkZ
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
            sourceRecords[locatedIndex].rawData = try BedrockNBTCodec.encode(document, encoding: sourceEncoding)
            let newSourceData = try ConsecutiveNBTCodec.encode(sourceRecords)
            let changes = [DatabaseChange(
                key: sourceKey,
                originalValue: sourceData,
                newValue: newSourceData,
                label: object.kind.displayName
            )]
            try commit(changes, database: database)
            return BedrockWorldObjectSaveResult(
                moved: false,
                destinationDimension: destination.dimension,
                destinationChunkX: destination.chunkX,
                destinationChunkZ: destination.chunkZ
            )
        }

        sourceRecords.remove(at: locatedIndex)
        let newSourceData = sourceRecords.isEmpty ? nil : try ConsecutiveNBTCodec.encode(sourceRecords)
        let targetOriginal = try database.get(targetKey)
        var targetRecords = try targetOriginal.map(ConsecutiveNBTCodec.decode) ?? []
        let targetEncoding = targetRecords.first?.encoding ?? sourceEncoding
        let editedRaw = try BedrockNBTCodec.encode(document, encoding: targetEncoding)
        targetRecords.append(ConsecutiveNBTRecord(document: document, rawData: editedRaw, encoding: targetEncoding))
        let newTargetData = try ConsecutiveNBTCodec.encode(targetRecords)

        let changes = [
            DatabaseChange(
                key: targetKey,
                originalValue: targetOriginal,
                newValue: newTargetData,
                label: "目标区块对象记录"
            ),
            DatabaseChange(
                key: sourceKey,
                originalValue: sourceData,
                newValue: newSourceData,
                label: "原区块对象记录"
            )
        ]
        try commit(changes, database: database)
        return BedrockWorldObjectSaveResult(
            moved: true,
            destinationDimension: destination.dimension,
            destinationChunkX: destination.chunkX,
            destinationChunkZ: destination.chunkZ
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
               $0.document.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"]) == uniqueID
           }) {
            return index
        }
        if let position = object.position,
           let index = records.firstIndex(where: { record in
               let candidate = extractPosition(root: record.document.root, kind: object.kind)
               let identifier = record.document.root.stringValue(namedAny: ["identifier", "Identifier", "id", "Id"])
               return identifier == object.identifier &&
                   candidate?.blockX == position.blockX &&
                   candidate?.blockY == position.blockY &&
                   candidate?.blockZ == position.blockZ
           }) {
            return index
        }
        throw BlocktopographError.malformedData("对象记录已经变化，无法确认要替换的 NBT。请返回列表重新扫描。")
    }

    private func validateIdentity(of object: BedrockWorldObject, editedDocument: NBTDocument) throws {
        guard object.kind == .entity, let originalID = object.uniqueID else { return }
        let editedID = editedDocument.root.int64Value(namedAny: ["UniqueID", "UniqueId", "uniqueID", "uniqueId"])
        if let editedID = editedID, editedID != originalID {
            throw BlocktopographError.unsupported("UniqueID 决定 actorprefix 键与 digp 引用，当前版本禁止修改该字段。")
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

    private func extractDimension(root: NBTValue, fallback: Int32) -> Int32 {
        guard let raw = root.int64Value(namedAny: ["DimensionId", "DimensionID", "Dimension", "dimension"]) else {
            return fallback
        }
        return Int32(clamping: raw)
    }

    private func decodeActorIDs(_ data: Data) throws -> [Int64] {
        guard data.count % 8 == 0 else {
            throw BlocktopographError.malformedData("digp 摘要长度 \(data.count) 不是 8 的倍数。")
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

    private func makeDigestKey(
        x: Int32,
        z: Int32,
        dimension: Int32,
        preserveLegacyOverworldForm: Bool
    ) -> Data {
        var key = Data("digp".utf8)
        key.appendLE(x)
        key.appendLE(z)
        if dimension != 0 || !preserveLegacyOverworldForm { key.appendLE(dimension) }
        return key
    }

    private func commit(_ changes: [DatabaseChange], database: MojangLevelDB) throws {
        var applied = [DatabaseChange]()
        do {
            for change in changes {
                if let value = change.newValue {
                    try database.put(value, for: change.key, sync: true)
                } else {
                    try database.delete(change.key, sync: true)
                }
                applied.append(change)
            }
        } catch {
            for change in applied.reversed() {
                do {
                    if let original = change.originalValue {
                        try database.put(original, for: change.key, sync: true)
                    } else {
                        try database.delete(change.key, sync: true)
                    }
                } catch {
                    // Best-effort rollback; preserve the original write error.
                }
            }
            throw error
        }
    }

}
