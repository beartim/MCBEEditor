using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

internal static class StructureAuditTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("Structure audit: " + message);
    }
    public static void Run()
    {
        using var db = new SelfTestWorldDatabase();
        var store = new BedrockRegionBlockStore(db);
        byte[] Key(int dim, int x = 0) => new BedrockDbKey(new(x, 0, dim), ChunkRecordType.BlockEntity, null).Encode();
        byte[] Record(sbyte? x, string marker)
        {
            var tags = new List<NbtNamedTag> { new("Marker", new NbtStringValue(marker)), new("DimensionId", new NbtIntValue(0)) };
            if (x.HasValue) tags.AddRange([new("x", new NbtByteValue(x.Value)), new("y", new NbtByteValue(0)), new("z", new NbtByteValue(0))]);
            return BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue(tags)));
        }
        store.SetBlock(0, new(0, 0, 0), [new("minecraft:stone", []), new("minecraft:water", [])]);
        db.Put(Key(0), Record(0, "source"));
        var document = store.CaptureStructureDocument(0, new(new(0, 0, 0), new(0, 0, 0)));
        var outside = Record(5, "outside-a").Concat(Record(null, "orphan")).Concat(Record(5, "outside-b")).ToArray();
        db.Put(Key(1), outside.Concat(Record(1, "old-target")).ToArray());
        store.LoadStructureDocument(document, 1, new(1, 0, 0));
        var records = ConsecutiveNbtCodec.Decode(db.Get(Key(1))!);
        Check(records.Count == 4 && ConsecutiveNbtCodec.Encode(records.Take(3)).SequenceEqual(outside), "unrelated records changed");
        Check(records[3].Document.Root.CompoundValue("x")?.IntegerValue() == 1 && records[3].Document.Root.CompoundValue("DimensionId")?.IntegerValue() == 1, "coordinate/dimension relocation");
        store.LoadStructureDocument(document, 1, new(300, 0, 0));
        Check(ConsecutiveNbtCodec.Decode(db.Get(Key(1, 18))!)[0].Document.Root.CompoundValue("x")?.IntegerValue() == 300, "Byte coordinate was clamped");
        db.Put(Key(0), Record(0, "first").Concat(Record(0, "duplicate")).ToArray());
        var batches = db.ApplyBatchCount;
        var rejected = false;
        try { store.CaptureStructureDocument(0, new(new(0, 0, 0), new(0, 0, 0))); }
        catch (InvalidDataException) { rejected = true; }
        Check(rejected && db.ApplyBatchCount == batches, "duplicate source must reject without writes");
        Console.WriteLine("Structure audit scenarios passed.");
    }
}
