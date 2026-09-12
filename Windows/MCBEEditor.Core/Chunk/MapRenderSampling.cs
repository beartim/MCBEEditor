namespace MCBEEditor.Core.Chunk;

public readonly record struct MapSampleAxis(int StartOffset, int EndOffset, int RepresentativeOffset)
{
    public int Span => EndOffset - StartOffset + 1;
}

/// <summary>
/// Bounds the number of LevelDB chunk decodes while preserving the complete
/// represented world extent. Large logical regions are divided into tiles and
/// one representative chunk is decoded for each tile; the tile is then drawn
/// with nearest-neighbour scaling. Clicks can still resolve the exact world
/// coordinate independently of the representative sample.
/// </summary>
public sealed record MapRenderSamplingPlan(
    int LogicalSideChunks,
    int Stride,
    IReadOnlyList<MapSampleAxis> XAxis,
    IReadOnlyList<MapSampleAxis> ZAxis)
{
    public int SampleCount
    {
        get
        {
            var product = (long)XAxis.Count * ZAxis.Count;
            return product > int.MaxValue ? int.MaxValue : (int)product;
        }
    }

    public bool IsDownsampled => Stride > 1;

    public static MapRenderSamplingPlan Create(int sideChunks, int leftChunks, int maximumSamplesPerAxis)
    {
        var side = Math.Max(1, sideChunks);
        var left = Math.Clamp(leftChunks, 0, side - 1);
        var right = side - left - 1;
        var maximumSamples = Math.Max(1, maximumSamplesPerAxis);
        var stride = Math.Max(1, CeilingDivide(side, maximumSamples));
        var axis = MakeAxis(-left, right, stride);
        return new MapRenderSamplingPlan(side, stride, axis, axis);
    }

    public static bool TryChunkCoordinate(int center, int offset, out int coordinate)
    {
        var value = (long)center + offset;
        if (value is < int.MinValue or > int.MaxValue)
        {
            coordinate = 0;
            return false;
        }
        coordinate = (int)value;
        return true;
    }

    private static int CeilingDivide(int value, int divisor)
        => value / divisor + (value % divisor == 0 ? 0 : 1);

    private static IReadOnlyList<MapSampleAxis> MakeAxis(int start, int end, int stride)
    {
        if (start > end) return Array.Empty<MapSampleAxis>();
        var result = new List<MapSampleAxis>(CeilingDivide(end - start + 1, stride));
        var tileStart = start;
        while (tileStart <= end)
        {
            var tileEnd = tileStart + Math.Min(stride - 1, end - tileStart);
            var representative = tileStart <= 0 && tileEnd >= 0
                ? 0
                : tileStart + (tileEnd - tileStart) / 2;
            result.Add(new MapSampleAxis(tileStart, tileEnd, representative));
            if (tileEnd >= end) break;
            tileStart = tileEnd + 1;
        }
        return result;
    }
}
