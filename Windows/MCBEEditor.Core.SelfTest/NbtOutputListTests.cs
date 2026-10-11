using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;

internal static class NbtOutputListTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("NBT list output regression: " + message);
    }

    private static NbtListValue Ints(params int[] values)
        => new(NbtTagType.Int, values.Select(value => (NbtValue)new NbtIntValue(value)).ToArray());

    private static NbtListValue Strings(params string[] values)
        => new(NbtTagType.String, values.Select(value => (NbtValue)new NbtStringValue(value)).ToArray());

    private static NbtListValue Lists(params NbtValue[] values) => new(NbtTagType.List, values);
    private static string Format(NbtListValue value)
        => BlockCommandNbtOutputFormatter.Root(new NbtCompoundValue([new("Mixed", value)]));

    public static void Run()
    {
        var homogeneous = Format(Lists(Ints(1), Ints(2)));
        var mixed = Format(Lists(Ints(1), Strings("2")));
        Check(mixed != homogeneous, "different child element types must not collapse to the same output");
        Check(homogeneous == "'List''List''Int'\"Mixed\"=\"[1],[2]\"", "homogeneous nested lists must retain existing syntax");
        Check(mixed == "'List''List'\"Mixed\"=\"['List''Int'=[1]],['List''String'=[2]]\"",
            "mixed children need their own exact list descriptors");

        var deeperMixed = Format(Lists(Lists(Ints(1), Strings("2")), Lists(Ints(3))));
        Check(deeperMixed == "'List''List'\"Mixed\"=\"['List''List'=[['List''Int'=[1]],['List''String'=[2]]]],['List''List''Int'=[[3]]]\"",
            "mixed grandchildren must preserve every list level and child type");
        Check(Format(Lists(Lists(Ints(1)), Lists(Strings("2"))))
              == "'List''List'\"Mixed\"=\"['List''List''Int'=[[1]]],['List''List''String'=[[2]]]\"",
            "homogeneous children with different descendant types still require typed siblings");

        Check(Format(Lists(new NbtListValue(NbtTagType.End, []), Ints()))
              == "'List''List'\"Mixed\"=\"['List'''=[]],['List''Int'=[]]\"",
            "empty child lists must retain their declared element types");
        Check(Format(Lists()) == "'List''List''Byte'\"Mixed\"=\"\"", "empty nested-list compatibility must remain unchanged");
        var text = Format(Lists(Ints(1), Strings("line one\nline two,close]\\tail\"")));
        Check(!text.Contains('\n') && !text.Contains('\r')
              && text.Contains("'List''String'=[line one\\nline two\\,close\\]\\\\tail\\\"]]", StringComparison.Ordinal),
            "typed string children must stay on one line and escape payload delimiters");
        foreach (var elementType in Enum.GetValues<NbtTagType>())
        {
            var value = new NbtListValue(elementType, []);
            var formatted = Format(value);
            if (elementType == NbtTagType.End)
                Check(formatted == "'List'''\"Mixed\"=\"\"", "unspecified empty List canonical command spelling");
            CheckRoundtrip(value, formatted);
        }
        foreach (var value in new[]
        {
            Lists(new NbtListValue(NbtTagType.End, []), new NbtListValue(NbtTagType.End, [])),
            Lists(new NbtListValue(NbtTagType.End, []), Ints(1)),
            Lists(Lists(new NbtListValue(NbtTagType.End, []), Ints(1)), Lists()),
            Lists(Strings("'hello'", "'List'", "'String'", "'List''Int'=[1]")),
            Lists(Strings("'List''Int'=[1]")),
            Lists(Strings("'List''String'=[abc]")),
            Lists(Lists(Strings("'hello'"))),
            Lists(new NbtListValue(NbtTagType.End, []), Strings("'hello'")),
            Lists(Lists(new NbtListValue(NbtTagType.End, []), Strings("'hello'")), Lists(Strings("'List'")))
        }) CheckRoundtrip(value, Format(value));
        foreach (var invalid in new[] { "''\"x\"=\"\"", "'Int'''\"x\"=\"\"", "'List'''\"x\"=\"1\"", "'List'''\"x\"=\"[]\"", "'List''List'''\"x\"=\"[1]\"" })
        {
            var rejected = false;
            try { _ = BlockCommandParser.ParseStates(invalid); }
            catch (InvalidDataException) { rejected = true; }
            Check(rejected, "blank type must not permit a real scalar or nonempty List: " + invalid);
        }
        Console.WriteLine("NBT list output regressions passed: homogeneous compatibility, mixed recursive types, empty children and escaped strings.");
    }

    private static void CheckRoundtrip(NbtListValue value, string text)
    {
        var expected = BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue([new("Mixed", value)])), NbtEncoding.LittleEndian);
        var command = BedrockNbtCodec.Encode(new NbtDocument("", new NbtCompoundValue(BlockCommandParser.ParseStates(text))), NbtEncoding.LittleEndian);
        var file = StandaloneNbtFileCodec.Encode(McbeSnbtCodec.Decode(System.Text.Encoding.UTF8.GetBytes(text)), NbtEncoding.LittleEndian);
        Check(command.SequenceEqual(expected) && file.SequenceEqual(expected), "command/file roundtrip must preserve exact empty and nested List types");
    }
}
