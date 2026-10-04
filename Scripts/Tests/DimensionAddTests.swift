import Foundation

enum DimensionAddTests {
    static func run() throws {
        let db = MojangLevelDB()
        let store = DimensionStore(database: db)
        try store.add(name: "wzn:bear", id: 1000)
        try store.add(name: "bear", id: 1001)
        precondition(db.batchCount == 2)
        let table = try BedrockNBTCodec.decode(db.get(DimensionStore.registryKey)!).root.compoundValue(named: "entries")!
        precondition(table.intValue(named: "wzn:bear") == 1000 && table.intValue(named: "bear") == 1001)
        let root = try BedrockNBTCodec.decode(db.get(Data("bear".utf8))!).root
        guard case .list(.compound, let items)? = root.compoundValue(named: "data")?.compoundValue(named: "LimboEntities") else { preconditionFailure("wrong dimension root") }
        precondition(items.isEmpty)
        let reopened = try DimensionStore(database: db).snapshot()
        precondition(reopened.map(\.id) == [1000,1001])
        try db.put(Data([1,2,3]), for: Data("existing_global_control".utf8))
        let invalid: [(String,Int32)] = [("bear",2000),("other",1000),("existing_global_control",2000),("scoreboard",2000),("portals",2000),("dimension1",2000),("schedulerWT",2000),("map_test",2000),("123",2000),("white space",2000),("overworld",5),("other",0)]
        for (name,id) in invalid {
            let before = db.values
            do { try store.add(name: name,id: id); preconditionFailure("invalid add accepted") }
            catch { precondition(db.values == before) }
        }
        let vanilla: [(String,Int32,String)] = [("overworld",0,"Overworld"),("nether",1,"Nether"),("the_end",2,"TheEnd")]
        for (name,id,key) in vanilla {
            try store.add(name: name,id: id)
            let bytes = try db.get(Data(key.utf8))
            precondition(bytes != nil)
        }
        try store.add(name: "negative",id: Int32.min)
        try store.add(name: "positive",id: Int32.max)
        print("Dimension add tests passed.")
    }
}
