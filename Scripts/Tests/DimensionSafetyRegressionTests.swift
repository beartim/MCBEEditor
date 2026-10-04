import Foundation

enum DimensionSafetyRegressionTests {
    static func run() throws {
        try rawOnly(); try villagePrefixes(); try ownershipAliases()
        print("Dimension safety regressions passed: unknown raw tags, longest village names and atomic ownership rejection.")
    }
    private static func rawOnly() throws {
        for id in [Int32(0), 43, 44, 47, 118, 1000, -1, Int32.min, Int32.max] {
            for suffix in 1...3 {
                var key = Data(); key.appendLE(Int32(7)); key.appendLE(Int32(9))
                if id != 0 { key.appendLE(id) }; key.append(0x7f); key.append(Data(repeating: 0, count: suffix - 1))
                let db = MojangLevelDB(), store = DimensionStore(database: db)
                try db.put(Data([42]), for: key)
                let before = db.values, batches = db.batchCount, rows = try store.snapshot()
                precondition(rows.count == 1 && rows[0].id == id && rows[0].chunkCount == 1)
                precondition(db.values == before && db.batchCount == batches)
                do { try store.add(name: id == 0 ? "overworld" : "raw-test", id: id); preconditionFailure("occupied raw ID accepted") }
                catch { precondition(db.values == before && db.batchCount == batches) }
                _ = try store.empty(id: id)
                let kept = try store.snapshot(), removed = try db.get(key)
                precondition(removed == nil && kept.count == 1 && kept[0].id == id && kept[0].chunkCount == 0)
                let purgeDB = MojangLevelDB(), purgeStore = DimensionStore(database: purgeDB)
                try purgeDB.put(Data([42]), for: key); _ = try purgeStore.purge(id: id)
                let deleted = try purgeDB.get(key), remaining = try purgeStore.snapshot()
                precondition(deleted == nil && remaining.isEmpty)
            }
        }
        let db = MojangLevelDB()
        for name in ["Overworld", "Nether", "TheEnd", "tickingarea_xy", "VILLAGE_x", "portals_x", "map_abcde", "player_abcdef", "digp_xxxx"] {
            try db.put(Data([10, 0, 0, 0]), for: Data(name.utf8))
        }
        let roots = try DimensionStore(database: db).snapshot()
        precondition(roots.map(\.id) == [0, 1, 2] && roots.allSatisfy { $0.chunkCount == 0 })
    }
    private static func villagePrefixes() throws {
        for (name, id) in [("overworld", Int32(0)), ("nether", Int32(1)), ("the_end", Int32(2))] {
            for purge in [false, true] {
                let db = MojangLevelDB(), store = DimensionStore(database: db)
                try store.add(name: name, id: id); try store.add(name: name + "_custom", id: 1000)
                let key = Data("VILLAGE_\(name)_custom_uuid_RAID".utf8), village = Data([10, 0, 0, 0])
                try db.put(village, for: key)
                if purge { _ = try store.purge(id: id) } else { _ = try store.empty(id: id) }
                let kept = try db.get(key); precondition(kept == village)
                if purge { _ = try store.purge(id: 1000) } else { _ = try store.empty(id: 1000) }
                let deleted = try db.get(key); precondition(deleted == nil)
            }
        }
    }
    private static func ownershipAliases() throws {
        for alias in [NBTValue.int(1001), .string("missing"), .long(Int64(Int32.max) + 1)] {
            for reverse in [false, true] {
                for purge in [false, true] {
                    for kind in ["actor", "tickingarea", "village", "autonomous", "legacyVillage"] {
                        let db = MojangLevelDB(), store = DimensionStore(database: db)
                        try store.add(name: "bear", id: 1000); try store.add(name: "cat", id: 1001)
                        try db.put(Data([42]), for: BedrockDBKey.subChunk(x: 0, z: 0, dimension: 1000, index: 0))
                        var fields = [NBTNamedTag(name: "Dimension", value: .int(1000)), NBTNamedTag(name: "DimensionId", value: alias)]
                        if reverse { fields.reverse() }
                        var root = NBTValue.compound(fields), key: Data
                        switch kind {
                        case "actor": key = Data("actorprefix".utf8) + Data(repeating: 0, count: 8)
                        case "tickingarea": key = Data("tickingarea_test".utf8)
                        case "village": key = Data("VILLAGE_bear_uuid_INFO".utf8)
                        case "autonomous":
                            key = Data("AutonomousEntities".utf8)
                            root = .compound([NBTNamedTag(name: "AutonomousEntityList", value: .list(.compound, [root]))])
                        default: key = Data("mVillages".utf8); root = .list(.compound, [root])
                        }
                        try db.put(BedrockNBTCodec.encode(NBTDocument(rootName: "", root: root)), for: key)
                        let before = db.values, batches = db.batchCount
                        do {
                            if purge { _ = try store.purge(id: 1000) } else { _ = try store.empty(id: 1000) }
                            preconditionFailure("invalid direct owner accepted: \(kind)")
                        } catch { precondition(db.values == before && db.batchCount == batches) }
                    }
                }
            }
        }
        let db = MojangLevelDB(), store = DimensionStore(database: db); try store.add(name: "bear", id: 1000)
        let root = NBTDocument(rootName: "", root: .compound([NBTNamedTag(name: "Dimension", value: .int(1000)), NBTNamedTag(name: "DimensionId", value: .string("bear"))]))
        let key = Data("tickingarea_agree".utf8); try db.put(BedrockNBTCodec.encode(root), for: key)
        _ = try store.empty(id: 1000); let removed = try db.get(key); precondition(removed == nil)
    }
}
