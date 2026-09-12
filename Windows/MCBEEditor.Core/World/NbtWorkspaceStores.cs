using System.Text;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.Entity;

namespace MCBEEditor.Core.World;

public sealed record MetadataNbtRename(MetadataNbtRecord Record, string NewKeyText);

public sealed record MetadataNbtRecord(
    byte[] Key,
    string KeyText,
    string DisplayName,
    byte[] RawData,
    IReadOnlyList<ConsecutiveNbtRecord>? Roots,
    string? DecodeError)
{
    public string DetailText => Roots is null
        ? $"无法解析为 NBT · {RawData.Length:N0} B"
        : $"NBT 根标签 {Roots.Count:N0} · {RawData.Length:N0} B";
}

public sealed class MetadataNbtStore
{
    public static readonly IReadOnlyList<string> ExactKeys =
    [
        "AutonomousEntities", "BiomeData", "mVillages", "Nether", "Overworld", "TheEnd",
        "portals", "dimension0", "scoreboard", "mobevents", "schedulerWT"
    ];

    private static readonly HashSet<string> ExactKeySet = new(ExactKeys, StringComparer.Ordinal);
    private readonly IWorldDatabase _database;

    public MetadataNbtStore(IWorldDatabase database)
        => _database = database ?? throw new ArgumentNullException(nameof(database));

    public IReadOnlyList<MetadataNbtRecord> Records()
    {
        var records = new List<MetadataNbtRecord>();
        foreach (var entry in _database.Entries(includeValues: true))
        {
            if (entry.Value is null || !TryUtf8(entry.Key, out var keyText) || !IsMetadataKey(keyText)) continue;
            records.Add(MakeRecord(entry.Key, entry.Value));
        }
        return records.OrderBy(record => SortKey(record.KeyText), StringComparer.OrdinalIgnoreCase).ToArray();
    }

    public MetadataNbtRecord? Record(ReadOnlySpan<byte> key)
    {
        var value = _database.Get(key);
        return value is null ? null : MakeRecord(key.ToArray(), value);
    }

    public void Save(MetadataNbtRecord record, IReadOnlyList<ConsecutiveNbtRecord> roots)
    {
        ArgumentNullException.ThrowIfNull(record);
        ArgumentNullException.ThrowIfNull(roots);
        if (roots.Count == 0) throw new InvalidDataException("至少需要保留一个 NBT 根标签。");
        _database.Put(record.Key, ConsecutiveNbtCodec.Encode(roots), sync: true);
    }

    public MetadataNbtRecord Create(string keyText, IReadOnlyList<NbtDocument> documents, bool overwrite = false)
    {
        var normalized = ValidateKeyText(keyText);
        if (documents.Count == 0) throw new InvalidDataException("至少需要一个 NBT 根标签。");
        var key = Encoding.UTF8.GetBytes(normalized);
        if (!overwrite && _database.Get(key) is not null) throw new InvalidDataException($"已存在同名元数据键：{normalized}");
        var roots = documents.Select(document => new ConsecutiveNbtRecord(document, [], NbtEncoding.LittleEndian)).ToArray();
        var encoded = ConsecutiveNbtCodec.Encode(roots);
        _database.Put(key, encoded, sync: true);
        var readBack = _database.Get(key);
        if (readBack is null || !readBack.AsSpan().SequenceEqual(encoded)) throw new InvalidDataException("元数据写入后未能从 LevelDB 读回。");
        return MakeRecord(key, encoded);
    }

    public void Rename(MetadataNbtRecord record, string newKeyText, bool overwrite = false)
    {
        var normalized = ValidateKeyText(newKeyText);
        var targetKey = Encoding.UTF8.GetBytes(normalized);
        if (targetKey.AsSpan().SequenceEqual(record.Key)) return;
        if (!overwrite && _database.Get(targetKey) is not null) throw new InvalidDataException($"已存在同名元数据键：{normalized}");
        _database.ApplyBatch([new WorldDatabasePut(targetKey, record.RawData)], [record.Key], sync: true);
    }

    public void Delete(MetadataNbtRecord record) => _database.Delete(record.Key, sync: true);

    public int Delete(IEnumerable<MetadataNbtRecord> records)
    {
        var keys = records.Select(record => record.Key).Distinct(ByteArrayComparer.Instance).ToArray();
        if (keys.Length == 0) return 0;
        _database.ApplyBatch([], keys, sync: true);
        return keys.Length;
    }

