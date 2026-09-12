using System.Buffers.Binary;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockSurfaceChunk(
    ChunkPosition Position,
    bool Generated,
    string[] BlockNames,
    int[] Heights,
    uint[] BiomeIds,
    uint[] Rgb,
    int DecodedSubChunks,
    string? Error)
{
    public const int Side = 16;
    public int Index(int localX, int localZ) => localZ * Side + localX;
}

public sealed record BedrockSurfaceRegion(
    BedrockMapRenderMode Mode,
    int Dimension,
    int CenterBlockX,
    int CenterBlockZ,
    int OriginBlockX,
    int OriginBlockZ,
    int LogicalWidthBlocks,
    int LogicalHeightBlocks,
    int Width,
    int Height,
    int SampleStrideChunks,
    int SampledChunkCount,
    uint[] Rgb,
    string[] BlockNames,
    int[] BlockHeights,
    uint[] BiomeIds,
    bool[] Generated,
    int GeneratedChunkCount,
    int MissingChunkCount,
    int TickingAreaCount,
    int TickingDefinedChunkCount,
    int VisibleTickingChunkCount,
    IReadOnlyList<string> Errors)
{
    public int Index(int pixelX, int pixelZ) => pixelZ * Width + pixelX;
    public bool ContainsPixel(int pixelX, int pixelZ) => (uint)pixelX < (uint)Width && (uint)pixelZ < (uint)Height;
    public bool IsDownsampled => SampleStrideChunks > 1 || Width != LogicalWidthBlocks || Height != LogicalHeightBlocks;
    public double WorldXAtPixel(double pixelX) => OriginBlockX + pixelX / Math.Max(1.0, Width) * LogicalWidthBlocks;
    public double WorldZAtPixel(double pixelZ) => OriginBlockZ + pixelZ / Math.Max(1.0, Height) * LogicalHeightBlocks;
    public double PixelXForWorld(double worldX) => (worldX - OriginBlockX) / Math.Max(1.0, LogicalWidthBlocks) * Width;
    public double PixelZForWorld(double worldZ) => (worldZ - OriginBlockZ) / Math.Max(1.0, LogicalHeightBlocks) * Height;
    public bool ContainsWorld(double worldX, double worldZ)
        => worldX >= OriginBlockX && worldX < (double)OriginBlockX + LogicalWidthBlocks
            && worldZ >= OriginBlockZ && worldZ < (double)OriginBlockZ + LogicalHeightBlocks;
}

/// <summary>
/// Decodes the visible top block in each X/Z column. Multiple modern storage
/// layers are treated like the iOS renderer: the first non-air state wins.
/// Height and biome modes reuse the same visible-column metadata.
/// </summary>
public sealed class BedrockSurfaceRenderer
{
    private readonly IWorldDatabase _database;

    public BedrockSurfaceRenderer(IWorldDatabase database)
    {
        _database = database ?? throw new ArgumentNullException(nameof(database));
    }

