using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

internal static class SummonCommandTests
{
    private const string Position = "'List''Float'\"Pos\"=\"0,64,0\"";

    public static void Run()
    {
        var failures = new List<Exception>();
        foreach (var test in new Action[] { ExplicitAndAutomaticIds, RawNbtPreservation, RawGeneratedIdAndIdentity,
                     NumericMetadataTypes, InvalidMetadataDoesNotWrite, CollisionsDoNotWrite, LegacyStorage,
                     DanglingDigestRaw, DanglingDigestNormal, AutoSkipsDanglingReference, UnrelatedMalformedDigests, LegacyReferenceNamespaces })
        {
            try { test(); }
            catch (Exception error)
            {
                Console.Error.WriteLine($"FAIL summon {test.Method.Name}: {error.Message}");
                failures.Add(error);
            }
        }
        if (failures.Count > 0) throw new AggregateException("Summon command regressions failed.", failures);
        Console.WriteLine("Summon commands passed: exact Long IDs, Auto, raw NBT, validation, ID/reference collisions and both storage formats.");
    }

    private static void ExplicitAndAutomaticIds()
    {
        foreach (var id in new long[] { 9007199254740993, long.MinValue, long.MaxValue, -1 })
        {
            using var db = new SelfTestWorldDatabase();
            var result = Execute(db, $"summon minecraft:cow nether 10.5 64.25 -3.75 'String'\"CustomName\"=\"Hello Cow\" {id.ToString(CultureInfo.InvariantCulture)}");
            var entity = ReadActor(db, id);
            Check(result.ChangedWorld && entity.Root.CompoundValue("UniqueID") is NbtLongValue unique && unique.Value == id,
                "normal summon must persist supplied Int64 without floating conversion");
            Check(entity.Root.StringValue("CustomName") == "Hello Cow" && entity.Root.StringValue("identifier") == "minecraft:cow"
                && entity.Root.IntValue("DimensionId") == 1, "normal additions and defaults must remain");
            Check(db.ApplyBatchCount == 1 && db.Get(DigestKey(0, -1, 1))!.SequenceEqual(IdBytes(id)), "actor and correct ownership must be one batch");
        }
        using var generatedDb = new SelfTestWorldDatabase();
        Execute(generatedDb, "summon minecraft:pig overworld 0 64 0 default");
        Execute(generatedDb, "summon minecraft:pig overworld 0 64 0 default Auto");
        var generated = new BedrockWorldObjectScanner(generatedDb).ScanRegion(0, 0, 0, 0, true, false).Objects;
        Check(generated.Count == 2 && generated.All(item => item.UniqueId is not null and not 0)
            && generated.Select(item => item.UniqueId).Distinct().Count() == 2, "old syntax and Auto must allocate distinct IDs");
    }

