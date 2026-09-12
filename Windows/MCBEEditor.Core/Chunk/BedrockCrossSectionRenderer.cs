using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public enum BedrockMapAxis
{
    X,
    Y,
    Z
}

public enum BedrockMapRenderMode
{
    Surface,
    Height,
    Minerals,
    Biome,
    TickingAreas,
    Slime
}

public enum BedrockProjectionDirection
{
    PositiveToNegative,
    NegativeToPositive
}

public sealed record BedrockCrossSectionRegion(
    BedrockMapAxis Axis,
    BedrockMapRenderMode Mode,
    int Dimension,
    int FixedX,
    int FixedZ,
    int CenterY,
    int OriginHorizontal,
    int MinimumY,
    int MaximumY,
    int LogicalHorizontalBlocks,
    int LogicalVerticalBlocks,
    int Width,
    int Height,
    int SampleStride,
    uint[] Rgb,
    string[] BlockNames,
    uint[] BiomeIds,
    int[] BlockX,
    int[] BlockY,
    int[] BlockZ,
    bool[] Generated,
    int ProjectionDepth,
    int DecodedSubChunks,
    IReadOnlyList<string> Errors)
{
    public int Index(int pixelX, int pixelY) => pixelY * Width + pixelX;
    public bool ContainsPixel(int pixelX, int pixelY) => (uint)pixelX < (uint)Width && (uint)pixelY < (uint)Height;
    public bool IsDownsampled => SampleStride > 1 || Width != LogicalHorizontalBlocks || Height != LogicalVerticalBlocks;
    public double WorldHorizontalAtPixel(double pixelX) => OriginHorizontal + pixelX / Math.Max(1.0, Width) * LogicalHorizontalBlocks;
    public double WorldYAtPixel(double pixelY) => MaximumY + 1.0 - pixelY / Math.Max(1.0, Height) * LogicalVerticalBlocks;
    public double PixelXForWorld(double horizontal) => (horizontal - OriginHorizontal) / Math.Max(1.0, LogicalHorizontalBlocks) * Width;
    public double PixelYForWorld(double y) => (MaximumY + 1.0 - y) / Math.Max(1.0, LogicalVerticalBlocks) * Height;
    public int FixedCoordinate => Axis == BedrockMapAxis.X ? FixedX : FixedZ;
}

/// <summary>
/// Vertical X/Z orthographic renderer. Surface/height/mineral modes project up
/// to 128/129 blocks; biome/ticking/slime are exact-plane property modes, matching iOS.
/// </summary>
public sealed class BedrockCrossSectionRenderer
{
    private readonly IWorldDatabase _database;
    private readonly Dictionary<ChunkPosition, CachedChunk> _cache = new();
    private readonly List<string> _errors = [];
    private IReadOnlyList<EnvironmentTickingAreaSpec> _tickingAreas = Array.Empty<EnvironmentTickingAreaSpec>();
    private int _decodedSubChunks;

    private sealed record CachedChunk(
        IReadOnlyDictionary<sbyte, BedrockSubChunk> SubChunks,
        BedrockBiomeDocument? BiomeDocument,
        BedrockLegacyTerrain? LegacyTerrain);

    private readonly record struct BlockSample(
        BedrockBlockState? State,
        bool HasSubChunk,
        uint? BiomeId,
        int ChunkX,
        int ChunkZ,
        int X,
        int Y,
        int Z)
    {
        public string Name => State?.Name ?? "minecraft:air";
    }

    public BedrockCrossSectionRenderer(IWorldDatabase database)
    {
        _database = database ?? throw new ArgumentNullException(nameof(database));
    }

