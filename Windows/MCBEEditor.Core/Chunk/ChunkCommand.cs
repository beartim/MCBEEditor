namespace MCBEEditor.Core.Chunk;

public enum ChunkCommandKind
{
    Query,
    Empty,
    Regenerate
}

public sealed record ChunkCommandRequest(ChunkCommandKind Kind, int? Dimension, int? X, int? Z)
{
    public bool IsDestructive => Kind is ChunkCommandKind.Empty or ChunkCommandKind.Regenerate;
}

public static class ChunkCommandParser
{
    public const string Usage =
        "chunk query [维度 [区块X 区块Z]]\n" +
        "chunk empty 维度 区块X 区块Z\n" +
        "chunk regenerate 维度 区块X 区块Z\n" +
        "维度：overworld / nether / the_end";

    public static ChunkCommandRequest Parse(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) throw new InvalidDataException("命令不能为空");
        var parts = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length < 2 || !parts[0].Equals("chunk", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException(" 当前只开放 chunk 命令。\n" + Usage);

        var action = parts[1].ToLowerInvariant();
        if (action == "query")
        {
            return parts.Length switch
            {
                2 => new ChunkCommandRequest(ChunkCommandKind.Query, null, null, null),
                3 => new ChunkCommandRequest(ChunkCommandKind.Query, ParseDimension(parts[2]), null, null),
                5 => new ChunkCommandRequest(ChunkCommandKind.Query, ParseDimension(parts[2]), ParseCoordinate(parts[3], "区块 X"), ParseCoordinate(parts[4], "区块 Z")),
                _ => throw new InvalidDataException("参数格式错误。\n" + Usage)
            };
        }

        if (action is "empty" or "regenerate")
        {
            if (parts.Length != 5) throw new InvalidDataException("参数格式错误。\n" + Usage);
            return new ChunkCommandRequest(
                action == "empty" ? ChunkCommandKind.Empty : ChunkCommandKind.Regenerate,
                ParseDimension(parts[2]),
                ParseCoordinate(parts[3], "区块 X"),
                ParseCoordinate(parts[4], "区块 Z"));
        }

        throw new InvalidDataException("不存在的 chunk 操作。\n" + Usage);
    }

    public static int ParseDimension(string text) => text.ToLowerInvariant() switch
    {
        "overworld" => 0,
        "nether" => 1,
        "the_end" => 2,
        _ => throw new InvalidDataException($"维度名称无效：{text}。只能使用 overworld、nether 或 the_end")
    };

    public static string DimensionName(int dimension) => dimension switch
    {
        0 => "overworld",
        1 => "nether",
        2 => "the_end",
        _ => $"unknown({dimension})"
    };

    private static int ParseCoordinate(string text, string name)
        => int.TryParse(text, out var value)
            ? value
            : throw new InvalidDataException($"{name} 必须是 Int32 区块坐标：{text}");
}
