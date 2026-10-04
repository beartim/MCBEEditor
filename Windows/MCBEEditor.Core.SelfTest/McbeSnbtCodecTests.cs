using System.Text;
using System.Text.Json;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

internal static class McbeSnbtCodecTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("MCBE-SNBT regression: " + message);
    }

    private static void Reject(Action action, string message)
    {
        try { action(); }
        catch (InvalidDataException) { return; }
        throw new Exception("MCBE-SNBT accepted invalid input: " + message);
    }

    public static void Run()
    {
        var fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures", "mcbe_snbt.json");
        using var fixture = JsonDocument.Parse(File.ReadAllBytes(fixtures));
        var count = 0;
        foreach (var item in fixture.RootElement.GetProperty("cases").EnumerateArray())
        {
            count++;
            var id = item.GetProperty("id").GetString()!;
            if (!item.GetProperty("valid").GetBoolean())
            {
                Reject(() => McbeSnbtCodec.Decode(Encoding.UTF8.GetBytes(item.GetProperty("text").GetString()!)), id);
                continue;
            }
            var expected = Convert.FromHexString(item.GetProperty("little_endian_hex").GetString()!);
            var binaryOnly = item.TryGetProperty("binary_only", out var flag) && flag.GetBoolean();
            var documents = binaryOnly
                ? StandaloneNbtFileCodec.Decode(expected, "fixture.mcstructure").Documents
                : McbeSnbtCodec.Decode(Encoding.UTF8.GetBytes(item.GetProperty("text").GetString()!));
            Check(StandaloneNbtFileCodec.Encode(documents, NbtEncoding.LittleEndian).SequenceEqual(expected), id + " typed binary fixture");
            var canonical = McbeSnbtCodec.Encode(documents);
            var standalone = StandaloneNbtFileCodec.Decode(canonical, "fixture.TXT");
            Check(standalone.OriginalWasSnbt && !standalone.OriginalWasJson && !standalone.WasCompressed
                && standalone.FormatDescription.Contains("MCBE-SNBT"), id + " standalone TXT identity");
            Check(McbeSnbtCodec.Encode(standalone.Documents).SequenceEqual(canonical), id + " canonical text stability");
            Check(StandaloneNbtFileCodec.Decode(canonical, "fixture.data").OriginalWasSnbt, id + " content detection");
            foreach (var encoding in Enum.GetValues<NbtEncoding>())
                Check(StandaloneNbtFileCodec.Encode(standalone.Documents, encoding)
                    .SequenceEqual(StandaloneNbtFileCodec.Encode(documents, encoding)), id + " preserves " + encoding);
        }

        Reject(() => StandaloneNbtFileCodec.Decode([0xFF, 0xFE], "invalid.txt"), "UTF-8 bytes");
        Reject(() => StandaloneNbtFileCodec.Decode(Encoding.UTF8.GetBytes("{\"Age\":0}"), "json-disguised.txt"), "TXT must use MCBE-SNBT");
        Reject(() => McbeSnbtCodec.Encode([]), "empty root sequence");
        Reject(() => McbeSnbtCodec.Encode([new("invalid", new NbtStringValue("\uD800"))]), "unpaired model surrogate");

        var typedRoots = new NbtDocument[]
        {
            new("long", new NbtLongValue(long.MinValue)),
            new("float", new NbtFloatValue(BitConverter.UInt32BitsToSingle(0xFFC12345))),
            new("double", new NbtDoubleValue(BitConverter.UInt64BitsToDouble(0xFFF8000000000123))),
            new("negative-zero", new NbtDoubleValue(BitConverter.Int64BitsToDouble(long.MinValue))),
            new("list", new NbtListValue(NbtTagType.String, [new NbtStringValue(""), new NbtStringValue(" a,b ")])),
            new("empty", new NbtListValue(NbtTagType.Compound, []))
        };
        var typedCopy = McbeSnbtCodec.Decode(McbeSnbtCodec.Encode(typedRoots));
        Check(StandaloneNbtFileCodec.Encode(typedCopy, NbtEncoding.LittleEndian)
            .SequenceEqual(StandaloneNbtFileCodec.Encode(typedRoots, NbtEncoding.LittleEndian)), "typed scalar roots and NaN bit patterns");

        NbtValue nested = new NbtIntValue(1);
        for (var depth = 0; depth < 257; depth++) nested = new NbtCompoundValue([new("child", nested)]);
        Reject(() => McbeSnbtCodec.Encode([new("", nested)]), "write depth limit");
        var tooDeep = new StringBuilder("['Compound'\"root\"=\"");
        for (var depth = 0; depth < 257; depth++) tooDeep.Append("{'Compound'\"child\"=\"");
        tooDeep.Append("{}");
        for (var depth = 0; depth < 257; depth++) tooDeep.Append("\"}");
        tooDeep.Append("\"]");
        Reject(() => McbeSnbtCodec.Decode(Encoding.UTF8.GetBytes(tooDeep.ToString())), "read depth limit");
        foreach (var spelling in new[] { "txt", "TXT", "mcbe-snbt" })
            Check(StructureTemplateCommandParser.Parse("structure export " + spelling + " test:house")
                is { Format: StructureFileFormat.Txt, IsDestructive: false }, "structure format alias " + spelling);
        Console.WriteLine($"MCBE-SNBT passed: {count} shared fixtures, typed roots, NaN/raw-string losslessness, strict UTF-8 and depth limits.");
    }
}
