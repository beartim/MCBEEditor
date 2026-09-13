using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public enum EnvironmentTimeQueryKind { Daytime, Gametime, Day }
public enum EnvironmentTimePeriodKind { Day, Sunset, Night, Sunrise, Noon, Midnight }
public enum EnvironmentTimeOperationKind { Query, Add, Set, Ceil, Floor }
public enum EnvironmentWeatherCondition { Clear, Rain, Thunder }
public enum EnvironmentTickingAreaOperationKind { Add, Delete, List }

public sealed record EnvironmentTickingAreaSpec(
    int Dimension,
    bool IsCircle,
    int MinimumX,
    int MinimumZ,
    int MaximumX,
    int MaximumZ,
    string Name,
    bool Preload)
{
    public EnvironmentTickingAreaSpec Normalized => new(
        Dimension,
        IsCircle,
        Math.Min(MinimumX, MaximumX),
        Math.Min(MinimumZ, MaximumZ),
        Math.Max(MinimumX, MaximumX),
        Math.Max(MinimumZ, MaximumZ),
        Name,
        Preload);

    public long CenterBlockX => MinimumX + ((long)MaximumX - MinimumX) / 2;
    public long CenterBlockZ => MinimumZ + ((long)MaximumZ - MinimumZ) / 2;

    public int Radius
    {
        get
        {
            var value = Normalized;
            var halfExtent = Math.Max((long)value.MaximumX - value.MinimumX, (long)value.MaximumZ - value.MinimumZ) / 2;
            return value.IsCircle ? checked((int)(halfExtent / 16 + (halfExtent % 16 == 0 ? 0 : 1))) : checked((int)halfExtent);
        }
    }

    public (int X, int Z) CenterChunk
    {
        get
        {
            var value = Normalized;
            if (!value.IsCircle) return (checked((int)value.CenterBlockX), checked((int)value.CenterBlockZ));
            return (FloorDiv16(value.CenterBlockX), FloorDiv16(value.CenterBlockZ));
        }
    }

    public int ChunkCount
    {
        get
        {
            var value = Normalized;
            if (value.IsCircle)
            {
                var radius = value.Radius;
                if (radius > 4096) return int.MaxValue;
                var total = 0;
                for (var dz = -radius; dz <= radius; dz++)
                    for (var dx = -radius; dx <= radius; dx++)
                        if ((long)dx * dx + (long)dz * dz <= (long)radius * radius) total++;
                return total;
            }
            var width = (long)value.MaximumX - value.MinimumX + 1;
            var height = (long)value.MaximumZ - value.MinimumZ + 1;
            var product = Math.Max(0L, width) * Math.Max(0L, height);
            return product > int.MaxValue ? int.MaxValue : (int)product;
        }
    }

    private static int FloorDiv16(long value)
    {
        var quotient = value / 16;
        var remainder = value % 16;
        if (remainder < 0) quotient--;
        return checked((int)quotient);
    }
}

public abstract record EnvironmentCommandRequest
{
    public virtual bool IsDestructive => true;
}

public sealed record DayLockEnvironmentCommandRequest(bool Locked) : EnvironmentCommandRequest;
public sealed record TimeEnvironmentCommandRequest(
    EnvironmentTimeOperationKind Operation,
    EnvironmentTimeQueryKind Query = EnvironmentTimeQueryKind.Daytime,
    EnvironmentTimePeriodKind Period = EnvironmentTimePeriodKind.Day,
    long Value = 0) : EnvironmentCommandRequest
{
    public override bool IsDestructive => Operation != EnvironmentTimeOperationKind.Query;
}
public sealed record WeatherQueryEnvironmentCommandRequest : EnvironmentCommandRequest
{
    public override bool IsDestructive => false;
}
public sealed record WeatherEnvironmentCommandRequest(
    EnvironmentWeatherCondition Condition,
    int? Duration,
    float? Intensity,
    bool AutomaticChange) : EnvironmentCommandRequest;
public sealed record TickingAreaEnvironmentCommandRequest(
    EnvironmentTickingAreaOperationKind Operation,
    EnvironmentTickingAreaSpec? Area = null,
    string? Name = null,
    int? Dimension = null) : EnvironmentCommandRequest
{
    public override bool IsDestructive => Operation != EnvironmentTickingAreaOperationKind.List;
}

