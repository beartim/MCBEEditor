using System.Buffers.Binary;
using System.Globalization;
using System.Text;
using MCBEEditor.Core.Chunk;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Entity;

public sealed class BedrockWorldObjectScanner
{
    private readonly IWorldDatabase _database;
    public BedrockWorldObjectScanner(IWorldDatabase database) => _database = database;

    public BedrockWorldObjectScanResult ScanRegion(
        int centerChunkX,
        int centerChunkZ,
        int dimension,
        int radius,
        bool includeEntities,
        bool includeBlockEntities,
        int maximumObjects = 5000)
    {
        if (!includeEntities && !includeBlockEntities) return BedrockWorldObjectScanResult.Empty;
        if (radius < 0) throw new ArgumentOutOfRangeException(nameof(radius));
        if (maximumObjects < 1) throw new ArgumentOutOfRangeException(nameof(maximumObjects));

        var output = new List<BedrockWorldObject>();
        var diagnostics = new List<string>();
        var seenActorReferences = new HashSet<string>(StringComparer.Ordinal);
        var actorDigestCount = 0;
        var actorRecordCount = 0;
        var legacyCount = 0;
        var blockEntityCount = 0;

        var minX = Math.Max((long)int.MinValue, (long)centerChunkX - radius);
        var maxX = Math.Min((long)int.MaxValue, (long)centerChunkX + radius);
        var minZ = Math.Max((long)int.MinValue, (long)centerChunkZ - radius);
        var maxZ = Math.Min((long)int.MaxValue, (long)centerChunkZ + radius);
        var chunkCount = checked((maxX - minX + 1) * (maxZ - minZ + 1));
        if (chunkCount > 262_144) throw new InvalidOperationException("实体扫描区域过大，请缩小地图范围。");

        for (var z64 = minZ; z64 <= maxZ && output.Count < maximumObjects; z64++)
        {
            var z = (int)z64;
            for (var x64 = minX; x64 <= maxX && output.Count < maximumObjects; x64++)
            {
                var x = (int)x64;
                if (includeBlockEntities)
                {
                    var key = new BedrockDbKey(new ChunkPosition(x, z, dimension), ChunkRecordType.BlockEntity, null).Encode();
                    var data = _database.Get(key);
                    if (data is not null)
                    {
                        blockEntityCount++;
                        DecodeInto(output, diagnostics, data, BedrockWorldObjectKind.BlockEntity, dimension, x, z,
                            BedrockWorldObjectSource.BlockEntity, null, key, null, maximumObjects);
                    }
                }

                if (!includeEntities) continue;

                var legacyKey = new BedrockDbKey(new ChunkPosition(x, z, dimension), ChunkRecordType.Entity, null).Encode();
                var legacyData = _database.Get(legacyKey);
                if (legacyData is not null)
                {
                    legacyCount++;
                    DecodeInto(output, diagnostics, legacyData, BedrockWorldObjectKind.Entity, dimension, x, z,
                        BedrockWorldObjectSource.LegacyChunkEntity, null, legacyKey, null, maximumObjects);
                }

                var digestEntry = FindDigest(x, z, dimension);
                if (digestEntry is null) continue;
                actorDigestCount++;
                var digest = digestEntry.Value.Data;
                if ((digest.Length & 7) != 0)
                    diagnostics.Add($"实体摘要 ({x},{z}) 长度 {digest.Length} 不是 8 的倍数。");
                var usable = digest.Length - digest.Length % 8;
                for (var offset = 0; offset < usable && output.Count < maximumObjects; offset += 8)
                {
                    var reference = digest.AsSpan(offset, 8).ToArray();
                    var referenceHex = Convert.ToHexString(reference);
                    if (!seenActorReferences.Add(referenceHex)) continue;
                    var actorKey = ActorKey(reference);
                    var actorData = _database.Get(actorKey);
                    if (actorData is null)
                    {
                        diagnostics.Add("摘要引用的 actorprefix 记录不存在：0x" + referenceHex.ToLowerInvariant());
                        continue;
                    }
                    actorRecordCount++;
                    DecodeInto(output, diagnostics, actorData, BedrockWorldObjectKind.Entity, dimension, x, z,
                        BedrockWorldObjectSource.ModernActor, BinaryPrimitives.ReadInt64LittleEndian(reference), actorKey,
                        digestEntry.Value.Key, maximumObjects);
                }
            }
        }

        if (output.Count >= maximumObjects) diagnostics.Add($"达到 {maximumObjects} 个对象的安全上限，结果已截断。");
        return FinalizeResult(output, diagnostics, actorDigestCount, actorRecordCount, legacyCount, blockEntityCount);
    }

