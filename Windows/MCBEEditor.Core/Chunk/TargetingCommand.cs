using System.Globalization;
using System.Text.RegularExpressions;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public enum TargetingCommandTargetKind
{
    UniqueId,
    LocalPlayer,
    AllPlayers,
    AllEntities,
    Identifier
}

public sealed record TargetingCommandTarget(TargetingCommandTargetKind Kind, long? UniqueId = null, string? Identifier = null)
{
    public string DisplayText => Kind switch
    {
        TargetingCommandTargetKind.UniqueId => UniqueId?.ToString(CultureInfo.InvariantCulture) ?? "0",
        TargetingCommandTargetKind.LocalPlayer => "@s",
        TargetingCommandTargetKind.AllPlayers => "@a",
        TargetingCommandTargetKind.AllEntities => "@e",
        TargetingCommandTargetKind.Identifier => Identifier ?? string.Empty,
        _ => string.Empty
    };
}

public sealed record TargetingTeleportY(bool Automatic, double Value, bool IntegerLiteral)
{
    public static TargetingTeleportY Auto { get; } = new(true, 0, false);
    public bool AddsPlayerEyeHeight => Automatic || IntegerLiteral;
    public string DisplayText => Automatic ? "Auto" : TargetingCommandParser.CoordinateText(Value);
}

public enum TargetingExperienceOperationKind
{
    Add,
    AddLevel,
    Level,
    Percent,
    Query,
    Set
}

public abstract record TargetingCommandRequest
{
    public virtual bool IsDestructive => true;
}

public sealed record SetWorldSpawnTargetingCommandRequest(BedrockBlockCoordinate Position) : TargetingCommandRequest;
public sealed record SpawnPointTargetingCommandRequest(TargetingCommandTarget Target, int Dimension, BedrockBlockCoordinate Position) : TargetingCommandRequest;
public sealed record ClearSpawnPointTargetingCommandRequest(TargetingCommandTarget Target) : TargetingCommandRequest;
public sealed record TeleportTargetingCommandRequest(TargetingCommandTarget Target, int Dimension, double X, TargetingTeleportY Y, double Z) : TargetingCommandRequest;
public sealed record SpreadTargetingCommandRequest(TargetingCommandTarget Target) : TargetingCommandRequest;
public sealed record ExperienceTargetingCommandRequest(
    TargetingExperienceOperationKind Operation,
    TargetingCommandTarget Target,
    long IntegerValue = 0,
    float Progress = 0) : TargetingCommandRequest
{
    public override bool IsDestructive => Operation != TargetingExperienceOperationKind.Query;
}

