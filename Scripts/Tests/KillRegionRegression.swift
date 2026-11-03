import Foundation

enum KillRegionRegression {
    static func run() throws {
        for command in ["kill overworld 0 0 0 1 1 1 1", "KiLl MiNeCrAfT:OvErWoRlD 1 1 1 0 0 0 0",
                        "kill nether -1.5 -2.25 -3 0.5 2 3 0", "kill the_end 0 0 0 0 0 0 1", "kill -7 0 0 0 1 1 1 0",
                        "kill @s 0", "kill @a 1", "kill @e 0", "kill minecraft:pig 1", "kill 42 0"] {
            guard case .kill = try WorldCommandParser.parse(command) else { preconditionFailure(command) }
        }
        for command in ["kill overworld 0 0 0 1 1 1 2", "kill overworld 0 0 0 1 1 1 true",
                        "kill overworld NaN 0 0 1 1 1 1", "kill overworld 0 inf 0 1 1 1 0", "kill overworld 0 0 0 1 1 1e40 1",
                        "kill 2147483648 0 0 0 1 1 1 0", "kill overworld 0 0 0 1 1 1 1 extra", "kill @e 2"] {
            var rejected = false
            do { _ = try WorldCommandParser.parse(command) } catch { rejected = true }
            precondition(rejected, "invalid kill syntax accepted: \(command)")
        }
        for flag in [0, 1] {
            for corners in ["0 0 0 1 1 1", "1 1 1 0 0 0"] {
                try selection(flag: flag, corners: corners)
            }
        }
        try selection(flag: 0, corners: "0 0 0 1 1 1", omitFlag: true)
        try mixedActorRecords()
        let empty = WorldSession()
        try put([document("nether", 1, 1, .init(x: 0.5, y: 0.5, z: 0.5))], session: empty, key: legacyKey(1))
        let before = empty.db.values
        var rejected = false
        do { _ = try WorldCommandExecutor(session: empty).execute(WorldCommandParser.parse("kill overworld 0 0 0 1 1 1 1")) }
        catch { rejected = true }
        precondition(rejected && empty.db.values == before, "empty selection changed data")
        for command in ["kill @e 0", "kill minecraft:pig 0", "kill 101 0"] {
            let session = WorldSession()
            try put([document("pig", 101, 0, .init(x: 100, y: 64, z: 100))], session: session, key: legacyKey(0))
            _ = try WorldCommandExecutor(session: session).execute(WorldCommandParser.parse(command))
            precondition(session.db.values[legacyKey(0)] == nil, "old selector changed")
        }
        print("kill region regression passed: bounds, dimensions, player modes, duplicate IDs, modern actors and old selectors")
    }

    private static func legacyKey(_ dimension: Int32) -> Data {
        BedrockDBKey(position: ChunkPosition(x: 0, z: 0, dimension: dimension), recordType: .entity, subChunkIndex: nil).encoded()
    }

    private static func mixedActorRecords() throws {
        let session = WorldSession()
        var storageReference = Int64(991).littleEndian
        let reference = withUnsafeBytes(of: &storageReference) { Data($0) }
        var actorKey = Data("actorprefix".utf8); actorKey.append(reference)
        var digestKey = Data("digp".utf8); digestKey.appendLE(Int32(0)); digestKey.appendLE(Int32(0))
        let retained = document("outside", 32, 0, .init(x: 2, y: 2, z: 2))
        let retainedBytes = try BedrockNBTCodec.encode(retained)
        try put([document("inside", 31, 0, .init(x: 0.5, y: 0.5, z: 0.5)), retained], session: session, key: actorKey)
        try session.db.put(reference, for: digestKey)
        let executor = WorldCommandExecutor(session: session)
        _ = try executor.execute(WorldCommandParser.parse("kill overworld 0 0 0 1 1 1 0"))
        precondition(session.db.values[actorKey] == retainedBytes, "outside actor root changed")
        precondition(session.db.values[digestKey] == reference, "outside actor lost its digp reference")
        let scan = try BedrockWorldObjectScanner(database: session.db).scanAll(
            dimensions: nil, includeEntities: true, includeBlockEntities: false, maximumObjects: Int.max)
        precondition(scan.objects.count == 1 && scan.objects[0].document.root.stringValue(named: "marker") == "outside",
                     "outside actor disappeared from subsequent scans")
        _ = try executor.execute(WorldCommandParser.parse("kill overworld 2 2 2 2 2 2 0"))
        precondition(session.db.values[actorKey] == nil && session.db.values[digestKey] == nil, "last actor left a stale reference")
    }

    private static func document(_ marker: String, _ id: Int64, _ dimension: Int32,
                                 _ position: CommandEntityCoordinate?, mode: Int32? = nil) -> NBTDocument {
        var tags = [NBTNamedTag(name: "marker", value: .string(marker)), NBTNamedTag(name: "UniqueID", value: .long(id)),
                    NBTNamedTag(name: "DimensionId", value: .int(dimension))]
        if let position = position {
            tags.append(NBTNamedTag(name: "Pos", value: .list(.double, [.double(position.x), .double(position.y), .double(position.z)])))
        }
        if let mode = mode {
            tags.append(NBTNamedTag(name: "PlayerGameMode", value: .int(mode)))
            tags.append(NBTNamedTag(name: "Attributes", value: .list(.compound, [.compound([
                NBTNamedTag(name: "Name", value: .string("minecraft:health")), NBTNamedTag(name: "Current", value: .float(20)),
                NBTNamedTag(name: "Max", value: .float(20))
            ])])))
            tags.append(NBTNamedTag(name: "PlayerLevel", value: .int(7)))
        } else {
            tags.append(NBTNamedTag(name: "identifier", value: .string("minecraft:pig")))
        }
        return NBTDocument(rootName: "", root: .compound(tags))
    }

