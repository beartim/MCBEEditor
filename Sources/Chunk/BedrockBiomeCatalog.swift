import UIKit

/// Human-readable names and stable display colors for the numeric biome values
/// stored in Bedrock Data2D/Data3D records. Unknown/custom numeric IDs remain
/// fully editable and receive a deterministic color instead of being hidden.
struct BedrockBiomeCatalogEntry: Hashable {
    let id: UInt32
    let identifier: String
    let displayName: String
}

enum BedrockBiomeCatalog {
    /// Bedrock numeric biome IDs from the Bedrock data-values table. Gaps are
    /// intentional: Mojang never assigned those values to public biome IDs.
    static let entries: [BedrockBiomeCatalogEntry] = [
        entry(0, "minecraft:ocean", "海洋"),
        entry(1, "minecraft:plains", "平原"),
        entry(2, "minecraft:desert", "沙漠"),
        entry(3, "minecraft:extreme_hills", "峭壁"),
        entry(4, "minecraft:forest", "森林"),
        entry(5, "minecraft:taiga", "针叶林"),
        entry(6, "minecraft:swampland", "沼泽"),
        entry(7, "minecraft:river", "河流"),
        entry(8, "minecraft:hell", "下界荒地"),
        entry(9, "minecraft:the_end", "末地"),
        entry(10, "minecraft:legacy_frozen_ocean", "旧版冻洋"),
        entry(11, "minecraft:frozen_river", "冻河"),
        entry(12, "minecraft:ice_plains", "雪原"),
        entry(13, "minecraft:ice_mountains", "雪山"),
        entry(14, "minecraft:mushroom_island", "蘑菇岛"),
        entry(15, "minecraft:mushroom_island_shore", "蘑菇岛岸"),
        entry(16, "minecraft:beach", "沙滩"),
        entry(17, "minecraft:desert_hills", "沙漠丘陵"),
        entry(18, "minecraft:forest_hills", "森林丘陵"),
        entry(19, "minecraft:taiga_hills", "针叶林丘陵"),
        entry(20, "minecraft:extreme_hills_edge", "峭壁边缘"),
        entry(21, "minecraft:jungle", "丛林"),
        entry(22, "minecraft:jungle_hills", "丛林丘陵"),
        entry(23, "minecraft:jungle_edge", "丛林边缘"),
        entry(24, "minecraft:deep_ocean", "深海"),
        entry(25, "minecraft:stone_beach", "石岸"),
        entry(26, "minecraft:cold_beach", "积雪沙滩"),
        entry(27, "minecraft:birch_forest", "桦木森林"),
        entry(28, "minecraft:birch_forest_hills", "桦木森林丘陵"),
        entry(29, "minecraft:roofed_forest", "黑森林"),
        entry(30, "minecraft:cold_taiga", "积雪针叶林"),
        entry(31, "minecraft:cold_taiga_hills", "积雪针叶林丘陵"),
        entry(32, "minecraft:mega_taiga", "巨型针叶林"),
        entry(33, "minecraft:mega_taiga_hills", "巨型针叶林丘陵"),
        entry(34, "minecraft:extreme_hills_plus_trees", "繁茂峭壁"),
        entry(35, "minecraft:savanna", "热带草原"),
        entry(36, "minecraft:savanna_plateau", "热带高原"),
        entry(37, "minecraft:mesa", "恶地"),
        entry(38, "minecraft:mesa_plateau_stone", "繁茂恶地高原"),
        entry(39, "minecraft:mesa_plateau", "恶地高原"),
        entry(40, "minecraft:warm_ocean", "暖水海洋"),
        entry(41, "minecraft:deep_warm_ocean", "暖水深海"),
        entry(42, "minecraft:lukewarm_ocean", "温水海洋"),
        entry(43, "minecraft:deep_lukewarm_ocean", "温水深海"),
        entry(44, "minecraft:cold_ocean", "冷水海洋"),
        entry(45, "minecraft:deep_cold_ocean", "冷水深海"),
        entry(46, "minecraft:frozen_ocean", "冻洋"),
        entry(47, "minecraft:deep_frozen_ocean", "封冻深海"),
        entry(48, "minecraft:bamboo_jungle", "竹林"),
        entry(49, "minecraft:bamboo_jungle_hills", "竹林丘陵"),
        entry(129, "minecraft:sunflower_plains", "向日葵平原"),
        entry(130, "minecraft:desert_mutated", "沙漠湖泊"),
        entry(131, "minecraft:extreme_hills_mutated", "沙砾山地"),
        entry(132, "minecraft:flower_forest", "繁花森林"),
        entry(133, "minecraft:taiga_mutated", "针叶林山地"),
        entry(134, "minecraft:swampland_mutated", "沼泽丘陵"),
        entry(140, "minecraft:ice_plains_spikes", "冰刺之地"),
        entry(149, "minecraft:jungle_mutated", "变种丛林"),
        entry(151, "minecraft:jungle_edge_mutated", "变种丛林边缘"),
        entry(155, "minecraft:birch_forest_mutated", "原始桦木森林"),
        entry(156, "minecraft:birch_forest_hills_mutated", "高大桦木丘陵"),
        entry(157, "minecraft:roofed_forest_mutated", "黑森林丘陵"),
        entry(158, "minecraft:cold_taiga_mutated", "积雪针叶林山地"),
        entry(160, "minecraft:redwood_taiga_mutated", "原始云杉针叶林"),
        entry(161, "minecraft:redwood_taiga_hills_mutated", "巨型云杉针叶林丘陵"),
        entry(162, "minecraft:extreme_hills_plus_trees_mutated", "沙砾山地+"),
        entry(163, "minecraft:savanna_mutated", "风袭热带草原"),
        entry(164, "minecraft:savanna_plateau_mutated", "破碎热带高原"),
        entry(165, "minecraft:mesa_bryce", "风蚀恶地"),
        entry(166, "minecraft:mesa_plateau_stone_mutated", "变种繁茂恶地高原"),
        entry(167, "minecraft:mesa_plateau_mutated", "变种恶地高原"),
        entry(178, "minecraft:soulsand_valley", "灵魂沙峡谷"),
        entry(179, "minecraft:crimson_forest", "绯红森林"),
        entry(180, "minecraft:warped_forest", "诡异森林"),
        entry(181, "minecraft:basalt_deltas", "玄武岩三角洲"),
        entry(182, "minecraft:jagged_peaks", "尖峭山峰"),
        entry(183, "minecraft:frozen_peaks", "冰封山峰"),
        entry(184, "minecraft:snowy_slopes", "积雪山坡"),
        entry(185, "minecraft:grove", "雪林"),
        entry(186, "minecraft:meadow", "草甸"),
        entry(187, "minecraft:lush_caves", "繁茂洞穴"),
        entry(188, "minecraft:dripstone_caves", "溶洞"),
        entry(189, "minecraft:stony_peaks", "裸岩山峰"),
        entry(190, "minecraft:deep_dark", "深暗之域"),
        entry(191, "minecraft:mangrove_swamp", "红树林沼泽"),
        entry(192, "minecraft:cherry_grove", "樱花树林"),
        entry(193, "minecraft:pale_garden", "苍白之园"),
        entry(194, "minecraft:sulfur_caves", "硫磺洞穴"),
        entry(195, "minecraft:dappled_forest", "斑驳森林"),
    ].sorted { $0.id < $1.id }

