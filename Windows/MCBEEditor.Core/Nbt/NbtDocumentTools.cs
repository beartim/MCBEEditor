using System.IO;
using System.Globalization;

namespace MCBEEditor.Core.Nbt;

public sealed record NbtSearchResult(string Path, string Name, NbtTagType Type, string ValueText, int MatchRank);

public static class NbtDocumentTools
{
    public static IReadOnlyList<NbtSearchResult> Search(NbtDocument document, string query, int limit = 500, string? rootAlias = null)
    {
        ArgumentNullException.ThrowIfNull(document);
        if (limit < 1) throw new ArgumentOutOfRangeException(nameof(limit));
        query = query?.Trim() ?? string.Empty;
        if (query.Length == 0) return Array.Empty<NbtSearchResult>();

        var results = new List<NbtSearchResult>();
        var rootName = string.IsNullOrEmpty(document.RootName) ? "<root>" : document.RootName;
        int bestRank = int.MaxValue;
        Visit(document.Root, rootName, NbtTagPath.Root, query, results, ref bestRank, rootAlias);
        if (results.Count == 0) return Array.Empty<NbtSearchResult>();
        return results.OrderBy(item => item.Path, StringComparer.OrdinalIgnoreCase).Take(limit).ToArray();
    }

    public static NbtValue DeepClone(NbtValue value) => value switch
    {
        NbtByteValue v => new NbtByteValue(v.Value),
        NbtShortValue v => new NbtShortValue(v.Value),
        NbtIntValue v => new NbtIntValue(v.Value),
        NbtLongValue v => new NbtLongValue(v.Value),
        NbtFloatValue v => new NbtFloatValue(v.Value),
        NbtDoubleValue v => new NbtDoubleValue(v.Value),
        NbtByteArrayValue v => new NbtByteArrayValue(v.Value.ToArray()),
        NbtStringValue v => new NbtStringValue(v.Value),
        NbtListValue v => new NbtListValue(v.ElementType, v.Values.Select(DeepClone).ToArray()),
        NbtCompoundValue v => new NbtCompoundValue(v.Tags.Select(tag => new NbtNamedTag(tag.Name, DeepClone(tag.Value))).ToArray()),
        NbtIntArrayValue v => new NbtIntArrayValue(v.Values.ToArray()),
        NbtLongArrayValue v => new NbtLongArrayValue(v.Values.ToArray()),
        _ => throw new InvalidDataException($"Unsupported NBT value type: {value.GetType().Name}")
    };

    public static string SearchValueText(NbtValue value) => value switch
    {
        NbtByteValue v => v.Value.ToString(CultureInfo.InvariantCulture),
        NbtShortValue v => v.Value.ToString(CultureInfo.InvariantCulture),
        NbtIntValue v => v.Value.ToString(CultureInfo.InvariantCulture),
        NbtLongValue v => v.Value.ToString(CultureInfo.InvariantCulture),
        NbtFloatValue v => v.Value.ToString("R", CultureInfo.InvariantCulture),
        NbtDoubleValue v => v.Value.ToString("R", CultureInfo.InvariantCulture),
        NbtStringValue v => NbtRawStringCodec.DisplayText(v.Value),
        NbtByteArrayValue v => string.Join(' ', v.Value.Take(64).Select(b => b.ToString("x2", CultureInfo.InvariantCulture))),
        NbtIntArrayValue v => string.Join(',', v.Values.Take(64)),
        NbtLongArrayValue v => string.Join(',', v.Values.Take(64)),
        _ => string.Empty
    };

    private static void Visit(NbtValue value, string name, string path, string query, List<NbtSearchResult> results,
        ref int bestRank, string? alias = null)
    {
        var valueText = SearchValueText(value);
        var rank = MatchRank(name, valueText, value.Type.ToString(), query);
        if (alias?.Contains(query, StringComparison.OrdinalIgnoreCase) == true) rank = 0;
        if (rank >= 0 && rank <= bestRank)
        {
            if (rank < bestRank) { results.Clear(); bestRank = rank; }
            results.Add(new NbtSearchResult(path, name, value.Type, valueText, rank));
        }

        if (value is NbtCompoundValue compound)
        {
            var occurrences = new Dictionary<string, int>(StringComparer.Ordinal);
            foreach (var tag in compound.Tags)
            {
                int occurrence = NbtTagPath.NextOccurrence(occurrences, tag.Name);
                Visit(tag.Value, tag.Name, NbtTagPath.AppendName(path, tag.Name, occurrence), query, results, ref bestRank);
            }
        }
        else if (value is NbtListValue list)
        {
            for (var index = 0; index < list.Values.Count; index++)
            {
                var childName = $"[{index}]";
                Visit(list.Values[index], childName, path + childName, query, results, ref bestRank);
            }
        }
    }

    private static int MatchRank(string name, string value, string type, string query)
    {
        if (name.Contains(query, StringComparison.OrdinalIgnoreCase)) return 0;
        if (value.Contains(query, StringComparison.OrdinalIgnoreCase)) return 1;
        if (type.Contains(query, StringComparison.OrdinalIgnoreCase)) return 2;
        return -1;
    }
}

public static class NbtFileCodec
{
    public static (NbtDocument Document, NbtEncoding Encoding) DecodeSingle(ReadOnlySpan<byte> data, NbtEncoding? preferred = null)
    {
        if (data.Length == 0) throw new InvalidDataException("NBT file is empty.");
        var candidates = new List<NbtEncoding>();
        if (preferred.HasValue) candidates.Add(preferred.Value);
        foreach (var encoding in new[] { NbtEncoding.LittleEndian, NbtEncoding.LittleEndianVarInt, NbtEncoding.BigEndian })
            if (!candidates.Contains(encoding)) candidates.Add(encoding);

        Exception? last = null;
        foreach (var encoding in candidates)
        {
            try
            {
                var document = BedrockNbtCodec.DecodeOne(data, out var consumed, encoding);
                if (consumed == data.Length || AllZero(data[consumed..])) return (document, encoding);
            }
            catch (Exception ex) when (ex is InvalidDataException or EndOfStreamException or OverflowException)
            {
                last = ex;
            }
        }
        throw new InvalidDataException("Unable to decode the file as a single Bedrock NBT document.", last);
    }

    public static byte[] Encode(NbtDocument document, NbtEncoding encoding) => BedrockNbtCodec.Encode(document, encoding);

    private static bool AllZero(ReadOnlySpan<byte> data)
    {
        foreach (var value in data) if (value != 0) return false;
        return true;
    }
}
