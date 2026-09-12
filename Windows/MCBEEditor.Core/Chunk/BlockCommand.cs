using System.Globalization;
using System.Text.RegularExpressions;
using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

public abstract record BlockCommandRequest;
public sealed record SetBlockCommandRequest(int Dimension, BedrockBlockCoordinate Position, IReadOnlyList<BedrockBlockStorageSpec> Storages) : BlockCommandRequest;
public sealed record FillBlockCommandRequest(int Dimension, BedrockBlockBox Region, IReadOnlyList<BedrockBlockStorageSpec> Storages) : BlockCommandRequest;
public sealed record CloneBlockCommandRequest(int SourceDimension, BedrockBlockBox Source, int TargetDimension, BedrockBlockCoordinate Destination) : BlockCommandRequest;
public sealed record GetBlockCommandRequest(int Dimension, BedrockBlockCoordinate Position) : BlockCommandRequest;

public static class BlockCommandParser
{
    private static readonly Regex BlockNamePattern = new("^[a-z0-9_.-]+:[a-z0-9_./-]+$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public const string Usage =
        "setblock 维度 x y z 方块名 states [方块名 states ...]\n" +
        "fill 维度 x1 y1 z1 x2 y2 z2 方块名 states [方块名 states ...]\n" +
        "clone 源维度 x1 y1 z1 x2 y2 z2 目标维度 x3 y3 z3\n" +
        "getblock 维度 x y z\n" +
        "states 可用 NULL，或 iOS 版同格式 typed NBT，例如 'String'\"wood_type\"=\"oak\"。";

    public static bool IsBlockCommand(string text)
    {
        var command = FirstToken(text).ToLowerInvariant();
        return command is "setblock" or "fill" or "clone" or "getblock";
    }

    public static BlockCommandRequest Parse(string text)
    {
        var tokens = TokenizeCommand(text);
        if (tokens.Count == 0) throw new InvalidDataException("命令不能为空。");
        var command = tokens[0].ToLowerInvariant();
        var arguments = tokens.Skip(1).ToArray();
        return command switch
        {
            "setblock" => ParseSetBlock(arguments),
            "fill" => ParseFill(arguments),
            "clone" => ParseClone(arguments),
            "getblock" => ParseGetBlock(arguments),
            _ => throw new InvalidDataException("不存在的方块命令。\n" + Usage)
        };
    }

    private static SetBlockCommandRequest ParseSetBlock(string[] args)
    {
        if (args.Length < 6 || (args.Length - 4) % 2 != 0) throw UsageError();
        var count = (args.Length - 4) / 2;
        if (count is < 1 or > byte.MaxValue) throw new InvalidDataException("setblock 必须提供 1…255 个 storage。");
        return new SetBlockCommandRequest(ParseDimension(args[0]), Coordinate(args, 1), ParseStorages(args, 4, count));
    }

    private static FillBlockCommandRequest ParseFill(string[] args)
    {
        if (args.Length < 9 || (args.Length - 7) % 2 != 0) throw UsageError();
        var count = (args.Length - 7) / 2;
        if (count is < 1 or > byte.MaxValue) throw new InvalidDataException("fill 必须提供 1…255 个 storage。");
        var first = Coordinate(args, 1);
        var second = Coordinate(args, 4);
        return new FillBlockCommandRequest(ParseDimension(args[0]), new BedrockBlockBox(first, second), ParseStorages(args, 7, count));
    }

    private static CloneBlockCommandRequest ParseClone(string[] args)
    {
        if (args.Length != 11) throw UsageError();
        var first = Coordinate(args, 1);
        var second = Coordinate(args, 4);
        return new CloneBlockCommandRequest(ParseDimension(args[0]), new BedrockBlockBox(first, second), ParseDimension(args[7]), Coordinate(args, 8));
    }

    private static GetBlockCommandRequest ParseGetBlock(string[] args)
    {
        if (args.Length != 4) throw UsageError();
        return new GetBlockCommandRequest(ParseDimension(args[0]), Coordinate(args, 1));
    }

    private static IReadOnlyList<BedrockBlockStorageSpec> ParseStorages(string[] args, int offset, int count)
    {
        var output = new List<BedrockBlockStorageSpec>(count);
        for (var layer = 0; layer < count; layer++)
        {
            var name = args[offset + layer * 2];
            if (!BlockNamePattern.IsMatch(name)) throw new InvalidDataException($"方块名称格式无效：{name}");
            output.Add(new BedrockBlockStorageSpec(name, ParseStates(args[offset + layer * 2 + 1])));
        }
        return output;
    }

    public static IReadOnlyList<NbtNamedTag> ParseStates(string text)
    {
        if (text == "NULL") return [];
        if (string.IsNullOrWhiteSpace(text)) throw new InvalidDataException("NBT 标签不能为空；不添加标签请填写 NULL。");
        var parser = new CommandNbtTextParser(text);
        var tags = parser.ParseNamedTags();
        parser.SkipWhitespace();
        if (!parser.IsAtEnd) throw new InvalidDataException("NBT 标签末尾存在无法识别的内容：" + parser.RemainingText);
        return tags;
    }

    public static int ParseDimension(string text) => text.ToLowerInvariant() switch
    {
        "overworld" => 0,
        "nether" => 1,
        "the_end" => 2,
        _ => throw new InvalidDataException($"维度名称无效：{text}。只能使用 overworld、nether 或 the_end。")
    };

    private static BedrockBlockCoordinate Coordinate(string[] args, int offset)
        => new(ParseInt(args[offset], "X"), ParseInt(args[offset + 1], "Y"), ParseInt(args[offset + 2], "Z"));

    private static int ParseInt(string text, string name)
        => int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value : throw new InvalidDataException($"{name} 必须是 Int32 坐标：{text}");

    private static InvalidDataException UsageError() => new("参数格式错误。\n" + Usage);

    private static string FirstToken(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        var trimmed = text.TrimStart();
        var index = 0;
        while (index < trimmed.Length && !char.IsWhiteSpace(trimmed[index])) index++;
        return trimmed[..index];
    }

    internal static IReadOnlyList<string> TokenizeCommand(string text)
    {
        var tokens = new List<string>();
        var index = 0;
        while (index < text.Length)
        {
            while (index < text.Length && char.IsWhiteSpace(text[index])) index++;
            if (index >= text.Length) break;
            var start = index;
            if (text[index] == '\'')
            {
                var parser = new CommandNbtTextParser(text, index);
                _ = parser.ParseNamedTags();
                index = parser.Position;
                if (index < text.Length && !char.IsWhiteSpace(text[index]))
                    throw new InvalidDataException("NBT 参数后必须使用空格分隔下一个命令参数。");
            }
            else
            {
                while (index < text.Length && !char.IsWhiteSpace(text[index])) index++;
            }
            tokens.Add(text[start..index]);
        }
        return tokens;
    }

    private sealed class CommandNbtTextParser
    {
        private readonly string _text;
        public int Position { get; private set; }
        public bool IsAtEnd => Position >= _text.Length;
        public string RemainingText => IsAtEnd ? string.Empty : _text[Position..];

        public CommandNbtTextParser(string text, int position = 0) { _text = text; Position = position; }

        public void SkipWhitespace() { while (!IsAtEnd && char.IsWhiteSpace(_text[Position])) Position++; }

        public IReadOnlyList<NbtNamedTag> ParseNamedTags(char? closing = null)
        {
            SkipWhitespace();
            if (closing.HasValue && Peek == closing.Value) return [];
            var tags = new List<NbtNamedTag>();
            var names = new HashSet<string>(StringComparer.Ordinal);
            while (true)
            {
                var tag = ParseNamedTag();
                if (!names.Add(tag.Name)) throw new InvalidDataException("同一 Compound 中存在重复 NBT 标签：" + tag.Name);
                tags.Add(tag);
                var endOfTag = Position;
                SkipWhitespace();
                if (closing.HasValue && Peek == closing.Value) break;
                if (Peek != ',')
                {
                    if (!closing.HasValue) Position = endOfTag;
                    break;
                }
                Advance();
                SkipWhitespace();
                if (IsAtEnd || (closing.HasValue && Peek == closing.Value)) throw new InvalidDataException("NBT 标签列表末尾不能有逗号。");
            }
            return tags;
        }

        private NbtNamedTag ParseNamedTag()
        {
            var descriptor = ParseTypeDescriptor();
            var name = ParseQuotedString('"');
            if (name.Length == 0) throw new InvalidDataException("NBT 标签名称不能为空。");
            Expect('='); Expect('"');
            var value = ParsePayload(descriptor, '"');
            Expect('"');
            return new NbtNamedTag(name, value);
        }

        private TypeDescriptor ParseTypeDescriptor()
        {
            var name = ParseQuotedString('\'');
            var type = name switch
            {
                "Byte" => NbtTagType.Byte, "Short" => NbtTagType.Short, "Int" => NbtTagType.Int,
                "Long" => NbtTagType.Long, "Float" => NbtTagType.Float, "Double" => NbtTagType.Double,
                "ByteArray" => NbtTagType.ByteArray, "String" => NbtTagType.String, "List" => NbtTagType.List,
                "Compound" => NbtTagType.Compound, "IntArray" => NbtTagType.IntArray, "LongArray" => NbtTagType.LongArray,
                _ => NbtTagType.End
            };
            if (type == NbtTagType.End) throw new InvalidDataException("不支持的 NBT 类型：" + name);
            return type == NbtTagType.List ? new TypeDescriptor(type, ParseTypeDescriptor()) : new TypeDescriptor(type, null);
        }

        private NbtValue ParsePayload(TypeDescriptor descriptor, char listTerminator)
        {
            if (descriptor.Type == NbtTagType.List)
            {
                var child = descriptor.Child ?? throw new InvalidDataException("List 缺少元素类型。");
                return new NbtListValue(child.Type, ParseListValues(child, listTerminator));
            }
            return descriptor.Type switch
            {
                NbtTagType.Byte => new NbtByteValue(ParseSByte(ReadScalarUntilQuote(), "Byte")),
                NbtTagType.Short => new NbtShortValue(ParseShort(ReadScalarUntilQuote(), "Short")),
                NbtTagType.Int => new NbtIntValue(ParseInt32(ReadScalarUntilQuote(), "Int")),
                NbtTagType.Long => new NbtLongValue(ParseInt64(ReadScalarUntilQuote(), "Long")),
                NbtTagType.Float => new NbtFloatValue(ParseFloat(ReadScalarUntilQuote(), "Float")),
                NbtTagType.Double => new NbtDoubleValue(ParseDouble(ReadScalarUntilQuote(), "Double")),
                NbtTagType.String => new NbtStringValue(ReadEscapedUntil('"')),
                NbtTagType.ByteArray => new NbtByteArrayValue(ParseNumericArray("ByteArray", raw => unchecked((byte)ParseSByte(raw, "ByteArray"))).ToArray()),
                NbtTagType.IntArray => new NbtIntArrayValue(ParseNumericArray("IntArray", raw => ParseInt32(raw, "IntArray"))),
                NbtTagType.LongArray => new NbtLongArrayValue(ParseNumericArray("LongArray", raw => ParseInt64(raw, "LongArray"))),
                NbtTagType.Compound => ParseCompound(),
                _ => throw new InvalidDataException("NBT 类型描述无效。")
            };
        }

        private NbtCompoundValue ParseCompound()
        {
            Expect('{');
            var tags = ParseNamedTags('}');
            Expect('}');
            return new NbtCompoundValue(tags);
        }

        private IReadOnlyList<NbtValue> ParseListValues(TypeDescriptor element, char terminator)
        {
            SkipWhitespace();
            if (Peek == terminator) return [];
            var values = new List<NbtValue>();
            while (true)
            {
                values.Add(ParseListElement(element, terminator));
                SkipWhitespace();
                if (Peek == terminator) break;
                if (Peek != ',') throw new InvalidDataException("List 元素之间必须使用英文逗号分隔。");
                Advance(); SkipWhitespace();
                if (Peek == terminator) throw new InvalidDataException("List 末尾不能有逗号。");
            }
            return values;
        }

        private NbtValue ParseListElement(TypeDescriptor descriptor, char terminator)
        {
            if (descriptor.Type == NbtTagType.List)
            {
                var child = descriptor.Child ?? throw new InvalidDataException("List 缺少元素类型。");
                Expect('['); var values = ParseListValues(child, ']'); Expect(']');
                return new NbtListValue(child.Type, values);
            }
            if (descriptor.Type == NbtTagType.Compound) return ParseCompound();
            if (descriptor.Type == NbtTagType.ByteArray) return new NbtByteArrayValue(ParseNumericArray("ByteArray", raw => unchecked((byte)ParseSByte(raw, "ByteArray"))).ToArray());
            if (descriptor.Type == NbtTagType.IntArray) return new NbtIntArrayValue(ParseNumericArray("IntArray", raw => ParseInt32(raw, "IntArray")));
            if (descriptor.Type == NbtTagType.LongArray) return new NbtLongArrayValue(ParseNumericArray("LongArray", raw => ParseInt64(raw, "LongArray")));
            var raw = ReadListScalar(terminator, descriptor.Type == NbtTagType.String);
            return descriptor.Type switch
            {
                NbtTagType.String => new NbtStringValue(raw),
                NbtTagType.Byte => new NbtByteValue(ParseSByte(raw, "Byte")),
                NbtTagType.Short => new NbtShortValue(ParseShort(raw, "Short")),
                NbtTagType.Int => new NbtIntValue(ParseInt32(raw, "Int")),
                NbtTagType.Long => new NbtLongValue(ParseInt64(raw, "Long")),
                NbtTagType.Float => new NbtFloatValue(ParseFloat(raw, "Float")),
                NbtTagType.Double => new NbtDoubleValue(ParseDouble(raw, "Double")),
                _ => throw new InvalidDataException("List 元素类型无效。")
            };
        }

        private List<T> ParseNumericArray<T>(string type, Func<string, T> convert)
        {
            Expect('['); SkipWhitespace();
            if (Peek == ']') { Advance(); return []; }
            var values = new List<T>();
            while (true)
            {
                var raw = ReadUntilAny(',', ']').Trim();
                if (raw.Length == 0) throw new InvalidDataException(type + " 值无效：" + raw);
                values.Add(convert(raw));
                if (!Peek.HasValue) throw new InvalidDataException(type + " 缺少右中括号。");
                if (Peek == ']') { Advance(); break; }
                Advance(); SkipWhitespace();
                if (Peek == ']') throw new InvalidDataException("数组末尾不能有逗号。");
            }
            return values;
        }

        private string ReadScalarUntilQuote()
        {
            var raw = ReadEscapedUntil('"').Trim();
            if (raw.Length == 0) throw new InvalidDataException("数值 NBT 标签不能为空。");
            return raw;
        }

        private string ReadListScalar(char terminator, bool preserveWhitespace)
        {
            var result = new System.Text.StringBuilder();
            var escaped = false;
            while (Peek is char c)
            {
                if (escaped) { result.Append(UnescapeCharacter(c)); escaped = false; Advance(); continue; }
                if (c == '\\') { escaped = true; Advance(); continue; }
                if (c == ',' || c == terminator) break;
                result.Append(c); Advance();
            }
            if (escaped) result.Append('\\');
            var value = preserveWhitespace ? result.ToString() : result.ToString().Trim();
            if (!preserveWhitespace && value.Length == 0) throw new InvalidDataException("List 中存在空元素。");
            return value;
        }

        private string ReadEscapedUntil(char terminator)
        {
            var result = new System.Text.StringBuilder();
            var escaped = false;
            while (Peek is char c)
            {
                if (escaped) { result.Append(UnescapeCharacter(c)); escaped = false; Advance(); continue; }
                if (c == '\\') { escaped = true; Advance(); continue; }
                if (c == terminator) return result.ToString();
                result.Append(c); Advance();
            }
            throw new InvalidDataException("NBT 字符串缺少结束引号。");
        }

        private static char UnescapeCharacter(char character) => character switch
        {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            _ => character
        };

        private string ReadUntilAny(char first, char second)
        {
            var start = Position;
            while (Peek is char c && c != first && c != second) Advance();
            if (!Peek.HasValue) throw new InvalidDataException("NBT 数组未闭合。");
            return _text[start..Position];
        }

        private string ParseQuotedString(char quote) { Expect(quote); var value = ReadEscapedUntil(quote); Expect(quote); return value; }
        private char? Peek => IsAtEnd ? null : _text[Position];
        private void Advance() { if (!IsAtEnd) Position++; }
        private void Expect(char expected)
        {
            if (Peek != expected) throw new InvalidDataException($"NBT 格式错误：应为 {expected}，当前位置为 {RemainingText[..Math.Min(24, RemainingText.Length)]}");
            Advance();
        }

        private static sbyte ParseSByte(string raw, string type) => sbyte.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) ? value : throw Invalid(type, raw);
        private static short ParseShort(string raw, string type) => short.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) ? value : throw Invalid(type, raw);
        private static int ParseInt32(string raw, string type) => int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) ? value : throw Invalid(type, raw);
        private static long ParseInt64(string raw, string type) => long.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) ? value : throw Invalid(type, raw);
        private static float ParseFloat(string raw, string type) => float.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) && float.IsFinite(value) ? value : throw Invalid(type, raw);
        private static double ParseDouble(string raw, string type) => double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) && double.IsFinite(value) ? value : throw Invalid(type, raw);
        private static InvalidDataException Invalid(string type, string raw) => new($"{type} 值无效：{raw}");
        private sealed record TypeDescriptor(NbtTagType Type, TypeDescriptor? Child);
    }
}
public static class BlockCommandNbtOutputFormatter
{
    public static string BlockState(BedrockBlockState state)
    {
        if (state.Nbt is NbtCompoundValue compound) return NamedTags(compound.Tags);
        var identifier = state.LegacyId is ushort id
            ? BedrockLegacyBlockCatalog.IdentifierForNumericId(id) ?? state.Name
            : state.Name;
        return NamedTags([
            new NbtNamedTag("name", new NbtStringValue(identifier)),
            new NbtNamedTag("legacy_id", new NbtShortValue(unchecked((short)(state.LegacyId ?? 0)))),
            new NbtNamedTag("legacy_data", new NbtByteValue(unchecked((sbyte)(state.LegacyData ?? 0))))
        ]);
    }

