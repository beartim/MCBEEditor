using System.Globalization;

namespace MCBEEditor.Core.Chunk;

public sealed record BedrockBiomeEntry(uint Id, string Identifier, string DisplayName);

public static class BedrockBiomeCatalog
{
    public static readonly IReadOnlyList<BedrockBiomeEntry> Entries = [
        new BedrockBiomeEntry(unchecked((uint)0), "minecraft:ocean", "海洋"),
        new BedrockBiomeEntry(unchecked((uint)1), "minecraft:plains", "平原"),
        new BedrockBiomeEntry(unchecked((uint)2), "minecraft:desert", "沙漠"),
        new BedrockBiomeEntry(unchecked((uint)3), "minecraft:extreme_hills", "峭壁"),
        new BedrockBiomeEntry(unchecked((uint)4), "minecraft:forest", "森林"),
        new BedrockBiomeEntry(unchecked((uint)5), "minecraft:taiga", "针叶林"),
        new BedrockBiomeEntry(unchecked((uint)6), "minecraft:swampland", "沼泽"),
        new BedrockBiomeEntry(unchecked((uint)7), "minecraft:river", "河流"),
        new BedrockBiomeEntry(unchecked((uint)8), "minecraft:hell", "下界荒地"),
        new BedrockBiomeEntry(unchecked((uint)9), "minecraft:the_end", "末地"),
        new BedrockBiomeEntry(unchecked((uint)10), "minecraft:legacy_frozen_ocean", "旧版冻洋"),
        new BedrockBiomeEntry(unchecked((uint)11), "minecraft:frozen_river", "冻河"),
        new BedrockBiomeEntry(unchecked((uint)12), "minecraft:ice_plains", "雪原"),
        new BedrockBiomeEntry(unchecked((uint)13), "minecraft:ice_mountains", "雪山"),
        new BedrockBiomeEntry(unchecked((uint)14), "minecraft:mushroom_island", "蘑菇岛"),
        new BedrockBiomeEntry(unchecked((uint)15), "minecraft:mushroom_island_shore", "蘑菇岛岸"),
        new BedrockBiomeEntry(unchecked((uint)16), "minecraft:beach", "沙滩"),
        new BedrockBiomeEntry(unchecked((uint)17), "minecraft:desert_hills", "沙漠丘陵"),
        new BedrockBiomeEntry(unchecked((uint)18), "minecraft:forest_hills", "森林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)19), "minecraft:taiga_hills", "针叶林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)20), "minecraft:extreme_hills_edge", "峭壁边缘"),
        new BedrockBiomeEntry(unchecked((uint)21), "minecraft:jungle", "丛林"),
        new BedrockBiomeEntry(unchecked((uint)22), "minecraft:jungle_hills", "丛林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)23), "minecraft:jungle_edge", "丛林边缘"),
        new BedrockBiomeEntry(unchecked((uint)24), "minecraft:deep_ocean", "深海"),
        new BedrockBiomeEntry(unchecked((uint)25), "minecraft:stone_beach", "石岸"),
        new BedrockBiomeEntry(unchecked((uint)26), "minecraft:cold_beach", "积雪沙滩"),
        new BedrockBiomeEntry(unchecked((uint)27), "minecraft:birch_forest", "桦木森林"),
        new BedrockBiomeEntry(unchecked((uint)28), "minecraft:birch_forest_hills", "桦木森林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)29), "minecraft:roofed_forest", "黑森林"),
        new BedrockBiomeEntry(unchecked((uint)30), "minecraft:cold_taiga", "积雪针叶林"),
        new BedrockBiomeEntry(unchecked((uint)31), "minecraft:cold_taiga_hills", "积雪针叶林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)32), "minecraft:mega_taiga", "巨型针叶林"),
        new BedrockBiomeEntry(unchecked((uint)33), "minecraft:mega_taiga_hills", "巨型针叶林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)34), "minecraft:extreme_hills_plus_trees", "繁茂峭壁"),
        new BedrockBiomeEntry(unchecked((uint)35), "minecraft:savanna", "热带草原"),
        new BedrockBiomeEntry(unchecked((uint)36), "minecraft:savanna_plateau", "热带高原"),
        new BedrockBiomeEntry(unchecked((uint)37), "minecraft:mesa", "恶地"),
        new BedrockBiomeEntry(unchecked((uint)38), "minecraft:mesa_plateau_stone", "繁茂恶地高原"),
        new BedrockBiomeEntry(unchecked((uint)39), "minecraft:mesa_plateau", "恶地高原"),
        new BedrockBiomeEntry(unchecked((uint)40), "minecraft:warm_ocean", "暖水海洋"),
        new BedrockBiomeEntry(unchecked((uint)41), "minecraft:deep_warm_ocean", "暖水深海"),
        new BedrockBiomeEntry(unchecked((uint)42), "minecraft:lukewarm_ocean", "温水海洋"),
        new BedrockBiomeEntry(unchecked((uint)43), "minecraft:deep_lukewarm_ocean", "温水深海"),
        new BedrockBiomeEntry(unchecked((uint)44), "minecraft:cold_ocean", "冷水海洋"),
        new BedrockBiomeEntry(unchecked((uint)45), "minecraft:deep_cold_ocean", "冷水深海"),
        new BedrockBiomeEntry(unchecked((uint)46), "minecraft:frozen_ocean", "冻洋"),
        new BedrockBiomeEntry(unchecked((uint)47), "minecraft:deep_frozen_ocean", "封冻深海"),
        new BedrockBiomeEntry(unchecked((uint)48), "minecraft:bamboo_jungle", "竹林"),
        new BedrockBiomeEntry(unchecked((uint)49), "minecraft:bamboo_jungle_hills", "竹林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)129), "minecraft:sunflower_plains", "向日葵平原"),
        new BedrockBiomeEntry(unchecked((uint)130), "minecraft:desert_mutated", "沙漠湖泊"),
        new BedrockBiomeEntry(unchecked((uint)131), "minecraft:extreme_hills_mutated", "沙砾山地"),
        new BedrockBiomeEntry(unchecked((uint)132), "minecraft:flower_forest", "繁花森林"),
        new BedrockBiomeEntry(unchecked((uint)133), "minecraft:taiga_mutated", "针叶林山地"),
        new BedrockBiomeEntry(unchecked((uint)134), "minecraft:swampland_mutated", "沼泽丘陵"),
        new BedrockBiomeEntry(unchecked((uint)140), "minecraft:ice_plains_spikes", "冰刺之地"),
        new BedrockBiomeEntry(unchecked((uint)149), "minecraft:jungle_mutated", "变种丛林"),
        new BedrockBiomeEntry(unchecked((uint)151), "minecraft:jungle_edge_mutated", "变种丛林边缘"),
        new BedrockBiomeEntry(unchecked((uint)155), "minecraft:birch_forest_mutated", "原始桦木森林"),
        new BedrockBiomeEntry(unchecked((uint)156), "minecraft:birch_forest_hills_mutated", "高大桦木丘陵"),
        new BedrockBiomeEntry(unchecked((uint)157), "minecraft:roofed_forest_mutated", "黑森林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)158), "minecraft:cold_taiga_mutated", "积雪针叶林山地"),
        new BedrockBiomeEntry(unchecked((uint)160), "minecraft:redwood_taiga_mutated", "原始云杉针叶林"),
        new BedrockBiomeEntry(unchecked((uint)161), "minecraft:redwood_taiga_hills_mutated", "巨型云杉针叶林丘陵"),
        new BedrockBiomeEntry(unchecked((uint)162), "minecraft:extreme_hills_plus_trees_mutated", "沙砾山地+"),
        new BedrockBiomeEntry(unchecked((uint)163), "minecraft:savanna_mutated", "风袭热带草原"),
        new BedrockBiomeEntry(unchecked((uint)164), "minecraft:savanna_plateau_mutated", "破碎热带高原"),
        new BedrockBiomeEntry(unchecked((uint)165), "minecraft:mesa_bryce", "风蚀恶地"),
        new BedrockBiomeEntry(unchecked((uint)166), "minecraft:mesa_plateau_stone_mutated", "变种繁茂恶地高原"),
        new BedrockBiomeEntry(unchecked((uint)167), "minecraft:mesa_plateau_mutated", "变种恶地高原"),
        new BedrockBiomeEntry(unchecked((uint)178), "minecraft:soulsand_valley", "灵魂沙峡谷"),
        new BedrockBiomeEntry(unchecked((uint)179), "minecraft:crimson_forest", "绯红森林"),
        new BedrockBiomeEntry(unchecked((uint)180), "minecraft:warped_forest", "诡异森林"),
        new BedrockBiomeEntry(unchecked((uint)181), "minecraft:basalt_deltas", "玄武岩三角洲"),
        new BedrockBiomeEntry(unchecked((uint)182), "minecraft:jagged_peaks", "尖峭山峰"),
        new BedrockBiomeEntry(unchecked((uint)183), "minecraft:frozen_peaks", "冰封山峰"),
        new BedrockBiomeEntry(unchecked((uint)184), "minecraft:snowy_slopes", "积雪山坡"),
        new BedrockBiomeEntry(unchecked((uint)185), "minecraft:grove", "雪林"),
        new BedrockBiomeEntry(unchecked((uint)186), "minecraft:meadow", "草甸"),
        new BedrockBiomeEntry(unchecked((uint)187), "minecraft:lush_caves", "繁茂洞穴"),
        new BedrockBiomeEntry(unchecked((uint)188), "minecraft:dripstone_caves", "溶洞"),
        new BedrockBiomeEntry(unchecked((uint)189), "minecraft:stony_peaks", "裸岩山峰"),
        new BedrockBiomeEntry(unchecked((uint)190), "minecraft:deep_dark", "深暗之域"),
        new BedrockBiomeEntry(unchecked((uint)191), "minecraft:mangrove_swamp", "红树林沼泽"),
        new BedrockBiomeEntry(unchecked((uint)192), "minecraft:cherry_grove", "樱花树林"),
        new BedrockBiomeEntry(unchecked((uint)193), "minecraft:pale_garden", "苍白之园"),
        new BedrockBiomeEntry(unchecked((uint)194), "minecraft:sulfur_caves", "硫磺洞穴"),
        new BedrockBiomeEntry(unchecked((uint)195), "minecraft:dappled_forest", "斑驳森林"),
    ];

    private static readonly Dictionary<string, BedrockBiomeEntry> ByIdentifier = Entries
        .ToDictionary(item => item.Identifier, StringComparer.OrdinalIgnoreCase);

    public static (uint Id, string DisplayText) Parse(string text)
    {
        if (int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var signed))
            return (unchecked((uint)signed), text);
        if (uint.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var unsigned))
            return (unsigned, text);
        if (ByIdentifier.TryGetValue(text, out var entry))
            return (entry.Id, $"{entry.Identifier}({entry.Id})");
        throw new InvalidDataException($"未知生物群系字符串 ID：{text}。字符串 ID 必须存在于内置 Bedrock 生物群系表；也可直接输入 32 位数字 ID。");
    }

    public static BedrockBiomeEntry? EntryForId(uint id)
        => Entries.FirstOrDefault(item => item.Id == id);

    public static string DisplayNameForId(uint id)
        => EntryForId(id)?.DisplayName ?? "未知生物群系";

    public static string DetailText(uint id)
    {
        var entry = EntryForId(id);
        return entry is null ? $"ID {id} · 未知/自定义" : $"ID {id} · {entry.DisplayName} · {entry.Identifier}";
    }

    /// <summary>Stable map colour parity with the current iOS biome renderer.</summary>
    public static uint ColorForId(uint id)
    {
        if (id == uint.MaxValue) return 0xE0E0E0;
        var identifier = EntryForId(id)?.Identifier.ToLowerInvariant();
        if (identifier is null)
        {
            var hue = ((unchecked(id * 2_654_435_761u)) % 360u) / 360.0;
            return HsvToRgb(hue, 0.42, 0.74);
        }

        bool Has(string token) => identifier.Contains(token, StringComparison.Ordinal);
        if (Has("deep_frozen_ocean")) return Rgb(0.25, 0.46, 0.64);
        if (Has("frozen_ocean")) return Rgb(0.42, 0.65, 0.78);
        if (Has("deep_cold_ocean")) return Rgb(0.10, 0.30, 0.54);
        if (Has("cold_ocean")) return Rgb(0.18, 0.43, 0.68);
        if (Has("deep_lukewarm_ocean")) return Rgb(0.08, 0.35, 0.62);
        if (Has("lukewarm_ocean")) return Rgb(0.10, 0.49, 0.72);
        if (Has("deep_warm_ocean")) return Rgb(0.04, 0.39, 0.65);
        if (Has("warm_ocean")) return Rgb(0.08, 0.58, 0.77);
        if (Has("deep_ocean")) return Rgb(0.07, 0.25, 0.52);
        if (Has("ocean")) return Rgb(0.10, 0.38, 0.72);
        if (Has("frozen_river")) return Rgb(0.48, 0.70, 0.84);
        if (Has("river")) return Rgb(0.18, 0.48, 0.78);
        if (Has("ice_spikes") || Has("ice_plains_spikes")) return Rgb(0.78, 0.90, 0.96);
        if (Has("frozen_peaks")) return Rgb(0.76, 0.84, 0.88);
        if (Has("snowy_slopes")) return Rgb(0.86, 0.91, 0.92);
        if (Has("snow") || Has("ice_") || Has("cold_beach") || Has("grove")) return Rgb(0.73, 0.84, 0.85);
        if (Has("jagged_peaks") || Has("stony_peaks")) return Rgb(0.52, 0.55, 0.54);
        if (Has("mountain") || Has("extreme_hills")) return Rgb(0.48, 0.52, 0.47);
        if (Has("desert")) return Rgb(0.90, 0.78, 0.39);
        if (Has("stone_beach")) return Rgb(0.58, 0.58, 0.54);
        if (Has("beach")) return Rgb(0.90, 0.82, 0.55);
        if (Has("mesa_bryce") || Has("wind_eroded_badlands")) return Rgb(0.76, 0.34, 0.16);
        if (Has("badlands") || Has("mesa")) return Rgb(0.68, 0.29, 0.15);
        if (Has("savanna")) return Rgb(0.70, 0.67, 0.27);
        if (Has("bamboo_jungle")) return Rgb(0.32, 0.64, 0.22);
        if (Has("jungle")) return Rgb(0.16, 0.55, 0.18);
        if (Has("mangrove")) return Rgb(0.25, 0.43, 0.25);
        if (Has("swamp") || Has("swampland")) return Rgb(0.30, 0.40, 0.23);
        if (Has("roofed_forest") || Has("dark_forest")) return Rgb(0.16, 0.34, 0.18);
        if (Has("birch")) return Rgb(0.45, 0.66, 0.32);
        if (Has("mega_taiga") || Has("redwood_taiga")) return Rgb(0.29, 0.43, 0.29);
        if (Has("taiga")) return Rgb(0.34, 0.52, 0.36);
        if (Has("flower_forest")) return Rgb(0.46, 0.70, 0.38);
        if (Has("forest")) return Rgb(0.25, 0.55, 0.25);
        if (Has("sunflower")) return Rgb(0.72, 0.72, 0.31);
        if (Has("meadow")) return Rgb(0.48, 0.72, 0.43);
        if (Has("plains")) return Rgb(0.48, 0.68, 0.32);
        if (Has("mushroom")) return Rgb(0.60, 0.35, 0.55);
        if (Has("cherry")) return Rgb(0.91, 0.59, 0.71);
        if (Has("pale_garden")) return Rgb(0.55, 0.62, 0.54);
        if (Has("dappled_forest")) return Rgb(0.37, 0.58, 0.34);
        if (Has("lush_caves")) return Rgb(0.25, 0.58, 0.33);
        if (Has("dripstone")) return Rgb(0.47, 0.39, 0.33);
        if (Has("deep_dark")) return Rgb(0.08, 0.20, 0.22);
        if (Has("sulfur_caves")) return Rgb(0.63, 0.61, 0.21);
        if (Has("cave")) return Rgb(0.27, 0.32, 0.31);
        if (Has("soulsand")) return Rgb(0.33, 0.25, 0.22);
        if (Has("crimson")) return Rgb(0.50, 0.13, 0.20);
        if (Has("warped")) return Rgb(0.08, 0.50, 0.48);
        if (Has("basalt")) return Rgb(0.25, 0.24, 0.25);
        if (Has("hell") || Has("nether")) return Rgb(0.48, 0.17, 0.16);
        if (Has("the_end") || Has("void")) return Rgb(0.58, 0.57, 0.36);
        return Rgb(0.40, 0.66, 0.32);
    }

    private static uint Rgb(double red, double green, double blue)
    {
        static byte Channel(double value) => (byte)Math.Clamp((int)Math.Round(value * 255.0, MidpointRounding.AwayFromZero), 0, 255);
        return (uint)(Channel(red) << 16 | Channel(green) << 8 | Channel(blue));
    }

    private static uint HsvToRgb(double hue, double saturation, double value)
    {
        hue = hue - Math.Floor(hue);
        var sector = hue * 6.0;
        var index = (int)Math.Floor(sector);
        var fraction = sector - index;
        var p = value * (1.0 - saturation);
        var q = value * (1.0 - saturation * fraction);
        var t = value * (1.0 - saturation * (1.0 - fraction));
        return (index % 6) switch
        {
            0 => Rgb(value, t, p),
            1 => Rgb(q, value, p),
            2 => Rgb(p, value, t),
            3 => Rgb(p, q, value),
            4 => Rgb(t, p, value),
            _ => Rgb(value, p, q)
        };
    }

}
