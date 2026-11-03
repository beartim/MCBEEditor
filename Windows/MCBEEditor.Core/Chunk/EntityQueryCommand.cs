using System.Globalization;
using System.Text.RegularExpressions;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record EntityQueryBounds(double MinX, double MinY, double MinZ, double MaxX, double MaxY, double MaxZ)
{
    public bool Contains(BedrockWorldObjectPosition position)
        => Contains(position.X, position.Y, position.Z);

    public bool Contains(double x, double y, double z)
        => x >= MinX && x <= MaxX && y >= MinY && y <= MaxY && z >= MinZ && z <= MaxZ;
}

public sealed record EntityQueryCommandRequest(int? Dimension = null, EntityQueryBounds? Bounds = null, TargetingCommandTarget? Target = null);

public static class EntityQueryCommandParser
{
    public const string Usage = "entity [目标]\nentity 维度 [x1 y1 z1 x2 y2 z2]\nentity 目标 维度 [x1 y1 z1 x2 y2 z2]\n只读查询玩家与普通实体，不包含方块实体。默认目标为 @e，entity 与 entity @e 完全等价，列出所有维度的全部实体（包括玩家）。\n目标支持非零有符号 Int64 UniqueID、@s（本机玩家）、@a（全部玩家）、@e（全部实体，含玩家）或完整实体 identifier；minecraft:player 可用于选择玩家。UniqueID 会返回所有匹配的独立存储记录，不按 ID 去重。\n单独数字始终表示 UniqueID，例如 entity 12345678；若要查询数字维度，写 entity @e 0。单个普通名称按维度解析，原版 minecraft:overworld/nether/the_end 别名保留；其他单个 namespace:name 按实体 identifier 解析。自定义 namespaced 维度请写在目标之后，例如 entity @e custom:moon。\n维度接受当前存档的名称或 Int32 ID。六个范围坐标须整组填写，支持有限小数、负数、反向角点，范围包含边界；按玩家和实体的实际维度与 Pos 筛选，玩家坐标不加眼高补偿。没有有效坐标的记录仍可按目标/维度查询，显示 Pos=NULL，但不进入坐标范围结果。\n每个实体一行：判断的实体类型 Dimension=维度名称(ID) Pos=(X,Y,Z) NBT=[全部MCBE-SNBT标签]。自定义维度可显示登记名称；无法读取名称时显示数字 ID。坐标保留 Double 精度。NBT 使用 MCBE-SNBT 文件格式的无损表示，保留全部标签、类型、顺序、嵌套列表、Int64 和 NaN 原始位，不向原 NBT 补写推断出的类型或坐标。\n无匹配时返回“entity：没有匹配的实体。”；损坏实体记录仍显示扫描提示；查询不修改数据库或 level.dat。\n示例：entity\n示例：entity @s\n示例：entity @a\n示例：entity @e\n示例：entity 12345678\n示例：entity minecraft:pig\n示例：entity overworld 50 60 65 100 120 150\n示例：entity @a overworld 0 0 0 1 1 1\n示例：entity @e 0\n示例：entity @e custom:moon";

    public static bool IsEntityQueryCommand(string text)
        => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()
            ?.Equals("entity", StringComparison.OrdinalIgnoreCase) == true;

    public static EntityQueryCommandRequest Parse(string text, Func<string,int>? dimensionResolver = null)
    {
        var tokens = BlockCommandParser.TokenizeCommand(text);
        if (tokens.Count == 0 || !tokens[0].Equals("entity", StringComparison.OrdinalIgnoreCase)
            || tokens.Count is not (1 or 2 or 3 or 8 or 9))
            throw new InvalidDataException("参数格式错误。\n" + Usage);
        var target = new TargetingCommandTarget(TargetingCommandTargetKind.AllEntities);
        if (tokens.Count == 1) return new(Target: target);
        if (tokens.Count == 8 && tokens[1].StartsWith('@'))
            throw new InvalidDataException("参数格式错误。\n" + Usage);
        var explicitTarget = tokens.Count is 3 or 9 || tokens.Count == 2 && IsTarget(tokens[1]);
        if (explicitTarget) target = TargetingCommandParser.ParseTarget(tokens[1]);
        if (tokens.Count == 2 && explicitTarget) return new(Target: target);
        var dimensionIndex = explicitTarget ? 2 : 1;
        var dimension = BlockCommandParser.ParseDimension(tokens[dimensionIndex], dimensionResolver);
        if (tokens.Count <= 3) return new(dimension, Target: target);
        var offset = dimensionIndex + 1;
        var x1 = Coordinate(tokens[offset], "X1");
        var y1 = Coordinate(tokens[offset + 1], "Y1");
        var z1 = Coordinate(tokens[offset + 2], "Z1");
        var x2 = Coordinate(tokens[offset + 3], "X2");
        var y2 = Coordinate(tokens[offset + 4], "Y2");
        var z2 = Coordinate(tokens[offset + 5], "Z2");
        return new EntityQueryCommandRequest(dimension, new EntityQueryBounds(
            Math.Min(x1, x2), Math.Min(y1, y2), Math.Min(z1, z2),
            Math.Max(x1, x2), Math.Max(y1, y2), Math.Max(z1, z2)), target);
    }