    public BedrockSurfaceChunk RenderChunk(
        ChunkPosition position,
        BedrockMapRenderMode mode = BedrockMapRenderMode.Surface,
        BedrockProjectionDirection verticalDirection = BedrockProjectionDirection.PositiveToNegative)
    {
        if (mode == BedrockMapRenderMode.Slime)
            return RenderSlimeChunk(position);
        if (mode == BedrockMapRenderMode.TickingAreas)
        {
            var names = Enumerable.Repeat("mcbeeditor:non_ticking_chunk", 256).ToArray();
            var heights = new int[256];
            var biomeIds = Enumerable.Repeat(uint.MaxValue, 256).ToArray();
            var rgb = Enumerable.Repeat(0x333333u, 256).ToArray();
            return new BedrockSurfaceChunk(position, true, names, heights, biomeIds, rgb, 0, null);
        }

        var namesSurface = Enumerable.Repeat("minecraft:air", 256).ToArray();
        var heightsSurface = Enumerable.Repeat(int.MinValue, 256).ToArray();
        var biomeIdsSurface = Enumerable.Repeat(uint.MaxValue, 256).ToArray();
        var background = mode == BedrockMapRenderMode.Minerals
            ? BedrockBlockMapColorCatalog.MineralBackgroundRgb
            : BedrockBlockMapColorCatalog.AirRgb;
        var rgbSurface = Enumerable.Repeat(background, 256).ToArray();
        var subChunks = new List<BedrockSubChunk>();
        var errors = new List<string>();
        var finalizedGenerated = false;
        var hasTerrainRecord = false;
        var hasBiomeRecord = false;
        BedrockBiomeDocument? biomeDocument = null;
        var biomePriority = -1;
        BedrockLegacyTerrain? legacyTerrain = null;

        foreach (var entry in _database.Entries(BedrockChunkStore.CoordinatePrefix(position.X, position.Z), includeValues: true))
        {
            if (entry.Value is null || !BedrockDbKey.TryParse(entry.Key, out var key) || key.Position != position) continue;
            try
            {
                if (key.RecordType == ChunkRecordType.SubChunk && key.SubChunkIndex is sbyte keyY)
                {
                    hasTerrainRecord = true;
                    subChunks.Add(BedrockSubChunk.Decode(entry.Value, keyY));
                }
                else if (key.RecordType == ChunkRecordType.LegacyTerrain)
                {
                    hasTerrainRecord = true;
                    legacyTerrain = BedrockLegacyTerrain.Decode(entry.Value);
                    for (sbyte y = 0; y < 8; y++) subChunks.Add(legacyTerrain.SubChunk(y));
                }
                else if (key.RecordType == ChunkRecordType.FinalizedState && entry.Value.Length >= 4)
                {
                    finalizedGenerated = BinaryPrimitives.ReadInt32LittleEndian(entry.Value.AsSpan(0, 4)) == 2;
                }
                else if (mode == BedrockMapRenderMode.Biome
                    && (key.RecordType == ChunkRecordType.Data3D
                        || key.RecordType == ChunkRecordType.Data2D
                        || key.RecordType == ChunkRecordType.Data2DLegacy))
                {
                    hasBiomeRecord = true;
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
                errors.Add($"{key.RecordType.DisplayName()}: {ex.Message}");
            }
        }

        var generated = hasTerrainRecord || finalizedGenerated || (mode == BedrockMapRenderMode.Biome && hasBiomeRecord);
        if (!generated)
            return new BedrockSurfaceChunk(position, false, namesSurface, heightsSurface, biomeIdsSurface, rgbSurface, 0,
                errors.Count == 0 ? null : string.Join("; ", errors));

        var candidates = subChunks.Where(item => item.YIndex.HasValue && item.Storages.Count > 0);
        var ordered = (verticalDirection == BedrockProjectionDirection.PositiveToNegative
                ? candidates.OrderByDescending(item => item.YIndex!.Value)
                : candidates.OrderBy(item => item.YIndex!.Value))
            .ToArray();
        var visible = new BedrockBlockState?[256];
        var unresolved = 256;

        foreach (var subChunk in ordered)
        {
            if (unresolved == 0) break;
            var baseY = subChunk.YIndex!.Value * 16;
            for (var localX = 0; localX < 16; localX++)
            {
                for (var localZ = 0; localZ < 16; localZ++)
                {
                    var column = localZ * 16 + localX;
                    if (visible[column] is not null) continue;
                    var startY = verticalDirection == BedrockProjectionDirection.PositiveToNegative ? 15 : 0;
                    var endY = verticalDirection == BedrockProjectionDirection.PositiveToNegative ? -1 : 16;
                    var stepY = verticalDirection == BedrockProjectionDirection.PositiveToNegative ? -1 : 1;
                    for (var localY = startY; localY != endY; localY += stepY)
                    {
                        var state = PreferredState(subChunk, localX, localY, localZ);
                        if (state is null) continue;
                        if (mode == BedrockMapRenderMode.Minerals && !BedrockBlockMapColorCatalog.IsHighlightedOre(state.Name))
                            continue;
                        visible[column] = state;
                        namesSurface[column] = state.Name;
                        heightsSurface[column] = baseY + localY;
                        unresolved--;
                        break;
                    }
                }
            }
        }

        for (var localZ = 0; localZ < 16; localZ++)
        for (var localX = 0; localX < 16; localX++)
        {
            var index = localZ * 16 + localX;
            var state = visible[index];
            switch (mode)
            {
                case BedrockMapRenderMode.Surface:
                    rgbSurface[index] = state is null ? BedrockBlockMapColorCatalog.AirRgb : BedrockBlockMapColorCatalog.ColorFor(state);
                    break;
                case BedrockMapRenderMode.Height:
                    rgbSurface[index] = HeightColor(namesSurface[index], heightsSurface[index]);
                    break;
                case BedrockMapRenderMode.Minerals:
                    rgbSurface[index] = state is null ? BedrockBlockMapColorCatalog.MineralBackgroundRgb : BedrockBlockMapColorCatalog.OreColor(state.Name);
                    break;
                case BedrockMapRenderMode.Biome:
                {
                    var surfaceY = heightsSurface[index] == int.MinValue ? 64 : heightsSurface[index];
                    var biome = biomeDocument?.BiomeId(localX, surfaceY, localZ) ?? legacyTerrain?.BiomeId(localX, localZ);
                    biomeIdsSurface[index] = biome ?? uint.MaxValue;
                    rgbSurface[index] = BedrockBiomeCatalog.ColorForId(biomeIdsSurface[index]);
                    break;
                }
            }
        }

        return new BedrockSurfaceChunk(
            position, true, namesSurface, heightsSurface, biomeIdsSurface, rgbSurface, ordered.Length,
            errors.Count == 0 ? null : string.Join("; ", errors));
    }

    internal static uint HeightColor(string blockName, int height)
    {
        if (height == int.MinValue) return BedrockBlockMapColorCatalog.AirRgb;
        var normalized = Math.Clamp((height + 64.0) / 384.0, 0.0, 1.0);
        if (BedrockBlockMapColorCatalog.IsWater(blockName))
            return Rgb(0.08 + normalized * 0.12, 0.25 + normalized * 0.25, 0.55 + normalized * 0.35);
        var value = 0.12 + normalized * 0.82;
        return Rgb(value, value, value);
    }

    private static BedrockSurfaceChunk RenderSlimeChunk(ChunkPosition position)
    {
        var isSlime = BedrockSlimeChunk.IsSlimeChunk(position.X, position.Z);
        var name = isSlime ? "mcbeeditor:slime_chunk" : "mcbeeditor:non_slime_chunk";
        var names = Enumerable.Repeat(name, 256).ToArray();
        var heights = new int[256];
        var biomeIds = Enumerable.Repeat(uint.MaxValue, 256).ToArray();
        var baseColor = isSlime ? 0x40B840u : 0x3D3D3Du;
        var accent = isSlime ? 0x7AE666u : 0x4A4A4Au;
        var rgb = Enumerable.Repeat(baseColor, 256).ToArray();
        for (var z = 1; z < 16; z += 4)
        for (var x = 1; x < 16; x += 4)
        for (var dz = 0; dz < 2; dz++)
        for (var dx = 0; dx < 2; dx++)
            rgb[(z + dz) * 16 + x + dx] = accent;
        return new BedrockSurfaceChunk(position, true, names, heights, biomeIds, rgb, 0, null);
    }

    private static uint Rgb(double red, double green, double blue)
    {
        static byte Channel(double value) => (byte)Math.Clamp((int)Math.Round(value * 255.0, MidpointRounding.AwayFromZero), 0, 255);
        return (uint)(Channel(red) << 16 | Channel(green) << 8 | Channel(blue));
    }

    private static BedrockBlockState? PreferredState(BedrockSubChunk subChunk, int x, int y, int z)
    {
        foreach (var storage in subChunk.Storages)
        {
            var state = storage.BlockState(x, y, z);
            if (state is not null && !state.IsAir) return state;
        }
        return null;
    }
}

public sealed class BedrockSurfaceRegionRenderer
{
    private readonly IWorldDatabase _database;