    public static string Root(NbtValue value)
        => value is NbtCompoundValue compound ? NamedTags(compound.Tags) : ValueText(value);

    private static string NamedTags(IReadOnlyList<NbtNamedTag> tags)
        => string.Join(",", tags.Select(NamedTag));

    private static string NamedTag(NbtNamedTag tag)
    {
        var name = Escape(tag.Name);
        return tag.Value switch
        {
            NbtCompoundValue compound => $"'Compound'\"{name}\"=\"{{{NamedTags(compound.Tags)}}}\"",
            NbtListValue list => $"{ListDescriptor(list)}\"{name}\"=\"{ListPayload(list.Values, list.ElementType, '\"')}\"",
            NbtStringValue text => $"'String'\"{name}\"=\"{Escape(NbtRawStringCodec.DisplayText(text.Value))}\"",
            _ => $"'{tag.Value.Type}'\"{name}\"=\"{ValueText(tag.Value)}\""
        };
    }

    private static string ListDescriptor(NbtListValue list)
        => "'List'" + ElementDescriptor(list.ElementType, list.Values);

    private static string ElementDescriptor(NbtTagType type, IReadOnlyList<NbtValue> values)
    {
        if (type != NbtTagType.List) return $"'{type}'";
        var child = values.OfType<NbtListValue>().FirstOrDefault();
        // An empty List<List<...>> has no inner runtime value from which the
        // command-only descriptor can be recovered. Byte is a lossless
        // placeholder here because the outer empty list still keeps
        // ElementType=List after parsing.
        return "'List'" + (child is null ? "'Byte'" : ElementDescriptor(child.ElementType, child.Values));
    }

