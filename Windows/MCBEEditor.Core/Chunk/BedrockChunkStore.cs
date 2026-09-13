using System.Buffers.Binary;
using System.Text;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockChunkSummary(
    ChunkPosition Position,
    int RecordCount,
    int SubChunkCount,
    bool HasLegacyTerrain,
    sbyte? MinimumSubChunkY,
    sbyte? MaximumSubChunkY,
    bool HasBlockEntities,
    bool HasLegacyEntities,
    bool HasActorDigest,
    ChunkRecordType? BiomeRecordType,
    bool HasHardcodedSpawners,
    IReadOnlyList<byte>? SubChunkVersions = null,
    bool HasUnknownSubChunkVersion = false)
{
    public string SubChunkVersionText
    {
        get
        {
            if (SubChunkCount == 0) return "—";
            var versions = (SubChunkVersions ?? []).Order().Select(v => $"v{v}").ToList();
            if (HasUnknownSubChunkVersion || versions.Count == 0) versions.Add("未知版本");
            return string.Join("/", versions);
        }
    }
    public bool HasTerrain => SubChunkCount > 0 || HasLegacyTerrain;
    public string DimensionText => Position.DimensionName;
    public int X => Position.X;
    public int Z => Position.Z;
    public string GenerationText => HasTerrain ? "已生成" : "仅元数据";

    public string DetailText
    {
        get
        {
            var parts = new List<string> { $"记录 {RecordCount}" };
            if (SubChunkCount > 0)
            {
                parts.Add($"SubChunk {SubChunkVersionText}");
                if (MinimumSubChunkY.HasValue && MaximumSubChunkY.HasValue)
                    parts.Add($"Y{MinimumSubChunkY.Value}-Y{MaximumSubChunkY.Value}");
            }
            if (HasLegacyTerrain) parts.Add("LegacyTerrain 1（8 虚拟切片）");
            if (BiomeRecordType is { } biome) parts.Add($"生物群系 {biome.DisplayName()}");
            if (HasHardcodedSpawners) parts.Add("HardcodedSpawners");
            if (HasBlockEntities) parts.Add("方块实体");
            if (HasLegacyEntities) parts.Add("旧实体");
            if (HasActorDigest) parts.Add("Actor 索引");
            return string.Join(" · ", parts);
        }
    }
}

public sealed record BedrockChunkRecordInfo(
    byte[] Key,
    byte[]? Value,
    BedrockDbKey? Parsed,
    string DisplayName,
    int ValueLength);

public sealed record BedrockChunkClearResult(
    int DeletedChunkRecordCount,
    int DeletedDigestCount,
    int DeletedActorCount,
    int CreatedMetadataRecordCount,
    ChunkRecordType VersionRecordType);

public sealed record BedrockChunkRegenerateResult(
    int DeletedChunkRecordCount,
    int DeletedDigestCount,
    int DeletedActorCount);

public sealed record BedrockChunkCopyResult(
    int CopiedRecordCount,
    int RemovedDestinationRecordCount,
    IReadOnlyList<ChunkRecordType> SkippedRecordTypes);

public sealed record BedrockRegionChunkMutationResult(
    int ProcessedChunkCount,
    int ChangedChunkCount,
    int SkippedChunkCount,
    long DetailCount);

public sealed class BedrockChunkStore
{
    private readonly IWorldDatabase _database;
    private IReadOnlyList<EnvironmentTickingAreaSpec>? _tickingAreas;

    public BedrockChunkStore(IWorldDatabase database)
    {
        _database = database ?? throw new ArgumentNullException(nameof(database));
    }

