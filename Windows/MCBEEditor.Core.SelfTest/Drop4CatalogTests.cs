using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

internal static class Drop4CatalogTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("Drop 4 catalog: " + message);
    }

    public static void Run()
    {
        foreach (var (id, identifier, name) in new[] { (155, "minecraft:frostbite", "冻尸"), (156, "minecraft:ice_ball", "冰球") })
        {
            Check(BedrockDataValueCatalog.Search(BedrockDataValueCatalog.Entities, name)
                .Any(entry => entry.Id == id && entry.Identifier == identifier), "entity search: " + name);
            Check(BedrockEntityCatalog.IdentifierForNumericId(id) == identifier
                  && BedrockEntityCatalog.NumericIdForIdentifier(identifier) == id, "numeric entity bridge: " + identifier);
            using var database = new SelfTestWorldDatabase();
            var key = new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.Entity, null).Encode();
            database.Put(key, BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue([
                new("id", new NbtIntValue(id)), new("UniqueID", new NbtLongValue(1)) ])), NbtEncoding.LittleEndian));
            var scanned = new BedrockWorldObjectScanner(database).ScanAll(null, true, false, int.MaxValue).Objects;
            Check(scanned.Single().Identifier == identifier, "numeric NBT entity type not recognized");
        }
        Check(BedrockDataValueCatalog.Search(BedrockDataValueCatalog.Biomes, "冰封洞穴")
            .Any(entry => entry.Id == 196 && entry.Identifier == "minecraft:ice_caves"), "biome ID/search");
        Check(BedrockBiomeCatalog.EntryForId(196)?.Identifier == "minecraft:ice_caves", "biome editor catalog");
        Check(BedrockBiomeCatalog.ColorForId(196) == 0x9ABBDD, "ice cave map color");
        foreach (var (name, color) in new[] {
            ("ice_crystal", 0xB0DAD3u), ("icicle", 0xB9D9ECu), ("brittle_ice", 0xA7C7EAu),
            ("packed_ice_bricks", 0x8DB4EAu), ("packed_ice_brick_stairs", 0x8DB4EAu),
            ("packed_ice_brick_slab", 0x8DB4EAu), ("packed_ice_brick_double_slab", 0x8DB4EAu),
            ("packed_ice_brick_wall", 0x8DB4EAu), ("chiseled_packed_ice", 0x8DB4EAu),
            ("snow_bricks", 0xF1F6F7u), ("snow_brick_stairs", 0xF1F6F7u),
            ("snow_brick_slab", 0xF1F6F7u), ("snow_brick_wall", 0xF1F6F7u) })
            Check(BedrockBlockMapColorCatalog.RgbHex("minecraft:" + name) == color, "block color: " + name);
        Check(BedrockDataValueCatalog.LegacyBlocks.Count == 256
            && BedrockDataValueCatalog.LegacyBlocks.All(entry => entry.Id <= 255), "modern IDs leaked into legacy block conversion");
        Effects();
        Console.WriteLine("Drop 4 passed: entity scan/search, ice cave, material colors, freezing NBT ID/ALL and legacy isolation.");
    }

    private static void Effects()
    {
        using var database = new SelfTestWorldDatabase();
        var key = Encoding.UTF8.GetBytes("~local_player");
        database.Put(key, BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue([
            new("UniqueID", new NbtLongValue(100)), new("PlayerLevel", new NbtIntValue(7)) ])), NbtEncoding.LittleEndian));
        var store = new EntityActionCommandStore(database);
        void Execute(string command) => store.Effect((EffectEntityActionCommandRequest)EntityActionCommandParser.Parse(command));
        long[] Ids()
        {
            var root = BedrockNbtCodec.Decode(database.Get(key)!, NbtEncoding.LittleEndian).Root;
            Check(root.CompoundValue("PlayerLevel")?.IntegerValue() == 7, "effect changed unrelated NBT");
            return root.CompoundValue("ActiveEffects") is NbtListValue list
                ? list.Values.Select(value => value.CompoundValue("Id")!.IntegerValue()!.Value).Order().ToArray() : [];
        }
        Execute("effect give @a freezing 200 1");
        Check(Ids().SequenceEqual(new long[] { 38 }), "freezing must write Id 38");
        Execute("effect clear @a freezing");
        Check(Ids().Length == 0, "named effect clear");
        Execute("effect give @a ALL 200 1");
        Check(Ids().SequenceEqual(Enumerable.Range(1, 38).Select(value => (long)value)), "ALL omits or duplicates freezing");
        Execute("effect clear @a freezing");
        Check(Ids().SequenceEqual(Enumerable.Range(1, 37).Select(value => (long)value)), "named clear changed another effect");
    }
}