public static class EnvironmentCommandParser
{
    private static readonly Regex TickingAreaNamePattern = new("^[A-Za-z0-9_.:-]+$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public const string Usage =
        "daylock 0或1\n" +
        "time query daytime|gametime|day\n" +
        "time add 整数\n" +
        "time set 非负整数\n" +
        "time ceil day|sunset|night|sunrise|noon|midnight\n" +
        "time floor day|sunset|night|sunrise|noon|midnight\n" +
        "weather query\n" +
        "weather clear 0或1\n" +
        "weather rain 持续游戏刻 强度 0或1\n" +
        "weather thunder 持续游戏刻 强度 0或1\n" +
        "tickingarea add square 维度 x1 z1 x2 z2 名称 0或1\n" +
        "tickingarea add circle 维度 中心区块X 中心区块Z 半径 名称 0或1\n" +
        "tickingarea delete 名称或ALL\n" +
        "tickingarea list 维度或ALL\n" +
        "圆形半径单位为区块，允许 0～4；每个区域最多 100 个区块，每个世界最多 10 个常加载区域。";

    public static bool IsEnvironmentCommand(string text)
    {
        var first = FirstToken(text).ToLowerInvariant();
        return first is "daylock" or "time" or "weather" or "tickingarea";
    }

    public static EnvironmentCommandRequest Parse(string text)
    {
        var tokens = BlockCommandParser.TokenizeCommand(text);
        if (tokens.Count == 0) throw new InvalidDataException("命令不能为空。");
        var command = tokens[0].ToLowerInvariant();
        var args = tokens.Skip(1).ToArray();
        return command switch
        {
            "daylock" => ParseDayLock(args),
            "time" => ParseTime(args),
            "weather" => ParseWeather(args),
            "tickingarea" => ParseTickingArea(args),
            _ => throw UsageError()
        };
    }

    private static EnvironmentCommandRequest ParseDayLock(string[] args)
    {
        if (args.Length != 1) throw UsageError();
        return new DayLockEnvironmentCommandRequest(ParseBooleanFlag(args[0], "是否锁定时间"));
    }

    private static EnvironmentCommandRequest ParseTime(string[] args)
    {
        if (args.Length != 2) throw UsageError();
        var action = args[0].ToLowerInvariant();
        return action switch
        {
            "query" => new TimeEnvironmentCommandRequest(EnvironmentTimeOperationKind.Query, Query: ParseTimeQuery(args[1])),
            "add" => new TimeEnvironmentCommandRequest(EnvironmentTimeOperationKind.Add, Value: ParseTimeInteger(args[1], allowNegative: true)),
            "set" => new TimeEnvironmentCommandRequest(EnvironmentTimeOperationKind.Set, Value: ParseTimeInteger(args[1], allowNegative: false)),
            "ceil" => new TimeEnvironmentCommandRequest(EnvironmentTimeOperationKind.Ceil, Period: ParseTimePeriod(args[1])),
            "floor" => new TimeEnvironmentCommandRequest(EnvironmentTimeOperationKind.Floor, Period: ParseTimePeriod(args[1])),
            _ => throw UsageError()
        };
    }

    private static EnvironmentCommandRequest ParseWeather(string[] args)
    {
        if (args.Length == 1 && args[0].Equals("query", StringComparison.OrdinalIgnoreCase))
            return new WeatherQueryEnvironmentCommandRequest();
        if (args.Length == 2 && args[0].Equals("clear", StringComparison.OrdinalIgnoreCase))
            return new WeatherEnvironmentCommandRequest(EnvironmentWeatherCondition.Clear, null, null, ParseBooleanFlag(args[1], "天气是否自动变化"));
        if (args.Length == 4 && args[0].Equals("rain", StringComparison.OrdinalIgnoreCase))
            return new WeatherEnvironmentCommandRequest(EnvironmentWeatherCondition.Rain, ParseWeatherDuration(args[1]), ParseWeatherIntensity(args[2]), ParseBooleanFlag(args[3], "天气是否自动变化"));
        if (args.Length == 4 && args[0].Equals("thunder", StringComparison.OrdinalIgnoreCase))
            return new WeatherEnvironmentCommandRequest(EnvironmentWeatherCondition.Thunder, ParseWeatherDuration(args[1]), ParseWeatherIntensity(args[2]), ParseBooleanFlag(args[3], "天气是否自动变化"));
        throw UsageError();
    }

    private static EnvironmentCommandRequest ParseTickingArea(string[] args)
    {
        if (args.Length < 2) throw UsageError();
        var action = args[0].ToLowerInvariant();
        if (action == "delete" && args.Length == 2)
            return new TickingAreaEnvironmentCommandRequest(EnvironmentTickingAreaOperationKind.Delete, Name: args[1] == "ALL" ? null : ParseTickingAreaName(args[1]));
        if (action == "list" && args.Length == 2)
            return new TickingAreaEnvironmentCommandRequest(EnvironmentTickingAreaOperationKind.List, Dimension: args[1] == "ALL" ? null : BlockCommandParser.ParseDimension(args[1]));
        if (action != "add" || args.Length < 3) throw UsageError();

        var shape = args[1].ToLowerInvariant();
        if (shape == "square" && args.Length == 9)
        {
            var dimension = BlockCommandParser.ParseDimension(args[2]);
            var x1 = ParseInt32(args[3], "X1");
            var z1 = ParseInt32(args[4], "Z1");
            var x2 = ParseInt32(args[5], "X2");
            var z2 = ParseInt32(args[6], "Z2");
            var area = new EnvironmentTickingAreaSpec(
                dimension, false, Math.Min(x1, x2), Math.Min(z1, z2), Math.Max(x1, x2), Math.Max(z1, z2),
                ParseTickingAreaName(args[7]), ParseBooleanFlag(args[8], "是否预加载"));
            ValidateTickingAreaSpec(area);
            return new TickingAreaEnvironmentCommandRequest(EnvironmentTickingAreaOperationKind.Add, Area: area);
        }
        if (shape == "circle" && args.Length == 8)
        {
            var dimension = BlockCommandParser.ParseDimension(args[2]);
            var chunkX = ParseInt32(args[3], "中心区块 X");
            var chunkZ = ParseInt32(args[4], "中心区块 Z");
            var radius = ParseTickingAreaRadius(args[5]);
            var centerBlockX = (long)chunkX * 16;
            var centerBlockZ = (long)chunkZ * 16;
            var radiusBlocks = (long)radius * 16;
            var minX = ExactInt32(centerBlockX - radiusBlocks, "圆形常加载区域 MinX");
            var minZ = ExactInt32(centerBlockZ - radiusBlocks, "圆形常加载区域 MinZ");
            var maxX = ExactInt32(centerBlockX + radiusBlocks, "圆形常加载区域 MaxX");
            var maxZ = ExactInt32(centerBlockZ + radiusBlocks, "圆形常加载区域 MaxZ");
            var area = new EnvironmentTickingAreaSpec(
                dimension, true, minX, minZ, maxX, maxZ,
                ParseTickingAreaName(args[6]), ParseBooleanFlag(args[7], "是否预加载"));
            ValidateTickingAreaSpec(area);
            return new TickingAreaEnvironmentCommandRequest(EnvironmentTickingAreaOperationKind.Add, Area: area);
        }
        throw UsageError();
    }

    private static int ExactInt32(long value, string name)
        => value is >= int.MinValue and <= int.MaxValue ? (int)value : throw new InvalidDataException($"{name} 坐标溢出 Int32。");

    private static bool ParseBooleanFlag(string text, string name) => text switch
    {
        "0" => false,
        "1" => true,
        _ => throw new InvalidDataException($"{name}只能输入 0 或 1。")
    };

    private static EnvironmentTimeQueryKind ParseTimeQuery(string text) => text.ToLowerInvariant() switch
    {
        "daytime" => EnvironmentTimeQueryKind.Daytime,
        "gametime" => EnvironmentTimeQueryKind.Gametime,
        "day" => EnvironmentTimeQueryKind.Day,
        _ => throw UsageError()
    };

    private static EnvironmentTimePeriodKind ParseTimePeriod(string text) => text.ToLowerInvariant() switch
    {
        "day" => EnvironmentTimePeriodKind.Day,
        "sunset" => EnvironmentTimePeriodKind.Sunset,
        "night" => EnvironmentTimePeriodKind.Night,
        "sunrise" => EnvironmentTimePeriodKind.Sunrise,
        "noon" => EnvironmentTimePeriodKind.Noon,
        "midnight" => EnvironmentTimePeriodKind.Midnight,
        _ => throw UsageError()
    };

    private static long ParseTimeInteger(string text, bool allowNegative)
    {
        if (!long.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || (!allowNegative && value < 0))
            throw new InvalidDataException($"time 参数必须是{(allowNegative ? "Int64 整数" : "0…9223372036854775807 的非负整数")}：{text}");
        return value;
    }

    private static int ParseWeatherDuration(string text)
    {
        if (!int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || value < 0)
            throw new InvalidDataException("天气持续时间必须是 0…2147483647 的游戏刻整数。");
        return value;
    }

    private static float ParseWeatherIntensity(string text)
    {
        if (!float.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) || !float.IsFinite(value) || value < 0 || value > 1)
            throw new InvalidDataException("天气强度必须是 0.0～1.0 的浮点数。");
        return value;
    }