public static class TargetingCommandParser
{
    private static readonly Regex IdentifierPattern = new("^[a-z0-9_.-]+:[a-z0-9_./-]+$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public const string Usage =
        "setworldspawn x y z\n" +
        "spawnpoint 目标 维度 x y z\n" +
        "clearspawnpoint 目标\n" +
        "teleport 目标 维度 x y或Auto z\n" +
        "spread 目标\n" +
        "experience add 目标 整数\n" +
        "experience addlevel 目标 整数\n" +
        "experience level 目标 0到24791整数\n" +
        "experience percent 目标 0到1浮点数\n" +
        "experience query 目标\n" +
        "experience set 目标 非负整数\n" +
        "目标支持非零 UniqueID、@s、@a、@e 或完整实体 identifier；experience 最终只能作用于玩家。";

    public static bool IsTargetingCommand(string text)
    {
        var first = FirstToken(text).ToLowerInvariant();
        return first is "setworldspawn" or "spawnpoint" or "clearspawnpoint" or "teleport" or "spread" or "experience";
    }

    public static TargetingCommandRequest Parse(string text)
    {
        var tokens = BlockCommandParser.TokenizeCommand(text);
        if (tokens.Count == 0) throw new InvalidDataException("命令不能为空。");
        var command = tokens[0].ToLowerInvariant();
        var args = tokens.Skip(1).ToArray();
        return command switch
        {
            "setworldspawn" => ParseSetWorldSpawn(args),
            "spawnpoint" => ParseSpawnPoint(args),
            "clearspawnpoint" => ParseClearSpawnPoint(args),
            "teleport" => ParseTeleport(args),
            "spread" => ParseSpread(args),
            "experience" => ParseExperience(args),
            _ => throw new InvalidDataException("不存在的命令。\n" + Usage)
        };
    }

    private static TargetingCommandRequest ParseSetWorldSpawn(string[] args)
    {
        if (args.Length != 3) throw UsageError();
        return new SetWorldSpawnTargetingCommandRequest(Coordinate(args, 0));
    }

    private static TargetingCommandRequest ParseSpawnPoint(string[] args)
    {
        if (args.Length != 5) throw UsageError();
        return new SpawnPointTargetingCommandRequest(ParseTarget(args[0]), BlockCommandParser.ParseDimension(args[1]), Coordinate(args, 2));
    }

    private static TargetingCommandRequest ParseClearSpawnPoint(string[] args)
    {
        if (args.Length != 1) throw UsageError();
        return new ClearSpawnPointTargetingCommandRequest(ParseTarget(args[0]));
    }

    private static TargetingCommandRequest ParseTeleport(string[] args)
    {
        if (args.Length != 5) throw UsageError();
        return new TeleportTargetingCommandRequest(
            ParseTarget(args[0]), BlockCommandParser.ParseDimension(args[1]),
            ParseTeleportCoordinate(args[2], "X"), ParseTeleportY(args[3]), ParseTeleportCoordinate(args[4], "Z"));
    }

    private static TargetingCommandRequest ParseSpread(string[] args)
    {
        if (args.Length != 1) throw UsageError();
        return new SpreadTargetingCommandRequest(ParseTarget(args[0]));
    }

    private static TargetingCommandRequest ParseExperience(string[] args)
    {
        if (args.Length < 2) throw UsageError();
        var action = args[0].ToLowerInvariant();
        var target = ParseTarget(args[1]);
        return action switch
        {
            "add" when args.Length == 3 => new ExperienceTargetingCommandRequest(
                TargetingExperienceOperationKind.Add, target, ParseInt64(args[2], "经验值变化量", allowNegative: true)),
            "addlevel" when args.Length == 3 => new ExperienceTargetingCommandRequest(
                TargetingExperienceOperationKind.AddLevel, target, ParseInt64(args[2], "经验等级变化量", allowNegative: true)),
            "level" when args.Length == 3 => new ExperienceTargetingCommandRequest(
                TargetingExperienceOperationKind.Level, target, ParseExperienceLevel(args[2])),
            "percent" when args.Length == 3 => new ExperienceTargetingCommandRequest(
                TargetingExperienceOperationKind.Percent, target, Progress: ParseExperiencePercent(args[2])),
            "query" when args.Length == 2 => new ExperienceTargetingCommandRequest(TargetingExperienceOperationKind.Query, target),
            "set" when args.Length == 3 => new ExperienceTargetingCommandRequest(
                TargetingExperienceOperationKind.Set, target, ParseInt64(args[2], "经验总数", allowNegative: false)),
            _ => throw UsageError()
        };
    }

    public static TargetingCommandTarget ParseTarget(string text)
    {
        return text switch
        {
            "@s" => new TargetingCommandTarget(TargetingCommandTargetKind.LocalPlayer),
            "@a" => new TargetingCommandTarget(TargetingCommandTargetKind.AllPlayers),
            "@e" => new TargetingCommandTarget(TargetingCommandTargetKind.AllEntities),
            _ => long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var uniqueId) && uniqueId != 0
                ? new TargetingCommandTarget(TargetingCommandTargetKind.UniqueId, UniqueId: uniqueId)
                : new TargetingCommandTarget(TargetingCommandTargetKind.Identifier, Identifier: ParseIdentifier(text))
        };
    }

    private static string ParseIdentifier(string text)
    {
        if (!IdentifierPattern.IsMatch(text)) throw new InvalidDataException($"目标实体字符串 ID 格式无效：{text}");
        return text;
    }

    private static BedrockBlockCoordinate Coordinate(string[] args, int offset)
        => new(ParseInt32(args[offset], "X"), ParseInt32(args[offset + 1], "Y"), ParseInt32(args[offset + 2], "Z"));

    private static int ParseInt32(string text, string name)
        => int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value : throw new InvalidDataException($"{name} 必须是 Int32 整数：{text}");

    private static long ParseInt64(string text, string name, bool allowNegative)
    {
        if (!long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || (!allowNegative && value < 0))
            throw new InvalidDataException($"{name}必须是{(allowNegative ? "Int64 整数" : "非负 Int64 整数")}：{text}");
        return value;
    }

    private static int ParseExperienceLevel(string text)
    {
        if (!int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || value is < 0 or > BedrockPlayerExperience.MaximumLevel)
            throw new InvalidDataException("经验等级必须是 0～24791 的整数。");
        return value;
    }

