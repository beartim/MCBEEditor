using System.Buffers.Binary;
using System.Globalization;
using MCBEEditor.Core.Entity;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public enum HardcodedSpawnerKind : byte
{
    NetherFortress = 1,
    SwampHut = 2,
    OceanMonument = 3,
    PillagerOutpost = 5
}

public static class HardcodedSpawnerKindNames
{
    public static string DisplayName(byte value) => value switch
    {
        1 => "下界要塞",
        2 => "沼泽小屋",
        3 => "海底神殿",
        5 => "掠夺者前哨站",
        _ => $"未知类型 {value}"
    };
}

public sealed record HardcodedSpawnerArea(
    int MinimumX, int MinimumY, int MinimumZ,
    int MaximumX, int MaximumY, int MaximumZ,
    byte Kind)
{
    public string KindText => HardcodedSpawnerKindNames.DisplayName(Kind);
    public string RangeText => $"({MinimumX}, {MinimumY}, {MinimumZ}) → ({MaximumX}, {MaximumY}, {MaximumZ})";
    public HardcodedSpawnerArea Validate()
    {
        if (MinimumX > MaximumX || MinimumY > MaximumY || MinimumZ > MaximumZ)
            throw new InvalidDataException("HardcodedSpawners 最小坐标必须小于或等于最大坐标。");
        return this;
    }
}

public sealed record HardcodedSpawnersDocument(IReadOnlyList<HardcodedSpawnerArea> Areas)
{
    public static HardcodedSpawnersDocument Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < 4) throw new InvalidDataException("HardcodedSpawners 数据少于 4 字节。");
        var count = BinaryPrimitives.ReadInt32LittleEndian(data[..4]);
        if (count < 0 || count > 1_000_000) throw new InvalidDataException($"HardcodedSpawners 数量无效：{count}");
        var expected = checked(4 + count * 25);
        if (data.Length != expected) throw new InvalidDataException($"HardcodedSpawners 长度不匹配：声明 {count} 项，实际 {data.Length - 4} 字节。");
        var output = new HardcodedSpawnerArea[count];
        var offset = 4;
        for (var i = 0; i < count; i++)
        {
            var area = new HardcodedSpawnerArea(
                BinaryPrimitives.ReadInt32LittleEndian(data.Slice(offset, 4)),
                BinaryPrimitives.ReadInt32LittleEndian(data.Slice(offset + 4, 4)),
                BinaryPrimitives.ReadInt32LittleEndian(data.Slice(offset + 8, 4)),
                BinaryPrimitives.ReadInt32LittleEndian(data.Slice(offset + 12, 4)),
                BinaryPrimitives.ReadInt32LittleEndian(data.Slice(offset + 16, 4)),
                BinaryPrimitives.ReadInt32LittleEndian(data.Slice(offset + 20, 4)),
                data[offset + 24]).Validate();
            output[i] = area;
            offset += 25;
        }
        return new HardcodedSpawnersDocument(output);
    }

    public byte[] Encode()
    {
        if (Areas.Count > int.MaxValue) throw new InvalidDataException("HardcodedSpawners 项目过多。");
        var output = new byte[checked(4 + Areas.Count * 25)];
        BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(0, 4), Areas.Count);
        var offset = 4;
        foreach (var original in Areas)
        {
            var area = original.Validate();
            BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(offset, 4), area.MinimumX);
            BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(offset + 4, 4), area.MinimumY);
            BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(offset + 8, 4), area.MinimumZ);
            BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(offset + 12, 4), area.MaximumX);
            BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(offset + 16, 4), area.MaximumY);
            BinaryPrimitives.WriteInt32LittleEndian(output.AsSpan(offset + 20, 4), area.MaximumZ);
            output[offset + 24] = area.Kind;
            offset += 25;
        }
        return output;
    }
}

public sealed record HardcodedSpawnersRecord(ChunkPosition Position, byte[] Key, HardcodedSpawnersDocument Document);

public sealed class HardcodedSpawnersStore
{
    private readonly IWorldDatabase _database;
    public HardcodedSpawnersStore(IWorldDatabase database) => _database = database;

