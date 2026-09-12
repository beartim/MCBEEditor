using System.Text.Json;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

internal static class PersistenceCompatibilityTests
{
    public static void Run()
    {
        static void Check(bool condition, string message)
        {
            if (!condition) throw new Exception("Persistence compatibility: " + message);
        }
        var vectors = new List<object>();
        foreach (var test in new (byte Version, bool Val)[] { (0, false), (7, false), (1, true), (8, true), (8, false), (9, false) })
        {
            using var db = new SelfTestWorldDatabase();
            var numeric = test.Version is 0 or 7;
            var palette = new BedrockPaletteFormat(test.Val, test.Val ? null : 17825808);
            var seed = numeric ? BedrockSubChunk.EmptyLegacy(test.Version, 0)
                : new BedrockSubChunk(test.Version, 0, [SubChunkStorage.AirFilled(palette.Air)], []);
            var seedKey = BedrockDbKey.SubChunk(0, 0, 2, 0);
            var seedRaw = seed.EncodePersistent();
            db.Put(seedKey, seedRaw);
            var versionType = test.Version == 9 ? ChunkRecordType.Version : ChunkRecordType.LegacyVersion;
            byte[] versionRaw = test.Version == 9 ? [40] : [19];
            db.Put(new BedrockDbKey(new(0, 0, 2), versionType, null).Encode(), versionRaw);
            db.Put(new BedrockDbKey(new(0, 0, 2), ChunkRecordType.FinalizedState, null).Encode(), [2, 0, 0, 0]);
            db.Put(new BedrockDbKey(new(0, 0, 2), ChunkRecordType.Data2D, null).Encode(), new byte[768]);
            var store = new BedrockBlockStore(db);
            foreach (var x in new[] { 3, 35 }) // absent slice, then wholly absent chunk
            {
                const int y = 200, z = 5;
                var template = store.ReadBlockForEditing(2, x, y, z);
                Check(!template.Generated, "reading an editing template must not generate terrain");
                if (numeric) store.SaveLegacyState(2, x, y, z, 0, 57, 0);
                else
                {
                    var tags = ((NbtCompoundValue)template.Layers[0].Nbt!).Tags
                        .Select(tag => tag.Name == "name" ? new NbtNamedTag("name", new NbtStringValue("minecraft:diamond_block")) : tag).ToArray();
                    store.SaveModernState(2, x, y, z, 0, new NbtDocument("", new NbtCompoundValue(tags)));
                }
                var saved = store.ReadBlock(2, x, y, z);
                Check(saved.SubChunkVersion == test.Version, "creation must retain the observed header version");
                Check(saved.Layers[0].Name == "minecraft:diamond_block", "created block identity");
                if (test.Val)
                    Check(saved.Layers[0].Nbt!.CompoundValue("val") is NbtShortValue
                        && saved.Layers[0].Nbt!.CompoundValue("states") is null
                        && saved.Layers[0].PaletteVersion is null, "unversioned val schema must stay unversioned val");
                var raw = db.Get(BedrockDbKey.SubChunk(x / 16, 0, 2, 12))!;
                vectors.Add(new { name = $"v{test.Version}-{test.Val}-{x}", raw = Convert.ToBase64String(raw),
                    version = test.Version, val = test.Val, x = 3, y = 8, z = 5, block = "minecraft:diamond_block" });
                var pos = new ChunkPosition(x / 16, 0, 2);
                Check(db.Get(new BedrockDbKey(pos, versionType, null).Encode())!.SequenceEqual(versionRaw), "new chunk version metadata");
                Check(db.Get(new BedrockDbKey(pos, ChunkRecordType.FinalizedState, null).Encode())!.SequenceEqual(new byte[] { 2, 0, 0, 0 }), "new chunk finalization metadata");
            }
            Check(db.Get(seedKey)!.SequenceEqual(seedRaw), "unmodified original SubChunk must remain byte-identical");
            if (test.Version is 8 or 9)
            {
                var storageStore = new BedrockStorageCommandStore(db);
                var beforeAbsent = db.ApplyBatchCount;
                Check(storageStore.Query(2, new(3, 220, 5)).Single() == "Block not generated", "missing slice query");
                Check(storageStore.Delete(2, new(3, 220, 5), 0).PutCount == 0, "missing slice delete is a no-op");
                Check(storageStore.Clear(2, new(3, 220, 5), 0).PutCount == 0, "missing slice clear is a no-op");
                Check(db.ApplyBatchCount == beforeAbsent, "query/delete/clear on missing terrain must not write");
                storageStore.Set(2, new(3, 220, 5), 2, new("minecraft:diamond_block", []));
                var raw = db.Get(BedrockDbKey.SubChunk(0, 0, 2, 13))!;
                var decoded = BedrockSubChunk.Decode(raw, 13);
                Check(decoded.Storages.Count == 3 && decoded.Storages[0].Palette.All(state => state.IsAir), "creating storage2 must preserve empty storage0/1");
                if (test.Version == 8) Check(decoded.Storages.All(storage => storage.BitsPerBlock >= 1), "old v8 readers require one-bit empty storages");
                vectors.Add(new { name = $"v{test.Version}-{test.Val}-storage2", raw = Convert.ToBase64String(raw),
                    version = test.Version, val = test.Val, x = 3, y = 12, z = 5, block = "minecraft:diamond_block", layer = 2 });
            }
            // An as-yet-unvisited dimension inherits a real world format.
            Check(BedrockEmptyChunkMetadata.DetectBlockFormat(db, 1).SubChunkVersion == test.Version, "empty dimension format fallback");
            if (numeric)
            {
                var before = db.ApplyBatchCount;
                try
                {
                    new BedrockRegionBlockStore(db).SetBlock(2, new(67, 200, 5), [new("minecraft:not_in_old_game", [])]);
                    throw new Exception("unrepresentable legacy edit unexpectedly succeeded");
                }
                catch (NotSupportedException) { }
                Check(db.ApplyBatchCount == before, "failed conversion must not write metadata or terrain");
            }
        }
        // A partially present chunk still needs its version/finalized records.
        using (var db = new SelfTestWorldDatabase())
        {
            db.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), new BedrockSubChunk(8, 0,
                [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir(17825808))], []).EncodePersistent());
            db.Put(new BedrockDbKey(new(0, 0, 0), ChunkRecordType.LegacyVersion, null).Encode(), [19]);
            var partial = new ChunkPosition(4, 4, 0);
            var biomeKey = new BedrockDbKey(partial, ChunkRecordType.Data2D, null).Encode();
            db.Put(biomeKey, new byte[768]);
            new BedrockRegionBlockStore(db).SetBlock(0, new(64, 200, 64), [new("minecraft:diamond_block", [])]);
            Check(db.Get(new BedrockDbKey(partial, ChunkRecordType.LegacyVersion, null).Encode()) is { Length: 1 }, "partial chunk must receive its missing version");
            Check(db.Get(new BedrockDbKey(partial, ChunkRecordType.FinalizedState, null).Encode()) is { Length: 4 }, "partial chunk must receive finalization");
            Check(db.Get(biomeKey)!.SequenceEqual(new byte[768]), "existing biome record preserved");
        }
        if (Environment.GetEnvironmentVariable("MCBE_AUDIT_VECTORS") is { Length: > 0 } output)
            File.WriteAllText(output, JsonSerializer.Serialize(vectors));
        Console.WriteLine("Persistence compatibility matrix passed: numeric/v1/v8/v9, val/states, missing chunks/slices, empty layers and atomic rejection.");
    }
}
