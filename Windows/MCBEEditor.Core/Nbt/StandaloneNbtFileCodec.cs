using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Nbt;

public enum StructureFileFormat { Mcstructure, Nbt, Json }

public enum StandaloneNbtStorageKind { Single, Consecutive }

public sealed record StandaloneNbtFile(
    string OriginalFilename,
    string OriginalExtension,
    NbtEncoding OriginalEncoding,
    bool OriginalWasJson,
    bool WasCompressed,
    IReadOnlyList<NbtDocument> Documents)
{
    public StandaloneNbtStorageKind StorageKind => Documents.Count == 1 ? StandaloneNbtStorageKind.Single : StandaloneNbtStorageKind.Consecutive;

    public string FormatDescription
    {
        get
        {
            var layout = StorageKind == StandaloneNbtStorageKind.Single ? "单根 NBT" : $"连续 NBT（{Documents.Count} 个根标签）";
            if (OriginalWasJson) return layout + " · JSON NBT";
            return layout + " · " + EncodingDescription(OriginalEncoding) + (WasCompressed ? " · 原文件为 GZip/Zlib" : string.Empty);
        }
    }

    public static string EncodingDescription(NbtEncoding encoding) => encoding switch
    {
        NbtEncoding.BigEndian => "Big Endian",
        NbtEncoding.LittleEndian => "Little Endian",
        NbtEncoding.LittleEndianVarInt => "Little Endian VarInt",
        _ => encoding.ToString()
    };
}

public static class StandaloneNbtFileCodec
{
    private const int MaximumRootCount = 2_000_000;
    private const long MaximumInflatedBytes = 512L * 1024 * 1024;

    public static StandaloneNbtFile Decode(byte[] originalData, string filename)
    {
        ArgumentNullException.ThrowIfNull(originalData);
        if (originalData.Length == 0) throw new InvalidDataException("NBT/JSON 文件为空。");
        filename ??= "file.nbt";
        var ext = Path.GetExtension(filename).TrimStart('.').ToLowerInvariant();
        var first = originalData.FirstOrDefault(value => value is not (0x20 or 0x09 or 0x0A or 0x0D));
        if (ext == "json" || first is 0x7B or 0x5B)
        {
            try
            {
                var documents = NbtJsonCodec.Decode(originalData);
                if (documents.Count == 0) throw new InvalidDataException("JSON 中没有 NBT 根标签。");
                return new StandaloneNbtFile(filename, ext, NbtEncoding.LittleEndian, true, false, documents);
            }
            catch when (ext != "json")
            {
                // Binary NBT can begin with a byte resembling JSON. Continue binary probing.
            }
        }

        var payloads = new List<(byte[] Data, bool Compressed)> { (originalData, false) };
        if (TryInflateWrapped(originalData, out var inflated) && inflated.Length > 0 && !inflated.AsSpan().SequenceEqual(originalData))
            payloads.Insert(0, (inflated, true));

        var failures = new List<string>();
        foreach (var payload in payloads)
        {
            foreach (var encoding in PreferredEncodings(filename))
            {
                try
                {
                    var documents = DecodeEveryRoot(payload.Data, encoding);
                    if (documents.Count == 0) throw new InvalidDataException("没有发现 NBT 根标签。");
                    return new StandaloneNbtFile(filename, ext, encoding, false, payload.Compressed, documents);
                }
                catch (Exception ex) when (ex is InvalidDataException or EndOfStreamException or OverflowException)
                {
                    failures.Add($"{(payload.Compressed ? "GZip/Zlib" : "未压缩")} {StandaloneNbtFile.EncodingDescription(encoding)}：{ex.Message}");
                }
            }
        }
        throw new InvalidDataException("无法识别该文件。支持 JSON NBT、Big Endian、Little Endian、Little Endian VarInt、连续多根 NBT 以及 GZip/Zlib。\n" + string.Join("\n", failures.Take(6)));
    }

    public static byte[] Encode(IReadOnlyList<NbtDocument> documents, NbtEncoding encoding)
    {
        ArgumentNullException.ThrowIfNull(documents);
        if (documents.Count == 0) throw new InvalidDataException("没有可导出的 NBT 根标签。");
        using var stream = new MemoryStream();
        foreach (var document in documents)
        {
            var bytes = BedrockNbtCodec.Encode(document, encoding);
            stream.Write(bytes, 0, bytes.Length);
        }
        return stream.ToArray();
    }

    public static byte[] EncodeStructure(NbtDocument document, StructureFileFormat format) => format switch
    {
        StructureFileFormat.Mcstructure => EncodeAsMcStructure([document]).Data,
        StructureFileFormat.Nbt => Encode([document], NbtEncoding.BigEndian),
        StructureFileFormat.Json => EncodeJson([document]),
        _ => throw new InvalidDataException("未知结构导出格式。")
    };