    private static int ParseInt32(string text, string name)
        => int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value : throw new InvalidDataException($"{name} 必须是 Int32 区块坐标：{text}");

    private static string ParseTickingAreaName(string text)
    {
        if (string.IsNullOrEmpty(text) || text == "ALL") throw new InvalidDataException("常加载区域名称不能为空，也不能使用保留字 ALL。");
        if (!TickingAreaNamePattern.IsMatch(text)) throw new InvalidDataException("常加载区域名称只能包含字母、数字、下划线、点、冒号和连字符。");
        return text;
    }

    private static int ParseTickingAreaRadius(string text)
    {
        if (!int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || value is < 0 or > 4)
            throw new InvalidDataException("圆形常加载区域半径必须是 0～4 的区块数整数。");
        return value;
    }

    internal static void ValidateTickingAreaSpec(EnvironmentTickingAreaSpec area)
    {
        var value = area.Normalized;
        if (value.Dimension is < 0 or > 2) throw new InvalidDataException($"不支持维度 {value.Dimension}。");
        if (value.IsCircle && value.Radius > 4) throw new InvalidDataException("圆形常加载区域半径最多为 4 个区块。");
        if (value.ChunkCount is <= 0 or > 100) throw new InvalidDataException("每个常加载区域最多包含 100 个区块。");
    }

