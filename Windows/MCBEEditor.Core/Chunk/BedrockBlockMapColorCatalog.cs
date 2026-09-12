using MCBEEditor.Core.Nbt;

namespace MCBEEditor.Core.Chunk;

/// <summary>
/// UIKit/WPF-independent map colours shared by the Windows map renderer.
/// The rules intentionally mirror the current iOS BedrockBlockMapColorCatalog
/// for the high-impact block families used by surface rendering.
/// </summary>
public static class BedrockBlockMapColorCatalog
{
    private static Func<string, uint?>? _overrideProvider;

    /// <summary>
    /// Optional application-provided colour override lookup. The lookup receives
    /// the original Bedrock identifier, never a render-only state variant, so
    /// Textures/Colors.txt semantics stay identical to the iOS implementation.
    /// </summary>
    public static Func<string, uint?>? OverrideProvider
    {
        get => System.Threading.Volatile.Read(ref _overrideProvider);
        set => System.Threading.Volatile.Write(ref _overrideProvider, value);
    }

    public const uint AirRgb = 0xE5E5E5;
    public const uint UngeneratedLineRgb = 0xA8A8A8;
    public const uint MineralBackgroundRgb = 0x000000;

    public static bool IsHighlightedOre(string identifier)
    {
        var name = Normalized(identifier);
        return name.Contains("_ore", StringComparison.Ordinal)
            || name.Contains("ancient_debris", StringComparison.Ordinal)
            || name.Contains("raw_iron_block", StringComparison.Ordinal)
            || name.Contains("raw_gold_block", StringComparison.Ordinal)
            || name.Contains("raw_copper_block", StringComparison.Ordinal)
            || name.Contains("amethyst_cluster", StringComparison.Ordinal);
    }

    public static uint OreColor(string identifier)
    {
        var name = Normalized(identifier);
        if (name.Contains("diamond", StringComparison.Ordinal)) return 0x33EBEB;
        if (name.Contains("emerald", StringComparison.Ordinal)) return 0x1AD952;
        if (name.Contains("redstone", StringComparison.Ordinal)) return 0xE61A14;
        if (name.Contains("lapis", StringComparison.Ordinal)) return 0x264DE6;
        if (name.Contains("gold", StringComparison.Ordinal)) return 0xFAC214;
        if (name.Contains("iron", StringComparison.Ordinal)) return 0xD1AD94;
        if (name.Contains("copper", StringComparison.Ordinal)) return 0xC7632E;
        if (name.Contains("coal", StringComparison.Ordinal)) return 0x2E2E2E;
        if (name.Contains("quartz", StringComparison.Ordinal)) return 0xEBDCCA;
        if (name.Contains("ancient_debris", StringComparison.Ordinal)) return 0x6B3829;
        if (name.Contains("amethyst", StringComparison.Ordinal)) return 0x944DDB;
        return IsAir(name) ? MineralBackgroundRgb : 0x9C27B0;
    }

    private static readonly uint[] DyeRgb =
    [
        0xF4F4F4, 0xF9801D, 0xC64FBD, 0x3AAFD9,
        0xFED83D, 0x70B919, 0xF38BAA, 0x474F52,
        0x9D9D97, 0x169C9C, 0x8932B8, 0x3C44AA,
        0x835432, 0x5E7C16, 0xB02E26, 0x1D1D21
    ];

    private static readonly uint[] TerracottaRgb =
    [
        0xD1B1A1, 0x9F5224, 0x95576C, 0x706C8A,
        0xBA8524, 0x677535, 0xA04D4E, 0x392923,
        0x876B62, 0x575C5C, 0x7A4958, 0x4C3E5C,
        0x4C3223, 0x4C522A, 0x8E3C2E, 0x251610
    ];

    private static readonly (string Token, int Index)[] DyeNames =
    [
        ("light_blue", 3), ("light_gray", 8), ("magenta", 2), ("orange", 1),
        ("yellow", 4), ("lime", 5), ("pink", 6), ("silver", 8), ("gray", 7),
        ("cyan", 9), ("purple", 10), ("blue", 11), ("brown", 12),
        ("green", 13), ("red", 14), ("black", 15), ("white", 0)
    ];

    public static uint ColorFor(BedrockBlockState? state)
    {
        if (state is null) return AirRgb;
        var original = Normalized(state.Name);
        var external = OverrideProvider?.Invoke(original);
        if (external.HasValue) return external.Value;

        var variant = VariantIdentifier(state);
        return RgbHex(variant, state.LegacyId, state.LegacyData)
               ?? RgbHex(original, state.LegacyId, state.LegacyData)
               ?? FallbackRgb(original);
    }

    public static bool IsAir(string identifier)
    {
        var name = Normalized(identifier);
        return name is "minecraft:air" or "minecraft:cave_air" or "minecraft:void_air" or "legacy:0:0";
    }

    public static bool IsWater(string identifier)
    {
        var name = Normalized(identifier);
        return name is "minecraft:water" or "minecraft:flowing_water" || name.EndsWith(":bubble_column", StringComparison.Ordinal);
    }

    public static bool IsLava(string identifier)
    {
        var name = Normalized(identifier);
        return name is "minecraft:lava" or "minecraft:flowing_lava";
    }