    public HardcodedSpawnersRecord Read(ChunkPosition position)
    {
        var key = new BedrockDbKey(position, ChunkRecordType.HardcodedSpawners, null).Encode();
        var raw = _database.Get(key);
        return new HardcodedSpawnersRecord(position, key, raw is null ? new HardcodedSpawnersDocument([]) : HardcodedSpawnersDocument.Decode(raw));
    }

    public void Save(HardcodedSpawnersRecord record)
    {
        if (record.Document.Areas.Count == 0) _database.Delete(record.Key, sync: true);
        else _database.Put(record.Key, record.Document.Encode(), sync: true);
    }

    public IReadOnlyList<HardcodedSpawnersRecord> RecordsInChunkRectangle(int dimension, int minChunkX, int minChunkZ, int maxChunkX, int maxChunkZ, bool includeEmpty = false)
    {
        var minX = Math.Min(minChunkX, maxChunkX);
        var maxX = Math.Max(minChunkX, maxChunkX);
        var minZ = Math.Min(minChunkZ, maxChunkZ);
        var maxZ = Math.Max(minChunkZ, maxChunkZ);
        var area = ((long)maxX - minX + 1) * ((long)maxZ - minZ + 1);
        if (area <= 4096 || includeEmpty)
        {
            var direct = new List<HardcodedSpawnersRecord>();
            for (var z = minZ; z <= maxZ; z++)
            for (var x = minX; x <= maxX; x++)
            {
                var position = new ChunkPosition(x, z, dimension);
                var record = Read(position);
                if (includeEmpty || record.Document.Areas.Count > 0) direct.Add(record);
            }
            return direct;
        }

        // Very large dynamic map windows must not issue one Get per logical
        // chunk. Scan the existing LevelDB keys once and decode only 0x39
        // records that actually intersect the requested rectangle.
        var result = new List<HardcodedSpawnersRecord>();
        foreach (var entry in _database.Entries(includeValues: true))
        {
            if (entry.Value is null || !BedrockDbKey.TryParse(entry.Key, out var key)
                || key.RecordType != ChunkRecordType.HardcodedSpawners) continue;
            var position = key.Position;
            if (position.Dimension != dimension || position.X < minX || position.X > maxX || position.Z < minZ || position.Z > maxZ) continue;
            try
            {
                var document = HardcodedSpawnersDocument.Decode(entry.Value);
                if (document.Areas.Count > 0) result.Add(new HardcodedSpawnersRecord(position, entry.Key, document));
            }
            catch
            {
                // Overlay scans are best-effort; the editor for a selected
                // record will surface the exact decode error if opened.
            }
        }
        return result;
    }
}

public sealed record SpawnMapFeature(string Label, int Dimension, long X, long? Y, long Z, bool IsWorldSpawn, bool? Forced, string Source);

public static class SpawnMapFeatureStore
{
    public static IReadOnlyList<SpawnMapFeature> Read(WorldDocument document, IWorldDatabase database)
    {
        var result = new List<SpawnMapFeature>();
        var level = document.ReadLevelDat();
        var root = level.Document.Root;
        var x = root.IntValue("SpawnX");
        var y = root.IntValue("SpawnY");
        var z = root.IntValue("SpawnZ");
        if (x.HasValue && z.HasValue)
            result.Add(new SpawnMapFeature("世界出生点", 0, x.Value, y, z.Value, true, null, "level.dat"));

        var players = new PlayerNbtStore(database);
        foreach (var player in players.Records())
        {
            if (!TrySpawn(player.Document.Root, out var sx, out var sy, out var sz, out var dimension, out var forced)) continue;
            result.Add(new SpawnMapFeature(player.DisplayName + " 出生点", dimension, sx, sy, sz, false, forced, player.KeyText));
        }
        return result;
    }