    public static string DimensionName(int dimension) => dimension switch
    {
        0 => "overworld",
        1 => "nether",
        2 => "the_end",
        _ => $"dimension({dimension})"
    };

    public static string TimePeriodName(EnvironmentTimePeriodKind period) => period.ToString().ToLowerInvariant();

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

public sealed class EnvironmentCommandStore
{
    private static readonly byte[] NativeTickingAreaPrefix = Encoding.UTF8.GetBytes("tickingarea_");
    private readonly WorldDocument _document;
    private readonly IWorldDatabase _database;

    public EnvironmentCommandStore(WorldDocument document, IWorldDatabase database)
    {
        _document = document ?? throw new ArgumentNullException(nameof(document));
        _database = database ?? throw new ArgumentNullException(nameof(database));
    }

    public TargetingCommandExecutionResult Execute(EnvironmentCommandRequest request) => request switch
    {
        DayLockEnvironmentCommandRequest dayLock => DayLock(dayLock),
        TimeEnvironmentCommandRequest time => Time(time),
        WeatherQueryEnvironmentCommandRequest => QueryWeather(),
        WeatherEnvironmentCommandRequest weather => Weather(weather),
        TickingAreaEnvironmentCommandRequest tickingArea => TickingArea(tickingArea),
        _ => throw new InvalidOperationException("无法执行未知命令。")
    };

    public TargetingCommandExecutionResult DayLock(DayLockEnvironmentCommandRequest request)
    {
        var file = _document.ReadLevelDat();
        var tags = RootCompound(file.Document);
        SetIgnoreCase(tags, "dodaylightcycle", new NbtByteValue(request.Locked ? (sbyte)0 : (sbyte)1));
        _document.WriteLevelDat(file with { Document = file.Document with { Root = new NbtCompoundValue(tags) } });
        return TargetingCommandExecutionResult.Success($"daylock 完成：锁定={(request.Locked ? 1 : 0)}，dodaylightcycle={(request.Locked ? 0 : 1)}", true);
    }

    public TargetingCommandExecutionResult Time(TimeEnvironmentCommandRequest request)
    {
        var current = ReadTime();
        switch (request.Operation)
        {
            case EnvironmentTimeOperationKind.Query:
            {
                var message = request.Query switch
                {
                    EnvironmentTimeQueryKind.Gametime => $"gametime={current}",
                    EnvironmentTimeQueryKind.Day => $"day={FloorDivision(current, 24_000)}",
                    _ => DaytimeSummary(current)
                };
                return TargetingCommandExecutionResult.Success(message, false);
            }
            case EnvironmentTimeOperationKind.Add:
            {
                long updated;
                try { updated = checked(current + request.Value); }
                catch (OverflowException) { throw new InvalidDataException("time add 结果超出 Int64 范围。"); }
                SaveTime(updated);
                return TargetingCommandExecutionResult.Success($"time add 完成：time={updated}", true);
            }
            case EnvironmentTimeOperationKind.Set:
                SaveTime(request.Value);
                return TargetingCommandExecutionResult.Success($"time set 完成：time={request.Value}", true);
            case EnvironmentTimeOperationKind.Ceil:
            {
                var updated = AlignedTime(current, StartTick(request.Period), roundingUp: true);
                SaveTime(updated);
                return TargetingCommandExecutionResult.Success($"time ceil {EnvironmentCommandParser.TimePeriodName(request.Period)} 完成：time={updated}", true);
            }
            case EnvironmentTimeOperationKind.Floor:
            {
                var updated = AlignedTime(current, StartTick(request.Period), roundingUp: false);
                SaveTime(updated);
                return TargetingCommandExecutionResult.Success($"time floor {EnvironmentCommandParser.TimePeriodName(request.Period)} 完成：time={updated}", true);
            }
            default:
                throw new InvalidOperationException("未知 time 操作。");
        }
    }

    public TargetingCommandExecutionResult QueryWeather()
    {
        var root = _document.ReadLevelDat().Document.Root;
        if (root is not NbtCompoundValue) throw new InvalidDataException("level.dat 根标签不是 Compound。");
        var lines = new[] { "rainLevel", "rainTime", "lightningLevel", "lightningTime", "doWeatherCycle" }
            .Select(name => $"{name}={(root.CompoundValue(name) is { } value ? NbtDocumentTools.SearchValueText(value) : "NULL")}");
        return TargetingCommandExecutionResult.Success(string.Join("\n", lines), false);
    }

