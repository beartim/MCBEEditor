using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public enum StructureTemplateStructureOperationKind { Save, Load, Delete }

public sealed record StructureTemplateStructureCommandRequest(
    StructureTemplateStructureOperationKind Operation,
    string? Name = null,
    int? Dimension = null,
    BedrockBlockBox? Region = null,
    BedrockBlockCoordinate? Destination = null,
    bool DeleteAll = false)
{
    public bool IsDestructive => true;
}

public static class StructureTemplateCommandParser
{
    private static readonly Regex NamespacedIdentifierPattern = new(
        "^[a-z0-9_.-]+:[a-z0-9_./-]+$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public const string Usage =
        "structure save 名称 维度 x1 y1 z1 x2 y2 z2\n" +
        "structure load 名称 维度 x y z\n" +
        "structure delete 名称或ALL\n" +
        "名称必须为 namespace:name；save 直接覆盖同名 structuretemplate_ 记录；load/delete 找不到名称时失败。";

    public static bool IsStructureTemplateCommand(string text)
        => FirstToken(text).Equals("structure", StringComparison.OrdinalIgnoreCase);

    public static StructureTemplateStructureCommandRequest Parse(string text)
    {
        var tokens = BlockCommandParser.TokenizeCommand(text);
        if (tokens.Count < 2 || !tokens[0].Equals("structure", StringComparison.OrdinalIgnoreCase)) throw UsageError();
        var action = tokens[1].ToLowerInvariant();
        if (action == "save" && tokens.Count == 10)
        {
            var name = ParseName(tokens[2]);
            var dimension = BlockCommandParser.ParseDimension(tokens[3]);
            var first = new BedrockBlockCoordinate(ParseInt32(tokens[4], "x1"), ParseInt32(tokens[5], "y1"), ParseInt32(tokens[6], "z1"));
            var second = new BedrockBlockCoordinate(ParseInt32(tokens[7], "x2"), ParseInt32(tokens[8], "y2"), ParseInt32(tokens[9], "z2"));
            return new StructureTemplateStructureCommandRequest(StructureTemplateStructureOperationKind.Save, name, dimension, new BedrockBlockBox(first, second));
        }
        if (action == "load" && tokens.Count == 7)
        {
            var name = ParseName(tokens[2]);
            var dimension = BlockCommandParser.ParseDimension(tokens[3]);
            var destination = new BedrockBlockCoordinate(ParseInt32(tokens[4], "x"), ParseInt32(tokens[5], "y"), ParseInt32(tokens[6], "z"));
            return new StructureTemplateStructureCommandRequest(StructureTemplateStructureOperationKind.Load, name, dimension, Destination: destination);
        }
        if (action == "delete" && tokens.Count == 3)
        {
            if (tokens[2] == "ALL") return new StructureTemplateStructureCommandRequest(StructureTemplateStructureOperationKind.Delete, DeleteAll: true);
            return new StructureTemplateStructureCommandRequest(StructureTemplateStructureOperationKind.Delete, ParseName(tokens[2]));
        }
        throw UsageError();
    }

    public static string ParseName(string text)
    {
        if (!NamespacedIdentifierPattern.IsMatch(text))
            throw new InvalidDataException($"结构名称字符串 ID 格式无效：{text}");
        return text;
    }

    private static int ParseInt32(string text, string name)
        => int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value : throw new InvalidDataException($"{name} 必须是 Int32 坐标：{text}");

    private static string FirstToken(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        var trimmed = text.TrimStart();
        var index = 0;
        while (index < trimmed.Length && !char.IsWhiteSpace(trimmed[index])) index++;
        return trimmed[..index];
    }

    private static InvalidDataException UsageError() => new("参数格式错误。\n" + Usage);
}

public sealed class StructureTemplateCommandStore
{
    public const string StructureKeyPrefix = "structuretemplate";
    private readonly IWorldDatabase _database;
    private readonly BedrockRegionBlockStore _regions;

    public StructureTemplateCommandStore(IWorldDatabase database)
    {
        _database = database ?? throw new ArgumentNullException(nameof(database));
        _regions = new BedrockRegionBlockStore(database);
    }

    public TargetingCommandExecutionResult Execute(StructureTemplateStructureCommandRequest request)
    {
        return request.Operation switch
        {
            StructureTemplateStructureOperationKind.Save => Save(request),
            StructureTemplateStructureOperationKind.Load => Load(request),
            StructureTemplateStructureOperationKind.Delete => Delete(request),
            _ => throw new InvalidDataException("未知 structure 操作。")
        };
    }

    private TargetingCommandExecutionResult Save(StructureTemplateStructureCommandRequest request)
    {
        var name = request.Name ?? throw new InvalidDataException("structure save 缺少名称。");
        var dimension = request.Dimension ?? throw new InvalidDataException("structure save 缺少维度。");
        var region = request.Region ?? throw new InvalidDataException("structure save 缺少范围。");
        var document = _regions.CaptureStructureDocument(dimension, region);
        var encoded = BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian);
        var key = StructureKey(name);
        _database.Put(key, encoded, sync: true);
        var persisted = _database.Get(key);
        if (persisted is null || !persisted.AsSpan().SequenceEqual(encoded))
            throw new InvalidDataException("结构写入后未能从 LevelDB 读回。");
        var message = $"structure save 完成：{name}，维度 {ChunkCommandParser.DimensionName(dimension)}，范围 {region.Minimum.X} {region.Minimum.Y} {region.Minimum.Z} 至 {region.Maximum.X} {region.Maximum.Y} {region.Maximum.Z}。";
        return TargetingCommandExecutionResult.Success(message, true);
    }

    private TargetingCommandExecutionResult Load(StructureTemplateStructureCommandRequest request)
    {
        var name = request.Name ?? throw new InvalidDataException("structure load 缺少名称。");
        var dimension = request.Dimension ?? throw new InvalidDataException("structure load 缺少维度。");
        var destination = request.Destination ?? throw new InvalidDataException("structure load 缺少目标坐标。");
        var raw = _database.Get(StructureKey(name)) ?? throw new NotSupportedException($"不存在结构：{name}");
        var document = NbtFileCodec.DecodeSingle(raw).Document;
        var result = _regions.LoadStructureDocument(document, dimension, destination);
        return TargetingCommandExecutionResult.Success($"structure load 完成：{name}。\n{result}", true);
    }

    private TargetingCommandExecutionResult Delete(StructureTemplateStructureCommandRequest request)
    {
        if (!request.DeleteAll)
        {
            var name = request.Name ?? throw new InvalidDataException("structure delete 缺少名称。");
            var key = StructureKey(name);
            if (_database.Get(key) is null) throw new NotSupportedException($"不存在结构：{name}");
            _database.Delete(key, sync: true);
            return TargetingCommandExecutionResult.Success($"structure delete 完成：已删除 {name}。", true);
        }

        var entries = _database.Entries(Encoding.UTF8.GetBytes(StructureKeyPrefix), includeValues: false).ToArray();
        if (entries.Length > 0) _database.ApplyBatch([], entries.Select(entry => entry.Key), sync: true);
        return TargetingCommandExecutionResult.Success($"structure delete 完成：删除全部 {entries.Length} 个已保存结构。", entries.Length > 0);
    }

    public bool Contains(string name) => _database.Get(StructureKey(name)) is not null;

    public static byte[] StructureKey(string name)
        => Encoding.UTF8.GetBytes(StructureKeyPrefix + "_" + StructureTemplateCommandParser.ParseName(name));
}
