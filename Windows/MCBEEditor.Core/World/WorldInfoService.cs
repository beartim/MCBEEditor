using System.Globalization;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;

namespace MCBEEditor.Core.World;

public sealed record WorldInfoRow(string Title, string Value);

public sealed class WorldInfoService
{
    public IReadOnlyList<WorldInfoRow> Inspect(WorldDocument document)
    {
        var file = document.ReadLevelDat();
        var root = file.Document.Root;
        var stats = GetFileStats(document.RootPath);
        var dbStats = Directory.Exists(document.DatabasePath) ? GetFileStats(document.DatabasePath) : default;

        using var database = document.OpenDatabase(readOnly: true);
        var players = new PlayerNbtStore(database);
        var playerRecords = players.Records();
        var playerCount = playerRecords.Count;
        var enchantmentPlayer = playerRecords.FirstOrDefault(record => record.IsLocal) ?? playerRecords.FirstOrDefault();
        var enchantmentSeed = enchantmentPlayer is null
            ? "未记录"
            : NumericValue(enchantmentPlayer.Document.Root, "EnchantmentSeed", "enchantmentSeed", "enchantment_seed")?.ToString(CultureInfo.InvariantCulture) ?? "未记录";

        var entityScan = new BedrockWorldObjectScanner(database).ScanAll(
            null, includeEntities: true, includeBlockEntities: false, maximumObjects: 1_000_000);
        var entityCount = entityScan.Objects.Count(item => item.Kind == BedrockWorldObjectKind.Entity);

        var chunks = new HashSet<ChunkPosition>();
        foreach (var entry in database.Entries(Array.Empty<byte>(), includeValues: false))
            if (BedrockDbKey.TryParse(entry.Key, out var key)) chunks.Add(key.Position);
        var chunkCount = chunks.Count;

        var villageCount = new VillageNbtStore(database).ScanRecords().Records
            .Select(record => record.VillageIdentifier)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Count();

        var rows = new List<WorldInfoRow>
        {
            new("名称", root.CompoundValueIgnoreCase("LevelName") is NbtStringValue name ? name.Value : Path.GetFileName(document.RootPath)),
            new("种子", NumericValue(root, "RandomSeed", "randomSeed", "random_seed")?.ToString(CultureInfo.InvariantCulture) ?? "未记录"),
            new("附魔种子", enchantmentSeed),
            new("玩家数目", playerCount.ToString(CultureInfo.InvariantCulture)),
            new("实体数目", entityCount.ToString(CultureInfo.InvariantCulture)),
            new("区块数目", chunkCount.ToString(CultureInfo.InvariantCulture)),
            new("村庄数目", villageCount.ToString(CultureInfo.InvariantCulture)),
            new("level.dat 版本", file.Version.ToString(CultureInfo.InvariantCulture))
        };

        AppendInteger(rows, root, "StorageVersion", "存储版本");
        AppendInteger(rows, root, "NetworkVersion", "网络版本");
        rows.Add(new("最后打开的游戏版本", VersionString(root, "lastOpenedWithVersion", "LastOpenedWithVersion", "last_opened_with_version") ?? "未记录"));
        rows.Add(new("最小兼容的游戏版本", VersionString(root, "MinimumCompatibleClientVersion", "minimumCompatibleClientVersion", "MinimumCompatibleVersion") ?? "未记录"));

        if (root.IntValue("GameType") is int gameType)
            rows.Add(new("游戏模式", GameTypeName(gameType)));
        if (root.IntValue("Difficulty") is int difficulty)
            rows.Add(new("难度", DifficultyName(difficulty)));

        if (root.IntValue("SpawnX") is int spawnX && root.IntValue("SpawnY") is int spawnY && root.IntValue("SpawnZ") is int spawnZ)
            rows.Add(new("出生点", $"{spawnX}, {spawnY}, {spawnZ}"));

        if (NumericValue(root, "LastPlayed") is long lastPlayed)
            rows.Add(new("最后游玩", FormatTimestamp(lastPlayed)));

        rows.Add(new("世界大小", FormatBytes(stats.Size)));
        rows.Add(new("数据库大小", FormatBytes(dbStats.Size)));
        rows.Add(new("文件数量", stats.Count.ToString(CultureInfo.InvariantCulture)));
        rows.Add(new("世界目录", document.RootPath));
        return rows;
    }

    private static long? NumericValue(NbtValue root, params string[] names)
        => root.CompoundValueIgnoreCase(names)?.IntegerValue();

    private static void AppendInteger(List<WorldInfoRow> rows, NbtValue root, string name, string title)
    {
        var value = root.CompoundValue(name)?.IntegerValue();
        if (value is not null)
            rows.Add(new(title, value.Value.ToString(CultureInfo.InvariantCulture)));
    }

    private static string? VersionString(NbtValue root, params string[] names)
    {
        return root.CompoundValueIgnoreCase(names) switch
        {
            NbtStringValue value when !string.IsNullOrEmpty(value.Value) => value.Value,
            NbtIntArrayValue value => FormatVersion(value.Values.Select(v => (long)v)),
            NbtLongArrayValue value => FormatVersion(value.Values),
            NbtListValue value => FormatVersionList(value),
            NbtValue value when value.IntegerValue() is long number => number.ToString(CultureInfo.InvariantCulture),
            _ => null
        };
    }

    private static string? FormatVersionList(NbtListValue value)
    {
        var numbers = value.Values.Select(v => v.IntegerValue()).ToArray();
        return numbers.All(v => v.HasValue) ? FormatVersion(numbers.Select(v => v!.Value)) : null;
    }

    private static string? FormatVersion(IEnumerable<long> source)
    {
        var values = source.ToList();
        if (values.Count == 0) return null;
        while (values.Count > 3 && values[^1] == 0) values.RemoveAt(values.Count - 1);
        return string.Join('.', values);
    }

    private static string GameTypeName(int value) => value switch
    {
        0 => "生存（0）",
        1 => "创造（1）",
        2 => "冒险（2）",
        3 => "旁观（3）",
        _ => $"未知（{value}）"
    };

    private static string DifficultyName(int value) => value switch
    {
        0 => "和平（0）",
        1 => "简单（1）",
        2 => "普通（2）",
        3 => "困难（3）",
        _ => $"未知（{value}）"
    };

    private static string FormatTimestamp(long value)
    {
        if (value <= 0) return value.ToString(CultureInfo.InvariantCulture);
        try
        {
            return DateTimeOffset.FromUnixTimeSeconds(value).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.CurrentCulture);
        }
        catch (ArgumentOutOfRangeException)
        {
            return value.ToString(CultureInfo.InvariantCulture);
        }
    }

    private static (long Size, int Count) GetFileStats(string path)
    {
        long size = 0;
        var count = 0;
        foreach (var file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
        {
            size += new FileInfo(file).Length;
            count++;
        }
        return (size, count);
    }

    private static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        double value = Math.Max(0, bytes);
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }
        return unit == 0 ? $"{value:0} {units[unit]}" : $"{value:0.##} {units[unit]}";
    }
}