    public BedrockCrossSectionRegion Render(
        BedrockMapAxis axis,
        int fixedX,
        int fixedZ,
        int centerY,
        int sideBlocks,
        int dimension,
        BedrockMapRenderMode mode,
        bool drawSubChunkGrid,
        bool drawBuildHeightLimits = true,
        int? projectionDepth = null,
        BedrockProjectionDirection projectionDirection = BedrockProjectionDirection.PositiveToNegative,
        int maximumRasterSide = 2048,
        bool showUngeneratedTexture = false,
        int? projectionMinimumCoordinateOverride = null,
        int? projectionMaximumCoordinateOverride = null)
    {
        if (axis != BedrockMapAxis.X && axis != BedrockMapAxis.Z)
            throw new ArgumentException("Y axis uses the top-down surface renderer", nameof(axis));
        if (sideBlocks < 16 || sideBlocks > 1_048_576)
            throw new ArgumentOutOfRangeException(nameof(sideBlocks), "Cross-section side must be 16..1048576 blocks");
        maximumRasterSide = Math.Clamp(maximumRasterSide, 256, 8192);

        _cache.Clear();
        _errors.Clear();
        _decodedSubChunks = 0;
        _tickingAreas = Array.Empty<EnvironmentTickingAreaSpec>();
        if (mode == BedrockMapRenderMode.TickingAreas)
        {
            var scan = BedrockTickingAreaMap.Read(_database);
            _tickingAreas = scan.Areas.Where(area => area.Dimension == dimension).ToArray();
            _errors.AddRange(scan.Diagnostics.Select(message => "常加载区块: " + message));
        }

        var half = sideBlocks / 2;
        var originHorizontal64 = (long)(axis == BedrockMapAxis.X ? fixedZ : fixedX) - half;
        var minimumY64 = (long)centerY - half;
        var maximumY64 = minimumY64 + sideBlocks - 1L;
        if (originHorizontal64 < int.MinValue || originHorizontal64 > int.MaxValue
            || originHorizontal64 + sideBlocks - 1L > int.MaxValue
            || minimumY64 < int.MinValue || maximumY64 > int.MaxValue)
            throw new ArgumentOutOfRangeException(nameof(sideBlocks), "剖面范围超出 Windows 当前 32 位坐标表示范围");
        var originHorizontal = (int)originHorizontal64;
        var minimumY = (int)minimumY64;
        var maximumY = (int)maximumY64;
        var rayDepth = projectionDepth ?? (mode == BedrockMapRenderMode.Minerals ? 129 : 128);
        rayDepth = Math.Clamp(rayDepth, 1, 4096);

        // Match iOS projection semantics exactly. With the ungenerated-SubChunk
        // layer enabled, X/Z views only project through the 16-block chunk that
        // contains the selected section plane. With it disabled, the normal
        // view projects 128 blocks (129 for the mineral default) away from the
        // current plane in the selected direction.
        var planeCoordinate = axis == BedrockMapAxis.X ? fixedX : fixedZ;
        int projectionMinimumCoordinate;
        int projectionMaximumCoordinate;
        if (projectionMinimumCoordinateOverride.HasValue || projectionMaximumCoordinateOverride.HasValue)
        {
            if (!projectionMinimumCoordinateOverride.HasValue || !projectionMaximumCoordinateOverride.HasValue)
                throw new ArgumentException("投影范围覆盖必须同时提供最小与最大坐标");
            projectionMinimumCoordinate = projectionMinimumCoordinateOverride.Value;
            projectionMaximumCoordinate = projectionMaximumCoordinateOverride.Value;
            if (projectionMinimumCoordinate > projectionMaximumCoordinate)
                throw new ArgumentOutOfRangeException(nameof(projectionMinimumCoordinateOverride), "投影最小坐标不能大于最大坐标");
            rayDepth = checked(projectionMaximumCoordinate - projectionMinimumCoordinate + 1);
            if (rayDepth > 4096)
                throw new ArgumentOutOfRangeException(nameof(projectionMaximumCoordinateOverride), "单次剖面投影深度最多为 4096 方块");
        }
        else if (showUngeneratedTexture)
        {
            var chunkOrigin = checked(BedrockSurfaceRegionRenderer.FloorDiv(planeCoordinate, 16) * 16);
            projectionMinimumCoordinate = chunkOrigin;
            projectionMaximumCoordinate = checked(chunkOrigin + 15);
        }
        else if (projectionDirection == BedrockProjectionDirection.PositiveToNegative)
        {
            projectionMaximumCoordinate = planeCoordinate;
            projectionMinimumCoordinate = ClampLongToInt((long)planeCoordinate - rayDepth + 1L);
        }
        else
        {
            projectionMinimumCoordinate = planeCoordinate;
            projectionMaximumCoordinate = ClampLongToInt((long)planeCoordinate + rayDepth - 1L);
        }

        var minimumStride = Math.Max(1, (int)Math.Ceiling(sideBlocks / (double)maximumRasterSide));
        var sampleStride = 1;
        while (sampleStride < minimumStride && sampleStride <= int.MaxValue / 2) sampleStride *= 2;
        var rasterColumns = (int)Math.Ceiling(sideBlocks / (double)sampleStride);
        var rasterRows = rasterColumns;
        var pixels = checked(rasterColumns * rasterRows);
        var initial = mode switch
        {
            BedrockMapRenderMode.Minerals => BedrockBlockMapColorCatalog.MineralBackgroundRgb,
            BedrockMapRenderMode.TickingAreas or BedrockMapRenderMode.Slime => 0x3D3D3Du,
            _ => BedrockBlockMapColorCatalog.AirRgb
        };
        var rgb = Enumerable.Repeat(initial, pixels).ToArray();
        var names = Enumerable.Repeat("minecraft:air", pixels).ToArray();
        var biomeIds = Enumerable.Repeat(uint.MaxValue, pixels).ToArray();
        var blockX = new int[pixels];
        var blockY = new int[pixels];
        var blockZ = new int[pixels];
        var generated = new bool[pixels];
        var propertyMode = mode is BedrockMapRenderMode.Biome or BedrockMapRenderMode.TickingAreas or BedrockMapRenderMode.Slime;

        for (var row = 0; row < rasterRows; row++)
        {
            var y = maximumY - Math.Min(sideBlocks - 1, row * sampleStride);
            for (var column = 0; column < rasterColumns; column++)
            {
                var horizontal = originHorizontal + Math.Min(sideBlocks - 1, column * sampleStride);
                var index = row * rasterColumns + column;
                var planeX = axis == BedrockMapAxis.X ? fixedX : horizontal;
                var planeZ = axis == BedrockMapAxis.Z ? fixedZ : horizontal;
                blockX[index] = planeX;
                blockY[index] = y;
                blockZ[index] = planeZ;

                var plane = SampleAt(planeX, planeZ, y, dimension);
                if (propertyMode)
                {
                    biomeIds[index] = plane.BiomeId ?? uint.MaxValue;
                    names[index] = mode switch
                    {
                        BedrockMapRenderMode.TickingAreas => IsTicking(plane.ChunkX, plane.ChunkZ) ? "mcbeeditor:ticking_chunk" : "mcbeeditor:non_ticking_chunk",
                        BedrockMapRenderMode.Slime => BedrockSlimeChunk.IsSlimeChunk(plane.ChunkX, plane.ChunkZ) ? "mcbeeditor:slime_chunk" : "mcbeeditor:non_slime_chunk",
                        _ => plane.Name
                    };
                    generated[index] = mode is BedrockMapRenderMode.TickingAreas or BedrockMapRenderMode.Slime || plane.HasSubChunk || plane.BiomeId.HasValue;
                    rgb[index] = mode switch
                    {
                        BedrockMapRenderMode.Biome => BedrockBiomeCatalog.ColorForId(plane.BiomeId ?? uint.MaxValue),
                        BedrockMapRenderMode.TickingAreas => IsTicking(plane.ChunkX, plane.ChunkZ) ? 0x42B347u : 0x3D3D3Du,
                        BedrockMapRenderMode.Slime => BedrockSlimeChunk.IsSlimeChunk(plane.ChunkX, plane.ChunkZ) ? 0x40B840u : 0x3D3D3Du,
                        _ => BedrockBlockMapColorCatalog.AirRgb
                    };
                    continue;
                }

                // When the ungenerated-SubChunk layer is visible, a missing section on the
                // selected X/Z plane is itself the thing being visualized, so stop at that
                // plane and draw the aligned ungenerated texture. When the layer is hidden,
                // keep scanning the full projection depth: an ungenerated front section must
                // not hide generated terrain farther along the negative projection direction.
                if (!plane.HasSubChunk && showUngeneratedTexture)
                {
                    var localHorizontal = horizontal - BedrockSurfaceRegionRenderer.FloorDiv(horizontal, 16) * 16;
                    var localY = y - BedrockSurfaceRegionRenderer.FloorDiv(y, 16) * 16;
                    var screenLocalY = 15 - localY;
                    var difference = screenLocalY - localHorizontal;
                    rgb[index] = difference is -8 or 0 or 8
                        ? BedrockBlockMapColorCatalog.UngeneratedLineRgb
                        : BedrockBlockMapColorCatalog.AirRgb;
                    continue;
                }

                generated[index] = plane.HasSubChunk;
                BlockSample? hit = null;
                if (mode == BedrockMapRenderMode.Minerals)
                {
                    if (projectionDirection == BedrockProjectionDirection.PositiveToNegative)
                    {
                        for (var coordinate = projectionMaximumCoordinate; coordinate >= projectionMinimumCoordinate; coordinate--)
                        {
                            var x = axis == BedrockMapAxis.X ? coordinate : horizontal;
                            var z = axis == BedrockMapAxis.Z ? coordinate : horizontal;
                            var sample = SampleAt(x, z, y, dimension);
                            if (sample.HasSubChunk && BedrockBlockMapColorCatalog.IsHighlightedOre(sample.Name))
                            {
                                hit = sample;
                                break;
                            }
                            if (coordinate == int.MinValue) break;
                        }
                    }
                    else
                    {
                        for (var coordinate = projectionMinimumCoordinate; coordinate <= projectionMaximumCoordinate; coordinate++)
                        {
                            var x = axis == BedrockMapAxis.X ? coordinate : horizontal;
                            var z = axis == BedrockMapAxis.Z ? coordinate : horizontal;
                            var sample = SampleAt(x, z, y, dimension);
                            if (sample.HasSubChunk && BedrockBlockMapColorCatalog.IsHighlightedOre(sample.Name))
                            {
                                hit = sample;
                                break;
                            }
                            if (coordinate == int.MaxValue) break;
                        }
                    }
                }
                else
                {
                    if (projectionDirection == BedrockProjectionDirection.PositiveToNegative)
                    {
                        for (var coordinate = projectionMaximumCoordinate; coordinate >= projectionMinimumCoordinate; coordinate--)
                        {
                            var x = axis == BedrockMapAxis.X ? coordinate : horizontal;
                            var z = axis == BedrockMapAxis.Z ? coordinate : horizontal;
                            var sample = SampleAt(x, z, y, dimension);
                            if (sample.HasSubChunk && !BedrockBlockMapColorCatalog.IsAir(sample.Name))
                            {
                                hit = sample;
                                break;
                            }
                            if (coordinate == int.MinValue) break;
                        }
                    }
                    else
                    {
                        for (var coordinate = projectionMinimumCoordinate; coordinate <= projectionMaximumCoordinate; coordinate++)
                        {
                            var x = axis == BedrockMapAxis.X ? coordinate : horizontal;
                            var z = axis == BedrockMapAxis.Z ? coordinate : horizontal;
                            var sample = SampleAt(x, z, y, dimension);
                            if (sample.HasSubChunk && !BedrockBlockMapColorCatalog.IsAir(sample.Name))
                            {
                                hit = sample;
                                break;
                            }
                            if (coordinate == int.MaxValue) break;
                        }
                    }
                }

                if (hit is { } selected)
                {
                    generated[index] = selected.HasSubChunk;
                    names[index] = selected.Name;
                    blockX[index] = selected.X;
                    blockY[index] = selected.Y;
                    blockZ[index] = selected.Z;
                    rgb[index] = mode switch
                    {
                        BedrockMapRenderMode.Minerals => BedrockBlockMapColorCatalog.OreColor(selected.Name),
                        BedrockMapRenderMode.Height => BedrockSurfaceRenderer.HeightColor(selected.Name, y),
                        _ => BedrockBlockMapColorCatalog.ColorFor(selected.State)
                    };
                }
                else if (mode is BedrockMapRenderMode.Surface or BedrockMapRenderMode.Height)
                {
                    names[index] = "minecraft:air";
                    rgb[index] = BedrockBlockMapColorCatalog.AirRgb;
                }
            }
        }

        if (drawSubChunkGrid)
            DrawSubChunkGrid(rgb, rasterColumns, rasterRows, originHorizontal, maximumY, sideBlocks, sampleStride);
        if (drawBuildHeightLimits)
            DrawBuildHeightLimits(rgb, rasterColumns, rasterRows, originHorizontal, minimumY, maximumY, sideBlocks, dimension);

        return new BedrockCrossSectionRegion(
            axis, mode, dimension, fixedX, fixedZ, centerY,
            originHorizontal, minimumY, maximumY, sideBlocks, sideBlocks,
            rasterColumns, rasterRows, sampleStride,
            rgb, names, biomeIds, blockX, blockY, blockZ, generated,
            rayDepth, _decodedSubChunks, _errors.ToArray());
    }