    public static uint? RgbHex(string identifier, ushort? legacyId = null, byte? legacyData = null)
    {
        var name = Normalized(identifier);
        if (IsAir(name)) return AirRgb;
        if (legacyId is ushort id)
        {
            var variant = LegacyVariantRgb(id, legacyData ?? 0);
            if (variant.HasValue) return variant;
            var baseColor = LegacyBaseRgb(id);
            if (baseColor.HasValue) return baseColor;
        }

        if (IsWater(name)) return 0x337CCB;
        if (IsLava(name)) return 0xF05A19;
        if (SpecialSemanticRgb(name) is uint special) return special;
        if (DyedFamilyRgb(name) is uint dyed) return dyed;

        if (name == "minecraft:bed") return 0xB02E26;
        if (ContainsAny(name, "iron_door", "iron_trapdoor", "iron_bars")) return 0xC8C5BC;
        if (name.Contains("light_weighted_pressure_plate")) return 0xC9A93C;
        if (name.Contains("heavy_weighted_pressure_plate")) return 0xAAA8A1;
        if (ContainsAny(name, "repeater", "comparator")) return 0x7B706A;
        if (name.Contains("daylight_detector")) return 0x8A6A42;
        if (name.EndsWith(":lever", StringComparison.Ordinal) || name.Contains("tripwire_hook")) return 0x77706A;
        if (ContainsAny(name, "tripwire", "trip_wire")) return 0xA0A0A0;
        if (name.Contains("brewing_stand")) return 0x5A5042;
        if (name.Contains("dragon_egg")) return 0x241B35;
        if (name.Contains("skull")) return 0x8D8D83;
        if (name.Contains("slime") && !name.Contains("slime_chunk")) return 0x72B85E;
        if (name.Contains("double_plant")) return 0x5E913D;
        if (name.Contains("end_portal_frame")) return 0x99996A;
        if (ContainsAny(name, "end_portal", "end_gateway")) return 0x17151E;
        if (name.Contains("end_rod")) return 0xE2DDD1;
        if (name.EndsWith(":allow", StringComparison.Ordinal)) return 0x61A85B;
        if (name.EndsWith(":deny", StringComparison.Ordinal)) return 0xA85B5B;
        if (name.Contains("border_block")) return 0xB56C60;
        if (name.Contains("chalkboard")) return 0x343331;
        if (ContainsAny(name, "chemistry_table", "compound_creator", "lab_table", "material_reducer", "element_constructor", "camera")) return 0x5E6265;
        if (name.Contains("chemical_heat")) return 0xD46E35;
        if (name.Contains("netherreactor")) return 0x455267;
        if (name.Contains("item_frame") || name == "minecraft:frame") return 0x835432;
        if (name.Contains("info_update")) return 0xB06DA8;
        if (ContainsAny(name, "movingblock", "moving_block")) return 0x777777;
        if (name.Contains("monster_egg") || name.Contains("infested_"))
        {
            if (name.Contains("deepslate")) return 0x3F4245;
            if (name.Contains("mossy")) return 0x5E7157;
            if (name.Contains("cobblestone")) return 0x686868;
            return 0x777777;
        }
        if (name.Contains(":element_")) return 0x8B8B8B;

        if (name.EndsWith(":structure_void", StringComparison.Ordinal)) return AirRgb;
        if (name.Contains("glass")) return 0xD6E9EC;

        if (ContainsAny(name, "mossy_cobblestone", "mossy_stone_brick")) return 0x5E7157;
        if (name.Contains("soul_sand")) return 0x544034;
        if (name.Contains("soul_soil")) return 0x4B3A30;
        if (name.Contains("red_sandstone")) return 0xB96A39;
        if (name.Contains("sandstone")) return 0xD9C58B;
        if (name.EndsWith(":red_sand", StringComparison.Ordinal) || name.Contains(":red_sand_")) return 0xB65A27;
        if (name.EndsWith(":sand", StringComparison.Ordinal) || name.Contains(":sand_")) return 0xDEC98A;

        if (name.Contains("mangrove_leaves")) return 0x3E7138;
        if (ContainsAny(name, "azalea_leaves_flowered", "flowering_azalea_leaves")) return 0x718954;
        if (name.Contains("azalea_leaves")) return 0x4F8A3A;
        if (name.Contains("red_poplar_leaves")) return 0xA84C3F;
        if (name.Contains("orange_poplar_leaves")) return 0xC67835;
        if (name.Contains("yellow_poplar_leaves")) return 0xC5B34A;
        if (ContainsAny(name, "cherry_leaves", "pink_petals")) return 0xECA7B7;
        if (name.Contains("pale_oak_leaves")) return 0x869280;
        if (name.Contains("spruce_leaves")) return 0x426B46;
        if (name.Contains("birch_leaves")) return 0x6F8F46;
        if (name.Contains("jungle_leaves")) return 0x2E7D32;
        if (name.Contains("acacia_leaves")) return 0x507D2A;
        if (ContainsAny(name, "dark_oak_leaves", "darkoak_leaves")) return 0x2E5D2E;
        if (name.Contains("oak_leaves")) return 0x3F7D32;
        if (name.Contains("leaves")) return 0x3F7D32;
        if (name.EndsWith(":vine", StringComparison.Ordinal) || name.Contains(":vines")) return 0x2E8B3A;
        if (ContainsAny(name, "moss_block", "moss_carpet")) return 0x5E9B3B;
        if (ContainsAny(name, "grass_block", "short_grass", "tall_grass", "tallgrass", "fern") || name == "minecraft:grass") return 0x5E9B3B;
        if (ContainsAny(name, "lily_pad", "waterlily")) return 0x347A38;
        if (name.Contains("cactus")) return 0x3F7F3C;
        if (ContainsAny(name, "sugar_cane", "reeds")) return 0x79A94A;
        if (name.Contains("dried_kelp_block")) return 0x39452D;
        if (ContainsAny(name, "kelp", "seagrass")) return 0x2E6C3A;
        if (name.Contains("sea_pickle")) return 0x71813C;
        if (name.Contains("sapling")) return 0x4C7E32;
        if (name.Contains("deadbush")) return 0x78603A;
        if (name.Contains("brown_mushroom")) return 0x8B684F;
        if (name.Contains("red_mushroom")) return 0xB84A42;
        if (name.Contains("mushroom")) return 0x9B7665;
        if (ContainsAny(name, "wheat", "hay_block")) return 0xC6A83A;
        if (ContainsAny(name, "beetroot", "carrots", "potatoes")) return 0x65913C;
        if (name.Contains("melon")) return 0x76A83D;
        if (name.Contains("pumpkin")) return 0xC87525;
        if (name.Contains("cocoa")) return 0x81522D;
        if (FlowerRgb(name) is uint flower) return flower;
        if (ContainsAny(name, "flower", "blossom")) return 0xC9828E;
        if (name.Contains("mycelium")) return 0x705A6A;
        if (name.Contains("podzol")) return 0x6B4B2A;
        if (name.Contains("mud_brick")) return 0x77645A;
        if (name.EndsWith(":mud", StringComparison.Ordinal) || name.Contains(":packed_mud")) return 0x4B4648;
        if (ContainsAny(name, "dirt", "farmland", "grass_path")) return 0x76502B;
        if (name.EndsWith(":clay", StringComparison.Ordinal)) return 0x9AA6B1;
        if (name.Contains("gravel")) return 0x77716D;

        if (name.Contains("powder_snow") || name.EndsWith(":snow", StringComparison.Ordinal) || name.Contains("snow_layer")) return 0xF1F6F7;
        if (name.Contains("blue_ice")) return 0x74A9FF;
        if (name.Contains("packed_ice")) return 0x8DB4EA;
        if (name.Contains("frosted_ice")) return 0xA9C7EA;
        if (name.EndsWith(":ice", StringComparison.Ordinal)) return 0xB6D7F2;

        if (name.Contains("bedrock")) return 0x3A3A3A;
        if (name.Contains("cinnabar")) return name.Contains("polished") ? 0xB45B49u : 0xA64A3Cu;
        if (name.Contains("sulfur"))
        {
            if (name.Contains("potent_sulfur")) return 0xE0C93A;
            if (ContainsAny(name, "polished", "brick")) return 0xCDBE4A;
            return 0xD8CB4B;
        }
        if (name.Contains("sculk")) return 0x12383B;
        if (name.Contains("dripstone")) return 0x6F594C;
        if (name.Contains("calcite")) return 0xD7D4CB;
        if (name.Contains("granite")) return 0x95604C;
        if (name.Contains("diorite")) return 0xC9C9C5;
        if (name.Contains("andesite")) return 0x7D7D7D;
        if (name.Contains("tuff")) return 0x59645D;
        if (name.Contains("deepslate")) return name.Contains("_ore") ? 0x535557u : 0x3F4245u;
        if (name.Contains("blackstone")) return 0x2F292F;
        if (name.Contains("basalt")) return 0x4D4A4A;
        if (name.Contains("prismarine"))
        {
            if (name.Contains("dark_prismarine")) return 0x335B51;
            if (name.Contains("brick")) return 0x63A89A;
            return 0x5E9B8B;
        }
        if (name.Contains("cobblestone")) return 0x686868;
        if (ContainsAny(name, "stone_brick", "stonebrick")) return 0x777777;

        if (name.Contains("_ore"))
        {
            if (ContainsAny(name, "nether", "quartz")) return 0x773333;
            if (name.Contains("copper")) return 0x88766D;
            if (name.Contains("iron")) return 0x85807A;
            if (name.Contains("gold")) return 0x837C63;
            if (name.Contains("redstone")) return 0x765F5E;
            if (name.Contains("lapis")) return 0x626B7D;
            if (name.Contains("diamond")) return 0x698080;
            if (name.Contains("emerald")) return 0x687D6B;
            if (name.Contains("coal")) return 0x5C5C5C;
            return 0x777777;
        }

        if (name.Contains("pale_oak")) return 0xC6BEA7;
        if (ContainsAny(name, "dark_oak", "darkoak")) return 0x4B3422;
        if (name.Contains("spruce")) return 0x6B4A2B;
        if (name.Contains("birch")) return 0xC4B87A;
        if (name.Contains("jungle")) return 0x9A6B36;
        if (name.Contains("acacia")) return 0xA85A32;
        if (name.Contains("mangrove")) return 0x74332F;
        if (name.Contains("cherry")) return 0xD28E8E;
        if (name.Contains("bamboo")) return 0xA9B744;
        if (name.Contains("crimson")) return 0x7C334A;
        if (name.Contains("warped")) return 0x247A75;
        if (name.Contains("poplar")) return 0xA88B61;
        if (name.Contains("oak")) return 0x9B743F;
        if (IsGenericWood(name)) return 0x8B6336;

        if (name.Contains("netherrack")) return 0x6E2B2B;
        if (name.Contains("magma")) return 0xA44720;
        if (name.Contains("glowstone")) return 0xD89B4B;
        if (ContainsAny(name, "shroomlight", "froglight")) return 0xE2B86A;
        if (name.Contains("nether_wart")) return 0x7A2530;
        if (name.Contains("red_nether_brick")) return 0x672934;
        if (name.Contains("nether_brick")) return 0x4A1E25;
        if (name.EndsWith(":portal", StringComparison.Ordinal)) return 0x6E3A8F;
        if (ContainsAny(name, "end_stone", "end_brick")) return 0xD5D69A;
        if (name.Contains("purpur")) return 0xA86F9E;
        if (name.Contains("chorus")) return 0x8B5A89;

        if (name.Contains("raw_iron_block")) return 0xC9A18B;
        if (name.Contains("raw_gold_block")) return 0xD5B24C;
        if (name.Contains("raw_copper_block")) return 0xA86245;
        if (name.Contains("copper"))
        {
            if (name.Contains("oxidized")) return 0x4F9C85;
            if (name.Contains("weathered")) return 0x6D8F75;
            if (name.Contains("exposed")) return 0xA66B4A;
            return 0xC46C43;
        }
        if (name.Contains("gold_block")) return 0xE5BE32;
        if (name.Contains("iron_block")) return 0xC8C5BC;
        if (name.Contains("diamond_block")) return 0x53C8C2;
        if (name.Contains("emerald_block")) return 0x32B85A;
        if (name.Contains("lapis_block")) return 0x3459A8;
        if (name.Contains("redstone_block")) return 0xB52A24;
        if (name.Contains("coal_block")) return 0x303030;
        if (name.Contains("obsidian")) return name.Contains("glowing") ? 0x563D76u : 0x241B35u;
        if (name.Contains("amethyst")) return 0x8B5CB5;
        if (name.Contains("bone_block")) return 0xD8D2B7;
        if (name.Contains("wet_sponge")) return 0x9E9B3F;
        if (name.Contains("sponge")) return 0xC9BC3B;
        if (name.Contains("sea_lantern")) return 0xC8DED2;
        if (name.Contains("resin")) return 0xC65F2C;

        if ((name is "minecraft:brick_block" or "minecraft:bricks") || ContainsAny(name, ":brick_stairs", ":brick_slab", ":brick_wall")) return 0x9B5146;

        if (name.Contains("redstone_lamp")) return name.Contains("lit_") ? 0xB06F32u : 0x6B4530u;
        if (name.Contains("tnt")) return 0xB94A3F;
        if (name.Contains("bookshelf")) return 0x795533;
        if (ContainsAny(name, "chest", "barrel")) return 0x8B5A2B;
        if (ContainsAny(name, "crafting_table", "jukebox", "noteblock", "note_block")) return 0x79502F;
        if (ContainsAny(name, "furnace", "dispenser", "dropper", "observer", "stonecutter", "crafter")) return 0x666666;
        if (name.Contains("piston")) return 0x8A7A58;
        if (ContainsAny(name, "hopper", "anvil", "cauldron")) return 0x55585A;
        if (name.Contains("rail")) return ContainsAny(name, "golden", "powered") ? 0xB89C43u : 0x807B70u;
        if (name.EndsWith(":campfire", StringComparison.Ordinal)) return 0x8B5C36;
        if (ContainsAny(name, "torch", "lantern")) return 0xD39A43;
        if (name.EndsWith(":fire", StringComparison.Ordinal)) return 0xE55A1C;
        if (name.Contains("web")) return 0xD9D9D9;
        if (name.Contains("cake")) return 0xE5D0B4;
        if (name.Contains("beacon")) return 0x9EDADC;
        if (name.Contains("enchanting_table")) return 0x5A3349;
        if (ContainsAny(name, "mob_spawner", "spawner")) return 0x3F4B48;
        if (name.Contains("command_block")) return 0xB98168;
        if (name.Contains("structure_block")) return 0x67566D;
        if (name.Contains("quartz")) return 0xD7D4CB;
        if (name.Contains("stone")) return 0x777777;
        return null;
    }