    public TargetingCommandExecutionResult Weather(WeatherEnvironmentCommandRequest request)
    {
        var duration = request.Condition == EnvironmentWeatherCondition.Clear ? 12_000 : request.Duration ?? throw new InvalidDataException("weather 缺少持续时间。");
        var intensity = request.Condition == EnvironmentWeatherCondition.Clear ? 0f : request.Intensity ?? throw new InvalidDataException("weather 缺少强度。");
        intensity = Math.Clamp(intensity, 0, 1);
        var rainLevel = request.Condition == EnvironmentWeatherCondition.Clear ? 0f : intensity;
        var lightningLevel = request.Condition == EnvironmentWeatherCondition.Thunder ? intensity : 0f;

        var file = _document.ReadLevelDat();
        var tags = RootCompound(file.Document);
        SetExact(tags, "rainLevel", new NbtFloatValue(rainLevel));
        SetExact(tags, "rainTime", new NbtIntValue(Math.Max(0, duration)));
        SetExact(tags, "lightningLevel", new NbtFloatValue(lightningLevel));
        SetExact(tags, "lightningTime", new NbtIntValue(Math.Max(0, duration)));
        SetExact(tags, "doWeatherCycle", new NbtByteValue(request.AutomaticChange ? (sbyte)1 : (sbyte)0));
        _document.WriteLevelDat(file with { Document = file.Document with { Root = new NbtCompoundValue(tags) } });

        var automatic = request.AutomaticChange ? "允许自动变化" : "禁止自动变化";
        var message = request.Condition switch
        {
            EnvironmentWeatherCondition.Clear => $"weather 完成：天气设为晴朗，{automatic}。",
            EnvironmentWeatherCondition.Rain => $"weather 完成：天气设为下雨，持续 {duration} 游戏刻，强度 {intensity.ToString("G3", CultureInfo.InvariantCulture)}，{automatic}。",
            _ => $"weather 完成：天气设为雷暴，持续 {duration} 游戏刻，强度 {intensity.ToString("G3", CultureInfo.InvariantCulture)}，{automatic}。"
        };
        return TargetingCommandExecutionResult.Success(message, true);
    }

    public IReadOnlyList<EnvironmentTickingAreaSpec> TickingAreas()
        => ReadTickingAreas().Select(record => record.Area.Normalized).ToArray();

    /// <summary>Creates or replaces one ticking area. replaceName permits an editor to rename an existing area atomically.</summary>
    public TargetingCommandExecutionResult SaveTickingArea(EnvironmentTickingAreaSpec area, string? replaceName = null)
    {
        area = area.Normalized;
        EnvironmentCommandParser.ValidateTickingAreaSpec(area);
        var records = ReadTickingAreas();
        var originalCount = records.Count;
        if (!string.IsNullOrWhiteSpace(replaceName))
            records.RemoveAll(record => string.Equals(record.Area.Name, replaceName, StringComparison.OrdinalIgnoreCase));
        records.RemoveAll(record => string.Equals(record.Area.Name, area.Name, StringComparison.OrdinalIgnoreCase));
        if (records.Count >= 10) throw new InvalidDataException("基岩版每个世界最多支持 10 个常加载区域。");
        records.Add(MakeTickingAreaRecord(area));
        SaveTickingAreas(records);
        var replaced = records.Count <= originalCount;
        return TargetingCommandExecutionResult.Success($"常加载区域已{(replaced ? "更新" : "创建")}：{TickingAreaLine(area, records.Count)}", true);
    }

    public TargetingCommandExecutionResult DeleteTickingArea(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) throw new InvalidDataException("常加载区域名称不能为空。");
        return DeleteTickingAreas([name]);
    }

