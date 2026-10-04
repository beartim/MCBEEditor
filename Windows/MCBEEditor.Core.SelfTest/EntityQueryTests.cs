using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;

internal static class EntityQueryTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("Entity query regression: " + message);
    }

    public static void Run()
    {
        DefinitionsOnlyIdentifier();
        DistinctLegacyRecordsWithRepeatedUniqueIds();
        QueryDoesNotUseBrowserResultLimit();
        Console.WriteLine("Entity query regressions: identifier fallback, per-record identity and more than 200,000 entities passed.");
    }

    private static void DefinitionsOnlyIdentifier()
    {
        using var database = new SelfTestWorldDatabase();
        var document = new NbtDocument("", new NbtCompoundValue([
            new("definitions", new NbtListValue(NbtTagType.String, [new NbtStringValue("+minecraft:cow")]))
        ]));
        SeedLegacy(database, 0, 0, document);
        var item = new BedrockWorldObjectScanner(database).ScanAll(null, true, false, int.MaxValue).Objects.Single();
        Check(item.Identifier == "minecraft:cow", "definitions-only entities must resolve the same type as other identifier forms");
    }

    private static void DistinctLegacyRecordsWithRepeatedUniqueIds()
    {
        using var database = new SelfTestWorldDatabase();
        NbtDocument Entity(string marker) => new("", new NbtCompoundValue([
            new("id", new NbtStringValue("minecraft:pig")),
            new("UniqueID", new NbtLongValue(42)),
            new("marker", new NbtStringValue(marker))
        ]));
        SeedLegacy(database, 0, 0, Entity("first"), Entity("second"));
        SeedLegacy(database, 0, 1, Entity("third"));
        var items = new BedrockWorldObjectScanner(database).ScanAll(null, true, false, int.MaxValue).Objects;
        Check(items.Count == 3, "repeated UniqueID values must not collapse distinct legacy records");
        Check(items.Select(item => item.Document.Root.StringValue("marker")).Order().SequenceEqual(new[] { "first", "second", "third" }),
            "all source records must remain visible");
    }

    private static void SeedLegacy(SelfTestWorldDatabase database, int dimension, int chunkX, params NbtDocument[] documents)
        => database.Put(new BedrockDbKey(new ChunkPosition(chunkX, 0, dimension), ChunkRecordType.Entity, null).Encode(),
            documents.SelectMany(document => BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian)).ToArray());

    private static void QueryDoesNotUseBrowserResultLimit()
    {
        using var database = new SelfTestWorldDatabase();
        var document = new NbtDocument("", new NbtCompoundValue([]));
        var bytes = BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian);
        const int recordCount = 200_001;
        var data = new byte[bytes.Length * recordCount];
        for (var index = 0; index < recordCount; index++) bytes.CopyTo(data, index * bytes.Length);
        var key = new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.Entity, null).Encode();
        database.Put(key, data);

        var result = new EntityQueryCommandStore(database).Execute(EntityQueryCommandParser.Parse("entity"));
        Check(!result.ChangedWorld && result.OutputLines.Count == recordCount,
            "queries must include every entity beyond the browser's 200,000-object default limit");
        Check(result.OutputLines.All(line => line.Style == TargetingOutputStyle.Entity && line.Text == "未知实体=[]"),
            "empty entity compounds must remain empty with one output per source record");
        Check(database.ApplyBatchCount == 0 && database.Get(key)!.SequenceEqual(data), "querying a large world must preserve stored NBT");
    }
}
