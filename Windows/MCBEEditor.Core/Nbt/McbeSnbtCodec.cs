using System.Globalization;
using System.Text;

namespace MCBEEditor.Core.Nbt;

/// <summary>Lossless MCBE-SNBT file codec. Structural quotes retain the command text grammar.</summary>
public static class McbeSnbtCodec
{
    private const int MaximumDepth = 256;
    private const int MaximumRootCount = 2_000_000;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;

    public static IReadOnlyList<NbtDocument> Decode(byte[] data)
    {
        ArgumentNullException.ThrowIfNull(data);
        try
        {
            var text = StrictUtf8.GetString(data);
            if (text.StartsWith('\uFEFF')) text = text[1..];
            return new Parser(text).ReadDocuments();
        }
        catch (DecoderFallbackException exception)
        {
            throw new InvalidDataException("MCBE-SNBT 必须使用有效的 UTF-8。", exception);
        }
    }

    public static byte[] Encode(IReadOnlyList<NbtDocument> documents)
    {
        ArgumentNullException.ThrowIfNull(documents);
        if (documents.Count is 0 or > MaximumRootCount)
            throw new InvalidDataException("MCBE-SNBT 根标签数量必须为 1 至 2,000,000。");
        var output = new StringBuilder("[\n");
        for (var i = 0; i < documents.Count; i++)
        {
            if (i != 0) output.Append(",\n");
            WriteNamed(output, documents[i].RootName, documents[i].Root, 0);
        }
        output.Append("\n]\n");
        return StrictUtf8.GetBytes(output.ToString());
    }

    private static void CheckDepth(int depth)
    {
        if (depth > MaximumDepth) throw new InvalidDataException($"MCBE-SNBT 嵌套超过 {MaximumDepth} 层。");
    }

    private static void CheckUnicode(string value)
    {
        for (var i = 0; i < value.Length; i++)
        {
            if (char.IsHighSurrogate(value[i]))
            {
                if (++i >= value.Length || !char.IsLowSurrogate(value[i]))
                    throw new InvalidDataException("MCBE-SNBT 包含未配对的 Unicode 代理项。");
            }
            else if (char.IsLowSurrogate(value[i]))
                throw new InvalidDataException("MCBE-SNBT 包含未配对的 Unicode 代理项。");
        }
    }

    private static void WriteEscaped(StringBuilder output, string value)
    {
        CheckUnicode(value);
        foreach (var character in value)
        {
            output.Append(character switch
            {
                '\\' => "\\\\", '"' => "\\\"", '\'' => "\\'", '\n' => "\\n", '\r' => "\\r",
                '\t' => "\\t", '\b' => "\\b", '\f' => "\\f",
                _ when char.IsControl(character) => "\\u" + ((int)character).ToString("X4", Invariant),
                _ => character.ToString()
            });
        }
    }

    private static void WriteDescriptor(StringBuilder output, NbtValue value)
    {
        if (!Enum.IsDefined(value.Type) || value.Type == NbtTagType.End)
            throw new InvalidDataException("End 不能作为 MCBE-SNBT 值。");
        output.Append('\'').Append(value.Type).Append('\'');
        if (value is NbtListValue list)
        {
            if (!Enum.IsDefined(list.ElementType) || list.ElementType == NbtTagType.End && list.Values.Count != 0)
                throw new InvalidDataException("MCBE-SNBT List 元素类型无效。");
            output.Append('\'').Append(list.ElementType).Append('\'');
        }
    }

    private static void WriteNamed(StringBuilder output, string name, NbtValue value, int depth)
    {
        CheckDepth(depth);
        WriteDescriptor(output, value);
        output.Append('"');
        WriteEscaped(output, name);
        output.Append("\"=\"");
        WritePayload(output, value, depth);
        output.Append('"');
    }

    private static void WriteAnonymous(StringBuilder output, NbtValue value, int depth)
    {
        output.Append('[');
        WriteDescriptor(output, value);
        output.Append("=\"");
        WritePayload(output, value, depth);
        output.Append("\"]");
    }

