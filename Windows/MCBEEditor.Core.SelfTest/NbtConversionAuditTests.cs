using System.Text;
using MCBEEditor.Core.Nbt;

internal static class NbtConversionAuditTests
{
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception("NBT conversion audit: " + message);
    }
    private static void Reject(Action action)
    {
        try { action(); }
        catch (InvalidDataException) { return; }
        throw new Exception("NBT conversion audit: invalid input was accepted");
    }
    public static void Run()
    {
        foreach (var number in new[] { long.MinValue, -9007199254740993L, 9007199254740993L, long.MaxValue })
        {
            var text = number.ToString(System.Globalization.CultureInfo.InvariantCulture);
            var typed = NbtJsonCodec.Decode(Encoding.UTF8.GetBytes("{\"type\":\"long\",\"value\":" + text + "}"));
            Check(typed[0].Root is NbtLongValue value && value.Value == number, "numeric JSON Int64 changed");
            var ordinary = NbtJsonCodec.Decode(Encoding.UTF8.GetBytes(text));
            Check(ordinary[0].Root is NbtLongValue inferred && inferred.Value == number, "ordinary JSON Int64 changed");
            var document = new NbtDocument("中文", new NbtCompoundValue([
                new NbtNamedTag("long", new NbtLongValue(number)),
                new NbtNamedTag("bytes", new NbtByteArrayValue([0, 127, 128, 255])),
                new NbtNamedTag("ints", new NbtIntArrayValue([int.MinValue, 0, int.MaxValue])),
                new NbtNamedTag("longs", new NbtLongArrayValue([number, 0])),
                new NbtNamedTag("empty", new NbtListValue(NbtTagType.End, []))]));
            foreach (var encoding in new[] { NbtEncoding.BigEndian, NbtEncoding.LittleEndian, NbtEncoding.LittleEndianVarInt })
            {
                var bytes = StandaloneNbtFileCodec.Encode([document, document], encoding);
                var decoded = StandaloneNbtFileCodec.Decode(bytes, "roots.nbt");
                Check(decoded.Documents.Count == 2 && StandaloneNbtFileCodec.Encode(decoded.Documents, encoding).SequenceEqual(bytes), "binary multiple-root roundtrip");
            }
            var json = StandaloneNbtFileCodec.EncodeJson([document]);
            var root = NbtJsonCodec.Decode(json)[0].Root;
            Check(root.CompoundValue("long") is NbtLongValue saved && saved.Value == number, "typed JSON Int64 roundtrip");
        }
        Check(NbtJsonCodec.Decode(Encoding.UTF8.GetBytes("[]"))[0].Root is NbtListValue { ElementType: NbtTagType.End, Values.Count: 0 }, "empty ordinary array");
        foreach (var text in new[] { "{\"type\":\"float\",\"value\":1e39}", "{\"type\":\"double\",\"value\":\"NaN\"}", "{\"type\":\"int\",\"value\":true}", "null", "{\"documents\":[]}" })
            Reject(() => NbtJsonCodec.Decode(Encoding.UTF8.GetBytes(text)));
        var duplicates = new NbtDocument("", new NbtCompoundValue([new NbtNamedTag("same", new NbtIntValue(1)), new NbtNamedTag("same", new NbtIntValue(2))]));
        Reject(() => StandaloneNbtFileCodec.EncodeJson([duplicates]));
        Console.WriteLine("NBT conversion audit scenarios passed.");
    }
}
