using System.Text;
using MCBEEditor.Core.Nbt;
using MCBEEditor.Core.World;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockTickingAreaMapScan(
    IReadOnlyList<EnvironmentTickingAreaSpec> Areas,
    IReadOnlyList<string> Diagnostics);

/// <summary>Read-only ticking-area decoder shared by map modes and UI overlays.</summary>
public static class BedrockTickingAreaMap
{
    private static readonly byte[] Prefix = Encoding.UTF8.GetBytes("tickingarea_");

    public static BedrockTickingAreaMapScan Read(IWorldDatabase database)
    {
        ArgumentNullException.ThrowIfNull(database);
        var areas = new List<EnvironmentTickingAreaSpec>();
        var diagnostics = new List<string>();
        foreach (var entry in database.Entries(Prefix, includeValues: true))
        {
            if (entry.Value is null || entry.Value.Length == 0) continue;
            try
            {
                var roots = ConsecutiveNbtCodec.Decode(entry.Value);
                foreach (var root in roots) areas.Add(Decode(root.Document));
            }
            catch (Exception ex)
            {
                diagnostics.Add($"{DescribeKey(entry.Key)}: {ex.Message}");
            }
        }
        return new BedrockTickingAreaMapScan(areas, diagnostics);
    }

    public static bool ContainsChunk(EnvironmentTickingAreaSpec source, int chunkX, int chunkZ)
    {
        var area = source.Normalized;
        if (!area.IsCircle)
            return chunkX >= area.MinimumX && chunkX <= area.MaximumX
                && chunkZ >= area.MinimumZ && chunkZ <= area.MaximumZ;
        var center = area.CenterChunk;
        var dx = (long)chunkX - center.X;
        var dz = (long)chunkZ - center.Z;
        var radius = (long)area.Radius;
        return dx * dx + dz * dz <= radius * radius;
    }

    private static EnvironmentTickingAreaSpec Decode(NbtDocument document)
    {
        if (document.Root is not NbtCompoundValue compound)
            throw new InvalidDataException("tickingarea 根标签不是 Compound。");
        NbtValue? Value(string name) => compound.Tags.FirstOrDefault(tag => tag.Name == name)?.Value;
        int? Integer(string name) => Value(name) switch
        {
            NbtByteValue value => value.Value,
            NbtShortValue value => value.Value,
            NbtIntValue value => value.Value,
            NbtLongValue value => value.Value > int.MaxValue ? int.MaxValue : value.Value < int.MinValue ? int.MinValue : (int)value.Value,
            _ => null
        };
        var dimension = Integer("Dimension");
        var minX = Integer("MinX");
        var minZ = Integer("MinZ");
        var maxX = Integer("MaxX");
        var maxZ = Integer("MaxZ");
        if (!dimension.HasValue || !minX.HasValue || !minZ.HasValue || !maxX.HasValue || !maxZ.HasValue)
            throw new InvalidDataException("tickingarea 缺少 Dimension/MinX/MinZ/MaxX/MaxZ。");
        var name = Value("Name") is NbtStringValue text ? text.Value : string.Empty;
        return new EnvironmentTickingAreaSpec(
            dimension.Value,
            (Integer("IsCircle") ?? 0) != 0,
            minX.Value, minZ.Value, maxX.Value, maxZ.Value,
            name,
            (Integer("Preload") ?? 0) != 0).Normalized;
    }

    private static string DescribeKey(byte[] key)
    {
        try
        {
            var text = new UTF8Encoding(false, true).GetString(key);
            if (text.All(character => !char.IsControl(character))) return text;
        }
        catch (DecoderFallbackException) { }
        return "0x" + Convert.ToHexString(key);
    }
}
