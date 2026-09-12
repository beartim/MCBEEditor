using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockBiomeMutationResult(
    int ProcessedChunkCount,
    int ChangedChunkCount,
    int SkippedChunkCount,
    long ChangedCellCount,
    int PutCount);

public sealed class BedrockBiomeRegionStore
{
    private readonly IWorldDatabase _database;

    public BedrockBiomeRegionStore(IWorldDatabase database)
        => _database = database ?? throw new ArgumentNullException(nameof(database));

    public BedrockBiomeMutationResult FillBiome(int dimension, BedrockBlockBox region, uint biomeId)
    {
        if (region.Volume > BedrockRegionBlockStore.MaximumVolume)
            throw new InvalidOperationException($"区域体积 {region.Volume:N0} 超过上限 {BedrockRegionBlockStore.MaximumVolume:N0}。");

        var minChunkX = FloorDiv(region.Minimum.X, 16);
        var maxChunkX = FloorDiv(region.Maximum.X, 16);
        var minChunkZ = FloorDiv(region.Minimum.Z, 16);
        var maxChunkZ = FloorDiv(region.Maximum.Z, 16);
        var processed = checked((maxChunkX - minChunkX + 1) * (maxChunkZ - minChunkZ + 1));
        var puts = new List<WorldDatabasePut>();
        var changedChunks = 0;
        var skipped = 0;
        long changedCells = 0;

        for (var chunkZ = minChunkZ; chunkZ <= maxChunkZ; chunkZ++)
        for (var chunkX = minChunkX; chunkX <= maxChunkX; chunkX++)
        {
            var chunk = new ChunkPosition(chunkX, chunkZ, dimension);
            var record = FindBiomeRecord(chunk);
            if (record is null)
            {
                skipped++;
                continue;
            }

            var document = BedrockBiomeDocument.Decode(record.Value.Type, record.Value.Value);
            if (document.Format != BedrockBiomeFormat.Data3D && biomeId > byte.MaxValue)
                throw new InvalidDataException($"Data2D 生物群系 ID 必须为 0～255；当前 32 位原始值为 {biomeId}。");

            var localMinX = Math.Max(0, region.Minimum.X - chunkX * 16);
            var localMaxX = Math.Min(15, region.Maximum.X - chunkX * 16);
            var localMinZ = Math.Max(0, region.Minimum.Z - chunkZ * 16);
            var localMaxZ = Math.Min(15, region.Maximum.Z - chunkZ * 16);
            var changed = 0L;

            if (document.Format is BedrockBiomeFormat.Data2D or BedrockBiomeFormat.Data2DLegacy)
            {
                if (document.Layers.Count == 0) continue;
                var layer = document.Layers[0];
                var values = layer.BiomeIds.ToArray();
                for (var z = localMinZ; z <= localMaxZ; z++)
                for (var x = localMinX; x <= localMaxX; x++)
                {
                    var index = z * 16 + x;
                    if ((uint)index >= (uint)values.Length) continue;
                    values[index] = biomeId;
                    changed++;
                }
                document.Layers[0] = new BedrockBiomeLayer(layer.BaseY, values, false);
            }
            else
            {
                for (var layerIndex = 0; layerIndex < document.Layers.Count; layerIndex++)
                {
                    var layer = document.Layers[layerIndex];
                    if (layer.IsAbsent || layer.BaseY is not int baseY) continue;
                    var lower = Math.Max(0, region.Minimum.Y - baseY);
                    var upper = Math.Min(15, region.Maximum.Y - baseY);
                    if (lower > upper) continue;
                    var values = layer.BiomeIds.ToArray();
                    for (var x = localMinX; x <= localMaxX; x++)
                    for (var z = localMinZ; z <= localMaxZ; z++)
                    for (var y = lower; y <= upper; y++)
                    {
                        var index = x * 256 + z * 16 + y;
                        if ((uint)index >= (uint)values.Length) continue;
                        values[index] = biomeId;
                        changed++;
                    }
                    document.Layers[layerIndex] = new BedrockBiomeLayer(baseY, values, false);
                }
            }

            if (changed == 0) continue;
            puts.Add(new WorldDatabasePut(record.Value.Key, document.Encode()));
            changedChunks++;
            changedCells += changed;
        }

        if (puts.Count == 0)
            throw new InvalidOperationException("选区内没有可修改的生物群系记录。");

        var coalesced = puts
            .GroupBy(item => Convert.ToHexString(item.Key), StringComparer.Ordinal)
            .Select(group => group.Last())
            .ToArray();
        _database.ApplyBatch(coalesced, Array.Empty<byte[]>(), sync: true);
        return new BedrockBiomeMutationResult(processed, changedChunks, skipped, changedCells, coalesced.Length);
    }

    private (byte[] Key, ChunkRecordType Type, byte[] Value)? FindBiomeRecord(ChunkPosition position)
    {
        (byte[] Key, ChunkRecordType Type, byte[] Value)? fallback = null;
        foreach (var entry in _database.Entries(BedrockChunkStore.CoordinatePrefix(position.X, position.Z), includeValues: true))
        {
            if (entry.Value is null || !BedrockDbKey.TryParse(entry.Key, out var key) || key.Position != position) continue;
            if (key.RecordType is not (ChunkRecordType.Data3D or ChunkRecordType.Data2D or ChunkRecordType.Data2DLegacy)) continue;
            var current = (entry.Key.ToArray(), key.RecordType, entry.Value.ToArray());
            if (key.RecordType == ChunkRecordType.Data3D) return current;
            if (fallback is null || key.RecordType == ChunkRecordType.Data2D) fallback = current;
        }
        return fallback;
    }

    private static int FloorDiv(int value, int divisor)
    {
        var quotient = value / divisor;
        var remainder = value % divisor;
        return remainder < 0 ? quotient - 1 : quotient;
    }
}
