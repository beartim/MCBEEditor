import Foundation

// The portable runner supplies an in-memory database. All command parsing,
// scanning, NBT decoding and rendering below use production implementations.
enum EntityCommandRegression {
    static func run() throws {
        let session = WorldSession()
        let executor = WorldCommandExecutor(session: session)
        func query(_ text: String) throws -> WorldCommandExecutionResult {
            try executor.execute(WorldCommandParser.parse(text))
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
        let before = session.db.values
        let levelBefore = try Data(contentsOf: session.document.levelDatURL)
        let all = try query("entity")
        precondition(!all.changedWorld && all.outputLines.count == 9)
        precondition(all.outputLines.allSatisfy { if case .entity = $0.style { return true }; return false })
        precondition(all.outputLines.contains { $0.text == "minecraft:pig=['String'\"identifier\"=\"minecraft:pig\",'Long'\"UniqueID\"=\"12345678\"]" })
        precondition(!all.message.contains("Chest"))
        precondition(all.outputLines.filter { $0.text.contains("'Long'\"UniqueID\"=\"42\"") }.count == 3)
        let output = all.outputLines.first { $0.text.hasPrefix("minecraft:cow=[") }!.text
        precondition(output.contains("'Long'\"Exact\"=\"9007199254740993\""))
        precondition(output.contains("'ByteArray'\"Bytes\"=\"[0,-1]\""))
        precondition(output.contains("'IntArray'\"Ints\"=\"[-1,2]\""))
        precondition(output.contains("'LongArray'\"Longs\"=\"[-9223372036854775808,9223372036854775807]\""))
        precondition(!output.contains("\n") && output.contains("a\\nb\\\"c\\\\\\,d"))
        precondition(output.contains("'List''List''Int'\"Matrix\"=\"[1,2],[3]\""))
        precondition(output.contains("'List''List'\"Mixed\"=\"['List''Int'=[1]],['List''String'=[2]]\""), "mixed lists must preserve each child type")
        precondition(output.contains("'List''List'\"Deep\"=\"['List''List'=[['List''Int'=[1]],['List''String'=[2]]]]\""), "deeper mixed lists must remain typed")
        precondition(output.contains("'List''Compound'\"Items\"=\"{'String'\"Name\"=\"minecraft:stone\"}\""))
        precondition(!output.contains("'String'\"identifier\""), "query must not invent identifier tags")
        let ow = try query("EnTiTy OvErWoRlD"), nether = try query("entity nether"), end = try query("entity the_end")
        precondition(ow.outputLines.count == 7 && nether.outputLines.count == 1 && end.message.hasPrefix("minecraft:enderman=["))
        let box = try query("entity overworld -0.5 64.25 8.5 1.5 65.25 10.5")
        let reverse = try query("entity overworld 1.5 65.25 10.5 -0.5 64.25 8.5")
        let point = try query("entity overworld -0.5 64.25 8.5 -0.5 64.25 8.5")
        precondition(box.outputLines.count == 2 && box.message == reverse.message)
        precondition(point.outputLines.count == 1 && point.message.hasPrefix("minecraft:cow=["))
        let empty = try query("entity nether 99 99 99 100 100 100")
        precondition(empty.message == "entity：没有匹配的实体。" && !empty.changedWorld)
        for bad in ["entity all", "entity 2147483648", "entity overworld 0 0 0", "entity 0 0 0 1 1 1", "entity overworld 0 0 0 1 1 1 extra",
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
        precondition(extreme.outputLines.filter { $0.text.hasPrefix("minecraft:chicken=[") }.count == 1)
        let extremePosition = BedrockWorldObjectPosition(x: 3e20, y: -.infinity, z: .nan)
        precondition(extremePosition.blockX == Int64.max && extremePosition.blockY == Int32.min && extremePosition.blockZ == 0)
        print("Entity query regression passed: scopes, exact NBT, mixed lists, extreme positions and read-only storage")
    }
}
