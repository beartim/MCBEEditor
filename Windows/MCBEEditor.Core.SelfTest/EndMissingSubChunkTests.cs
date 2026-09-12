using System.Text.Json;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

internal static class EndMissingSubChunkTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("End missing-SubChunk regression: " + message);
    }

    public static void Run()
    {
        using var fixture = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Fixtures", "end_missing_subchunks.json")));
        var root = fixture.RootElement;
        var paletteVersion = root.GetProperty("paletteVersion").GetInt32();
        ChunkPosition Position(string name)
        {
            var values = root.GetProperty(name).EnumerateArray().Select(value => value.GetInt32()).ToArray();
            return new ChunkPosition(values[0], values[1], values[2]);
        }
        SelfTestWorldDatabase Load()
        {
            var db = new SelfTestWorldDatabase();
            foreach (var entry in root.GetProperty("entries").EnumerateArray())
                db.Put(Convert.FromBase64String(entry.GetProperty("keyBase64").GetString()!),
                    Convert.FromBase64String(entry.GetProperty("valueBase64").GetString()!));
            return db;
        }
        void CheckOriginals(IWorldDatabase db)
        {
            foreach (var entry in root.GetProperty("entries").EnumerateArray())
                Check(db.Get(Convert.FromBase64String(entry.GetProperty("keyBase64").GetString()!))!
                    .SequenceEqual(Convert.FromBase64String(entry.GetProperty("valueBase64").GetString()!)),
                    "existing terrain and metadata must remain byte-identical");
        }
        var v8Chunk = Position("v8Chunk");
        foreach (var chunk in new[] { v8Chunk, Position("v1Chunk"), Position("emptyChunk") })
        {
            using var db = Load();
            var store = new BedrockBlockStore(db);
            var expectedVersion = chunk == Position("v1Chunk") ? (byte)1 : (byte)8;
            int? expectedPaletteVersion = expectedVersion == 1 ? null : paletteVersion;
            foreach (var y in new[] { 160, 200, 255 })
            {
                var x = chunk.X * 16; var z = chunk.Z * 16;
                var template = store.ReadBlockForEditing(2, x, y, z);
                Check(!template.Generated && template.Layers.Count == 1, "missing slice must remain ungenerated until save");
                Check(template.Layers[0].PaletteVersion == expectedPaletteVersion && template.Layers[0].Nbt is not null,
                    "air template must inherit the saved End schema, including v1/metadata-only chunks");
                var tags = ((NbtCompoundValue)template.Layers[0].Nbt!).Tags
                    .Select(tag => tag.Name == "name" ? new NbtNamedTag("name", new NbtStringValue("minecraft:diamond_block")) : tag).ToArray();
                store.SaveModernState(2, x, y, z, 0, new NbtDocument(string.Empty, new NbtCompoundValue(tags)));
                var saved = store.ReadBlock(2, x, y, z);
                Check(saved.Generated && saved.SubChunkVersion == expectedVersion, "new slice must use the compatible v1/v8 format");
                Check(saved.Layers[0].Name == "minecraft:diamond_block" && saved.Layers[0].PaletteVersion == expectedPaletteVersion,
                    "saved block and version must read back at the original coordinates");
            }
            CheckOriginals(db);
        }

        foreach (var storageCount in new[] { 1, 3, 255 })
        {
            using var db = Load();
            var specs = Enumerable.Range(0, storageCount).Select(_ => new BedrockBlockStorageSpec("minecraft:diamond_block", [])).ToArray();
            var regionStore = new BedrockRegionBlockStore(db);
            var position = new BedrockBlockCoordinate(v8Chunk.X * 16, 200, v8Chunk.Z * 16);
            regionStore.SetBlock(2, position, specs);
            var raw = db.Get(BedrockDbKey.SubChunk(v8Chunk.X, v8Chunk.Z, 2, 12))!;
            var decoded = BedrockSubChunk.Decode(raw, 12);
            Check(decoded.Version == 8 && decoded.Storages.Count == storageCount, "setblock must retain v8 with 1/3/255 storages");
            Check(decoded.Storages.All(storage => storage.BlockState(0, 8, 0)?.Name == "minecraft:diamond_block"
                && storage.BlockState(0, 8, 0)?.PaletteVersion == paletteVersion), "all storages must use the saved palette schema");
            Check(new BedrockBlockStore(db).ReadBlock(2, position.X, 201, position.Z).Layers.All(state => state.IsAir),
                "neighboring positions must stay air");
            CheckOriginals(db);
        }

        using (var db = Load())
        {
            var regionStore = new BedrockRegionBlockStore(db);
            var from = new BedrockBlockCoordinate(0, 16, 0);
            regionStore.Clone(2, new BedrockBlockBox(from, from), 2, new BedrockBlockCoordinate(0, 220, 0));
            var saved = new BedrockBlockStore(db).ReadBlock(2, 0, 220, 0);
            Check(saved.Generated && saved.SubChunkVersion == 8, "clone into a missing End slice must preserve v8");
            CheckOriginals(db);
        }
        Console.WriteLine("End missing-SubChunk fixture tests passed: editing templates, v1/v8 creation, 255 storages and clone.");
    }
}