    private static bool TrySpawn(NbtValue root, out long x, out long? y, out long z, out int dimension, out bool? forced)
    {
        if (TryDirect(root, false, out x, out y, out z, out dimension, out forced)) return true;
        if (root is NbtCompoundValue compound)
        {
            foreach (var tag in compound.Tags)
            {
                var normalized = Normalize(tag.Name);
                if (normalized is not ("respawn" or "spawn" or "spawnpoint" or "playerspawn" or "bedspawn" or "respawnpoint")) continue;
                if (TryDirect(tag.Value, true, out x, out y, out z, out dimension, out forced)) return true;
            }
        }
        x = z = 0; y = null; dimension = 0; forced = null; return false;
    }

    private static bool TryDirect(NbtValue value, bool generic, out long x, out long? y, out long z, out int dimension, out bool? forced)
    {
        x = z = 0; y = null; dimension = 0; forced = null;
        if (value is not NbtCompoundValue compound) return false;
        var sx = Integer(compound, generic ? ["SpawnX", "spawn_x", "X", "x"] : ["SpawnX", "spawn_x"]);
        var sy = Integer(compound, generic ? ["SpawnY", "spawn_y", "Y", "y"] : ["SpawnY", "spawn_y"]);
        var sz = Integer(compound, generic ? ["SpawnZ", "spawn_z", "Z", "z"] : ["SpawnZ", "spawn_z"]);
        if ((!sx.HasValue || !sz.HasValue) && compound.CompoundValueIgnoreCase("Pos", "pos", "Position", "position") is { } pos && TryCoordinate(pos, out var px, out var py, out var pz))
        { sx = px; sy = py; sz = pz; }
        if (!sx.HasValue || !sz.HasValue) return false;
        x = sx.Value; y = sy; z = sz.Value;
        var dimValue = compound.CompoundValueIgnoreCase("SpawnDimension", "spawn_dimension", "Dimension", "dimension", "DimensionId", "dimension_id", "DimensionID");
        dimension = PlayerNbtStore.ParseDimension(dimValue) ?? 0;
        var forcedValue = compound.CompoundValueIgnoreCase("SpawnForced", "spawn_forced", "Forced", "forced")?.IntegerValue();
        forced = forcedValue.HasValue ? forcedValue.Value != 0 : null;
        return true;
    }

    private static long? Integer(NbtCompoundValue compound, IReadOnlyList<string> names)
    {
        foreach (var name in names) if (compound.CompoundValue(name)?.IntegerValue() is long v) return v;
        return null;
    }

    private static bool TryCoordinate(NbtValue value, out long x, out long? y, out long z)
    {
        x = z = 0; y = null;
        switch (value)
        {
            case NbtListValue list when list.Values.Count >= 3:
                var lx = list.Values[0].IntegerValue(); var ly = list.Values[1].IntegerValue(); var lz = list.Values[2].IntegerValue();
                if (!lx.HasValue || !lz.HasValue) return false; x = lx.Value; y = ly; z = lz.Value; return true;
            case NbtIntArrayValue ints when ints.Values.Count >= 3:
                x = ints.Values[0]; y = ints.Values[1]; z = ints.Values[2]; return true;
            case NbtLongArrayValue longs when longs.Values.Count >= 3:
                x = longs.Values[0]; y = longs.Values[1]; z = longs.Values[2]; return true;
            case NbtCompoundValue compound:
                var cx = Integer(compound, ["X", "x"]); var cy = Integer(compound, ["Y", "y"]); var cz = Integer(compound, ["Z", "z"]);
                if (!cx.HasValue || !cz.HasValue) return false; x = cx.Value; y = cy; z = cz.Value; return true;
            default: return false;
        }
    }

    private static string Normalize(string value) => new(value.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());
}

public sealed record VillageMapPointFeature(
    long X,
    long Y,
    long Z,
    string Label,
    IReadOnlyList<long> LinkedEntityIds)
{
    public VillageMapPointFeature(long x, long y, long z, string label)
        : this(x, y, z, label, Array.Empty<long>()) { }

    public string CoordinateKey => $"{X}:{Y}:{Z}";
    public string HorizontalCoordinateKey => $"{X}:{Z}";

    public VillageMapPointFeature MergeLinkedEntityIds(IEnumerable<long> ids)
        => this with { LinkedEntityIds = LinkedEntityIds.Concat(ids).Distinct().OrderBy(value => value).ToArray() };
}