    public BedrockWorldObjectScanResult ScanAll(
        ISet<int>? dimensions,
        bool includeEntities,
        bool includeBlockEntities,
        int maximumObjects = 200_000)
    {
        if (!includeEntities && !includeBlockEntities) return BedrockWorldObjectScanResult.Empty;
        var output = new List<BedrockWorldObject>();
        var diagnostics = new List<string>();
        var actorDigestCount = 0;
        var actorRecordCount = 0;
        var legacyCount = 0;
        var blockEntityCount = 0;

        var digpLocations = new Dictionary<string, (byte[] Key, int Dimension, int X, int Z)>(StringComparer.Ordinal);
        if (includeEntities)
        {
            var digpPrefix = Encoding.ASCII.GetBytes("digp");
            foreach (var entry in _database.Entries(digpPrefix, includeValues: true))
            {
                if (entry.Value is null || !TryParseDigestKey(entry.Key, out var dimension, out var x, out var z)) continue;
                actorDigestCount++;
                if ((entry.Value.Length & 7) != 0) diagnostics.Add($"实体摘要 ({x},{z}) 长度 {entry.Value.Length} 不是 8 的倍数。");
                var usable = entry.Value.Length - entry.Value.Length % 8;
                for (var offset = 0; offset < usable; offset += 8)
                {
                    var referenceHex = Convert.ToHexString(entry.Value, offset, 8);
                    digpLocations.TryAdd(referenceHex, (entry.Key, dimension, x, z));
                }
            }

            var actorPrefix = Encoding.ASCII.GetBytes("actorprefix");
            foreach (var entry in _database.Entries(actorPrefix, includeValues: true))
            {
                if (output.Count >= maximumObjects) break;
                if (entry.Value is null || entry.Key.Length != actorPrefix.Length + 8) continue;
                var reference = entry.Key.AsSpan(actorPrefix.Length, 8);
                var hex = Convert.ToHexString(reference);
                if (!digpLocations.TryGetValue(hex, out var location))
                {
                    diagnostics.Add("未被 digp 引用的孤立 actorprefix，已忽略：0x" + hex.ToLowerInvariant());
                    continue;
                }
                if (dimensions is not null && !dimensions.Contains(location.Dimension)) continue;
                actorRecordCount++;
                DecodeInto(output, diagnostics, entry.Value, BedrockWorldObjectKind.Entity, location.Dimension,
                    location.X, location.Z, BedrockWorldObjectSource.ModernActor,
                    BinaryPrimitives.ReadInt64LittleEndian(reference), entry.Key, location.Key, maximumObjects);
            }
        }

        foreach (var entry in _database.Entries(includeValues: false))
        {
            if (output.Count >= maximumObjects) break;
            if (!BedrockDbKey.TryParse(entry.Key, out var parsed)) continue;
            if (dimensions is not null && !dimensions.Contains(parsed.Position.Dimension)) continue;
            BedrockWorldObjectKind kind;
            BedrockWorldObjectSource source;
            if (includeBlockEntities && parsed.RecordType == ChunkRecordType.BlockEntity)
            {
                kind = BedrockWorldObjectKind.BlockEntity; source = BedrockWorldObjectSource.BlockEntity; blockEntityCount++;
            }
            else if (includeEntities && parsed.RecordType == ChunkRecordType.Entity)
            {
                kind = BedrockWorldObjectKind.Entity; source = BedrockWorldObjectSource.LegacyChunkEntity; legacyCount++;
            }
            else continue;
            var data = _database.Get(entry.Key);
            if (data is null) continue;
            DecodeInto(output, diagnostics, data, kind, parsed.Position.Dimension, parsed.Position.X, parsed.Position.Z,
                source, null, entry.Key, null, maximumObjects);
        }

        if (output.Count >= maximumObjects) diagnostics.Add($"达到 {maximumObjects} 个对象的安全上限，结果已截断。");
        return FinalizeResult(output, diagnostics, actorDigestCount, actorRecordCount, legacyCount, blockEntityCount);
    }

