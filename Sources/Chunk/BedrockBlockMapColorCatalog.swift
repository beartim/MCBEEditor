import Foundation

/// Stable, UIKit-independent block colours used by the 2-D map and X/Z cross-section renderers.
///
/// The renderer only has a block palette entry, not the vanilla resource-pack texture.  These
/// colours therefore follow the block's dominant/vanilla-map material colour instead of trying
/// to sample textures at runtime.  Keep specific rules before broad material families so names
/// such as `soul_sand`, `waterlily`, `stone_bricks` and `prismarine_bricks` cannot be captured by
/// an unrelated substring rule.
enum BedrockBlockMapColorCatalog {
    static let airRGB: UInt32 = 0xE5E5E5

    private static let dyeRGB: [UInt32] = [
        0xF4F4F4, 0xF9801D, 0xC64FBD, 0x3AAFD9,
        0xFED83D, 0x70B919, 0xF38BAA, 0x474F52,
        0x9D9D97, 0x169C9C, 0x8932B8, 0x3C44AA,
        0x835432, 0x5E7C16, 0xB02E26, 0x1D1D21
    ]

    // Vanilla stained-terracotta/map colours are deliberately much more muted than wool or
    // concrete.  Treating all dyed families as wool was a major source of misleading maps.
    private static let terracottaRGB: [UInt32] = [
        0xD1B1A1, 0x9F5224, 0x95576C, 0x706C8A,
        0xBA8524, 0x677535, 0xA04D4E, 0x392923,
        0x876B62, 0x575C5C, 0x7A4958, 0x4C3E5C,
        0x4C3223, 0x4C522A, 0x8E3C2E, 0x251610
    ]

    private static let dyeNames: [(String, Int)] = [
        ("light_blue", 3), ("light_gray", 8), ("magenta", 2), ("orange", 1),
        ("yellow", 4), ("lime", 5), ("pink", 6), ("silver", 8), ("gray", 7),
        ("cyan", 9), ("purple", 10), ("blue", 11), ("brown", 12),
        ("green", 13), ("red", 14), ("black", 15), ("white", 0)
    ]

    static func isAir(_ identifier: String) -> Bool {
        BedrockBlockIdentifier.isAir(identifier)
    }

    static func isWater(_ identifier: String) -> Bool {
        BedrockBlockIdentifier.isWater(identifier)
    }

