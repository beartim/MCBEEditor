using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

internal static class FillSetblockBlockEntityTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("Fill/setblock block entity: " + message);
    }

    public static void Run()
    {
        foreach (var command in new[] {
            "setblock overworld 0 64 0 minecraft:stone NULL",
            "fill overworld 0 64 0 16 64 0 minecraft:stone NULL" })
        {
            var rejected = false;
            try { _ = BlockCommandParser.Parse(command); }
            catch (InvalidDataException) { rejected = true; }
            Check(rejected, "missing required final block-entity argument was accepted: " + command);
        }
        using var db = new SelfTestWorldDatabase();
        var store = new BedrockRegionBlockStore(db);
        BedrockRegionMutationResult Run(string text) => BlockCommandParser.Parse(text) switch
        {
            SetBlockCommandRequest set => store.SetBlock(set.Dimension, set.Position, set.Storages, set.BlockEntity),
            FillBlockCommandRequest fill => store.Fill(fill.Dimension, fill.Region, fill.Storages, fill.BlockEntity),
            _ => throw new Exception("Unexpected command")
        };
        static byte[] Key(int dimension, int x, int z) => new BedrockDbKey(new(x, z, dimension), ChunkRecordType.BlockEntity, null).Encode();
        static string Tags(int x, int y, int z, string id = "Chest") =>
            $"'Byte'\"Findable\"=\"0\",'List'''\"Items\"=\"\",'String'\"id\"=\"{id}\",'Byte'\"isMovable\"=\"1\",'Int'\"x\"=\"{x}\",'Int'\"y\"=\"{y}\",'Int'\"z\"=\"{z}\"";
        static byte[] Record(string tags, string root = "") => BedrockNbtCodec.Encode(
            new NbtDocument(root, new NbtCompoundValue(BlockCommandParser.ParseStates(tags))));
        Dictionary<string, string> Snapshot() => db.Entries(includeValues: true).ToDictionary(e => Convert.ToHexString(e.Key), e => Convert.ToHexString(e.Value!));
        void FailsWithoutWrites(string command)
        {
            var before = Snapshot();
            var batches = db.ApplyBatchCount;
            var rejected = false;
            try { Run(command); } catch (Exception error) when (error is InvalidDataException or NotSupportedException) { rejected = true; }
            var after = Snapshot();
            Check(rejected && batches == db.ApplyBatchCount && before.Count == after.Count && before.All(e => after.GetValueOrDefault(e.Key) == e.Value),
                "rejected command changed database: " + command);
        }

        var baseTags = "'String'\"id\"=\"Chest\",'List'''\"Items\"=\"\",'Compound'\"Nested\"=\"{'Int'\"x\"=\"999\",'String'\"y\"=\"keep\"}\"";
        foreach (var suffix in new[] { "", ",'Long'\"x\"=\"9223372036854775807\"",
            ",'Int'\"x\"=\"-999\",'Int'\"y\"=\"1\",'Int'\"z\"=\"999\"",
            ",'Float'\"X\"=\"0.75\",'String'\"Y\"=\"ignored\",'List'''\"z\"=\"\"",
            ",'Int'\"x\"=\"1\",'Int'\"X\"=\"2\",'String'\"z\"=\"ignored\"" })
        {
            Run("setblock 6100 137 64 -17 minecraft:stone NULL " + baseTags + suffix);
            var records = ConsecutiveNbtCodec.Decode(db.Get(Key(6100, 8, -2))!);
            Check(records.Count == 1, "optional root coordinates left duplicate entities");
            var root = records[0].Document.Root;
            var coordinates = ((NbtCompoundValue)root).Tags.Where(t => new[] { "x", "y", "z" }.Contains(t.Name.ToLowerInvariant())).ToArray();
            Check(coordinates.Length == 3 && coordinates.All(t => new[] { "x", "y", "z" }.Contains(t.Name) && t.Value is NbtIntValue), "coordinates must be unique canonical Int tags");
            Check(root.CompoundValue("x")?.IntegerValue() == 137 && root.CompoundValue("y")?.IntegerValue() == 64 && root.CompoundValue("z")?.IntegerValue() == -17, "input coordinates overrode the command position");
            Check(root.CompoundValue("Nested")?.CompoundValue("x")?.IntegerValue() == 999 && root.CompoundValue("Nested")?.CompoundValue("y") is NbtStringValue { Value: "keep" }, "nested coordinates were changed");
        }

        var key = Key(0, 0, 0);
        var outside = Record(Tags(1, 64, 0, "arbitrary:outside"), "peer");
        var orphan = Record("'String'\"id\"=\"no-coordinate\"");
        var target = Record(Tags(0, 64, 0));
        var original = outside.Concat(target).Concat(orphan).Concat(target).ToArray();
        db.Put(key, original);
        foreach (var command in new[] { "setblock overworld 0 64 0 minecraft:stone NULL preserve", "fill overworld 0 64 0 0 64 0 minecraft:dirt NULL preserve" })
        {
            var batches = db.ApplyBatchCount;
            var result = Run(command);
            Check(result.RemovedBlockEntities == 0 && result.CopiedBlockEntities == 0 && db.Get(key)!.SequenceEqual(original), "preserve changed entities");
            Check(db.ApplyBatchCount == batches + 1, "mutation must use one WriteBatch");
        }
        var changed = Run("setblock overworld 0 64 0 minecraft:stone NULL minecraft:water NULL " + Tags(0, 64, 0));
        Check(changed.RemovedBlockEntities == 2 && changed.CopiedBlockEntities == 1, "replacement must remove duplicates and create one entity");
        Check(db.Get(key)!.SequenceEqual(outside.Concat(orphan).Concat(target)), "custom entity changed peer bytes/order or supplied tags");
        var layers = new BedrockBlockStore(db).ReadBlock(0, 0, 64, 0).Layers;
        Check(layers[0].Name == "minecraft:stone" && layers[1].Name == "minecraft:water", "user example storages were not written");
        var output = store.GetBlockText(0, new(0, 64, 0));
        Check(output.Contains("'List'''\"Items\"=\"\""), "empty List output regressed");
        Run("setblock overworld 0 64 0 minecraft:stone NULL " + Tags(0, 64, 0, "anything:custom_id"));
        Check(store.GetBlockText(0, new(0, 64, 0)).Contains("anything:custom_id"), "arbitrary id was rejected or changed");
        var emptied = Run("fill overworld 0 64 0 0 64 0 minecraft:stone NULL empty");
        Check(emptied.RemovedBlockEntities == 1 && db.Get(key)!.SequenceEqual(outside.Concat(orphan)), "empty changed unrelated records");

        // Reverse endpoints and no supplied root coordinates.
        var template = "'String'\"id\"=\"wzn:anything\",'List'''\"Items\"=\"\",'Int'\"DimensionId\"=\"77\",'Compound'\"Nested\"=\"{'Long'\"Exact\"=\"9007199254740993\",'Int'\"x\"=\"999\"}\"";
        var batchesBeforeFill = db.ApplyBatchCount;
        var filled = Run("fill 1000 16 65 0 -1 64 -1 minecraft:stone NULL " + template);
        Check(filled.CopiedBlockEntities == 72 && db.ApplyBatchCount == batchesBeforeFill + 1, "cross-chunk fill must create one entity per position in one batch");
        for (var x = -1; x <= 16; x++) for (var y = 64; y <= 65; y++) for (var z = -1; z <= 0; z++)
        {
            var records = ConsecutiveNbtCodec.Decode(db.Get(Key(1000, x < 0 ? -1 : x / 16, z < 0 ? -1 : 0))!);
            var matches = records.Where(r => r.Document.Root.CompoundValue("x")?.IntegerValue() == x && r.Document.Root.CompoundValue("y")?.IntegerValue() == y && r.Document.Root.CompoundValue("z")?.IntegerValue() == z).ToArray();
            Check(matches.Length == 1 && matches[0].Document.Root.CompoundValue("id") is NbtStringValue { Value: "wzn:anything" }, "fill coordinate/id mismatch");
            Check(matches[0].Document.Root.CompoundValue("DimensionId")?.IntegerValue() == 77 && matches[0].Document.Root.CompoundValue("Nested")?.CompoundValue("x")?.IntegerValue() == 999,
                "fill changed non-coordinate tags");
        }
        var typed = "'String'\"id\"=\"ByteCoordinate\",'Byte'\"X\"=\"1\",'Short'\"y\"=\"64\",'Long'\"z\"=\"1\"";
        Run("fill -123 1 64 1 2 64 1 minecraft:air NULL " + typed);
        var typedRecords = ConsecutiveNbtCodec.Decode(db.Get(Key(-123, 0, 0))!);
        Check(typedRecords.Count == 2 && typedRecords.All(r => r.Document.Root.CompoundValue("x") is NbtIntValue && r.Document.Root.CompoundValue("y") is NbtIntValue && r.Document.Root.CompoundValue("z") is NbtIntValue), "input coordinate types must be ignored");
        Run("fill -123 1 64 1 128 64 1 minecraft:dirt NULL " + typed);
        Check(ConsecutiveNbtCodec.Decode(db.Get(Key(-123, 8, 0))!).Any(r => r.Document.Root.CompoundValue("x")?.IntegerValue() == 128), "ignored Byte coordinate constrained fill");

        foreach (var suffix in new[] { "NULL", "unknown", Tags(0, 64, 0) + ",'List'''\"Invalid\"=\"1\"" })
            FailsWithoutWrites("setblock overworld 0 64 0 minecraft:dirt NULL " + suffix);
        Run("fill 1000 16 65 0 -1 64 -1 minecraft:dirt NULL " + Tags(-999, -999, -999));
        var ignoredFillCoordinates = store.GetBlockText(1000, new(16, 65, 0));
        Check(ignoredFillCoordinates.Contains("'Int'\"x\"=\"16\"") && ignoredFillCoordinates.Contains("'Int'\"y\"=\"65\""), "fill used template coordinates");

        // preserve must work even if existing entity data cannot be decoded.
        var brokenKey = Key(0, 1, 0);
        byte[] broken = [10, 0, 0, 3];
        db.Put(brokenKey, broken);
        Run("fill overworld 0 64 0 16 64 0 minecraft:stone NULL preserve");
        Check(db.Get(brokenKey)!.SequenceEqual(broken), "preserve parsed or rewrote malformed entities");
        FailsWithoutWrites("fill overworld 0 64 0 16 64 0 minecraft:dirt NULL empty");
        FailsWithoutWrites("fill overworld 0 64 0 16 64 0 minecraft:dirt NULL " + Tags(0, 64, 0));
        Run("setblock 2000 0 64 0 minecraft:stone NULL " + Tags(0, 64, 0));
        Run("setblock 2000 0 64 0 minecraft:stone NULL empty");
        Check(db.Get(Key(2000, 0, 0)) is null, "empty must delete the entity key when no records remain");
        var withPos = Tags(0, 64, 0, "custom:with_pos") + ",'List''Float'\"Pos\"=\"1,64,0\"";
        Run("setblock 3000 0 64 0 minecraft:stone NULL " + withPos);
        Check(store.GetBlockText(3000, new(0, 64, 0)).Contains("custom:with_pos"), "auxiliary Pos must not override root block-entity coordinates");
        Run("setblock 3000 0 64 0 minecraft:dirt NULL " + withPos);
        Check(ConsecutiveNbtCodec.Decode(db.Get(Key(3000, 0, 0))!).Count == 1, "auxiliary Pos left duplicate entities");
        Run("setblock 3000 0 64 0 minecraft:stone NULL empty");
        Check(db.Get(Key(3000, 0, 0)) is null, "empty used auxiliary Pos rather than root coordinates");
        var extremeKey = Key(4000, int.MaxValue / 16, 0);
        var outOfRangePeer = Record("'String'\"id\"=\"outside_int32\",'Long'\"x\"=\"2147483648\",'Int'\"y\"=\"64\",'Int'\"z\"=\"0\"");
        db.Put(extremeKey, outOfRangePeer);
        Run("setblock 4000 2147483647 64 0 minecraft:stone NULL empty");
        Check(db.Get(extremeKey)!.SequenceEqual(outOfRangePeer), "out-of-range Long entity was clamped into a target position");
        var ambiguous = Record("'String'\"id\"=\"fractional\",'Float'\"x\"=\"0.75\",'Int'\"y\"=\"64\",'Int'\"z\"=\"0\"")
            .Concat(Record("'String'\"id\"=\"duplicate\",'Int'\"x\"=\"0\",'Int'\"X\"=\"1\",'Int'\"y\"=\"64\",'Int'\"z\"=\"0\"")).ToArray();
        db.Put(Key(3001, 0, 0), ambiguous);
        Run("setblock 3001 0 64 0 minecraft:stone NULL empty");
        Check(db.Get(Key(3001, 0, 0))!.SequenceEqual(ambiguous), "empty removed ambiguous coordinate records");
        var legacyDocument = new NbtDocument("legacy", new NbtCompoundValue(BlockCommandParser.ParseStates(Tags(1, 64, 0, "legacy:peer"))));
        db.Put(Key(4001, 0, 0), BedrockNbtCodec.Encode(legacyDocument, NbtEncoding.LittleEndianVarInt));
        Run("setblock 4001 0 64 0 minecraft:stone NULL " + Tags(0, 64, 0));
        var normalized = ConsecutiveNbtCodec.Decode(db.Get(Key(4001, 0, 0))!);
        Check(normalized.Count == 2 && normalized[0].RawData.SequenceEqual(BedrockNbtCodec.Encode(legacyDocument, NbtEncoding.LittleEndian)), "legacy VarInt peer or appended entity was lost");
        Console.WriteLine("Fill/setblock block entities passed: optional/ignored root coordinates, canonical Int positions, nested preservation, three modes, reverse/cross-chunk fill and atomic failures.");
    }
}
