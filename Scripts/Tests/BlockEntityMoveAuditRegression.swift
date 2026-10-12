import Foundation

/// Uses the production scanner, NBT writer and terrain codecs with the same
/// in-memory WorldSession fixture as the effect-command regressions.
enum BlockEntityMoveAuditRegression {
    static func run() throws {
        var failures = [String]()
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func scenario(_ name: String, _ body: () throws -> Void) {
            do { try body() }
            catch { failures.append("\(name): \(error.localizedDescription)") }
        }

        scenario("all-storage and repeated moves") {
            let (session, original) = try fixture()
            let store = BedrockWorldObjectNBTStore(session: session)
            let sourceLayers = try layers(session, x: 1)
            let peer = try entityDocument(x: 2, id: "Furnace", marker: "peer")
            let peerRaw = try BedrockNBTCodec.encode(peer)
            var current = original
            for (x, y, dimension) in [(Int32(17), Int32(64), Int32(0)), (18, 64, 0), (-17, 80, 2)] {
                let previous = current
                let edited = moved(current.document, x: x, y: y, dimension: dimension, marker: "saved-\(x)")
                let result = try store.save(object: current, document: edited)
                check(try layers(session, x: Int32(previous.position!.blockX), y: previous.position!.blockY,
                                 dimension: previous.dimension).allSatisfy(\.isAir),
                      "move left one or more source storages occupied")
                let savedLayers = try layers(session, x: x, y: y, dimension: dimension)
                check(savedLayers.count >= sourceLayers.count, "move dropped source storage layers")
                for index in sourceLayers.indices {
                    check(try savedLayers.indices.contains(index) && stateBytes(savedLayers[index]) == stateBytes(sourceLayers[index]),
                          "move changed or lost storage \(index)")
                }
                let destinationRecords = try records(session, x: x, dimension: dimension)
                check(destinationRecords.filter { matches($0.document, x: x, y: y) }.count == 1,
                      "move did not leave exactly one target block entity")
                check(destinationRecords.contains { $0.document.root.stringValue(namedAny: ["Marker"]) == "saved-\(x)" },
                      "move lost edited non-coordinate NBT")
                check(try records(session, x: Int32(previous.position!.blockX), dimension: previous.dimension)
                    .filter { matches($0.document, x: Int32(previous.position!.blockX), y: previous.position!.blockY) }.isEmpty,
                      "move left the old block entity behind")
                current = try store.refreshedObject(afterSaving: current, document: edited, result: result)
                check(current.dimension == dimension && current.position?.blockX == Int64(x) && current.position?.blockY == y,
                      "same editor could not rebind after a committed move")
            }
            check(try records(session, x: 2).contains { $0.rawData == peerRaw }, "move changed sibling NBT")
            check(try layers(session, x: 2).first?.name == "minecraft:furnace", "move changed sibling terrain")
            let before = session.db.values
            let edited = moved(current.document, x: -17, y: 80, dimension: 2, marker: "in-place")
            let result = try store.save(object: current, document: edited)
            current = try store.refreshedObject(afterSaving: current, document: edited, result: result)
            check(current.document.root.stringValue(namedAny: ["Marker"]) == "in-place", "ordinary NBT save failed after moves")
            check(before.filter { BedrockDBKey.parse($0.key)?.recordType != .blockEntity }
                == session.db.values.filter { BedrockDBKey.parse($0.key)?.recordType != .blockEntity },
                  "ordinary NBT save unexpectedly changed terrain")
        }

        scenario("target extra storages") {
            let (session, original) = try fixture()
            try putTerrain(session, chunkX: 1, layerNames: ["minecraft:stone", "minecraft:dirt", "minecraft:gold_block", "minecraft:diamond_block"], localX: 1)
            let store = BedrockWorldObjectNBTStore(session: session)
            let edited = moved(original.document, x: 17, marker: "replace-extra")
            _ = try store.save(object: original, document: edited)
            let saved = try layers(session, x: 17)
            check(saved.count == 4 && saved[3].isAir, "move retained a target storage absent from the source")
        }

        for sourceHasAirTerrain in [false, true] {
            scenario(sourceHasAirTerrain ? "air-source NBT-only move" : "orphan NBT-only move") {
                let (session, original) = try fixture()
                let sourceKey = BedrockDBKey.subChunk(x: 0, z: 0, dimension: 0, index: 4)
                if sourceHasAirTerrain {
                    let air = BedrockSubChunk(version: 9, yIndex: 4,
                        storages: [.airFilled(with: .editableAir(version: nil))], trailingData: Data())
                    try session.db.put(air.encodePersistent(), for: sourceKey)
                } else {
                    try session.db.delete(sourceKey)
                }
                try putTerrain(session, chunkX: 1, layerNames: ["minecraft:stone"], localX: 1)
                let terrainBefore = session.db.values.filter { BedrockDBKey.parse($0.key)?.recordType != .blockEntity }
                let store = BedrockWorldObjectNBTStore(session: session)
                let edited = moved(original.document, x: 17, marker: "orphan-compatible")
                let result = try store.save(object: original, document: edited)
                let refreshed = try store.refreshedObject(afterSaving: original, document: edited, result: result)
                check(refreshed.position?.blockX == 17, "NBT-only move could not rebind")
                check(terrainBefore == session.db.values.filter { BedrockDBKey.parse($0.key)?.recordType != .blockEntity },
                      "NBT-only move changed source or target terrain")
            }
        }

        scenario("numeric SubChunk and full-byte extra storage") {
            let (session, original) = try fixture()
            let sourceKey = BedrockDBKey.subChunk(x: 0, z: 0, dimension: 0, index: 4)
            let empty = try BedrockSubChunk.emptyLegacy(version: 7, yIndex: 4)
            let primary = try empty.storages[0].replacingBlockState(x: 1, y: 0, z: 1,
                with: BedrockBlockState(nbt: nil, legacyID: 54, legacyData: 3))
            let numeric = BedrockSubChunk(version: 7, yIndex: 4, storages: [primary], trailingData: empty.trailingData)
            try session.db.put(numeric.encodePersistent(), for: sourceKey)
            let sourceChunk = ChunkPosition(x: 0, z: 0, dimension: 0)
            let extraKey = BedrockDBKey(position: sourceChunk, recordType: .legacyBlockExtraData, subChunkIndex: nil).encoded()
            let extra = BedrockLegacyBlockExtraData(entries: [BedrockLegacyBlockExtraEntry(
                location: try BedrockLegacyBlockExtraEntry.location(x: 1, absoluteY: 64, z: 1),
                blockID: 8, blockData: 255)], trailingData: Data([0xef]))
            try session.db.put(extra.encodePersistent(), for: extraKey)
            try session.db.put(Data([15]), for: BedrockDBKey(position: sourceChunk, recordType: .legacyVersion, subChunkIndex: nil).encoded())
            _ = try BedrockWorldObjectNBTStore(session: session).save(object: original,
                document: moved(original.document, x: 17, marker: "numeric"))
            let saved = try layers(session, x: 17)
            check(saved.count == 2 && saved[0].legacyID == 54 && saved[0].legacyData == 3
                && saved[1].legacyID == 8 && saved[1].legacyData == 255,
                  "numeric move lost primary or full-byte legacy extra storage")
            check(try layers(session, x: 1).allSatisfy(\.isAir), "numeric move left source terrain")
            check(try BedrockLegacyBlockExtraData.decode(session.db.get(extraKey)!).trailingData == Data([0xef]),
                  "numeric move changed legacy extra trailing bytes")
        }

        scenario("LegacyTerrain backing remains LegacyTerrain") {
            let (session, original) = try fixture()
            try session.db.delete(BedrockDBKey.subChunk(x: 0, z: 0, dimension: 0, index: 4))
            var terrain = BedrockLegacyTerrain.empty()
            let index = (1 << 11) | (1 << 7) | 64
            terrain.blockIDs[index] = 54
            terrain.dataValues[index >> 1] = 3
            let sourceKey = BedrockDBKey(position: ChunkPosition(x: 0, z: 0, dimension: 0), recordType: .legacyTerrain, subChunkIndex: nil).encoded()
            try session.db.put(terrain.encodePersistent(), for: sourceKey)
            _ = try BedrockWorldObjectNBTStore(session: session).save(object: original,
                document: moved(original.document, x: 17, marker: "legacy-terrain"))
            let saved = try layers(session, x: 17)
            check(saved.count == 1 && saved[0].legacyID == 54 && saved[0].legacyData == 3,
                  "LegacyTerrain move changed block ID or metadata")
            check(try layers(session, x: 1).allSatisfy(\.isAir), "LegacyTerrain move left source terrain")
            let targetKey = BedrockDBKey(position: ChunkPosition(x: 1, z: 0, dimension: 0), recordType: .legacyTerrain, subChunkIndex: nil).encoded()
            check(try session.db.get(targetKey) != nil
                && session.db.get(BedrockDBKey.subChunk(x: 1, z: 0, dimension: 0, index: 4)) == nil,
                  "LegacyTerrain move silently changed the physical storage family")
        }

        scenario("v1 target upgrades for all source storages") {
            let (session, original) = try fixture()
            let oldAir = BedrockPaletteFormat(usesLegacyVal: true, version: nil).air
            let target = BedrockSubChunk(version: 1, yIndex: 4, storages: [.airFilled(with: oldAir)], trailingData: Data([0xaa]))
            let targetKey = BedrockDBKey.subChunk(x: 1, z: 0, dimension: 0, index: 4)
            try session.db.put(target.encodePersistent(), for: targetKey)
            _ = try BedrockWorldObjectNBTStore(session: session).save(object: original,
                document: moved(original.document, x: 17, marker: "v1-upgrade"))
            let saved = try BedrockSubChunk.decode(session.db.get(targetKey)!, keyYIndex: 4)
            check(saved.version == 8 && saved.storages.count == 3 && saved.trailingData == Data([0xaa]),
                  "v1 target lost layers or trailing bytes during v8 upgrade")
            check(saved.storages.flatMap(\.palette).allSatisfy { $0.nbt?.compoundValue(named: "val") != nil
                && $0.nbt?.compoundValue(named: "states") == nil }, "v1 target lost its legacy val schema")
        }

        func rejected(_ name: String, targetX: Int32 = 17, mutation: (WorldSession) throws -> Void) {
            scenario(name) {
                let (session, original) = try fixture()
                try mutation(session)
                let before = session.db.values
                var didReject = false
                do {
                    _ = try BedrockWorldObjectNBTStore(session: session).save(
                        object: original, document: moved(original.document, x: targetX, marker: name))
                } catch { didReject = true }
                check(didReject, "\(name) was accepted")
                check(session.db.values == before, "\(name) changed the database before rejection")
            }
        }
        rejected("target already has block entity") { session in
            try session.db.put(try BedrockNBTCodec.encode(entityDocument(x: 17)), for: entityKey(x: 17))
        }
        rejected("same-chunk target already has block entity", targetX: 2) { _ in }
        rejected("damaged source terrain") { session in
            try session.db.put(Data([9, 3, 4]), for: BedrockDBKey.subChunk(x: 0, z: 0, dimension: 0, index: 4))
        }
        rejected("damaged target terrain") { session in
            try session.db.put(Data([9, 3, 4]), for: BedrockDBKey.subChunk(x: 1, z: 0, dimension: 0, index: 4))
        }
        rejected("damaged target NBT") { session in
            try session.db.put(Data([10]), for: entityKey(x: 17))
        }
        rejected("unknown target terrain format") { session in
            try session.db.put(Data([10, 0x55, 0xff]), for: BedrockDBKey.subChunk(x: 1, z: 0, dimension: 0, index: 4))
        }
        rejected("unknown source terrain format") { session in
            try session.db.put(Data([10, 0x55, 0xff]), for: BedrockDBKey.subChunk(x: 0, z: 0, dimension: 0, index: 4))
        }
        rejected("incompatible numeric target format") { session in
            try session.db.put(try BedrockSubChunk.emptyLegacy(version: 0, yIndex: 4).encodePersistent(),
                               for: BedrockDBKey.subChunk(x: 1, z: 0, dimension: 0, index: 4))
        }
        if !failures.isEmpty {
            throw MCBEEditorError.malformedData("Block entity move audit failed:\n" + failures.joined(separator: "\n"))
        }
        print("Block entity move audit passed: every storage, repeated saves, sibling preservation, collisions and atomic rejection")
    }