public sealed record VillageMapBoundsFeature(long MinimumX, long MinimumZ, long MaximumX, long MaximumZ)
{
    public bool Contains(long x, long z) => x >= MinimumX && x <= MaximumX && z >= MinimumZ && z <= MaximumZ;
}

public sealed record VillageMapFeature(
    string Identifier,
    int Dimension,
    VillageMapPointFeature? Center,
    VillageMapBoundsFeature? Bounds,
    IReadOnlyList<VillageMapPointFeature> PointsOfInterest,
    IReadOnlyList<VillageNbtRecord> Records,
    IReadOnlyList<BedrockWorldObject> ResidentEntities)
{
    public string DisplayName => Records.FirstOrDefault()?.VillageDisplayName ?? $"村庄 {Identifier}";
}

public sealed class VillageMapFeatureStore
{
    private readonly IWorldDatabase _database;
    public VillageMapFeatureStore(IWorldDatabase database) => _database = database;

    private sealed record FeatureSeed(
        string Identifier,
        int Dimension,
        VillageMapPointFeature? Center,
        VillageMapBoundsFeature? Bounds,
        IReadOnlyList<VillageMapPointFeature> Poi,
        IReadOnlyList<VillageNbtRecord> Records,
        IReadOnlyList<long> ResidentIds);

    public IReadOnlyList<VillageMapFeature> Features()
    {
        var store = new VillageNbtStore(_database);
        var scan = store.ScanRecords();
        var seeds = new List<FeatureSeed>();
        var allResidentIds = new HashSet<long>();
        foreach (var group in scan.Records.GroupBy(record => record.VillageIdentifier, StringComparer.OrdinalIgnoreCase))
        {
            var records = group.ToArray();
            var dimension = records.Select(record => FindDimension(record.Document.Root)).FirstOrDefault(value => value.HasValue) ?? 0;
            VillageMapPointFeature? center = null;
            VillageMapBoundsFeature? bounds = null;
            var poi = new List<VillageMapPointFeature>();
            foreach (var record in records)
            {
                center ??= FindCenter(record.Document.Root);
                bounds ??= FindBounds(record.Document.Root);
                if (record.Kind is VillageNbtRecordKind.Poi or VillageNbtRecordKind.Legacy)
                    CollectPoi(record.Document.Root, poi, Array.Empty<long>());
            }
            poi = poi.GroupBy(point => point.CoordinateKey)
                .Select(grouping => grouping.Aggregate((left, right) => left.MergeLinkedEntityIds(right.LinkedEntityIds)))
                .ToList();
            if (center is null && bounds is not null)
                center = new VillageMapPointFeature((bounds.MinimumX + bounds.MaximumX) / 2, 0, (bounds.MinimumZ + bounds.MaximumZ) / 2, "村庄中心");
            if (bounds is null && center is not null)
                bounds = new VillageMapBoundsFeature(center.X - 1, center.Z - 1, center.X + 1, center.Z + 1);
            if (bounds is null && poi.Count > 0)
                bounds = new VillageMapBoundsFeature(poi.Min(p => p.X) - 1, poi.Min(p => p.Z) - 1, poi.Max(p => p.X) + 1, poi.Max(p => p.Z) + 1);
            if (center is null && poi.Count > 0)
                center = new VillageMapPointFeature((long)Math.Round(poi.Average(p => (double)p.X)), (long)Math.Round(poi.Average(p => (double)p.Y)), (long)Math.Round(poi.Average(p => (double)p.Z)), "推断中心");
            if (center is null && bounds is null && poi.Count == 0) continue;

            var residentIds = records
                .Where(record => record.Kind is VillageNbtRecordKind.Dwellers or VillageNbtRecordKind.Legacy)
                .SelectMany(record => VillageNbtStore.DwellerUniqueIds(record.Document.Root, record.Kind == VillageNbtRecordKind.Dwellers))
                .Distinct().OrderBy(value => value).ToArray();
            foreach (var id in residentIds) allResidentIds.Add(id);
            seeds.Add(new FeatureSeed(group.Key, dimension, center, bounds, poi, records, residentIds));
        }

        Dictionary<long, BedrockWorldObject> residentsById = new();
        if (allResidentIds.Count > 0)
        {
            var entities = new BedrockWorldObjectScanner(_database).ScanAll(null, includeEntities: true, includeBlockEntities: false).Objects;
            residentsById = entities.Where(item => item.UniqueId.HasValue && allResidentIds.Contains(item.UniqueId.Value))
                .GroupBy(item => item.UniqueId!.Value)
                .ToDictionary(group => group.Key, group => group.First());
        }

        return seeds.Select(seed => new VillageMapFeature(
                seed.Identifier, seed.Dimension, seed.Center, seed.Bounds, seed.Poi, seed.Records,
                seed.ResidentIds.Where(residentsById.ContainsKey).Select(id => residentsById[id]).ToArray()))
            .OrderBy(feature => feature.Dimension)
            .ThenBy(feature => feature.Center?.X ?? feature.Bounds?.MinimumX ?? 0)
            .ThenBy(feature => feature.Center?.Z ?? feature.Bounds?.MinimumZ ?? 0)
            .ToArray();
    }