    private static int ClampLongToInt(long value)
        => value < int.MinValue ? int.MinValue : value > int.MaxValue ? int.MaxValue : (int)value;

    private bool IsTicking(int chunkX, int chunkZ)
        => _tickingAreas.Any(area => BedrockTickingAreaMap.ContainsChunk(area, chunkX, chunkZ));

    private BlockSample SampleAt(int worldX, int worldZ, int y, int dimension)
    {
        var chunkX = BedrockSurfaceRegionRenderer.FloorDiv(worldX, 16);
        var chunkZ = BedrockSurfaceRegionRenderer.FloorDiv(worldZ, 16);
        var subY = BedrockSurfaceRegionRenderer.FloorDiv(y, 16);
        var position = new ChunkPosition(chunkX, chunkZ, dimension);
        var cached = LoadChunk(position);
        var localX = worldX - chunkX * 16;
        var localZ = worldZ - chunkZ * 16;
        var biomeId = cached.BiomeDocument?.BiomeId(localX, y, localZ) ?? cached.LegacyTerrain?.BiomeId(localX, localZ);
        if (subY < sbyte.MinValue || subY > sbyte.MaxValue)
            return new BlockSample(null, false, biomeId, chunkX, chunkZ, worldX, y, worldZ);
        if (!cached.SubChunks.TryGetValue((sbyte)subY, out var subChunk))
            return new BlockSample(null, false, biomeId, chunkX, chunkZ, worldX, y, worldZ);

        var localY = y - subY * 16;
        BedrockBlockState? first = null;
        foreach (var storage in subChunk.Storages)
        {
            var state = storage.BlockState(localX, localY, localZ);
            first ??= state;
            if (state is not null && !state.IsAir)
                return new BlockSample(state, true, biomeId, chunkX, chunkZ, worldX, y, worldZ);
        }
        return new BlockSample(first, true, biomeId, chunkX, chunkZ, worldX, y, worldZ);
    }