    public void RenameBatch(IEnumerable<MetadataNbtRename> renames)
    {
        ArgumentNullException.ThrowIfNull(renames);
        var items = renames.Select(item =>
        {
            var text = ValidateKeyText(item.NewKeyText);
            return (Record: item.Record, Text: text, Key: Encoding.UTF8.GetBytes(text));
        }).ToArray();
        if (items.Length == 0) return;

        var sourceKeys = items.Select(item => item.Record.Key).ToArray();
        var destinationKeys = items.Select(item => item.Key).ToArray();
        if (destinationKeys.Distinct(ByteArrayComparer.Instance).Count() != destinationKeys.Length)
            throw new InvalidDataException("批量重命名后产生了重复的元数据键。");

        foreach (var item in items)
        {
            var destinationIsSelectedSource = sourceKeys.Any(source => source.AsSpan().SequenceEqual(item.Key));
            if (!destinationIsSelectedSource && _database.Get(item.Key) is not null)
                throw new InvalidDataException($"目标元数据键已存在：{item.Text}");
        }

        var changed = items.Where(item => !item.Key.AsSpan().SequenceEqual(item.Record.Key)).ToArray();
        if (changed.Length == 0) return;
        _database.ApplyBatch(
            changed.Select(item => new WorldDatabasePut(item.Key, item.Record.RawData)),
            changed.Select(item => item.Record.Key),
            sync: true);
    }

    public static bool IsMetadataKey(string key) => ExactKeySet.Contains(key) || key.StartsWith("map_", StringComparison.Ordinal);

    public static string ValidateKeyText(string key)
    {
        var clean = key?.Trim() ?? string.Empty;
        if (clean.Length == 0) throw new InvalidDataException("元数据键不能为空。");
        if (clean.IndexOfAny(new[] { '\0', '\r', '\n' }) >= 0) throw new InvalidDataException("元数据键包含无效字符。");
        if (!IsMetadataKey(clean)) throw new NotSupportedException($"“{clean}”不属于当前支持的世界元数据键。可使用固定元数据键或 map_* 地图键。");
        return clean;
    }

    public static MetadataNbtRecord MakeRecord(byte[] key, byte[] value)
    {
        var keyText = TryUtf8(key, out var text) ? text : "0x" + Convert.ToHexString(key).ToLowerInvariant();
        try
        {
            var roots = ConsecutiveNbtCodec.Decode(value);
            if (roots.Count == 0) return new MetadataNbtRecord(key.ToArray(), keyText, DisplayName(keyText), value.ToArray(), null, "NBT 值为空");
            return new MetadataNbtRecord(key.ToArray(), keyText, DisplayName(keyText), value.ToArray(), roots, null);
        }
        catch (Exception ex)
        {
            return new MetadataNbtRecord(key.ToArray(), keyText, DisplayName(keyText), value.ToArray(), null, ex.Message);
        }
    }

    private static string DisplayName(string key) => key switch
    {
        "AutonomousEntities" => "自主实体",
        "BiomeData" => "生物群系数据",
        "mVillages" => "旧版村庄",
        "Nether" => "下界元数据",
        "Overworld" => "主世界元数据",
        "TheEnd" => "末地元数据",
        "portals" => "传送门",
        "dimension0" => "维度 0",
        "scoreboard" => "计分板",
        "mobevents" => "生物事件",
        "schedulerWT" => "计划刻",
        _ when key.StartsWith("map_", StringComparison.Ordinal) => "地图 " + key[4..],
        _ => key
    };

    private static string SortKey(string key)
    {
        for (var index = 0; index < ExactKeys.Count; index++)
            if (string.Equals(ExactKeys[index], key, StringComparison.Ordinal)) return index.ToString("D3") + "_" + key;
        return key.StartsWith("map_", StringComparison.Ordinal) ? "100_" + key : "999_" + key;
    }

    internal static bool TryUtf8(ReadOnlySpan<byte> bytes, out string value)
    {
        try
        {
            value = new UTF8Encoding(false, true).GetString(bytes);
            return true;
        }
        catch (DecoderFallbackException)
        {
            value = string.Empty;
            return false;
        }
    }

