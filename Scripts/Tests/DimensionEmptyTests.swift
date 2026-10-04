import Foundation

enum DimensionEmptyTests {
    static func run() throws {
        func nbt(_ root: NBTValue) throws -> Data {
            try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: root))
        }
        func village(_ id: Int32) -> NBTValue {
            .compound([NBTNamedTag(name: "Dimension", value: .int(id))])
        }
        for root in [village(1000), .list(.compound, [village(1000), village(1001)]),
                     .compound([NBTNamedTag(name: "first", value: village(1000)), NBTNamedTag(name: "second", value: village(1001))])] {
            let db = MojangLevelDB()
            let target = DimensionStore(database: db)
            try target.add(name: "bear", id: 1000)
            try target.add(name: "cat", id: 1001)
            try db.put(nbt(root), for: Data("mVillages".utf8))
            let other = BedrockDBKey.subChunk(x: 0, z: 0, dimension: 1001, index: 0)
            try db.put(Data([3]), for: other)
            let registry = try db.get(DimensionStore.registryKey)
            _ = try target.empty(id: 1000)
            let otherBytes = try db.get(other); precondition(otherBytes == Data([3]))
            let registryAfter = try db.get(DimensionStore.registryKey); precondition(registryAfter == registry)
            let cleaned = try BedrockNBTCodec.decode(db.get(Data("mVillages".utf8))!).root
            let cleanedBytes = try nbt(cleaned), originalBytes = try nbt(root)
            precondition(cleanedBytes != originalBytes)
            if case .list(_, _) = root {
                guard case .list(_, let kept) = cleaned else { preconditionFailure("wrong list shape") }
                let keptBytes = try nbt(.list(.compound, kept)), expectedBytes = try nbt(.list(.compound, [village(1001)]))
                precondition(keptBytes == expectedBytes)
            }
            if case .compound(let tags) = root, tags.count == 2 {
                guard case .compound(let kept) = cleaned else { preconditionFailure("wrong map shape") }
                precondition(kept.count == 1 && kept[0].name == "second")
                let keptBytes = try nbt(kept[0].value), expectedBytes = try nbt(village(1001))
                precondition(keptBytes == expectedBytes)
            }
            let rows = try target.snapshot(); precondition(rows.first { $0.id == 1000 }?.chunkCount == 0)
        }
        let db = MojangLevelDB(), target = DimensionStore(database: db)
        try target.add(name: "overworld", id: 0)
        for name in ["schedulerWT", "dimension0", "portals"] {
            try db.put(nbt(.compound([])), for: Data(name.utf8))
        }
        try db.put(nbt(.compound([])), for: Data("VILLAGE_NETHER_uuid_INFO".utf8))
        _ = try target.empty(id: 0)
        let netherVillage = try db.get(Data("VILLAGE_NETHER_uuid_INFO".utf8)); precondition(netherVillage != nil)
        for name in ["schedulerWT", "portals"] { let value = try db.get(Data(name.utf8)); precondition(value != nil) }
        var digest = Data("digp".utf8); digest.append(Data(repeating: 0, count: 8))
        try db.put(Data([1]), for: digest)
        let before = db.values, batches = db.batchCount
        do { _ = try target.empty(id: 0); preconditionFailure("malformed digest accepted") }
        catch { precondition(db.values == before && db.batchCount == batches) }
        db.values.removeValue(forKey: digest)
        try db.put(nbt(village(0)), for: Data("portals".utf8))
        let beforeMetadata = db.values, metadataBatches = db.batchCount
        do { _ = try target.empty(id: 0); preconditionFailure("unsupported portals accepted") }
        catch { precondition(db.values == beforeMetadata && db.batchCount == metadataBatches) }
        try metadataTests()
        try DimensionSafetyRegressionTests.run()
        print("Dimension empty tests passed.")
    }
    private static func metadataTests() throws {
        let db = MojangLevelDB(), store = DimensionStore(database: db)
        try store.add(name: "bear", id: 1000)
        try store.add(name: "cat", id: 1001)
        func encode(_ value: NBTValue) throws -> Data { try BedrockNBTCodec.encode(NBTDocument(rootName: "", root: value)) }
        func portal(_ id: Int32) -> NBTValue { .compound([NBTNamedTag(name: "DimId", value: .int(id)), NBTNamedTag(name: "TpX", value: .int(17))]) }
        let portals = NBTValue.compound([NBTNamedTag(name: "data", value: .compound([
            NBTNamedTag(name: "PortalRecords", value: .list(.compound, [portal(1000), portal(1001)])),
            NBTNamedTag(name: "setting", value: .int(5))]))])
        try db.put(encode(portals), for: Data("portals".utf8))
        let scheduler = try encode(.compound([NBTNamedTag(name: "daysSinceLastWTSpawn", value: .int(3))]))
        try db.put(scheduler, for: Data("schedulerWT".utf8))
        try db.put(encode(.compound([])), for: Data("VILLAGE_bear_uuid_RAID".utf8))
        try db.put(encode(.compound([])), for: Data("VILLAGE_cat_uuid_INFO".utf8))
        _ = try store.empty(id: 1000)
        let root = try BedrockNBTCodec.decode(db.get(Data("portals".utf8))!).root
        guard case .list(.compound, let records)? = root.compoundValue(named: "data")?.compoundValue(named: "PortalRecords") else { preconditionFailure("portal schema lost") }
        precondition(records.count == 1 && records[0].intValue(named: "DimId") == 1001)
        precondition(root.compoundValue(named: "data")?.intValue(named: "setting") == 5)
        let schedulerAfter = try db.get(Data("schedulerWT".utf8)); precondition(schedulerAfter == scheduler)
        let raid = try db.get(Data("VILLAGE_bear_uuid_RAID".utf8)), otherVillage = try db.get(Data("VILLAGE_cat_uuid_INFO".utf8))
        precondition(raid == nil && otherVillage != nil)
        let legacy = MojangLevelDB(), legacyStore = DimensionStore(database: legacy)
        try legacy.put(encode(.compound([NBTNamedTag(name: "bridge", value: .compound([]))])), for: Data("dimension1".utf8))
        try legacy.put(encode(.compound([])), for: Data("dimension2".utf8))
        let rows = try legacyStore.snapshot(); precondition(rows.map(\.id) == [1, 2])
        let otherLegacy = try legacy.get(Data("dimension2".utf8))
        _ = try legacyStore.empty(id: 1)
        let removed = try legacy.get(Data("dimension1".utf8)), otherAfter = try legacy.get(Data("dimension2".utf8))
        precondition(removed == nil && otherAfter == otherLegacy)
        let retained = try legacyStore.snapshot(); precondition(retained.map(\.id) == [1, 2])
        try legacy.put(encode(.compound([NBTNamedTag(name: "data", value: .compound([
            NBTNamedTag(name: "DragonFight", value: .compound([NBTNamedTag(name: "DragonUUID", value: .long(99))])),
            NBTNamedTag(name: "setting", value: .int(42))]))])), for: Data("TheEnd".utf8))
        _ = try legacyStore.empty(id: 2)
        let endData = try BedrockNBTCodec.decode(legacy.get(Data("TheEnd".utf8))!).root.compoundValue(named: "data")!
        if case .some = endData.compoundValue(named: "DragonFight") { preconditionFailure("dragon fight state retained") }
        precondition(endData.intValue(named: "setting") == 42)
    }
}
