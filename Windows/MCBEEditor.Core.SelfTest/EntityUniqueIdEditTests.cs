using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;

static class EntityUniqueIdEditTests
{
    public static void Run()
    {
        ModernActorEdits();
        LegacyEntityEdits();
        Console.WriteLine("Entity UniqueID edits passed: collisions, unchanged storage references, legacy records, relocation and repeated saves.");
    }

    private static void ModernActorEdits()
    {
        using var db = new SelfTestWorldDatabase();
        var store = new BedrockWorldObjectNbtStore(db);
        const long reference = 0x112233445566778;
        var actorKey = ActorKey(reference);
        var digestKey = DigestKey(0, 0, 0);
        db.Put(actorKey, Encode(Entity(101)));
        db.Put(digestKey, IdBytes(reference));
        // This storage reference is allowed as an NBT UniqueID: its own NBT ID differs.
        var otherActorBytes = Encode(Entity(202, 32));
        db.Put(ActorKey(999), otherActorBytes);
        db.Put(DigestKey(2, 0, 0), IdBytes(999));
        var legacyKey = EntityKey(4, 0, 2);
        db.Put(legacyKey, Encode(Entity(303, 64, dimension: 2)));
        var current = Scan(db, 0, 0, 0, 101);
        foreach (var id in new long[] { long.MinValue, 999, 999, long.MaxValue })
        {
            var digestBefore = db.Get(digestKey)!;
            store.Save(current, Entity(id));
            current = Scan(db, 0, 0, 0, id); // The editor refreshes this snapshot after each save.
            Check(current.UniqueId == id && current.Storage.PrimaryKey.SequenceEqual(actorKey), "ID value saved under original actor key");
            Check(db.Get(digestKey)!.SequenceEqual(digestBefore), "in-place ID edits leave digp byte-for-byte identical");
            Check(db.Get(ActorKey(999))!.SequenceEqual(otherActorBytes), "NBT ID may equal an unrelated storage reference");
        }

        foreach (var duplicateId in new long[] { 202, 303 })
            RejectUnchanged(db, () => store.Save(current, Entity(duplicateId, 48, -17, 1)), "modern/legacy duplicate IDs rejected before moving");
        RejectUnchanged(db, () => store.Save(current, Entity(0)), "zero rejected");
        var validTags = ((NbtCompoundValue)current.Document.Root).Tags;
        foreach (var invalid in new[]
        {
            new NbtDocument("", new NbtCompoundValue(validTags.Where(t => t.Name != "UniqueID").ToArray())),
            new NbtDocument("", new NbtCompoundValue(validTags.Select(t => t.Name == "UniqueID" ? t with { Name = "RenamedID" } : t).ToArray())),
            new NbtDocument("", new NbtCompoundValue(validTags.Select(t => t.Name == "UniqueID" ? t with { Value = new NbtStringValue("bad") } : t).ToArray()))
        }) RejectUnchanged(db, () => store.Save(current, invalid), "removal, rename or invalid ID rejected");

        var destinationKey = DigestKey(3, -2, 1);
        var unrelatedReference = IdBytes(0x55667788);
        db.Put(destinationKey, unrelatedReference);
        var beforeBatch = db.ApplyBatchCount;
        store.Save(current, Entity(-404, 48, -17, 1));
        Check(db.ApplyBatchCount == beforeBatch + 1, "ID plus ownership move uses one batch");
        Check(db.Get(digestKey) is null && db.Get(destinationKey)!.SequenceEqual(unrelatedReference.Concat(IdBytes(reference))),
            "move relocates the original reference and preserves destination peers");
        current = Scan(db, 3, -2, 1, -404);
        Check(current.Storage.PrimaryKey.SequenceEqual(actorKey), "moving and changing ID never rename the actor key");
        store.Save(current, Entity(-405, 48, -17, 1));
        Check(Scan(db, 3, -2, 1, -405).UniqueId == -405, "next save after moving uses the refreshed identity");
    }