    private CachedChunk LoadChunk(ChunkPosition position)
    {
        if (_cache.TryGetValue(position, out var cached)) return cached;
        var byY = new Dictionary<sbyte, BedrockSubChunk>();
        BedrockBiomeDocument? biomeDocument = null;
        BedrockLegacyTerrain? legacyTerrain = null;
        var biomePriority = -1;
        foreach (var entry in _database.Entries(BedrockChunkStore.CoordinatePrefix(position.X, position.Z), includeValues: true))
        {
            if (entry.Value is null || !BedrockDbKey.TryParse(entry.Key, out var key) || key.Position != position) continue;
            try
            {
                if (key.RecordType == ChunkRecordType.SubChunk && key.SubChunkIndex is sbyte keyY)
                {
                    var subChunk = BedrockSubChunk.Decode(entry.Value, keyY);
                    if (subChunk.YIndex is sbyte logicalY)
                        byY[logicalY] = subChunk;
                    _decodedSubChunks++;
                }
                else if (key.RecordType == ChunkRecordType.LegacyTerrain)
                {
                    legacyTerrain = BedrockLegacyTerrain.Decode(entry.Value);
                    for (sbyte y = 0; y < 8; y++) byY[y] = legacyTerrain.SubChunk(y);
                    _decodedSubChunks += 8;
                }
                else if (key.RecordType is ChunkRecordType.Data3D or ChunkRecordType.Data2D or ChunkRecordType.Data2DLegacy)
                {
                    var priority = key.RecordType switch
                    {
                        ChunkRecordType.Data3D => 3,
                        ChunkRecordType.Data2D => 2,
                        _ => 1
                    };
                    if (priority > biomePriority)
                    {
                        biomeDocument = BedrockBiomeDocument.Decode(key.RecordType, entry.Value);
                        biomePriority = priority;
                    }
                }
            }
            catch (Exception ex)
            {
                _errors.Add($"{position} {key.RecordType.DisplayName()}: {ex.Message}");
            }
        }
        cached = new CachedChunk(byY, biomeDocument, legacyTerrain);
        _cache[position] = cached;
        return cached;
    }

