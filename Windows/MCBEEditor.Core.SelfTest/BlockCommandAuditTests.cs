using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

internal static class BlockCommandAuditTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("Block command audit: " + message);
    }

    public static void Run()
    {
        using var db = new SelfTestWorldDatabase();
        var store = new BedrockRegionBlockStore(db);
        var reader = new BedrockBlockStore(db);
        foreach (var x in new[] { -17, -16, -1, 0, 15, 16, 17 })
            store.SetBlock(0, new(x, 64, -1), [new("minecraft:stone", []), new("minecraft:water", []), new("minecraft:diamond_block", [])]);
        store.Fill(0, new(new(-17, 64, -1), new(16, 64, -1)), [new("minecraft:dirt", [])]);
        foreach (var x in new[] { -17, -16, -1, 0, 15, 16 })
        {
            var layers = reader.ReadBlock(0, x, 64, -1).Layers;
            Check(layers.Count == 3 && layers[0].Name == "minecraft:dirt" && layers[1].Name == "minecraft:water"
                  && layers[2].Name == "minecraft:diamond_block", "negative/cross-chunk fill must preserve omitted layers");
        }
        Check(reader.ReadBlock(0, 17, 64, -1).Layers[0].Name == "minecraft:stone", "fill changed neighboring block");
        store.SetBlock(0, new(-1, 64, -1), [new("minecraft:dirt", []), new("minecraft:air", [])]);
        Check(reader.ReadBlock(0, -1, 64, -1).Layers[1].IsAir && reader.ReadBlock(0, -1, 64, -1).Layers[2].Name == "minecraft:diamond_block",
            "explicit air must only clear the supplied layer");
        Check(store.GetBlockText(0, new(-1, 64, -1)).Contains("Storage2=["), "getblock must include every storage");

        byte[] Record(int? x, string marker)
        {
            var tags = new List<NbtNamedTag> { new("id", new NbtStringValue("Chest")), new("Marker", new NbtStringValue(marker)), new("Items", new NbtListValue(NbtTagType.End, [])) };
            if (x.HasValue) tags.AddRange([new("x", new NbtIntValue(x.Value)), new("y", new NbtIntValue(0)), new("z", new NbtIntValue(0))]);
            return BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue(tags)), NbtEncoding.LittleEndian);
        }
        var key = new BedrockDbKey(new(0, 0, 0), ChunkRecordType.BlockEntity, null).Encode();
        var first = Record(1, "first-outside");
        var orphan = Record(null, "no-position");
        var second = Record(1, "second-outside");
        var kept = first.Concat(orphan).Concat(second).ToArray();
        db.Put(key, first.Concat(Record(0, "target-a")).Concat(orphan).Concat(second).Concat(Record(0, "target-b")).ToArray());
        Check(store.GetBlockText(0, new(1, 0, 0)).Contains("first-outside"), "getblock duplicate-coordinate lookup must use the first stored record");
        Check(store.GetBlockText(0, new(1, 0, 0)).Contains("'List'''\"Items\"=\"\"", StringComparison.Ordinal),
            "getblock must print an unspecified empty block-entity List with an empty element-type marker");
        var changed = store.SetBlock(0, new(0, 0, 0), [new("minecraft:stone", [])]);
        Check(changed.RemovedBlockEntities == 2 && db.Get(key)!.SequenceEqual(kept), "fill lost outside duplicates, coordinate-less records or record order");
        store.SetBlock(0, new(2, 0, 0), [new("minecraft:stone", [])]);
        Check(db.Get(key)!.SequenceEqual(kept), "no matching block entity must leave the original bytes unchanged");
        var brokenKey = new BedrockDbKey(new(1, 0, 0), ChunkRecordType.BlockEntity, null).Encode();
        db.Put(brokenKey, [10, 0, 0, 3]);
        var beforeBroken = db.Entries(includeValues: true).ToDictionary(e => Convert.ToHexString(e.Key), e => Convert.ToHexString(e.Value!));
        var brokenRejected = false;
        try { store.Fill(0, new(new(0, 0, 0), new(16, 0, 0)), [new("minecraft:dirt", [])]); }
        catch (InvalidDataException) { brokenRejected = true; }
        var afterBroken = db.Entries(includeValues: true).ToDictionary(e => Convert.ToHexString(e.Key), e => Convert.ToHexString(e.Value!));
        Check(brokenRejected && beforeBroken.Count == afterBroken.Count && beforeBroken.All(e => afterBroken.TryGetValue(e.Key, out var value) && value == e.Value),
            "malformed block entity must abort the whole fill before any write");

        using var legacy = new SelfTestWorldDatabase();
        legacy.Put(BedrockDbKey.SubChunk(0, 0, 0, 0), BedrockSubChunk.EmptyLegacy(7, 0).EncodePersistent());
        legacy.Put(new BedrockDbKey(new(0, 0, 0), ChunkRecordType.LegacyVersion, null).Encode(), [19]);
        var before = legacy.Entries(includeValues: true).ToDictionary(e => Convert.ToHexString(e.Key), e => Convert.ToHexString(e.Value!));
        foreach (var specs in new BedrockBlockStorageSpec[][] {
            [new("minecraft:not_in_old_game", [])],
            [new("minecraft:stone", []), new("minecraft:air", []), new("minecraft:air", [])] })
        {
            var rejected = false;
            try { new BedrockRegionBlockStore(legacy).SetBlock(0, new(64, 64, 64), specs); }
            catch (NotSupportedException) { rejected = true; }
            var after = legacy.Entries(includeValues: true).ToDictionary(e => Convert.ToHexString(e.Key), e => Convert.ToHexString(e.Value!));
            Check(rejected && before.Count == after.Count && before.All(e => after.TryGetValue(e.Key, out var value) && value == e.Value),
                "rejected legacy edit must not leave metadata or partial terrain");
        }
        Console.WriteLine("Block command audit scenarios passed.");
    }
}
