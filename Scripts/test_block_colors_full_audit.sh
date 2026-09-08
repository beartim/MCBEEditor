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

        // Third-pass flower/plant audit.  These used to collapse into the generic red-flower or
        // green-bush rules.  Sunflower aliases must stay yellow and every common flower keeps a
        // visually meaningful hue.
        precondition(color("minecraft:sun_flower") == 0xE2B93B)
        precondition(color("minecraft:sunflower") == color("minecraft:sun_flower"))
        precondition(color("minecraft:sunflower") != color("minecraft:red_flower"))
        precondition(color("minecraft:blue_orchid") == 0x5C91D0)
        precondition(color("minecraft:allium") == 0xA56BC0)
        precondition(color("minecraft:azure_bluet") == 0xDAD8CE)
        precondition(color("minecraft:orange_tulip") == 0xE47B2A)
        precondition(color("minecraft:white_tulip") == 0xE6E4D8)
        precondition(color("minecraft:pink_tulip") == 0xE58FA8)
        precondition(color("minecraft:cornflower") == 0x5579C6)
        precondition(color("minecraft:wither_rose") == 0x3B2B3E)
        precondition(color("minecraft:lilac") == 0xB57AB8)
        precondition(color("minecraft:peony") == 0xE58FA8)
        precondition(color("minecraft:deadbush") == 0x78603A)
        precondition(color("minecraft:deadbush") != color("minecraft:bush"))
        precondition(color("minecraft:dried_kelp_block") != color("minecraft:kelp"))
        precondition(color("minecraft:wet_sponge") != color("minecraft:sponge"))

        // Copper rules must inspect the oxidation token anywhere in the identifier and must not
        // steal raw-copper storage blocks.
        precondition(color("minecraft:raw_copper_block") == 0xA86245)
        precondition(color("minecraft:waxed_oxidized_cut_copper_stairs") == 0x4F9C85)
        precondition(color("minecraft:waxed_weathered_copper_lantern") == 0x6D8F75)
        precondition(color("minecraft:exposed_cut_copper_slab") == 0xA66B4A)
        precondition(color("minecraft:copper_block") == 0xC46C43)

        // Current Bedrock families added after the original colour table should use semantic
        // colours rather than identifier-hash fallbacks.
        precondition(color("minecraft:cinnabar") == 0xA64A3C)
        precondition(color("minecraft:polished_cinnabar") == 0xB45B49)
        precondition(color("minecraft:sulfur") == 0xD8CB4B)
        precondition(color("minecraft:polished_sulfur") == 0xCDBE4A)
        precondition(color("minecraft:potent_sulfur") == 0xE0C93A)
        precondition(color("minecraft:golden_dandelion") == 0xEBC43B)
        precondition(color("minecraft:red_poplar_leaves") == 0xA84C3F)
        precondition(color("minecraft:orange_poplar_leaves") == 0xC67835)
        precondition(color("minecraft:yellow_poplar_leaves") == 0xC5B34A)
        precondition(color("minecraft:red_poplar_leaves") != color("minecraft:poplar_planks"))
        precondition(color("minecraft:poplar_planks") == 0xA88B61)
        precondition(color("minecraft:red_shrub") == 0x9A5544)
        precondition(color("minecraft:small_dripleaf_block") == color("minecraft:small_dripleaf"))
        precondition(color("minecraft:iron_chain") == color("minecraft:chain"))
        precondition(color("minecraft:straw_bed") == 0xC7A84A)
        precondition(color("minecraft:straw_bed") != color("minecraft:white_bed"))
        precondition(color("minecraft:infested_deepslate") == 0x3F4245)
        precondition(color("minecraft:infested_mossy_stone_bricks") == 0x5E7157)
        precondition(color("minecraft:infested_cobblestone") == 0x686868)
        precondition(color("minecraft:dried_ghast") == 0xC8C2B6)
        precondition(color("minecraft:copper_torch") == 0x58A88F)
        precondition(color("minecraft:light_block_15") == 0xEEE7A0)
        precondition(color("minecraft:element_118") == 0x8B8B8B)
        precondition(color("minecraft:darkoak_standing_sign") == 0x4B3422)
        precondition(color("minecraft:darkoak_standing_sign") != color("minecraft:oak_standing_sign"))
        precondition(color("minecraft:spruce_leaves") == 0x426B46)
        precondition(color("minecraft:birch_leaves") == 0x6F8F46)
        precondition(color("minecraft:acacia_leaves") == 0x507D2A)
        precondition(color("minecraft:dark_oak_leaves") == 0x2E5D2E)
        precondition(color("minecraft:candle") == 0xD6C28B)
        precondition(color("minecraft:candle") != color("minecraft:white_candle"))
        precondition(color("minecraft:oxidized_lightning_rod") == 0x4F9C85)
        precondition(color("minecraft:weathered_lightning_rod") == 0x6D8F75)
        precondition(color("minecraft:exposed_lightning_rod") == 0xA66B4A)
        precondition(color("minecraft:chain_command_block") == 0x5F8F69)
        precondition(color("minecraft:repeating_command_block") == 0x8266A8)
        precondition(color("minecraft:chain_command_block") != color("minecraft:command_block"))
        precondition(color("minecraft:repeating_command_block") != color("minecraft:command_block"))
        precondition(color("minecraft:lit_smoker") != color("minecraft:furnace"))
        precondition(color("minecraft:lit_pumpkin") == color("minecraft:jack_o_lantern"))
        precondition(color("minecraft:skeleton_skull") == 0xC9C5B2)
        precondition(color("minecraft:wither_skeleton_skull") == 0x3A3538)
        precondition(color("minecraft:skeleton_skull") != color("minecraft:wither_skeleton_skull"))
        precondition(color("minecraft:unknown") == 0x8A4F9B)

        // Legacy identifier aliases and metadata-driven families.
        precondition(color("minecraft:seaLantern") == color("minecraft:sea_lantern"))
        precondition(color("minecraft:invisibleBedrock", 95, 0) == 0x3A3A3A)
        precondition(color("minecraft:shulker_box", 218, 14) == 0xB02E26)
        precondition(color("minecraft:shulker_box", 218, 11) == 0x3C44AA)
        precondition(color("minecraft:silver_glazed_terracotta") == 0x9D9D97)
        precondition(color("minecraft:pumpkin_stem") == color("minecraft:melon_stem"))
        // Legacy red_flower and double_plant IDs encode the actual flower in data.
        precondition(color("minecraft:red_flower", 38, 0) == 0xB94A4A)
        precondition(color("minecraft:red_flower", 38, 1) == 0x5C91D0)
        precondition(color("minecraft:red_flower", 38, 2) == 0xA56BC0)
        precondition(color("minecraft:red_flower", 38, 5) == 0xE47B2A)
        precondition(color("minecraft:red_flower", 38, 7) == 0xE58FA8)
        precondition(color("minecraft:double_plant", 175, 0) == 0xE2B93B)
        precondition(color("minecraft:double_plant", 175, 1) == 0xB57AB8)
        precondition(color("minecraft:double_plant", 175, 4) == 0xB94A4A)
        precondition(color("minecraft:double_plant", 175, 5) == 0xE58FA8)
        precondition(color("minecraft:colored_torch_rg", 202, 0) == 0xD94A3A)
        precondition(color("minecraft:colored_torch_rg", 202, 1) == 0x55B95B)
        precondition(color("minecraft:colored_torch_bp", 204, 0) == 0x4B73D1)
        precondition(color("minecraft:colored_torch_bp", 204, 1) == 0x9B5BC2)

        // Distinct newer families should never fall back to identifier-hash colours.
        let representativeModernBlocks = [
            "minecraft:ender_chest", "minecraft:trapped_chest", "minecraft:barrel",
            "minecraft:sunflower", "minecraft:sun_flower", "minecraft:blue_orchid",
            "minecraft:allium", "minecraft:azure_bluet", "minecraft:cornflower",
            "minecraft:lilac", "minecraft:peony", "minecraft:wither_rose",
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
            "minecraft:barrier", "minecraft:light_block", "minecraft:light_block_15",
            "minecraft:cinnabar", "minecraft:polished_cinnabar", "minecraft:sulfur",
            "minecraft:polished_sulfur", "minecraft:potent_sulfur", "minecraft:golden_dandelion",
            "minecraft:poplar_planks", "minecraft:red_poplar_leaves", "minecraft:orange_poplar_leaves",
            "minecraft:yellow_poplar_leaves", "minecraft:red_shrub", "minecraft:small_dripleaf_block",
            "minecraft:iron_chain", "minecraft:straw_bed", "minecraft:infested_deepslate",
            "minecraft:chain_command_block", "minecraft:repeating_command_block",
            "minecraft:lit_smoker", "minecraft:lit_pumpkin", "minecraft:skeleton_skull",
            "minecraft:wither_skeleton_skull", "minecraft:unknown", "minecraft:dried_ghast",
            "minecraft:dried_kelp_block", "minecraft:copper_torch", "minecraft:element_118"
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
