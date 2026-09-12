namespace MCBEEditor.Core.Chunk;

/// <summary>
/// Shared dynamic-map viewport policy. Reload decisions are based on the full
/// visible world rectangle so a finite desktop scroll surface cannot reach its
/// raster edge before the logical world is recentered.
/// </summary>
public static class MapViewportPolicy
{
    public static bool NeedsRecentering(
        double visibleMinimumA, double visibleMaximumA,
        double visibleMinimumB, double visibleMaximumB,
        double renderedMinimumA, double renderedMaximumA,
        double renderedMinimumB, double renderedMaximumB,
        double maximumPreloadBlocks = 32.0)
    {
        var spanA = Math.Max(0.0, renderedMaximumA - renderedMinimumA);
        var spanB = Math.Max(0.0, renderedMaximumB - renderedMinimumB);
        var preloadLimit = Math.Max(0.0, maximumPreloadBlocks);
        var preloadA = Math.Min(spanA * 0.25, preloadLimit);
        var preloadB = Math.Min(spanB * 0.25, preloadLimit);

        return visibleMinimumA < renderedMinimumA + preloadA
            || visibleMaximumA > renderedMaximumA - preloadA
            || visibleMinimumB < renderedMinimumB + preloadB
            || visibleMaximumB > renderedMaximumB - preloadB;
    }
}
