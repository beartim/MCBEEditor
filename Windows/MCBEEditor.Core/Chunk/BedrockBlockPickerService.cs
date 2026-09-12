using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockBlockColumnResult(
    IReadOnlyList<BedrockBlockRecord> Blocks,
    IReadOnlyList<string> Diagnostics);

public sealed record BedrockBlockAxisLineResult(
    BedrockMapAxis Axis,
    IReadOnlyList<BedrockBlockRecord> Blocks,
    IReadOnlyList<string> Diagnostics);

/// <summary>
/// Desktop counterpart of the iOS map block pickers. It reads each SubChunk only
/// once per chunk and returns editable-air templates for missing SubChunks, so
/// selecting a missing coordinate keeps the same semantics as the block editor.
/// </summary>
public sealed class BedrockBlockPickerService
{
    private readonly IWorldDatabase _database;

    public BedrockBlockPickerService(IWorldDatabase database)
        => _database = database ?? throw new ArgumentNullException(nameof(database));

    public BedrockBlockColumnResult BlockColumn(int blockX, int blockZ, int dimension)
    {
        var chunkX = BedrockSurfaceRegionRenderer.FloorDiv(blockX, 16);
        var chunkZ = BedrockSurfaceRegionRenderer.FloorDiv(blockZ, 16);
        var localX = blockX - chunkX * 16;
        var localZ = blockZ - chunkZ * 16;
        var position = new ChunkPosition(chunkX, chunkZ, dimension);
        var diagnostics = new List<string>();
        IReadOnlyList<BedrockStoredSubChunk> records;
        try
        {
            records = new BedrockChunkSubChunkAccess(_database).Records(position);
        }
        catch (Exception ex)
        {
            diagnostics.Add("地形：" + ex.Message);
            records = Array.Empty<BedrockStoredSubChunk>();
        }

        var byY = records
            .GroupBy(item => item.YIndex)
            .ToDictionary(group => group.Key, group => group.First());
        var minimumSubChunkY = Math.Min(-4, records.Count == 0 ? -4 : records.Min(item => (int)item.YIndex));
        var maximumSubChunkY = Math.Max(19, records.Count == 0 ? 19 : records.Max(item => (int)item.YIndex));
        BedrockBlockState? missingAir = null;
        var blocks = new List<BedrockBlockRecord>(checked((maximumSubChunkY - minimumSubChunkY + 1) * 16));

        for (var subY = maximumSubChunkY; subY >= minimumSubChunkY; subY--)
        {
            BedrockStoredSubChunk? record = null;
            if (subY is >= sbyte.MinValue and <= sbyte.MaxValue)
                byY.TryGetValue((sbyte)subY, out record);
            var hasRecord = record is not null;
            if (!hasRecord && missingAir is null)
            {
                try { missingAir = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, position).Air; }
                catch (Exception ex)
                {
                    diagnostics.Add("缺失 SubChunk 空气模板：" + ex.Message);
                    missingAir = BedrockBlockState.EditableAir();
                }
            }

            for (var localY = 15; localY >= 0; localY--)
            {
                var y64 = (long)subY * 16 + localY;
                if (y64 < int.MinValue || y64 > int.MaxValue) continue;
                if (hasRecord && record is not null)
                {
                    var layers = record.SubChunk.Storages
                        .Select(storage => storage.BlockState(localX, localY, localZ))
                        .Where(state => state is not null)
                        .Cast<BedrockBlockState>()
                        .ToArray();
                    blocks.Add(new BedrockBlockRecord(blockX, (int)y64, blockZ, dimension, true,
                        layers, record.SubChunk.Version, record.BackingKind));
                }
                else
                {
                    blocks.Add(new BedrockBlockRecord(blockX, (int)y64, blockZ, dimension, false,
                        [missingAir ?? BedrockBlockState.EditableAir()], null, null));
                }
            }
        }
        return new BedrockBlockColumnResult(blocks, diagnostics);
    }

    public BedrockBlockAxisLineResult BlockAxisLine(
        BedrockMapAxis axis,
        int fixedY,
        int fixedX,
        int fixedZ,
        int minimumCoordinate,
        int maximumCoordinate,
        int dimension)
    {
        if (axis is not (BedrockMapAxis.X or BedrockMapAxis.Z))
            throw new ArgumentException("仅 X/Z 轴支持水平方块选择。", nameof(axis));

        var lower = Math.Min((long)minimumCoordinate, maximumCoordinate);
        var upper = Math.Max((long)minimumCoordinate, maximumCoordinate);
        const long maximumRows = 8192;
        var cappedLower = Math.Max(lower, upper - maximumRows + 1);
        var diagnostics = new List<string>();
        if (cappedLower != lower)
            diagnostics.Add($"轴向范围过大，选择器仅显示靠近正方向的最后 {maximumRows} 个方块。");

        var subY = BedrockSurfaceRegionRenderer.FloorDiv(fixedY, 16);
        var localY = fixedY - subY * 16;
        var access = new BedrockChunkSubChunkAccess(_database);
        var chunkCache = new Dictionary<ChunkPosition, IReadOnlyDictionary<sbyte, BedrockStoredSubChunk>>();
        var missingAirCache = new Dictionary<ChunkPosition, BedrockBlockState>();
        BedrockBlockFormat? dimensionFallbackFormat = null;
        var blocks = new List<BedrockBlockRecord>(checked((int)(upper - cappedLower + 1)));

        for (var coordinate = upper; coordinate >= cappedLower; coordinate--)
        {
            if (coordinate < int.MinValue || coordinate > int.MaxValue)
            {
                if (coordinate == long.MinValue) break;
                continue;
            }
            var x = axis == BedrockMapAxis.X ? (int)coordinate : fixedX;
            var z = axis == BedrockMapAxis.Z ? (int)coordinate : fixedZ;
            var chunkX = BedrockSurfaceRegionRenderer.FloorDiv(x, 16);
            var chunkZ = BedrockSurfaceRegionRenderer.FloorDiv(z, 16);
            var localX = x - chunkX * 16;
            var localZ = z - chunkZ * 16;
            var position = new ChunkPosition(chunkX, chunkZ, dimension);

            if (!chunkCache.TryGetValue(position, out var byY))
            {
                try
                {
                    byY = access.Records(position)
                        .GroupBy(item => item.YIndex)
                        .ToDictionary(group => group.Key, group => group.First());
                }
                catch (Exception ex)
                {
                    diagnostics.Add($"区块 ({chunkX},{chunkZ})：{ex.Message}");
                    byY = new Dictionary<sbyte, BedrockStoredSubChunk>();
                }
                chunkCache[position] = byY;
            }

            BedrockStoredSubChunk? record = null;
            if (subY is >= sbyte.MinValue and <= sbyte.MaxValue)
                byY.TryGetValue((sbyte)subY, out record);

            if (record is not null)
            {
                var layers = record.SubChunk.Storages
                    .Select(storage => storage.BlockState(localX, localY, localZ))
                    .Where(state => state is not null)
                    .Cast<BedrockBlockState>()
                    .ToArray();
                blocks.Add(new BedrockBlockRecord(x, fixedY, z, dimension, true,
                    layers, record.SubChunk.Version, record.BackingKind));
            }
            else
            {
                if (!missingAirCache.TryGetValue(position, out var air))
                {
                    try
                    {
                        dimensionFallbackFormat ??= BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension);
                        air = BedrockEmptyChunkMetadata.DetectBlockFormat(_database, dimension, position, dimensionFallbackFormat).Air;
                    }
                    catch (Exception ex)
                    {
                        diagnostics.Add($"区块 ({chunkX},{chunkZ}) 空气模板：{ex.Message}");
                        air = BedrockBlockState.EditableAir();
                    }
                    missingAirCache[position] = air;
                }
                blocks.Add(new BedrockBlockRecord(x, fixedY, z, dimension, false, [air], null, null));
            }

            if (coordinate == long.MinValue) break;
        }
        return new BedrockBlockAxisLineResult(axis, blocks, diagnostics);
    }
}