    private static void WritePayload(StringBuilder output, NbtValue value, int depth)
    {
        CheckDepth(depth);
        switch (value)
        {
            case NbtByteValue item: output.Append(item.Value.ToString(Invariant)); break;
            case NbtShortValue item: output.Append(item.Value.ToString(Invariant)); break;
            case NbtIntValue item: output.Append(item.Value.ToString(Invariant)); break;
            case NbtLongValue item: output.Append(item.Value.ToString(Invariant)); break;
            case NbtFloatValue item:
                output.Append(float.IsNaN(item.Value) ? "bits:" + BitConverter.SingleToUInt32Bits(item.Value).ToString("X8", Invariant)
                    : item.Value == 0 && BitConverter.SingleToInt32Bits(item.Value) < 0 ? "-0" : item.Value.ToString("R", Invariant));
                break;
            case NbtDoubleValue item:
                output.Append(double.IsNaN(item.Value) ? "bits:" + BitConverter.DoubleToUInt64Bits(item.Value).ToString("X16", Invariant)
                    : item.Value == 0 && BitConverter.DoubleToInt64Bits(item.Value) < 0 ? "-0" : item.Value.ToString("R", Invariant));
                break;
            case NbtStringValue item: WriteEscaped(output, item.Value); break;
            case NbtByteArrayValue item:
                output.Append('[').AppendJoin(',', item.Value.Select(x => unchecked((sbyte)x).ToString(Invariant))).Append(']');
                break;
            case NbtIntArrayValue item:
                output.Append('[').AppendJoin(',', item.Values.Select(x => x.ToString(Invariant))).Append(']');
                break;
            case NbtLongArrayValue item:
                output.Append('[').AppendJoin(',', item.Values.Select(x => x.ToString(Invariant))).Append(']');
                break;
            case NbtCompoundValue item:
                output.Append('{');
                for (var i = 0; i < item.Tags.Count; i++)
                {
                    if (i != 0) output.Append(',');
                    WriteNamed(output, item.Tags[i].Name, item.Tags[i].Value, depth + 1);
                }
                output.Append('}');
                break;
            case NbtListValue item:
                if (!Enum.IsDefined(item.ElementType) || item.ElementType == NbtTagType.End && item.Values.Count != 0)
                    throw new InvalidDataException("MCBE-SNBT List 元素类型无效。");
                for (var i = 0; i < item.Values.Count; i++)
                {
                    var child = item.Values[i];
                    if (child.Type != item.ElementType) throw new InvalidDataException("MCBE-SNBT List 包含不同类型的元素。");
                    if (i != 0) output.Append(',');
                    if (child is NbtStringValue or NbtListValue) WriteAnonymous(output, child, depth + 1);
                    else WritePayload(output, child, depth + 1);
                }
                break;
            default: throw new InvalidDataException("未知 MCBE-SNBT 值类型。");
        }
    }

    private sealed record TypeSpec(NbtTagType Type, TypeSpec? Element = null);

    private sealed class Parser(string text)
    {
        private int _position;
        private char Current => _position < text.Length ? text[_position] : '\0';
        private InvalidDataException Error(string message) => new($"MCBE-SNBT（位置 {_position + 1}）：{message}");
        private void SkipSpace() { while (_position < text.Length && char.IsWhiteSpace(Current)) _position++; }
        private void Expect(char character)
        {
            SkipSpace();
            if (_position >= text.Length || Current != character) throw Error($"应为 {character}。");
            _position++;
        }

        public IReadOnlyList<NbtDocument> ReadDocuments()
        {
            SkipSpace();
            if (_position == text.Length) throw Error("文件为空。");
            var documents = new List<NbtDocument>();
            if (Current == '[')
            {
                _position++;
                SkipSpace();
                if (Current == ']') throw Error("根标签序列不能为空。");
                while (true)
                {
                    var tag = ReadNamed(0);
                    documents.Add(new(tag.Name, tag.Value));
                    if (documents.Count > MaximumRootCount) throw Error("根标签数量超过 2,000,000。");
                    SkipSpace();
                    if (Current == ']') { _position++; break; }
                    Expect(',');
                    SkipSpace();
                    if (Current == ']') throw Error("不允许末尾逗号。");
                }
            }
            else
            {
                var compound = Current == '{' ? ReadCompound(0) : new NbtCompoundValue(ReadNamedSequence(null, 0));
                documents.Add(new(string.Empty, compound));
            }
            SkipSpace();
            if (_position != text.Length) throw Error("根标签后有多余内容。");
            return documents;
        }

        private TypeSpec ReadDescriptor()
        {
            var types = new List<NbtTagType>();
            SkipSpace();
            while (Current == '\'')
            {
                _position++;
                var start = _position;
                while (_position < text.Length && Current != '\'') _position++;
                if (_position == text.Length) throw Error("类型引号未闭合。");
                var name = text[start.._position++];
                if (!Enum.TryParse<NbtTagType>(name, false, out var type) || type.ToString() != name)
                    throw Error($"未知标签类型：{name}。");
                if (types.Count != 0 && types[^1] != NbtTagType.List) throw Error("只有 List 可以声明元素类型。");
                types.Add(type);
                if (types.Count > MaximumDepth + 2) throw Error("List 类型嵌套过深。");
                SkipSpace();
            }
            if (types.Count == 0) throw Error("缺少标签类型。");
            TypeSpec? result = null;
            for (var i = types.Count - 1; i >= 0; i--) result = new TypeSpec(types[i], result);
            return result!;
        }

