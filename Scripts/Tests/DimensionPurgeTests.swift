import Foundation

enum DimensionPurgeTests {
    static func run() throws {
        func encode(_ root: NBTValue) throws -> Data { try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: root)) }
        let db = MojangLevelDB(), store = DimensionStore(database: db)
        try store.add(name: "bear", id: 1000)
        try store.add(name: "nether", id: 1)
        let player = NBTValue.compound([
            NBTNamedTag(name: "DimensionId", value: .int(1000)),
            NBTNamedTag(name: "Pos", value: .list(.float, [.float(5), .float(66), .float(8)])),
            NBTNamedTag(name: "SpawnDimension", value: .int(1000)),
            NBTNamedTag(name: "SpawnX", value: .int(5)), NBTNamedTag(name: "SpawnY", value: .int(64)), NBTNamedTag(name: "SpawnZ", value: .int(8)),
            NBTNamedTag(name: "Health", value: .short(20))])
        try db.put(encode(player), for: Data("~local_player".utf8))
        try db.put(Data([1]), for: BedrockDBKey.subChunk(x: 0, z: 0, dimension: 1000, index: 0))
        try db.put(encode(.compound([NBTNamedTag(name: "clocks", value: .list(.compound, [
            .compound([NBTNamedTag(name: "Name", value: .string("bear"))]),
            .compound([NBTNamedTag(name: "Name", value: .string("minecraft:nether"))])]))])), for: Data("WorldClocks".utf8))
        let beforeBatches = db.batchCount
        let result = try store.purge(id: 1000)
        precondition(result.affectedPlayerCount == 1 && db.batchCount == beforeBatches + 1)
        let rows = try store.snapshot(); precondition(rows.map(\.id) == [1])
        let rootBytes = try db.get(Data("bear".utf8)); precondition(rootBytes == nil)
        let updated = try BedrockNBTCodec.decode(db.get(Data("~local_player".utf8))!).root
        precondition(updated.intValue(named: "DimensionId") == 1 && updated.intValue(named: "SpawnDimension") == 1)
        guard case .list(.float, let position)? = updated.compoundValue(named: "Pos"), position.count == 3,
              case .float(let x) = position[0], case .float(let y) = position[1], case .float(let z) = position[2] else { preconditionFailure("position was not migrated") }
        precondition(x == 0.5 && abs(y - 65.62) < 0.001 && z == 0.5)
        precondition(updated.intValue(named: "SpawnX") == 0 && updated.intValue(named: "SpawnY") == 64 && updated.intValue(named: "SpawnZ") == 0)
        guard case .short(20)? = updated.compoundValue(named: "Health") else { preconditionFailure("player settings changed") }
        let clocks = try BedrockNBTCodec.decode(db.get(Data("WorldClocks".utf8))!).root
        guard case .list(_, let kept)? = clocks.compoundValue(named: "clocks") else { preconditionFailure("clocks missing") }
        precondition(kept.count == 1 && kept[0].stringValue(named: "Name") == "minecraft:nether")
        try store.add(name: "bear", id: 1000)
        let only = MojangLevelDB(), onlyStore = DimensionStore(database: only)
        try onlyStore.add(name: "bear", id: 1000)
        try only.put(encode(player), for: Data("~local_player".utf8))
        let before = only.values, batches = only.batchCount
        do { _ = try onlyStore.purge(id: 1000); preconditionFailure("last dimension with player accepted") }
        catch { precondition(only.values == before && only.batchCount == batches) }
        only.values.removeValue(forKey: Data("~local_player".utf8))
        _ = try onlyStore.purge(id: 1000)
        let none = try onlyStore.snapshot(); precondition(none.isEmpty)
        print("Dimension purge tests passed.")
    }
}
