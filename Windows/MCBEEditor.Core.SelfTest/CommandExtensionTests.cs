using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;
using System.Text;

internal static class CommandExtensionTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("Command extension regression: " + message);
    }

    public static void Run()
    {
        var weather = EnvironmentCommandParser.Parse("weather query");
        Check(weather is WeatherQueryEnvironmentCommandRequest && !weather.IsDestructive, "weather query is read-only");
        foreach (var text in new[] { "structure query", "structure export nbt", "structure export json demo:house", "structure export mcstructure demo:house" })
            Check(!StructureTemplateCommandParser.Parse(text).IsDestructive, "read-only parse: " + text);
        Check(StructureTemplateCommandParser.Parse("structure import").Operation == StructureTemplateStructureOperationKind.Import, "import dialog parse");
        Check(StructureTemplateCommandParser.Parse("structure import demo:house").Name == "demo:house", "import name parse");
        foreach (var text in new[] { "structure export", "structure export zip", "structure export nbt a b", "structure query x", "structure import a b" })
        {
            try { StructureTemplateCommandParser.Parse(text); throw new Exception("Invalid structure command accepted: " + text); }
            catch (InvalidDataException) { }
        }
        try { EnvironmentCommandParser.Parse("weather query 1"); throw new Exception("weather query accepted arguments"); }
        catch (InvalidDataException) { }

        using var db = new SelfTestWorldDatabase();
        var chunk = new ChunkPosition(-3, 2, 2);
        db.Put(BedrockDbKey.SubChunk(-3, 2, 2, -4), new BedrockSubChunk(8, -4, [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())], []).EncodePersistent());
        db.Put(BedrockDbKey.SubChunk(-3, 2, 2, 4), new BedrockSubChunk(9, 4, [SubChunkStorage.AirFilled(BedrockBlockState.EditableAir())], []).EncodePersistent());
        var chunks = new BedrockChunkStore(db);
        foreach (var summary in new[] { chunks.ListChunks().Single(), chunks.SummaryAt(chunk) })
            Check(summary.DetailText.Contains("SubChunk v8/v9") && summary.DetailText.Contains("Y-4-Y4"), "actual mixed versions and signed range");
        db.Put(BedrockDbKey.SubChunk(-3, 2, 2, 5), []);
        Check(chunks.SummaryAt(chunk).SubChunkVersionText == "v8/v9/未知版本", "empty headers do not become v0");

        var root = Path.Combine(Path.GetTempPath(), "MCBEEditor-query-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var world = new WorldDocument(root);
            world.WriteLevelDat(new LevelDatFile(10, new NbtDocument("", new NbtCompoundValue([
                new("rainLevel", new NbtFloatValue(0.25f)), new("rainTime", new NbtIntValue(123)),
                new("lightningLevel", new NbtFloatValue(0.5f)), new("lightningTime", new NbtIntValue(456)),
                new("doWeatherCycle", new NbtByteValue(0))
            ]))));
            var before = File.ReadAllBytes(Path.Combine(root, "level.dat"));
            var result = new EnvironmentCommandStore(world, db).Execute(weather);
            Check(!result.ChangedWorld && result.Message.Split('\n').Length == 5, "five weather parameters");
            foreach (var field in new[] { "rainLevel=0.25", "rainTime=123", "lightningLevel=0.5", "lightningTime=456", "doWeatherCycle=0" })
                Check(result.Message.Contains(field), "query weather field " + field);
            Check(File.ReadAllBytes(Path.Combine(root, "level.dat")).SequenceEqual(before), "query leaves level.dat identical");
        }
        finally { Directory.Delete(root, true); }

        // Exercise actual capture, export and import code, including big-endian bytes.
        var structure = new BedrockRegionBlockStore(db).CaptureStructureDocument(2, new BedrockBlockBox(new(-48, -64, 32), new(-48, -64, 32)));
        var stores = new StructureNbtStore(db);
        stores.SaveNew(structure, "demo:house");
        db.Put(Encoding.UTF8.GetBytes("structuretemplate_bad"), [255, 1]);
        var snapshot = db.Entries(includeValues: true).Select(e => Convert.ToHexString(e.Key) + ":" + Convert.ToHexString(e.Value!)).ToArray();
        var query = new StructureTemplateCommandStore(db).Execute(StructureTemplateCommandParser.Parse("structure query"));
        Check(!query.ChangedWorld && query.OutputLines.Count == 2, "query includes malformed records, one row each");
        Check(query.Message.Contains("demo:house") && query.Message.Contains("尺寸 1×1×1") && query.Message.Contains("NBT 无法解析"), "structure metadata query");
        Check(snapshot.SequenceEqual(db.Entries(includeValues: true).Select(e => Convert.ToHexString(e.Key) + ":" + Convert.ToHexString(e.Value!))), "query leaves database identical");
        foreach (var format in Enum.GetValues<StructureFileFormat>())
        {
            var bytes = StandaloneNbtFileCodec.EncodeStructure(structure, format);
            var filename = "structure." + format.ToString().ToLowerInvariant();
            if (format == StructureFileFormat.Nbt)
                Check(bytes.SequenceEqual(BedrockNbtCodec.Encode(structure, NbtEncoding.BigEndian)), "NBT exports big endian");
            if (format == StructureFileFormat.Mcstructure)
                Check(BedrockNbtCodec.Decode(bytes, NbtEncoding.LittleEndian).Root.IntValue("format_version") == 1, "mcstructure is little endian");
            var decoded = StandaloneNbtFileCodec.Decode(bytes, filename);
            Check(decoded.Documents.Count == 1 && decoded.Documents[0].Root.IntValue("format_version") == 1, "export round trip " + format);
            stores.Import(bytes, filename, "test:" + format.ToString().ToLowerInvariant(), false);
        }
        Check(stores.Records().Count == 5, "all three formats imported as structures");
        var legacyNested = NbtJsonCodec.Decode(Encoding.UTF8.GetBytes("""
            {"documents":[{"name":"lists","type":"list","value":{"type":"list","value":[{"type":"int","value":[1,2]},{"type":"int","value":[]}]}}]}
            """));
        Check(legacyNested[0].Root is NbtListValue { ElementType: NbtTagType.List } outer && outer.Values[0] is NbtListValue { ElementType: NbtTagType.Int } ints && ints.Values.Count == 2, "legacy iOS nested-list JSON");
        var explicitList = NbtJsonCodec.Decode(Encoding.UTF8.GetBytes("""
            {"documents":[{"name":"lists","type":"list","value":{"type":"list","value":[{"type":"list","value":[{"type":"int","value":1}]}]}}]}
            """));
        Check(explicitList[0].Root is NbtListValue { ElementType: NbtTagType.List } explicitOuter && explicitOuter.Values[0] is NbtListValue { ElementType: NbtTagType.Int } explicitInts && explicitInts.Values.Count == 1, "explicit nested-list tags");
        if (Environment.GetEnvironmentVariable("MCBE_STRUCTURE_VECTORS") is { } directory)
        {
            Directory.CreateDirectory(directory);
            File.WriteAllBytes(Path.Combine(directory, "windows.json"), StandaloneNbtFileCodec.EncodeStructure(structure, StructureFileFormat.Json));
            var peer = Path.Combine(directory, "ios.json");
            if (File.Exists(peer))
            {
                var importedIos = StandaloneNbtFileCodec.Decode(File.ReadAllBytes(peer), peer);
                Check(JavaStructureConverter.ConvertIfNeeded(importedIos.Documents[0]).Document.Root.IntValue("format_version") == 1, "iOS JSON imports on Windows");
                Console.WriteLine("iOS JSON structure imported successfully by Windows codec.");
            }
        }
        Console.WriteLine("Command extensions passed: parsing, readonly queries, mixed SubChunk versions, all structure export/import formats.");
    }
}