    private static let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

    static func entry(for id: UInt32) -> BedrockBiomeCatalogEntry? { byID[id] }

    static func displayName(for id: UInt32) -> String {
        guard let value = byID[id] else { return "未知生物群系" }
        return value.displayName
    }

    static func identifier(for id: UInt32) -> String? { byID[id]?.identifier }

    static func detailText(for id: UInt32) -> String {
        guard let value = byID[id] else { return "ID \(id) · 未知/自定义" }
        return "ID \(id) · \(value.displayName) · \(value.identifier)"
    }

    static func search(_ rawQuery: String) -> [BedrockBiomeCatalogEntry] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            String($0.id).contains(query)
                || String(format: "0x%02X", $0.id).lowercased().contains(query)
                || $0.identifier.lowercased().contains(query)
                || $0.displayName.lowercased().contains(query)
        }
    }

    static func color(for id: UInt32) -> UIColor {
        guard id != UInt32.max else { return UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1) }
        guard let identifier = identifier(for: id)?.lowercased() else {
            // Unknown/custom IDs remain visually distinct but avoid overly vivid neon colors.
            let hue = CGFloat((id &* 2_654_435_761) % 360) / 360.0
            return UIColor(hue: hue, saturation: 0.42, brightness: 0.74, alpha: 1)
        }

        // Oceans and rivers use depth/temperature-aware blues.
        if identifier.contains("deep_frozen_ocean") { return UIColor(red: 0.25, green: 0.46, blue: 0.64, alpha: 1) }
        if identifier.contains("frozen_ocean") { return UIColor(red: 0.42, green: 0.65, blue: 0.78, alpha: 1) }
        if identifier.contains("deep_cold_ocean") { return UIColor(red: 0.10, green: 0.30, blue: 0.54, alpha: 1) }
        if identifier.contains("cold_ocean") { return UIColor(red: 0.18, green: 0.43, blue: 0.68, alpha: 1) }
        if identifier.contains("deep_lukewarm_ocean") { return UIColor(red: 0.08, green: 0.35, blue: 0.62, alpha: 1) }
        if identifier.contains("lukewarm_ocean") { return UIColor(red: 0.10, green: 0.49, blue: 0.72, alpha: 1) }
        if identifier.contains("deep_warm_ocean") { return UIColor(red: 0.04, green: 0.39, blue: 0.65, alpha: 1) }
        if identifier.contains("warm_ocean") { return UIColor(red: 0.08, green: 0.58, blue: 0.77, alpha: 1) }
        if identifier.contains("deep_ocean") { return UIColor(red: 0.07, green: 0.25, blue: 0.52, alpha: 1) }
        if identifier.contains("ocean") { return UIColor(red: 0.10, green: 0.38, blue: 0.72, alpha: 1) }
        if identifier.contains("frozen_river") { return UIColor(red: 0.48, green: 0.70, blue: 0.84, alpha: 1) }
        if identifier.contains("river") { return UIColor(red: 0.18, green: 0.48, blue: 0.78, alpha: 1) }

        // Cold and alpine biomes.
        if identifier.contains("ice_spikes") || identifier.contains("ice_plains_spikes") { return UIColor(red: 0.78, green: 0.90, blue: 0.96, alpha: 1) }
        if identifier.contains("frozen_peaks") { return UIColor(red: 0.76, green: 0.84, blue: 0.88, alpha: 1) }
        if identifier.contains("snowy_slopes") { return UIColor(red: 0.86, green: 0.91, blue: 0.92, alpha: 1) }
        if identifier.contains("snow") || identifier.contains("ice_") || identifier.contains("cold_beach") || identifier.contains("grove") { return UIColor(red: 0.73, green: 0.84, blue: 0.85, alpha: 1) }
        if identifier.contains("jagged_peaks") || identifier.contains("stony_peaks") { return UIColor(red: 0.52, green: 0.55, blue: 0.54, alpha: 1) }
        if identifier.contains("mountain") || identifier.contains("extreme_hills") { return UIColor(red: 0.48, green: 0.52, blue: 0.47, alpha: 1) }

        // Dry biomes.
        if identifier.contains("desert") { return UIColor(red: 0.90, green: 0.78, blue: 0.39, alpha: 1) }
        if identifier.contains("stone_beach") { return UIColor(red: 0.58, green: 0.58, blue: 0.54, alpha: 1) }
        if identifier.contains("beach") { return UIColor(red: 0.90, green: 0.82, blue: 0.55, alpha: 1) }
        if identifier.contains("mesa_bryce") || identifier.contains("wind_eroded_badlands") { return UIColor(red: 0.76, green: 0.34, blue: 0.16, alpha: 1) }
        if identifier.contains("badlands") || identifier.contains("mesa") { return UIColor(red: 0.68, green: 0.29, blue: 0.15, alpha: 1) }
        if identifier.contains("savanna") { return UIColor(red: 0.70, green: 0.67, blue: 0.27, alpha: 1) }

        // Forests and temperate surface biomes.
        if identifier.contains("bamboo_jungle") { return UIColor(red: 0.32, green: 0.64, blue: 0.22, alpha: 1) }
        if identifier.contains("jungle") { return UIColor(red: 0.16, green: 0.55, blue: 0.18, alpha: 1) }
        if identifier.contains("mangrove") { return UIColor(red: 0.25, green: 0.43, blue: 0.25, alpha: 1) }
        if identifier.contains("swamp") || identifier.contains("swampland") { return UIColor(red: 0.30, green: 0.40, blue: 0.23, alpha: 1) }
        if identifier.contains("roofed_forest") || identifier.contains("dark_forest") { return UIColor(red: 0.16, green: 0.34, blue: 0.18, alpha: 1) }
        if identifier.contains("birch") { return UIColor(red: 0.45, green: 0.66, blue: 0.32, alpha: 1) }
        if identifier.contains("mega_taiga") || identifier.contains("redwood_taiga") { return UIColor(red: 0.29, green: 0.43, blue: 0.29, alpha: 1) }
        if identifier.contains("taiga") { return UIColor(red: 0.34, green: 0.52, blue: 0.36, alpha: 1) }
        if identifier.contains("flower_forest") { return UIColor(red: 0.46, green: 0.70, blue: 0.38, alpha: 1) }
        if identifier.contains("forest") { return UIColor(red: 0.25, green: 0.55, blue: 0.25, alpha: 1) }
        if identifier.contains("sunflower") { return UIColor(red: 0.72, green: 0.72, blue: 0.31, alpha: 1) }
        if identifier.contains("meadow") { return UIColor(red: 0.48, green: 0.72, blue: 0.43, alpha: 1) }
        if identifier.contains("plains") { return UIColor(red: 0.48, green: 0.68, blue: 0.32, alpha: 1) }

        // Special Overworld biomes.
        if identifier.contains("mushroom") { return UIColor(red: 0.60, green: 0.35, blue: 0.55, alpha: 1) }
        if identifier.contains("cherry") { return UIColor(red: 0.91, green: 0.59, blue: 0.71, alpha: 1) }
        if identifier.contains("pale_garden") { return UIColor(red: 0.55, green: 0.62, blue: 0.54, alpha: 1) }
        if identifier.contains("dappled_forest") { return UIColor(red: 0.37, green: 0.58, blue: 0.34, alpha: 1) }
        if identifier.contains("lush_caves") { return UIColor(red: 0.25, green: 0.58, blue: 0.33, alpha: 1) }
        if identifier.contains("dripstone") { return UIColor(red: 0.47, green: 0.39, blue: 0.33, alpha: 1) }
        if identifier.contains("deep_dark") { return UIColor(red: 0.08, green: 0.20, blue: 0.22, alpha: 1) }
        if identifier.contains("sulfur_caves") { return UIColor(red: 0.63, green: 0.61, blue: 0.21, alpha: 1) }
        if identifier.contains("cave") { return UIColor(red: 0.27, green: 0.32, blue: 0.31, alpha: 1) }

        // Nether biomes need distinct colors rather than one shared red.
        if identifier.contains("soulsand") { return UIColor(red: 0.33, green: 0.25, blue: 0.22, alpha: 1) }
        if identifier.contains("crimson") { return UIColor(red: 0.50, green: 0.13, blue: 0.20, alpha: 1) }
        if identifier.contains("warped") { return UIColor(red: 0.08, green: 0.50, blue: 0.48, alpha: 1) }
        if identifier.contains("basalt") { return UIColor(red: 0.25, green: 0.24, blue: 0.25, alpha: 1) }
        if identifier.contains("hell") || identifier.contains("nether") { return UIColor(red: 0.48, green: 0.17, blue: 0.16, alpha: 1) }

        if identifier.contains("the_end") || identifier.contains("void") { return UIColor(red: 0.58, green: 0.57, blue: 0.36, alpha: 1) }
        return UIColor(red: 0.40, green: 0.66, blue: 0.32, alpha: 1)
    }

    private static func entry(_ id: UInt32, _ identifier: String, _ displayName: String) -> BedrockBiomeCatalogEntry {
        BedrockBiomeCatalogEntry(id: id, identifier: identifier, displayName: displayName)
    }
}