    public IReadOnlyList<BedrockChunkSummary> ListChunks()
    {
        var chunks = new Dictionary<ChunkPosition, Accumulator>();
        foreach (var entry in _database.Entries(includeValues: false))
        {
            if (BedrockDbKey.TryParse(entry.Key, out var key))
            {
                if (!chunks.TryGetValue(key.Position, out var value)) value = new Accumulator();
                value.Records++;
                if (key.RecordType == ChunkRecordType.SubChunk && key.SubChunkIndex is sbyte y)
                {
                    value.SubChunkYs.Add(y);
                    var bytes = _database.Get(entry.Key);
                    if (bytes is { Length: > 0 }) value.SubChunkVersions.Add(bytes[0]);
                    else value.HasUnknownSubChunkVersion = true;
                }
                if (key.RecordType == ChunkRecordType.LegacyTerrain) value.HasLegacyTerrain = true;
                if (key.RecordType == ChunkRecordType.BlockEntity) value.HasBlockEntities = true;
                if (key.RecordType == ChunkRecordType.Entity) value.HasLegacyEntities = true;
                if (key.RecordType is ChunkRecordType.Data3D or ChunkRecordType.Data2D or ChunkRecordType.Data2DLegacy)
                {
                    if (value.BiomeRecordType is null || key.RecordType == ChunkRecordType.Data3D)
                        value.BiomeRecordType = key.RecordType;
                }
                if (key.RecordType == ChunkRecordType.HardcodedSpawners) value.HasHardcodedSpawners = true;
                chunks[key.Position] = value;
            }
            else if (TryParseActorDigestKey(entry.Key, out var actorPosition))
            {
                if (!chunks.TryGetValue(actorPosition, out var value)) value = new Accumulator();
                value.Records++;
                value.HasActorDigest = true;
                chunks[actorPosition] = value;
            }
        }

        return chunks
            .Select(pair => ToSummary(pair.Key, pair.Value))
            .OrderBy(item => item.Position.Dimension)
            .ThenBy(item => item.Position.Z)
            .ThenBy(item => item.Position.X)
            .ToArray();
    }

    public BedrockChunkSummary SummaryAt(ChunkPosition position)
    {
        var acc = new Accumulator();
        var prefix = CoordinatePrefix(position.X, position.Z);
        foreach (var entry in _database.Entries(prefix, includeValues: false))
        {
            if (!BedrockDbKey.TryParse(entry.Key, out var key) || key.Position != position) continue;
            acc.Records++;
            if (key.RecordType == ChunkRecordType.SubChunk && key.SubChunkIndex is sbyte y)
            {
                acc.SubChunkYs.Add(y);
                var bytes = _database.Get(entry.Key);
                if (bytes is { Length: > 0 }) acc.SubChunkVersions.Add(bytes[0]);
                else acc.HasUnknownSubChunkVersion = true;
            }
            if (key.RecordType == ChunkRecordType.LegacyTerrain) acc.HasLegacyTerrain = true;
            if (key.RecordType == ChunkRecordType.BlockEntity) acc.HasBlockEntities = true;
            if (key.RecordType == ChunkRecordType.Entity) acc.HasLegacyEntities = true;
            if (key.RecordType is ChunkRecordType.Data3D or ChunkRecordType.Data2D or ChunkRecordType.Data2DLegacy)
            {
                if (acc.BiomeRecordType is null || key.RecordType == ChunkRecordType.Data3D) acc.BiomeRecordType = key.RecordType;
            }
            if (key.RecordType == ChunkRecordType.HardcodedSpawners) acc.HasHardcodedSpawners = true;
        }
        foreach (var digestKey in ActorDigestKeys(position))
        {
            if (_database.Get(digestKey) is null) continue;
            acc.Records++;
            acc.HasActorDigest = true;
        }
        return ToSummary(position, acc);
    }

    public IReadOnlyList<BedrockChunkRecordInfo> RecordsAt(ChunkPosition position, bool includeValues = false)
    {
        var result = new List<BedrockChunkRecordInfo>();
        var seen = new HashSet<byte[]>(ByteArrayComparer.Instance);
        foreach (var prefix in BedrockRawChunkKey.Prefixes(position))
        {
            foreach (var entry in _database.Entries(prefix, includeValues))
            {
                if (!BedrockRawChunkKey.Matches(entry.Key, position) || !seen.Add(entry.Key)) continue;
                BedrockDbKey? parsed = BedrockDbKey.TryParse(entry.Key, out var key) ? key : null;
                var name = parsed?.ToString() ?? $"Raw {Convert.ToHexString(entry.Key)}";
                result.Add(new BedrockChunkRecordInfo(entry.Key, entry.Value, parsed, name, entry.Value?.Length ?? -1));
            }
        }
        foreach (var digestKey in ActorDigestKeys(position))
        {
            var value = includeValues ? _database.Get(digestKey) : null;
            if (includeValues && value is null) continue;
            if (!includeValues && _database.Get(digestKey) is null) continue;
            result.Add(new BedrockChunkRecordInfo(
                digestKey, value, null, $"{position.DimensionName} ({position.X}, {position.Z}) ActorDigest", value?.Length ?? -1));
        }
        return result.OrderBy(item => item.Key, ByteArrayComparer.Instance).ToArray();
    }