    private static void RawNbtPreservation()
    {
        using var db = new SelfTestWorldDatabase();
        Execute(db, "summon 'String'\"identifier\"=\"minecraft:cow\",'List''Float'\"Pos\"=\"0.0,64.0,0.0\",'Long'\"UniqueID\"=\"12345678\"");
        var expected = new NbtDocument("", new NbtCompoundValue([
            new("identifier", new NbtStringValue("minecraft:cow")),
            new("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0), new NbtFloatValue(64), new NbtFloatValue(0)])),
            new("UniqueID", new NbtLongValue(12345678))
        ]));
        Check(db.Get(ActorKey(12345678))!.SequenceEqual(Encode(expected)), "raw example must preserve exactly the three tags and their order");
        Check(db.ApplyBatchCount == 1 && db.Get(DigestKey(0, 0, 0))!.SequenceEqual(IdBytes(12345678)), "absent dimension selects overworld without adding NBT");
        Execute(db, "summon 'Long'\"uNiQuEiD\"=\"9223372036854775807\",'Compound'\"Nested\"=\"{'Byte'\"Flag\"=\"1\",'LongArray'\"Exact\"=\"[-9223372036854775808,9007199254740993,9223372036854775807]\"}\",'List''Double'\"pOsItIoN\"=\"-16.25,65.125,32.5\",'Short'\"dImEnSiOn\"=\"2\"");
        expected = new NbtDocument("", new NbtCompoundValue([
            new("uNiQuEiD", new NbtLongValue(long.MaxValue)),
            new("Nested", new NbtCompoundValue([new("Flag", new NbtByteValue(1)), new("Exact", new NbtLongArrayValue([long.MinValue, 9007199254740993, long.MaxValue]))])),
            new("pOsItIoN", new NbtListValue(NbtTagType.Double, [new NbtDoubleValue(-16.25), new NbtDoubleValue(65.125), new NbtDoubleValue(32.5)])),
            new("dImEnSiOn", new NbtShortValue(2))
        ]));
        Check(db.Get(ActorKey(long.MaxValue))!.SequenceEqual(Encode(expected)), "nested values, alias spelling, numeric types and order must survive");
        Check(db.Get(DigestKey(-2, 2, 2))!.SequenceEqual(IdBytes(long.MaxValue)), "aliases must determine negative chunk and dimension");
    }

    private static void RawGeneratedIdAndIdentity()
    {
        foreach (var identity in new[] { "'Int'\"id\"=\"12\"", "'Int'\"identifier\"=\"12\"", "'List''String'\"definitions\"=\"+minecraft:cow\"" })
        {
            using var db = new SelfTestWorldDatabase();
            Execute(db, $"summon {identity},{Position}");
            var entry = db.Entries(Encoding.ASCII.GetBytes("actorprefix"), includeValues: true).Single();
            var root = (NbtCompoundValue)BedrockNbtCodec.Decode(entry.Value!, NbtEncoding.LittleEndian).Root;
            Check(root.Tags.Count == 3 && root.Tags[1].Name == "Pos" && root.Tags[2] is { Name: "UniqueID", Value: NbtLongValue { Value: not 0 } }, "only missing UniqueID may be appended");
            var id = ((NbtLongValue)root.Tags[2].Value).Value;
            Check(entry.Key.SequenceEqual(ActorKey(id)) && db.Get(DigestKey(0, 0, 0))!.SequenceEqual(IdBytes(id)), "generated ID must match storage references");
            if (identity.StartsWith("'Int'", StringComparison.Ordinal)) Check(root.Tags[0].Value is NbtIntValue { Value: 12 }, "numeric identity must remain numeric");
            else Check(root.Tags[0].Value is NbtListValue { ElementType: NbtTagType.String } definitions
                && definitions.Values.Single() is NbtStringValue { Value: "+minecraft:cow" }, "definitions-only identity must remain unchanged");
        }
    }

    private static void NumericMetadataTypes()
    {
        foreach (var type in new[] { "Byte", "Short", "Int", "Long", "Float", "Double" })
        {
            using var db = new SelfTestWorldDatabase();
            Execute(db, $"summon 'List''{type}'\"Pos\"=\"-1,64,17\",'Long'\"UniqueID\"=\"-9223372036854775808\"");
            Check(((NbtListValue)ReadActor(db, long.MinValue).Root.CompoundValue("Pos")!).ElementType.ToString() == type
                && db.Get(DigestKey(-1, 1, 0)) is not null, "numeric Pos type and ownership must remain: " + type);
        }
        foreach (var (type, dimension) in new[] { ("Byte", -1), ("Short", 2), ("Int", int.MinValue), ("Long", int.MaxValue) })
        {
            using var db = new SelfTestWorldDatabase();
            Execute(db, $"summon {Position},'{type}'\"DimensionId\"=\"{dimension}\",'Long'\"UniqueID\"=\"7\"");
            Check(db.Get(DigestKey(0, 0, dimension)) is not null, "dimension must support integer tags across Int32 range");
        }
    }

    private static void InvalidMetadataDoesNotWrite()
    {
        using var db = new SelfTestWorldDatabase();
        foreach (var id in new[] { "0", "auto", "AUTO", "1.5", "1e3", "9223372036854775808", "-9223372036854775809", "NaN" })
            RejectUnchanged(db, () => Execute(db, "summon minecraft:cow overworld 0 64 0 default " + id), "invalid normal ID " + id);
        foreach (var name in new[] { "UniqueID", "Pos", "Position", "DimensionId", "Dimension", "identifier", "id", "definitions" })
            RejectUnchanged(db, () => Execute(db, $"summon minecraft:cow overworld 0 64 0 'String'\"{name}\"=\"bad\" Auto"), "normal protected tag " + name);
        foreach (var payload in new[]
        {
            "NULL", "default", "'String'\"identifier\"=\"minecraft:cow\"", "'List''Float'\"Pos\"=\"0,64\"", "'List''Float'\"Pos\"=\"0,64,0,1\"",
            "'List''String'\"Pos\"=\"0,64,0\"", "'IntArray'\"Pos\"=\"[0,64,0]\"", "'List''Float'\"Pos\"=\"NaN,64,0\"",
            "'List''Double'\"Pos\"=\"0,Infinity,0\"", "'List''Double'\"Pos\"=\"0,64,3.5e38\"",
            Position + ",'Int'\"UniqueID\"=\"123\"", Position + ",'Double'\"UniqueID\"=\"123\"", Position + ",'String'\"UniqueID\"=\"123\"",
            Position + ",'Long'\"UniqueID\"=\"0\"", Position + ",'Long'\"UniqueID\"=\"9223372036854775808\"",
            Position + ",'String'\"DimensionId\"=\"nether\"", Position + ",'Float'\"DimensionId\"=\"1\"", Position + ",'Double'\"DimensionId\"=\"1.5\"",
            Position + ",'Long'\"DimensionId\"=\"2147483648\"", Position + ",'Long'\"Dimension\"=\"-2147483649\"",
            Position + ",'List''Float'\"pos\"=\"0,64,0\"", Position + ",'List''Int'\"Position\"=\"0,64,0\"",
            Position + ",'Long'\"UniqueID\"=\"1\",'Long'\"uniqueid\"=\"2\"", Position + ",'Int'\"DimensionId\"=\"0\",'Int'\"Dimension\"=\"1\"",
            Position + ",'Int'\"DimensionId\"=\"0\",'String'\"dimensionid\"=\"bad\"", Position + " Auto"
        }) RejectUnchanged(db, () => Execute(db, "summon " + payload), "invalid raw metadata " + payload);
    }

    private static void CollisionsDoNotWrite()
    {
        using var db = new SelfTestWorldDatabase();
        db.Put(ActorKey(202), Encode(Peer(101)));
        db.Put(DigestKey(0, 0, 0), IdBytes(202));
        foreach (var id in new[] { 101, 202 })
        {
            RejectUnchanged(db, () => Execute(db, $"summon {Position},'Long'\"UniqueID\"=\"{id}\""), "raw duplicate ID or occupied actor key");
            RejectUnchanged(db, () => Execute(db, $"summon minecraft:cow overworld 0 64 0 default {id}"), "normal duplicate ID or occupied actor key");
        }
        db.Put(DigestKey(1, 0, 0), [1]);
        RejectUnchanged(db, () => Execute(db, "summon 'List''Float'\"Pos\"=\"16,64,0\",'Long'\"UniqueID\"=\"303\""), "malformed target digest must fail without an orphan actor");
    }

    private static void LegacyStorage()
    {
        using var db = new SelfTestWorldDatabase();
        var key = EntityKey();
        var peer = Encode(Peer(401));
        db.Put(key, peer);
        Execute(db, $"summon 'Int'\"id\"=\"11\",{Position},'Long'\"UniqueID\"=\"402\"");
        Execute(db, "summon minecraft:pig overworld 1 64 1 default 403");
        var records = ConsecutiveNbtCodec.Decode(db.Get(key)!);
        Check(records.Count == 3 && records[0].RawData.SequenceEqual(peer), "legacy consecutive peer must remain exact");
        Check(records[1].Document.Root is NbtCompoundValue raw && raw.Tags.Count == 3 && raw.Tags[0].Value is NbtIntValue { Value: 11 }, "raw legacy identity must remain numeric without defaults");
        Check(records[2].Document.Root.CompoundValue("UniqueID") is NbtLongValue { Value: 403 }
            && !db.Entries(Encoding.ASCII.GetBytes("actorprefix")).Any(), "normal explicit ID must use legacy storage");
        RejectUnchanged(db, () => Execute(db, $"summon {Position},'Long'\"UniqueID\"=\"401\""), "legacy duplicate ID must not append");
    }

    private static void DanglingDigestRaw() => RejectDanglingDigest("summon 'String'\"identifier\"=\"minecraft:cow\",'List''Float'\"Pos\"=\"32,64,0\",'Long'\"UniqueID\"=\"4242\"");
    private static void DanglingDigestNormal() => RejectDanglingDigest("summon minecraft:cow overworld 32 64 0 default 4242");
    private static void RejectDanglingDigest(string command)
    {
        foreach (var trailingFragment in new[] { false, true })
        {
            using var db = new SelfTestWorldDatabase();
            var digest = trailingFragment ? IdBytes(4242).Concat(new byte[] { 1 }).ToArray() : IdBytes(4242);
            db.Put(DigestKey(0, 0, 1), digest);
            RejectUnchanged(db, () => Execute(db, command), $"dangling digp in another dimension reserves its actor reference (trailing fragment: {trailingFragment})");
        }
    }

    private static void AutoSkipsDanglingReference()
    {
        foreach (var trailingFragment in new[] { false, true })
        {
            using var db = new FirstCandidateDigestDatabase(trailingFragment);
            var chosen = new BedrockWorldObjectNbtStore(db).SuggestedUniqueId();
            Check(db.FirstCandidate.HasValue && chosen != db.FirstCandidate && chosen != 0,
                $"Auto must retry when its first candidate has a dangling digest reference (trailing fragment: {trailingFragment})");
        }
    }

    private static void UnrelatedMalformedDigests()
    {
        using var db = new SelfTestWorldDatabase();
        var malformedKey = DigestKey(9, 9, 1);
        var malformed = IdBytes(4241).Concat(new byte[] { 1 }).ToArray();
        var invalidKey = Encoding.ASCII.GetBytes("digp-invalid-length");
        db.Put(malformedKey, malformed);
        db.Put(invalidKey, IdBytes(4242));
        Execute(db, $"summon {Position},'Long'\"UniqueID\"=\"4242\"");
        Check(db.Get(malformedKey)!.SequenceEqual(malformed) && db.Get(invalidKey)!.SequenceEqual(IdBytes(4242)),
            "unrelated malformed digests must remain untouched without blocking an unrelated ID");
    }

    private static void LegacyReferenceNamespaces()
    {
        foreach (var command in new[] { $"summon {Position},'Long'\"UniqueID\"=\"4242\"", "summon minecraft:cow overworld 0 64 0 default 4242" })
        {
            using var db = new SelfTestWorldDatabase();
            db.Put(EntityKey(), Encode(Peer(401)));
            var actor = Encode(Peer(4243));
            var digest = IdBytes(4242).Concat(IdBytes(4244)).ToArray();
            db.Put(ActorKey(4242), actor);
            db.Put(DigestKey(9, 9, 1), digest);
            Execute(db, command);
            Check(ConsecutiveNbtCodec.Decode(db.Get(EntityKey())!).Count == 2 && db.Get(ActorKey(4242))!.SequenceEqual(actor)
                && db.Get(DigestKey(9, 9, 1))!.SequenceEqual(digest), "legacy explicit NBT IDs must not be restricted by the separate modern storage reference namespace");
        }
    }

    // Bind a valid, occupied digest to the first randomly chosen candidate. This
    // database boundary fixture makes the retry deterministic without changing
    // production randomness or asserting on calls instead of the returned ID.
    private sealed class FirstCandidateDigestDatabase(bool trailingFragment = false) : IWorldDatabase
    {
        public long? FirstCandidate { get; private set; }
        public byte[]? Get(ReadOnlySpan<byte> key)
        {
            if (key.Length == 19 && key[..11].SequenceEqual("actorprefix"u8))
                FirstCandidate ??= BinaryPrimitives.ReadInt64LittleEndian(key[11..]);
            return null;
        }
        public IEnumerable<WorldDatabaseEntry> Entries(ReadOnlyMemory<byte>? prefix = null, bool includeValues = false, int limit = 0)
        {
            var key = DigestKey(0, 0, 1);
            if (FirstCandidate is not long id || (prefix.HasValue && !key.AsSpan().StartsWith(prefix.Value.Span))) return [];
            var digest = trailingFragment ? IdBytes(id).Concat(new byte[] { 1 }).ToArray() : IdBytes(id);
            return [new WorldDatabaseEntry(key, includeValues ? digest : null)];
        }
        public void Put(ReadOnlySpan<byte> key, ReadOnlySpan<byte> value, bool sync = true) => throw new InvalidOperationException("ID generation must not write");
        public void Delete(ReadOnlySpan<byte> key, bool sync = true) => throw new InvalidOperationException("ID generation must not delete");
        public void ApplyBatch(IEnumerable<WorldDatabasePut> puts, IEnumerable<byte[]> deletes, bool sync = true) => throw new InvalidOperationException("ID generation must not write batches");
        public void Dispose() { }
    }

    private static TargetingCommandExecutionResult Execute(SelfTestWorldDatabase db, string text)
    {
        var store = new EntityActionCommandStore(db);
        return EntityActionCommandParser.Parse(text) switch
        {
            SummonEntityActionCommandRequest request => store.Summon(request),
            SummonNbtEntityActionCommandRequest request => store.Summon(request),
            _ => throw new InvalidOperationException("Expected summon")
        };
    }
    private static NbtDocument Peer(long id) => new("peer", new NbtCompoundValue([
        new("id", new NbtIntValue(12)), new("UniqueID", new NbtLongValue(id)),
        new("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0), new NbtFloatValue(64), new NbtFloatValue(0)]))
    ]));
    private static byte[] EntityKey() => new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.Entity, null).Encode();
    private static NbtDocument ReadActor(SelfTestWorldDatabase db, long id) => BedrockNbtCodec.Decode(db.Get(ActorKey(id)) ?? throw new InvalidOperationException("Actor missing for exact ID " + id), NbtEncoding.LittleEndian);
    private static byte[] Encode(NbtDocument document) => BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian);
    private static byte[] IdBytes(long id) { var bytes = new byte[8]; BinaryPrimitives.WriteInt64LittleEndian(bytes, id); return bytes; }
    private static byte[] ActorKey(long id) => Encoding.ASCII.GetBytes("actorprefix").Concat(IdBytes(id)).ToArray();
    private static byte[] DigestKey(int x, int z, int dimension)
    {
        var bytes = new byte[dimension == 0 ? 12 : 16];
        Encoding.ASCII.GetBytes("digp").CopyTo(bytes, 0);
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(4), x);
        BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(8), z);
        if (dimension != 0) BinaryPrimitives.WriteInt32LittleEndian(bytes.AsSpan(12), dimension);
        return bytes;
    }
    private static void RejectUnchanged(SelfTestWorldDatabase db, Action action, string label)
    {
        string[] Snapshot() => db.Entries(includeValues: true).Select(e => Convert.ToHexString(e.Key) + ":" + Convert.ToHexString(e.Value!)).ToArray();
        var before = Snapshot(); var batches = db.ApplyBatchCount; var rejected = false;
        try { action(); } catch (Exception error) when (error is InvalidOperationException or InvalidDataException) { rejected = true; }
        Check(rejected && before.SequenceEqual(Snapshot()) && db.ApplyBatchCount == batches, label);
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException("Summon regression: " + message); }
}
