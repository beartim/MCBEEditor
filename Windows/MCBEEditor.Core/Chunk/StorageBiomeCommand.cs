using System.Globalization;
using System.Text.RegularExpressions;

namespace MCBEEditor.Core.Chunk;

public abstract record StorageBiomeCommandRequest
{
    public virtual bool IsDestructive => false;
}

public sealed record InfoStorageBiomeCommandRequest : StorageBiomeCommandRequest;
public sealed record StorageQueryStorageBiomeCommandRequest(int Dimension, BedrockBlockCoordinate Position) : StorageBiomeCommandRequest;
public sealed record StorageSetStorageBiomeCommandRequest(int Dimension, BedrockBlockCoordinate Position, int Layer, BedrockBlockStorageSpec Block) : StorageBiomeCommandRequest
{
    public override bool IsDestructive => true;
}
public sealed record StorageDeleteStorageBiomeCommandRequest(int Dimension, BedrockBlockCoordinate Position, int Layer) : StorageBiomeCommandRequest
{
    public override bool IsDestructive => true;
}
public sealed record StorageClearStorageBiomeCommandRequest(int Dimension, BedrockBlockCoordinate Position, byte KeepThroughLayer) : StorageBiomeCommandRequest
{
    public override bool IsDestructive => true;
}
public sealed record FillBiomeStorageBiomeCommandRequest(int Dimension, BedrockBlockBox Region, uint BiomeId, string BiomeDisplayText) : StorageBiomeCommandRequest
{
    public override bool IsDestructive => true;
}

public static class StorageBiomeCommandParser
{
    private static readonly Regex BlockNamePattern = new("^[a-z0-9_.-]+:[a-z0-9_./-]+$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public const string Usage =
        "storage query 维度 x y z\n" +
        "storage set 维度 x y z 层数 方块名 states\n" +
        "storage delete 维度 x y z 层数\n" +
        "storage clear 维度 x y z 保留到的层数\n" +
        "fillbiome 维度 x1 y1 z1 x2 y2 z2 生物群系数字ID或字符串ID\n" +
        "info";

    public static bool IsStorageBiomeCommand(string text)
    {
        var token = FirstToken(text).ToLowerInvariant();
        return token is "storage" or "fillbiome" or "info";
    }

    public static StorageBiomeCommandRequest Parse(string text)
    {
        var tokens = BlockCommandParser.TokenizeCommand(text);
        if (tokens.Count == 0) throw new InvalidDataException("命令不能为空。");
        var command = tokens[0].ToLowerInvariant();
        var args = tokens.Skip(1).ToArray();
        return command switch
        {
            "info" => ParseInfo(args),
            "storage" => ParseStorage(args),
            "fillbiome" => ParseFillBiome(args),
            _ => throw new InvalidDataException("不存在的命令。\n" + Usage)
        };
    }

    private static StorageBiomeCommandRequest ParseInfo(string[] args)
    {
        if (args.Length != 0) throw UsageError();
        return new InfoStorageBiomeCommandRequest();
    }

    private static StorageBiomeCommandRequest ParseStorage(string[] args)
    {
        if (args.Length == 0) throw UsageError();
        var operation = args[0].ToLowerInvariant();
        return operation switch
        {
            "query" when args.Length == 5 => new StorageQueryStorageBiomeCommandRequest(
                BlockCommandParser.ParseDimension(args[1]), Coordinate(args, 2)),
            "set" when args.Length == 8 => new StorageSetStorageBiomeCommandRequest(
                BlockCommandParser.ParseDimension(args[1]), Coordinate(args, 2), ParseLayer(args[5]), ParseBlock(args[6], args[7])),
            "delete" when args.Length == 6 => new StorageDeleteStorageBiomeCommandRequest(
                BlockCommandParser.ParseDimension(args[1]), Coordinate(args, 2), ParseLayer(args[5])),
            "clear" when args.Length == 6 => new StorageClearStorageBiomeCommandRequest(
                BlockCommandParser.ParseDimension(args[1]), Coordinate(args, 2), ParseKeepLayer(args[5])),
            "add" => throw new InvalidDataException("storage 不支持 add；仅支持 query、set、delete、clear。"),
            _ => throw UsageError()
        };
    }

    private static StorageBiomeCommandRequest ParseFillBiome(string[] args)
    {
        if (args.Length != 8) throw UsageError();
        var dimension = BlockCommandParser.ParseDimension(args[0]);
        var first = Coordinate(args, 1);
        var second = Coordinate(args, 4);
        var (id, display) = BedrockBiomeCatalog.Parse(args[7]);
        return new FillBiomeStorageBiomeCommandRequest(dimension, new BedrockBlockBox(first, second), id, display);
    }

    private static BedrockBlockStorageSpec ParseBlock(string name, string states)
    {
        if (!BlockNamePattern.IsMatch(name)) throw new InvalidDataException($"方块名称格式无效：{name}");
        return new BedrockBlockStorageSpec(name, BlockCommandParser.ParseStates(states));
    }

    private static BedrockBlockCoordinate Coordinate(string[] args, int offset)
        => new(ParseInt(args[offset], "X"), ParseInt(args[offset + 1], "Y"), ParseInt(args[offset + 2], "Z"));

    private static int ParseInt(string text, string name)
        => int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value : throw new InvalidDataException($"{name} 必须是 Int32 坐标：{text}");

    private static int ParseLayer(string text)
        => int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) && value is >= 0 and < byte.MaxValue
            ? value : throw new InvalidDataException($"storage 层数必须为 0…254：{text}");

    private static byte ParseKeepLayer(string text)
        => byte.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value : throw new InvalidDataException($"storage clear 保留层数必须为 0…255：{text}");

    private static InvalidDataException UsageError() => new("参数格式错误。\n" + Usage);

    private static string FirstToken(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        var trimmed = text.TrimStart();
        var index = 0;
        while (index < trimmed.Length && !char.IsWhiteSpace(trimmed[index])) index++;
        return trimmed[..index];
    }
}