    public static byte[] EncodeJson(IReadOnlyList<NbtDocument> documents)
    {
        ArgumentNullException.ThrowIfNull(documents);
        if (documents.Count == 0) throw new InvalidDataException("没有可导出的 NBT 根标签。");
        var root = new JsonObject
        {
            ["format"] = "mcbeeditor-nbt-json",
            ["documents"] = new JsonArray(documents.Select(DocumentNode).ToArray())
        };
        return Encoding.UTF8.GetBytes(root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    public static (byte[] Data, StructureImportResult Result) EncodeAsMcStructure(IReadOnlyList<NbtDocument> documents)
    {
        ArgumentNullException.ThrowIfNull(documents);
        if (documents.Count != 1) throw new NotSupportedException("只有单根 Java 结构 NBT 或 Bedrock mcstructure 可以转换为 mcstructure；连续 NBT 文件不能整体转换为结构。");
        var conversion = JavaStructureConverter.ConvertIfNeeded(documents[0]);
        return (BedrockNbtCodec.Encode(conversion.Document, NbtEncoding.LittleEndian), conversion.Result);
    }

    public static bool TryInflateWrapped(byte[] source, out byte[] inflated)
    {
        ArgumentNullException.ThrowIfNull(source);
        inflated = Array.Empty<byte>();
        if (source.Length < 2) return false;
        foreach (var kind in new[] { 0, 1 })
        {
            try
            {
                using var input = new MemoryStream(source, writable: false);
                using Stream decompressor = kind == 0
                    ? new GZipStream(input, CompressionMode.Decompress, leaveOpen: false)
                    : new ZLibStream(input, CompressionMode.Decompress, leaveOpen: false);
                using var output = new MemoryStream(Math.Min(Math.Max(source.Length * 4, 64 * 1024), 16 * 1024 * 1024));
                var buffer = new byte[64 * 1024];
                while (true)
                {
                    var read = decompressor.Read(buffer, 0, buffer.Length);
                    if (read <= 0) break;
                    if (output.Length + read > MaximumInflatedBytes) throw new InvalidDataException("GZip/Zlib 解压结果超过 512 MiB 安全上限。");
                    output.Write(buffer, 0, read);
                }
                inflated = output.ToArray();
                if (inflated.Length != 0) return true;
            }
            catch (Exception ex) when (ex is InvalidDataException or IOException)
            {
                // Try the other wrapper. Random uncompressed NBT normally reaches this path.
            }
        }
        inflated = Array.Empty<byte>();
        return false;
    }

    private static IReadOnlyList<NbtDocument> DecodeEveryRoot(byte[] data, NbtEncoding encoding)
    {
        var documents = new List<NbtDocument>();
        var offset = 0;
        while (offset < data.Length)
        {
            if (AllZero(data.AsSpan(offset))) break;
            var document = BedrockNbtCodec.DecodeOne(data.AsSpan(offset), out var consumed, encoding, 256);
            if (consumed <= 0) throw new InvalidDataException($"NBT 解析器在偏移 {offset} 没有前进。");
            documents.Add(document);
            if (documents.Count > MaximumRootCount) throw new InvalidDataException("连续 NBT 根标签数量超过安全上限。");
            offset += consumed;
        }
        return documents;
    }

    private static IEnumerable<NbtEncoding> PreferredEncodings(string filename)
    {
        if (string.Equals(Path.GetExtension(filename), ".mcstructure", StringComparison.OrdinalIgnoreCase))
            return new[] { NbtEncoding.LittleEndian, NbtEncoding.LittleEndianVarInt, NbtEncoding.BigEndian };
        return new[] { NbtEncoding.BigEndian, NbtEncoding.LittleEndian, NbtEncoding.LittleEndianVarInt };
    }

    private static bool AllZero(ReadOnlySpan<byte> data)
    {
        foreach (var value in data) if (value != 0) return false;
        return true;
    }

    private static JsonNode DocumentNode(NbtDocument document) => new JsonObject
    {
        ["name"] = document.RootName,
        ["root"] = ValueNode(document.Root)
    };

    private static JsonNode ValueNode(NbtValue value)
    {
        var node = new JsonObject { ["type"] = TypeName(value.Type) };
        node["value"] = value switch
        {
            NbtByteValue v => JsonValue.Create(v.Value),
            NbtShortValue v => JsonValue.Create(v.Value),
            NbtIntValue v => JsonValue.Create(v.Value),
            NbtLongValue v => JsonValue.Create(v.Value),
            NbtFloatValue v => JsonValue.Create(v.Value),
            NbtDoubleValue v => JsonValue.Create(v.Value),
            NbtStringValue v => JsonValue.Create(v.Value),
            NbtByteArrayValue v => new JsonArray(v.Value.Select(b => JsonValue.Create(unchecked((sbyte)b))).ToArray()),
            NbtIntArrayValue v => new JsonArray(v.Values.Select(i => JsonValue.Create(i)).ToArray()),
            NbtLongArrayValue v => new JsonArray(v.Values.Select(i => JsonValue.Create(i)).ToArray()),
            NbtCompoundValue v => CompoundNode(v),
            NbtListValue v => new JsonObject
            {
                ["type"] = TypeName(v.ElementType),
                ["value"] = new JsonArray(v.Values.Select(ValueNode).ToArray())
            },
            _ => throw new InvalidDataException("不支持导出的 NBT 类型：" + value.Type)
        };
        return node;
    }


    private static JsonNode CompoundNode(NbtCompoundValue compound)
    {
        var node = new JsonObject();
        foreach (var tag in compound.Tags.OrderBy(tag => tag.Name, StringComparer.Ordinal)) node[tag.Name] = ValueNode(tag.Value);
        return node;
    }

    private static string TypeName(NbtTagType type) => type switch
    {
        NbtTagType.Byte => "byte", NbtTagType.Short => "short", NbtTagType.Int => "int", NbtTagType.Long => "long",
        NbtTagType.Float => "float", NbtTagType.Double => "double", NbtTagType.ByteArray => "byteArray", NbtTagType.String => "string",
        NbtTagType.List => "list", NbtTagType.Compound => "compound", NbtTagType.IntArray => "intArray", NbtTagType.LongArray => "longArray",
        _ => "end"
    };
}