    private sealed class ByteArrayComparer : IEqualityComparer<byte[]>
    {
        public static readonly ByteArrayComparer Instance = new();
        public bool Equals(byte[]? x, byte[]? y) => x is not null && y is not null && x.AsSpan().SequenceEqual(y);
        public int GetHashCode(byte[] obj)
        {
            var hash = new HashCode();
            foreach (var value in obj) hash.Add(value);
            return hash.ToHashCode();
        }
    }
}

public sealed record StructureNbtRecord(
    byte[] Key,
    string KeyText,
    string DisplayName,
    NbtDocument? Document,
    byte[] RawData,
    NbtEncoding? Encoding,
    string? DecodeError)
{
    public string DetailText
    {
        get
        {
            var parts = new List<string>();
            if (Document is not null)
            {
                var size = IntegerVector(Document.Root.CompoundValue("size"));
                if (size is { Count: >= 3 }) parts.Add($"尺寸 {size[0]}×{size[1]}×{size[2]}");
                var origin = IntegerVector(Document.Root.CompoundValue("structure_world_origin"));
                if (origin is { Count: >= 3 }) parts.Add($"原点 ({origin[0]}, {origin[1]}, {origin[2]})");
                if (Document.Root.IntValue("format_version") is int version) parts.Add($"格式 {version}");
            }
            else parts.Add("NBT 无法解析");
            parts.Add($"{RawData.Length:N0} B");
            return string.Join(" · ", parts);
        }
    }

    private static IReadOnlyList<long>? IntegerVector(NbtValue? value) => value switch
    {
        NbtIntArrayValue ints => ints.Values.Select(item => (long)item).ToArray(),
        NbtLongArrayValue longs => longs.Values.ToArray(),
        NbtListValue list => list.Values.Select(item => item.IntegerValue()).All(item => item.HasValue)
            ? list.Values.Select(item => item.IntegerValue()!.Value).ToArray()
            : null,
        _ => null
    };
}

public sealed class StructureNbtStore
{
    public const string KeyPrefix = "structuretemplate";
    private readonly IWorldDatabase _database;

    public StructureNbtStore(IWorldDatabase database)
        => _database = database ?? throw new ArgumentNullException(nameof(database));

