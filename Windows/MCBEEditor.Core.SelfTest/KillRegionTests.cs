using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;

internal static class KillRegionTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("kill region regression: " + message);
    }

    public static void Run()
    {
        ParserContract();
        foreach (var flag in new[] { 0, 1 })
        foreach (var corners in new[] { "0 0 0 1 1 1", "1 1 1 0 0 0" })
            RegionSelection(flag, corners);
        RegionSelection(0, "0 0 0 1 1 1", omitFlag: true);
        MixedActorRecords();
        EmptySelectionPreservesData();
        LegacySelectors();
        Console.WriteLine("kill region: parsing, boundaries, dimensions, all player modes, duplicate IDs, legacy/modern deletion and old selectors passed.");
    }

    private static void ParserContract()
    {
        foreach (var command in new[] {
            "kill overworld 0 0 0 1 1 1 1", "KiLl MiNeCrAfT:OvErWoRlD 1 1 1 0 0 0 0",
            "kill nether -1.5 -2.25 -3 0.5 2 3 0", "kill the_end 0 0 0 0 0 0 1",
            "kill -7 0 0 0 1 1 1 0", "kill @s 0", "kill @a 1", "kill @e 0", "kill minecraft:pig 1", "kill 42 0" })
            Check(EntityActionCommandParser.Parse(command) is KillEntityActionCommandRequest, command);
        Check(EntityActionCommandParser.Parse("kill custom:moon 0 0 0 1 1 1 1", name => name == "custom:moon" ? 42 : throw new InvalidDataException())
            is KillEntityActionCommandRequest, "custom dimension resolver");
        foreach (var command in new[] {
            "kill overworld 0 0 0 1 1 1 2", "kill overworld 0 0 0 1 1 1 true",
            "kill overworld NaN 0 0 1 1 1 1", "kill overworld 0 inf 0 1 1 1 0", "kill overworld 0 0 0 1 1 1e40 1",
            "kill 2147483648 0 0 0 1 1 1 0", "kill overworld 0 0 0 1 1 1 1 extra", "kill @e 2" })
        {
            var rejected = false;
            try { EntityActionCommandParser.Parse(command); } catch (InvalidDataException) { rejected = true; }
            Check(rejected, "accepted invalid command: " + command);
        }
    }

    private static NbtDocument Document(string marker, long id, int dimension, double x, double y, double z,
        int? mode = null, bool hasPosition = true)
    {
        var tags = new List<NbtNamedTag> {
            new("marker", new NbtStringValue(marker)), new("UniqueID", new NbtLongValue(id)),
            new("DimensionId", new NbtIntValue(dimension)) };
        if (hasPosition) tags.Add(new("Pos", new NbtListValue(NbtTagType.Double,
            [new NbtDoubleValue(x), new NbtDoubleValue(y), new NbtDoubleValue(z)])));
        if (mode.HasValue)
        {
            tags.Add(new("PlayerGameMode", new NbtIntValue(mode.Value)));
            tags.Add(new("Attributes", new NbtListValue(NbtTagType.Compound, [new NbtCompoundValue([
                new("Name", new NbtStringValue("minecraft:health")), new("Current", new NbtFloatValue(20)),
                new("Max", new NbtFloatValue(20)) ])])));
            tags.Add(new("PlayerLevel", new NbtIntValue(7)));
        }
        else tags.Add(new("identifier", new NbtStringValue("minecraft:pig")));
        return new NbtDocument("", new NbtCompoundValue(tags));
    }

    private static byte[] Key(string text) => Encoding.UTF8.GetBytes(text);
    private static byte[] Bytes(NbtDocument document) => BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian);
    private static byte[] LegacyKey(int dimension) => new BedrockDbKey(new ChunkPosition(0, 0, dimension), ChunkRecordType.Entity, null).Encode();
    private static void PutLegacy(SelfTestWorldDatabase database, int dimension, params NbtDocument[] documents)
        => database.Put(LegacyKey(dimension), documents.SelectMany(Bytes).ToArray());

    private static void RegionSelection(int flag, string corners, bool omitFlag = false)
    {
        using var database = new SelfTestWorldDatabase();
        PutLegacy(database, 0,
            Document("lower", 101, 0, 0, 0, 0), Document("upper", 102, 0, 1, 1, 1),
            Document("middle", 103, 0, .5, .5, .5), Document("duplicate", 103, 0, .75, .75, .75),
            Document("outsideX", 103, 0, 1.0001, .5, .5), Document("outsideY", 105, 0, .5, -.0001, .5),
            Document("outsideZ", 106, 0, .5, .5, 1.0001), Document("noPos", 107, 0, 0, 0, 0, hasPosition: false));
        PutLegacy(database, 1, Document("otherDimension", 201, 1, .5, .5, .5));
        var otherDimensionBefore = database.Get(LegacyKey(1))!;
        var retainedLegacy = database.Get(LegacyKey(0))!;
        var expectedLegacy = ConsecutiveNbtCodec.Decode(retainedLegacy).Skip(4).SelectMany(item => item.RawData).ToArray();

        var actorRef = new byte[8]; BinaryPrimitives.WriteInt64LittleEndian(actorRef, 501);
        var actorKey = Key("actorprefix").Concat(actorRef).ToArray();
        var digestKey = Key("digp").Concat(new byte[8]).Concat(new byte[] { 1, 0, 0, 0 }).ToArray();
        // Owning digp says nether, but actual NBT dimension is overworld.
        database.Put(actorKey, Bytes(Document("modern", 901, 0, .5, .5, .5)));
        database.Put(digestKey, actorRef);
        var blockEntityKey = new BedrockDbKey(new ChunkPosition(0, 0, 0), ChunkRecordType.BlockEntity, null).Encode();
        var blockEntity = Bytes(new NbtDocument("", new NbtCompoundValue([
            new("id", new NbtStringValue("Chest")), new("x", new NbtIntValue(0)),
            new("y", new NbtIntValue(0)), new("z", new NbtIntValue(0)) ])));
        database.Put(blockEntityKey, blockEntity);

        var players = new[] {
            (Key: "~local_player", Mode: 0, Dimension: 0, X: .5, HasPos: true, Selected: true),
            (Key: "player_creative", Mode: 1, Dimension: 0, X: 1.0, HasPos: true, Selected: true),
            (Key: "player_adventure", Mode: 2, Dimension: 0, X: 0.0, HasPos: true, Selected: true),
            (Key: "player_spectator", Mode: 6, Dimension: 0, X: .5, HasPos: true, Selected: true),
            (Key: "player_outside", Mode: 0, Dimension: 0, X: 1.0001, HasPos: true, Selected: false),
            (Key: "player_nether", Mode: 0, Dimension: 1, X: .5, HasPos: true, Selected: false),
            (Key: "player_noPos", Mode: 0, Dimension: 0, X: .5, HasPos: false, Selected: false) };
        var before = new Dictionary<string, byte[]>();
        for (var index = 0; index < players.Length; index++)
        {
            var p = players[index];
            before[p.Key] = Bytes(Document(p.Key, 1000 + index, p.Dimension, p.X, .5, .5, p.Mode, p.HasPos));
            database.Put(Key(p.Key), before[p.Key]);
        }

        var result = new EntityActionCommandStore(database).Kill((KillEntityActionCommandRequest)
            EntityActionCommandParser.Parse(omitFlag ? $"kill overworld {corners}" : $"kill overworld {corners} {flag}"));
        Check(result.ChangedWorld && result.Message.Contains("删除 5 个非玩家实体"), "all selected entities deleted including duplicate IDs and modern actor");
        Check(database.Get(LegacyKey(0))!.SequenceEqual(expectedLegacy), "unselected legacy records preserved byte-for-byte");
        Check(database.Get(LegacyKey(1))!.SequenceEqual(otherDimensionBefore), "other dimension entity preserved");
        Check(database.Get(actorKey) is null && database.Get(digestKey) is null, "modern actor and its digest removed");
        Check(database.Get(blockEntityKey)!.SequenceEqual(blockEntity), "block entities preserved");
        foreach (var p in players)
        {
            var after = database.Get(Key(p.Key))!;
            var selected = p.Selected && (p.Mode != 1 || flag == 1);
            if (!selected) Check(after.SequenceEqual(before[p.Key]), "unselected player changed: " + p.Key);
            var root = BedrockNbtCodec.Decode(after, NbtEncoding.LittleEndian).Root;
            var health = ((NbtListValue)root.CompoundValue("Attributes")!).Values.Single().CompoundValue("Current");
            Check(health is NbtFloatValue value && value.Value == (selected ? 0 : 20), "player health/creative switch: " + p.Key);
            Check(root.CompoundValue("PlayerLevel")?.IntegerValue() == 7, "unrelated player NBT changed");
        }
    }

    private static void EmptySelectionPreservesData()
    {
        using var database = new SelfTestWorldDatabase();
        PutLegacy(database, 1, Document("nether", 1, 1, .5, .5, .5));
        var before = database.Get(LegacyKey(1))!;
        var rejected = false;
        try { new EntityActionCommandStore(database).Kill((KillEntityActionCommandRequest)EntityActionCommandParser.Parse("kill overworld 0 0 0 1 1 1 1")); }
        catch (InvalidOperationException) { rejected = true; }
        Check(rejected && database.ApplyBatchCount == 0 && database.Get(LegacyKey(1))!.SequenceEqual(before), "empty selection writes data");
    }

    private static void MixedActorRecords()
    {
        using var database = new SelfTestWorldDatabase();
        var reference = new byte[8]; BinaryPrimitives.WriteInt64LittleEndian(reference, 991);
        var actorKey = Key("actorprefix").Concat(reference).ToArray();
        var digestKey = Key("digp").Concat(new byte[8]).ToArray();
        var retained = Bytes(Document("outside", 32, 0, 2, 2, 2));
        database.Put(actorKey, Bytes(Document("inside", 31, 0, .5, .5, .5)).Concat(retained).ToArray());
        database.Put(digestKey, reference);
        var store = new EntityActionCommandStore(database);
        store.Kill((KillEntityActionCommandRequest)EntityActionCommandParser.Parse("kill overworld 0 0 0 1 1 1 0"));
        Check(database.Get(actorKey)!.SequenceEqual(retained), "outside actor root changed");
        Check(database.Get(digestKey)!.SequenceEqual(reference), "outside actor lost its digp reference");
        var visible = new BedrockWorldObjectScanner(database).ScanAll(null, true, false, int.MaxValue).Objects;
        Check(visible.Count == 1 && visible[0].Document.Root.StringValue("marker") == "outside", "outside actor disappeared on rescan");
        store.Kill((KillEntityActionCommandRequest)EntityActionCommandParser.Parse("kill overworld 2 2 2 2 2 2 0"));
        Check(database.Get(actorKey) is null && database.Get(digestKey) is null, "last actor left a stale reference");
    }

    private static void LegacySelectors()
    {
        foreach (var command in new[] { "kill @e 0", "kill minecraft:pig 0", "kill 101 0" })
        {
            using var database = new SelfTestWorldDatabase();
            PutLegacy(database, 0, Document("pig", 101, 0, 100, 64, 100));
            new EntityActionCommandStore(database).Kill((KillEntityActionCommandRequest)EntityActionCommandParser.Parse(command));
            Check(database.Get(LegacyKey(0)) is null, "old target changed: " + command);
        }
    }
}