    public IReadOnlyList<BedrockSubChunk> DecodeSubChunks(ChunkPosition position)
    {
        var output = new List<BedrockSubChunk>();
        var prefix = CoordinatePrefix(position.X, position.Z);
        foreach (var entry in _database.Entries(prefix, includeValues: true))
        {
            if (!BedrockDbKey.TryParse(entry.Key, out var key) || key.Position != position || entry.Value is null) continue;
            if (key.RecordType == ChunkRecordType.SubChunk && key.SubChunkIndex is sbyte keyY)
                output.Add(BedrockSubChunk.Decode(entry.Value, keyY));
            else if (key.RecordType == ChunkRecordType.LegacyTerrain)
            {
                var terrain = BedrockLegacyTerrain.Decode(entry.Value);
                for (sbyte y = 0; y < 8; y++) output.Add(terrain.SubChunk(y));
            }
        }
        return output.OrderBy(item => item.YIndex ?? sbyte.MinValue).ToArray();
    }

    public BedrockChunkCopyResult CopyChunk(ChunkPosition source, ChunkPosition destination)
    {
        if (source == destination)
            throw new InvalidDataException("源区块与目标区块不能相同");

        var sourceRecords = StandardRecordsAt(source, includeValues: true);
        var copyable = sourceRecords.Where(item => CopyableRecordTypes.Contains(item.Parsed.RecordType)).ToArray();
        if (copyable.Length == 0)
            throw new NotSupportedException("源区块没有可复制的现代区块记录");

        var destinationRecords = StandardRecordsAt(destination, includeValues: true)
            .Where(item => CopyableRecordTypes.Contains(item.Parsed.RecordType))
            .ToArray();
        var deltaX = ((long)destination.X - source.X) * 16L;
        var deltaZ = ((long)destination.Z - source.Z) * 16L;
        var puts = new List<WorldDatabasePut>(copyable.Length);
        foreach (var record in copyable)
        {
            if (record.Value is null) continue;
            var value = record.Parsed.RecordType == ChunkRecordType.BlockEntity
                ? BedrockBlockEntityCoordinateTools.OffsetPayload(record.Value, deltaX, deltaZ)
                : record.Value;
            var targetKey = new BedrockDbKey(destination, record.Parsed.RecordType, record.Parsed.SubChunkIndex).Encode();
            puts.Add(new WorldDatabasePut(targetKey, value));
        }

        _database.ApplyBatch(puts, destinationRecords.Select(item => item.Key), sync: true);
        var skipped = sourceRecords.Select(item => item.Parsed.RecordType)
            .Where(type => !CopyableRecordTypes.Contains(type))
            .Distinct()
            .OrderBy(type => (byte)type)
            .ToArray();
        return new BedrockChunkCopyResult(puts.Count, destinationRecords.Length, skipped);
    }

    private IReadOnlyList<StandardChunkRecord> StandardRecordsAt(ChunkPosition position, bool includeValues)
    {
        var result = new List<StandardChunkRecord>();
        foreach (var entry in _database.Entries(CoordinatePrefix(position.X, position.Z), includeValues))
        {
            if (!BedrockDbKey.TryParse(entry.Key, out var parsed) || parsed.Position != position) continue;
            result.Add(new StandardChunkRecord(entry.Key, entry.Value, parsed));
        }
        return result;
    }

    private static readonly HashSet<ChunkRecordType> CopyableRecordTypes =
    [
        ChunkRecordType.Data3D, ChunkRecordType.Version, ChunkRecordType.Data2D, ChunkRecordType.Data2DLegacy,
        ChunkRecordType.SubChunk, ChunkRecordType.LegacyTerrain, ChunkRecordType.BlockEntity,
        ChunkRecordType.LegacyBlockExtraData, ChunkRecordType.BiomeState, ChunkRecordType.FinalizedState,
        ChunkRecordType.BorderBlocks, ChunkRecordType.Checksums
    ];

    private sealed record StandardChunkRecord(byte[] Key, byte[]? Value, BedrockDbKey Parsed);

