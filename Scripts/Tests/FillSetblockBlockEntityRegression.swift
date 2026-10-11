import Foundation

enum FillSetblockBlockEntityRegression {
    static func run() throws {
        for text in ["setblock overworld 0 64 0 minecraft:stone NULL", "fill overworld 0 64 0 16 64 0 minecraft:stone NULL"] {
            var rejected = false
            do { _ = try WorldCommandParser.parse(text) } catch { rejected = true }
            precondition(rejected, "missing required final block-entity argument was accepted: \(text)")
        }
        let session = WorldSession()
        let executor = WorldCommandExecutor(session: session)
        @discardableResult func run(_ text: String) throws -> WorldCommandExecutionResult {
            try executor.execute(WorldCommandParser.parse(text))
        }
        func key(_ dimension: Int32, _ x: Int32 = 0, _ z: Int32 = 0) -> Data {
            BedrockDBKey(position: ChunkPosition(x: x, z: z, dimension: dimension), recordType: .blockEntity, subChunkIndex: nil).encoded()
        }
        func tags(_ x: Int, _ y: Int, _ z: Int, _ id: String = "Chest") -> String {
            "'Byte'\"Findable\"=\"0\",'List'''\"Items\"=\"\",'String'\"id\"=\"\(id)\",'Byte'\"isMovable\"=\"1\",'Int'\"x\"=\"\(x)\",'Int'\"y\"=\"\(y)\",'Int'\"z\"=\"\(z)\""
        }
        func record(_ text: String, root: String = "") throws -> Data {
            try BedrockNBTCodec.encode(NBTDocument(rootName: root, root: .compound(WorldCommandParser.parseStates(text))))
        }
        func failsWithoutWrites(_ text: String) throws {
            let before = session.db.values
            var rejected = false
            do { try run(text) } catch { rejected = true }
            precondition(rejected && session.db.values == before, "rejected command changed storage: \(text)")
        }
        let outside = try record(tags(1, 64, 0, "arbitrary:outside"), root: "peer")
        let orphan = try record(#"'String'"id"="no-coordinate""#)
        let target = try record(tags(0, 64, 0))
        let original = outside + target + orphan + target
        session.db.values[key(0)] = original
        for command in ["setblock overworld 0 64 0 minecraft:stone NULL preserve", "fill overworld 0 64 0 0 64 0 minecraft:dirt NULL preserve"] {
            try run(command)
            precondition(session.db.values[key(0)] == original, "preserve changed entities")
        }
        try run("setblock overworld 0 64 0 minecraft:stone NULL minecraft:water NULL " + tags(0, 64, 0))
        precondition(session.db.values[key(0)] == outside + orphan + target, "replacement changed peers or retained duplicate target entities")
        let queried = try run("getblock overworld 0 64 0")
        precondition(queried.message.contains("minecraft:stone") && queried.message.contains("minecraft:water") && queried.message.contains(#"'List'''"Items"="""#), "user example/empty List output mismatch")
        try run("setblock overworld 0 64 0 minecraft:stone NULL " + tags(0, 64, 0, "anything:custom_id"))
        let arbitrary = try run("getblock overworld 0 64 0")
        precondition(arbitrary.message.contains("anything:custom_id"), "arbitrary id was rejected or changed")
        try run("fill overworld 0 64 0 0 64 0 minecraft:stone NULL empty")
        precondition(session.db.values[key(0)] == outside + orphan, "empty changed unrelated entities")

        let template = tags(16, 65, 0, "wzn:anything") + #",'Int'"DimensionId"="77",'Compound'"Nested"="{'Long'"Exact"="9007199254740993",'Int'"x"="999"}""#
        let filled = try run("fill 1000 16 65 0 -1 64 -1 minecraft:stone NULL " + template)
        precondition(filled.message.contains("写入 72 个方块实体"))
        for x in -1...16 { for y in 64...65 { for z in -1...0 {
            let chunkX: Int32 = x < 0 ? -1 : Int32(x / 16)
            let chunkZ: Int32 = z < 0 ? -1 : 0
            let records = try ConsecutiveNBTCodec.decode(session.db.values[key(1000, chunkX, chunkZ)]!)
            let matches = records.filter { $0.document.root.compoundValue(named: "x")?.integerValue() == Int64(x)
                && $0.document.root.compoundValue(named: "y")?.integerValue() == Int64(y)
                && $0.document.root.compoundValue(named: "z")?.integerValue() == Int64(z) }
            precondition(matches.count == 1, "fill did not create exactly one entity per target coordinate")
            let root = matches[0].document.root
            precondition(root.stringValue(named: "id") == "wzn:anything" && root.intValue(named: "DimensionId") == 77
                && root.compoundValue(named: "Nested")?.intValue(named: "x") == 999, "fill changed non-coordinate tags")
        } } }
        let typed = #"'String'"id"="ByteCoordinate",'Byte'"X"="1",'Short'"y"="64",'Long'"z"="1""#
        try run("fill -123 1 64 1 2 64 1 minecraft:air NULL " + typed)
        let typedRecords = try ConsecutiveNBTCodec.decode(session.db.values[key(-123)]!)
        precondition(typedRecords.count == 2 && typedRecords.allSatisfy {
            $0.document.root.compoundValue(named: "X")?.type == .byte && $0.document.root.compoundValue(named: "y")?.type == .short && $0.document.root.compoundValue(named: "z")?.type == .long
        }, "coordinate types changed")
        for suffix in ["NULL", "unknown", tags(1, 64, 0), tags(0, 63, 0), tags(0, 64, -1),
            #"'Int'"x"="0",'Int'"y"="64""#, #"'Float'"x"="0",'Int'"y"="64",'Int'"z"="0""#,
            tags(0, 64, 0) + #",'Int'"X"="0""#, tags(0, 64, 0) + #",'List'''"Invalid"="1""#] {
            try failsWithoutWrites("setblock overworld 0 64 0 minecraft:dirt NULL " + suffix)
        }
        try failsWithoutWrites("fill 1000 16 65 0 -1 64 -1 minecraft:dirt NULL " + tags(-1, 64, -1))
        try failsWithoutWrites("fill overworld 1 64 1 128 64 1 minecraft:dirt NULL " + typed)
        let broken = Data([10, 0, 0, 3])
        session.db.values[key(0, 1)] = broken
        try run("fill overworld 0 64 0 16 64 0 minecraft:stone NULL preserve")
        precondition(session.db.values[key(0, 1)] == broken, "preserve parsed or rewrote malformed entities")
        try failsWithoutWrites("fill overworld 0 64 0 16 64 0 minecraft:dirt NULL empty")
        try failsWithoutWrites("fill overworld 0 64 0 16 64 0 minecraft:dirt NULL " + tags(0, 64, 0))
        try run("setblock 2000 0 64 0 minecraft:stone NULL " + tags(0, 64, 0))
        try run("setblock 2000 0 64 0 minecraft:stone NULL empty")
        precondition(session.db.values[key(2000)] == nil, "empty did not delete the empty record key")
        let withPos = tags(0, 64, 0, "custom:with_pos") + #",'List''Float'"Pos"="1,64,0""#
        try run("setblock 3000 0 64 0 minecraft:stone NULL " + withPos)
        let positionQuery = try run("getblock 3000 0 64 0")
        precondition(positionQuery.message.contains("custom:with_pos"), "auxiliary Pos overrode root coordinates")
        try run("setblock 3000 0 64 0 minecraft:dirt NULL " + withPos)
        let positionRecords = try ConsecutiveNBTCodec.decode(session.db.values[key(3000)]!)
        precondition(positionRecords.count == 1, "auxiliary Pos left duplicate entities")
        try run("setblock 3000 0 64 0 minecraft:stone NULL empty")
        precondition(session.db.values[key(3000)] == nil, "empty used auxiliary Pos rather than root coordinates")
        let ambiguous = try record(#"'String'"id"="fractional",'Float'"x"="0.75",'Int'"y"="64",'Int'"z"="0""#)
            + record(#"'String'"id"="duplicate",'Int'"x"="0",'Int'"X"="1",'Int'"y"="64",'Int'"z"="0""#)
        session.db.values[key(3001)] = ambiguous
        try run("setblock 3001 0 64 0 minecraft:stone NULL empty")
        precondition(session.db.values[key(3001)] == ambiguous, "empty removed ambiguous coordinate records")
        let extremeKey = key(4000, Int32.max / 16)
        let outOfRange = try record(#"'String'"id"="outside_int32",'Long'"x"="2147483648",'Int'"y"="64",'Int'"z"="0""#)
        session.db.values[extremeKey] = outOfRange
        try run("setblock 4000 2147483647 64 0 minecraft:stone NULL empty")
        precondition(session.db.values[extremeKey] == outOfRange, "out-of-range entity was clamped into a target position")
        let legacyDocument = try NBTDocument(rootName: "legacy", root: .compound(WorldCommandParser.parseStates(tags(1, 64, 0, "legacy:peer"))))
        session.db.values[key(4001)] = try BedrockNBTCodec.encode(legacyDocument, encoding: .littleEndianVarInt)
        try run("setblock 4001 0 64 0 minecraft:stone NULL " + tags(0, 64, 0))
        let normalized = try ConsecutiveNBTCodec.decode(session.db.values[key(4001)]!)
        let legacyExpected = try BedrockNBTCodec.encode(legacyDocument, encoding: .littleEndian)
        precondition(normalized.count == 2 && normalized[0].rawData == legacyExpected, "legacy VarInt peer or appended entity was lost")
        // Applying an already satisfied preserve/empty request is a successful no-op.
        try run("setblock 5000 0 64 0 minecraft:stone NULL " + tags(0, 64, 0))
        let noOpBefore = session.db.values
        let preservedAgain = try run("setblock 5000 0 64 0 minecraft:stone NULL preserve")
        precondition(!preservedAgain.changedWorld && session.db.values == noOpBefore, "unchanged preserve must succeed without marking the world dirty")
        try run("setblock 5000 0 64 0 minecraft:stone NULL empty")
        let emptyBefore = session.db.values
        let emptiedAgain = try run("fill 5000 0 64 0 0 64 0 minecraft:stone NULL empty")
        precondition(!emptiedAgain.changedWorld && session.db.values == emptyBefore, "unchanged empty must succeed without marking the world dirty")
        print("Fill/setblock block entities passed: required argument, three modes, arbitrary IDs, coordinate/type checks, reverse/cross-chunk fill, duplicate/peer preservation and atomic failures.")
    }
}
