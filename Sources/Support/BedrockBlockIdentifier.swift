import Foundation

/// Shared identifier semantics used by commands, chunk editing and map rendering.
/// Keep these exact-name checks centralized: substring checks such as `contains("water")`
/// incorrectly classify blocks like `waterlily` and `underwater_torch` as fluids.
enum BedrockBlockIdentifier {
    static func normalized(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isAir(_ identifier: String) -> Bool {
        switch normalized(identifier) {
        case "minecraft:air", "minecraft:cave_air", "minecraft:void_air", "legacy:0:0":
            return true
        default:
            return false
        }
    }

    static func isWater(_ identifier: String) -> Bool {
        let name = normalized(identifier)
        return name == "minecraft:water"
            || name == "minecraft:flowing_water"
            || name.hasSuffix(":bubble_column")
    }

    static func isLava(_ identifier: String) -> Bool {
        let name = normalized(identifier)
        return name == "minecraft:lava" || name == "minecraft:flowing_lava"
    }

    static func isHighlightedOre(_ identifier: String) -> Bool {
        let name = normalized(identifier)
        return name.contains("_ore")
            || name.contains("ancient_debris")
            || name.contains("raw_iron_block")
            || name.contains("raw_gold_block")
            || name.contains("raw_copper_block")
            || name.contains("amethyst_cluster")
    }
}