    private static string ValueText(NbtValue value) => value switch
    {
        NbtByteValue item => item.Value.ToString(CultureInfo.InvariantCulture),
        NbtShortValue item => item.Value.ToString(CultureInfo.InvariantCulture),
        NbtIntValue item => item.Value.ToString(CultureInfo.InvariantCulture),
        NbtLongValue item => item.Value.ToString(CultureInfo.InvariantCulture),
        NbtFloatValue item => item.Value.ToString("R", CultureInfo.InvariantCulture),
        NbtDoubleValue item => item.Value.ToString("R", CultureInfo.InvariantCulture),
        NbtByteArrayValue item => "[" + string.Join(",", item.Value.Select(value => unchecked((sbyte)value).ToString(CultureInfo.InvariantCulture))) + "]",
        NbtStringValue item => Escape(NbtRawStringCodec.DisplayText(item.Value)),
        NbtListValue item => ListPayload(item.Values, item.ElementType, ']'),
        NbtCompoundValue item => "{" + NamedTags(item.Tags) + "}",
        NbtIntArrayValue item => "[" + string.Join(",", item.Values.Select(value => value.ToString(CultureInfo.InvariantCulture))) + "]",
        NbtLongArrayValue item => "[" + string.Join(",", item.Values.Select(value => value.ToString(CultureInfo.InvariantCulture))) + "]",
        _ => value.Summary
    };