    static func rgbHex(
        for identifier: String,
        legacyID: UInt16? = nil,
        legacyData: UInt8? = nil
    ) -> UInt32? {
        let name = normalized(identifier)

        if isAir(name) { return airRGB }
        if let legacyID, let color = legacyVariantRGB(id: legacyID, data: legacyData ?? 0) {
            return color
        }

        // Fluids: use exact/suffix matching so `waterlily` and `underwater_torch` are not water.
        if isWater(name) { return 0x337CCB }
        if BedrockBlockIdentifier.isLava(name) { return 0xF05A19 }

        if let dyed = dyedFamilyRGB(name) { return dyed }

        // Exact/special semantic colours are intentionally evaluated before broad material
        // families.  Many block identifiers contain a misleading material token: for example
        // `ender_chest` is obsidian/teal rather than oak-brown, `flower_pot` is terracotta rather
        // than a flower, and `end_stone_bricks` must not be swallowed by generic stone bricks.
        if let special = specialSemanticRGB(name) { return special }

        // Legacy/functional blocks whose identifiers do not carry their material in the name.
        if name == "minecraft:bed" { return 0xB02E26 }
        if name.contains("iron_door") || name.contains("iron_trapdoor") || name.contains("iron_bars") { return 0xC8C5BC }
        if name.contains("light_weighted_pressure_plate") { return 0xC9A93C }
        if name.contains("heavy_weighted_pressure_plate") { return 0xAAA8A1 }
        if name.contains("repeater") || name.contains("comparator") { return 0x7B706A }
        if name.contains("daylight_detector") { return 0x8A6A42 }
        if name.hasSuffix(":lever") || name.contains("tripwire_hook") { return 0x77706A }
        if name.contains("tripwire") || name.contains("trip_wire") { return 0xA0A0A0 }
        if name.contains("brewing_stand") { return 0x5A5042 }
        if name.contains("dragon_egg") { return 0x241B35 }
        if name.contains("skull") { return 0x8D8D83 }
        if name.contains("slime") && !name.contains("slime_chunk") { return 0x72B85E }
        if name.contains("double_plant") { return 0x5E913D }
        if name.contains("end_portal_frame") { return 0x99996A }
        if name.contains("end_portal") || name.contains("end_gateway") { return 0x17151E }
        if name.contains("end_rod") { return 0xE2DDD1 }
        if name.hasSuffix(":allow") { return 0x61A85B }
        if name.hasSuffix(":deny") { return 0xA85B5B }
        if name.contains("border_block") { return 0xB56C60 }
        if name.contains("chalkboard") { return 0x343331 }
        if name.contains("chemistry_table") || name.contains("camera") { return 0x5E6265 }
        if name.contains("chemical_heat") { return 0xD46E35 }
        if name.contains("netherreactor") { return 0x455267 }
        if name.contains("item_frame") || name == "minecraft:frame" { return 0x835432 }
        if name.contains("info_update") { return 0xB06DA8 }
        if name.lowercased().contains("movingblock") || name.contains("moving_block") { return 0x777777 }
        if name.contains("monster_egg") || name.contains("infested_") { return 0x777777 }
        if name.contains("element_0") { return 0x8B8B8B }

        // Transparent/invisible technical blocks.
        if name.hasSuffix(":structure_void") { return airRGB }
        if name.contains("glass") || name.hasSuffix(":glass_pane") { return 0xD6E9EC }

        // Highly specific natural blocks must precede broad plant/stone/sand families.
        if name.contains("mossy_cobblestone") || name.contains("mossy_stone_brick") { return 0x5E7157 }
        if name.contains("soul_sand") { return 0x544034 }
        if name.contains("soul_soil") { return 0x4B3A30 }
        if name.contains("red_sandstone") { return 0xB96A39 }
        if name.contains("sandstone") { return 0xD9C58B }
        if name.hasSuffix(":red_sand") || name.contains(":red_sand_") { return 0xB65A27 }
        if name.hasSuffix(":sand") || name.contains(":sand_") { return 0xDEC98A }

        // Vegetation and organic blocks.
        if name.contains("mangrove_leaves") { return 0x3E7138 }
        if name.contains("azalea_leaves") { return 0x4F8A3A }
        if name.contains("cherry_leaves") || name.contains("pink_petals") { return 0xECA7B7 }
        if name.contains("pale_oak_leaves") { return 0x869280 }
        if name.contains("leaves") { return 0x3F7D32 }
        if name.hasSuffix(":vine") || name.contains(":vines") { return 0x2E8B3A }
        if name.contains("moss_block") || name.contains("moss_carpet") { return 0x5E9B3B }
        if name.contains("grass_block") || name == "minecraft:grass" || name.contains("short_grass")
            || name.contains("tall_grass") || name.contains("tallgrass") || name.contains("fern") {
            return 0x5E9B3B
        }
        if name.contains("lily_pad") || name.contains("waterlily") { return 0x347A38 }
        if name.contains("cactus") { return 0x3F7F3C }
        if name.contains("sugar_cane") || name.contains("reeds") { return 0x79A94A }
        if name.contains("kelp") || name.contains("seagrass") { return 0x2E6C3A }
        if name.contains("sea_pickle") { return 0x71813C }
        if name.contains("sapling") { return 0x4C7E32 }
        if name.contains("deadbush") { return 0x78603A }
        if name.contains("brown_mushroom") { return 0x8B684F }
        if name.contains("red_mushroom") { return 0xB84A42 }
        if name.contains("mushroom") { return 0x9B7665 }
        if name.contains("wheat") || name.contains("hay_block") { return 0xC6A83A }
        if name.contains("beetroot") || name.contains("carrots") || name.contains("potatoes") { return 0x65913C }
        if name.contains("melon") { return 0x76A83D }
        if name.contains("pumpkin") { return 0xC87525 }
        if name.contains("cocoa") { return 0x81522D }
        if name.contains("flower") || name.contains("poppy") || name.contains("dandelion") {
            if name.contains("blue") { return 0x5C85C9 }
            if name.contains("yellow") || name.contains("dandelion") { return 0xE0C83E }
            return 0xB94A4A
        }
        if name.contains("mycelium") { return 0x705A6A }
        if name.contains("podzol") { return 0x6B4B2A }
        if name.contains("mud_brick") { return 0x77645A }
        if name.hasSuffix(":mud") || name.contains(":packed_mud") { return 0x4B4648 }
        if name.contains("rooted_dirt") || name.contains("coarse_dirt") || name.contains("dirt")
            || name.contains("farmland") || name.contains("grass_path") || name.contains("dirt_path") {
            return 0x76502B
        }
        if name == "minecraft:clay" || name.hasSuffix(":clay") { return 0x9AA6B1 }
        if name.contains("gravel") { return 0x77716D }

        // Snow and ice.
        if name.contains("powder_snow") || name.hasSuffix(":snow") || name.contains("snow_layer") { return 0xF1F6F7 }
        if name.contains("blue_ice") { return 0x74A9FF }
        if name.contains("packed_ice") { return 0x8DB4EA }
        if name.contains("frosted_ice") { return 0xA9C7EA }
        if name.hasSuffix(":ice") { return 0xB6D7F2 }

        // Stone/mineral host families.  Specific brick families stay material-coloured instead
        // of falling into the old generic red `brick` substring rule.
        if name.contains("bedrock") { return 0x3A3A3A }
        if name.contains("sculk") { return 0x12383B }
        if name.contains("dripstone") { return 0x6F594C }
        if name.contains("calcite") { return 0xD7D4CB }
        if name.contains("granite") { return 0x95604C }
        if name.contains("diorite") { return 0xC9C9C5 }
        if name.contains("andesite") { return 0x7D7D7D }
        if name.contains("tuff") { return 0x59645D }
        if name.contains("deepslate") { return 0x3F4245 }
        if name.contains("blackstone") { return 0x2F292F }
        if name.contains("basalt") { return 0x4D4A4A }
        if name.contains("prismarine") {
            if name.contains("dark_prismarine") { return 0x335B51 }
            if name.contains("brick") { return 0x63A89A }
            return 0x5E9B8B
        }
        if name.contains("cobblestone") { return 0x686868 }
        if name.contains("stone_brick") || name.contains("stonebrick") { return 0x777777 }

        // Ores should resemble their host block in normal surface mode.  X-ray mode has a
        // separate vivid ore palette, so making exposed ore cyan/yellow here is misleading.
        if name.contains("_ore") {
            if name.contains("deepslate") { return 0x535557 }
            if name.contains("nether") || name.contains("quartz") { return 0x773333 }
            if name.contains("copper") { return 0x88766D }
            if name.contains("iron") { return 0x85807A }
            if name.contains("gold") { return 0x837C63 }
            if name.contains("redstone") { return 0x765F5E }
            if name.contains("lapis") { return 0x626B7D }
            if name.contains("diamond") { return 0x698080 }
            if name.contains("emerald") { return 0x687D6B }
            if name.contains("coal") { return 0x5C5C5C }
            return 0x777777
        }

        // Wood species. Plant forms were handled above so `oak_sapling` never becomes timber.
        if name.contains("pale_oak") { return 0xC6BEA7 }
        if name.contains("dark_oak") { return 0x4B3422 }
        if name.contains("spruce") { return 0x6B4A2B }
        if name.contains("birch") { return 0xC4B87A }
        if name.contains("jungle") { return 0x9A6B36 }
        if name.contains("acacia") { return 0xA85A32 }
        if name.contains("mangrove") { return 0x74332F }
        if name.contains("cherry") { return 0xD28E8E }
        if name.contains("bamboo") { return 0xA9B744 }
        if name.contains("crimson") { return 0x7C334A }
        if name.contains("warped") { return 0x247A75 }
        if name.contains("oak") { return 0x9B743F }
        if isGenericWood(name) { return 0x8B6336 }

        // Nether and End.
        if name.contains("netherrack") { return 0x6E2B2B }
        if name.contains("magma") { return 0xA44720 }
        if name.contains("glowstone") { return 0xD89B4B }
        if name.contains("shroomlight") || name.contains("froglight") { return 0xE2B86A }
        if name.contains("nether_wart") { return 0x7A2530 }
        if name.contains("nether_brick") { return 0x4A1E25 }
        if name.hasSuffix(":portal") { return 0x6E3A8F }
        if name.contains("end_stone") || name.contains("end_brick") { return 0xD5D69A }
        if name.contains("purpur") { return 0xA86F9E }
        if name.contains("chorus") { return 0x8B5A89 }

        // Copper/metal/gem blocks and distinctive decorative blocks.
        if name.contains("oxidized_copper") { return 0x4F9C85 }
        if name.contains("weathered_copper") { return 0x6D8F75 }
        if name.contains("exposed_copper") { return 0xA66B4A }
        if name.contains("copper") { return 0xC46C43 }
        if name.contains("raw_iron_block") { return 0xC9A18B }
        if name.contains("raw_gold_block") { return 0xD5B24C }
        if name.contains("raw_copper_block") { return 0xA86245 }
        if name.contains("gold_block") { return 0xE5BE32 }
        if name.contains("iron_block") { return 0xC8C5BC }
        if name.contains("diamond_block") { return 0x53C8C2 }
        if name.contains("emerald_block") { return 0x32B85A }
        if name.contains("lapis_block") { return 0x3459A8 }
        if name.contains("redstone_block") { return 0xB52A24 }
        if name.contains("coal_block") { return 0x303030 }
        if name.contains("obsidian") { return name.contains("glowing") ? 0x563D76 : 0x241B35 }
        if name.contains("amethyst") { return 0x8B5CB5 }
        if name.contains("bone_block") { return 0xD8D2B7 }
        if name.contains("sponge") { return 0xC9BC3B }
        if name.contains("sea_lantern") { return 0xC8DED2 }
        if name.contains("resin") { return 0xC65F2C }

        // Brick must be near the end: many unrelated material names contain "brick".
        if name == "minecraft:brick_block" || name == "minecraft:bricks" || name.contains(":brick_stairs")
            || name.contains(":brick_slab") || name.contains(":brick_wall") {
            return 0x9B5146
        }

        // Functional blocks.  These used to fall through to a random hash colour.
        if name.contains("redstone_lamp") { return name.contains("lit_") ? 0xB06F32 : 0x6B4530 }
        if name.contains("tnt") { return 0xB94A3F }
        if name.contains("bookshelf") { return 0x795533 }
        if name.contains("chest") || name.contains("barrel") { return 0x8B5A2B }
        if name.contains("crafting_table") || name.contains("jukebox") || name.contains("noteblock") { return 0x79502F }
        if name.contains("furnace") || name.contains("dispenser") || name.contains("dropper")
            || name.contains("observer") || name.contains("stonecutter") || name.contains("crafter") {
            return 0x666666
        }
        if name.contains("piston") { return 0x8A7A58 }
        if name.contains("hopper") || name.contains("anvil") || name.contains("cauldron") { return 0x55585A }
        if name.contains("rail") { return name.contains("golden") || name.contains("powered") ? 0xB89C43 : 0x807B70 }
        if name.contains("torch") || name.contains("lantern") || name.contains("campfire") { return 0xD39A43 }
        if name.hasSuffix(":fire") { return 0xE55A1C }
        if name.contains("web") { return 0xD9D9D9 }
        if name.contains("cake") { return 0xE5D0B4 }
        if name.contains("beacon") { return 0x9EDADC }
        if name.contains("enchanting_table") { return 0x5A3349 }
        if name.contains("mob_spawner") || name.contains("spawner") { return 0x3F4B48 }
        if name.contains("command_block") { return 0xB98168 }
        if name.contains("structure_block") { return 0x67566D }

        if name.contains("quartz") { return 0xD7D4CB }
        if name.contains("stone") { return 0x777777 }
        return nil
    }

