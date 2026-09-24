using MCBEEditor.Core.Chunk;

internal static class RegionAuditTests
{
    public static void Run()
    {
        var circle = new EnvironmentTickingAreaSpec(0, true, int.MinValue, int.MinValue, int.MinValue + 32, int.MinValue + 32, "edge", false);
        if (!BedrockTickingAreaMap.ContainsChunk(circle, circle.CenterChunk.X, circle.CenterChunk.Z)
            || BedrockTickingAreaMap.ContainsChunk(circle, int.MaxValue, int.MaxValue))
            throw new Exception("Extreme circle containment overflowed.");
        var square = new EnvironmentTickingAreaSpec(0, false, int.MinValue, int.MinValue, int.MaxValue, int.MaxValue, "huge", false);
        if (square.ChunkCount != int.MaxValue) throw new Exception("Extreme rectangle count must saturate.");
        Console.WriteLine("Region arithmetic audit scenarios passed.");
    }
}