    /// <summary>
    /// Replaces the complete raw chunk coordinate with a minimal generated-air
    /// skeleton. Unknown chunk tags are removed by raw prefix rather than by a
    /// whitelist, and modern actor digests/actorprefix records are cleaned too.
    /// </summary>
    public BedrockChunkClearResult ClearChunk(ChunkPosition position)
    {
        var chunkRecords = RawChunkRecordsAt(position, includeValues: true);
        var actorRecords = ActorRecordsForRemoval(position);
        if (chunkRecords.Count == 0 && actorRecords.DigestKeys.Count == 0)
            throw new InvalidOperationException("该区块没有可清空的记录");

        var parsedTypes = chunkRecords
            .Select(item => BedrockDbKey.TryParse(item.Key, out var parsed) ? parsed.RecordType : (ChunkRecordType?)null)
            .Where(item => item.HasValue)
            .Select(item => item!.Value)
            .ToHashSet();
        var preferLegacy = parsedTypes.Contains(ChunkRecordType.LegacyVersion)
            && !parsedTypes.Contains(ChunkRecordType.Version);
        var profile = BedrockEmptyChunkMetadata.DetectProfile(_database, position.Dimension, preferLegacy);
        var metadata = BedrockEmptyChunkMetadata.Records(position, profile);

        var deleteKeys = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var item in chunkRecords) deleteKeys[Convert.ToHexString(item.Key)] = item.Key;
        foreach (var key in actorRecords.DigestKeys) deleteKeys[Convert.ToHexString(key)] = key;
        foreach (var key in actorRecords.ActorKeys) deleteKeys[Convert.ToHexString(key)] = key;

        _database.ApplyBatch(
            metadata.Select(item => new WorldDatabasePut(item.Key, item.Value)),
            deleteKeys.Values,
            sync: true);