    private static void LegacyEntityEdits()
    {
        using var db = new SelfTestWorldDatabase();
        var store = new BedrockWorldObjectNbtStore(db);
        var sourceKey = EntityKey(0, 0, 0);
        var peer = Encode(Entity(502, 2));
        db.Put(sourceKey, Encode(Entity(501)).Concat(peer).ToArray());
        var current = Scan(db, 0, 0, 0, 501);
        RejectUnchanged(db, () => store.Save(current, Entity(502)), "legacy same-record collision rejected");
        db.Put(ActorKey(88), Encode(Entity(503))); // Orphan actor IDs are still occupied.
        RejectUnchanged(db, () => store.Save(current, Entity(503)), "legacy-to-modern collision rejected");
        store.Save(current, Entity(-504));
        var records = ConsecutiveNbtCodec.Decode(db.Get(sourceKey)!);
        Check(records.Count == 2 && records[1].RawData.SequenceEqual(peer), "legacy ID edit preserves consecutive peers");
        current = Scan(db, 0, 0, 0, -504);
        var destinationKey = EntityKey(2, -2, 2);
        var destinationPeer = Encode(Entity(505, 34, -18, 2));
        db.Put(destinationKey, destinationPeer);
        RejectUnchanged(db, () => store.Save(current, Entity(505, 33, -17, 2)), "new ID checked before appending to destination");
        var beforeBatch = db.ApplyBatchCount;
        store.Save(current, Entity(-506, 33, -17, 2));
        Check(db.ApplyBatchCount == beforeBatch + 1 && db.Get(sourceKey)!.SequenceEqual(peer), "legacy relocation is atomic and preserves source peers");
        records = ConsecutiveNbtCodec.Decode(db.Get(destinationKey)!);
        Check(records.Count == 2 && records[0].RawData.SequenceEqual(destinationPeer), "legacy destination peers preserved");
        current = Scan(db, 2, -2, 2, -506);
        Check(current.Storage is ChunkRecordStorage { RecordIndex: 1, Encoding: NbtEncoding.LittleEndian }, "refresh tracks the appended record index and encoding");
        store.Save(current, Entity(-507, 33, -17, 2));
        Check(Scan(db, 2, -2, 2, -507).UniqueId == -507, "legacy ID editable again after moving");
    }

    private static NbtDocument Entity(long id, float x = 1, float z = 1, int dimension = 0) => new("", new NbtCompoundValue([
        new("identifier", new NbtStringValue("minecraft:pig")),
        new("UniqueID", new NbtLongValue(id)),
        new("DimensionId", new NbtIntValue(dimension)),
        new("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(x), new NbtFloatValue(70), new NbtFloatValue(z)]))
    ]));

    private static byte[] Encode(NbtDocument document) => BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian);
    private static byte[] IdBytes(long id)
    {
        var bytes = new byte[8];
        BinaryPrimitives.WriteInt64LittleEndian(bytes, id);
        return bytes;
    }
    private static byte[] ActorKey(long reference) => Encoding.ASCII.GetBytes("actorprefix").Concat(IdBytes(reference)).ToArray();
    private static byte[] EntityKey(int x, int z, int dimension) => new BedrockDbKey(new ChunkPosition(x, z, dimension), ChunkRecordType.Entity, null).Encode();
    private static byte[] DigestKey(int x, int z, int dimension)
    {
        var bytes = new byte[dimension == 0 ? 12 : 16];
        Encoding.ASCII.GetBytes("digp").CopyTo(bytes, 0);
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(4), x);
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(8), z);
        if (dimension != 0) BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(12), dimension);
        return bytes;
    }
    private static BedrockWorldObject Scan(SelfTestWorldDatabase db, int x, int z, int dimension, long id)
        => new BedrockWorldObjectScanner(db).ScanRegion(x, z, dimension, 0, true, false).Objects.Single(item => item.UniqueId == id);
    private static string[] Snapshot(SelfTestWorldDatabase db)
        => db.Entries(includeValues: true).Select(e => Convert.ToHexString(e.Key) + ":" + Convert.ToHexString(e.Value!)).ToArray();
    private static void RejectUnchanged(SelfTestWorldDatabase db, Action action, string label)
    {
        var before = Snapshot(db);
        var batches = db.ApplyBatchCount;
        var rejected = false;
        try { action(); }
        catch (Exception error) when (error is InvalidOperationException or InvalidDataException) { rejected = true; }
        Check(rejected && Snapshot(db).SequenceEqual(before) && db.ApplyBatchCount == batches, label);
    }
    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException("UniqueID regression: " + message);
    }
}