    public BedrockSurfaceRegionRenderer(IWorldDatabase database)
    {
        _database = database ?? throw new ArgumentNullException(nameof(database));
    }

    public BedrockSurfaceRegion Render(
        int dimension,
        int centerBlockX,
        int centerBlockZ,
        int chunkRadius,
        bool drawChunkGrid,
        BedrockMapRenderMode mode = BedrockMapRenderMode.Surface,
        BedrockProjectionDirection verticalDirection = BedrockProjectionDirection.PositiveToNegative,
        int maximumSamplesPerAxis = 64,
        int maximumRasterSide = 2048,
        bool showUngeneratedTexture = false)
    {
        if (chunkRadius < 1) throw new ArgumentOutOfRangeException(nameof(chunkRadius), "区块半径必须至少为 1");
        if (chunkRadius > 32767) throw new ArgumentOutOfRangeException(nameof(chunkRadius), "动态地图单轴最多表示 65535 个区块");
        maximumSamplesPerAxis = Math.Clamp(maximumSamplesPerAxis, 1, 512);
        maximumRasterSide = Math.Clamp(maximumRasterSide, 256, 8192);

        var centerChunkX = FloorDiv(centerBlockX, 16);
        var centerChunkZ = FloorDiv(centerBlockZ, 16);
        var sideChunks = checked(chunkRadius * 2 + 1);
        var leftChunks = chunkRadius;
        var plan = MapRenderSamplingPlan.Create(sideChunks, leftChunks, maximumSamplesPerAxis);
        var minChunkX64 = (long)centerChunkX - leftChunks;
        var minChunkZ64 = (long)centerChunkZ - leftChunks;
        if (minChunkX64 < int.MinValue || minChunkZ64 < int.MinValue
            || minChunkX64 + sideChunks - 1 > int.MaxValue || minChunkZ64 + sideChunks - 1 > int.MaxValue)
            throw new ArgumentOutOfRangeException(nameof(chunkRadius), "地图范围超出基岩版 Int32 区块坐标范围");
        var minChunkX = (int)minChunkX64;
        var minChunkZ = (int)minChunkZ64;
        var logicalSide64 = (long)sideChunks * 16;
        if (logicalSide64 > int.MaxValue) throw new ArgumentOutOfRangeException(nameof(chunkRadius), "地图方块范围过大");
        var logicalSide = (int)logicalSide64;
        var originX64 = minChunkX64 * 16;
        var originZ64 = minChunkZ64 * 16;
        if (originX64 < int.MinValue || originX64 > int.MaxValue || originZ64 < int.MinValue || originZ64 > int.MaxValue)
            throw new ArgumentOutOfRangeException(nameof(chunkRadius), "地图方块原点超出 Windows 当前 32 位坐标表示范围");
        var originX = (int)originX64;
        var originZ = (int)originZ64;

        var rasterSide = Math.Min(logicalSide, maximumRasterSide);
        var pixels = checked(rasterSide * rasterSide);
        var initial = mode == BedrockMapRenderMode.Minerals ? BedrockBlockMapColorCatalog.MineralBackgroundRgb : BedrockBlockMapColorCatalog.AirRgb;
        var rgb = Enumerable.Repeat(initial, pixels).ToArray();
        // Per-block metadata is only retained for an exact 1:1 raster. Large
        // sampled maps resolve click details from the exact target chunk.
        var keepsMetadata = plan.Stride == 1 && rasterSide == logicalSide;
        var names = keepsMetadata ? Enumerable.Repeat("minecraft:air", pixels).ToArray() : Array.Empty<string>();
        var heights = keepsMetadata ? Enumerable.Repeat(int.MinValue, pixels).ToArray() : Array.Empty<int>();
        var biomeIds = keepsMetadata ? Enumerable.Repeat(uint.MaxValue, pixels).ToArray() : Array.Empty<uint>();
        var generated = keepsMetadata ? new bool[pixels] : Array.Empty<bool>();
        var errors = new List<string>();
        var generatedChunks = 0;
        var missingChunks = 0;
        var tickingAreaCount = 0;
        var tickingDefinedChunkCount = 0;
        var visibleTickingChunks = 0;
        IReadOnlyList<EnvironmentTickingAreaSpec> tickingAreas = Array.Empty<EnvironmentTickingAreaSpec>();

        if (mode == BedrockMapRenderMode.TickingAreas)
        {
            var scan = BedrockTickingAreaMap.Read(_database);
            tickingAreas = scan.Areas.Where(area => area.Dimension == dimension).ToArray();
            errors.AddRange(scan.Diagnostics.Select(message => "常加载区块: " + message));
            tickingAreaCount = tickingAreas.Count;
            long defined = 0;
            foreach (var area in tickingAreas) defined = Math.Min(int.MaxValue, defined + Math.Max(0, area.ChunkCount));
            tickingDefinedChunkCount = (int)defined;
        }

        var renderer = new BedrockSurfaceRenderer(_database);
        foreach (var zSample in plan.ZAxis)
        {
            foreach (var xSample in plan.XAxis)
            {
                if (!MapRenderSamplingPlan.TryChunkCoordinate(centerChunkX, xSample.RepresentativeOffset, out var chunkX)
                    || !MapRenderSamplingPlan.TryChunkCoordinate(centerChunkZ, zSample.RepresentativeOffset, out var chunkZ))
                {
                    errors.Add("采样点超出基岩版 Int32 区块坐标范围，已跳过。");
                    continue;
                }

                BedrockSurfaceChunk chunk;
                if (mode == BedrockMapRenderMode.TickingAreas)
                {
                    var tileMinX = centerChunkX + xSample.StartOffset;
                    var tileMaxX = centerChunkX + xSample.EndOffset;
                    var tileMinZ = centerChunkZ + zSample.StartOffset;
                    var tileMaxZ = centerChunkZ + zSample.EndOffset;
                    var matches = tickingAreas.Where(area => TickingAreaIntersects(area, tileMinX, tileMinZ, tileMaxX, tileMaxZ)).ToArray();
                    if (matches.Length > 0)
                    {
                        var tileChunks = (long)(xSample.Span) * zSample.Span;
                        visibleTickingChunks = (int)Math.Min(int.MaxValue, (long)visibleTickingChunks + tileChunks);
                    }
                    chunk = RenderTickingChunk(new ChunkPosition(chunkX, chunkZ, dimension), matches);
                }
                else
                {
                    chunk = renderer.RenderChunk(new ChunkPosition(chunkX, chunkZ, dimension), mode, verticalDirection);
                }

                if (chunk.Generated) generatedChunks++; else missingChunks++;
                if (!string.IsNullOrWhiteSpace(chunk.Error)) errors.Add($"{chunk.Position}: {chunk.Error}");

                var logicalStartX = (xSample.StartOffset + leftChunks) * 16;
                var logicalEndX = (xSample.EndOffset + leftChunks + 1) * 16;
                var logicalStartZ = (zSample.StartOffset + leftChunks) * 16;
                var logicalEndZ = (zSample.EndOffset + leftChunks + 1) * 16;
                var targetX0 = Math.Clamp((int)Math.Floor(logicalStartX * (double)rasterSide / logicalSide), 0, rasterSide);
                var targetX1 = Math.Clamp((int)Math.Ceiling(logicalEndX * (double)rasterSide / logicalSide), 0, rasterSide);
                var targetZ0 = Math.Clamp((int)Math.Floor(logicalStartZ * (double)rasterSide / logicalSide), 0, rasterSide);
                var targetZ1 = Math.Clamp((int)Math.Ceiling(logicalEndZ * (double)rasterSide / logicalSide), 0, rasterSide);
                if (targetX1 <= targetX0 || targetZ1 <= targetZ0) continue;

                for (var rz = targetZ0; rz < targetZ1; rz++)
                {
                    var sourceZ = Math.Min(15, (int)((long)(rz - targetZ0) * 16 / Math.Max(1, targetZ1 - targetZ0)));
                    for (var rx = targetX0; rx < targetX1; rx++)
                    {
                        var sourceX = Math.Min(15, (int)((long)(rx - targetX0) * 16 / Math.Max(1, targetX1 - targetX0)));
                        var source = sourceZ * 16 + sourceX;
                        var target = rz * rasterSide + rx;
                        if (!chunk.Generated && showUngeneratedTexture)
                        {
                            var worldX = originX + Math.Min(logicalSide - 1, (int)Math.Floor(rx * (double)logicalSide / rasterSide));
                            var worldZ = originZ + Math.Min(logicalSide - 1, (int)Math.Floor(rz * (double)logicalSide / rasterSide));
                            rgb[target] = BedrockSurfaceRegionRenderer.IsUngeneratedStripe(worldX, worldZ)
                                ? BedrockBlockMapColorCatalog.UngeneratedLineRgb
                                : BedrockBlockMapColorCatalog.AirRgb;
                        }
                        else rgb[target] = chunk.Rgb[source];
                        if (keepsMetadata)
                        {
                            names[target] = chunk.BlockNames[source];
                            heights[target] = chunk.Heights[source];
                            biomeIds[target] = chunk.BiomeIds[source];
                            generated[target] = chunk.Generated;
                        }
                    }
                }
            }
        }

        if (drawChunkGrid)
        {
            const uint grid = 0x555555;
            for (var chunkOffset = 1; chunkOffset < sideChunks; chunkOffset++)
            {
                var coordinate = chunkOffset * 16.0 * rasterSide / logicalSide;
                var pixel = (int)Math.Round(coordinate);
                if (pixel <= 0 || pixel >= rasterSide) continue;
                for (var i = 0; i < rasterSide; i++)
                {
                    rgb[i * rasterSide + pixel] = grid;
                    rgb[pixel * rasterSide + i] = grid;
                }
            }
        }

        return new BedrockSurfaceRegion(
            mode, dimension, centerBlockX, centerBlockZ, originX, originZ,
            logicalSide, logicalSide, rasterSide, rasterSide,
            plan.Stride, plan.SampleCount,
            rgb, names, heights, biomeIds, generated, generatedChunks, missingChunks,
            tickingAreaCount, tickingDefinedChunkCount, visibleTickingChunks, errors);
    }

