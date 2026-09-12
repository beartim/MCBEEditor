using System.IO.Compression;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.World;

public sealed record BedrockWeatherSettings(float RainLevel, int RainTime, float LightningLevel, int LightningTime, bool AutomaticChange)
{
    public string ConditionName => LightningLevel > 0.01f ? "雷暴" : RainLevel > 0.01f ? "下雨" : "晴朗";
    public static BedrockWeatherSettings Clear(bool automaticChange, int duration = 12_000) => new(0, Math.Max(0, duration), 0, Math.Max(0, duration), automaticChange);
    public static BedrockWeatherSettings Rain(int duration, float intensity, bool automaticChange)
    {
        var level = Math.Clamp(float.IsFinite(intensity) ? intensity : 0, 0, 1);
        return new(level, Math.Max(0, duration), 0, Math.Max(0, duration), automaticChange);
    }
    public static BedrockWeatherSettings Thunder(int duration, float intensity, bool automaticChange)
    {
        var level = Math.Clamp(float.IsFinite(intensity) ? intensity : 0, 0, 1);
        return new(level, Math.Max(0, duration), level, Math.Max(0, duration), automaticChange);
    }
}

public static class WorldWeatherStore
{
    public static BedrockWeatherSettings Read(WorldDocument world)
    {
        var file = world.ReadLevelDat();
        var tags = RootTags(file.Document);
        return new BedrockWeatherSettings(
            Math.Clamp(Float(tags, "rainLevel"), 0, 1),
            Math.Max(0, Integer(tags, "rainTime")),
            Math.Clamp(Float(tags, "lightningLevel"), 0, 1),
            Math.Max(0, Integer(tags, "lightningTime")),
            Boolean(tags, "doWeatherCycle", true));
    }

    public static void Save(WorldDocument world, BedrockWeatherSettings settings)
    {
        var file = world.ReadLevelDat();
        var tags = RootTags(file.Document).ToList();
        SetExact(tags, "rainLevel", new NbtFloatValue(Math.Clamp(settings.RainLevel, 0, 1)));
        SetExact(tags, "rainTime", new NbtIntValue(Math.Max(0, settings.RainTime)));
        SetExact(tags, "lightningLevel", new NbtFloatValue(Math.Clamp(settings.LightningLevel, 0, 1)));
        SetExact(tags, "lightningTime", new NbtIntValue(Math.Max(0, settings.LightningTime)));
        SetExact(tags, "doWeatherCycle", new NbtByteValue(settings.AutomaticChange ? (sbyte)1 : (sbyte)0));
        world.WriteLevelDat(file with { Document = file.Document with { Root = new NbtCompoundValue(tags) } });
    }

    private static IReadOnlyList<NbtNamedTag> RootTags(NbtDocument document) => document.Root is NbtCompoundValue root
        ? root.Tags : throw new InvalidDataException("level.dat 根标签不是 Compound。");
    private static NbtValue? Value(IReadOnlyList<NbtNamedTag> tags, string name) => tags.FirstOrDefault(tag => tag.Name == name)?.Value;
    private static float Float(IReadOnlyList<NbtNamedTag> tags, string name) => Value(tags, name) switch
    {
        NbtFloatValue v => v.Value,
        NbtDoubleValue v => (float)v.Value,
        NbtIntValue v => v.Value,
        _ => 0
    };
    private static int Integer(IReadOnlyList<NbtNamedTag> tags, string name) => Value(tags, name) switch
    {
        NbtByteValue v => v.Value,
        NbtShortValue v => v.Value,
        NbtIntValue v => v.Value,
        NbtLongValue v => (int)Math.Clamp(v.Value, int.MinValue, int.MaxValue),
        _ => 0
    };
    private static bool Boolean(IReadOnlyList<NbtNamedTag> tags, string name, bool defaultValue) => Value(tags, name) is null ? defaultValue : Integer(tags, name) != 0;
    private static void SetExact(List<NbtNamedTag> tags, string name, NbtValue value)
    {
        var index = tags.FindIndex(tag => tag.Name == name);
        if (index >= 0) tags[index] = new NbtNamedTag(name, value); else tags.Add(new NbtNamedTag(name, value));
    }
}

public sealed record BedrockTimeSettings(long Time, bool AutomaticProgression)
{
    public long Daytime => EnvironmentCommandStore.PositiveRemainder(Time, 24_000);
    public long Day => EnvironmentCommandStore.FloorDivision(Time, 24_000);
    public string Summary => EnvironmentCommandStore.DaytimeSummary(Time);
}

public static class WorldTimeStore
{
    public static BedrockTimeSettings Read(WorldDocument world)
    {
        var file = world.ReadLevelDat();
        if (file.Document.Root is not NbtCompoundValue root) throw new InvalidDataException("level.dat 根标签不是 Compound。");
        return new BedrockTimeSettings(Integer(root.Tags, "Time", 0), Integer(root.Tags, "dodaylightcycle", 1) != 0);
    }