    public static uint FallbackRgb(string identifier)
    {
        uint hash = 2_166_136_261;
        foreach (var value in System.Text.Encoding.UTF8.GetBytes(Normalized(identifier)))
        {
            hash ^= value;
            hash *= 16_777_619;
        }
        var r = 72u + (hash & 0x5Fu);
        var g = 72u + ((hash >> 8) & 0x5Fu);
        var b = 72u + ((hash >> 16) & 0x5Fu);
        return (r << 16) | (g << 8) | b;
    }

    public static string VariantIdentifier(BedrockBlockState state)
    {
        var name = Normalized(state.Name);
        if (!name.StartsWith("minecraft:", StringComparison.Ordinal) || state.Nbt is null) return name;
        var states = state.Nbt.CompoundValue("states") as NbtCompoundValue;
        if (states is null || states.Tags.Count == 0) return name;
        var properties = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var tag in states.Tags)
            if (tag.Value is NbtStringValue value) properties[tag.Name.ToLowerInvariant()] = value.Value.ToLowerInvariant();
        if (properties.Count == 0) return name;

        var path = name["minecraft:".Length..];
        string? Value(string key) => properties.TryGetValue(key, out var value) ? value : null;
        static string Block(string path) => "minecraft:" + path;

        switch (path)
        {
            case "wool": case "carpet": case "concrete": case "concretepowder": case "concrete_powder":
            case "stained_glass": case "stained_glass_pane": case "hard_stained_glass": case "hard_stained_glass_pane":
            case "stained_hardened_clay": case "shulker_box":
            {
                var color = Value("color");
                if (color is not null && DyeNames.Any(item => item.Token == color))
                {
                    var dye = color == "silver" ? "light_gray" : color;
                    if (path == "stained_hardened_clay") return Block(dye + "_terracotta");
                    if (path == "concretepowder") return Block(dye + "_concrete_powder");
                    if (path is "hard_stained_glass" or "hard_stained_glass_pane") return Block("hard_" + dye + "_" + path[5..]);
                    return Block(dye + "_" + path);
                }
                break;
            }
            case "planks": case "wooden_slab": case "double_wooden_slab": case "log": case "log2": case "wood": case "leaves": case "leaves2":
            {
                var species = Value("wood_type") ?? Value("old_log_type") ?? Value("new_log_type") ?? Value("old_leaf_type") ?? Value("new_leaf_type");
                if (species is "oak" or "spruce" or "birch" or "jungle" or "acacia" or "dark_oak")
                {
                    var family = path switch { "wooden_slab" or "double_wooden_slab" => "slab", "log2" => "log", "leaves2" => "leaves", _ => path };
                    return Block(species + "_" + family);
                }
                break;
            }
            case "stone":
            {
                var type = Value("stone_type");
                if (type is "stone" or "granite" or "granite_smooth" or "diorite" or "diorite_smooth" or "andesite" or "andesite_smooth") return Block(type);
                break;
            }
            case "stonebrick": if (Value("stone_brick_type") == "mossy") return Block("mossy_stone_bricks"); break;
            case "sand": if (Value("sand_type") == "red") return Block("red_sand"); break;
            case "dirt": if (Value("dirt_type") == "coarse") return Block("coarse_dirt"); break;
            case "prismarine":
                if (Value("prismarine_block_type") == "dark") return Block("dark_prismarine");
                else if (Value("prismarine_block_type") == "bricks") return Block("prismarine_bricks");
                break;
            case "sponge": if (Value("sponge_type") == "wet") return Block("wet_sponge"); break;
            case "red_flower":
            {
                var type = Value("flower_type");
                if (type is not null && FlowerRgb(Block(type)).HasValue) return Block(type);
                break;
            }
            case "double_plant":
            {
                var type = Value("double_plant_type");
                var plant = type switch { "sunflower" => "sunflower", "syringa" => "lilac", "grass" => "tall_grass", "fern" => "large_fern", "rose" => "rose_bush", "paeonia" => "peony", _ => null };
                if (plant is not null) return Block(plant);
                break;
            }
        }
        return name;
    }

    private static uint? SpecialSemanticRgb(string name)
    {
        var exact = name switch
        {
            "minecraft:ender_chest" => 0x234342u,
            "minecraft:crying_obsidian" => 0x35234Fu,
            "minecraft:respawn_anchor" => 0x40314Fu,
            "minecraft:end_bricks" or "minecraft:end_stone_bricks" => 0xD0D18Fu,
            "minecraft:chorus_flower" => 0xA565A0u,
            "minecraft:sunflower" or "minecraft:sun_flower" => 0xE2B93Bu,
            "minecraft:redstone_wire" => 0xA32222u,
            "minecraft:redstone_torch" => 0xC53A2Fu,
            "minecraft:unlit_redstone_torch" => 0x68302Bu,
            "minecraft:command_block" => 0xB98168u,
            "minecraft:chain_command_block" => 0x5F8F69u,
            "minecraft:repeating_command_block" => 0x8266A8u,
            "minecraft:trapped_chest" => 0x8A4B29u,
            "minecraft:flower_pot" or "minecraft:decorated_pot" => 0x9D563Du,
            "minecraft:lectern" => 0x8A6539u,
            "minecraft:loom" => 0x9A7A4Fu,
            "minecraft:cartography_table" => 0x8C7152u,
            "minecraft:fletching_table" => 0xA38857u,
            "minecraft:smithing_table" => 0x4F514Cu,
            "minecraft:composter" => 0x72502Cu,
            "minecraft:smoker" => 0x5A5149u,
            "minecraft:lit_smoker" => 0x67584Bu,
            "minecraft:beehive" => 0xB88935u,
            "minecraft:bee_nest" => 0xD2A33Cu,
            "minecraft:bell" => 0xD0A43Au,
            "minecraft:conduit" => 0x5D9B90u,
            "minecraft:lodestone" => 0x707575u,
            "minecraft:chain" or "minecraft:iron_chain" => 0x555B60u,
            "minecraft:lightning_rod" => 0xB76A46u,
            "minecraft:target" => 0xD8C9AAu,
            "minecraft:heavy_core" => 0x4F5355u,
            "minecraft:vault" => 0x59645Du,
            "minecraft:ominous_vault" => 0x444A46u,
            "minecraft:jigsaw" => 0xA58D73u,
            "minecraft:barrier" => 0xC95B5Bu,
            "minecraft:unknown" => 0x8A4F9Bu,
            "minecraft:honey_block" => 0xD79A26u,
            "minecraft:honeycomb_block" => 0xC77B1Eu,
            "minecraft:turtle_egg" => 0xD6D4B0u,
            "minecraft:sniffer_egg" => 0x52766Cu,
            "minecraft:frog_spawn" => 0x82967Fu,
            "minecraft:suspicious_sand" => 0xC8B783u,
            "minecraft:suspicious_gravel" => 0x817973u,
            "minecraft:dried_ghast" => 0xC8C2B6u,
            "minecraft:glow_frame" => 0xA07843u,
            "minecraft:dragon_head" => 0x34303Au,
            "minecraft:creeper_head" => 0x5D8649u,
            "minecraft:skeleton_skull" => 0xC9C5B2u,
            "minecraft:wither_skeleton_skull" => 0x3A3538u,
            "minecraft:zombie_head" => 0x66794Cu,
            "minecraft:piglin_head" => 0x9A6953u,
            "minecraft:player_head" => 0x9A7C69u,
            "minecraft:sealantern" => 0xC8DED2u,
            "minecraft:invisiblebedrock" => 0x3A3A3Au,
            "minecraft:pumpkin_stem" or "minecraft:melon_stem" or "minecraft:attached_pumpkin_stem" or "minecraft:attached_melon_stem" => 0x6F8138u,
            "minecraft:cactus_flower" => 0xE698A8u,
            "minecraft:torchflower" => 0xD98232u,
            "minecraft:torchflower_crop" => 0x718D3Bu,
            "minecraft:pitcher_plant" => 0x668B46u,
            "minecraft:pitcher_crop" => 0x6C8A42u,
            "minecraft:spore_blossom" => 0xA86F8Bu,
            "minecraft:azalea" => 0x56853Eu,
            "minecraft:flowering_azalea" => 0x6E8A4Bu,
            "minecraft:big_dripleaf" or "minecraft:small_dripleaf" or "minecraft:small_dripleaf_block" => 0x4E7E3Au,
            "minecraft:hanging_roots" => 0x7B5A3Au,
            "minecraft:glow_lichen" => 0x66796Du,
            "minecraft:leaf_litter" => 0x806744u,
            "minecraft:mangrove_propagule" => 0x688844u,
            "minecraft:mangrove_roots" => 0x6B4A34u,
            "minecraft:muddy_mangrove_roots" => 0x55483Eu,
            "minecraft:scaffolding" => 0xB79A50u,
            "minecraft:deadbush" => 0x78603Au,
            "minecraft:red_shrub" => 0x9A5544u,
            "minecraft:mushroom_stem" => 0xC4B7A5u,
            "minecraft:cave_vines" or "minecraft:cave_vines_body_with_berries" or "minecraft:cave_vines_head_with_berries" => 0x5D843Bu,
            "minecraft:pale_moss_block" or "minecraft:pale_moss_carpet" => 0x87947Fu,
            "minecraft:pale_hanging_moss" => 0x7D8A76u,
            "minecraft:creaking_heart" => 0x75664Eu,
            "minecraft:open_eyeblossom" => 0xC68A35u,
            "minecraft:closed_eyeblossom" or "minecraft:eyeblossom" => 0x77776Cu,
            "minecraft:soul_fire" or "minecraft:soul_torch" or "minecraft:soul_lantern" or "minecraft:soul_campfire" => 0x53BEC2u,
            "minecraft:weeping_vines" or "minecraft:weeping_vines_plant" => 0x8C2D3Eu,
            "minecraft:twisting_vines" or "minecraft:twisting_vines_plant" => 0x26867Bu,
            "minecraft:nether_sprouts" => 0x348779u,
            "minecraft:crimson_fungus" => 0x9B3949u,
            "minecraft:warped_fungus" => 0x2C8B7Fu,
            "minecraft:crimson_roots" => 0x8A3141u,
            "minecraft:warped_roots" => 0x2B7E75u,
            "minecraft:ancient_debris" => 0x5A4038u,
            "minecraft:netherite_block" => 0x454146u,
            "minecraft:gilded_blackstone" => 0x4E4434u,
            "minecraft:red_nether_brick" or "minecraft:red_nether_bricks" => 0x672934u,
            "minecraft:tinted_glass" => 0x4B4654u,
            "minecraft:light_block" or "minecraft:light" => 0xEEE7A0u,
            "minecraft:jack_o_lantern" or "minecraft:lit_pumpkin" => 0xD98B28u,
            "minecraft:trial_spawner" => 0x52655Fu,
            "minecraft:crafter" => 0x76695Bu,
            "minecraft:sculk_sensor" => 0x18494Au,
            "minecraft:calibrated_sculk_sensor" => 0x3B5559u,
            "minecraft:sculk_catalyst" => 0x183D3Bu,
            "minecraft:sculk_shrieker" => 0x334746u,
            "minecraft:sculk_vein" => 0x123436u,
            "minecraft:colored_torch_red" => 0xD94A3Au,
            "minecraft:colored_torch_green" => 0x55B95Bu,
            "minecraft:colored_torch_blue" => 0x4B73D1u,
            "minecraft:colored_torch_purple" => 0x9B5BC2u,
            "minecraft:copper_torch" => 0x58A88Fu,
            "minecraft:ochre_froglight" => 0xE4C66Cu,
            "minecraft:verdant_froglight" => 0xC4DDB1u,
            "minecraft:pearlescent_froglight" => 0xD7B9D3u,
            _ => (uint?)null
        };
        if (exact.HasValue) return exact;

        if (name.Contains(":light_block_")) return 0xEEE7A0;
        if (name.Contains("lightning_rod"))
        {
            if (name.Contains("oxidized")) return 0x4F9C85;
            if (name.Contains("weathered")) return 0x6D8F75;
            if (name.Contains("exposed")) return 0xA66B4A;
            return 0xB76A46;
        }
        if (name.Contains("dead_") && name.Contains("coral")) return 0x77716D;
        if (name.Contains("tube_coral")) return 0x315FC4;
        if (name.Contains("brain_coral")) return 0xD4689C;
        if (name.Contains("bubble_coral")) return 0x9D55B8;
        if (name.Contains("fire_coral")) return 0xB94A4A;
        if (name.Contains("horn_coral")) return 0xD6C547;

        if (ContainsAny(name, "bamboo_planks", "bamboo_mosaic", "bamboo_door", "bamboo_trapdoor", "bamboo_stairs", "bamboo_slab", "bamboo_fence", "bamboo_button", "bamboo_pressure_plate", "bamboo_sign", "bamboo_shelf")) return 0xB5A256;
        if (name.Contains("sweet_berry_bush")) return 0x4D7839;
        if (name.Contains("firefly_bush")) return 0x557E42;
        if (name.Contains("dry_grass")) return 0x9B874B;
        if (name.Contains("wildflowers")) return 0xB89A4B;
        if (name.Contains("bush") && !name.Contains("deadbush") && !name.Contains("rose_bush")) return 0x557A3E;
        return null;
    }

    private static uint? LegacyVariantRgb(ushort id, byte data)
    {
        var meta = data & 0x0F;
        return id switch
        {
            1 => (meta & 0x07) switch { 1 or 2 => 0x95604Cu, 3 or 4 => 0xC9C9C5u, 5 or 6 => 0x7D7D7Du, _ => 0x777777u },
            3 => meta == 2 ? 0x6B4B2Au : 0x76502Bu,
            5 or 157 or 158 => WoodRgb(meta & 0x07),
            12 => meta == 1 ? 0xB65A27u : 0xDEC98Au,
            17 => WoodRgb(meta & 0x03),
            18 => LeafRgb(meta & 0x03),
            37 => 0xE0C83Eu,
            38 => LegacyRedFlowerRgb(meta),
            175 => LegacyDoublePlantRgb(meta),
            202 => (meta & 1) == 0 ? 0xD94A3Au : 0x55B95Bu,
            204 => (meta & 1) == 0 ? 0x4B73D1u : 0x9B5BC2u,
            35 or 160 or 171 or 218 or 236 or 237 or 241 or 254 => LegacyDyedRgb(id, meta),
            43 or 44 => (meta & 0x07) switch { 1 => 0xD9C58Bu, 2 => 0x8B6336u, 3 => 0x686868u, 4 => 0x9B5146u, 5 => 0x777777u, 6 => 0xD7D4CBu, 7 => 0x4A1E25u, _ => 0x777777u },
            159 => TerracottaRgb[meta],
            168 => meta switch { 1 => 0x335B51u, 2 => 0x63A89Au, _ => 0x5E9B8Bu },
            19 => meta == 1 ? 0x9E9B3Fu : 0xC9BC3Bu,
            161 => LeafRgb((meta & 1) + 4),
            162 => WoodRgb((meta & 1) + 4),
            _ => null
        };
    }

    private static uint LegacyDyedRgb(ushort id, int meta)
    {
        var baseColor = DyeRgb[meta];
        if (id is 160 or 241 or 254) return Blend(baseColor, 0xE8F1F2, 24);
        if (id == 237) return Blend(baseColor, 0xC8C8C8, 10);
        return baseColor;
    }

    private static uint? LegacyBaseRgb(ushort id) => id switch
    {
        0 => AirRgb, 1 => 0x777777u, 2 => 0x5E9B3Bu, 3 => 0x76502Bu, 4 => 0x686868u,
        5 => 0x9B743Fu, 7 => 0x3A3A3Au, 8 or 9 => 0x337CCBu, 10 or 11 => 0xF05A19u,
        12 => 0xDEC98Au, 13 => 0x77716Du, 14 => 0x837C63u, 15 => 0x85807Au, 16 => 0x5C5C5Cu,
        17 => 0x9B743Fu, 18 => 0x3F7D32u, 19 => 0xC9BC3Bu, 20 => 0xD6E9ECu, 21 => 0x626B7Du,
        22 => 0x3459A8u, 24 => 0xD9C58Bu, 30 => 0xD9D9D9u, 35 => 0xF4F4F4u, 37 => 0xE0C83Eu,
        38 => 0xB94A4Au, 41 => 0xE5BE32u, 42 => 0xC8C5BCu, 43 or 44 => 0x777777u,
        45 => 0x9B5146u, 46 => 0xB94A3Fu, 47 => 0x795533u, 48 => 0x5E7157u, 49 => 0x241B35u,
        50 => 0xD39A43u, 52 => 0x3F4B48u, 54 => 0x8B5A2Bu, 56 => 0x698080u, 57 => 0x53C8C2u,
        58 => 0x79502Fu, 60 => 0x76502Bu, 61 or 62 => 0x666666u, 65 => 0x8B6336u, 67 => 0x686868u,
        73 or 74 => 0x765F5Eu, 78 or 80 => 0xF1F6F7u, 79 => 0xB6D7F2u, 81 => 0x3F7F3Cu,
        82 => 0x9AA6B1u, 85 => 0x8B6336u, 86 => 0xC87525u, 87 => 0x6E2B2Bu, 88 => 0x544034u,
        89 => 0xD89B4Bu, 91 => 0xD98B28u, 95 => 0xD6E9ECu, 98 => 0x777777u, 103 => 0x76A83Du,
        110 => 0x705A6Au, 112 => 0x4A1E25u, 121 => 0xD5D69Au, 129 => 0x687D6Bu,
        133 => 0x32B85Au, 152 => 0xB52A24u, 155 => 0xD7D4CBu, 159 => 0x985E4Bu,
        168 => 0x5E9B8Bu, 169 => 0xC8DED2u, 172 => 0x985E4Bu, 173 => 0x303030u,
        174 => 0x8DB4EAu, 179 => 0xB96A39u, 201 or 202 => 0xA86F9Eu, 206 => 0xD5D69Au,
        213 => 0xA44720u, 216 => 0xD8D2B7u, 236 => 0xB98168u, 243 => 0x76502Bu,
        _ => null
    };

    private static uint? FlowerRgb(string name) => name switch
    {
        "minecraft:yellow_flower" or "minecraft:dandelion" => 0xE0C83Eu,
        "minecraft:golden_dandelion" => 0xEBC43Bu,
        "minecraft:red_flower" or "minecraft:poppy" or "minecraft:red_tulip" or "minecraft:rose_bush" => 0xB94A4Au,
        "minecraft:blue_orchid" => 0x5C91D0u, "minecraft:allium" => 0xA56BC0u,
        "minecraft:azure_bluet" => 0xDAD8CEu, "minecraft:orange_tulip" => 0xE47B2Au,
        "minecraft:white_tulip" or "minecraft:oxeye_daisy" or "minecraft:lily_of_the_valley" => 0xE6E4D8u,
        "minecraft:pink_tulip" or "minecraft:peony" => 0xE58FA8u,
        "minecraft:cornflower" => 0x5579C6u, "minecraft:wither_rose" => 0x3B2B3Eu,
        "minecraft:lilac" => 0xB57AB8u, _ => null
    };

    private static uint LegacyRedFlowerRgb(int meta) => (meta & 0x0F) switch
    {
        1 => 0x5C91D0u, 2 => 0xA56BC0u, 3 => 0xDAD8CEu, 4 => 0xB94A4Au, 5 => 0xE47B2Au,
        6 => 0xE6E4D8u, 7 => 0xE58FA8u, 8 => 0xE6E4D8u, 9 => 0x5579C6u, 10 => 0xE6E4D8u,
        _ => 0xB94A4Au
    };

    private static uint LegacyDoublePlantRgb(int meta) => (meta & 0x07) switch
    {
        0 => 0xE2B93Bu, 1 => 0xB57AB8u, 2 => 0x5E9B3Bu, 3 => 0x4F813Eu, 4 => 0xB94A4Au, 5 => 0xE58FA8u,
        _ => 0x5E913Du
    };

    private static uint? DyedFamilyRgb(string name)
    {
        if (name == "minecraft:moss_carpet") return 0x5E9B3B;
        if (name == "minecraft:straw_bed") return 0xC7A84A;
        if (name.Contains("terracotta") || name.Contains("hardened_clay"))
        {
            var dye = DyeIndex(name);
            if (name.Contains("glazed_terracotta")) return dye.HasValue ? DyeRgb[dye.Value] : 0x985E4B;
            return dye.HasValue ? TerracottaRgb[dye.Value] : 0x985E4B;
        }
        var usesDye = ContainsAny(name, "wool", "carpet", "concrete", "stained_glass", "shulker_box", "candle", "_bed", "banner");
        if (!usesDye) return null;
        var index = DyeIndex(name);
        if (name.Contains("shulker_box") && !index.HasValue) return 0x8B5C8F;
        if (name.Contains("candle") && !index.HasValue) return 0xD6C28B;
        var baseColor = DyeRgb[index ?? 0];
        if (name.Contains("stained_glass")) return Blend(baseColor, 0xE8F1F2, 24);
        if (name.Contains("concrete_powder")) return Blend(baseColor, 0xC8C8C8, 10);
        return baseColor;
    }

    private static int? DyeIndex(string name)
    {
        var colon = name.IndexOf(':');
        var path = colon >= 0 ? name[(colon + 1)..] : name;
        var material = path.StartsWith("hard_", StringComparison.Ordinal) ? path[5..] : path;
        foreach (var (token, index) in DyeNames)
            if (material.StartsWith(token + "_", StringComparison.Ordinal)) return index;
        return null;
    }

    private static bool IsGenericWood(string name)
    {
        if (name.Contains(":wooden_")) return true;
        return name is "minecraft:planks" or "minecraft:log" or "minecraft:log2" or "minecraft:fence" or "minecraft:fence_gate"
            or "minecraft:trapdoor" or "minecraft:standing_sign" or "minecraft:wall_sign" or "minecraft:ladder" or "minecraft:double_wooden_slab";
    }

    private static uint WoodRgb(int speciesIndex) => speciesIndex switch
    {
        1 => 0x6B4A2Bu, 2 => 0xC4B87Au, 3 => 0x9A6B36u, 4 => 0xA85A32u, 5 => 0x4B3422u, _ => 0x9B743Fu
    };

    private static uint LeafRgb(int speciesIndex) => speciesIndex switch
    {
        1 => 0x426B46u, 2 => 0x6F8F46u, 3 => 0x2E7D32u, 4 => 0x507D2Au, 5 => 0x2E5D2Eu, _ => 0x3F7D32u
    };

    private static uint Blend(uint first, uint second, uint percentSecond)
    {
        var p = Math.Min(percentSecond, 100u);
        var q = 100u - p;
        uint Channel(int shift)
        {
            var a = (first >> shift) & 0xFFu;
            var b = (second >> shift) & 0xFFu;
            return (a * q + b * p + 50u) / 100u;
        }
        return (Channel(16) << 16) | (Channel(8) << 8) | Channel(0);
    }

    private static bool ContainsAny(string value, params string[] tokens) => tokens.Any(value.Contains);
    private static string Normalized(string value) => value.Trim().ToLowerInvariant();
}
