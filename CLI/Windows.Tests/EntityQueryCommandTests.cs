using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Cli.Tests;

internal static class EntityQueryCommandTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("CLI entity query regression: " + message);
    }

    public static void RunParserTests()
    {
        foreach (var text in new[]
        {
            "entity", "entity overworld", "entity nether", "entity the_end", " EnTiTy\tthe_end ",
            "entity overworld 9.25 80.5 -1 -12.75 -64 8.5",
            "entity nether -1e3 1.5 0 2.5 3.5 1e2",
            "entity overworld -3e20 -3e20 -3e20 3e20 3e20 3e20"
        })
        {
            object? request = null;
            try { request = CliCommandParser.Parse(text); }
            catch (InvalidDataException) { }
            Check(request is not null, "valid entity command was rejected: " + text);
            Check(!CliCommandPolicy.MayMutate(request!), "entity queries must never require an export or write handle: " + text);
            CliCommandPolicy.RequireExecutable(request!);
        }

        foreach (var text in new[]
        {
            "entity moon", "entity 2147483648", "entity ALL", "entity overworld 0", "entity overworld 0 1 2",
            "entity overworld 0 1 2 3 4", "entity overworld 0 1 2 3 4 5 6", "entity 0 1 2 3 4 5",
            "entity overworld NaN 0 0 1 1 1", "entity overworld 0 Infinity 0 1 1 1",
            "entity overworld 0 0 -Infinity 1 1 1", "entity overworld 0 0 0 1e300 1 1",
            "entity overworld 0 0 0 1 3.5e38 1", "entity overworld 0 0 0 1 1 Auto"
        })
        {
            var rejected = false;
            try { _ = CliCommandParser.Parse(text); }
            catch (InvalidDataException) { rejected = true; }
            Check(rejected, "invalid entity command was accepted: " + text);
        }

        using var errors = new StringWriter();
        var plan = CliCommandPlan.Parse([
            new CliCommandLine(1, "entity"), new CliCommandLine(2, "entity nether"),
            new CliCommandLine(3, "entity the_end -1.5 63 0 2.5 64 0")
        ], errors, forExecution: true);
        Check(plan is { MayMutate: false } && plan.Commands.Count == 3, "query batches must be executable without output files: " + errors);
        Console.WriteLine("CLI entity parser and read-only policy regressions passed.");
    }

    public static void RunNativeTests(string root, string fixtureTool)
    {
        var source = WorldFixture.Create(Path.Combine(root, "entity-query"), fixtureTool);
        var world = new WorldDocument(source);
        var rich = Entity("identifier", new NbtStringValue("minecraft:pig"), 1, -1.25, 64.5, 2.75, [
            new("UniqueID", new NbtLongValue(9007199254740993)),
            new("Health", new NbtFloatValue(7.25f)),
            new("Nested", new NbtCompoundValue([
                new("name", new NbtStringValue("line one\nline two,\"quote\"\\tail")),
                new("strings", new NbtListValue(NbtTagType.String, [new NbtStringValue("first\nsecond,comma\r\ntab\t\"quote\"\\end")])),
                new("bytes", new NbtByteArrayValue([0, 128, 255])),
                new("ints", new NbtIntArrayValue([int.MinValue, 0, int.MaxValue])),
                new("longs", new NbtLongArrayValue([long.MinValue, 9007199254740993, long.MaxValue])),
                new("list", new NbtListValue(NbtTagType.Compound, [new NbtCompoundValue([
                    new("exact", new NbtLongValue(long.MaxValue)),
                    new("inner", new NbtListValue(NbtTagType.List, [new NbtListValue(NbtTagType.Int, [new NbtIntValue(-17)])]))
                ])]))
            ]))
        ]);
        using (var database = world.OpenDatabase(readOnly: false))
        {
            AddModern(database, 1, 0, rich);
            AddModern(database, 2, 2, Entity("definitions", new NbtListValue(NbtTagType.String, [new NbtStringValue("+minecraft:chicken")]), 2, 0, 70, 0));
            AddModern(database, 3, 7, new NbtDocument("", new NbtCompoundValue([
                new("identifier", new NbtStringValue("custom:unlocated"))
            ])));
            SeedLegacy(database, 0,
                Entity("id", new NbtStringValue("minecraft:cow"), 0, -2.5, 64.5, 2.75),
                Entity("id", new NbtIntValue(12), 0, -1.25, 64.5, 2.75),
                Entity("id", new NbtStringValue("12"), 0, -1.25, 64.5, 2.75),
                Entity("identifier", new NbtStringValue("custom:above"), 0, -1.25, 64.75, 2.75),
                Entity("identifier", new NbtStringValue("custom:left"), 0, -2.5001, 64.5, 2.75),
                Entity("identifier", new NbtStringValue("custom:back"), 0, -1.25, 64.5, 2.7501));
            database.Put(new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.BlockEntity, null).Encode(),
                BedrockNbtCodec.Encode(Entity("id", new NbtStringValue("Chest"), 0, 0, 64, 0), NbtEncoding.LittleEndian));
        }

        var before = SnapshotRecords(world);
        CliCommandResult Execute(string text) => new CliWorldCommandExecutor(world).Execute(CliCommandParser.Parse(text));
        var all = Execute("entity");
        Check(!all.ChangedWorld && all.Lines.Count == 9, "all-dimension entity query must retain every ordinary entity record");
        Check(all.Lines.All(line => line.Kind == CliOutputKind.Entity && !line.Text.Contains('\n')), "each entity must be exactly one Entity-style output line");
        Check(all.Lines.Any(line => line.Text == "custom:unlocated=['String'\"identifier\"=\"custom:unlocated\"]"),
            "no-argument queries must include custom dimensions and entities without Pos without inventing fields");
        Check(all.Lines.Any(line => line.Text.StartsWith("minecraft:chicken=[", StringComparison.Ordinal)), "definitions-only types must match the entity browser");
        Check(!all.Lines.Any(line => line.Text.Contains("PlayerName", StringComparison.Ordinal) || line.Text.StartsWith("Chest=", StringComparison.Ordinal)),
            "entity query included player or block-entity records");

        var nether = Execute("entity nether");
        Check(nether.Lines.Count == 1 && nether.Lines[0].Text.StartsWith("minecraft:pig=[", StringComparison.Ordinal),
            "dimension selection must use resolved NBT DimensionId even when digp records a different dimension");
        var output = nether.Lines[0].Text;
        Check(output.Contains("'Long'\"UniqueID\"=\"9007199254740993\"", StringComparison.Ordinal)
              && output.Contains("'LongArray'\"longs\"=\"[-9223372036854775808,9007199254740993,9223372036854775807]\"", StringComparison.Ordinal),
            "entity output lost exact Int64 or array values");
        var payload = output[(output.IndexOf("=[", StringComparison.Ordinal) + 2)..^1];
        var parsed = new NbtDocument("", new NbtCompoundValue(BlockCommandParser.ParseStates(payload)));
        Check(BedrockNbtCodec.Encode(parsed, NbtEncoding.LittleEndian).SequenceEqual(BedrockNbtCodec.Encode(rich, NbtEncoding.LittleEndian)),
            "all original named tags, types, nested data and order must survive the getblock-compatible NBT output");

        var bounded = Execute("entity overworld -1.25 64.5 2.75 -2.5 64.5 2.75");
        Check(bounded.Lines.Count == 3 && bounded.Lines.Count(line => line.Text.StartsWith("minecraft:pig=[", StringComparison.Ordinal)) == 2
              && bounded.Lines.Count(line => line.Text.StartsWith("minecraft:cow=[", StringComparison.Ordinal)) == 1,
            "reversed bounds must include all equal-face positions and exclude outside X, Y and Z using actual floating Pos");
        Check(Execute("entity overworld -2.5 64.5 2.75 -1.25 64.5 2.75").Lines.Select(line => line.Text)
                .SequenceEqual(bounded.Lines.Select(line => line.Text)), "normal and reversed corners must select the same records");
        var point = Execute("entity nether -1.25 64.5 2.75 -1.25 64.5 2.75");
        Check(point.Lines.Count == 1 && point.Lines[0].Text == output, "all six inclusive bound faces must accept exact floating positions");
        var empty = Execute("entity overworld 0 0 0 0 0 0");
        Check(!empty.ChangedWorld && empty.Lines.Single().Text == "entity：没有匹配的实体。", "empty queries must report no matches");

        using (var database = world.OpenDatabase(readOnly: false))
            database.Put(new BedrockDbKey(new ChunkPosition(9, 9, 0), ChunkRecordType.Entity, null).Encode(), [255, 1, 2]);
        var diagnosed = Execute("entity");
        Check(diagnosed.Lines.Count == 10 && diagnosed.Lines.Any(line => line.Text.StartsWith("entity 扫描提示：", StringComparison.Ordinal)),
            "malformed entity record diagnostics must remain visible alongside valid entities");
        Check(diagnosed.Lines.All(line => line.Kind == CliOutputKind.Entity), "diagnostics must use the existing Entity output style");
        var after = SnapshotRecords(world);
        Check(before.All(pair => after.TryGetValue(pair.Key, out var bytes) && bytes == pair.Value) && after.Count == before.Count + 1,
            "query execution mutated or removed world data");

        var cache = Path.Combine(root, "entity-query-cache");
        using var console = new StringWriter();
        using var errors = new StringWriter();
        var original = WorldFixture.Snapshot(source);
        var exit = MCBEEditor.Cli.Program.Run(["--world", source, "--cache-dir", cache, "--command", "entity nether"], console, errors);
        Check(exit == 0 && console.ToString().Contains(output, StringComparison.Ordinal), "CLI query must execute without --output: " + errors);
        Check(WorldFixture.SameSnapshot(original, WorldFixture.Snapshot(source)), "CLI entity query changed source-world bytes");
        Check(Directory.GetDirectories(cache).Length == 0, "successful entity query leaked a working copy");
        Console.WriteLine("CLI entity native queries: all dimensions, exact bounds, identifier variants, full NBT, diagnostics and read-only execution passed.");
    }

    private static NbtDocument Entity(string identityName, NbtValue identity, int dimension, double x, double y, double z,
        IReadOnlyList<NbtNamedTag>? additions = null)
        => new("", new NbtCompoundValue(new NbtNamedTag[] {
            new(identityName, identity), new("DimensionId", new NbtIntValue(dimension)),
            new("Pos", new NbtListValue(NbtTagType.Double, [new NbtDoubleValue(x), new NbtDoubleValue(y), new NbtDoubleValue(z)]))
        }.Concat(additions ?? []).ToArray()));

    private static void SeedLegacy(IWorldDatabase database, int dimension, params NbtDocument[] documents)
        => database.Put(new BedrockDbKey(new ChunkPosition(0, 0, dimension), ChunkRecordType.Entity, null).Encode(),
            documents.SelectMany(document => BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian)).ToArray());

    private static void AddModern(IWorldDatabase database, long reference, int digestDimension, NbtDocument document)
    {
        var referenceBytes = new byte[8];
        BinaryPrimitives.WriteInt64LittleEndian(referenceBytes, reference);
        var digest = new byte[digestDimension == 0 ? 12 : 16];
        Encoding.ASCII.GetBytes("digp").CopyTo(digest, 0);
        if (digestDimension != 0) BinaryPrimitives.WriteInt32LittleEndian(digest.AsSpan(12), digestDimension);
        database.Put(digest, (database.Get(digest) ?? []).Concat(referenceBytes).ToArray());
        database.Put(Encoding.ASCII.GetBytes("actorprefix").Concat(referenceBytes).ToArray(), BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian));
    }

    private static IReadOnlyDictionary<string, string> SnapshotRecords(WorldDocument world)
    {
        using var database = world.OpenDatabase(readOnly: true);
        return database.Entries(includeValues: true).ToDictionary(entry => Convert.ToHexString(entry.Key), entry => Convert.ToHexString(entry.Value!));
    }
}
