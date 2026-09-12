using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockStorageMutationResult(
    int StorageCountBefore,
    int StorageCountAfter,
    int PutCount,
    string Message);

/// <summary>
/// command-only physical storage editor. Unlike setblock/fill, these
/// operations change the SubChunk storage array itself, so they are deliberately
/// restricted to known structured modern v8/v9 SubChunks.
/// </summary>
public sealed class BedrockStorageCommandStore
{
    private readonly IWorldDatabase _database;
    private readonly BedrockChunkSubChunkAccess _access;

    public BedrockStorageCommandStore(IWorldDatabase database)
    {
        _database = database ?? throw new ArgumentNullException(nameof(database));
        _access = new BedrockChunkSubChunkAccess(database);
    }

    public IReadOnlyList<string> Query(int dimension, BedrockBlockCoordinate position)
    {
        var address = Address(dimension, position);
        var stored = _access.Record(address.Chunk, address.SubChunkY);
        if (stored is null) return ["Block not generated"];
        RequireStructuredModern(stored);
        var output = new List<string>(stored.SubChunk.Storages.Count);
        for (var layer = 0; layer < stored.SubChunk.Storages.Count; layer++)
        {
            var storage = stored.SubChunk.Storages[layer];
            var state = storage.BlockState(address.LocalX, address.LocalY, address.LocalZ)
                ?? throw new InvalidDataException($"storage {layer} 的方块索引无效。");
            output.Add($"层{layer}=[{BlockCommandNbtOutputFormatter.BlockState(state)}]");
        }
        return output;
    }

    public BedrockStorageMutationResult Set(int dimension, BedrockBlockCoordinate position, int layer, BedrockBlockStorageSpec block)
    {
        if (layer is < 0 or >= byte.MaxValue)
            throw new ArgumentOutOfRangeException(nameof(layer), "storage 层数必须为 0…254。");
        var address = Address(dimension, position);
        var stored = _access.Record(address.Chunk, address.SubChunkY);
        BedrockSubChunk original;

        if (stored is not null)
        {
            RequireStructuredModern(stored);
            original = stored.SubChunk;
        }
        else
        {
            var format = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, address.Chunk);
            if (format.IsLegacyNumeric || format.SubChunkVersion is not (8 or 9))
                throw new NotSupportedException($"storage set 只支持 v8 或更新的已知结构化 SubChunk；当前新建格式为 v{format.SubChunkVersion}。");
            var profile = BedrockEmptyChunkMetadata.DetectProfile(_database, dimension, preferLegacy: false);
            if (profile.UsesLegacyTerrain)
                throw new NotSupportedException("storage set 不能在 LegacyTerrain 世界中猜测创建现代 SubChunk。");
            original = new BedrockSubChunk(format.SubChunkVersion, address.SubChunkY,
                [SubChunkStorage.AirFilled(format.Air)], []);

        }