    private static bool IsTarget(string text)
    {
        var vanillaDimension = text.ToLowerInvariant() is "minecraft:overworld" or "minecraft:nether" or "minecraft:the_end";
        return text.StartsWith('@') || Regex.IsMatch(text, "^[+-]?[0-9]+$", RegexOptions.CultureInvariant)
            || text.Contains(':') && !vanillaDimension;
    }

    private static double Coordinate(string text, string name)
        => EntityActionCommandParser.ParseEntityCoordinate(text, name, "entity");
}

public sealed class EntityQueryCommandStore(IWorldDatabase database)
{
    private sealed record QueryRecord(string Identifier, long? UniqueId, int Dimension, BedrockWorldObjectPosition? Position,
        NbtValue Root, bool IsPlayer, bool IsLocal);

    public TargetingCommandExecutionResult Execute(EntityQueryCommandRequest request)
    {
        // NBT may override the owning digp/chunk dimension; filter the same
        // resolved objects shown by the entity browser after scanning all records.
        var scan = new BedrockWorldObjectScanner(database).ScanAll(
            dimensions: null, includeEntities: true, includeBlockEntities: false, maximumObjects: int.MaxValue);
        var players = new PlayerNbtStore(database);
        var playerRecords = players.Records();
        var playerKeys = playerRecords.Select(player => Convert.ToHexString(player.Key)).ToHashSet(StringComparer.Ordinal);
        var records = playerRecords.Select(player =>
        {
            var position = players.CurrentPosition(player);
            return new QueryRecord("minecraft:player", players.UniqueId(player), players.CurrentDimension(player),
                position is null ? null : new(position.X, position.Y, position.Z), player.Document.Root, true, player.IsLocal);
        // Short player keys can also look like binary chunk Entity keys. Merge
        // by storage identity here, never by UniqueID across separate records.
        }).Concat(scan.Objects.Where(item => !playerKeys.Contains(Convert.ToHexString(item.Storage.PrimaryKey)))
            .Select(item => new QueryRecord(item.Identifier, item.UniqueId, item.Dimension, item.Position,
            item.Document.Root, item.Identifier == "minecraft:player", false)));
        var diagnostics = scan.Diagnostics.ToList();
        Dictionary<int, string> names;
        try { names = new DimensionStore(database).Snapshot().ToDictionary(row => row.Id, row => row.Name); }
        catch (InvalidDataException error)
        {
            names = [];
            diagnostics.Add("无法读取维度名称，使用维度 ID：" + error.Message);
        }
        var target = request.Target ?? new(TargetingCommandTargetKind.AllEntities);
        var lines = records
            .Where(item => Matches(item, target))
            .Where(item => !request.Dimension.HasValue || item.Dimension == request.Dimension.Value)
            .Where(item => request.Bounds is null || item.Position is not null && request.Bounds.Contains(item.Position))
            .Select(item => new TargetingOutputLine(
                $"{OneLine(item.Identifier)} Dimension={DimensionText(item.Dimension, names)} Pos={PositionText(item.Position)} NBT=[{NbtText(item.Root)}]", TargetingOutputStyle.Entity))
            .ToList();
        var message = lines.Count == 0 ? "entity：没有匹配的实体。" : $"entity：找到 {lines.Count} 个实体。";
        if (lines.Count == 0) lines.Add(new TargetingOutputLine(message, TargetingOutputStyle.Entity));
        lines.AddRange(diagnostics.Select(diagnostic =>
            new TargetingOutputLine("entity 扫描提示：" + OneLine(diagnostic), TargetingOutputStyle.Entity)));
        return new TargetingCommandExecutionResult(message, false, lines);
    }

    private static bool Matches(QueryRecord record, TargetingCommandTarget target) => target.Kind switch
    {
        TargetingCommandTargetKind.AllEntities => true,
        TargetingCommandTargetKind.AllPlayers => record.IsPlayer,
        TargetingCommandTargetKind.LocalPlayer => record.IsLocal,
        TargetingCommandTargetKind.UniqueId => target.UniqueId.HasValue && record.UniqueId == target.UniqueId,
        TargetingCommandTargetKind.Identifier => record.Identifier == target.Identifier,
        _ => false
    };

    private static string OneLine(string text)
        => text.Replace("\\", "\\\\").Replace("\r", "\\r").Replace("\n", "\\n").Replace("\t", "\\t");

    private static string NbtText(NbtValue root)
        => McbeSnbtCodec.EncodeNamedTags(root is NbtCompoundValue compound ? compound.Tags : [new NbtNamedTag("", root)]);

    private static string DimensionText(int dimension, IReadOnlyDictionary<int, string> names)
    {
        var name = names.GetValueOrDefault(dimension) ?? ChunkCommandParser.DimensionName(dimension);
        var id = dimension.ToString(CultureInfo.InvariantCulture);
        return name == id ? id : $"{OneLine(name)}({id})";
    }

    private static string PositionText(BedrockWorldObjectPosition? position)
        => position is null ? "NULL" : $"({CoordinateText(position.X)},{CoordinateText(position.Y)},{CoordinateText(position.Z)})";

    private static string CoordinateText(double value)
    {
        var text = value.ToString("G17", CultureInfo.InvariantCulture).ToLowerInvariant();
        var parts = text.Split('e');
        return parts.Length == 2 ? parts[0] + "e" + int.Parse(parts[1], CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture) : text;
    }
}
