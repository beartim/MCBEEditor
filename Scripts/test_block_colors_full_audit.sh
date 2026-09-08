#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/mcbeeditor-block-color-full-audit"
rm -rf "$TMP"
mkdir -p "$TMP"

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

@main
struct Main {
    static func main() throws {
        func semantic(_ name: String, _ legacyID: UInt16? = nil, _ data: UInt8? = nil) -> UInt32? {
            BedrockBlockMapColorCatalog.rgbHex(for: name, legacyID: legacyID, legacyData: data)
        }
        func color(_ name: String, _ legacyID: UInt16? = nil, _ data: UInt8? = nil) -> UInt32 {
            semantic(name, legacyID, data) ?? BedrockBlockMapColorCatalog.fallbackRGB(for: name)
        }

        // Previously confirmed wrong/misleading blocks.
        precondition(color("minecraft:ender_chest") == 0x234342)
        precondition(color("minecraft:ender_chest") != color("minecraft:chest"))
        precondition(color("minecraft:soul_sand") != color("minecraft:sand"))
        precondition(color("minecraft:flower_pot") != color("minecraft:red_flower"))
        precondition(color("minecraft:chorus_flower") != color("minecraft:red_flower"))
        precondition(color("minecraft:end_bricks") != color("minecraft:stone_bricks"))
        precondition(color("minecraft:end_stone_bricks") == color("minecraft:end_bricks"))
        precondition(color("minecraft:soul_torch") != color("minecraft:torch"))
        precondition(color("minecraft:redstone_torch") != color("minecraft:torch"))
        precondition(color("minecraft:redstone_wire") == 0xA32222)
        precondition(color("minecraft:tinted_glass") != color("minecraft:glass"))
        precondition(color("minecraft:mangrove_roots") != color("minecraft:mangrove_planks"))
        precondition(color("minecraft:pale_moss_block") != color("minecraft:moss_block"))
        precondition(color("minecraft:weeping_vines") != color("minecraft:vine"))
        precondition(color("minecraft:twisting_vines") != color("minecraft:vine"))
        precondition(color("minecraft:trapped_chest") != color("minecraft:ender_chest"))

        // Legacy identifier aliases and metadata-driven families.
        precondition(color("minecraft:seaLantern") == color("minecraft:sea_lantern"))
        precondition(color("minecraft:invisibleBedrock", 95, 0) == 0x3A3A3A)
        precondition(color("minecraft:shulker_box", 218, 14) == 0xB02E26)
        precondition(color("minecraft:shulker_box", 218, 11) == 0x3C44AA)
        precondition(color("minecraft:silver_glazed_terracotta") == 0x9D9D97)
        precondition(color("minecraft:pumpkin_stem") == color("minecraft:melon_stem"))

        // Distinct newer families should never fall back to identifier-hash colours.
        let representativeModernBlocks = [
            "minecraft:ender_chest", "minecraft:trapped_chest", "minecraft:barrel",
            "minecraft:lectern", "minecraft:loom", "minecraft:cartography_table",
            "minecraft:fletching_table", "minecraft:smithing_table", "minecraft:composter",
            "minecraft:smoker", "minecraft:blast_furnace", "minecraft:grindstone",
            "minecraft:stonecutter", "minecraft:bell", "minecraft:conduit",
            "minecraft:lodestone", "minecraft:chain", "minecraft:lightning_rod",
            "minecraft:target", "minecraft:honey_block", "minecraft:honeycomb_block",
            "minecraft:decorated_pot", "minecraft:tinted_glass", "minecraft:respawn_anchor",
            "minecraft:crying_obsidian", "minecraft:ancient_debris", "minecraft:netherite_block",
            "minecraft:gilded_blackstone", "minecraft:soul_fire", "minecraft:soul_torch",
            "minecraft:soul_lantern", "minecraft:soul_campfire", "minecraft:weeping_vines",
            "minecraft:twisting_vines", "minecraft:nether_sprouts", "minecraft:end_stone_bricks",
            "minecraft:chorus_flower", "minecraft:ochre_froglight", "minecraft:verdant_froglight",
            "minecraft:pearlescent_froglight", "minecraft:tube_coral_block",
            "minecraft:brain_coral_fan", "minecraft:bubble_coral", "minecraft:dead_fire_coral_block",
            "minecraft:horn_coral", "minecraft:mangrove_roots", "minecraft:muddy_mangrove_roots",
            "minecraft:mangrove_propagule", "minecraft:azalea", "minecraft:flowering_azalea",
            "minecraft:big_dripleaf", "minecraft:small_dripleaf", "minecraft:hanging_roots",
            "minecraft:glow_lichen", "minecraft:leaf_litter", "minecraft:pale_moss_block",
            "minecraft:pale_moss_carpet", "minecraft:pale_hanging_moss", "minecraft:creaking_heart",
            "minecraft:open_eyeblossom", "minecraft:closed_eyeblossom", "minecraft:resin_block",
            "minecraft:resin_bricks", "minecraft:trial_spawner", "minecraft:vault",
            "minecraft:ominous_vault", "minecraft:heavy_core", "minecraft:crafter",
            "minecraft:copper_bulb", "minecraft:copper_grate", "minecraft:oxidized_copper_grate",
            "minecraft:waxed_weathered_copper_bulb", "minecraft:chiseled_copper",
            "minecraft:calibrated_sculk_sensor", "minecraft:sculk_catalyst", "minecraft:sculk_shrieker",
            "minecraft:reinforced_deepslate", "minecraft:suspicious_sand", "minecraft:suspicious_gravel",
            "minecraft:sniffer_egg", "minecraft:torchflower", "minecraft:torchflower_crop",
            "minecraft:pitcher_plant", "minecraft:pitcher_crop", "minecraft:frog_spawn",
            "minecraft:turtle_egg", "minecraft:scaffolding", "minecraft:bamboo_planks",
            "minecraft:bamboo_mosaic", "minecraft:bamboo_block", "minecraft:stripped_bamboo_block",
            "minecraft:bamboo", "minecraft:powder_snow", "minecraft:pointed_dripstone",
            "minecraft:amethyst_cluster", "minecraft:budding_amethyst", "minecraft:small_amethyst_bud",
            "minecraft:smooth_basalt", "minecraft:calcite", "minecraft:dripstone_block",
            "minecraft:spore_blossom", "minecraft:rooted_dirt", "minecraft:coarse_dirt",
            "minecraft:mud", "minecraft:packed_mud", "minecraft:mud_bricks", "minecraft:sea_pickle",
            "minecraft:kelp", "minecraft:seagrass", "minecraft:jack_o_lantern",
            "minecraft:redstone_wire", "minecraft:redstone_torch", "minecraft:repeater",
            "minecraft:comparator", "minecraft:daylight_detector", "minecraft:observer",
            "minecraft:piston", "minecraft:sticky_piston", "minecraft:hopper", "minecraft:anvil",
            "minecraft:cauldron", "minecraft:beacon", "minecraft:enchanting_table",
            "minecraft:chiseled_bookshelf", "minecraft:bookshelf", "minecraft:jigsaw",
            "minecraft:barrier", "minecraft:light_block"
        ]
        let modernFallbacks = representativeModernBlocks.filter { semantic($0) == nil }
        precondition(modernFallbacks.isEmpty, "Unexpected modern block fallback(s): \(modernFallbacks)")

        // Every known numeric legacy block must keep a deterministic semantic colour except the
        // two intentionally unused/reserved technical IDs.
        guard CommandLine.arguments.count == 2 else { preconditionFailure("legacy catalogue path missing") }
        let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"BedrockDataValueEntry\(id:\s*(\d+), identifier:\s*\"([^\"]+)\""#)
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        precondition(matches.count == 256)
        var fallbackIDs: [Int] = []
        for match in matches {
            let id = Int(ns.substring(with: match.range(at: 1)))!
            let name = ns.substring(with: match.range(at: 2))
            if semantic(name, UInt16(id), 0) == nil { fallbackIDs.append(id) }
        }
        precondition(Set(fallbackIDs) == Set([166, 255]), "Unexpected legacy color fallback IDs: \(fallbackIDs)")

        print("Full block-color audit passed (256 legacy IDs + representative modern families)")
    }
}
SWIFT

swiftc -parse-as-library \
  "$ROOT/Sources/Support/BedrockBlockIdentifier.swift" \
  "$ROOT/Sources/Chunk/BedrockBlockMapColorCatalog.swift" \
  "$TMP/main.swift" -o "$TMP/test"
"$TMP/test" "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift"

# Guard the exact problems that motivated this audit against rule-order regressions.
grep -Fq 'case "minecraft:ender_chest": return 0x234342' "$ROOT/Sources/Chunk/BedrockBlockMapColorCatalog.swift"
grep -Fq 'case 35, 160, 171, 218, 236, 237, 241, 254:' "$ROOT/Sources/Chunk/BedrockBlockMapColorCatalog.swift"
if grep -Fq 'case 35, 95,' "$ROOT/Sources/Chunk/BedrockBlockMapColorCatalog.swift"; then
  echo 'error: invisibleBedrock was reintroduced into the stained/dyed legacy family' >&2
  exit 1
fi

echo 'Full block-color regression checks passed'