    private static func fixture() throws -> (WorldSession, BedrockWorldObject) {
        let session = WorldSession()
        try putTerrain(session, chunkX: 0, layerNames: ["minecraft:chest", "minecraft:water", "minecraft:torch"], localX: 1, peer: true)
        try session.db.put(try BedrockNBTCodec.encode(entityDocument(x: 1))
            + BedrockNBTCodec.encode(entityDocument(x: 2, id: "Furnace", marker: "peer")), for: entityKey(x: 1))
        let objects = try BedrockWorldObjectScanner(database: session.db).scanRegion(
            centerX: 0, centerZ: 0, dimension: 0, radius: 0,
            includeEntities: false, includeBlockEntities: true).objects
        guard let original = objects.first(where: { $0.position?.blockX == 1 }) else {
            throw MCBEEditorError.malformedData("fixture block entity was not scanned")
        }
        return (session, original)
    }

    private static func entityDocument(x: Int32, id: String = "Chest", marker: String = "source") throws -> NBTDocument {
        NBTDocument(rootName: "preserved-root", root: .compound([
            NBTNamedTag(name: "id", value: .string(id)),
            NBTNamedTag(name: "x", value: .int(x)),
            NBTNamedTag(name: "y", value: .int(64)),
            NBTNamedTag(name: "z", value: .int(1)),
            NBTNamedTag(name: "Marker", value: .string(marker)),
            NBTNamedTag(name: "Items", value: .list(.compound, [.compound([
                NBTNamedTag(name: "Name", value: .string("minecraft:diamond")),
                NBTNamedTag(name: "Count", value: .byte(3))
            ])]))
        ]))
    }