    public static void Save(WorldDocument world, BedrockTimeSettings settings)
    {
        var file = world.ReadLevelDat();
        if (file.Document.Root is not NbtCompoundValue root) throw new InvalidDataException("level.dat 根标签不是 Compound。");
        var tags = root.Tags.ToList();
        SetIgnoreCase(tags, "Time", new NbtLongValue(settings.Time));
        SetIgnoreCase(tags, "dodaylightcycle", new NbtByteValue(settings.AutomaticProgression ? (sbyte)1 : (sbyte)0));
        world.WriteLevelDat(file with { Document = file.Document with { Root = new NbtCompoundValue(tags) } });
    }

    private static long Integer(IReadOnlyList<NbtNamedTag> tags, string name, long fallback)
    {
        var value = tags.FirstOrDefault(tag => string.Equals(tag.Name, name, StringComparison.OrdinalIgnoreCase))?.Value;
        if (value is null) return fallback;
        return value switch
        {
            NbtByteValue v => v.Value,
            NbtShortValue v => v.Value,
            NbtIntValue v => v.Value,
            NbtLongValue v => v.Value,
            _ => throw new InvalidDataException($"level.dat 的 {name} 标签必须是整数类型。")
        };
    }
    private static void SetIgnoreCase(List<NbtNamedTag> tags, string name, NbtValue value)
    {
        var matches = Enumerable.Range(0, tags.Count).Where(i => string.Equals(tags[i].Name, name, StringComparison.OrdinalIgnoreCase)).ToArray();
        if (matches.Length == 0) { tags.Add(new NbtNamedTag(name, value)); return; }
        tags[matches[0]] = new NbtNamedTag(name, value);
        for (var i = matches.Length - 1; i >= 1; i--) tags.RemoveAt(matches[i]);
    }
}

public sealed record PlayerExperienceRecord(PlayerNbtRecord Player, long? UniqueId, BedrockPlayerExperience Experience);

public static class WorldExperienceStore
{
    public static IReadOnlyList<PlayerExperienceRecord> Records(IWorldDatabase database)
    {
        var store = new PlayerNbtStore(database);
        return store.Records().Select(player => new PlayerExperienceRecord(player, store.UniqueId(player), TargetingCommandStore.ReadExperience(player.Document))).ToArray();
    }

    public static void Save(IWorldDatabase database, PlayerNbtRecord player, BedrockPlayerExperience experience)
    {
        var store = new PlayerNbtStore(database);
        store.Save(player, TargetingCommandStore.ExperienceDocument(player.Document, experience.Bounded()));
    }
}

public static class WorldArchiveService
{
    public static void ExportMcworld(WorldDocument world, string destinationPath)
    {
        if (string.IsNullOrWhiteSpace(destinationPath)) throw new ArgumentException("导出路径不能为空。", nameof(destinationPath));
        var root = Path.GetFullPath(world.RootPath).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var destination = Path.GetFullPath(destinationPath);
        if (destination.Equals(root, StringComparison.OrdinalIgnoreCase) || destination.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(".mcworld 不能导出到当前世界目录内部。请选择其它目录。 ");
        var parent = Path.GetDirectoryName(destination) ?? throw new IOException("导出目标没有父目录。");
        Directory.CreateDirectory(parent);
        var configuredCache = Environment.GetEnvironmentVariable("MCBEEDITOR_CACHE_ROOT");
        var tempParent = string.IsNullOrWhiteSpace(configuredCache)
            ? parent
            : Path.Combine(Path.GetFullPath(configuredCache), "Export");
        Directory.CreateDirectory(tempParent);
        var temp = Path.Combine(tempParent, $"{Path.GetFileName(destination)}.{Guid.NewGuid():N}.tmp");
        try
        {
            if (File.Exists(temp)) File.Delete(temp);
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: false))
            {
                foreach (var path in Directory.EnumerateFileSystemEntries(root, "*", SearchOption.AllDirectories))
                {
                    var relative = Path.GetRelativePath(root, path).Replace('\\', '/');
                    if (IsEditorPrivateRelativePath(relative)) continue;
                    if (Directory.Exists(path))
                    {
                        if (!Directory.EnumerateFileSystemEntries(path).Any())
                            archive.CreateEntry(relative.TrimEnd('/') + "/");
                        continue;
                    }
                    archive.CreateEntryFromFile(path, relative, CompressionLevel.Optimal);
                }
            }
            File.Move(temp, destination, overwrite: true);
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
    }
    private static bool IsEditorPrivateRelativePath(string relativePath)
    {
        var components = relativePath.Replace('\\', '/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (relativePath.Replace('\\', '/').Equals("db/LOCK", StringComparison.OrdinalIgnoreCase)) return true;
        if (components.Length == 0) return false;
        var first = components[0].ToLowerInvariant();
        if (first == ".mcbeeditor" || first.StartsWith(".mcbeeditor-", StringComparison.Ordinal)
            || first == "mcbeeditor" || first.StartsWith("mcbeeditor.", StringComparison.Ordinal)
            || first.StartsWith("mcbeeditor-", StringComparison.Ordinal))
            return true;
        return components.Any(component =>
        {
            var value = component.ToLowerInvariant();
            return value == "map-display-preferences.json"
                || value == "editor-settings.json"
                || value == "editor-preferences.json";
        });
    }

}