    public IReadOnlyList<StructureNbtRecord> Records()
    {
        var prefix = Encoding.UTF8.GetBytes(KeyPrefix);
        return _database.Entries(prefix, includeValues: true)
            .Where(entry => entry.Value is not null)
            .Select(entry => MakeRecord(entry.Key, entry.Value!))
            .OrderBy(record => record.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(record => record.KeyText, StringComparer.Ordinal)
            .ToArray();
    }

    public void Save(StructureNbtRecord record, NbtDocument document)
    {
        var encoding = record.Encoding ?? throw new NotSupportedException("无法确定该结构记录的 NBT 编码，不能安全写回。");
        _database.Put(record.Key, BedrockNbtCodec.Encode(document, encoding), sync: true);
    }

    public bool Contains(string name) => _database.Get(KeyForName(name)) is not null;

    public StructureImportResult SaveNew(NbtDocument document, string name, bool overwrite = true)
    {
        var conversion = JavaStructureConverter.ConvertIfNeeded(document);
        var key = KeyForName(name);
        if (!overwrite && _database.Get(key) is not null) throw new InvalidDataException($"已存在同名结构：{NormalizeName(name)}");
        var encoded = BedrockNbtCodec.Encode(conversion.Document, NbtEncoding.LittleEndian);
        _database.Put(key, encoded, sync: true);
        var readBack = _database.Get(key);
        if (readBack is null || !readBack.AsSpan().SequenceEqual(encoded)) throw new InvalidDataException("结构写入后未能从 LevelDB 读回。");
        return conversion.Result;
    }

    public StructureImportResult Import(byte[] data, string filename, string name, bool overwrite = true)
    {
        var file = StandaloneNbtFileCodec.Decode(data, filename);
        if (file.Documents.Count != 1) throw new InvalidDataException("结构文件必须只包含一个 NBT 根标签。");
        return SaveNew(file.Documents[0], name, overwrite);
    }

    public void Rename(StructureNbtRecord record, string name, bool overwrite = false)
    {
        var target = KeyForName(name);
        if (target.AsSpan().SequenceEqual(record.Key)) return;
        if (!overwrite && _database.Get(target) is not null) throw new InvalidDataException($"已存在同名结构：{NormalizeName(name)}");
        _database.ApplyBatch([new WorldDatabasePut(target, record.RawData)], [record.Key], sync: true);
    }

    public void Delete(StructureNbtRecord record) => _database.Delete(record.Key, sync: true);

    private static IReadOnlyList<long>? IntegerVector(NbtValue? value) => value switch
    {
        NbtIntArrayValue ints => ints.Values.Select(item => (long)item).ToArray(),
        NbtLongArrayValue longs => longs.Values.ToArray(),
        NbtListValue list => list.Values.Select(item => item.IntegerValue()).All(item => item.HasValue)
            ? list.Values.Select(item => item.IntegerValue()!.Value).ToArray()
            : null,
        _ => null
    };

    public static string NormalizeName(string name)
    {
        var clean = name?.Trim() ?? string.Empty;
        if (clean.StartsWith(KeyPrefix, StringComparison.Ordinal))
        {
            clean = clean[KeyPrefix.Length..];
            while (clean.Length > 0 && clean[0] is '_' or ':' or '/') clean = clean[1..];
        }
        return clean;
    }

    public static byte[] KeyForName(string name)
    {
        var clean = NormalizeName(name);
        if (clean.Length == 0) throw new InvalidDataException("结构名称不能为空。");
        if (clean.IndexOfAny(new[] { '\0', '\r', '\n' }) >= 0) throw new InvalidDataException("结构名称包含无效字符。");
        return Encoding.UTF8.GetBytes(KeyPrefix + "_" + clean);
    }

    private static StructureNbtRecord MakeRecord(byte[] key, byte[] raw)
    {
        var keyText = MetadataNbtStore.TryUtf8(key, out var text) ? text : "0x" + Convert.ToHexString(key).ToLowerInvariant();
        try
        {
            var decoded = NbtFileCodec.DecodeSingle(raw);
            return new StructureNbtRecord(key.ToArray(), keyText, DisplayName(keyText, decoded.Document), decoded.Document, raw.ToArray(), decoded.Encoding, null);
        }
        catch (Exception ex)
        {
            return new StructureNbtRecord(key.ToArray(), keyText, DisplayName(keyText, null), null, raw.ToArray(), null, ex.Message);
        }
    }

    private static string DisplayName(string keyText, NbtDocument? document)
    {
        var suffix = keyText;
        if (suffix.StartsWith(KeyPrefix, StringComparison.Ordinal)) suffix = suffix[KeyPrefix.Length..];
        while (suffix.Length > 0 && suffix[0] is '_' or ':' or '/') suffix = suffix[1..];
        if (suffix.Length > 0) return suffix;
        return !string.IsNullOrWhiteSpace(document?.RootName) ? document!.RootName.Trim() : "未命名结构";
    }
}

public enum VillageNbtRecordKind { Legacy, Info, Poi, Dwellers, Players, Other }

public abstract record VillageNbtPathComponent;
public sealed record VillageNbtCompoundPath(string Name) : VillageNbtPathComponent;
public sealed record VillageNbtListPath(int Index) : VillageNbtPathComponent;

public sealed record VillageNbtRecord(
    byte[] Key,
    string KeyText,
    string VillageIdentifier,
    VillageNbtRecordKind Kind,
    int DocumentIndex,
    int DocumentCount,
    IReadOnlyList<VillageNbtPathComponent> DocumentPath,
    NbtDocument Document,
    NbtEncoding Encoding,
    int RawValueSize,
    int? LegacyVillageIndex)
{
    public string KindText => Kind switch
    {
        VillageNbtRecordKind.Legacy => "旧版村庄信息",
        VillageNbtRecordKind.Info => "村庄信息",
        VillageNbtRecordKind.Poi => "兴趣点",
        VillageNbtRecordKind.Dwellers => "村庄居民",
        VillageNbtRecordKind.Players => "玩家声望",
        _ => "其他村庄数据"
    };

    public string VillageDisplayName => LegacyVillageIndex.HasValue
        ? $"旧版村庄 {LegacyVillageIndex.Value + 1}"
        : VillageIdentifier == "legacy" ? "旧版村庄数据" : $"村庄 {ShortIdentifier(VillageIdentifier)}";

    public string DisplayName => DocumentCount > 1 ? $"{KindText} [{DocumentIndex + 1}/{DocumentCount}]" : KindText;
    public string StableId => Convert.ToHexString(Key) + ":" + DocumentIndex + ":" + PathText(DocumentPath);
    public string DetailText => string.Join(" · ", new[]
    {
        string.IsNullOrEmpty(Document.RootName) ? null : "根 " + Document.RootName,
        DocumentPath.Count == 0 ? null : PathText(DocumentPath),
        $"{RawValueSize:N0} B",
        KeyText
    }.Where(item => item is not null));

    private static string ShortIdentifier(string value) => value.Length <= 20 ? value : value[..10] + "…" + value[^7..];
    public static string PathText(IReadOnlyList<VillageNbtPathComponent> path)
    {
        if (path.Count == 0) return "/";
        var result = new StringBuilder();
        foreach (var component in path)
        {
            if (component is VillageNbtCompoundPath compound) result.Append('/').Append(compound.Name);
            else if (component is VillageNbtListPath list) result.Append('[').Append(list.Index).Append(']');
        }
        return result.ToString();
    }
}

public sealed record VillageNbtScanResult(IReadOnlyList<VillageNbtRecord> Records, IReadOnlyList<string> Diagnostics);

public enum VillageResidentEntityKind { Villager, Cat, IronGolem, Other }

public sealed record VillageResidentResolution(
    IReadOnlyList<long> RequestedUniqueIds,
    IReadOnlyList<BedrockWorldObject> Entities,
    IReadOnlyList<long> UnresolvedUniqueIds,
    IReadOnlyList<string> Diagnostics)
{
    public IReadOnlyList<BedrockWorldObject> EntitiesOf(VillageResidentEntityKind kind)
        => Entities.Where(item => VillageNbtStore.ResidentKindFor(item) == kind).ToArray();
}

public sealed class VillageNbtStore
{
    private static readonly byte[] LegacyKey = Encoding.UTF8.GetBytes("mVillages");
    private static readonly byte[] ModernPrefix = Encoding.UTF8.GetBytes("VILLAGE_");
    private readonly IWorldDatabase _database;

