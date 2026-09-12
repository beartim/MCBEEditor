using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

/// <summary>
/// Loss-aware bridge used when must copy a legacy numeric block into a
/// modern palette. Unknown non-zero metadata is preserved as historical `val`
/// instead of being silently discarded.
/// </summary>
public static class BedrockLegacyBlockStateConverter
{
    public static byte? NumericData(BedrockBlockState state)
    {
        if (state.Nbt is null) return state.LegacyData ?? 0;
        if (state.Nbt.CompoundValue("val")?.IntegerValue() is long val)
            return val is >= 0 and <= 255 ? (byte)val : null;
        if (state.Nbt.CompoundValue("states") is not NbtCompoundValue properties) return null;
        if (properties.Tags.Count == 0) return 0;
        if (BedrockLegacyBlockCatalog.NumericIdForIdentifier(state.Name) is not ushort id) return null;
        for (var data = 0; data <= byte.MaxValue; data++)
        {
            var candidate = ExactStates(state.Name, id, (byte)data);
            if (candidate is not null && candidate.Count == properties.Tags.Count
                && candidate.All(tag => properties.Tags.Any(other => tag.Name == other.Name
                    && BedrockNbtCodec.Encode(new NbtDocument("", tag.Value), NbtEncoding.LittleEndian)
                        .AsSpan().SequenceEqual(BedrockNbtCodec.Encode(new NbtDocument("", other.Value), NbtEncoding.LittleEndian)))))
                return (byte)data;
        }
        return null;
    }

    public static BedrockBlockState ForPalette(BedrockBlockState state, BedrockPaletteFormat? format)
    {
        if (format?.UsesLegacyVal != true) return state;
        if (state.Nbt?.CompoundValue("val") is not null && state.Nbt.CompoundValue("states") is null)
            return state;
        var data = NumericData(state) ?? throw new NotSupportedException(
            $"当前存档使用旧式 val 调色板，无法无损表示 {state.Name} 的 states。");
        var tags = new List<NbtNamedTag>
        {
            new("name", new NbtStringValue(state.Name)), new("val", new NbtShortValue(data))
        };
        if (format.Version is int version) tags.Add(new("version", new NbtIntValue(version)));
        return new(new NbtCompoundValue(tags), null, null);
    }

    public const int HistoricalPaletteVersion = 0x010C0000;

    public static BedrockBlockState StateForNumeric(BedrockBlockState state)
    {
        var id = state.LegacyId ?? 0;
        var data = state.LegacyData ?? 0;
        var identifier = BedrockLegacyBlockCatalog.IdentifierForNumericId(id) ?? state.Name;
        var states = ExactStates(identifier, id, data);
        if (states is not null)
        {
            return new BedrockBlockState(new NbtCompoundValue([
                new NbtNamedTag("name", new NbtStringValue(identifier)),
                new NbtNamedTag("states", new NbtCompoundValue(states)),
                new NbtNamedTag("version", new NbtIntValue(HistoricalPaletteVersion))
            ]), null, null);
        }

        return new BedrockBlockState(new NbtCompoundValue([
            new NbtNamedTag("name", new NbtStringValue(identifier)),
            new NbtNamedTag("val", new NbtShortValue(data)),
            new NbtNamedTag("version", new NbtIntValue(HistoricalPaletteVersion))
        ]), null, null);
    }

    private static IReadOnlyList<NbtNamedTag>? ExactStates(string identifier, ushort legacyId, byte data)
    {
        var value = (int)data;
        string[] colors = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "silver", "cyan", "purple", "blue", "brown", "green", "red", "black"];
        if (new[] { 35, 159, 160, 171, 218, 236, 237, 241, 254 }.Contains((int)legacyId) && value < colors.Length)
            return [new NbtNamedTag("color", new NbtStringValue(colors[value]))];
        if (legacyId == 5)
        {
            string[] woods = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak"];
            return value < woods.Length ? [new NbtNamedTag("wood_type", new NbtStringValue(woods[value]))] : null;
        }
        if (legacyId == 1)
        {
            string[] types = ["stone", "granite", "granite_smooth", "diorite", "diorite_smooth", "andesite", "andesite_smooth"];
            return value < types.Length ? [new NbtNamedTag("stone_type", new NbtStringValue(types[value]))] : null;
        }
        if (legacyId == 3)
        {
            string[] types = ["normal", "coarse"];
            return value < types.Length ? [new NbtNamedTag("dirt_type", new NbtStringValue(types[value]))] : null;
        }
        if (legacyId == 12)
        {
            string[] types = ["normal", "red"];
            return value < types.Length ? [new NbtNamedTag("sand_type", new NbtStringValue(types[value]))] : null;
        }
        if (legacyId is 24 or 179)
        {
            string[] types = ["default", "heiroglyphs", "cut", "smooth"];
            return value < types.Length ? [new NbtNamedTag("sand_stone_type", new NbtStringValue(types[value]))] : null;
        }
        if (legacyId == 155)
        {
            string[] types = ["default", "chiseled", "lines", "smooth"];
            return value < types.Length ? [new NbtNamedTag("chisel_type", new NbtStringValue(types[value]))] : null;
        }
        if (legacyId == 168)
        {
            string[] types = ["default", "dark", "bricks"];
            return value < types.Length ? [new NbtNamedTag("prismarine_block_type", new NbtStringValue(types[value]))] : null;
        }
        if (data == 0 && !identifier.Equals("minecraft:unknown", StringComparison.OrdinalIgnoreCase)) return [];
        return null;
    }
}
