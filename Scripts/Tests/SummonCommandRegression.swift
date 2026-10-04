import Foundation

enum SummonCommandRegression {
    static func run() throws {
        // The literals in shared fixtures exercise both production parsers.
        struct Fixture: Decodable { let id: String; let command: String; let valid: Bool }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("CLI/Shared/parser-cases.json")))
        for fixture in fixtures {
            var accepted = false
            do { _ = try WorldCommandParser.parse(fixture.command); accepted = true } catch {}
            precondition(accepted == fixture.valid, "Swift parser fixture failed: \(fixture.id)")
        }
        print("Swift shared parser fixtures passed: \(fixtures.count)")

        let session = WorldSession()
        let executor = WorldCommandExecutor(session: session)
        func run(_ text: String) throws -> WorldCommandExecutionResult {
            try executor.execute(WorldCommandParser.parse(text))
        }
        func objects() throws -> [BedrockWorldObject] {
            try BedrockWorldObjectScanner(database: session.db).scanAll(
                dimensions: nil, includeEntities: true, includeBlockEntities: false, maximumObjects: Int.max).objects
        }
        func object(_ uniqueID: Int64) throws -> BedrockWorldObject {
            let result = try objects().filter { $0.uniqueID == uniqueID }
            precondition(result.count == 1)
            return result[0]
        }
        func failsWithoutWrites(_ text: String) throws {
            let before = session.db.values
            var rejected = false
            do { _ = try run(text) } catch { rejected = true }
            precondition(rejected && session.db.values == before, "failed summon modified storage: \(text)")
        }
        for id in [Int64.min, Int64.max, 9_007_199_254_740_993] {
            let result = try run("summon minecraft:pig nether -1.25 64.5 2.75 default \(id)")
            precondition(result.changedWorld && result.message.contains("UniqueID \(id)"))
            let item = try object(id)
            guard case .long(let stored)? = item.document.root.compoundValue(named: "UniqueID") else {
                preconditionFailure("manual UniqueID lost Long type")
            }
            precondition(stored == id && item.dimension == 1)
        }
        _ = try run("summon minecraft:pig overworld 1 64 1 default Auto")
        _ = try run("summon minecraft:pig overworld 2 64 2 default")
        let automatic = try objects()
        precondition(automatic.count == 5 && Set(automatic.compactMap(\.uniqueID)).count == 5)
        precondition(automatic.allSatisfy { $0.uniqueID != nil && $0.uniqueID != 0 })

        let example = #"summon 'String'"identifier"="minecraft:cow",'List''Float'"Pos"="0.0,64.0,0.0",'Long'"UniqueID"="12345678""#
        _ = try run(example)
        let cow = try object(12_345_678)
        let expected = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "identifier", value: .string("minecraft:cow")),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(0), .float(64), .float(0)])),
            NBTNamedTag(name: "UniqueID", value: .long(12_345_678))
        ]))
        let expectedBytes = try BedrockNBTCodec.encode(expected)
        let actualBytes = try BedrockNBTCodec.encode(cow.document)
        precondition(expectedBytes == actualBytes && cow.dimension == 0 && cow.source == .modernActor,
                     "direct summon changed supplied tags/types/order or added defaults")
        try failsWithoutWrites(example)
        try failsWithoutWrites("summon minecraft:pig overworld 0 64 0 default 12345678")

        _ = try run(#"summon 'List''String'"definitions"="+minecraft:chicken",'List''Double'"Position"="-0.25,64.125,2.5",'Int'"Dimension"="2",'Compound'"Nested"="{'Long'"Exact"="9007199254740993",'String'"Name"="two words"}""#)
        let chickens = try objects().filter { $0.identifier == "minecraft:chicken" }
        precondition(chickens.count == 1 && chickens[0].dimension == 2 && chickens[0].position?.y == 64.125)
        guard case .compound(let tags) = chickens[0].document.root, case .long(let generated)? = tags.last?.value else {
            preconditionFailure("missing ID must append an automatic Long")
        }
        precondition(generated != 0 && tags.map(\.name) == ["definitions", "Position", "Dimension", "Nested", "UniqueID"])
        precondition(tags[3].value.compoundValue(named: "Exact")?.numericInt64Value == 9_007_199_254_740_993)

        var reference = Int64(7788).littleEndian
        var actorKey = Data("actorprefix".utf8)
        withUnsafeBytes(of: &reference) { actorKey.append(contentsOf: $0) }
        let occupied = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "UniqueID", value: .long(9988)),
            NBTNamedTag(name: "identifier", value: .string("minecraft:sheep"))
        ]))
        try session.db.put(BedrockNBTCodec.encode(occupied), for: actorKey)
        try failsWithoutWrites("summon minecraft:cow overworld 0 64 0 default 7788")
        try failsWithoutWrites(#"summon 'List''Float'"Pos"="0,64,0",'Long'"UniqueID"="9988""#)

        let legacy = WorldSession()
        let legacyKey = BedrockDBKey(position: ChunkPosition(x: 0, z: 0, dimension: 0), recordType: .entity, subChunkIndex: nil).encoded()
        try legacy.db.put(Data(), for: legacyKey)
        let legacyExecutor = WorldCommandExecutor(session: legacy)
        _ = try legacyExecutor.execute(WorldCommandParser.parse(#"summon 'Short'"id"="11",'List''Float'"Pos"="0,64,0",'Long'"UniqueID"="-1234""#))
        let legacyItems = try BedrockWorldObjectScanner(database: legacy.db).scanAll(
            dimensions: nil, includeEntities: true, includeBlockEntities: false, maximumObjects: Int.max).objects
        precondition(legacyItems.count == 1 && legacyItems[0].source == .legacyChunkEntity && legacyItems[0].uniqueID == -1234)
        precondition(legacyItems[0].document.root.compoundValue(named: "identifier") == nil)
        let before = legacy.db.values
        var rejected = false
        do { _ = try legacyExecutor.execute(WorldCommandParser.parse("summon minecraft:cow overworld 0 64 0 default -1234")) }
        catch { rejected = true }
        precondition(rejected && legacy.db.values == before)

        try danglingDigestCollision()
        try automaticIDsAndReferenceNamespaces()
        print("Summon regression passed: exact Long, Auto, raw NBT, legacy/modern storage and atomic collision rejection")
    }

    private static func danglingDigestCollision() throws {
        for trailingFragment in [false, true] {
        for command in ["summon minecraft:cow overworld 32 64 0 default 4242",
                        #"summon 'String'"identifier"="minecraft:cow",'List''Float'"Pos"="32,64,0",'Long'"UniqueID"="4242""#] {
            let session = WorldSession()
            var digestKey = Data("digp".utf8)
            digestKey.appendLE(Int32(0)); digestKey.appendLE(Int32(0)); digestKey.appendLE(Int32(1))
            var actorID = Int64(4242).littleEndian
            var reference = withUnsafeBytes(of: &actorID) { Data($0) }
            if trailingFragment { reference.append(0) }
            try session.db.put(reference, for: digestKey)
            let before = session.db.values
            var rejected = false
            do { _ = try WorldCommandExecutor(session: session).execute(WorldCommandParser.parse(command)) }
            catch { rejected = true }
            precondition(rejected && before == session.db.values,
                         "summon must not adopt an orphan digp reference from another dimension (trailing fragment: \(trailingFragment))")
        }
        }
    }

    private static func automaticIDsAndReferenceNamespaces() throws {
        func bytes(_ id: Int64) -> Data {
            var littleEndian = id.littleEndian
            return withUnsafeBytes(of: &littleEndian) { Data($0) }
        }
        func digest(_ x: Int32, _ z: Int32) -> Data {
            var key = Data("digp".utf8)
            key.appendLE(x); key.appendLE(z)
            return key
        }
        let session = WorldSession()
        try session.db.put(bytes(4242), for: digest(99, 99))
        var actorKey = Data("actorprefix".utf8); actorKey.append(bytes(4243))
        try session.db.put(BedrockNBTCodec.encode(NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "UniqueID", value: .long(22))
        ]))), for: actorKey)
        // Ignore invalid keys, but reserve complete references before a trailing fragment.
        try session.db.put(bytes(4246), for: Data("digp-short".utf8))
        var malformed = bytes(4244); malformed.append(0)
        try session.db.put(malformed, for: digest(100, 100))
        var extendedKey = digest(101, 101)
        extendedKey.appendLE(Int32(1)); extendedKey.append(0)
        try session.db.put(bytes(4245), for: extendedKey)
        var candidates: [Int64] = [4242, 4243, 22, 4244, 4245, 4246]
        let generated = try BedrockWorldObjectNBTStore(session: session).suggestedUniqueID(
            candidateGenerator: { candidates.removeFirst() })
        precondition(generated == 4246 && candidates.isEmpty,
                     "Auto must avoid NBT IDs, actor keys and dangling digp references")

        // An explicit legacy NBT ID is not a modern actor storage reference.
        for command in ["summon minecraft:cow overworld 0 64 0 default 4242",
                        #"summon 'Short'"id"="11",'List''Float'"Pos"="0,64,0",'Long'"UniqueID"="4242""#] {
            let legacy = WorldSession()
            let key = BedrockDBKey(position: ChunkPosition(x: 0, z: 0, dimension: 0), recordType: .entity, subChunkIndex: nil).encoded()
            try legacy.db.put(Data(), for: key)
            let digestKey = digest(99, 99)
            try legacy.db.put(bytes(4242), for: digestKey)
            _ = try WorldCommandExecutor(session: legacy).execute(WorldCommandParser.parse(command))
            let stored = try ConsecutiveNBTCodec.decode(legacy.db.get(key)!)
            precondition(stored.count == 1 && stored[0].document.root.compoundValue(named: "UniqueID")?.numericInt64Value == 4242)
            let preservedDigest = try legacy.db.get(digestKey)
            precondition(preservedDigest == bytes(4242))
        }
    }
}
