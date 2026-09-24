using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;

internal static class ObjectEditorRefreshTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("Object editor refresh: " + message);
    }

    public static void Run()
    {
        using var db = new SelfTestWorldDatabase();
        var blocks = new BedrockRegionBlockStore(db);
        blocks.SetBlock(0, new(1, 64, 1), [new("minecraft:chest", []), new("minecraft:water", [])]);
        var store = new BedrockWorldObjectNbtStore(db);
        store.Create(BedrockWorldObjectKind.BlockEntity, "Chest", new(1, 64, 1), 0);
        var current = new BedrockWorldObjectScanner(db).ScanRegion(0, 0, 0, 0, false, true).Objects.Single();
        foreach (var (x, dimension) in new[] { (17, 0), (-17, 2), (-17, 2) })
        {
            var previous = current;
            var tags = ((NbtCompoundValue)current.Document.Root).Tags
                .Where(t => t.Name is not ("x" or "DimensionId" or "Marker")).ToList();
            tags.Add(new("x", new NbtIntValue(x)));
            tags.Add(new("DimensionId", new NbtIntValue(dimension)));
            tags.Add(new("Marker", new NbtStringValue(Guid.NewGuid().ToString())));
            var edited = new NbtDocument(current.Document.RootName, new NbtCompoundValue(tags));
            store.Save(current, edited);
            current = store.RefreshedObject(current, edited);
            Check(current.Dimension == dimension && current.Position?.BlockX == x, "saved identity/location not refreshed");
            Check(current.RawData.SequenceEqual(BedrockNbtCodec.Encode(edited, current.Storage.Encoding)), "saved NBT was not rebound");
            var layers = new BedrockBlockStore(db).ReadBlock(dimension, x, 64, 1).Layers;
            Check(layers.Count == 2 && layers[0].Name == "minecraft:chest" && layers[1].Name == "minecraft:water", "repeated move lost block layers");
            if (previous.Dimension != dimension || previous.Position!.BlockX != x)
                Check(new BedrockBlockStore(db).ReadBlock(previous.Dimension, previous.Position!.BlockX, 64, 1).Layers.All(l => l.IsAir), "old block left behind");
        }
        Console.WriteLine("Object editor refresh passed: same editor repeated block-entity saves across chunks/dimensions and all block layers.");
    }
}
