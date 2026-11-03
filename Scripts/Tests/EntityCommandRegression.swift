import Foundation

// The portable runner supplies an in-memory database. All command parsing,
// scanning, NBT decoding and rendering below use production implementations.
enum EntityCommandRegression {
    static func run() throws {
        for text in ["entity @e", "entity @s", "entity @a", "entity 12345678", "entity -42", "entity 2147483648",
                     "entity -9223372036854775808", "entity 9223372036854775807", "entity minecraft:cow", "entity @e 0",
                     "entity @a nether", "entity 42 0 -0.5 64.25 8.5 1.5 65.25 10.5"] {
            guard case .entity = try WorldCommandParser.parse(text) else { preconditionFailure(text) }
        }
        for text in ["entity 0", "entity 9223372036854775808", "entity -9223372036854775809", "entity @p",
                     "entity @a 2147483648", "entity @e 0 0 64 0", "entity @e 0 0 64 0 1 65",
                     "entity @e 0 0 64 0 1 65 1 extra", "entity @a 0 NaN 0 0 1 1 1"] {
            var rejected = false
            do { _ = try WorldCommandParser.parse(text) } catch { rejected = true }
            precondition(rejected, "invalid target query accepted: \(text)")
        }
        var incompleteRejected = false
        do { _ = try WorldCommandParser.parse("entity @e 0 0 64 0 1 65", dimensionResolver: { _ in 0 }) }
        catch { incompleteRejected = true }
        precondition(incompleteRejected, "incomplete target bounds must not use a permissive dimension resolver")
        func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
        let session = WorldSession()
        let executor = WorldCommandExecutor(session: session)
        func query(_ text: String) throws -> WorldCommandExecutionResult {
            try executor.execute(WorldCommandParser.parse(text, dimensionResolver: DimensionStore(database: session.db).resolve))
        }
        func doc(_ tags: [NBTNamedTag]) -> NBTDocument { NBTDocument(rootName: "", root: .compound(tags)) }
        func entity(_ type: NBTNamedTag, _ id: Int64, _ x: Double, _ y: Double, _ z: Double, extra: [NBTNamedTag] = []) -> NBTDocument {
            doc([type, NBTNamedTag(name: "UniqueID", value: .long(id)),
                 NBTNamedTag(name: "Pos", value: .list(.double, [.double(x), .double(y), .double(z)]))] + extra)
        }
        func legacyKey(_ dim: Int32, _ x: Int32 = 0) -> Data {
            BedrockDBKey(position: ChunkPosition(x: x, z: 0, dimension: dim), recordType: .entity, subChunkIndex: nil).encoded()
        }
        func put(_ documents: [NBTDocument], at key: Data) throws {
            var bytes = Data()
            for document in documents { bytes.append(try BedrockNBTCodec.encode(document)) }
            try session.db.put(bytes, for: key)
        }
        let pig = doc([NBTNamedTag(name: "identifier", value: .string("minecraft:pig")), NBTNamedTag(name: "UniqueID", value: .long(12_345_678))])
        let chicken = NBTNamedTag(name: "identifier", value: .string("minecraft:chicken"))
        let cow = entity(NBTNamedTag(name: "definitions", value: .list(.string, [.string("+minecraft:cow")])), 42, -0.5, 64.25, 8.5, extra: [
            NBTNamedTag(name: "ExactNaN", value: .float(Float(bitPattern: 0x7FC01234))),
            NBTNamedTag(name: "Nested", value: .compound([
                NBTNamedTag(name: "Exact", value: .long(9_007_199_254_740_993)),
                NBTNamedTag(name: "Text", value: .string("line\nquote\"slash\\")),
                NBTNamedTag(name: "Bytes", value: .byteArray(Data([0, 255]))),
                NBTNamedTag(name: "Ints", value: .intArray([-1, 2])),
                NBTNamedTag(name: "Longs", value: .longArray([Int64.min, Int64.max]))
            ])),
            NBTNamedTag(name: "Lines", value: .list(.string, [.string("a\nb\"c\\,d")])),
            NBTNamedTag(name: "Matrix", value: .list(.list, [.list(.int, [.int(1), .int(2)]), .list(.int, [.int(3)])])),
            NBTNamedTag(name: "Mixed", value: .list(.list, [.list(.int, [.int(1)]), .list(.string, [.string("2")])])),
            NBTNamedTag(name: "Deep", value: .list(.list, [.list(.list, [.list(.int, [.int(1)]), .list(.string, [.string("2")])])])),
            NBTNamedTag(name: "Items", value: .list(.compound, [.compound([NBTNamedTag(name: "Name", value: .string("minecraft:stone"))])]))
        ])
        try put([pig, cow, entity(NBTNamedTag(name: "id", value: .int(12)), 42, 1.5, 65.25, 10.5),
                 entity(chicken, 51, 1.5001, 65, 10), entity(chicken, 52, 0, 65.2501, 10), entity(chicken, 53, 0, 65, 10.5001)], at: legacyKey(0))
        try put([entity(chicken, 42, 20, 65, 10)], at: legacyKey(0, 1))
        try put([entity(chicken, 60, 0, 65, 10)], at: legacyKey(1))
        var ref = Int64(999).littleEndian
        let reference = withUnsafeBytes(of: &ref) { Data($0) }
        var actorKey = Data("actorprefix".utf8); actorKey.append(reference)
        var digestKey = Data("digp".utf8); digestKey.appendLE(Int32(0)); digestKey.appendLE(Int32(0)); digestKey.appendLE(Int32(1))
        try session.db.put(reference, for: digestKey)
        try put([entity(NBTNamedTag(name: "Identifier", value: .string("minecraft:enderman")), 91, 0, 65, 10,
                        extra: [NBTNamedTag(name: "DimensionId", value: .int(2))])], at: actorKey)
        let chestKey = BedrockDBKey(position: ChunkPosition(x: 0, z: 0, dimension: 0), recordType: .blockEntity, subChunkIndex: nil).encoded()
        try put([doc([NBTNamedTag(name: "id", value: .string("Chest"))])], at: chestKey)
        try put([pig], at: Data("~local_player".utf8))
        try put([doc([NBTNamedTag(name: "UniqueID", value: .long(42)), NBTNamedTag(name: "DimensionId", value: .int(0)),
                       NBTNamedTag(name: "Pos", value: .list(.double, [.double(0.12345678901234566), .double(65), .double(10)]))])],
                at: Data("player_42".utf8))
        try put([doc([NBTNamedTag(name: "DimensionId", value: .int(1))])], at: Data("player_server_-9007199254740993".utf8))
        try DimensionStore(database: session.db).add(name: "custom:moon", id: 7)
        try put([doc([])], at: legacyKey(7))
        let before = session.db.values
        let levelBefore = try Data(contentsOf: session.document.levelDatURL)
        let all = try query("entity")
        precondition(!all.changedWorld && all.outputLines.count == 13, "expected 13 records, got \(all.outputLines.count): \(all.message)")
        precondition(all.outputLines.allSatisfy { if case .entity = $0.style { return true }; return false })
        precondition(all.outputLines.contains { $0.text == "minecraft:pig Dimension=overworld(0) Pos=NULL NBT=['String'\"identifier\"=\"minecraft:pig\",'Long'\"UniqueID\"=\"12345678\"]" })
        precondition(!all.message.contains("Chest"))
        precondition(all.outputLines.filter { $0.text.contains("'Long'\"UniqueID\"=\"42\"") }.count == 4)
        let output = all.outputLines.first { $0.text.hasPrefix("minecraft:cow Dimension=") }!.text
        precondition(output.contains("'Long'\"Exact\"=\"9007199254740993\""))
        precondition(output.contains("'ByteArray'\"Bytes\"=\"[0,-1]\""))
        precondition(output.contains("'IntArray'\"Ints\"=\"[-1,2]\""))
        precondition(!output.contains("\n"), "entity NBT must stay on one line")
        precondition(output.contains("'LongArray'\"Longs\"=\"[-9223372036854775808,9223372036854775807]\""))
        precondition(output.contains("'List''Compound'\"Items\"=\"{'String'\"Name\"=\"minecraft:stone\"}\""))
        precondition(!output.contains("'String'\"identifier\""), "query must not invent identifier tags")
        let ow = try query("EnTiTy OvErWoRlD"), nether = try query("entity nether"), end = try query("entity the_end")
        precondition(ow.outputLines.count == 9 && nether.outputLines.count == 2 && end.message.hasPrefix("minecraft:enderman Dimension=the_end(2)"))
        let box = try query("entity overworld -0.5 64.25 8.5 1.5 65.25 10.5")
        let reverse = try query("entity overworld 1.5 65.25 10.5 -0.5 64.25 8.5")
        let point = try query("entity overworld -0.5 64.25 8.5 -0.5 64.25 8.5")
        precondition(box.outputLines.count == 3 && box.message == reverse.message)
        precondition(point.outputLines.count == 1 && point.message.hasPrefix("minecraft:cow Dimension="))
        try check(query("entity @e").message == all.message, "default @e must have identical output")
        try check(query("entity @a").outputLines.count == 3 && query("entity minecraft:player").outputLines.count == 3, "all players and player identifier")
        try check(query("entity @s").outputLines.count == 1 && query("entity @s").message.hasPrefix("minecraft:player Dimension=overworld(0) Pos=NULL NBT=["), "local player is inferred from storage, not its raw identifier")
        try check(query("entity 12345678").outputLines.count == 2 && query("entity 42").outputLines.count == 4, "UniqueID matches players and independent duplicate actors")
        try check(query("entity minecraft:pig").outputLines.count == 2 && query("entity minecraft:cow").outputLines.count == 1, "identifier matches inferred actor type")
        try check(query("entity -9007199254740993").message.hasPrefix("minecraft:player Dimension=nether(1) Pos=NULL NBT=["), "exact player key ID and dimension independent of Pos")
        try check(query("entity @e custom:moon").message == "未知实体 Dimension=custom:moon(7) Pos=NULL NBT=[]", "custom dimension name and missing Pos")
        try check(query("entity @a overworld -0.5 64.25 8.5 1.5 65.25 10.5").outputLines.count == 1, "selector plus scope")
        try check(query("entity 42 0 -0.5 64.25 8.5 1.5 65.25 10.5").outputLines.count == 3, "UniqueID plus bounds")
        try check(query("entity 999999999").message == "entity：没有匹配的实体。", "missing target is a normal query result")
        try check(query("entity 42").message.contains("Pos=(0.12345678901234566,65,10)"), "actual coordinates retain precision without eye height changes")
        let payload = String(output.components(separatedBy: " NBT=[")[1].dropLast())
        let decoded = try MCBESNBTCodec.decode(text: "['Compound'\"\"=\"{" + payload + "}\"]")[0]
        try check(BedrockNBTCodec.encode(decoded) == BedrockNBTCodec.encode(cow), "full named NBT roundtrip")
        let empty = try query("entity nether 99 99 99 100 100 100")
        precondition(empty.message == "entity：没有匹配的实体。" && !empty.changedWorld)
        for bad in ["entity all", "entity overworld 0 0 0", "entity 0 0 0 1 1 1", "entity overworld 0 0 0 1 1 1 extra",
                    "entity overworld NaN 0 0 1 1 1", "entity overworld 0 inf 0 1 1 1", "entity overworld 0 0 0 1 1 1e40"] {
            var rejected = false; do { _ = try WorldCommandParser.parse(bad) } catch { rejected = true }
            precondition(rejected, "invalid entity syntax accepted: \(bad)")
        }
        let levelAfter = try Data(contentsOf: session.document.levelDatURL)
        precondition(session.db.values == before && levelBefore == levelAfter)
        try session.db.put(Data([255, 255]), for: legacyKey(2, 9))
        let damaged = try query("entity the_end")
        precondition(damaged.message.contains("entity 扫描提示："))

        // Finite large coordinates must remain queryable. Bad coordinates in
        // another dimension must not abort an otherwise valid read-only query.
        try put([entity(chicken, 101, 3e20, -3e20, 3e20), entity(chicken, 102, .nan, 0, 0), entity(chicken, 103, .infinity, 0, 0)], at: legacyKey(0, 10))
        let otherDimension = try query("entity nether")
        precondition(otherDimension.outputLines.count >= 1)
        let extreme = try query("entity overworld 3e20 -3e20 3e20 3e20 -3e20 3e20")
        precondition(extreme.outputLines.filter { $0.text.hasPrefix("minecraft:chicken Dimension=") }.count == 1)
        let extremePosition = BedrockWorldObjectPosition(x: 3e20, y: -.infinity, z: .nan)
        precondition(extremePosition.blockX == Int64.max && extremePosition.blockY == Int32.min && extremePosition.blockZ == 0)
        print("Entity query regression passed: scopes, exact NBT, mixed lists, extreme positions and read-only storage")
    }
}