        return new BedrockChunkClearResult(
            chunkRecords.Count,
            actorRecords.DigestKeys.Count,
            actorRecords.ActorKeys.Count,
            metadata.Count,
            metadata[0].RecordType);
    }

    /// <summary>
    /// Removes every raw chunk record plus digp/actorprefix references so Bedrock
    /// treats the coordinate as never generated and rebuilds it from the world seed.
    /// </summary>
    public BedrockChunkRegenerateResult RegenerateChunk(ChunkPosition position)
    {
        var chunkRecords = RawChunkRecordsAt(position, includeValues: true);
        var actorRecords = ActorRecordsForRemoval(position);
        var deleteKeys = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var item in chunkRecords) deleteKeys[Convert.ToHexString(item.Key)] = item.Key;
        foreach (var key in actorRecords.DigestKeys) deleteKeys[Convert.ToHexString(key)] = key;
        foreach (var key in actorRecords.ActorKeys) deleteKeys[Convert.ToHexString(key)] = key;
        if (deleteKeys.Count == 0)
            throw new InvalidOperationException("该区块已经处于未生成状态");

        _database.ApplyBatch([], deleteKeys.Values, sync: true);
        return new BedrockChunkRegenerateResult(
            chunkRecords.Count,
            actorRecords.DigestKeys.Count,
            actorRecords.ActorKeys.Count);
    }

    public BedrockRegionChunkMutationResult ClearRegion(int dimension, int minimumX, int minimumZ, int maximumX, int maximumZ)
        => MutateRegion(dimension, minimumX, minimumZ, maximumX, maximumZ, regenerate: false);

    public BedrockRegionChunkMutationResult RegenerateRegion(int dimension, int minimumX, int minimumZ, int maximumX, int maximumZ)
        => MutateRegion(dimension, minimumX, minimumZ, maximumX, maximumZ, regenerate: true);

    private BedrockRegionChunkMutationResult MutateRegion(
        int dimension, int minimumX, int minimumZ, int maximumX, int maximumZ, bool regenerate)
    {
        if (minimumX > maximumX) (minimumX, maximumX) = (maximumX, minimumX);
        if (minimumZ > maximumZ) (minimumZ, maximumZ) = (maximumZ, minimumZ);

        var minimumChunkX = BedrockSurfaceRegionRenderer.FloorDiv(minimumX, 16);
        var maximumChunkX = BedrockSurfaceRegionRenderer.FloorDiv(maximumX, 16);
        var minimumChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(minimumZ, 16);
        var maximumChunkZ = BedrockSurfaceRegionRenderer.FloorDiv(maximumZ, 16);
        var processed = checked((int)((long)(maximumChunkX - minimumChunkX + 1) * (maximumChunkZ - minimumChunkZ + 1)));
        var changed = 0;
        var skipped = 0;
        long detail = 0;

        for (var chunkZ = minimumChunkZ; chunkZ <= maximumChunkZ; chunkZ++)
        for (var chunkX = minimumChunkX; chunkX <= maximumChunkX; chunkX++)
        {
            var position = new ChunkPosition(chunkX, chunkZ, dimension);
            try
            {
                if (regenerate)
                {
                    var result = RegenerateChunk(position);
                    detail += result.DeletedChunkRecordCount + result.DeletedDigestCount + result.DeletedActorCount;
                }
                else
                {
                    var result = ClearChunk(position);
                    detail += result.DeletedChunkRecordCount + result.DeletedDigestCount + result.DeletedActorCount;
                }
                changed++;
            }
            catch (InvalidOperationException)
            {
                skipped++;
            }
            catch (NotSupportedException)
            {
                skipped++;
            }
        }

        if (changed == 0)
            throw new NotSupportedException(regenerate
                ? "扩展后的区域内没有可重新生成的区块"
                : "扩展后的区域内没有可清空的区块");

        return new BedrockRegionChunkMutationResult(processed, changed, skipped, detail);
    }

    public string GenerationDescription(BedrockChunkSummary summary)
    {
        var finalizedKey = new BedrockDbKey(summary.Position, ChunkRecordType.FinalizedState, null).Encode();
        var raw = _database.Get(finalizedKey);
        if (raw is not null)
        {
            if (raw.Length < 4) return "已加载（FinalizedState 数据异常）";
            var state = BinaryPrimitives.ReadInt32LittleEndian(raw.AsSpan(0, 4));
            return state == 2 ? "已生成（FinalizedState=2）" : $"已加载（FinalizedState={state}）";
        }
        if (summary.RecordCount == 0) return "未生成";
        if (summary.HasTerrain || summary.BiomeRecordType is not null) return "已加载（无 FinalizedState）";
        return "已加载元数据（无 FinalizedState）";
    }

    public string QueryText(BedrockChunkSummary summary)
    {
        var detail = summary.RecordCount == 0 ? "无区块记录" : summary.DetailText;
        var slime = BedrockSlimeChunk.IsSlimeChunk(summary.Position.X, summary.Position.Z);
        var ticking = IsTickingChunk(summary.Position);
        return $"{ChunkCommandParser.DimensionName(summary.Position.Dimension)} {summary.Position.CoordinateText} · {detail} · 生成情况：{GenerationDescription(summary)} · IsSlimeChunk={slime} · Ticking={ticking}";
    }

    private bool IsTickingChunk(ChunkPosition position)
    {
        _tickingAreas ??= BedrockTickingAreaMap.Read(_database).Areas;
        return _tickingAreas.Any(area => area.Dimension == position.Dimension
            && BedrockTickingAreaMap.ContainsChunk(area, position.X, position.Z));
    }

    private IReadOnlyList<BedrockChunkRecordInfo> RawChunkRecordsAt(ChunkPosition position, bool includeValues)
    {
        var found = new Dictionary<string, BedrockChunkRecordInfo>(StringComparer.Ordinal);
        foreach (var prefix in BedrockRawChunkKey.Prefixes(position))
        {
            foreach (var entry in _database.Entries(prefix, includeValues))
            {
                if (!BedrockRawChunkKey.Matches(entry.Key, position)) continue;
                BedrockDbKey? parsed = BedrockDbKey.TryParse(entry.Key, out var key) ? key : null;
                found[Convert.ToHexString(entry.Key)] = new BedrockChunkRecordInfo(
                    entry.Key, entry.Value, parsed, parsed?.ToString() ?? $"Raw {Convert.ToHexString(entry.Key)}", entry.Value?.Length ?? -1);
            }
        }
        return found.Values.ToArray();
    }

    private ActorRemovalRecords ActorRecordsForRemoval(ChunkPosition position)
    {
        var digestKeys = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        var actorKeys = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var digestKey in ActorDigestKeys(position))
        {
            var digest = _database.Get(digestKey);
            if (digest is null) continue;
            digestKeys[Convert.ToHexString(digestKey)] = digestKey;
            if (digest.Length % 8 != 0) continue;

            for (var offset = 0; offset < digest.Length; offset += 8)
            {
                var actorKey = ActorKey(digest.AsSpan(offset, 8));
                actorKeys[Convert.ToHexString(actorKey)] = actorKey;
            }
        }
        return new ActorRemovalRecords(digestKeys.Values.ToArray(), actorKeys.Values.ToArray());
    }

    private static byte[] ActorKey(ReadOnlySpan<byte> rawId)
    {
        if (rawId.Length != 8) throw new ArgumentException("Actor raw ID 必须为 8 字节", nameof(rawId));
        var prefix = Encoding.ASCII.GetBytes("actorprefix");
        var key = new byte[prefix.Length + 8];
        prefix.CopyTo(key, 0);
        rawId.CopyTo(key.AsSpan(prefix.Length));
        return key;
    }

    private sealed record ActorRemovalRecords(IReadOnlyList<byte[]> DigestKeys, IReadOnlyList<byte[]> ActorKeys);

    public static byte[] CoordinatePrefix(int x, int z)
    {
        var prefix = new byte[8];
        BinaryPrimitives.WriteInt32LittleEndian(prefix.AsSpan(0, 4), x);
        BinaryPrimitives.WriteInt32LittleEndian(prefix.AsSpan(4, 4), z);
        return prefix;
    }

    public static IReadOnlyList<byte[]> ActorDigestKeys(ChunkPosition position)
    {
        var text = Encoding.ASCII.GetBytes("digp");
        var modern = new byte[16];
        text.CopyTo(modern, 0);
        BinaryPrimitives.WriteInt32LittleEndian(modern.AsSpan(4, 4), position.X);
        BinaryPrimitives.WriteInt32LittleEndian(modern.AsSpan(8, 4), position.Z);
        BinaryPrimitives.WriteInt32LittleEndian(modern.AsSpan(12, 4), position.Dimension);
        if (position.Dimension != 0) return [modern];

        var legacy = new byte[12];
        text.CopyTo(legacy, 0);
        BinaryPrimitives.WriteInt32LittleEndian(legacy.AsSpan(4, 4), position.X);
        BinaryPrimitives.WriteInt32LittleEndian(legacy.AsSpan(8, 4), position.Z);
        return [modern, legacy];
    }

    public static bool TryParseActorDigestKey(ReadOnlySpan<byte> data, out ChunkPosition position)
    {
        position = default;
        if (data.Length is not (12 or 16) || !data[..4].SequenceEqual("digp"u8)) return false;
        var x = BinaryPrimitives.ReadInt32LittleEndian(data.Slice(4, 4));
        var z = BinaryPrimitives.ReadInt32LittleEndian(data.Slice(8, 4));
        var dimension = data.Length == 16 ? BinaryPrimitives.ReadInt32LittleEndian(data.Slice(12, 4)) : 0;
        position = new ChunkPosition(x, z, dimension);
        return true;
    }

    private static BedrockChunkSummary ToSummary(ChunkPosition position, Accumulator value)
        => new(
            position,
            value.Records,
            value.SubChunkYs.Count,
            value.HasLegacyTerrain,
            value.SubChunkYs.Count == 0 ? null : value.SubChunkYs.Min(),
            value.SubChunkYs.Count == 0 ? null : value.SubChunkYs.Max(),
            value.HasBlockEntities,
            value.HasLegacyEntities,
            value.HasActorDigest,
            value.BiomeRecordType,
            value.HasHardcodedSpawners,
            value.SubChunkVersions.Order().ToArray(),
            value.HasUnknownSubChunkVersion);

    private sealed class Accumulator
    {
        public int Records;
        public HashSet<sbyte> SubChunkYs { get; } = [];
        public HashSet<byte> SubChunkVersions { get; } = [];
        public bool HasUnknownSubChunkVersion;
        public bool HasLegacyTerrain;
        public bool HasBlockEntities;
        public bool HasLegacyEntities;
        public bool HasActorDigest;
        public ChunkRecordType? BiomeRecordType;
        public bool HasHardcodedSpawners;
    }

    private sealed class ByteArrayComparer : IComparer<byte[]>, IEqualityComparer<byte[]>
    {
        public static ByteArrayComparer Instance { get; } = new();
        public int Compare(byte[]? x, byte[]? y)
        {
            if (ReferenceEquals(x, y)) return 0;
            if (x is null) return -1;
            if (y is null) return 1;
            var common = Math.Min(x.Length, y.Length);
            for (var i = 0; i < common; i++)
            {
                var compare = x[i].CompareTo(y[i]);
                if (compare != 0) return compare;
            }
            return x.Length.CompareTo(y.Length);
        }
        public bool Equals(byte[]? x, byte[]? y) => x is not null && y is not null && x.AsSpan().SequenceEqual(y);
        public int GetHashCode(byte[] obj)
        {
            var hash = new HashCode();
            foreach (var value in obj) hash.Add(value);
            return hash.ToHashCode();
        }
    }
}