    /// Colours for blocks whose identifier is easily captured by the wrong broad family, or
    /// whose dominant appearance is distinctive enough to deserve an explicit map colour.
    /// Keep this function exact/prefix-oriented; broad material fallbacks belong in `rgbHex`.
    private static func specialSemanticRGB(_ name: String) -> UInt32? {
        switch name {
        // End / obsidian family.
        case "minecraft:ender_chest": return 0x234342
        case "minecraft:crying_obsidian": return 0x35234F
        case "minecraft:respawn_anchor": return 0x40314F
        case "minecraft:end_bricks", "minecraft:end_stone_bricks": return 0xD0D18F
        case "minecraft:chorus_flower": return 0xA565A0

        // Redstone: these all used to become generic stone/torch colours.
        case "minecraft:redstone_wire": return 0xA32222
        case "minecraft:redstone_torch": return 0xC53A2F
        case "minecraft:unlit_redstone_torch": return 0x68302B

        // Containers and workstation blocks.
        case "minecraft:trapped_chest": return 0x8A4B29
        case "minecraft:flower_pot", "minecraft:decorated_pot": return 0x9D563D
        case "minecraft:lectern": return 0x8A6539
        case "minecraft:loom": return 0x9A7A4F
        case "minecraft:cartography_table": return 0x8C7152
        case "minecraft:fletching_table": return 0xA38857
        case "minecraft:smithing_table": return 0x4F514C
        case "minecraft:composter": return 0x72502C
        case "minecraft:smoker": return 0x5A5149
        case "minecraft:beehive": return 0xB88935
        case "minecraft:bee_nest": return 0xD2A33C

        // Distinct utility / metal blocks.
        case "minecraft:bell": return 0xD0A43A
        case "minecraft:conduit": return 0x5D9B90
        case "minecraft:lodestone": return 0x707575
        case "minecraft:chain": return 0x555B60
        case "minecraft:lightning_rod": return 0xB76A46
        case "minecraft:target": return 0xD8C9AA
        case "minecraft:heavy_core": return 0x4F5355
        case "minecraft:vault": return 0x59645D
        case "minecraft:ominous_vault": return 0x444A46
        case "minecraft:jigsaw": return 0xA58D73
        case "minecraft:barrier": return 0xC95B5B

        // Honey / eggs / other recognizable decorative blocks.
        case "minecraft:honey_block": return 0xD79A26
        case "minecraft:honeycomb_block": return 0xC77B1E
        case "minecraft:turtle_egg": return 0xD6D4B0
        case "minecraft:sniffer_egg": return 0x52766C
        case "minecraft:frog_spawn": return 0x82967F
        case "minecraft:suspicious_sand": return 0xC8B783

        // Legacy aliases whose old identifiers pre-date modern snake_case.
        case "minecraft:sealantern": return 0xC8DED2
        case "minecraft:invisiblebedrock": return 0x3A3A3A
        case "minecraft:silver_glazed_terracotta": return dyeRGB[8]

        // Crop stems and small vegetation should not inherit the fruit/wood colour.
        case "minecraft:pumpkin_stem", "minecraft:melon_stem",
             "minecraft:attached_pumpkin_stem", "minecraft:attached_melon_stem": return 0x6F8138
        case "minecraft:cactus_flower": return 0xE698A8
        case "minecraft:torchflower": return 0xD98232
        case "minecraft:torchflower_crop": return 0x718D3B
        case "minecraft:pitcher_plant": return 0x668B46
        case "minecraft:pitcher_crop": return 0x6C8A42
        case "minecraft:spore_blossom": return 0xA86F8B
        case "minecraft:azalea": return 0x56853E
        case "minecraft:flowering_azalea": return 0x6E8A4B
        case "minecraft:big_dripleaf", "minecraft:small_dripleaf": return 0x4E7E3A
        case "minecraft:hanging_roots": return 0x7B5A3A
        case "minecraft:glow_lichen": return 0x66796D
        case "minecraft:leaf_litter": return 0x806744
        case "minecraft:mangrove_propagule": return 0x688844
        case "minecraft:mangrove_roots": return 0x6B4A34
        case "minecraft:muddy_mangrove_roots": return 0x55483E
        case "minecraft:scaffolding": return 0xB79A50

        // Pale-garden blocks.
        case "minecraft:pale_moss_block", "minecraft:pale_moss_carpet": return 0x87947F
        case "minecraft:pale_hanging_moss": return 0x7D8A76
        case "minecraft:creaking_heart": return 0x75664E
        case "minecraft:open_eyeblossom": return 0xC68A35
        case "minecraft:closed_eyeblossom", "minecraft:eyeblossom": return 0x77776C

        // Nether blocks where the broad torch/vine/stone rule gives the wrong hue.
        case "minecraft:soul_fire", "minecraft:soul_torch", "minecraft:soul_lantern",
             "minecraft:soul_campfire": return 0x53BEC2
        case "minecraft:weeping_vines", "minecraft:weeping_vines_plant": return 0x8C2D3E
        case "minecraft:twisting_vines", "minecraft:twisting_vines_plant": return 0x26867B
        case "minecraft:nether_sprouts": return 0x348779
        case "minecraft:ancient_debris": return 0x5A4038
        case "minecraft:netherite_block": return 0x454146
        case "minecraft:gilded_blackstone": return 0x4E4434
        case "minecraft:red_nether_brick", "minecraft:red_nether_bricks": return 0x672934

        // Transparent/special light blocks.
        case "minecraft:tinted_glass": return 0x4B4654
        case "minecraft:light_block", "minecraft:light": return 0xEEE7A0

        // Froglights have deliberately different vanilla hues.
        case "minecraft:ochre_froglight": return 0xE4C66C
        case "minecraft:verdant_froglight": return 0xC4DDB1
        case "minecraft:pearlescent_froglight": return 0xD7B9D3

        default: break
        }

        // Coral is a large block family and deserves semantic colour rather than fallback hashes.
        if name.contains("dead_") && name.contains("coral") { return 0x77716D }
        if name.contains("tube_coral") { return 0x315FC4 }
        if name.contains("brain_coral") { return 0xD4689C }
        if name.contains("bubble_coral") { return 0x9D55B8 }
        if name.contains("fire_coral") { return 0xB94A4A }
        if name.contains("horn_coral") { return 0xD6C547 }

        // Modern bamboo building blocks are warmer than the live bamboo plant.
        if name.contains("bamboo_planks") || name.contains("bamboo_mosaic")
            || name.contains("bamboo_door") || name.contains("bamboo_trapdoor")
            || name.contains("bamboo_stairs") || name.contains("bamboo_slab")
            || name.contains("bamboo_fence") || name.contains("bamboo_button")
            || name.contains("bamboo_pressure_plate") || name.contains("bamboo_sign") {
            return 0xB5A256
        }

        // Generic vegetation added by newer Bedrock versions. Exact distinctive plants above
        // still win, while these rules keep newly introduced bushes/grasses out of hash colours.
        if name.contains("sweet_berry_bush") { return 0x4D7839 }
        if name.contains("firefly_bush") { return 0x557E42 }
        if name.contains("dry_grass") { return 0x9B874B }
        if name.contains("wildflowers") { return 0xB89A4B }
        if name.contains("bush") { return 0x557A3E }

        return nil
    }