    public static IReadOnlySet<string> ReferencePositionKeys(NbtValue root)
    {
        var relationshipTerms = new[] { "poi", "home", "bed", "work", "job", "dwelling", "meeting", "station" };
        var result = new HashSet<string>(StringComparer.Ordinal);
        void Add(VillageMapPointFeature point)
        {
            result.Add(point.CoordinateKey);
            result.Add(point.HorizontalCoordinateKey);
        }
        void WalkValue(NbtValue value, string nameHint, bool inheritedRelevant)
        {
            switch (value)
            {
                case NbtCompoundValue compound:
                {
                    var normalizedHint = Normalize(nameHint);
                    var relevant = inheritedRelevant || relationshipTerms.Any(term => normalizedHint.Contains(term, StringComparison.Ordinal));
                    if (relevant && TryPoint(compound, out var compoundPoint)) Add(compoundPoint);
                    foreach (var tag in compound.Tags)
                    {
                        var normalizedName = Normalize(tag.Name);
                        var childRelevant = relevant || relationshipTerms.Any(term => normalizedName.Contains(term, StringComparison.Ordinal));
                        if (childRelevant && TryPoint(tag.Value, out var point)) Add(point);
                        WalkValue(tag.Value, tag.Name, childRelevant);
                    }
                    break;
                }
                case NbtListValue list:
                    foreach (var child in list.Values) WalkValue(child, nameHint, inheritedRelevant);
                    break;
            }
        }
        WalkValue(root, string.Empty, false);
        return result;
    }

    private static int? FindDimension(NbtValue root)
    {
        foreach (var (name, value) in Walk(root))
        {
            var n = Normalize(name);
            if (n is "dimension" or "dimensionid" or "dimensionidentifier")
                return PlayerNbtStore.ParseDimension(value);
        }
        return null;
    }

    private static VillageMapPointFeature? FindCenter(NbtValue root)
    {
        foreach (var (name, value) in Walk(root))
        {
            var n = Normalize(name);
            if (!n.Contains("center", StringComparison.Ordinal)) continue;
            if (TryPoint(value, out var point)) return point with { Label = "村庄中心" };
        }
        return null;
    }

    private static VillageMapBoundsFeature? FindBounds(NbtValue root)
    {
        if (root is NbtCompoundValue compound)
        {
            var x0 = IntIgnoreCase(compound, "X0", "x0", "MinX", "min_x", "minX");
            var z0 = IntIgnoreCase(compound, "Z0", "z0", "MinZ", "min_z", "minZ");
            var x1 = IntIgnoreCase(compound, "X1", "x1", "MaxX", "max_x", "maxX");
            var z1 = IntIgnoreCase(compound, "Z1", "z1", "MaxZ", "max_z", "maxZ");
            if (x0.HasValue && z0.HasValue && x1.HasValue && z1.HasValue)
                return new VillageMapBoundsFeature(Math.Min(x0.Value, x1.Value), Math.Min(z0.Value, z1.Value), Math.Max(x0.Value, x1.Value), Math.Max(z0.Value, z1.Value));
            foreach (var tag in compound.Tags)
                if (FindBounds(tag.Value) is { } child) return child;
        }
        else if (root is NbtListValue list)
        {
            foreach (var value in list.Values) if (FindBounds(value) is { } child) return child;
        }
        return null;
    }

