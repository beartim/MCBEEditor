using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Cli.Tests;

internal static class SummonCommandTests
{
    private const string RawExample = "summon 'String'\"identifier\"=\"minecraft:cow\",'List''Float'\"Pos\"=\"0.0,64.0,0.0\",'Long'\"UniqueID\"=\"12345678\"";
    public static void RunParserTests()
    {
        foreach (var command in new[] { RawExample, "summon minecraft:pig overworld 0 64 0 default",
                     "summon minecraft:pig overworld 0 64 0 default Auto", "summon minecraft:pig overworld 0 64 0 default -9223372036854775808" })
        {
            var request = CliCommandParser.Parse(command);
            Check(CliCommandPolicy.MayMutate(request), "both forms must require a writable world and output destination");
            CliCommandPolicy.RequireExecutable(request);
        }
        using var errors = new StringWriter();
        var plan = CliCommandPlan.Parse([new CliCommandLine(1, RawExample)], errors, forExecution: true);
        Check(plan is { MayMutate: true } && plan.Commands.Count == 1, "raw summon must pass preflight as a mutation: " + errors);
        Console.WriteLine("CLI summon parsing and mutation policy passed.");
    }

    public static void RunNativeTests(string root, string fixtureTool)
    {
        var source = WorldFixture.Create(Path.Combine(root, "summon-source"), fixtureTool);
        var original = WorldFixture.Snapshot(source);
        var cache = Path.Combine(root, "summon-cache");
        var archive = Path.Combine(root, "summoned.mcworld");
        using (var output = new StringWriter())
        using (var error = new StringWriter())
        {
            var exit = MCBEEditor.Cli.Program.Run(["--world", source, "--cache-dir", cache, "--command", RawExample], output, error);
            Check(exit == 2 && !Directory.Exists(cache), "missing output must fail before creating a work copy");
        }
        using (var output = new StringWriter())
        using (var error = new StringWriter())
        {
            var exit = MCBEEditor.Cli.Program.Run([
                "--world", source, "--cache-dir", cache, "--output", archive, "--command", RawExample,
                "--command", "summon minecraft:pig overworld 1 64 1 default -9223372036854775808",
                "--command", "summon minecraft:pig overworld 2 64 2 default 9223372036854775807",
                "--command", "summon minecraft:pig overworld 3 64 3 default 9007199254740993",
                "--command", "summon 'List''String'\"definitions\"=\"+minecraft:chicken\",'List''Double'\"Pos\"=\"4.25,64.5,4.75\"",
                "--command", "summon minecraft:pig overworld 5 64 5 default Auto",
                "--command", "summon minecraft:pig overworld 6 64 6 default"
            ], output, error);
            Check(exit == 0, "native CLI must dispatch and export both summon forms: " + error);
        }
        Check(WorldFixture.SameSnapshot(original, WorldFixture.Snapshot(source)), "summon changed source-world files");
        using (var verification = PortableWorldWorkspace.Create(Path.Combine(root, "summon-verify"), archive))
        {
            var world = new WorldDocument(verification.WorkingRootPath);
            using (var db = world.OpenDatabase(readOnly: true))
            {
                var expected = Encode(new NbtDocument("", new NbtCompoundValue([
                    new("identifier", new NbtStringValue("minecraft:cow")),
                    new("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0), new NbtFloatValue(64), new NbtFloatValue(0)])),
                    new("UniqueID", new NbtLongValue(12345678))
                ])));
                Check(db.Get(ActorKey(12345678))!.SequenceEqual(expected), "raw example must survive export/reopen byte-for-byte");
                var entities = new BedrockWorldObjectScanner(db).ScanRegion(0, 0, 0, 0, true, false).Objects;
                Check(entities.Count == 7 && entities.All(item => item.UniqueId is not null and not 0)
                    && entities.Select(item => item.UniqueId).Distinct().Count() == 7, "all seven summons need distinct nonzero IDs");
                foreach (var id in new long[] { long.MinValue, long.MaxValue, 9007199254740993 })
                    Check(entities.Single(item => item.UniqueId == id).Document.Root.CompoundValue("UniqueID") is NbtLongValue exact && exact.Value == id, "Long ID exactness after export");
                var definitions = (NbtCompoundValue)entities.Single(item => item.Identifier == "minecraft:chicken").Document.Root;
                Check(definitions.Tags.Select(tag => tag.Name).SequenceEqual(new[] { "definitions", "Pos", "UniqueID" })
                    && definitions.Tags[1].Value is NbtListValue { ElementType: NbtTagType.Double }, "raw definitions must retain original fields and Pos type");
            }
            foreach (var command in new[] { RawExample, "summon minecraft:pig overworld 0 64 0 default 9007199254740993" })
                RejectUnchanged(world, command, "duplicate ID must not write native records");
            using (var db = world.OpenDatabase(readOnly: false))
            {
                db.Put(ActorKey(777), Encode(new NbtDocument("", new NbtCompoundValue([new("UniqueID", new NbtLongValue(778))]))));
                db.Put(BedrockChunkStore.ActorDigestKeys(new ChunkPosition(0, 0, 1))[0], IdBytes(4242));
            }
            RejectUnchanged(world, "summon 'List''Float'\"Pos\"=\"0,64,0\",'Long'\"UniqueID\"=\"777\"", "occupied actor reference with another NBT ID must not write");
            foreach (var trailingFragment in new[] { false, true })
            {
                using (var db = world.OpenDatabase(readOnly: false))
                    db.Put(BedrockChunkStore.ActorDigestKeys(new ChunkPosition(0, 0, 1))[0],
                        trailingFragment ? IdBytes(4242).Concat(new byte[] { 1 }).ToArray() : IdBytes(4242));
                foreach (var command in new[] {
                    "summon 'String'\"identifier\"=\"minecraft:cow\",'List''Float'\"Pos\"=\"32,64,0\",'Long'\"UniqueID\"=\"4242\"",
                    "summon minecraft:cow overworld 32 64 0 default 4242"
                }) RejectUnchanged(world, command, "dangling digest in another dimension must reject normal/raw creation without writes");
            }
        }

        var legacy = new WorldDocument(WorldFixture.Create(Path.Combine(root, "summon-legacy"), fixtureTool));
        var legacyKey = new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.Entity, null).Encode();
        var peer = Encode(new NbtDocument("peer", new NbtCompoundValue([
            new("id", new NbtIntValue(12)), new("UniqueID", new NbtLongValue(501)),
            new("Pos", new NbtListValue(NbtTagType.Float, [new NbtFloatValue(0), new NbtFloatValue(64), new NbtFloatValue(0)]))
        ])));
        using (var db = legacy.OpenDatabase(readOnly: false)) db.Put(legacyKey, peer);
        var executor = new CliWorldCommandExecutor(legacy);
        Check(executor.Execute(CliCommandParser.Parse("summon 'Int'\"id\"=\"11\",'List''Float'\"Pos\"=\"0,64,0\",'Long'\"UniqueID\"=\"502\"")).ChangedWorld, "legacy raw persistence");
        executor.Execute(CliCommandParser.Parse("summon minecraft:pig overworld 1 64 1 default 503"));
        using (var db = legacy.OpenDatabase(readOnly: true))
        {
            var records = ConsecutiveNbtCodec.Decode(db.Get(legacyKey)!);
            Check(records.Count == 3 && records[0].RawData.SequenceEqual(peer), "legacy consecutive peer must remain exact");
            Check(records[1].Document.Root is NbtCompoundValue raw && raw.Tags.Count == 3 && raw.Tags[0].Value is NbtIntValue { Value: 11 }
                && !db.Entries(Encoding.ASCII.GetBytes("actorprefix")).Any(), "native legacy raw identity and storage must remain unchanged");
        }
        RejectUnchanged(legacy, "summon 'List''Float'\"Pos\"=\"0,64,0\",'Long'\"UniqueID\"=\"501\"", "legacy duplicate ID must not append");
        Console.WriteLine("CLI summon native tests passed: dispatch, export/reopen, exact Long IDs, source integrity, legacy storage and atomic ID/reference rejection.");
    }
    private static byte[] Encode(NbtDocument document) => BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian);
    private static byte[] IdBytes(long id) { var bytes = new byte[8]; BinaryPrimitives.WriteInt64LittleEndian(bytes, id); return bytes; }
    private static byte[] ActorKey(long id) => Encoding.ASCII.GetBytes("actorprefix").Concat(IdBytes(id)).ToArray();
    private static string[] Snapshot(WorldDocument world)
    {
        using var db = world.OpenDatabase(readOnly: true);
        return db.Entries(includeValues: true).Select(entry => Convert.ToHexString(entry.Key) + ":" + Convert.ToHexString(entry.Value!)).ToArray();
    }
    private static void RejectUnchanged(WorldDocument world, string command, string label)
    {
        var before = Snapshot(world); var rejected = false;
        try { new CliWorldCommandExecutor(world).Execute(CliCommandParser.Parse(command)); }
        catch (Exception error) when (error is InvalidDataException or InvalidOperationException) { rejected = true; }
        Check(rejected && Snapshot(world).SequenceEqual(before), label);
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException("CLI summon regression: " + message); }
}