    /// Returns a stable, muted RGB for custom/unknown blocks.
    static func fallbackRGB(for identifier: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in normalized(identifier).utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        // Keep every channel in a readable mid-range.  This is intentionally not a semantic
        // colour; it only gives unknown/custom blocks a deterministic identity.
        let r = UInt32(72 + (hash & 0x5F))
        let g = UInt32(72 + ((hash >> 8) & 0x5F))
        let b = UInt32(72 + ((hash >> 16) & 0x5F))
        return (min(r, 167) << 16) | (min(g, 167) << 8) | min(b, 167)
    }

    private static func normalized(_ identifier: String) -> String {
        BedrockBlockIdentifier.normalized(identifier)
    }

    private static func legacyVariantRGB(id: UInt16, data: UInt8) -> UInt32? {
        let meta = Int(data & 0x0F)
        switch id {
        case 1: // stone variants
            switch meta & 0x07 {
            case 1, 2: return 0x95604C // granite / polished granite
            case 3, 4: return 0xC9C9C5 // diorite
            case 5, 6: return 0x7D7D7D // andesite
            default: return 0x777777
            }
        case 3: // dirt / coarse dirt / podzol
            return meta == 2 ? 0x6B4B2A : 0x76502B
        case 5: return woodRGB(speciesIndex: meta & 0x07)
        case 12: return meta == 1 ? 0xB65A27 : 0xDEC98A
        case 17: return woodRGB(speciesIndex: meta & 0x03)
        case 18: return leafRGB(speciesIndex: meta & 0x03)
        case 35, 160, 171, 218, 236, 237, 241, 254:
            let base = dyeRGB[meta]
            if id == 95 || id == 160 || id == 241 || id == 254 { return blend(base, with: 0xE8F1F2, percentSecond: 24) }
            if id == 237 { return blend(base, with: 0xC8C8C8, percentSecond: 10) }
            return base
        case 43, 44:
            switch meta & 0x07 {
            case 1: return 0xD9C58B
            case 2: return 0x8B6336
            case 3: return 0x686868
            case 4: return 0x9B5146
            case 5: return 0x777777
            case 6: return 0xD7D4CB
            case 7: return 0x4A1E25
            default: return 0x777777
            }
        case 159: return terracottaRGB[meta]
        case 161: return leafRGB(speciesIndex: (meta & 0x01) + 4)
        case 162: return woodRGB(speciesIndex: (meta & 0x01) + 4)
        default: return nil
        }
    }