    private static void DrawSubChunkGrid(
        uint[] rgb, int width, int height, int originHorizontal, int maximumY, int logicalSide, int sampleStride)
    {
        const uint grid = 0x666666;
        double PixelX(double worldBoundary) => (worldBoundary - originHorizontal) / logicalSide * width;
        double PixelY(double worldBoundary) => (maximumY + 1.0 - worldBoundary) / logicalSide * height;

        var endHorizontal = (long)originHorizontal + logicalSide;
        var boundary = (long)BedrockSurfaceRegionRenderer.FloorDiv(originHorizontal, 16) * 16;
        if (boundary < originHorizontal) boundary += 16;
        for (; boundary <= endHorizontal; boundary += 16)
        {
            var x = (int)Math.Round(PixelX(boundary));
            if (x <= 0 || x >= width) continue;
            for (var row = 0; row < height; row++) rgb[row * width + x] = grid;
        }

        var minimumY = maximumY - logicalSide + 1L;
        var yBoundary = (long)BedrockSurfaceRegionRenderer.FloorDiv((int)Math.Max(int.MinValue, Math.Min(int.MaxValue, minimumY)), 16) * 16;
        if (yBoundary < minimumY) yBoundary += 16;
        for (; yBoundary <= (long)maximumY + 1; yBoundary += 16)
        {
            var y = (int)Math.Round(PixelY(yBoundary));
            if (y <= 0 || y >= height) continue;
            for (var column = 0; column < width; column++) rgb[y * width + column] = grid;
        }
    }

