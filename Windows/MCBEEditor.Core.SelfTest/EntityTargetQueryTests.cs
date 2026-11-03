using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

internal static class EntityTargetQueryTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("Entity target query: " + message);
    }
    public static void Run()
    {
        foreach (var text in new[] { "entity", "entity @e", "entity @s", "entity @a", "entity 12345678", "entity -42",
            "entity 2147483648", "entity -9223372036854775808", "entity 9223372036854775807", "entity minecraft:pig",
            "entity @e 0", "entity @a the_end", "entity 12345678 nether", "entity minecraft:pig 0 1 65 1 0 64 0",
            "entity 0 1 65 1 0 64 0", "entity minecraft:overworld" })
            _ = EntityQueryCommandParser.Parse(text);
        foreach (var text in new[] { "entity 0", "entity 9223372036854775808", "entity -9223372036854775809", "entity @p",
            "entity @e 0 0", "entity @a 0 0 64 0", "entity @e 0 0 64 0 1 65", "entity @e 0 0 64 0 1 65 1 extra",
            "entity @e 0 NaN 64 0 1 65 1", "entity minecraft:pig 0 0 64 0 1 65 1e40", "entity @a 2147483648" })
        {
            var rejected = false;
            try { _ = EntityQueryCommandParser.Parse(text); } catch (InvalidDataException) { rejected = true; }
            Check(rejected, "invalid syntax accepted: " + text);
        }
        var incompleteRejected = false;
        try { _ = EntityQueryCommandParser.Parse("entity @e 0 0 64 0 1 65", _ => 0); }
        catch (InvalidDataException) { incompleteRejected = true; }
        Check(incompleteRejected, "incomplete target bounds must not use a permissive dimension resolver");
        using var db = new SelfTestWorldDatabase();
        NbtDocument Actor(string identifier, long id, int dimension, double x, double y, double z, bool definitions = false) => new("", new NbtCompoundValue([
            definitions ? new("definitions", new NbtListValue(NbtTagType.String, [new NbtStringValue("+" + identifier)])) : new("identifier", new NbtStringValue(identifier)),
            new("UniqueID", new NbtLongValue(id)), new("DimensionId", new NbtIntValue(dimension)),
            new("Pos", new NbtListValue(NbtTagType.Double, [new NbtDoubleValue(x), new NbtDoubleValue(y), new NbtDoubleValue(z)])) ]));
        var pig = Actor("minecraft:pig", 12345678, 0, 0, 64, 0);
        pig = new NbtDocument("", new NbtCompoundValue(((NbtCompoundValue)pig.Root).Tags.Concat(new NbtNamedTag[] {
            new("ExactNaN", new NbtFloatValue(BitConverter.Int32BitsToSingle(0x7FC01234))),
            new("MixedChildren", new NbtListValue(NbtTagType.List, [new NbtListValue(NbtTagType.Int, [new NbtIntValue(1)]), new NbtListValue(NbtTagType.String, [new NbtStringValue("two,words")])]))
        }).ToArray()));
        var key = new BedrockDbKey(new(0, 0, 0), ChunkRecordType.Entity, null).Encode();
        db.Put(key, new[] { pig, Actor("minecraft:cow", -42, 0, .5, 64.25, .5, true),
            Actor("minecraft:pig", 12345678, 0, 1, 65, 1), Actor("minecraft:pig", 44, 0, 1.0001, 64, 0) }
            .SelectMany(d => BedrockNbtCodec.Encode(d, NbtEncoding.LittleEndian)).ToArray());
        new DimensionStore(db).Add("custom:moon", 7);
        db.Put(new BedrockDbKey(new(0, 0, 7), ChunkRecordType.Entity, null).Encode(), BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue([]))));
        var reference = new byte[8]; BinaryPrimitives.WriteInt64LittleEndian(reference, 999);
        var actorKey = Encoding.UTF8.GetBytes("actorprefix").Concat(reference).ToArray();
        db.Put(actorKey, BedrockNbtCodec.Encode(Actor("minecraft:chicken", 91, 2, 0, 65, 0)));
        db.Put(Encoding.UTF8.GetBytes("digp").Concat(new byte[8]).ToArray(), reference);
        db.Put(new BedrockDbKey(new(0, 0, 0), ChunkRecordType.BlockEntity, null).Encode(), BedrockNbtCodec.Encode(Actor("Chest", 12345678, 0, 0, 64, 0)));
        void Player(string name, long? id, int? dimension, double? x)
        {
            var tags = new List<NbtNamedTag> { new("PlayerName", new NbtStringValue(name)) };
            if (id.HasValue) tags.Add(new("UniqueID", new NbtLongValue(id.Value)));
            if (dimension.HasValue) tags.Add(new("DimensionId", new NbtIntValue(dimension.Value)));
            if (x.HasValue) tags.Add(new("Pos", new NbtListValue(NbtTagType.Double, [new NbtDoubleValue(x.Value), new NbtDoubleValue(64), new NbtDoubleValue(0)])));
            db.Put(Encoding.UTF8.GetBytes(name), BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue(tags))));
        }
        Player("~local_player", 12345678, 0, 0);
        // Nine-byte player_42 also resembles a binary chunk Entity key.
        Player("player_42", -42, 1, 0);
        Player("player_nopos", 77, 2, null);
        Player("player_missingdim", 88, null, .12345678901234566);
        Player("player_server_-9007199254740993", null, 1, 0);
        Dictionary<string, string> Snapshot() => db.Entries(includeValues: true).ToDictionary(e => Convert.ToHexString(e.Key), e => Convert.ToHexString(e.Value!));
        var before = Snapshot(); var batches = db.ApplyBatchCount;
        TargetingCommandExecutionResult Query(string text)
        {
            var result = new EntityQueryCommandStore(db).Execute(EntityQueryCommandParser.Parse(text, new DimensionStore(db).Resolve));
            Check(!result.ChangedWorld && result.OutputLines.All(l => !l.Text.Contains('\n')), "query wrote world or split an entity line");
            return result;
        }
        var all = Query("entity");
        Check(all.OutputLines.Count == 11 && all.OutputLines.Select(l => l.Text).SequenceEqual(Query("entity @e").OutputLines.Select(l => l.Text)), "default @e, players and independent records");
        Check(Query("entity @a").OutputLines.Count == 5 && Query("entity minecraft:player").OutputLines.Count == 5, "player selectors");
        Check(Query("entity @s").OutputLines.Single().Text.StartsWith("minecraft:player Dimension=overworld(0) Pos=(0,64,0) NBT=["), "local player's actual coordinates and inferred type");
        Check(Query("entity 12345678").OutputLines.Count == 3 && Query("entity -42").OutputLines.Count == 2, "exact ID selection including players and repeated IDs");
        Check(Query("entity -9007199254740993").OutputLines.Single().Text.Contains("player_server_-9007199254740993"), "player key fallback and exact Long");
        Check(Query("entity minecraft:pig").OutputLines.Count == 3 && Query("entity minecraft:cow").OutputLines.Single().Text.StartsWith("minecraft:cow Dimension="), "judged identifier from definitions");
        Check(Query("entity @e custom:moon").OutputLines.Single().Text == "未知实体 Dimension=custom:moon(7) Pos=NULL NBT=[]", "dimension name and missing Pos without invented tags");
        Check(Query("entity 77").OutputLines.Single().Text.StartsWith("minecraft:player Dimension=the_end(2) Pos=NULL NBT=["), "player dimension independent of Pos");
        Check(Query("entity @e 0 0 64 0 1 65 1").OutputLines.Count == 5, "range includes player and actor boundaries");
        Check(Query("entity @a 0 0 64 0 1 65 1").OutputLines.Count == 2 && Query("entity minecraft:pig 0 0 64 0 1 65 1").OutputLines.Count == 2, "selector plus dimension and bounds");
        Check(Query("entity 0 1 65 1 0 64 0").OutputLines.Select(l => l.Text).SequenceEqual(Query("entity @e 0 0 64 0 1 65 1").OutputLines.Select(l => l.Text)), "legacy numeric dimension with full range and reverse corners");
        Check(Query("entity @e 2 0 65 0 0 65 0").OutputLines.Single().Text.StartsWith("minecraft:chicken Dimension=the_end(2)"), "actual NBT dimension and no-Pos player excluded from range");
        var output = Query("entity 12345678").OutputLines.Single(l => l.Text.StartsWith("minecraft:pig Dimension=") && l.Text.Contains("Pos=(0,64,0)" )).Text;
        var payload = output[(output.IndexOf(" NBT=[", StringComparison.Ordinal) + 6)..^1];
        Check(BedrockNbtCodec.Encode(McbeSnbtCodec.Decode(Encoding.UTF8.GetBytes("['Compound'\"\"=\"{" + payload + "}\"]")).Single()).SequenceEqual(BedrockNbtCodec.Encode(pig)), "full original NBT roundtrip");
        var oldCulture = CultureInfo.CurrentCulture;
        try { CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("de-DE"); Check(Query("entity 88").OutputLines.Single().Text.Contains("Pos=(0.12345678901234566,64,0)"), "coordinate precision and culture"); }
        finally { CultureInfo.CurrentCulture = oldCulture; }
        Check(Query("entity 999999999").OutputLines.Single().Text == "entity：没有匹配的实体。", "unmatched ID is a normal readonly result");
        var after = Snapshot();
        Check(db.ApplyBatchCount == batches && before.Count == after.Count && before.All(e => after.GetValueOrDefault(e.Key) == e.Value), "database changed");
        Console.WriteLine("Entity target query passed: players, selectors, exact IDs, dimensions/bounds, full NBT, precision and readonly storage.");
    }
}
