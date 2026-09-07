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
    static let entries: [BedrockBiomeCatalogEntry] = BedrockDataValueCatalog.biomes.map { value in
        BedrockBiomeCatalogEntry(
            id: UInt32(value.id),
            identifier: value.identifier,
            displayName: value.displayName
        )
    }.sorted { $0.id < $1.id }

    private static let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    private static let byIdentifier = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.identifier.lowercased(), $0) }
    )

    static func entry(for id: UInt32) -> BedrockBiomeCatalogEntry? { byID[id] }
    static func entry(forIdentifier identifier: String) -> BedrockBiomeCatalogEntry? {
        byIdentifier[identifier.lowercased()]
    }

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
}