    private static float ParseExperiencePercent(string text)
    {
        if (!float.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) || !float.IsFinite(value) || value < 0 || value > 1)
            throw new InvalidDataException("经验条进度必须是 0～1 的浮点数。");
        return value;
    }

    private static double ParseTeleportCoordinate(string text, string name)
    {
        if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) || !double.IsFinite(value) || !float.IsFinite((float)value))
            throw new InvalidDataException($"teleport 的 {name} 坐标必须是可写入 Pos 的有限整数或浮点数：{text}");
        ValidateWindowsEntityCoordinateRange(value, name);
        return value;
    }

    private static TargetingTeleportY ParseTeleportY(string text)
    {
        if (text == "Auto") return TargetingTeleportY.Auto;
        if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) || !double.IsFinite(value) || !float.IsFinite((float)value))
            throw new InvalidDataException($"teleport 的 Y 坐标必须是有限整数、浮点数或 Auto：{text}");
        return new TargetingTeleportY(false, value, long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out _));
    }

    private static void ValidateWindowsEntityCoordinateRange(double value, string name)
    {
        var floored = Math.Floor(value);
        if (floored < int.MinValue || floored > int.MaxValue)
            throw new InvalidDataException($"teleport 的 {name} 超出当前 Windows actor/digp 坐标层可安全迁移的 Int32 方块范围。");
    }

    public static string CoordinateText(double value)
    {
        if (!double.IsFinite(value)) return value.ToString(CultureInfo.InvariantCulture);
        return value == Math.Round(value)
            ? value.ToString("0", CultureInfo.InvariantCulture)
            : value.ToString("0.#########", CultureInfo.InvariantCulture);
    }

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

public enum TargetingOutputStyle
{
    Success,
    LocalPlayer,
    OnlinePlayer,
    Entity
}

public sealed record TargetingOutputLine(string Text, TargetingOutputStyle Style);
public sealed record TargetingCommandExecutionResult(string Message, bool ChangedWorld, IReadOnlyList<TargetingOutputLine> OutputLines)
{
    public static TargetingCommandExecutionResult Success(string message, bool changedWorld)
        => new(message, changedWorld, [new TargetingOutputLine(message, TargetingOutputStyle.Success)]);
}

public sealed record TargetingResolvedTargets(IReadOnlyList<PlayerNbtRecord> Players, IReadOnlyList<BedrockWorldObject> Entities)
{
    public bool IsEmpty => Players.Count == 0 && Entities.Count == 0;
}

public sealed record BedrockPlayerExperience(int Level, float Progress)
{
    public const int MaximumLevel = 24_791;

    public BedrockPlayerExperience Bounded()
        => new(Math.Clamp(Level, 0, MaximumLevel), float.IsFinite(Progress) ? Math.Clamp(Progress, 0, 1) : 0);

    public long Total
    {
        get
        {
            var bounded = Bounded();
            var baseTotal = TotalRequired(bounded.Level);
            var needed = PointsRequiredForNextLevel(bounded.Level);
            var inside = (long)Math.Round(Math.Clamp((double)bounded.Progress, 0, 1) * needed, MidpointRounding.AwayFromZero);
            return Math.Min(MaximumTotal, baseTotal + Math.Clamp(inside, 0, needed));
        }
    }

    public static long MaximumTotal => TotalRequired(MaximumLevel) + PointsRequiredForNextLevel(MaximumLevel);

    public static BedrockPlayerExperience FromTotal(long total)
    {
        if (total < 0 || total > MaximumTotal)
            throw new InvalidDataException($"经验总数必须是 0～{MaximumTotal} 的整数。");
        var low = 0;
        var high = MaximumLevel;
        while (low < high)
        {
            var middle = low + (high - low + 1) / 2;
            if (TotalRequired(middle) <= total) low = middle; else high = middle - 1;
        }
        var baseTotal = TotalRequired(low);
        var needed = PointsRequiredForNextLevel(low);
        var progress = needed > 0 ? (float)((double)(total - baseTotal) / needed) : 0;
        return new BedrockPlayerExperience(low, progress);
    }

    public static int PointsRequiredForNextLevel(int level)
    {
        var value = Math.Clamp(level, 0, MaximumLevel);
        return value switch
        {
            <= 15 => 2 * value + 7,
            <= 30 => 5 * value - 38,
            _ => 9 * value - 158
        };
    }

    public static long TotalRequired(int level)
    {
        var value = (long)Math.Clamp(level, 0, MaximumLevel);
        return value switch
        {
            <= 16 => value * value + 6 * value,
            <= 31 => (5 * value * value - 81 * value + 720) / 2,
            _ => (9 * value * value - 325 * value + 4_440) / 2
        };
    }
}

/// <summary>
/// target-selector, player state and movement command layer. It reuses
/// the entity writer so modern actor digp and legacy Entity(0x32)
/// records keep their correct chunk/dimension ownership when teleporting.
/// </summary>
public sealed class TargetingCommandStore
{
    private static readonly string[] SpawnTagNames = ["SpawnX", "SpawnY", "SpawnZ", "SpawnDimension", "SpawnForced"];
    private readonly IWorldDatabase _database;

    public TargetingCommandStore(IWorldDatabase database) => _database = database;