    private static func put(_ documents: [NBTDocument], session: WorldSession, key: Data) throws {
        var bytes = Data()
        for document in documents { bytes.append(try BedrockNBTCodec.encode(document)) }
        try session.db.put(bytes, for: key)
    }

    private static func selection(flag: Int, corners: String, omitFlag: Bool = false) throws {
        let session = WorldSession()
        let lower = CommandEntityCoordinate(x: 0, y: 0, z: 0)
        let middle = CommandEntityCoordinate(x: 0.5, y: 0.5, z: 0.5)
        let retained = [document("outsideX", 103, 0, .init(x: 1.0001, y: 0.5, z: 0.5)),
                        document("outsideY", 105, 0, .init(x: 0.5, y: -0.0001, z: 0.5)),
                        document("outsideZ", 106, 0, .init(x: 0.5, y: 0.5, z: 1.0001)), document("noPos", 107, 0, nil)]
        try put([document("lower", 101, 0, lower), document("upper", 102, 0, .init(x: 1, y: 1, z: 1)),
                 document("middle", 103, 0, middle), document("duplicate", 103, 0, .init(x: 0.75, y: 0.75, z: 0.75))] + retained,
                session: session, key: legacyKey(0))
        var expectedLegacy = Data()
        for document in retained { expectedLegacy.append(try BedrockNBTCodec.encode(document)) }
        try put([document("otherDimension", 201, 1, middle)], session: session, key: legacyKey(1))
        let otherDimensionBefore = session.db.values[legacyKey(1)]!
        var storageReference = Int64(501).littleEndian
        let reference = withUnsafeBytes(of: &storageReference) { Data($0) }
        var actorKey = Data("actorprefix".utf8); actorKey.append(reference)
        var digestKey = Data("digp".utf8); digestKey.appendLE(Int32(0)); digestKey.appendLE(Int32(0)); digestKey.appendLE(Int32(1))
        try put([document("modern", 901, 0, middle)], session: session, key: actorKey)
        try session.db.put(reference, for: digestKey)
        let chestKey = BedrockDBKey(position: ChunkPosition(x: 0, z: 0, dimension: 0), recordType: .blockEntity, subChunkIndex: nil).encoded()
        try put([NBTDocument(rootName: "", root: .compound([NBTNamedTag(name: "id", value: .string("Chest")),
            NBTNamedTag(name: "x", value: .int(0)), NBTNamedTag(name: "y", value: .int(0)), NBTNamedTag(name: "z", value: .int(0))]))], session: session, key: chestKey)
        let chestBefore = session.db.values[chestKey]!
        let players: [(String, Int32, Int32, CommandEntityCoordinate?, Bool)] = [
            ("~local_player", 0, 0, middle, true), ("player_creative", 1, 0, .init(x: 1, y: 0.5, z: 0.5), true),
            ("player_adventure", 2, 0, .init(x: 0, y: 0.5, z: 0.5), true), ("player_spectator", 6, 0, middle, true),
            ("player_outside", 0, 0, .init(x: 1.0001, y: 0.5, z: 0.5), false),
            ("player_nether", 0, 1, middle, false), ("player_noPos", 0, 0, nil, false)]
        var before = [Data: Data]()
        for (index, p) in players.enumerated() {
            let key = Data(p.0.utf8)
            try put([document(p.0, Int64(1000 + index), p.2, p.3, mode: p.1)], session: session, key: key)
            before[key] = session.db.values[key]!
        }
        let result = try WorldCommandExecutor(session: session).execute(WorldCommandParser.parse(omitFlag ? "kill overworld \(corners)" : "kill overworld \(corners) \(flag)"))
        precondition(result.changedWorld && result.message.contains("删除 5 个非玩家实体"), "selected entity count")
        precondition(session.db.values[legacyKey(0)] == expectedLegacy, "unselected legacy records changed")
        precondition(session.db.values[legacyKey(1)] == otherDimensionBefore, "other dimension changed")
        precondition(session.db.values[actorKey] == nil && session.db.values[digestKey] == nil, "actor/digest not deleted")
        precondition(session.db.values[chestKey] == chestBefore, "block entity changed")
        for p in players {
            let key = Data(p.0.utf8), selected = p.4 && (p.1 != 1 || flag == 1)
            let after = session.db.values[key]!
            if !selected { precondition(after == before[key], "unselected player changed: \(p.0)") }
            let root = try BedrockNBTCodec.decode(after).root
            guard case .list(_, let attributes)? = root.compoundValue(named: "Attributes"),
                  case .float(let health)? = attributes[0].compoundValue(named: "Current") else { preconditionFailure("health lost") }
            precondition(health == (selected ? 0 : 20), "player health / creative switch: \(p.0)")
            precondition(root.int64Value(namedAny: ["PlayerLevel"]) == 7, "unrelated player NBT changed")
        }
    }
}