    private BedrockWorldObjectScanResult FinalizeResult(List<BedrockWorldObject> source, List<string> diagnostics,
        int digestCount, int actorCount, int legacyCount, int blockEntityCount)
    {
        var unique = new Dictionary<string, BedrockWorldObject>(StringComparer.Ordinal);
        foreach (var item in source)
        {
            if (unique.TryGetValue(item.StableId, out var existing))
            {
                if (existing.Source != BedrockWorldObjectSource.ModernActor && item.Source == BedrockWorldObjectSource.ModernActor)
                    unique[item.StableId] = item;
            }
            else unique[item.StableId] = item;
        }
        var objects = unique.Values
            .OrderBy(o => o.Dimension)
            .ThenBy(o => o.Kind)
            .ThenBy(o => o.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(o => o.Position?.BlockZ ?? o.ChunkZ * 16)
            .ThenBy(o => o.Position?.BlockX ?? o.ChunkX * 16)
            .ThenBy(o => o.Position?.BlockY ?? 0)
            .ToArray();
        return new BedrockWorldObjectScanResult(objects, diagnostics, digestCount, actorCount, legacyCount, blockEntityCount);
    }

    private void DecodeInto(List<BedrockWorldObject> output, List<string> diagnostics, byte[] data,
        BedrockWorldObjectKind kind, int dimension, int chunkX, int chunkZ, BedrockWorldObjectSource source,
        long? fallbackActorId, byte[] storageKey, byte[]? digestKey, int maximumObjects)
    {
        try
        {
            var records = ConsecutiveNbtCodec.Decode(data);
            for (var index = 0; index < records.Count && output.Count < maximumObjects; index++)
            {
                var record = records[index];
                output.Add(MakeObject(record, index, kind, dimension, chunkX, chunkZ, source, fallbackActorId,
                    storageKey, digestKey));
            }
        }
        catch (Exception ex)
        {
            diagnostics.Add($"{SourceLabel(source)} ({chunkX},{chunkZ})：{ex.Message}");
        }
    }

    private static BedrockWorldObject MakeObject(ConsecutiveNbtRecord record, int index,
        BedrockWorldObjectKind kind, int fallbackDimension, int fallbackChunkX, int fallbackChunkZ,
        BedrockWorldObjectSource source, long? fallbackActorId, byte[] storageKey, byte[]? digestKey)
    {
        var root = record.Document.Root;
        var dimension = ExtractDimension(root) ?? fallbackDimension;
        var identifier = ResolveIdentifier(root, kind);
        var customName = StringValue(root, "CustomName", "customName", "Name", "name");
        var position = ExtractPosition(root, kind);
        var chunkX = position is null ? fallbackChunkX : FloorDiv(position.BlockX, 16);
        var chunkZ = position is null ? fallbackChunkZ : FloorDiv(position.BlockZ, 16);
        var nbtId = IntegerValue(root, "UniqueID", "UniqueId", "uniqueID", "uniqueId");
        var uniqueId = nbtId ?? fallbackActorId;
        var itemCount = CountItems(root);
        BedrockWorldObjectStorage storage = source == BedrockWorldObjectSource.ModernActor
            ? new ModernActorStorage(storageKey.ToArray(), digestKey?.ToArray() ?? Array.Empty<byte>(), index, record.Encoding)
            : new ChunkRecordStorage(storageKey.ToArray(), index, record.Encoding);

        var stable = source == BedrockWorldObjectSource.ModernActor
            ? $"actorprefix:{Convert.ToHexString(storageKey)}:{index}"
            : uniqueId.HasValue
                ? $"actor:{uniqueId.Value}"
                : position is not null
                    ? $"{kind}:{dimension}:{position.BlockX}:{position.BlockY}:{position.BlockZ}:{identifier}:{index}"
                    : $"{kind}:{dimension}:{fallbackChunkX}:{fallbackChunkZ}:{identifier}:{index}";

        return new BedrockWorldObject(stable, kind, identifier, customName, position, dimension, chunkX, chunkZ,
            source, uniqueId, itemCount, record.Document, record.RawData, storage);
    }

    private (byte[] Key, byte[] Data)? FindDigest(int x, int z, int dimension)
    {
        foreach (var key in DigestKeys(x, z, dimension))
        {
            var data = _database.Get(key);
            if (data is not null) return (key, data);
        }
        return null;
    }

    private static IEnumerable<byte[]> DigestKeys(int x, int z, int dimension)
    {
        yield return DigestKey(x, z, dimension);
    }

    internal static byte[] DigestKey(int x, int z, int dimension)
    {
        var prefix = Encoding.ASCII.GetBytes("digp");
        var includeDimension = dimension != 0;
        var key = new byte[prefix.Length + 8 + (includeDimension ? 4 : 0)];
        prefix.CopyTo(key, 0);
        BinaryPrimitives.WriteInt32LittleEndian(key.AsSpan(prefix.Length, 4), x);
        BinaryPrimitives.WriteInt32LittleEndian(key.AsSpan(prefix.Length + 4, 4), z);
        if (includeDimension) BinaryPrimitives.WriteInt32LittleEndian(key.AsSpan(prefix.Length + 8, 4), dimension);
        return key;
    }

    internal static byte[] ActorKey(ReadOnlySpan<byte> reference)
    {
        if (reference.Length != 8) throw new ArgumentException("Actor storage reference must be 8 bytes.", nameof(reference));
        var prefix = Encoding.ASCII.GetBytes("actorprefix");
        var key = new byte[prefix.Length + 8];
        prefix.CopyTo(key, 0);
        reference.CopyTo(key.AsSpan(prefix.Length));
        return key;
    }

    private static bool TryParseDigestKey(byte[] key, out int dimension, out int x, out int z)
    {
        dimension = x = z = 0;
        var prefixLength = Encoding.ASCII.GetByteCount("digp");
        if (key.Length != prefixLength + 8 && key.Length != prefixLength + 12) return false;
        x = BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(prefixLength, 4));
        z = BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(prefixLength + 4, 4));
        if (key.Length == prefixLength + 12) dimension = BinaryPrimitives.ReadInt32LittleEndian(key.AsSpan(prefixLength + 8, 4));
        return true;
    }

    private static string ResolveIdentifier(NbtValue root, BedrockWorldObjectKind kind)
    {
        var direct = root.CompoundValueIgnoreCase("identifier", "Identifier", "id", "Id");
        if (kind == BedrockWorldObjectKind.Entity)
        {
            if (direct is NbtStringValue text)
            {
                var value = text.Value.Trim();
                if (value.Length > 0)
                {
                    if (TryParseNumericId(value, out var numeric))
                        return BedrockEntityCatalog.IdentifierForNumericId(numeric) ?? FirstDefinition(root) ?? $"数字实体ID:{numeric}";
                    return value;
                }
            }
            if (direct?.IntegerValue() is long numericId)
                return BedrockEntityCatalog.IdentifierForNumericId(numericId) ?? FirstDefinition(root) ?? $"数字实体ID:{numericId}";
            var alternative = root.CompoundValueIgnoreCase("EntityType", "entityType", "EntityID", "entityID")?.IntegerValue();
            if (alternative.HasValue)
                return BedrockEntityCatalog.IdentifierForNumericId(alternative.Value) ?? FirstDefinition(root) ?? $"数字实体ID:{alternative.Value}";
        }
        else if (direct is NbtStringValue blockEntityText && !string.IsNullOrWhiteSpace(blockEntityText.Value))
            return blockEntityText.Value.Trim();
        return kind == BedrockWorldObjectKind.Entity ? "未知实体" : "未知方块实体";
    }

    private static string? FirstDefinition(NbtValue root)
    {
        if (root.CompoundValueIgnoreCase("definitions", "Definitions") is not NbtListValue list || list.Values.Count == 0 || list.Values[0] is not NbtStringValue text)
            return null;
        var value = text.Value.Trim();
        while (value.StartsWith('+')) value = value[1..];
        value = value.Trim();
        return value.Length == 0 ? null : value;
    }

    private static bool TryParseNumericId(string value, out long id)
    {
        value = value.Trim();
        if (value.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            return long.TryParse(value[2..], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out id);
        return long.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out id);
    }

    internal static BedrockWorldObjectPosition? ExtractPosition(NbtValue root, BedrockWorldObjectKind kind)
    {
        if (root.CompoundValueIgnoreCase("Pos", "pos", "Position", "position") is NbtListValue list && list.Values.Count >= 3
            && PlayerNbtStore.TryNumber(list.Values[0], out var lx)
            && PlayerNbtStore.TryNumber(list.Values[1], out var ly)
            && PlayerNbtStore.TryNumber(list.Values[2], out var lz))
            return new BedrockWorldObjectPosition(lx, ly, lz);

        var xNames = kind == BedrockWorldObjectKind.BlockEntity ? new[] { "x", "X" } : new[] { "x", "X", "PosX", "posX" };
        var yNames = kind == BedrockWorldObjectKind.BlockEntity ? new[] { "y", "Y" } : new[] { "y", "Y", "PosY", "posY" };
        var zNames = kind == BedrockWorldObjectKind.BlockEntity ? new[] { "z", "Z" } : new[] { "z", "Z", "PosZ", "posZ" };
        if (TryNamedNumber(root, xNames, out var x) && TryNamedNumber(root, yNames, out var y) && TryNamedNumber(root, zNames, out var z))
            return new BedrockWorldObjectPosition(x, y, z);
        return null;
    }

    internal static int? ExtractDimension(NbtValue root)
        => PlayerNbtStore.ParseDimension(root.CompoundValueIgnoreCase("DimensionId", "DimensionID", "dimensionId", "dimension", "Dimension"));

    private static int CountItems(NbtValue root)
    {
        var count = 0;
        foreach (var name in new[] { "Items", "items", "Inventory", "inventory", "Armor", "Mainhand", "Offhand" })
        {
            if (root.CompoundValueIgnoreCase(name) is not NbtListValue list) continue;
            foreach (var value in list.Values)
            {
                if (value is not NbtCompoundValue)
                {
                    count++;
                    continue;
                }
                var stack = value.CompoundValueIgnoreCase("Count", "count")?.IntegerValue() ?? 1;
                if (stack > 0) count++;
            }
        }
        return count;
    }

    private static bool TryNamedNumber(NbtValue root, string[] names, out double value)
        => PlayerNbtStore.TryNumber(root.CompoundValueIgnoreCase(names), out value);

    private static string? StringValue(NbtValue root, params string[] names)
        => root.CompoundValueIgnoreCase(names) is NbtStringValue value ? value.Value : null;

    private static long? IntegerValue(NbtValue root, params string[] names)
        => root.CompoundValueIgnoreCase(names)?.IntegerValue();

    internal static int FloorDiv(int value, int divisor)
    {
        var q = value / divisor;
        var r = value % divisor;
        return r < 0 ? q - 1 : q;
    }

    private static string SourceLabel(BedrockWorldObjectSource source) => source switch
    {
        BedrockWorldObjectSource.ModernActor => "实体",
        BedrockWorldObjectSource.LegacyChunkEntity => "旧实体",
        BedrockWorldObjectSource.BlockEntity => "方块实体",
        _ => "对象"
    };
}