    private static void CollectPoi(NbtValue root, List<VillageMapPointFeature> output, IReadOnlyList<long> inheritedIds)
    {
        if (root is NbtCompoundValue compound)
        {
            var directIds = inheritedIds.Concat(LinkedEntityIds(compound)).Distinct().ToArray();
            if (TryPoint(compound, out var direct)) output.Add(direct with { Label = "POI", LinkedEntityIds = directIds });
            foreach (var tag in compound.Tags) CollectPoi(tag.Value, output, directIds);
        }
        else if (root is NbtListValue list)
        {
            foreach (var value in list.Values) CollectPoi(value, output, inheritedIds);
        }
    }

    private static IEnumerable<long> LinkedEntityIds(NbtCompoundValue compound)
    {
        foreach (var tag in compound.Tags)
        {
            var name = Normalize(tag.Name);
            var looksLikeLink = name is "id" or "uniqueid" or "villagerid" or "villageruniqueid" or "residentid" or "residentuniqueid"
                or "ownerid" or "owneruniqueid" or "occupantid" or "occupantuniqueid" or "dwellerid" or "actorid" or "entityid"
                || name.Contains("villagerid", StringComparison.Ordinal) || name.Contains("residentid", StringComparison.Ordinal)
                || name.Contains("occupantid", StringComparison.Ordinal) || name.Contains("ownerid", StringComparison.Ordinal);
            if (looksLikeLink && tag.Value.IntegerValue() is long value) yield return value;
        }
    }

    private static bool TryPoint(NbtValue value, out VillageMapPointFeature point)
    {
        if (value is NbtCompoundValue compound)
        {
            var x = IntIgnoreCase(compound, "X", "x", "PosX", "pos_x", "BlockX", "block_x");
            var y = IntIgnoreCase(compound, "Y", "y", "PosY", "pos_y", "BlockY", "block_y") ?? 0;
            var z = IntIgnoreCase(compound, "Z", "z", "PosZ", "pos_z", "BlockZ", "block_z");
            if (x.HasValue && z.HasValue) { point = new VillageMapPointFeature(x.Value, y, z.Value, "POI"); return true; }
        }
        if (value is NbtListValue list && list.Values.Count >= 3 && list.Values[0].IntegerValue() is long lx && list.Values[2].IntegerValue() is long lz)
        { point = new VillageMapPointFeature(lx, list.Values[1].IntegerValue() ?? 0, lz, "POI"); return true; }
        if (value is NbtIntArrayValue ints && ints.Values.Count >= 3)
        { point = new VillageMapPointFeature(ints.Values[0], ints.Values[1], ints.Values[2], "POI"); return true; }
        if (value is NbtLongArrayValue longs && longs.Values.Count >= 3)
        { point = new VillageMapPointFeature(longs.Values[0], longs.Values[1], longs.Values[2], "POI"); return true; }
        point = default!; return false;
    }

    private static long? IntIgnoreCase(NbtCompoundValue compound, params string[] names)
    {
        foreach (var name in names) if (compound.CompoundValueIgnoreCase(name)?.IntegerValue() is long v) return v;
        return null;
    }

    private static IEnumerable<(string Name, NbtValue Value)> Walk(NbtValue root)
    {
        if (root is NbtCompoundValue compound)
        {
            foreach (var tag in compound.Tags)
            {
                yield return (tag.Name, tag.Value);
                foreach (var child in Walk(tag.Value)) yield return child;
            }
        }
        else if (root is NbtListValue list)
        {
            foreach (var item in list.Values) foreach (var child in Walk(item)) yield return child;
        }
    }

    private static string Normalize(string value) => new(value.Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());
}