    private static func moved(_ original: NBTDocument, x: Int32, y: Int32 = 64, dimension: Int32 = 0, marker: String) -> NBTDocument {
        guard case .compound(let tags) = original.root else { return original }
        var changed = tags.filter { !["x", "y", "DimensionId", "Marker"].contains($0.name) }
        changed.append(contentsOf: [NBTNamedTag(name: "x", value: .int(x)),
            NBTNamedTag(name: "y", value: .int(y)), NBTNamedTag(name: "DimensionId", value: .int(dimension)),
            NBTNamedTag(name: "Marker", value: .string(marker))])
        return NBTDocument(rootName: original.rootName, root: .compound(changed))
    }

    private static func putTerrain(_ session: WorldSession, chunkX: Int32, layerNames: [String], localX: Int, peer: Bool = false) throws {
        var storages = try layerNames.map { name in
            try SubChunkStorage.airFilled(with: .editableAir(version: BedrockBlockState.defaultPaletteVersion))
                .replacingBlockState(x: localX, y: 0, z: 1, with: state(name))
        }
        if peer {
            storages[0] = try storages[0].replacingBlockState(x: 2, y: 0, z: 1, with: state("minecraft:furnace"))
        }
        let subChunk = BedrockSubChunk(version: 9, yIndex: 4, storages: storages, trailingData: Data([0xab, 0xcd]))
        try session.db.put(subChunk.encodePersistent(), for: BedrockDBKey.subChunk(x: chunkX, z: 0, dimension: 0, index: 4))
    }