    public VillageNbtStore(IWorldDatabase database)
        => _database = database ?? throw new ArgumentNullException(nameof(database));

    public VillageNbtScanResult ScanRecords()
    {
        var entries = new List<WorldDatabaseEntry>();
        var legacy = _database.Get(LegacyKey);
        if (legacy is not null) entries.Add(new WorldDatabaseEntry(LegacyKey.ToArray(), legacy));
        entries.AddRange(_database.Entries(ModernPrefix, includeValues: true).Where(entry => entry.Value is not null));

        var result = new List<VillageNbtRecord>();
        var diagnostics = new List<string>();
        foreach (var entry in entries)
        {
            var keyText = MetadataNbtStore.TryUtf8(entry.Key, out var text) ? text : "0x" + Convert.ToHexString(entry.Key).ToLowerInvariant();
            try
            {
                var decoded = ConsecutiveNbtCodec.Decode(entry.Value!);
                var metadata = Metadata(entry.Key, keyText);
                for (var index = 0; index < decoded.Count; index++)
                {
                    var decodedRecord = decoded[index];
                    if (metadata.Kind == VillageNbtRecordKind.Legacy)
                    {
                        var split = LegacyVillageRecords(entry.Key, keyText, index, decoded.Count, decodedRecord, entry.Value!.Length);
                        if (split.Count > 0) result.AddRange(split);
                        else result.Add(new VillageNbtRecord(entry.Key.ToArray(), keyText, "legacy", VillageNbtRecordKind.Legacy,
                            index, decoded.Count, [], decodedRecord.Document, decodedRecord.Encoding, entry.Value!.Length, null));
                    }
                    else
                    {
                        result.Add(new VillageNbtRecord(entry.Key.ToArray(), keyText, metadata.Identifier, metadata.Kind,
                            index, decoded.Count, [], decodedRecord.Document, decodedRecord.Encoding, entry.Value!.Length, null));
                    }
                }
            }
            catch (Exception ex)
            {
                diagnostics.Add(keyText + "：" + ex.Message);
            }
        }

        var sorted = result.OrderBy(record => record.VillageIdentifier, StringComparer.OrdinalIgnoreCase)
            .ThenBy(record => SortOrder(record.Kind))
            .ThenBy(record => record.KeyText, StringComparer.Ordinal)
            .ThenBy(record => record.DocumentIndex)
            .ThenBy(record => record.StableId, StringComparer.Ordinal)
            .ToArray();
        return new VillageNbtScanResult(sorted, diagnostics);
    }

