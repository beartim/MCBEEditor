using System.Globalization;
using System.Text.Json;

namespace MCBEEditor.Core.Nbt;

/// <summary>
/// Typed/ordinary JSON to NBT decoder used by Windows entity import.
/// It accepts MCBEEditor/Blocktopograph typed JSON, selected-entity tag-list
/// JSON and ordinary JSON whose values can be represented losslessly as NBT.
/// </summary>
public static class NbtJsonCodec
{
    private const string Format = "mcbeeditor-nbt-json";
    private const string LegacyFormat = "blocktopograph-nbt-json";

    public static IReadOnlyList<NbtDocument> DecodeEntityDocuments(ReadOnlySpan<byte> data)
    {
        using var json = Parse(data);
        var root = json.RootElement;
        if (root.ValueKind == JsonValueKind.Object
            && SupportedFormat(root)
            && root.TryGetProperty("documents", out var documents)
            && documents.ValueKind == JsonValueKind.Array
            && documents.GetArrayLength() > 0)
        {
            var entries = documents.EnumerateArray().ToArray();
            var selectedLayout = entries.All(IsNamedTypedTag)
                && (entries.Any(item => CommonEntityNames.Contains(item.GetProperty("name").GetString() ?? string.Empty))
                    || entries.Any(item => !string.Equals(item.GetProperty("type").GetString(), "compound", StringComparison.OrdinalIgnoreCase)));
            if (selectedLayout)
            {
                var tags = entries.Select((item, index) =>
                {
                    var name = item.GetProperty("name").GetString()
                        ?? throw new InvalidDataException($"实体 JSON documents[{index}] 缺少 name。");
                    return new NbtNamedTag(name, DecodeTag(item, $"$.documents[{index}]"));
                }).ToArray();
                return [new NbtDocument(string.Empty, new NbtCompoundValue(tags))];
            }
        }
        return DecodeElement(root);
    }

    public static IReadOnlyList<NbtDocument> Decode(ReadOnlySpan<byte> data)
    {
        using var json = Parse(data);
        return DecodeElement(json.RootElement);
    }

    private static JsonDocument Parse(ReadOnlySpan<byte> data)
    {
        if (data.Length == 0) throw new InvalidDataException("JSON 文件为空。");
        try
        {
            return JsonDocument.Parse(data.ToArray());
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException("JSON 解析失败：" + ex.Message, ex);
        }
    }