        var before = original.Storages.Count;
        var paletteVersion = original.Storages
            .SelectMany(storage => storage.Palette)
            .Select(state => state.PaletteVersion)
            .FirstOrDefault(version => version.HasValue)
            ?? BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, address.Chunk).BlockPaletteVersion;
        var updated = original.ReplacingBlockState(
            address.LocalX, address.LocalY, address.LocalZ, layer, block.ModernState(paletteVersion));
        var putCount = Persist(address.Chunk, address.SubChunkY, updated);
        var changed = putCount > 0 ? 1 : 0;
        return new BedrockStorageMutationResult(before, updated.Storages.Count, putCount,
            $"storage set 完成：层 {layer}={block.Name}；变化={changed}；storage 数量 {before}→{updated.Storages.Count}；WriteBatch Put={putCount}。");
    }

    public BedrockStorageMutationResult Delete(int dimension, BedrockBlockCoordinate position, int layer)
    {
        if (layer is < 0 or >= byte.MaxValue)
            throw new ArgumentOutOfRangeException(nameof(layer), "storage 层数必须为 0…254。");
        var address = Address(dimension, position);
        var stored = _access.Record(address.Chunk, address.SubChunkY);
        if (stored is null) return new BedrockStorageMutationResult(0, 0, 0, "Block not generated");
        RequireStructuredModern(stored);
        var before = stored.SubChunk.Storages.Count;
        if (layer >= before)
            throw new InvalidOperationException($"目标 SubChunk 只有 {before} 个 storage，不存在层 {layer}。");

        var storages = stored.SubChunk.Storages.ToList();
        storages.RemoveAt(layer);
        if (storages.Count == 0)
            storages.Add(SubChunkStorage.AirFilled(EditableAir(stored.SubChunk)));
        TrimTrailingAir(storages);
        var updated = stored.SubChunk with { Storages = storages, RawPersistentData = null };
        Persist(address.Chunk, address.SubChunkY, updated);
        return new BedrockStorageMutationResult(before, storages.Count, 1,
            $"storage delete 完成：删除原层 {layer}，后续 storage 已前移；storage 数量 {before}→{storages.Count}。");
    }

    public BedrockStorageMutationResult Clear(int dimension, BedrockBlockCoordinate position, byte keepThroughLayer)
    {
        var address = Address(dimension, position);
        var stored = _access.Record(address.Chunk, address.SubChunkY);
        if (stored is null) return new BedrockStorageMutationResult(0, 0, 0, "Block not generated");
        RequireStructuredModern(stored);
        var before = stored.SubChunk.Storages.Count;
        if (keepThroughLayer == byte.MaxValue || before <= keepThroughLayer + 1)
        {
            return new BedrockStorageMutationResult(before, before, 0,
                $"storage clear：当前只有 {before} 个 storage，无需裁剪（保留到层 {keepThroughLayer}）。");
        }

        var keepCount = keepThroughLayer + 1;
        var storages = stored.SubChunk.Storages.Take(keepCount).ToList();
        if (storages.Count == 0)
            storages.Add(SubChunkStorage.AirFilled(EditableAir(stored.SubChunk)));
        var updated = stored.SubChunk with { Storages = storages, RawPersistentData = null };
        Persist(address.Chunk, address.SubChunkY, updated);
        return new BedrockStorageMutationResult(before, storages.Count, 1,
            $"storage clear 完成：保留 storage 0…{keepThroughLayer}；storage 数量 {before}→{storages.Count}。");
    }

    private static void RequireStructuredModern(BedrockStoredSubChunk stored)
    {
        if (stored.BackingKind != BedrockSubChunkBackingKind.SubChunk)
            throw new NotSupportedException("storage 命令不直接修改 LegacyTerrain。");
        if (stored.SubChunk.IsRawPreservedUnknownVersion)
            throw new NotSupportedException($"未知 SubChunk v{stored.SubChunk.Version} 只能原样保留，不能执行 storage 命令。");
        if (stored.SubChunk.Version is not (8 or 9) || stored.SubChunk.IsLegacyNumeric)
            throw new NotSupportedException($"storage 命令仅支持已知结构化 SubChunk v8/v9；当前为 v{stored.SubChunk.Version}。");
        if (stored.SubChunk.Storages.Count == 0)
            throw new InvalidDataException("目标 SubChunk 没有 storage。");
    }

    private int Persist(ChunkPosition chunk, sbyte y, BedrockSubChunk updated)
    {
        var puts = _access.PersistentPuts(chunk, new Dictionary<sbyte, BedrockSubChunk> { [y] = updated })
            .GroupBy(item => Convert.ToHexString(item.Key), StringComparer.Ordinal)
            .Select(group => group.Last())
            .Where(item =>
            {
                var current = _database.Get(item.Key);
                return current is null || !current.AsSpan().SequenceEqual(item.Value);
            })
            .ToArray();
        if (puts.Length == 0) return 0;
        _database.ApplyBatch(puts, Array.Empty<byte[]>(), sync: true);
        return puts.Length;
    }

    private static BedrockBlockState EditableAir(BedrockSubChunk subChunk)
    {
        var version = subChunk.Storages.SelectMany(storage => storage.Palette)
            .Select(state => state.PaletteVersion)
            .FirstOrDefault(value => value.HasValue);
        return BedrockBlockState.EditableAir(version);
    }

    private static void TrimTrailingAir(List<SubChunkStorage> storages)
    {
        while (storages.Count > 1 && IsAllAir(storages[^1])) storages.RemoveAt(storages.Count - 1);
    }

    private static bool IsAllAir(SubChunkStorage storage)
    {
        if (storage.Indices.Length != 4096 || storage.Palette.Count == 0) return false;
        foreach (var index in storage.Indices)
        {
            if (index >= storage.Palette.Count || !storage.Palette[index].IsAir) return false;
        }
        return true;
    }

    private static BlockAddress Address(int dimension, BedrockBlockCoordinate position)
    {
        var chunkX = FloorDiv(position.X, 16);
        var chunkZ = FloorDiv(position.Z, 16);
        var subY = FloorDiv(position.Y, 16);
        if (subY is < sbyte.MinValue or > sbyte.MaxValue)
            throw new ArgumentOutOfRangeException(nameof(position), "Y 超出 Bedrock SubChunk Int8 索引范围。");
        return new BlockAddress(
            new ChunkPosition(chunkX, chunkZ, dimension),
            (sbyte)subY,
            FloorMod(position.X, 16), FloorMod(position.Y, 16), FloorMod(position.Z, 16));
    }

    private static int FloorDiv(int value, int divisor)
    {
        var quotient = value / divisor;
        var remainder = value % divisor;
        return remainder < 0 ? quotient - 1 : quotient;
    }

    private static int FloorMod(int value, int divisor)
    {
        var remainder = value % divisor;
        return remainder < 0 ? remainder + divisor : remainder;
    }

    private readonly record struct BlockAddress(
        ChunkPosition Chunk, sbyte SubChunkY, int LocalX, int LocalY, int LocalZ);
}