    private static void DrawBuildHeightLimits(
        uint[] rgb, int width, int height, int originHorizontal, int minimumY, int maximumY, int logicalSide, int dimension)
    {
        var (minimum, maximumExclusive) = dimension switch
        {
            1 => (0, 128),
            2 => (0, 256),
            _ => (-64, 320)
        };
        DrawLimit(rgb, width, height, originHorizontal, minimumY, maximumY, logicalSide, minimum);
        DrawLimit(rgb, width, height, originHorizontal, minimumY, maximumY, logicalSide, maximumExclusive);
    }

    private static void DrawLimit(
        uint[] rgb, int width, int height, int originHorizontal, int minimumY, int maximumY, int logicalSide, int boundaryY)
    {
        if (boundaryY < minimumY || boundaryY > maximumY + 1) return;
        var row = (int)Math.Round((maximumY + 1.0 - boundaryY) / logicalSide * height);
        row = Math.Clamp(row, 0, height - 1);
        const uint red = 0xE53935;
        for (var x = 0; x < width; x++)
        {
            var worldHorizontal = originHorizontal + (long)Math.Floor((x + 0.5) / width * logicalSide);
            if ((BedrockSurfaceRegionRenderer.FloorDiv((int)Math.Clamp(worldHorizontal, int.MinValue, int.MaxValue), 4) & 1) == 0)
                rgb[row * width + x] = red;
        }
    }

    private static int Mod(int value, int divisor)
    {
        var result = value % divisor;
        return result < 0 ? result + divisor : result;
    }
}