    public TargetingResolvedTargets ResolveTargets(TargetingCommandTarget target)
    {
        var playerStore = new PlayerNbtStore(_database);
        var allPlayers = playerStore.Records();
        IReadOnlyList<BedrockWorldObject> allEntities;
        var playerIdentifierTarget = target.Kind == TargetingCommandTargetKind.Identifier
                                     && NormalizeIdentifier(target.Identifier ?? string.Empty) == "minecraft:player";
        if ((target.Kind is TargetingCommandTargetKind.LocalPlayer or TargetingCommandTargetKind.AllPlayers) || playerIdentifierTarget)
        {
            allEntities = [];
        }
        else
        {
            allEntities = new BedrockWorldObjectScanner(_database).ScanAll(
                    dimensions: null, includeEntities: true, includeBlockEntities: false, maximumObjects: int.MaxValue)
                .Objects
                .Where(item => item.Kind == BedrockWorldObjectKind.Entity && SelectableIdentifier(item) != "minecraft:player")
                .GroupBy(EntitySelectionIdentity, StringComparer.Ordinal)
                .Select(group => group.First())
                .ToArray();
        }

        IReadOnlyList<PlayerNbtRecord> players;
        IReadOnlyList<BedrockWorldObject> entities;
        switch (target.Kind)
        {
            case TargetingCommandTargetKind.LocalPlayer:
                players = allPlayers.Where(record => record.IsLocal).ToArray(); entities = []; break;
            case TargetingCommandTargetKind.AllPlayers:
                players = allPlayers; entities = []; break;
            case TargetingCommandTargetKind.AllEntities:
                players = allPlayers; entities = allEntities; break;
            case TargetingCommandTargetKind.Identifier:
            {
                var wanted = NormalizeIdentifier(target.Identifier ?? string.Empty);
                if (wanted == "minecraft:player") { players = allPlayers; entities = []; }
                else { players = []; entities = allEntities.Where(item => SelectableIdentifier(item) == wanted).ToArray(); }
                break;
            }
            case TargetingCommandTargetKind.UniqueId:
            {
                var id = target.UniqueId ?? 0;
                players = allPlayers.Where(record => playerStore.UniqueId(record) == id).ToArray();
                entities = allEntities.Where(item => item.UniqueId == id).ToArray();
                break;
            }
            default:
                players = []; entities = []; break;
        }

        var result = new TargetingResolvedTargets(players, entities);
        if (result.IsEmpty) throw new InvalidOperationException($"目标 {target.DisplayText} 没有匹配到玩家或实体。");
        return result;
    }