    private static func state(_ name: String) -> BedrockBlockState {
        BedrockBlockState(nbt: .compound([
            NBTNamedTag(name: "name", value: .string(name)), NBTNamedTag(name: "states", value: .compound([])),
            NBTNamedTag(name: "version", value: .int(BedrockBlockState.defaultPaletteVersion))
        ]), legacyID: nil, legacyData: nil)
    }

    private static func stateBytes(_ state: BedrockBlockState) throws -> Data {
        try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: state.nbt!))
    }

    private static func entityKey(x: Int32, dimension: Int32 = 0) -> Data {
        BedrockDBKey(position: ChunkPosition(x: MapCoordinate.chunk(fromBlock: x), z: 0, dimension: dimension),
                     recordType: .blockEntity, subChunkIndex: nil).encoded()
    }

    private static func records(_ session: WorldSession, x: Int32, dimension: Int32 = 0) throws -> [ConsecutiveNBTRecord] {
        try session.db.get(entityKey(x: x, dimension: dimension)).map(ConsecutiveNBTCodec.decode) ?? []
    }

    private static func matches(_ document: NBTDocument, x: Int32, y: Int32) -> Bool {
        document.root.intValue(named: "x") == x && document.root.intValue(named: "y") == y && document.root.intValue(named: "z") == 1
    }

    private static func layers(_ session: WorldSession, x: Int32, y: Int32 = 64, dimension: Int32 = 0) throws -> [BedrockBlockState] {
        let chunkX = MapCoordinate.chunk(fromBlock: x)
        let subY = Int8(MapCoordinate.floorDiv16(y))
        guard let record = try BedrockChunkSubChunkAccess.record(database: session.db,
            position: ChunkPosition(x: chunkX, z: 0, dimension: dimension), yIndex: subY) else { return [] }
        let localX = Int(Int64(x) - MapCoordinate.blockOrigin(ofChunk: chunkX))
        return record.subChunk.storages.compactMap { $0.blockState(x: localX, y: Int(y) - Int(subY) * 16, z: 1) }
    }
}