    public VillageResidentResolution ResidentResolution(string villageIdentifier)
    {
        if (string.IsNullOrWhiteSpace(villageIdentifier)) throw new ArgumentException("村庄标识不能为空。", nameof(villageIdentifier));
        var scan = ScanRecords();
        var records = scan.Records.Where(record => string.Equals(record.VillageIdentifier, villageIdentifier, StringComparison.OrdinalIgnoreCase)).ToArray();
        var ids = records
            .Where(record => record.Kind is VillageNbtRecordKind.Dwellers or VillageNbtRecordKind.Legacy)
            .SelectMany(record => DwellerUniqueIds(record.Document.Root, record.Kind == VillageNbtRecordKind.Dwellers))
            .Distinct().OrderBy(value => value).ToArray();
        if (ids.Length == 0) return new VillageResidentResolution([], [], [], scan.Diagnostics);

        var requested = ids.ToHashSet();
        var entityScan = new BedrockWorldObjectScanner(_database).ScanAll(null, includeEntities: true, includeBlockEntities: false, maximumObjects: 200_000);
        var entities = entityScan.Objects
            .Where(item => item.Kind == BedrockWorldObjectKind.Entity && item.UniqueId is long id && requested.Contains(id))
            .GroupBy(item => item.UniqueId!.Value)
            .Select(group => group.First())
            .OrderBy(item => item.UniqueId).ToArray();
        var resolved = entities.Select(item => item.UniqueId!.Value).ToHashSet();
        var unresolved = ids.Where(id => !resolved.Contains(id)).ToArray();
        return new VillageResidentResolution(ids, entities, unresolved, scan.Diagnostics.Concat(entityScan.Diagnostics).ToArray());
    }

    public static VillageResidentEntityKind ResidentKindFor(BedrockWorldObject item)
    {
        if (item.Kind != BedrockWorldObjectKind.Entity) return VillageResidentEntityKind.Other;
        var identifier = item.Identifier.Trim().ToLowerInvariant();
        var local = identifier.Contains(':') ? identifier[(identifier.LastIndexOf(':') + 1)..] : identifier;
        return local switch
        {
            "villager" or "villager_v2" => VillageResidentEntityKind.Villager,
            "cat" => VillageResidentEntityKind.Cat,
            "iron_golem" or "irongolem" => VillageResidentEntityKind.IronGolem,
            _ => VillageResidentEntityKind.Other
        };
    }

    public static IReadOnlyList<long> DwellerUniqueIds(NbtValue root, bool rootIsDwellersRecord = true)
    {
        var containerNames = new HashSet<string>(["dwellers", "dweller", "residents", "resident", "villagers", "villager", "members", "member"], StringComparer.Ordinal);
        var identityNames = new HashSet<string>([
            "uniqueid", "actoruniqueid", "entityuniqueid", "dwelleruniqueid", "villageruniqueid", "residentuniqueid",
            "owneruniqueid", "occupantuniqueid", "actorid", "entityid", "dwellerid", "villagerid", "residentid"
        ], StringComparer.Ordinal);
        var result = new HashSet<long>();

        void Walk(NbtValue value, bool insideDwellers)
        {
            if (value is NbtCompoundValue compound)
            {
                foreach (var tag in compound.Tags)
                {
                    var name = Normalize(tag.Name);
                    var childInside = insideDwellers || containerNames.Contains(name);
                    if (childInside && (name == "id" || identityNames.Contains(name) || name.EndsWith("uniqueid", StringComparison.Ordinal)))
                        foreach (var id in NumericIdentifierValues(tag.Value)) result.Add(id);
                    Walk(tag.Value, childInside);
                }
            }
            else if (value is NbtListValue list)
            {
                foreach (var child in list.Values) Walk(child, insideDwellers);
            }
        }

        Walk(root, rootIsDwellersRecord);
        return result.OrderBy(value => value).ToArray();
    }