    public TargetingCommandExecutionResult SpawnPoint(SpawnPointTargetingCommandRequest request)
    {
        var targets = ResolveTargets(request.Target);
        if (targets.Players.Count == 0)
            throw new InvalidOperationException($"目标 {request.Target.DisplayText} 没有匹配到玩家；spawnpoint 不能用于普通实体。");

        var puts = new List<WorldDatabasePut>(targets.Players.Count);
        foreach (var player in targets.Players)
        {
            var root = SetTopLevel(player.Document.Root, "SpawnX", new NbtIntValue(request.Position.X));
            root = SetTopLevel(root, "SpawnY", new NbtIntValue(request.Position.Y));
            root = SetTopLevel(root, "SpawnZ", new NbtIntValue(request.Position.Z));
            root = SetTopLevel(root, "SpawnDimension", new NbtIntValue(request.Dimension));
            root = SetTopLevel(root, "SpawnForced", new NbtByteValue(1));
            var document = new NbtDocument(player.Document.RootName, root);
            puts.Add(new WorldDatabasePut(player.Key.ToArray(), BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian)));
        }
        _database.ApplyBatch(puts, [], sync: true);
        return TargetingCommandExecutionResult.Success(
            $"spawnpoint 完成：设置 {puts.Count} 个玩家的重生点为 {DimensionToken(request.Dimension)} {request.Position.X} {request.Position.Y} {request.Position.Z}。", true);
    }

    public TargetingCommandExecutionResult ClearSpawnPoint(ClearSpawnPointTargetingCommandRequest request)
    {
        var targets = ResolveTargets(request.Target);
        if (targets.Players.Count == 0)
            throw new InvalidOperationException($"目标 {request.Target.DisplayText} 没有匹配到玩家；实体不具有玩家出生点。");
        var puts = new List<WorldDatabasePut>();
        var removed = 0;
        foreach (var player in targets.Players)
        {
            if (player.Document.Root is not NbtCompoundValue compound) throw new InvalidDataException("玩家 NBT 根必须是 Compound。");
            var tags = compound.Tags.ToList();
            var before = tags.Count;
            tags.RemoveAll(tag => SpawnTagNames.Any(name => string.Equals(name, tag.Name, StringComparison.OrdinalIgnoreCase)));
            var count = before - tags.Count;
            if (count == 0) continue;
            removed += count;
            var document = new NbtDocument(player.Document.RootName, new NbtCompoundValue(tags));
            puts.Add(new WorldDatabasePut(player.Key.ToArray(), BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian)));
        }
        if (puts.Count == 0) throw new InvalidOperationException("目标玩家当前没有可清除的出生点标签。");
        _database.ApplyBatch(puts, [], sync: true);
        return TargetingCommandExecutionResult.Success($"clearspawnpoint 完成：清除 {puts.Count} 个玩家的出生点，移除 {removed} 个相关标签。", true);
    }

    public TargetingCommandExecutionResult Teleport(TeleportTargetingCommandRequest request)
    {
        var resolvedY = request.Y.Automatic ? AutomaticTeleportY(request.X, request.Z, request.Dimension) ?? 63 : request.Y.Value;
        var targets = ResolveTargets(request.Target);
        var playerY = resolvedY + (request.Y.AddsPlayerEyeHeight ? 1.62 : 0);
        if (!float.IsFinite((float)playerY)) throw new InvalidDataException("玩家 teleport 的 Y 坐标增加 1.62 后超出 Pos 可写入范围。");

        var playerPuts = new List<WorldDatabasePut>(targets.Players.Count);
        foreach (var player in targets.Players)
        {
            var document = TeleportedDocument(player.Document, request.X, playerY, request.Z, request.Dimension);
            playerPuts.Add(new WorldDatabasePut(player.Key.ToArray(), BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian)));
        }
        if (playerPuts.Count > 0) _database.ApplyBatch(playerPuts, [], sync: true);

        var entityStore = new BedrockWorldObjectNbtStore(_database);
        var movedEntities = 0;
        foreach (var entity in StableEntityMutationOrder(targets.Entities))
        {
            var document = TeleportedDocument(entity.Document, request.X, resolvedY, request.Z, request.Dimension);
            entityStore.Save(entity, document);
            movedEntities++;
        }

        var yText = request.Y.Automatic ? $"Auto→{TargetingCommandParser.CoordinateText(resolvedY)}" : request.Y.DisplayText;
        var playerSuffix = targets.Players.Count == 0 || !request.Y.AddsPlayerEyeHeight
            ? string.Empty : $"；玩家 Pos Y={TargetingCommandParser.CoordinateText(playerY)}";
        return TargetingCommandExecutionResult.Success(
            $"teleport 完成：将 {targets.Players.Count} 个玩家和 {movedEntities} 个实体传送到 {DimensionToken(request.Dimension)} 的 {TargetingCommandParser.CoordinateText(request.X)} {yText} {TargetingCommandParser.CoordinateText(request.Z)}{playerSuffix}。", true);
    }

    public TargetingCommandExecutionResult Spread(SpreadTargetingCommandRequest request)
    {
        var targets = ResolveTargets(request.Target);
        var supported = new HashSet<int> { 0, 1, 2 };
        var summaries = new BedrockChunkStore(_database).ListChunks()
            .Where(item => item.HasTerrain && supported.Contains(item.Position.Dimension)).ToArray();
        var grouped = summaries.GroupBy(item => item.Position.Dimension)
            .ToDictionary(group => group.Key, group => group.Select(item => item.Position).ToArray());
        var dimensions = grouped.Keys.OrderBy(value => value).ToArray();
        if (dimensions.Length == 0) throw new InvalidOperationException("世界中没有包含方块数据的已加载区块，无法执行 spread。");

        var lines = new List<TargetingOutputLine>();
        var playerPuts = new List<WorldDatabasePut>();
        foreach (var player in targets.Players)
        {
            var destination = RandomSpreadDestination(grouped, dimensions);
            var playerY = destination.Y + 1.62;
            var document = TeleportedDocument(player.Document, destination.X, playerY, destination.Z, destination.Dimension);
            playerPuts.Add(new WorldDatabasePut(player.Key.ToArray(), BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian)));
            lines.Add(new TargetingOutputLine(
                SpreadOutputLine("minecraft:player", new PlayerNbtStore(_database).UniqueId(player), destination.Dimension, destination.X, playerY, destination.Z),
                player.IsLocal ? TargetingOutputStyle.LocalPlayer : TargetingOutputStyle.OnlinePlayer));
        }
        if (playerPuts.Count > 0) _database.ApplyBatch(playerPuts, [], sync: true);

        var entityStore = new BedrockWorldObjectNbtStore(_database);
        foreach (var entity in StableEntityMutationOrder(targets.Entities))
        {
            var destination = RandomSpreadDestination(grouped, dimensions);
            var document = TeleportedDocument(entity.Document, destination.X, destination.Y, destination.Z, destination.Dimension);
            entityStore.Save(entity, document);
            lines.Add(new TargetingOutputLine(
                SpreadOutputLine(SelectableIdentifier(entity), entity.UniqueId, destination.Dimension, destination.X, destination.Y, destination.Z),
                TargetingOutputStyle.Entity));
        }
        return new TargetingCommandExecutionResult(string.Join(Environment.NewLine, lines.Select(line => line.Text)), true, lines);
    }

    public TargetingCommandExecutionResult Experience(ExperienceTargetingCommandRequest request)
    {
        var targets = ResolveTargets(request.Target);
        if (targets.Players.Count == 0)
            throw new InvalidOperationException($"目标 {request.Target.DisplayText} 没有匹配到玩家；experience 不能用于普通实体。");
        var playerStore = new PlayerNbtStore(_database);

        if (request.Operation == TargetingExperienceOperationKind.Query)
        {
            var lines = targets.Players.Select(player =>
            {
                var xp = ReadExperience(player.Document);
                var id = playerStore.UniqueId(player)?.ToString(CultureInfo.InvariantCulture) ?? "无UniqueID";
                var text = string.Format(CultureInfo.InvariantCulture,
                    "minecraft:player {0} 经验总数={1} 经验等级={2} 当前经验条进度={3:0.000}", id, xp.Total, xp.Level, xp.Progress);
                return new TargetingOutputLine(text, player.IsLocal ? TargetingOutputStyle.LocalPlayer : TargetingOutputStyle.OnlinePlayer);
            }).ToArray();
            return new TargetingCommandExecutionResult(string.Join(Environment.NewLine, lines.Select(line => line.Text)), false, lines);
        }

        var puts = new List<WorldDatabasePut>(targets.Players.Count);
        foreach (var player in targets.Players)
        {
            var xp = ReadExperience(player.Document);
            var updated = request.Operation switch
            {
                TargetingExperienceOperationKind.Add => AddExperience(xp, request.IntegerValue),
                TargetingExperienceOperationKind.AddLevel => AddLevel(xp, request.IntegerValue),
                TargetingExperienceOperationKind.Level => new BedrockPlayerExperience((int)request.IntegerValue, 0),
                TargetingExperienceOperationKind.Percent => new BedrockPlayerExperience(xp.Level, request.Progress),
                TargetingExperienceOperationKind.Set => BedrockPlayerExperience.FromTotal(request.IntegerValue),
                _ => xp
            };
            var document = ExperienceDocument(player.Document, updated.Bounded());
            puts.Add(new WorldDatabasePut(player.Key.ToArray(), BedrockNbtCodec.Encode(document, NbtEncoding.LittleEndian)));
        }
        _database.ApplyBatch(puts, [], sync: true);

        var action = request.Operation switch
        {
            TargetingExperienceOperationKind.Add => $"add {request.IntegerValue}",
            TargetingExperienceOperationKind.AddLevel => $"addlevel {request.IntegerValue}",
            TargetingExperienceOperationKind.Level => $"level {request.IntegerValue}",
            TargetingExperienceOperationKind.Percent => $"percent {request.Progress.ToString("0.000", CultureInfo.InvariantCulture)}",
            TargetingExperienceOperationKind.Set => $"set {request.IntegerValue}",
            _ => "query"
        };
        return TargetingCommandExecutionResult.Success($"experience {action} 完成：修改 {puts.Count} 个玩家。", true);
    }

    public static string SetWorldSpawn(WorldDocument document, BedrockBlockCoordinate position)
    {
        var file = document.ReadLevelDat();
        var root = SetTopLevel(file.Document.Root, "SpawnX", new NbtIntValue(position.X));
        root = SetTopLevel(root, "SpawnY", new NbtIntValue(position.Y));
        root = SetTopLevel(root, "SpawnZ", new NbtIntValue(position.Z));
        document.WriteLevelDat(file with { Document = new NbtDocument(file.Document.RootName, root) });
        return $"setworldspawn 完成：世界重生点设为 {position.X} {position.Y} {position.Z}。";
    }

    public int? AutomaticTeleportY(double x, double z, int dimension)
    {
        var blockX = checked((int)Math.Floor(x));
        var blockZ = checked((int)Math.Floor(z));
        var chunkX = FloorDiv(blockX, 16);
        var chunkZ = FloorDiv(blockZ, 16);
        var localX = FloorMod(blockX, 16);
        var localZ = FloorMod(blockZ, 16);
        var records = new BedrockChunkSubChunkAccess(_database).Records(new ChunkPosition(chunkX, chunkZ, dimension))
            .OrderByDescending(record => record.YIndex).ToArray();
        var blocks = new List<(int Y, bool NonAir, bool Air)>();
        foreach (var record in records)
        {
            var baseY = record.YIndex * 16;
            for (var localY = 15; localY >= 0; localY--)
            {
                var states = record.SubChunk.Storages.Select(storage => storage.BlockState(localX, localY, localZ)).Where(state => state is not null).ToArray();
                if (states.Length == 0) continue;
                var nonAir = states.Any(state => state is not null && !state.IsAir);
                blocks.Add((baseY + localY, nonAir, !nonAir));
            }
        }
        var highestIndex = blocks.FindIndex(block => block.NonAir);
        if (highestIndex < 0) return null;
        var highest = blocks[highestIndex];
        if (dimension == 1)
        {
            var airIndex = blocks.FindIndex(highestIndex + 1, block => block.Air);
            if (airIndex >= 0)
            {
                var lowerSolidIndex = blocks.FindIndex(airIndex + 1, block => block.NonAir);
                if (lowerSolidIndex >= 0) return checked(blocks[lowerSolidIndex].Y + 1);
            }
        }
        return checked(highest.Y + 1);
    }

    public static BedrockPlayerExperience ReadExperience(NbtDocument document)
    {
        if (document.Root is not NbtCompoundValue compound) throw new InvalidDataException("玩家 NBT 根必须是 Compound。");
        var level = ReadInteger(compound, "PlayerLevel", 0);
        var progress = ReadFloat(compound, "PlayerLevelProgress", 0);
        return new BedrockPlayerExperience(level, progress).Bounded();
    }

    private static BedrockPlayerExperience AddExperience(BedrockPlayerExperience current, long delta)
    {
        long sum;
        try { sum = checked(current.Total + delta); }
        catch (OverflowException) { throw new InvalidDataException("experience add 结果超出 Int64 范围。"); }
        var bounded = Math.Clamp(sum, 0, BedrockPlayerExperience.MaximumTotal);
        return BedrockPlayerExperience.FromTotal(bounded);
    }

    private static BedrockPlayerExperience AddLevel(BedrockPlayerExperience current, long delta)
    {
        long sum;
        try { sum = checked((long)current.Level + delta); }
        catch (OverflowException) { throw new InvalidDataException("experience addlevel 结果超出 Int64 范围。"); }
        return new BedrockPlayerExperience((int)Math.Clamp(sum, 0, BedrockPlayerExperience.MaximumLevel), current.Progress);
    }

    public static NbtDocument ExperienceDocument(NbtDocument source, BedrockPlayerExperience experience)
    {
        if (source.Root is not NbtCompoundValue compound) throw new InvalidDataException("玩家 NBT 根必须是 Compound。");
        var root = new NbtCompoundValue(compound.Tags.ToList());
        root = (NbtCompoundValue)SetTopLevel(root, "PlayerLevel", new NbtIntValue(experience.Level));
        root = (NbtCompoundValue)SetTopLevel(root, "PlayerLevelProgress", new NbtFloatValue(experience.Progress));
        return new NbtDocument(source.RootName, root);
    }

    private static int ReadInteger(NbtCompoundValue compound, string name, int fallback)
    {
        var value = compound.Tags.FirstOrDefault(tag => string.Equals(tag.Name, name, StringComparison.OrdinalIgnoreCase))?.Value;
        if (value is null) return fallback;

        double number = value switch
        {
            NbtByteValue v => v.Value,
            NbtShortValue v => v.Value,
            NbtIntValue v => v.Value,
            NbtLongValue v => v.Value,
            NbtFloatValue v => v.Value,
            NbtDoubleValue v => v.Value,
            _ => double.NaN
        };
        if (!double.IsFinite(number) || number != Math.Truncate(number) || number < int.MinValue || number > int.MaxValue)
            throw new InvalidDataException($"玩家 {name} 必须是 Int32 范围内的整数数字标签。");
        return (int)number;
    }

    private static float ReadFloat(NbtCompoundValue compound, string name, float fallback)
    {
        var value = compound.Tags.FirstOrDefault(tag => string.Equals(tag.Name, name, StringComparison.OrdinalIgnoreCase))?.Value;
        if (value is null) return fallback;
        return value switch
        {
            NbtByteValue v => v.Value,
            NbtShortValue v => v.Value,
            NbtIntValue v => v.Value,
            NbtLongValue v => v.Value,
            NbtFloatValue v => v.Value,
            NbtDoubleValue v => (float)v.Value,
            _ => throw new InvalidDataException($"玩家 {name} 标签必须是数字类型。")
        };
    }

    private static NbtDocument TeleportedDocument(NbtDocument source, double x, double y, double z, int dimension)
    {
        if (source.Root is not NbtCompoundValue) throw new InvalidDataException("玩家或实体 NBT 根必须是 Compound。");
        var root = SetTopLevel(source.Root, "Pos", new NbtListValue(NbtTagType.Float,
            [new NbtFloatValue((float)x), new NbtFloatValue((float)y), new NbtFloatValue((float)z)]));
        root = SetTopLevel(root, "DimensionId", new NbtIntValue(dimension));
        root = SetTopLevel(root, "LastDimensionId", new NbtIntValue(dimension));
        root = SetTopLevel(root, "Motion", new NbtListValue(NbtTagType.Float,
            [new NbtFloatValue(0), new NbtFloatValue(0), new NbtFloatValue(0)]));
        return new NbtDocument(source.RootName, root);
    }

    private (int Dimension, int X, int Y, int Z) RandomSpreadDestination(
        IReadOnlyDictionary<int, ChunkPosition[]> grouped, IReadOnlyList<int> dimensions)
    {
        var dimensionOrder = dimensions.OrderBy(_ => Random.Shared.Next()).ToArray();
        foreach (var dimension in dimensionOrder)
        {
            if (!grouped.TryGetValue(dimension, out var chunks)) continue;
            foreach (var chunk in chunks.OrderBy(_ => Random.Shared.Next()))
            {
                var columns = Enumerable.Range(0, 256).OrderBy(_ => Random.Shared.Next()).ToArray();
                foreach (var column in columns)
                {
                    var localX = column & 15;
                    var localZ = column >> 4;
                    int x, z;
                    try { x = checked(chunk.X * 16 + localX); z = checked(chunk.Z * 16 + localZ); }
                    catch (OverflowException) { continue; }
                    try
                    {
                        var y = AutomaticTeleportY(x, z, dimension);
                        if (y.HasValue) return (dimension, x, y.Value, z);
                    }
                    catch (Exception ex) when (ex is InvalidDataException or NotSupportedException or OverflowException)
                    {
                        // A damaged column must not stop spread from trying other loaded columns.
                    }
                }
            }
        }
        throw new InvalidOperationException("所有已加载区块都没有可用的非空气方块列，无法执行 spread。");
    }

    private static string SpreadOutputLine(string identifier, long? uniqueId, int dimension, double x, double y, double z)
        => $"{identifier} {(uniqueId?.ToString(CultureInfo.InvariantCulture) ?? "无UniqueID")} {BedrockDimensionNames.DisplayName(dimension)} " +
           $"{TargetingCommandParser.CoordinateText(x)} {TargetingCommandParser.CoordinateText(y)} {TargetingCommandParser.CoordinateText(z)}";

    private static IReadOnlyList<BedrockWorldObject> StableEntityMutationOrder(IReadOnlyList<BedrockWorldObject> entities)
        => entities.OrderBy(item => Convert.ToHexString(item.Storage.PrimaryKey), StringComparer.Ordinal)
            .ThenByDescending(item => item.Storage.RecordIndex).ToArray();

    private static string EntitySelectionIdentity(BedrockWorldObject item)
        => item.UniqueId.HasValue ? "uid:" + item.UniqueId.Value.ToString(CultureInfo.InvariantCulture) : item.StableId;

    private static string SelectableIdentifier(BedrockWorldObject item)
    {
        var root = item.Document.Root;
        if (root.CompoundValueIgnoreCase("identifier", "Identifier") is NbtStringValue direct && !string.IsNullOrWhiteSpace(direct.Value))
            return NormalizeIdentifier(direct.Value);
        if (root.CompoundValueIgnoreCase("definitions", "Definitions") is NbtListValue definitions
            && definitions.Values.Count > 0 && definitions.Values[0] is NbtStringValue definition)
        {
            var value = definition.Value.Trim();
            while (value.StartsWith('+') || value.StartsWith('-')) value = value[1..];
            if (value.Length > 0) return NormalizeIdentifier(value);
        }
        return NormalizeIdentifier(item.Identifier);
    }

    private static string NormalizeIdentifier(string value)
    {
        var lowered = value.Trim().ToLowerInvariant();
        return lowered.Contains(':') ? lowered : "minecraft:" + lowered;
    }

    private static NbtValue SetTopLevel(NbtValue root, string name, NbtValue value)
    {
        if (root is not NbtCompoundValue compound) throw new InvalidDataException("NBT 根必须是 Compound。");
        var tags = compound.Tags.ToList();
        var matches = tags.Select((tag, index) => (tag, index))
            .Where(item => string.Equals(item.tag.Name, name, StringComparison.OrdinalIgnoreCase))
            .Select(item => item.index).ToArray();
        if (matches.Length > 0)
        {
            tags[matches[0]] = new NbtNamedTag(name, NbtDocumentTools.DeepClone(value));
            for (var index = matches.Length - 1; index >= 1; index--) tags.RemoveAt(matches[index]);
        }
        else tags.Add(new NbtNamedTag(name, NbtDocumentTools.DeepClone(value)));
        return new NbtCompoundValue(tags);
    }

    private static int FloorDiv(int value, int divisor)
    {
        var quotient = value / divisor;
        var remainder = value % divisor;
        if (remainder != 0 && ((remainder < 0) != (divisor < 0))) quotient--;
        return quotient;
    }

    private static int FloorMod(int value, int divisor)
    {
        var remainder = value % divisor;
        return remainder < 0 ? remainder + Math.Abs(divisor) : remainder;
    }

    private static string DimensionToken(int dimension) => dimension switch
    {
        0 => "overworld",
        1 => "nether",
        2 => "the_end",
        _ => dimension.ToString(CultureInfo.InvariantCulture)
    };
}
