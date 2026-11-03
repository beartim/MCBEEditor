import Foundation

enum Drop4CatalogRegression {
    static func run() throws {
        for (id, identifier, name) in [(155, "minecraft:frostbite", "冻尸"), (156, "minecraft:ice_ball", "冰球")] {
            precondition(BedrockDataValueCatalog.search(BedrockDataValueCatalog.entities, query: name)
                .contains { $0.id == id && $0.identifier == identifier }, "Drop 4 entity/search missing: \(name)")
            precondition(BedrockDataValueCatalog.entityIdentifier(forRawValue: String(id)) == identifier, "numeric entity bridge")
            let session = WorldSession()
            let key = BedrockDBKey(position: ChunkPosition(x: 0, z: 0, dimension: 0), recordType: .entity, subChunkIndex: nil).encoded()
            let document = NBTDocument(rootName: "", root: .compound([
                NBTNamedTag(name: "id", value: .int(Int32(id))), NBTNamedTag(name: "UniqueID", value: .long(1)) ]))
            try session.db.put(BedrockNBTCodec.encode(document), for: key)
            let scan = try BedrockWorldObjectScanner(database: session.db).scanAll(
                dimensions: nil, includeEntities: true, includeBlockEntities: false, maximumObjects: Int.max)
            precondition(scan.objects.count == 1 && scan.objects[0].identifier == identifier, "numeric entity scanner")
        }
        precondition(BedrockDataValueCatalog.biome(forIdentifier: "minecraft:ice_caves")?.id == 196, "ice cave ID")
        precondition(BedrockDataValueCatalog.search(BedrockDataValueCatalog.biomes, query: "冰封洞穴").contains { $0.id == 196 }, "ice cave search")
        let colors: [(String, UInt32)] = [
            ("ice_crystal", 0xB0DAD3), ("icicle", 0xB9D9EC), ("brittle_ice", 0xA7C7EA),
            ("packed_ice_bricks", 0x8DB4EA), ("packed_ice_brick_stairs", 0x8DB4EA),
            ("packed_ice_brick_slab", 0x8DB4EA), ("packed_ice_brick_double_slab", 0x8DB4EA),
            ("packed_ice_brick_wall", 0x8DB4EA), ("chiseled_packed_ice", 0x8DB4EA),
            ("snow_bricks", 0xF1F6F7), ("snow_brick_stairs", 0xF1F6F7),
            ("snow_brick_slab", 0xF1F6F7), ("snow_brick_wall", 0xF1F6F7) ]
        for (name, color) in colors {
            precondition(BedrockBlockMapColorCatalog.rgbHex(for: "minecraft:" + name) == color, "Drop 4 color: \(name)")
        }
        precondition(BedrockLegacyBlockCatalog.blocks.count == 256 && BedrockLegacyBlockCatalog.blocks.allSatisfy { $0.id <= 255 }, "modern IDs in legacy conversion")
        let session = WorldSession(), key = Data("~local_player".utf8)
        try session.db.put(BedrockNBTCodec.encode(NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "UniqueID", value: .long(100)), NBTNamedTag(name: "PlayerLevel", value: .int(7)) ]))), for: key)
        func execute(_ command: String) throws { _ = try WorldCommandExecutor(session: session).execute(WorldCommandParser.parse(command)) }
        func ids() throws -> [Int64] {
            let root = try BedrockNBTCodec.decode(session.db.values[key]!).root
            precondition(root.int64Value(namedAny: ["PlayerLevel"]) == 7, "effect changed unrelated NBT")
            guard case .list(_, let values)? = root.compoundValue(named: "ActiveEffects") else { return [] }
            return values.compactMap { $0.int64Value(namedAny: ["Id"]) }.sorted()
        }
        try execute("effect give @a freezing 200 1")
        var actual = try ids(); precondition(actual == [38], "freezing must write Id 38")
        try execute("effect clear @a freezing")
        actual = try ids(); precondition(actual.isEmpty, "named clear")
        try execute("effect give @a ALL 200 1")
        actual = try ids(); precondition(actual == Array(1...38).map(Int64.init), "ALL omits or duplicates freezing")
        try execute("effect clear @a freezing")
        actual = try ids(); precondition(actual == Array(1...37).map(Int64.init), "clear removed another effect")
        print("Drop 4 regression passed: numeric entity scan, Chinese searches, biome, ice colors and freezing NBT/ALL")
    }
}