    public void Save(VillageNbtRecord record, NbtDocument document)
    {
        var current = _database.Get(record.Key) ?? throw new InvalidDataException("村庄记录已不存在，请返回列表重新读取。");
        var decoded = ConsecutiveNbtCodec.Decode(current).ToArray();
        if ((uint)record.DocumentIndex >= (uint)decoded.Length) throw new InvalidDataException("村庄记录中的 NBT 数量已经变化，请返回列表重新读取。");
        if (record.DocumentPath.Count == 0)
        {
            decoded[record.DocumentIndex] = decoded[record.DocumentIndex] with { Document = document };
        }
        else
        {
            var container = decoded[record.DocumentIndex].Document;
            var root = ReplaceValue(container.Root, record.DocumentPath, 0, document.Root);
            decoded[record.DocumentIndex] = decoded[record.DocumentIndex] with { Document = new NbtDocument(container.RootName, root) };
        }
        _database.Put(record.Key, ConsecutiveNbtCodec.Encode(decoded), sync: true);
    }

    private static (string Identifier, VillageNbtRecordKind Kind) Metadata(byte[] key, string keyText)
    {
        if (key.AsSpan().SequenceEqual(LegacyKey)) return ("legacy", VillageNbtRecordKind.Legacy);
        if (!key.AsSpan().StartsWith(ModernPrefix)) return (keyText, VillageNbtRecordKind.Other);
        var body = key.AsSpan(ModernPrefix.Length);
        var suffixes = new (string Suffix, VillageNbtRecordKind Kind)[]
        {
            ("_DWELLERS", VillageNbtRecordKind.Dwellers),
            ("_PLAYERS", VillageNbtRecordKind.Players),
            ("_INFO", VillageNbtRecordKind.Info),
            ("_POI", VillageNbtRecordKind.Poi)
        };
        foreach (var item in suffixes)
        {
            var suffix = Encoding.UTF8.GetBytes(item.Suffix);
            if (body.Length < suffix.Length || !body[^suffix.Length..].SequenceEqual(suffix)) continue;
            var identifierBytes = body[..^suffix.Length];
            var identifier = MetadataNbtStore.TryUtf8(identifierBytes, out var parsed) ? parsed : "0x" + Convert.ToHexString(identifierBytes).ToLowerInvariant();
            return (identifier.Length == 0 ? keyText : identifier, item.Kind);
        }
        var whole = MetadataNbtStore.TryUtf8(body, out var wholeText) ? wholeText : "0x" + Convert.ToHexString(body).ToLowerInvariant();
        return (whole.Length == 0 ? keyText : whole, VillageNbtRecordKind.Other);
    }

    private sealed record LegacyCandidate(IReadOnlyList<VillageNbtPathComponent> Path, NbtValue Value);

    private static IReadOnlyList<VillageNbtRecord> LegacyVillageRecords(
        byte[] key, string keyText, int documentIndex, int documentCount,
        ConsecutiveNbtRecord decodedRecord, int rawValueSize)
    {
        var candidates = LegacyCandidates(decodedRecord.Document.Root, [], decodedRecord.Document.RootName);
        return candidates.Select((candidate, offset) =>
        {
            var identifier = FindIdentifier(candidate.Value) ?? $"legacy-{documentIndex}-{offset}";
            return new VillageNbtRecord(key.ToArray(), keyText, identifier, VillageNbtRecordKind.Legacy,
                documentIndex, documentCount, candidate.Path,
                new NbtDocument($"Village {offset + 1}", NbtDocumentTools.DeepClone(candidate.Value)),
                decodedRecord.Encoding, rawValueSize, offset);
        }).ToArray();
    }

    private static IReadOnlyList<LegacyCandidate> LegacyCandidates(NbtValue value, IReadOnlyList<VillageNbtPathComponent> path, string nameHint)
    {
        var result = new List<LegacyCandidate>();
        if (value is NbtListValue list)
        {
            var normalized = Normalize(nameHint);
            var looksLikeVillageList = path.Count == 0 || normalized is "villages" or "mvillages" or "villagecollection" or "villagelist";
            if (looksLikeVillageList && list.Values.Count > 0 && list.Values.All(child => child is NbtCompoundValue))
            {
                for (var index = 0; index < list.Values.Count; index++)
                    result.Add(new LegacyCandidate(path.Concat(new VillageNbtPathComponent[] { new VillageNbtListPath(index) }).ToArray(), list.Values[index]));
                return result;
            }
            for (var index = 0; index < list.Values.Count; index++)
                result.AddRange(LegacyCandidates(list.Values[index], path.Concat(new VillageNbtPathComponent[] { new VillageNbtListPath(index) }).ToArray(), nameHint));
        }
        else if (value is NbtCompoundValue compound)
        {
            foreach (var tag in compound.Tags)
                result.AddRange(LegacyCandidates(tag.Value, path.Concat(new VillageNbtPathComponent[] { new VillageNbtCompoundPath(tag.Name) }).ToArray(), tag.Name));
        }
        return result;
    }