    private static IReadOnlyList<NbtDocument> DecodeElement(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("documents", out var docs) && docs.ValueKind == JsonValueKind.Array)
        {
            if (docs.GetArrayLength() == 0) throw new InvalidDataException("JSON 中没有 NBT 根标签。");
            return docs.EnumerateArray().Select((item, index) => DecodeDocument(item, $"root_{index}")).ToArray();
        }
        if (root.ValueKind == JsonValueKind.Array)
        {
            var values = root.EnumerateArray().ToArray();
            if (values.Length > 0 && values.All(item => item.ValueKind == JsonValueKind.Object && item.TryGetProperty("type", out _)))
                return values.Select((item, index) => DecodeDocument(item, $"root_{index}")).ToArray();
        }
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("type", out _))
            return [DecodeDocument(root, string.Empty)];
        return [new NbtDocument(string.Empty, InferValue(root, "$"))];
    }

    private static NbtDocument DecodeDocument(JsonElement element, string fallbackName)
    {
        if (element.ValueKind != JsonValueKind.Object) throw new InvalidDataException("NBT JSON 根标签必须是对象。");
        var name = element.TryGetProperty("name", out var nameValue) && nameValue.ValueKind == JsonValueKind.String
            ? nameValue.GetString() ?? fallbackName
            : element.TryGetProperty("rootName", out var rootNameValue) && rootNameValue.ValueKind == JsonValueKind.String
                ? rootNameValue.GetString() ?? fallbackName
                : fallbackName;
        if (element.TryGetProperty("root", out var nested)) return new NbtDocument(name, DecodeTag(nested, "$root"));
        return new NbtDocument(name, DecodeTag(element, "$"));
    }

    private static NbtValue DecodeTag(JsonElement element, string path)
    {
        if (element.ValueKind != JsonValueKind.Object
            || !element.TryGetProperty("type", out var typeValue)
            || typeValue.ValueKind != JsonValueKind.String)
            return InferValue(element, path);

        var typeName = typeValue.GetString() ?? string.Empty;
        var type = ParseTagType(typeName) ?? throw new InvalidDataException($"{path} 使用了未知 NBT 类型 {typeName}。");
        if (type == NbtTagType.End) throw new InvalidDataException($"{path} 不能使用 End 作为实际标签。");
        if (!element.TryGetProperty("value", out var payload)) throw new InvalidDataException($"{path} 缺少 value。");
        return DecodePayload(type, payload, path);
    }

    private static NbtValue DecodePayload(NbtTagType type, JsonElement payload, string path)
    {
        switch (type)
        {
            case NbtTagType.Byte:
                return new NbtByteValue((sbyte)Integer(payload, path, sbyte.MinValue, sbyte.MaxValue));
            case NbtTagType.Short:
                return new NbtShortValue((short)Integer(payload, path, short.MinValue, short.MaxValue));
            case NbtTagType.Int:
                return new NbtIntValue((int)Integer(payload, path, int.MinValue, int.MaxValue));
            case NbtTagType.Long:
                return new NbtLongValue(Integer(payload, path, long.MinValue, long.MaxValue));
            case NbtTagType.Float:
                return new NbtFloatValue((float)Floating(payload, path));
            case NbtTagType.Double:
                return new NbtDoubleValue(Floating(payload, path));
            case NbtTagType.String:
                if (payload.ValueKind != JsonValueKind.String) throw TypeError(path, "字符串");
                return new NbtStringValue(payload.GetString() ?? string.Empty);
            case NbtTagType.ByteArray:
                if (payload.ValueKind != JsonValueKind.Array) throw TypeError(path, "整数数组");
                return new NbtByteArrayValue(payload.EnumerateArray().Select((item, index) =>
                    unchecked((byte)(sbyte)Integer(item, $"{path}[{index}]", sbyte.MinValue, sbyte.MaxValue))).ToArray());
            case NbtTagType.IntArray:
                if (payload.ValueKind != JsonValueKind.Array) throw TypeError(path, "整数数组");
                return new NbtIntArrayValue(payload.EnumerateArray().Select((item, index) =>
                    (int)Integer(item, $"{path}[{index}]", int.MinValue, int.MaxValue)).ToArray());
            case NbtTagType.LongArray:
                if (payload.ValueKind != JsonValueKind.Array) throw TypeError(path, "长整数数组");
                return new NbtLongArrayValue(payload.EnumerateArray().Select((item, index) =>
                    Integer(item, $"{path}[{index}]", long.MinValue, long.MaxValue)).ToArray());
            case NbtTagType.Compound:
                if (payload.ValueKind != JsonValueKind.Object) throw TypeError(path, "对象");
                return new NbtCompoundValue(payload.EnumerateObject()
                    .OrderBy(property => property.Name, StringComparer.Ordinal)
                    .Select(property => new NbtNamedTag(property.Name, DecodeTag(property.Value, path + "." + property.Name)))
                    .ToArray());
            case NbtTagType.List:
                return DecodeList(payload, path);
            default:
                throw new InvalidDataException($"{path} 的 {type} 类型没有可解析值。");
        }
    }

    private static NbtValue DecodeList(JsonElement payload, string path)
    {
        if (payload.ValueKind == JsonValueKind.Object
            && payload.TryGetProperty("type", out var elementTypeValue)
            && elementTypeValue.ValueKind == JsonValueKind.String)
        {
            var rawType = elementTypeValue.GetString() ?? string.Empty;
            var elementType = ParseTagType(rawType) ?? throw new InvalidDataException($"{path} 的 List 使用了未知元素类型 {rawType}。");
            if (!payload.TryGetProperty("value", out var values) || values.ValueKind != JsonValueKind.Array)
                throw TypeError(path, "List value 数组");
            var items = values.EnumerateArray().ToArray();
            if (elementType == NbtTagType.End)
            {
                if (items.Length != 0) throw new InvalidDataException($"{path} 的非空 List 不能使用 End 元素类型。");
                return new NbtListValue(NbtTagType.End, []);
            }
            var decoded = items.Select((item, index) =>
            {
                // Legacy iOS JSON omits the outer tag around nested List payloads.
                var legacyList = elementType == NbtTagType.List && item.ValueKind == JsonValueKind.Object
                    && item.TryGetProperty("value", out var inner) && inner.ValueKind == JsonValueKind.Array;
                var tagged = item.ValueKind == JsonValueKind.Object && item.TryGetProperty("type", out var tagType)
                    && tagType.ValueKind == JsonValueKind.String;
                NbtValue value;
                if (legacyList)
                {
                    try { value = DecodePayload(NbtTagType.List, item, $"{path}[{index}]"); }
                    catch (InvalidDataException) when (tagged)
                    { value = DecodeTag(item, $"{path}[{index}]"); }
                }
                else value = tagged ? DecodeTag(item, $"{path}[{index}]")
                    : DecodePayload(elementType, item, $"{path}[{index}]");
                if (value.Type != elementType) throw new InvalidDataException($"{path}[{index}] 类型与 List 元素类型不一致。");
                return value;
            }).ToArray();
            return new NbtListValue(elementType, decoded);
        }

        if (payload.ValueKind != JsonValueKind.Array) throw TypeError(path, "List 对象或数组");
        var inferred = payload.EnumerateArray().Select((item, index) => DecodeTag(item, $"{path}[{index}]")).ToArray();
        if (inferred.Length == 0) return new NbtListValue(NbtTagType.End, []);
        var type = inferred[0].Type;
        if (inferred.Any(value => value.Type != type)) throw new InvalidDataException($"{path} 的 List 元素类型不一致。");
        return new NbtListValue(type, inferred);
    }

    private static NbtValue InferValue(JsonElement element, string path)
        => element.ValueKind switch
        {
            JsonValueKind.String => new NbtStringValue(element.GetString() ?? string.Empty),
            JsonValueKind.True => new NbtByteValue(1),
            JsonValueKind.False => new NbtByteValue(0),
            JsonValueKind.Number => InferNumber(element),
            JsonValueKind.Object => new NbtCompoundValue(element.EnumerateObject()
                .OrderBy(property => property.Name, StringComparer.Ordinal)
                .Select(property => new NbtNamedTag(property.Name, InferValue(property.Value, path + "." + property.Name)))
                .ToArray()),
            JsonValueKind.Array => InferArray(element, path),
            JsonValueKind.Null => throw new InvalidDataException($"{path} 是 null；NBT 没有 null 标签。"),
            _ => throw new InvalidDataException($"{path} 包含无法转换为 NBT 的 JSON 值。")
        };

    private static NbtValue InferNumber(JsonElement element)
    {
        if (element.TryGetInt32(out var i32)) return new NbtIntValue(i32);
        if (element.TryGetInt64(out var i64)) return new NbtLongValue(i64);
        var value = element.GetDouble();
        if (!double.IsFinite(value)) throw new InvalidDataException("JSON 数字不是有限值。");
        return new NbtDoubleValue(value);
    }

    private static NbtValue InferArray(JsonElement element, string path)
    {
        var values = element.EnumerateArray().Select((item, index) => InferValue(item, $"{path}[{index}]")).ToArray();
        if (values.Length == 0) return new NbtListValue(NbtTagType.End, []);
        var type = values[0].Type;
        if (values.Any(value => value.Type != type)) throw new InvalidDataException($"{path} 是混合类型 JSON 数组；NBT List 必须使用相同元素类型。");
        return new NbtListValue(type, values);
    }

    private static long Integer(JsonElement element, string path, long minimum, long maximum)
    {
        long value;
        if (element.ValueKind == JsonValueKind.String)
        {
            if (!long.TryParse(element.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value))
                throw TypeError(path, $"{minimum}...{maximum} 的整数");
        }
        else if (element.ValueKind == JsonValueKind.Number && element.TryGetInt64(out value))
        {
        }
        else
        {
            throw TypeError(path, $"{minimum}...{maximum} 的整数");
        }
        if (value < minimum || value > maximum) throw TypeError(path, $"{minimum}...{maximum} 的整数");
        return value;
    }

    private static double Floating(JsonElement element, string path)
    {
        double value;
        if (element.ValueKind == JsonValueKind.Number) value = element.GetDouble();
        else if (element.ValueKind == JsonValueKind.String
                 && double.TryParse(element.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed)) value = parsed;
        else throw TypeError(path, "数字");
        if (!double.IsFinite(value)) throw TypeError(path, "有限数字");
        return value;
    }

    private static NbtTagType? ParseTagType(string value)
        => value.Trim().Replace("_", string.Empty, StringComparison.Ordinal).Replace("-", string.Empty, StringComparison.Ordinal).ToLowerInvariant() switch
        {
            "end" => NbtTagType.End,
            "byte" => NbtTagType.Byte,
            "short" => NbtTagType.Short,
            "int" or "integer" => NbtTagType.Int,
            "long" => NbtTagType.Long,
            "float" => NbtTagType.Float,
            "double" => NbtTagType.Double,
            "bytearray" => NbtTagType.ByteArray,
            "string" => NbtTagType.String,
            "list" => NbtTagType.List,
            "compound" => NbtTagType.Compound,
            "intarray" => NbtTagType.IntArray,
            "longarray" => NbtTagType.LongArray,
            _ => null
        };

    private static bool SupportedFormat(JsonElement root)
        => root.TryGetProperty("format", out var format) && format.ValueKind == JsonValueKind.String
            && (string.Equals(format.GetString(), Format, StringComparison.Ordinal)
                || string.Equals(format.GetString(), LegacyFormat, StringComparison.Ordinal));

    private static bool IsNamedTypedTag(JsonElement element)
        => element.ValueKind == JsonValueKind.Object
            && element.TryGetProperty("name", out var name) && name.ValueKind == JsonValueKind.String
            && element.TryGetProperty("type", out var type) && type.ValueKind == JsonValueKind.String
            && element.TryGetProperty("value", out _);

    private static InvalidDataException TypeError(string path, string expected)
        => new($"{path} 应为{expected}。");

    private static readonly HashSet<string> CommonEntityNames = new(StringComparer.Ordinal)
    {
        "UniqueID", "identifier", "definitions", "Pos", "Motion", "Rotation", "Attributes"
    };
}