        private NbtNamedTag ReadNamed(int depth)
        {
            CheckDepth(depth);
            var type = ReadDescriptor();
            var name = ReadQuotedString();
            Expect('=');
            return new(name, ReadQuotedPayload(type, depth));
        }

        private IReadOnlyList<NbtNamedTag> ReadNamedSequence(char? closing, int depth)
        {
            var tags = new List<NbtNamedTag>();
            SkipSpace();
            if (closing is not null && Current == closing) return tags;
            while (true)
            {
                tags.Add(ReadNamed(depth + 1));
                SkipSpace();
                if (closing is null && _position == text.Length || closing is not null && Current == closing) break;
                Expect(',');
                SkipSpace();
                if (_position == text.Length || closing is not null && Current == closing) throw Error("不允许末尾逗号。");
            }
            return tags;
        }

        private NbtCompoundValue ReadCompound(int depth)
        {
            CheckDepth(depth);
            Expect('{');
            var tags = ReadNamedSequence('}', depth);
            Expect('}');
            return new(tags);
        }

        private NbtValue ReadQuotedPayload(TypeSpec spec, int depth)
        {
            CheckDepth(depth);
            if (spec.Type == NbtTagType.String) return new NbtStringValue(ReadQuotedString());
            Expect('"');
            NbtValue value;
            if (spec.Type == NbtTagType.Compound) value = ReadCompound(depth);
            else if (spec.Type == NbtTagType.List) value = ReadList(spec, '"', depth);
            else if (spec.Type is NbtTagType.ByteArray or NbtTagType.IntArray or NbtTagType.LongArray) value = ReadArray(spec.Type);
            else value = ReadScalar(spec.Type, ReadToken('"'));
            Expect('"');
            return value;
        }

        private NbtListValue ReadList(TypeSpec spec, char closing, int depth)
        {
            CheckDepth(depth);
            if (spec.Element is null) throw Error("List 缺少元素类型；嵌套 List 元素请使用带类型的匿名值。");
            var values = new List<NbtValue>();
            SkipSpace();
            if (Current == closing) return new(spec.Element.Type, values);
            if (spec.Element.Type == NbtTagType.End) throw Error("End List 必须为空。");
            while (true)
            {
                values.Add(ReadListElement(spec.Element, closing, depth + 1));
                SkipSpace();
                if (Current == closing) break;
                Expect(',');
                SkipSpace();
                if (Current == closing) throw Error("不允许末尾逗号。");
            }
            return new(spec.Element.Type, values);
        }

        private NbtValue ReadListElement(TypeSpec spec, char closing, int depth)
        {
            CheckDepth(depth);
            SkipSpace();
            if (Current == '[')
            {
                var next = _position + 1;
                while (next < text.Length && char.IsWhiteSpace(text[next])) next++;
                if (next < text.Length && text[next] == '\'')
                {
                    _position++;
                    var anonymous = ReadDescriptor();
                    if (anonymous.Type != spec.Type || anonymous.Type == NbtTagType.End)
                        throw Error("匿名值类型与 List 声明类型不一致。");
                    Expect('=');
                    SkipSpace();
                    NbtValue value;
                    if (Current == '[' && anonymous.Type == NbtTagType.List)
                    {
                        // Older entity/getblock output encloses a typed List payload in brackets.
                        _position++;
                        value = ReadList(anonymous, ']', depth);
                        Expect(']');
                    }
                    else value = ReadQuotedPayload(anonymous, depth);
                    Expect(']');
                    return value;
                }
            }
            if (spec.Type == NbtTagType.Compound) return ReadCompound(depth);
            if (spec.Type == NbtTagType.List)
            {
                Expect('[');
                var value = ReadList(spec, ']', depth);
                Expect(']');
                return value;
            }
            if (spec.Type is NbtTagType.ByteArray or NbtTagType.IntArray or NbtTagType.LongArray) return ReadArray(spec.Type);
            if (spec.Type == NbtTagType.String)
            {
                // Layout whitespace is skipped before reading, but escaped whitespace
                // and trailing spaces belong to the String value.
                var value = ReadEscapedText(closing, commaTerminates: true);
                if (value.Length == 0) throw Error("空字符串 List 元素必须使用带类型的匿名值。");
                return new NbtStringValue(value);
            }
            return ReadScalar(spec.Type, ReadToken(closing, commaTerminates: true));
        }