    private static string? FindIdentifier(NbtValue root)
    {
        var preferred = new HashSet<string>(["villageuuid", "uuid", "villageid", "uniqueid"], StringComparer.Ordinal);
        foreach (var (name, value) in NamedValues(root))
        {
            if (!preferred.Contains(Normalize(name))) continue;
            var text = ScalarText(value);
            if (!string.IsNullOrWhiteSpace(text)) return text;
        }
        return null;
    }

    private static IEnumerable<(string Name, NbtValue Value)> NamedValues(NbtValue root)
    {
        if (root is not NbtCompoundValue compound) yield break;
        foreach (var tag in compound.Tags)
        {
            yield return (tag.Name, tag.Value);
            foreach (var child in NamedValues(tag.Value)) yield return child;
        }
    }

    private static string? ScalarText(NbtValue value) => value switch
    {
        NbtStringValue text => NbtRawStringCodec.DisplayText(text.Value),
        _ when value.IntegerValue().HasValue => value.IntegerValue()!.Value.ToString(System.Globalization.CultureInfo.InvariantCulture),
        _ => null
    };

    private static NbtValue ReplaceValue(NbtValue current, IReadOnlyList<VillageNbtPathComponent> path, int offset, NbtValue replacement)
    {
        if (offset == path.Count) return NbtDocumentTools.DeepClone(replacement);
        var component = path[offset];
        if (component is VillageNbtCompoundPath compoundPath)
        {
            if (current is not NbtCompoundValue compound) throw new InvalidDataException("村庄 NBT 路径与当前 Compound 结构不一致。");
            var found = false;
            var tags = compound.Tags.Select(tag =>
            {
                if (!string.Equals(tag.Name, compoundPath.Name, StringComparison.Ordinal)) return tag;
                found = true;
                return new NbtNamedTag(tag.Name, ReplaceValue(tag.Value, path, offset + 1, replacement));
            }).ToArray();
            if (!found) throw new InvalidDataException("村庄 NBT 路径中的 Compound 标签已不存在。");
            return new NbtCompoundValue(tags);
        }
        if (component is VillageNbtListPath listPath)
        {
            if (current is not NbtListValue list || (uint)listPath.Index >= (uint)list.Values.Count)
                throw new InvalidDataException("村庄 NBT 路径中的 List 索引已不存在。");
            var values = list.Values.ToArray();
            var replaced = ReplaceValue(values[listPath.Index], path, offset + 1, replacement);
            if (list.ElementType != NbtTagType.End && replaced.Type != list.ElementType)
                throw new InvalidDataException("村庄 NBT 子项类型与原 List 元素类型不一致。");
            values[listPath.Index] = replaced;
            return new NbtListValue(list.ElementType, values);
        }
        throw new InvalidDataException("未知村庄 NBT 路径组件。");
    }

    private static IEnumerable<long> NumericIdentifierValues(NbtValue value)
    {
        if (value.IntegerValue() is long scalar) yield return scalar;
        else if (value is NbtStringValue text && long.TryParse(text.Value.Trim(), System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var parsed)) yield return parsed;
        else if (value is NbtListValue list)
        {
            foreach (var child in list.Values) foreach (var id in NumericIdentifierValues(child)) yield return id;
        }
        else if (value is NbtIntArrayValue ints)
        {
            foreach (var id in ints.Values) yield return id;
        }
        else if (value is NbtLongArrayValue longs)
        {
            foreach (var id in longs.Values) yield return id;
        }
    }

    private static string Normalize(string value)
        => new(value.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());

    private static int SortOrder(VillageNbtRecordKind kind) => kind switch
    {
        VillageNbtRecordKind.Info => 0,
        VillageNbtRecordKind.Poi => 1,
        VillageNbtRecordKind.Dwellers => 2,
        VillageNbtRecordKind.Players => 3,
        VillageNbtRecordKind.Legacy => 4,
        _ => 5
    };
}