    private static func dyedFamilyRGB(_ name: String) -> UInt32? {
        let dyeIndex = dyeIndex(in: name)

        if name.contains("terracotta") || name.contains("hardened_clay") {
            if name.contains("glazed_terracotta") {
                return dyeIndex.map { dyeRGB[$0] } ?? 0x985E4B
            }
            return dyeIndex.map { terracottaRGB[$0] } ?? 0x985E4B
        }

        let usesDye = name.contains("wool") || name.contains("carpet") || name.contains("concrete")
            || name.contains("stained_glass") || name.contains("shulker_box") || name.contains("candle")
            || name.contains("_bed") || name.contains("banner")
        guard usesDye else { return nil }
        if name.contains("shulker_box"), dyeIndex == nil { return 0x8B5C8F }

        let base = dyeIndex.map { dyeRGB[$0] } ?? dyeRGB[0]
        if name.contains("stained_glass") { return blend(base, with: 0xE8F1F2, percentSecond: 24) }
        if name.contains("concrete_powder") { return blend(base, with: 0xC8C8C8, percentSecond: 10) }
        return base
    }

    private static func dyeIndex(in name: String) -> Int? {
        for (token, index) in dyeNames where name.contains(token) { return index }
        return nil
    }

    private static func isGenericWood(_ name: String) -> Bool {
        if name.contains(":wooden_") { return true }
        let exact: Set<String> = [
            "minecraft:planks", "minecraft:log", "minecraft:log2",
            "minecraft:fence", "minecraft:fence_gate", "minecraft:trapdoor",
            "minecraft:standing_sign", "minecraft:wall_sign", "minecraft:ladder",
            "minecraft:wooden_slab", "minecraft:double_wooden_slab"
        ]
        return exact.contains(name)
    }

    private static func woodRGB(speciesIndex: Int) -> UInt32 {
        switch speciesIndex {
        case 1: return 0x6B4A2B // spruce
        case 2: return 0xC4B87A // birch
        case 3: return 0x9A6B36 // jungle
        case 4: return 0xA85A32 // acacia
        case 5: return 0x4B3422 // dark oak
        default: return 0x9B743F // oak
        }
    }

    private static func leafRGB(speciesIndex: Int) -> UInt32 {
        switch speciesIndex {
        case 1: return 0x426B46
        case 2: return 0x6F8F46
        case 3: return 0x2E7D32
        case 4: return 0x507D2A
        case 5: return 0x2E5D2E
        default: return 0x3F7D32
        }
    }

    private static func blend(_ first: UInt32, with second: UInt32, percentSecond: UInt32) -> UInt32 {
        let p = min(percentSecond, 100)
        let q = 100 - p
        func channel(_ shift: UInt32) -> UInt32 {
            let a = (first >> shift) & 0xFF
            let b = (second >> shift) & 0xFF
            return (a * q + b * p + 50) / 100
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }
}