        private NbtValue ReadArray(NbtTagType type)
        {
            Expect('[');
            var values = new List<long>();
            SkipSpace();
            if (Current != ']')
            {
                while (true)
                {
                    var scalarType = type == NbtTagType.ByteArray ? NbtTagType.Byte : type == NbtTagType.IntArray ? NbtTagType.Int : NbtTagType.Long;
                    values.Add(ReadScalar(scalarType, ReadToken(']', commaTerminates: true)).IntegerValue()!.Value);
                    SkipSpace();
                    if (Current == ']') break;
                    Expect(',');
                    SkipSpace();
                    if (Current == ']') throw Error("不允许末尾逗号。");
                }
            }
            Expect(']');
            return type switch
            {
                NbtTagType.ByteArray => new NbtByteArrayValue(values.Select(x => unchecked((byte)x)).ToArray()),
                NbtTagType.IntArray => new NbtIntArrayValue(values.Select(x => (int)x).ToArray()),
                _ => new NbtLongArrayValue(values)
            };
        }

        private string ReadToken(char closing, bool commaTerminates = false)
        {
            SkipSpace();
            var start = _position;
            while (_position < text.Length && Current != closing && (!commaTerminates || Current != ',')) _position++;
            return text[start.._position].Trim();
        }

        private NbtValue ReadScalar(NbtTagType type, string token)
        {
            const NumberStyles integerStyle = NumberStyles.AllowLeadingSign;
            switch (type)
            {
                case NbtTagType.Byte when sbyte.TryParse(token, integerStyle, Invariant, out var value): return new NbtByteValue(value);
                case NbtTagType.Short when short.TryParse(token, integerStyle, Invariant, out var value): return new NbtShortValue(value);
                case NbtTagType.Int when int.TryParse(token, integerStyle, Invariant, out var value): return new NbtIntValue(value);
                case NbtTagType.Long when long.TryParse(token, integerStyle, Invariant, out var value): return new NbtLongValue(value);
                case NbtTagType.Float:
                    if (token.StartsWith("bits:", StringComparison.Ordinal) && token.Length == 13
                        && uint.TryParse(token.AsSpan(5), NumberStyles.AllowHexSpecifier, Invariant, out var bits))
                        return new NbtFloatValue(BitConverter.UInt32BitsToSingle(bits));
                    if (token is "NaN" or "Infinity" or "-Infinity") return new NbtFloatValue(float.Parse(token, Invariant));
                    if (float.TryParse(token, NumberStyles.Float, Invariant, out var single) && float.IsFinite(single)) return new NbtFloatValue(single);
                    break;
                case NbtTagType.Double:
                    if (token.StartsWith("bits:", StringComparison.Ordinal) && token.Length == 21
                        && ulong.TryParse(token.AsSpan(5), NumberStyles.AllowHexSpecifier, Invariant, out var longBits))
                        return new NbtDoubleValue(BitConverter.UInt64BitsToDouble(longBits));
                    if (token is "NaN" or "Infinity" or "-Infinity") return new NbtDoubleValue(double.Parse(token, Invariant));
                    if (double.TryParse(token, NumberStyles.Float, Invariant, out var number) && double.IsFinite(number)) return new NbtDoubleValue(number);
                    break;
            }
            throw Error($"{type} 的值无效或超出范围：{token}。");
        }

        private string ReadQuotedString()
        {
            Expect('"');
            var value = ReadEscapedText('"', commaTerminates: false);
            // Do not skip whitespace inside a String or name.
            if (_position == text.Length || Current != '"') throw Error("字符串引号未闭合。");
            _position++;
            return value;
        }

        private string ReadEscapedText(char closing, bool commaTerminates)
        {
            var value = new StringBuilder();
            while (_position < text.Length && Current != closing && (!commaTerminates || Current != ','))
            {
                var character = text[_position++];
                if (character == '\\')
                {
                    if (_position == text.Length) throw Error("转义未完成。");
                    var escaped = text[_position++];
                    if (escaped == 'u')
                    {
                        if (_position + 4 > text.Length || !ushort.TryParse(text.AsSpan(_position, 4), NumberStyles.AllowHexSpecifier, Invariant, out var code))
                            throw Error("Unicode 转义必须为四位十六进制数。");
                        _position += 4;
                        value.Append((char)code);
                    }
                    else value.Append(escaped switch
                    {
                        '\\' or '"' or '\'' or ',' or '[' or ']' or '{' or '}' => escaped,
                        'n' => '\n', 'r' => '\r', 't' => '\t', 'b' => '\b', 'f' => '\f',
                        _ => throw Error($"未知转义：\\{escaped}。")
                    });
                }
                else
                {
                    if (character < 0x20 || character == '"') throw Error("字符串中的控制字符或引号必须转义。");
                    value.Append(character);
                }
            }
            var result = value.ToString();
            CheckUnicode(result);
            return result;
        }
    }
}