    private static string ListPayload(IReadOnlyList<NbtValue> values, NbtTagType elementType, char terminator)
        => string.Join(",", values.Select(value => ListElementText(value, elementType, terminator)));

    private static string ListElementText(NbtValue value, NbtTagType elementType, char terminator)
    {
        if (elementType == NbtTagType.List && value is NbtListValue list)
            return "[" + ListPayload(list.Values, list.ElementType, ']') + "]";
        if (elementType == NbtTagType.Compound && value is NbtCompoundValue compound)
            return "{" + NamedTags(compound.Tags) + "}";
        if (elementType == NbtTagType.String && value is NbtStringValue text)
            return EscapeListString(NbtRawStringCodec.DisplayText(text.Value), terminator);
        return ValueText(value);
    }

    private static string EscapeListString(string text, char terminator)
    {
        var builder = new System.Text.StringBuilder(text.Length);
        foreach (var character in text)
        {
            switch (character)
            {
                case '\\': builder.Append("\\\\"); break;
                case '\n': builder.Append("\\n"); break;
                case '\r': builder.Append("\\r"); break;
                case '\t': builder.Append("\\t"); break;
                case ',': builder.Append("\\,"); break;
                case '"': builder.Append("\\\""); break;
                default:
                    if (character == terminator) builder.Append('\\');
                    builder.Append(character);
                    break;
            }
        }
        return builder.ToString();
    }

    private static string Escape(string text)
        => text.Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal)
            .Replace("\t", "\\t", StringComparison.Ordinal);
}
