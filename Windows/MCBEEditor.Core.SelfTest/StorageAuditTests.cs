using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

internal static class StorageAuditTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("Storage audit: " + message);
    }

    public static void Run()
    {
        foreach (byte version in new byte[] { 8, 9 })
        {
            using var db = new SelfTestWorldDatabase();
            var air = version == 8 ? new BedrockPaletteFormat(true, null).Air : BedrockBlockState.EditableAir(17825808);
            var seedKey = BedrockDbKey.SubChunk(0, 0, 2, 0);
            var seed = new BedrockSubChunk(version, 0, [SubChunkStorage.AirFilled(air)], []).EncodePersistent();
            db.Put(seedKey, seed);
            var store = new BedrockStorageCommandStore(db);
            var missing = new BedrockBlockCoordinate(16, 200, 16);
            var beforeMissing = db.ApplyBatchCount;
            Check(store.Query(2, missing).Single() == "Block not generated" && store.Delete(2, missing, 0).PutCount == 0
                  && store.Clear(2, missing, 255).PutCount == 0 && db.ApplyBatchCount == beforeMissing, "missing storage operations must not write");
            foreach (var y in new[] { 160, 200, 255 })
            {
                var result = store.Set(2, new(16, y, 16), 0, new("minecraft:air", []));
                var key = BedrockDbKey.SubChunk(1, 1, 2, (sbyte)(y / 16));
                var raw = db.Get(key);
                Check(result.PutCount > 0 && raw is not null, "explicit layer0 air must create a persistent high End slice");
                var saved = BedrockSubChunk.Decode(raw!, (sbyte)(y / 16));
                Check(saved.Version == version && saved.Storages.Count == 1 && saved.Storages[0].BlockState(0, y % 16, 0)!.IsAir,
                    "new End slice must retain source format");
                if (version == 8) Check(saved.Storages[0].BitsPerBlock >= 1 && saved.Storages[0].Palette.All(s => s.Nbt!.CompoundValue("val") is not null && s.PaletteVersion is null), "v8 val schema and empty storage bits");
            }
            var beforeDelete = db.ApplyBatchCount;
            var unchanged = store.Delete(2, new(16, 160, 16), 0);
            Check(unchanged.PutCount == 0 && db.ApplyBatchCount == beforeDelete, "deleting the only empty storage must report the actual zero writes");
            store.Set(2, missing, 254, new("minecraft:diamond_block", []));
            Check(store.Query(2, missing).Count == 255, "storage254 must materialize 255 storages");
            var beforeRepeat = db.ApplyBatchCount;
            Check(store.Set(2, missing, 254, new("minecraft:diamond_block", [])).PutCount == 0 && db.ApplyBatchCount == beforeRepeat,
                "repeated storage set must not append duplicate val palette entries");
            var beforeClear = db.ApplyBatchCount;
            Check(store.Clear(2, missing, 255).PutCount == 0 && store.Clear(2, missing, 254).PutCount == 0
                  && db.ApplyBatchCount == beforeClear, "clear255 and retaining the current highest layer are no-ops");
            store.Set(2, new(17, 200, 16), 1, new("minecraft:gold_block", []));
            store.Delete(2, missing, 0);
            var shifted = new BedrockBlockStore(db).ReadBlock(2, 17, 200, 16);
            Check(shifted.Layers.Count == 254 && shifted.Layers[0].Name == "minecraft:gold_block", "delete must shift the whole storage, including other coordinates");
            Check(new BedrockBlockStore(db).ReadBlock(2, 16, 200, 16).Layers[253].Name == "minecraft:diamond_block", "highest physical layer must shift");
            Check(db.Get(seedKey)!.SequenceEqual(seed), "original End terrain must remain byte-identical");
            var beforeInvalid = db.ApplyBatchCount;
            var rejected = false;
            try { store.Set(2, missing, 255, new("minecraft:stone", [])); }
            catch (ArgumentOutOfRangeException) { rejected = true; }
            Check(rejected && db.ApplyBatchCount == beforeInvalid, "storage255 must be rejected without a write");
        }
        Console.WriteLine("Storage audit scenarios passed.");
    }
}