    private static bool TickingAreaIntersects(EnvironmentTickingAreaSpec source, int minX, int minZ, int maxX, int maxZ)
    {
        var area = source.Normalized;
        if (!area.IsCircle)
            return area.MaximumX >= minX && area.MinimumX <= maxX && area.MaximumZ >= minZ && area.MinimumZ <= maxZ;
        var center = area.CenterChunk;
        var closestX = Math.Clamp(center.X, minX, maxX);
        var closestZ = Math.Clamp(center.Z, minZ, maxZ);
        var dx = (long)closestX - center.X;
        var dz = (long)closestZ - center.Z;
        return dx * dx + dz * dz <= (long)area.Radius * area.Radius;
    }

    private static BedrockSurfaceChunk RenderTickingChunk(ChunkPosition position, IReadOnlyList<EnvironmentTickingAreaSpec> matches)
    {
        var kind = matches.Count switch
        {
            > 1 => "mcbeeditor:overlap_ticking_chunk",
            1 when matches[0].Preload => "mcbeeditor:preload_ticking_chunk",
            1 => "mcbeeditor:ticking_chunk",
            _ => "mcbeeditor:non_ticking_chunk"
        };
        var fill = matches.Count switch
        {
            > 1 => 0x9C27B0u,
            1 when matches[0].Preload => 0xFF9800u,
            1 => 0x4CAF50u,
            _ => 0x333333u
        };
        var rgb = Enumerable.Repeat(fill, 256).ToArray();
        if (matches.Count > 0)
        {
            const uint border = 0xAFAFAF;
            for (var i = 0; i < 16; i++)
            {
                rgb[i] = border;
                rgb[15 * 16 + i] = border;
                rgb[i * 16] = border;
                rgb[i * 16 + 15] = border;
            }
            if (matches[0].IsCircle)
            {
                const uint accent = 0xCFCFCF;
                for (var z = 6; z <= 9; z++)
                for (var x = 6; x <= 9; x++)
                    if ((x - 7.5) * (x - 7.5) + (z - 7.5) * (z - 7.5) <= 4.1) rgb[z * 16 + x] = accent;
            }
        }
        return new BedrockSurfaceChunk(position, true, Enumerable.Repeat(kind, 256).ToArray(), new int[256],
            Enumerable.Repeat(uint.MaxValue, 256).ToArray(), rgb, 0, null);
    }

    public static int FloorDiv(int value, int divisor)
    {
        if (divisor <= 0) throw new ArgumentOutOfRangeException(nameof(divisor));
        var quotient = value / divisor;
        var remainder = value % divisor;
        return remainder < 0 ? quotient - 1 : quotient;
    }

    public static bool IsUngeneratedStripe(int blockX, int blockZ)
    {
        var localX = blockX - FloorDiv(blockX, 16) * 16;
        var localZ = blockZ - FloorDiv(blockZ, 16) * 16;
        var difference = localZ - localX;
        return difference is -8 or 0 or 8;
    }
}