    public TargetingCommandExecutionResult DeleteTickingAreas(IEnumerable<string> names)
    {
        var selected = names.Where(name => !string.IsNullOrWhiteSpace(name)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (selected.Count == 0) throw new InvalidDataException("没有选择常加载区域。");
        var records = ReadTickingAreas();
        var original = records.Count;
        records.RemoveAll(record => selected.Contains(record.Area.Name));
        var removed = original - records.Count;
        if (removed == 0) throw new InvalidDataException("所选常加载区域已经不存在。");
        SaveTickingAreas(records);
        return TargetingCommandExecutionResult.Success($"已删除 {removed} 个常加载区域。", true);
    }

    public TargetingCommandExecutionResult SetTickingAreaPreload(IEnumerable<string> names, bool preload)
    {
        var selected = names.Where(name => !string.IsNullOrWhiteSpace(name)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (selected.Count == 0) throw new InvalidDataException("没有选择常加载区域。");
        var records = ReadTickingAreas();
        var changed = 0;
        for (var index = 0; index < records.Count; index++)
        {
            var record = records[index];
            if (!selected.Contains(record.Area.Name) || record.Area.Preload == preload) continue;
            records[index] = record with { Area = record.Area with { Preload = preload } };
            changed++;
        }
        if (changed == 0)
        {
            var matched = records.Count(record => selected.Contains(record.Area.Name));
            if (matched == 0) throw new InvalidDataException("所选常加载区域已经不存在。");
            return TargetingCommandExecutionResult.Success($"所选 {matched} 个常加载区域已经全部{(preload ? "开启" : "关闭")}预加载。", false);
        }
        SaveTickingAreas(records);
        return TargetingCommandExecutionResult.Success($"已为 {changed} 个常加载区域{(preload ? "开启" : "关闭")}预加载。", true);
    }

    public TargetingCommandExecutionResult TickingArea(TickingAreaEnvironmentCommandRequest request)
    {
        var records = ReadTickingAreas();
        switch (request.Operation)
        {
            case EnvironmentTickingAreaOperationKind.Add:
            {
                var area = request.Area?.Normalized ?? throw new InvalidDataException("tickingarea add 缺少区域参数。");
                EnvironmentCommandParser.ValidateTickingAreaSpec(area);
                var before = records.Count;
                records.RemoveAll(record => string.Equals(record.Area.Name, area.Name, StringComparison.OrdinalIgnoreCase));
                var replaced = records.Count != before;
                records.Add(MakeTickingAreaRecord(area));
                SaveTickingAreas(records);
                var line = TickingAreaLine(area, records.Count);
                return TargetingCommandExecutionResult.Success($"tickingarea add 完成：已{(replaced ? "覆盖" : "创建")} {line}", true);
            }
            case EnvironmentTickingAreaOperationKind.Delete:
            {
                if (request.Name is not null)
                {
                    var original = records.Count;
                    records.RemoveAll(record => string.Equals(record.Area.Name, request.Name, StringComparison.OrdinalIgnoreCase));
                    if (records.Count == original) throw new InvalidDataException($"不存在常加载区域：{request.Name}");
                    SaveTickingAreas(records);
                    return TargetingCommandExecutionResult.Success($"tickingarea delete 完成：删除名称为 {request.Name} 的 {original - records.Count} 个区域。", true);
                }
                var count = records.Count;
                SaveTickingAreas([]);
                return TargetingCommandExecutionResult.Success($"tickingarea delete 完成：删除全部 {count} 个常加载区域。", count > 0);
            }
            case EnvironmentTickingAreaOperationKind.List:
            {
                var filtered = records.Where(record => request.Dimension is null || record.Area.Dimension == request.Dimension.Value).ToArray();
                if (filtered.Length == 0)
                {
                    var scope = request.Dimension.HasValue ? EnvironmentCommandParser.DimensionName(request.Dimension.Value) : "ALL";
                    return TargetingCommandExecutionResult.Success($"tickingarea list：{scope} 没有常加载区域。", false);
                }
                var lines = filtered.Select((record, index) => new TargetingOutputLine(TickingAreaLine(record.Area, index + 1), TargetingOutputStyle.Success)).ToArray();
                return new TargetingCommandExecutionResult(string.Join(Environment.NewLine, lines.Select(line => line.Text)), false, lines);
            }
            default:
                throw new InvalidOperationException("未知 tickingarea 操作。");
        }
    }

    private long ReadTime()
    {
        var file = _document.ReadLevelDat();
        var tags = RootCompound(file.Document);
        return IntegerIgnoreCase(tags, "Time", 0);
    }

    private void SaveTime(long time)
    {
        var file = _document.ReadLevelDat();
        var tags = RootCompound(file.Document);
        var automatic = IntegerIgnoreCase(tags, "dodaylightcycle", 1) != 0;
        SetIgnoreCase(tags, "Time", new NbtLongValue(time));
        SetIgnoreCase(tags, "dodaylightcycle", new NbtByteValue(automatic ? (sbyte)1 : (sbyte)0));
        _document.WriteLevelDat(file with { Document = file.Document with { Root = new NbtCompoundValue(tags) } });
    }

    private static List<NbtNamedTag> RootCompound(NbtDocument document)
        => document.Root is NbtCompoundValue compound
            ? compound.Tags.ToList()
            : throw new InvalidDataException("level.dat 根标签不是 Compound。");

    private static long IntegerIgnoreCase(IReadOnlyList<NbtNamedTag> tags, string name, long defaultValue)
    {
        var value = tags.FirstOrDefault(tag => string.Equals(tag.Name, name, StringComparison.OrdinalIgnoreCase))?.Value;
        if (value is null) return defaultValue;
        return value switch
        {
            NbtByteValue number => number.Value,
            NbtShortValue number => number.Value,
            NbtIntValue number => number.Value,
            NbtLongValue number => number.Value,
            _ => throw new InvalidDataException($"level.dat 的 {name} 标签必须是整数类型。")
        };
    }

    private static void SetIgnoreCase(List<NbtNamedTag> tags, string name, NbtValue value)
    {
        var matches = Enumerable.Range(0, tags.Count).Where(index => string.Equals(tags[index].Name, name, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (matches.Length == 0)
        {
            tags.Add(new NbtNamedTag(name, value));
            return;
        }
        tags[matches[0]] = new NbtNamedTag(name, value);
        for (var i = matches.Length - 1; i >= 1; i--) tags.RemoveAt(matches[i]);
    }

    private static void SetExact(List<NbtNamedTag> tags, string name, NbtValue value)
    {
        var index = tags.FindIndex(tag => tag.Name == name);
        if (index >= 0) tags[index] = new NbtNamedTag(name, value);
        else tags.Add(new NbtNamedTag(name, value));
    }

    private static long StartTick(EnvironmentTimePeriodKind period) => period switch
    {
        EnvironmentTimePeriodKind.Day => 0,
        EnvironmentTimePeriodKind.Noon => 6_000,
        EnvironmentTimePeriodKind.Sunset => 12_001,
        EnvironmentTimePeriodKind.Night => 13_801,
        EnvironmentTimePeriodKind.Midnight => 18_000,
        EnvironmentTimePeriodKind.Sunrise => 22_201,
        _ => 0
    };

    public static long FloorDivision(long value, long divisor)
    {
        var quotient = value / divisor;
        var remainder = value % divisor;
        return remainder < 0 ? quotient - 1 : quotient;
    }

    public static long CeilingDivision(long value, long divisor)
    {
        var quotient = value / divisor;
        var remainder = value % divisor;
        return remainder > 0 ? quotient + 1 : quotient;
    }

    public static long PositiveRemainder(long value, long divisor)
    {
        var remainder = value % divisor;
        return remainder >= 0 ? remainder : remainder + divisor;
    }

    public static long AlignedTime(long current, long startTick, bool roundingUp)
    {
        var dayIndex = roundingUp ? CeilingDivision(current, 24_000) : FloorDivision(current, 24_000);
        try { return checked(dayIndex * 24_000 + startTick); }
        catch (OverflowException) { throw new InvalidDataException("time 对齐结果超出 Int64 范围。"); }
    }

    public static string DaytimeSummary(long time)
    {
        var daytime = PositiveRemainder(time, 24_000);
        string name;
        long start;
        long end;
        if (daytime <= 12_000) { name = "白天"; start = 0; end = 12_000; }
        else if (daytime <= 13_800) { name = "日落"; start = 12_001; end = 13_800; }
        else if (daytime <= 22_200) { name = "夜晚"; start = 13_801; end = 22_200; }
        else { name = "日出"; start = 22_201; end = 23_999; }
        var segmentPercent = RoundedPercent(daytime - start, end - start);
        var wholePercent = RoundedPercent(daytime, 24_000);
        return $"daytime={daytime}，{name}{segmentPercent}%，全天{wholePercent}%";
    }

    private static int RoundedPercent(long numerator, long denominator)
    {
        if (denominator <= 0) return 100;
        var value = Math.Round((double)numerator * 100.0 / denominator, MidpointRounding.AwayFromZero);
        return Math.Clamp((int)value, 0, 100);
    }

    private sealed record EnvironmentTickingAreaRecord(EnvironmentTickingAreaSpec Area, NbtDocument Document, NbtEncoding Encoding, byte[]? DatabaseKey);

    private List<EnvironmentTickingAreaRecord> ReadTickingAreas()
    {
        var entries = _database.Entries(NativeTickingAreaPrefix, includeValues: true).ToArray();
        var result = new List<EnvironmentTickingAreaRecord>();
        foreach (var entry in entries)
        {
            if (entry.Value is null || entry.Value.Length == 0) continue;
            var roots = ConsecutiveNbtCodec.Decode(entry.Value);
            if (roots.Count != 1)
                throw new InvalidDataException("tickingarea_ 记录必须只包含一个 NBT 根。");
            var source = roots[0];
            result.Add(new EnvironmentTickingAreaRecord(DecodeTickingArea(source.Document), source.Document, source.Encoding, entry.Key.ToArray()));
        }
        return result;
    }

    private void SaveTickingAreas(IReadOnlyList<EnvironmentTickingAreaRecord> records)
    {
        if (records.Count > 10) throw new InvalidDataException("基岩版每个世界最多支持 10 个常加载区域。");
        foreach (var record in records) EnvironmentCommandParser.ValidateTickingAreaSpec(record.Area);

        var existingKeys = _database.Entries(NativeTickingAreaPrefix, includeValues: false).Select(entry => entry.Key).ToArray();
        var usedKeys = new HashSet<string>(StringComparer.Ordinal);
        var puts = new List<WorldDatabasePut>(records.Count);
        foreach (var record in records)
        {
            byte[] key;
            if (record.DatabaseKey is byte[] existingKey
                && existingKey.Length > 0
                && existingKey.AsSpan().StartsWith(NativeTickingAreaPrefix)
                && !usedKeys.Contains(Convert.ToHexString(existingKey)))
            {
                key = existingKey.ToArray();
            }
            else
            {
                key = MakeUniqueTickingAreaKey(usedKeys);
            }
            usedKeys.Add(Convert.ToHexString(key));
            var document = UpdateTickingAreaDocument(record.Document, record.Area.Normalized);
            puts.Add(new WorldDatabasePut(key, BedrockNbtCodec.Encode(document, record.Encoding)));
        }
        var deletes = existingKeys.Where(key => !usedKeys.Contains(Convert.ToHexString(key))).Select(key => key.ToArray()).ToArray();
        _database.ApplyBatch(puts, deletes, sync: true);
    }

    private static byte[] MakeUniqueTickingAreaKey(HashSet<string> usedKeys)
    {
        while (true)
        {
            var key = Encoding.UTF8.GetBytes("tickingarea_" + Guid.NewGuid().ToString("D").ToLowerInvariant());
            if (!usedKeys.Contains(Convert.ToHexString(key))) return key;
        }
    }

    private static EnvironmentTickingAreaRecord MakeTickingAreaRecord(EnvironmentTickingAreaSpec area)
    {
        var document = UpdateTickingAreaDocument(new NbtDocument(string.Empty, new NbtCompoundValue([])), area.Normalized);
        return new EnvironmentTickingAreaRecord(area.Normalized, document, NbtEncoding.LittleEndian, null);
    }

    private static EnvironmentTickingAreaSpec DecodeTickingArea(NbtDocument document)
    {
        if (document.Root is not NbtCompoundValue compound) throw new InvalidDataException("tickingarea 根标签不是 Compound。");
        NbtValue? Value(string name) => compound.Tags.FirstOrDefault(tag => tag.Name == name)?.Value;
        int? Integer(string name) => Value(name) switch
        {
            NbtByteValue value => value.Value,
            NbtShortValue value => value.Value,
            NbtIntValue value => value.Value,
            NbtLongValue value => value.Value > int.MaxValue ? int.MaxValue : value.Value < int.MinValue ? int.MinValue : (int)value.Value,
            _ => null
        };
        var dimension = Integer("Dimension");
        var minX = Integer("MinX");
        var minZ = Integer("MinZ");
        var maxX = Integer("MaxX");
        var maxZ = Integer("MaxZ");
        if (!dimension.HasValue || !minX.HasValue || !minZ.HasValue || !maxX.HasValue || !maxZ.HasValue)
            throw new InvalidDataException("tickingarea 缺少 Dimension/MinX/MinZ/MaxX/MaxZ。");
        var name = Value("Name") is NbtStringValue text ? text.Value : string.Empty;
        return new EnvironmentTickingAreaSpec(
            dimension.Value,
            (Integer("IsCircle") ?? 0) != 0,
            minX.Value,
            minZ.Value,
            maxX.Value,
            maxZ.Value,
            name,
            (Integer("Preload") ?? 0) != 0).Normalized;
    }

    private static NbtDocument UpdateTickingAreaDocument(NbtDocument document, EnvironmentTickingAreaSpec area)
    {
        var tags = document.Root is NbtCompoundValue compound ? compound.Tags.ToList() : [];
        SetExact(tags, "Dimension", new NbtIntValue(area.Dimension));
        SetExact(tags, "IsCircle", new NbtByteValue(area.IsCircle ? (sbyte)1 : (sbyte)0));
        SetExact(tags, "MaxX", new NbtIntValue(area.MaximumX));
        SetExact(tags, "MaxZ", new NbtIntValue(area.MaximumZ));
        SetExact(tags, "MinX", new NbtIntValue(area.MinimumX));
        SetExact(tags, "MinZ", new NbtIntValue(area.MinimumZ));
        SetExact(tags, "Name", new NbtStringValue(area.Name));
        SetExact(tags, "Preload", new NbtByteValue(area.Preload ? (sbyte)1 : (sbyte)0));
        return document with { Root = new NbtCompoundValue(tags) };
    }

    private static string TickingAreaLine(EnvironmentTickingAreaSpec area, int index)
    {
        var value = area.Normalized;
        var name = string.IsNullOrEmpty(value.Name) ? "未命名" : value.Name;
        if (value.IsCircle)
        {
            var center = value.CenterChunk;
            return $"[{index}]{name}: {center.X} {center.Z} radius: {value.Radius}";
        }
        return $"[{index}]{name}: {value.MinimumX} {value.MinimumZ} to {value.MaximumX} {value.MaximumZ}";
    }
}
