import Foundation

enum DimensionCommandResolverTests {
    static func run() throws {
        let db = MojangLevelDB(), store = DimensionStore(database: db)
        try store.add(name: "wzn:bear", id: 1000)
        try store.add(name: "bear", id: 1001)
        func parse(_ command: String) throws -> ParsedWorldCommand { try WorldCommandParser.parse(command, dimensionResolver: store.resolve) }
        guard case .setBlock(let id, _, _) = try parse("setblock wzn:bear 0 64 0 minecraft:stone NULL"), id == 1000 else { preconditionFailure("setblock name") }
        guard case .clone(let source, _, let target, _) = try parse("clone wzn:bear 0 0 0 1 1 1 bear 2 2 2"), source == 1000, target == 1001 else { preconditionFailure("clone names") }
        guard case .entity(let id, _) = try parse("entity bear"), id == 1001 else { preconditionFailure("entity name") }
        _ = try parse("storage query bear 0 64 0")
        _ = try parse("teleport @s bear 0 Auto 0")
        _ = try parse("summon minecraft:pig bear 0 64 0 default")
        _ = try parse("structure load wzn:test bear 0 64 0")
        _ = try parse("tickingarea add circle bear 0 0 1 test 0")
        guard case .getBlock(let id, _) = try WorldCommandParser.parse("getblock -2147483648 0 0 0"), id == Int32.min else { preconditionFailure("numeric boundary") }
        do { _ = try parse("getblock missing 0 0 0"); preconditionFailure("unknown name accepted") } catch { }
        let otherDB = MojangLevelDB(), otherStore = DimensionStore(database: otherDB)
        try otherStore.add(name: "bear", id: 9000)
        guard case .getBlock(let id, _) = try WorldCommandParser.parse("getblock bear 0 0 0", dimensionResolver: otherStore.resolve), id == 9000 else { preconditionFailure("world isolation") }
        let initial = try store.snapshot()
        let before = db.values
        let context = try DimensionCommandContext(database: db)
        try context.apply(WorldCommandParser.parse("dimension add new:name 8000", dimensionResolver: context.resolve))
        guard case .getBlock(let projected, _) = try WorldCommandParser.parse("getblock new:name 0 0 0", dimensionResolver: context.resolve), projected == 8000 else { preconditionFailure("projected add") }
        do { try context.apply(WorldCommandParser.parse("dimension add conflict 8000")); preconditionFailure("duplicate projected ID") } catch { }
        try context.apply(WorldCommandParser.parse("dimension purge new:name"))
        do { _ = try context.resolve("new:name"); preconditionFailure("purged name resolved") } catch { }
        try context.apply(WorldCommandParser.parse("dimension add new:name 8000"))
        let newID = try context.resolve("new:name")
        precondition(newID == 8000)
        let after = try store.snapshot()
        precondition(db.values == before && initial.count == after.count, "preflight wrote world")
        let unbound = DimensionCommandContext()
        _ = try WorldCommandParser.parse("getblock existing:name 0 0 0", dimensionResolver: unbound.resolve)
        do { _ = try WorldCommandParser.parse("getblock 2147483648 0 0 0", dimensionResolver: unbound.resolve); preconditionFailure("overflow accepted in validate") } catch { }
        print("Dimension command resolver tests passed.")
    }
}
