import Foundation

// ID/reference audit: Bedrock 26.52; official content snapshot v1.26.50.4.
// Provenance, legacy group labels and fixed data snapshots: Docs/CatalogSync.
/// Legacy Bedrock block numeric IDs (0...255) and their matching legacy string IDs.
/// Numeric IDs are used by old subchunk storage; modern aliases are accepted for lookup.
enum BedrockLegacyBlockCatalog {
    static let blocks: [BedrockDataValueEntry] = [
        BedrockDataValueEntry(id: 0, identifier: "minecraft:air", displayName: "空气"),
        BedrockDataValueEntry(id: 1, identifier: "minecraft:stone", displayName: "石头"),
        BedrockDataValueEntry(id: 2, identifier: "minecraft:grass", displayName: "草方块"),
        BedrockDataValueEntry(id: 3, identifier: "minecraft:dirt", displayName: "泥土"),
        BedrockDataValueEntry(id: 4, identifier: "minecraft:cobblestone", displayName: "圆石"),
        BedrockDataValueEntry(id: 5, identifier: "minecraft:planks", displayName: "木板"),
        BedrockDataValueEntry(id: 6, identifier: "minecraft:sapling", displayName: "树苗"),
        BedrockDataValueEntry(id: 7, identifier: "minecraft:bedrock", displayName: "基岩"),
        BedrockDataValueEntry(id: 8, identifier: "minecraft:flowing_water", displayName: "流动的水"),
        BedrockDataValueEntry(id: 9, identifier: "minecraft:water", displayName: "水"),
        BedrockDataValueEntry(id: 10, identifier: "minecraft:flowing_lava", displayName: "流动的熔岩"),
        BedrockDataValueEntry(id: 11, identifier: "minecraft:lava", displayName: "熔岩"),
        BedrockDataValueEntry(id: 12, identifier: "minecraft:sand", displayName: "沙子"),
        BedrockDataValueEntry(id: 13, identifier: "minecraft:gravel", displayName: "砂砾"),
        BedrockDataValueEntry(id: 14, identifier: "minecraft:gold_ore", displayName: "金矿石"),
        BedrockDataValueEntry(id: 15, identifier: "minecraft:iron_ore", displayName: "铁矿石"),
        BedrockDataValueEntry(id: 16, identifier: "minecraft:coal_ore", displayName: "煤矿石"),
        BedrockDataValueEntry(id: 17, identifier: "minecraft:log", displayName: "原木"),
        BedrockDataValueEntry(id: 18, identifier: "minecraft:leaves", displayName: "树叶"),
        BedrockDataValueEntry(id: 19, identifier: "minecraft:sponge", displayName: "海绵"),
        BedrockDataValueEntry(id: 20, identifier: "minecraft:glass", displayName: "玻璃"),
        BedrockDataValueEntry(id: 21, identifier: "minecraft:lapis_ore", displayName: "青金石矿石"),
        BedrockDataValueEntry(id: 22, identifier: "minecraft:lapis_block", displayName: "青金石块"),
        BedrockDataValueEntry(id: 23, identifier: "minecraft:dispenser", displayName: "发射器"),
        BedrockDataValueEntry(id: 24, identifier: "minecraft:sandstone", displayName: "砂岩"),
        BedrockDataValueEntry(id: 25, identifier: "minecraft:noteblock", displayName: "音符盒"),
        BedrockDataValueEntry(id: 26, identifier: "minecraft:bed", displayName: "床"),
        BedrockDataValueEntry(id: 27, identifier: "minecraft:golden_rail", displayName: "动力铁轨"),
        BedrockDataValueEntry(id: 28, identifier: "minecraft:detector_rail", displayName: "探测铁轨"),
        BedrockDataValueEntry(id: 29, identifier: "minecraft:sticky_piston", displayName: "黏性活塞"),
        BedrockDataValueEntry(id: 30, identifier: "minecraft:web", displayName: "蜘蛛网"),
        BedrockDataValueEntry(id: 31, identifier: "minecraft:tallgrass", displayName: "矮草丛"),
        BedrockDataValueEntry(id: 32, identifier: "minecraft:deadbush", displayName: "枯萎的灌木"),
        BedrockDataValueEntry(id: 33, identifier: "minecraft:piston", displayName: "活塞"),
        BedrockDataValueEntry(id: 34, identifier: "minecraft:pistonArmCollision", displayName: "活塞头"),
        BedrockDataValueEntry(id: 35, identifier: "minecraft:wool", displayName: "羊毛"),
        BedrockDataValueEntry(id: 36, identifier: "minecraft:element_0", displayName: "未知元素"),
        BedrockDataValueEntry(id: 37, identifier: "minecraft:yellow_flower", displayName: "蒲公英"),
        BedrockDataValueEntry(id: 38, identifier: "minecraft:red_flower", displayName: "花（旧版红花组）"),
        BedrockDataValueEntry(id: 39, identifier: "minecraft:brown_mushroom", displayName: "棕色蘑菇"),
        BedrockDataValueEntry(id: 40, identifier: "minecraft:red_mushroom", displayName: "红蘑菇"),
        BedrockDataValueEntry(id: 41, identifier: "minecraft:gold_block", displayName: "金块"),
        BedrockDataValueEntry(id: 42, identifier: "minecraft:iron_block", displayName: "铁块"),
        BedrockDataValueEntry(id: 43, identifier: "minecraft:double_stone_slab", displayName: "双层石台阶"),
        BedrockDataValueEntry(id: 44, identifier: "minecraft:stone_slab", displayName: "石台阶"),
        BedrockDataValueEntry(id: 45, identifier: "minecraft:brick_block", displayName: "砖块"),
        BedrockDataValueEntry(id: 46, identifier: "minecraft:tnt", displayName: "TNT（炸药）"),
        BedrockDataValueEntry(id: 47, identifier: "minecraft:bookshelf", displayName: "书架"),
        BedrockDataValueEntry(id: 48, identifier: "minecraft:mossy_cobblestone", displayName: "苔石"),
        BedrockDataValueEntry(id: 49, identifier: "minecraft:obsidian", displayName: "黑曜石"),
        BedrockDataValueEntry(id: 50, identifier: "minecraft:torch", displayName: "火把"),
        BedrockDataValueEntry(id: 51, identifier: "minecraft:fire", displayName: "火"),
        BedrockDataValueEntry(id: 52, identifier: "minecraft:mob_spawner", displayName: "刷怪笼"),
        BedrockDataValueEntry(id: 53, identifier: "minecraft:oak_stairs", displayName: "橡木楼梯"),
        BedrockDataValueEntry(id: 54, identifier: "minecraft:chest", displayName: "箱子"),
        BedrockDataValueEntry(id: 55, identifier: "minecraft:redstone_wire", displayName: "红石粉"),
        BedrockDataValueEntry(id: 56, identifier: "minecraft:diamond_ore", displayName: "钻石矿石"),
        BedrockDataValueEntry(id: 57, identifier: "minecraft:diamond_block", displayName: "钻石块"),
        BedrockDataValueEntry(id: 58, identifier: "minecraft:crafting_table", displayName: "工作台"),
        BedrockDataValueEntry(id: 59, identifier: "minecraft:wheat", displayName: "小麦"),
        BedrockDataValueEntry(id: 60, identifier: "minecraft:farmland", displayName: "耕地"),
        BedrockDataValueEntry(id: 61, identifier: "minecraft:furnace", displayName: "熔炉"),
        BedrockDataValueEntry(id: 62, identifier: "minecraft:lit_furnace", displayName: "燃烧中的熔炉"),
        BedrockDataValueEntry(id: 63, identifier: "minecraft:standing_sign", displayName: "告示牌"),
        BedrockDataValueEntry(id: 64, identifier: "minecraft:wooden_door", displayName: "橡木门"),
        BedrockDataValueEntry(id: 65, identifier: "minecraft:ladder", displayName: "梯子"),
        BedrockDataValueEntry(id: 66, identifier: "minecraft:rail", displayName: "铁轨"),
        BedrockDataValueEntry(id: 67, identifier: "minecraft:stone_stairs", displayName: "圆石楼梯"),
        BedrockDataValueEntry(id: 68, identifier: "minecraft:wall_sign", displayName: "墙上的告示牌"),
        BedrockDataValueEntry(id: 69, identifier: "minecraft:lever", displayName: "拉杆"),
        BedrockDataValueEntry(id: 70, identifier: "minecraft:stone_pressure_plate", displayName: "石质压力板"),
        BedrockDataValueEntry(id: 71, identifier: "minecraft:iron_door", displayName: "铁门"),
        BedrockDataValueEntry(id: 72, identifier: "minecraft:wooden_pressure_plate", displayName: "橡木压力板"),
        BedrockDataValueEntry(id: 73, identifier: "minecraft:redstone_ore", displayName: "红石矿石"),
        BedrockDataValueEntry(id: 74, identifier: "minecraft:lit_redstone_ore", displayName: "发光的红石矿石"),
        BedrockDataValueEntry(id: 75, identifier: "minecraft:unlit_redstone_torch", displayName: "熄灭的红石火把"),
        BedrockDataValueEntry(id: 76, identifier: "minecraft:redstone_torch", displayName: "点亮的红石火把"),
        BedrockDataValueEntry(id: 77, identifier: "minecraft:stone_button", displayName: "石质按钮"),
        BedrockDataValueEntry(id: 78, identifier: "minecraft:snow_layer", displayName: "雪"),
        BedrockDataValueEntry(id: 79, identifier: "minecraft:ice", displayName: "冰"),
        BedrockDataValueEntry(id: 80, identifier: "minecraft:snow", displayName: "雪块"),
        BedrockDataValueEntry(id: 81, identifier: "minecraft:cactus", displayName: "仙人掌"),
        BedrockDataValueEntry(id: 82, identifier: "minecraft:clay", displayName: "黏土"),
        BedrockDataValueEntry(id: 83, identifier: "minecraft:reeds", displayName: "甘蔗"),
        BedrockDataValueEntry(id: 84, identifier: "minecraft:jukebox", displayName: "唱片机"),
        BedrockDataValueEntry(id: 85, identifier: "minecraft:fence", displayName: "橡木栅栏"),
        BedrockDataValueEntry(id: 86, identifier: "minecraft:pumpkin", displayName: "南瓜"),
        BedrockDataValueEntry(id: 87, identifier: "minecraft:netherrack", displayName: "下界岩"),
        BedrockDataValueEntry(id: 88, identifier: "minecraft:soul_sand", displayName: "灵魂沙"),
        BedrockDataValueEntry(id: 89, identifier: "minecraft:glowstone", displayName: "荧石"),
        BedrockDataValueEntry(id: 90, identifier: "minecraft:portal", displayName: "下界传送门"),
        BedrockDataValueEntry(id: 91, identifier: "minecraft:lit_pumpkin", displayName: "南瓜灯"),
        BedrockDataValueEntry(id: 92, identifier: "minecraft:cake", displayName: "蛋糕"),
        BedrockDataValueEntry(id: 93, identifier: "minecraft:unpowered_repeater", displayName: "红石中继器（未激活）"),
        BedrockDataValueEntry(id: 94, identifier: "minecraft:powered_repeater", displayName: "红石中继器（已激活）"),
        BedrockDataValueEntry(id: 95, identifier: "minecraft:invisibleBedrock", displayName: "隐形基岩"),
        BedrockDataValueEntry(id: 96, identifier: "minecraft:trapdoor", displayName: "橡木活板门"),
        BedrockDataValueEntry(id: 97, identifier: "minecraft:monster_egg", displayName: "虫蚀方块"),
        BedrockDataValueEntry(id: 98, identifier: "minecraft:stonebrick", displayName: "石砖"),
        BedrockDataValueEntry(id: 99, identifier: "minecraft:brown_mushroom_block", displayName: "棕色蘑菇方块"),
        BedrockDataValueEntry(id: 100, identifier: "minecraft:red_mushroom_block", displayName: "红色蘑菇方块"),
        BedrockDataValueEntry(id: 101, identifier: "minecraft:iron_bars", displayName: "铁栏杆"),
        BedrockDataValueEntry(id: 102, identifier: "minecraft:glass_pane", displayName: "玻璃板"),
        BedrockDataValueEntry(id: 103, identifier: "minecraft:melon_block", displayName: "西瓜"),
        BedrockDataValueEntry(id: 104, identifier: "minecraft:pumpkin_stem", displayName: "南瓜茎"),
        BedrockDataValueEntry(id: 105, identifier: "minecraft:melon_stem", displayName: "西瓜茎"),
        BedrockDataValueEntry(id: 106, identifier: "minecraft:vine", displayName: "藤蔓"),
        BedrockDataValueEntry(id: 107, identifier: "minecraft:fence_gate", displayName: "橡木栅栏门"),
        BedrockDataValueEntry(id: 108, identifier: "minecraft:brick_stairs", displayName: "砖块楼梯"),
        BedrockDataValueEntry(id: 109, identifier: "minecraft:stone_brick_stairs", displayName: "石砖楼梯"),
        BedrockDataValueEntry(id: 110, identifier: "minecraft:mycelium", displayName: "菌丝体"),
        BedrockDataValueEntry(id: 111, identifier: "minecraft:waterlily", displayName: "睡莲"),
        BedrockDataValueEntry(id: 112, identifier: "minecraft:nether_brick", displayName: "下界砖块"),
        BedrockDataValueEntry(id: 113, identifier: "minecraft:nether_brick_fence", displayName: "下界砖栅栏"),
        BedrockDataValueEntry(id: 114, identifier: "minecraft:nether_brick_stairs", displayName: "下界砖楼梯"),
        BedrockDataValueEntry(id: 115, identifier: "minecraft:nether_wart", displayName: "下界疣"),
        BedrockDataValueEntry(id: 116, identifier: "minecraft:enchanting_table", displayName: "附魔台"),
        BedrockDataValueEntry(id: 117, identifier: "minecraft:brewing_stand", displayName: "酿造台"),
        BedrockDataValueEntry(id: 118, identifier: "minecraft:cauldron", displayName: "炼药锅"),
        BedrockDataValueEntry(id: 119, identifier: "minecraft:end_portal", displayName: "末地传送门"),
        BedrockDataValueEntry(id: 120, identifier: "minecraft:end_portal_frame", displayName: "末地传送门框架"),
        BedrockDataValueEntry(id: 121, identifier: "minecraft:end_stone", displayName: "末地石"),
        BedrockDataValueEntry(id: 122, identifier: "minecraft:dragon_egg", displayName: "龙蛋"),
        BedrockDataValueEntry(id: 123, identifier: "minecraft:redstone_lamp", displayName: "红石灯"),
        BedrockDataValueEntry(id: 124, identifier: "minecraft:lit_redstone_lamp", displayName: "点亮的红石灯"),
        BedrockDataValueEntry(id: 125, identifier: "minecraft:dropper", displayName: "投掷器"),
        BedrockDataValueEntry(id: 126, identifier: "minecraft:activator_rail", displayName: "激活铁轨"),
        BedrockDataValueEntry(id: 127, identifier: "minecraft:cocoa", displayName: "可可"),
        BedrockDataValueEntry(id: 128, identifier: "minecraft:sandstone_stairs", displayName: "砂岩楼梯"),
        BedrockDataValueEntry(id: 129, identifier: "minecraft:emerald_ore", displayName: "绿宝石矿石"),
        BedrockDataValueEntry(id: 130, identifier: "minecraft:ender_chest", displayName: "末影箱"),
        BedrockDataValueEntry(id: 131, identifier: "minecraft:tripwire_hook", displayName: "绊线钩"),
        BedrockDataValueEntry(id: 132, identifier: "minecraft:tripWire", displayName: "绊线"),
        BedrockDataValueEntry(id: 133, identifier: "minecraft:emerald_block", displayName: "绿宝石块"),
        BedrockDataValueEntry(id: 134, identifier: "minecraft:spruce_stairs", displayName: "云杉木楼梯"),
        BedrockDataValueEntry(id: 135, identifier: "minecraft:birch_stairs", displayName: "白桦木楼梯"),
        BedrockDataValueEntry(id: 136, identifier: "minecraft:jungle_stairs", displayName: "丛林木楼梯"),
        BedrockDataValueEntry(id: 137, identifier: "minecraft:command_block", displayName: "命令方块"),
        BedrockDataValueEntry(id: 138, identifier: "minecraft:beacon", displayName: "信标"),
        BedrockDataValueEntry(id: 139, identifier: "minecraft:cobblestone_wall", displayName: "圆石墙"),
        BedrockDataValueEntry(id: 140, identifier: "minecraft:flower_pot", displayName: "花盆"),
        BedrockDataValueEntry(id: 141, identifier: "minecraft:carrots", displayName: "胡萝卜"),
        BedrockDataValueEntry(id: 142, identifier: "minecraft:potatoes", displayName: "马铃薯"),
        BedrockDataValueEntry(id: 143, identifier: "minecraft:wooden_button", displayName: "橡木按钮"),
        BedrockDataValueEntry(id: 144, identifier: "minecraft:skull", displayName: "生物头颅"),
        BedrockDataValueEntry(id: 145, identifier: "minecraft:anvil", displayName: "铁砧"),
        BedrockDataValueEntry(id: 146, identifier: "minecraft:trapped_chest", displayName: "陷阱箱"),
        BedrockDataValueEntry(id: 147, identifier: "minecraft:light_weighted_pressure_plate", displayName: "轻质测重压力板"),
        BedrockDataValueEntry(id: 148, identifier: "minecraft:heavy_weighted_pressure_plate", displayName: "重质测重压力板"),
        BedrockDataValueEntry(id: 149, identifier: "minecraft:unpowered_comparator", displayName: "红石比较器（未激活）"),
        BedrockDataValueEntry(id: 150, identifier: "minecraft:powered_comparator", displayName: "红石比较器（已激活）"),
        BedrockDataValueEntry(id: 151, identifier: "minecraft:daylight_detector", displayName: "阳光探测器"),
        BedrockDataValueEntry(id: 152, identifier: "minecraft:redstone_block", displayName: "红石块"),
        BedrockDataValueEntry(id: 153, identifier: "minecraft:quartz_ore", displayName: "下界石英矿石"),
        BedrockDataValueEntry(id: 154, identifier: "minecraft:hopper", displayName: "漏斗"),
        BedrockDataValueEntry(id: 155, identifier: "minecraft:quartz_block", displayName: "石英块"),
        BedrockDataValueEntry(id: 156, identifier: "minecraft:quartz_stairs", displayName: "石英楼梯"),
        BedrockDataValueEntry(id: 157, identifier: "minecraft:double_wooden_slab", displayName: "双层木台阶"),
        BedrockDataValueEntry(id: 158, identifier: "minecraft:wooden_slab", displayName: "木台阶"),
        BedrockDataValueEntry(id: 159, identifier: "minecraft:stained_hardened_clay", displayName: "染色陶瓦"),
        BedrockDataValueEntry(id: 160, identifier: "minecraft:stained_glass_pane", displayName: "染色玻璃板"),
        BedrockDataValueEntry(id: 161, identifier: "minecraft:leaves2", displayName: "树叶（第二组）"),
        BedrockDataValueEntry(id: 162, identifier: "minecraft:log2", displayName: "原木（第二组）"),
        BedrockDataValueEntry(id: 163, identifier: "minecraft:acacia_stairs", displayName: "金合欢木楼梯"),
        BedrockDataValueEntry(id: 164, identifier: "minecraft:dark_oak_stairs", displayName: "深色橡木楼梯"),
        BedrockDataValueEntry(id: 165, identifier: "minecraft:slime", displayName: "黏液块"),
        BedrockDataValueEntry(id: 166, identifier: "minecraft:unused_166", displayName: "未使用"),
        BedrockDataValueEntry(id: 167, identifier: "minecraft:iron_trapdoor", displayName: "铁活板门"),
        BedrockDataValueEntry(id: 168, identifier: "minecraft:prismarine", displayName: "海晶石"),
        BedrockDataValueEntry(id: 169, identifier: "minecraft:seaLantern", displayName: "海晶灯"),
        BedrockDataValueEntry(id: 170, identifier: "minecraft:hay_block", displayName: "干草块"),
        BedrockDataValueEntry(id: 171, identifier: "minecraft:carpet", displayName: "地毯"),
        BedrockDataValueEntry(id: 172, identifier: "minecraft:hardened_clay", displayName: "陶瓦"),
        BedrockDataValueEntry(id: 173, identifier: "minecraft:coal_block", displayName: "煤炭块"),
        BedrockDataValueEntry(id: 174, identifier: "minecraft:packed_ice", displayName: "浮冰"),
        BedrockDataValueEntry(id: 175, identifier: "minecraft:double_plant", displayName: "高花与高草丛"),
        BedrockDataValueEntry(id: 176, identifier: "minecraft:standing_banner", displayName: "旗帜"),
        BedrockDataValueEntry(id: 177, identifier: "minecraft:wall_banner", displayName: "墙上的旗帜"),
        BedrockDataValueEntry(id: 178, identifier: "minecraft:daylight_detector_inverted", displayName: "反向阳光探测器"),
        BedrockDataValueEntry(id: 179, identifier: "minecraft:red_sandstone", displayName: "红砂岩"),
        BedrockDataValueEntry(id: 180, identifier: "minecraft:red_sandstone_stairs", displayName: "红砂岩楼梯"),
        BedrockDataValueEntry(id: 181, identifier: "minecraft:double_stone_slab2", displayName: "双层石台阶（第二组）"),
        BedrockDataValueEntry(id: 182, identifier: "minecraft:stone_slab2", displayName: "石台阶（第二组）"),
        BedrockDataValueEntry(id: 183, identifier: "minecraft:spruce_fence_gate", displayName: "云杉木栅栏门"),
        BedrockDataValueEntry(id: 184, identifier: "minecraft:birch_fence_gate", displayName: "白桦木栅栏门"),
        BedrockDataValueEntry(id: 185, identifier: "minecraft:jungle_fence_gate", displayName: "丛林木栅栏门"),
        BedrockDataValueEntry(id: 186, identifier: "minecraft:dark_oak_fence_gate", displayName: "深色橡木栅栏门"),
        BedrockDataValueEntry(id: 187, identifier: "minecraft:acacia_fence_gate", displayName: "金合欢木栅栏门"),
        BedrockDataValueEntry(id: 188, identifier: "minecraft:repeating_command_block", displayName: "循环型命令方块"),
        BedrockDataValueEntry(id: 189, identifier: "minecraft:chain_command_block", displayName: "锁链命令方块"),
        BedrockDataValueEntry(id: 190, identifier: "minecraft:hard_glass_pane", displayName: "强化玻璃板"),
        BedrockDataValueEntry(id: 191, identifier: "minecraft:hard_stained_glass_pane", displayName: "强化染色玻璃板"),
        BedrockDataValueEntry(id: 192, identifier: "minecraft:chemical_heat", displayName: "加热块"),
        BedrockDataValueEntry(id: 193, identifier: "minecraft:spruce_door", displayName: "云杉木门"),
        BedrockDataValueEntry(id: 194, identifier: "minecraft:birch_door", displayName: "白桦木门"),
        BedrockDataValueEntry(id: 195, identifier: "minecraft:jungle_door", displayName: "丛林木门"),
        BedrockDataValueEntry(id: 196, identifier: "minecraft:acacia_door", displayName: "金合欢木门"),
        BedrockDataValueEntry(id: 197, identifier: "minecraft:dark_oak_door", displayName: "深色橡木门"),
        BedrockDataValueEntry(id: 198, identifier: "minecraft:grass_path", displayName: "土径"),
        BedrockDataValueEntry(id: 199, identifier: "minecraft:frame", displayName: "物品展示框"),
        BedrockDataValueEntry(id: 200, identifier: "minecraft:chorus_flower", displayName: "紫颂花"),
        BedrockDataValueEntry(id: 201, identifier: "minecraft:purpur_block", displayName: "紫珀块"),
        BedrockDataValueEntry(id: 202, identifier: "minecraft:colored_torch_rg", displayName: "彩色火把（红、绿）"),
        BedrockDataValueEntry(id: 203, identifier: "minecraft:purpur_stairs", displayName: "紫珀楼梯"),
        BedrockDataValueEntry(id: 204, identifier: "minecraft:colored_torch_bp", displayName: "彩色火把（蓝、紫）"),
        BedrockDataValueEntry(id: 205, identifier: "minecraft:undyed_shulker_box", displayName: "潜影盒（未染色）"),
        BedrockDataValueEntry(id: 206, identifier: "minecraft:end_bricks", displayName: "末地石砖"),
        BedrockDataValueEntry(id: 207, identifier: "minecraft:frosted_ice", displayName: "霜冰"),
        BedrockDataValueEntry(id: 208, identifier: "minecraft:end_rod", displayName: "末地烛"),
        BedrockDataValueEntry(id: 209, identifier: "minecraft:end_gateway", displayName: "末地折跃门"),
        BedrockDataValueEntry(id: 210, identifier: "minecraft:allow", displayName: "允许方块"),
        BedrockDataValueEntry(id: 211, identifier: "minecraft:deny", displayName: "拒绝方块"),
        BedrockDataValueEntry(id: 212, identifier: "minecraft:border_block", displayName: "边界方块"),
        BedrockDataValueEntry(id: 213, identifier: "minecraft:magma", displayName: "岩浆块"),
        BedrockDataValueEntry(id: 214, identifier: "minecraft:nether_wart_block", displayName: "下界疣块"),
        BedrockDataValueEntry(id: 215, identifier: "minecraft:red_nether_brick", displayName: "红色下界砖块"),
        BedrockDataValueEntry(id: 216, identifier: "minecraft:bone_block", displayName: "骨块"),
        BedrockDataValueEntry(id: 217, identifier: "minecraft:structure_void", displayName: "结构空位"),
        BedrockDataValueEntry(id: 218, identifier: "minecraft:shulker_box", displayName: "潜影盒"),
        BedrockDataValueEntry(id: 219, identifier: "minecraft:purple_glazed_terracotta", displayName: "紫色带釉陶瓦"),
        BedrockDataValueEntry(id: 220, identifier: "minecraft:white_glazed_terracotta", displayName: "白色带釉陶瓦"),
        BedrockDataValueEntry(id: 221, identifier: "minecraft:orange_glazed_terracotta", displayName: "橙色带釉陶瓦"),
        BedrockDataValueEntry(id: 222, identifier: "minecraft:magenta_glazed_terracotta", displayName: "品红色带釉陶瓦"),
        BedrockDataValueEntry(id: 223, identifier: "minecraft:light_blue_glazed_terracotta", displayName: "淡蓝色带釉陶瓦"),
        BedrockDataValueEntry(id: 224, identifier: "minecraft:yellow_glazed_terracotta", displayName: "黄色带釉陶瓦"),
        BedrockDataValueEntry(id: 225, identifier: "minecraft:lime_glazed_terracotta", displayName: "黄绿色带釉陶瓦"),
        BedrockDataValueEntry(id: 226, identifier: "minecraft:pink_glazed_terracotta", displayName: "粉红色带釉陶瓦"),
        BedrockDataValueEntry(id: 227, identifier: "minecraft:gray_glazed_terracotta", displayName: "灰色带釉陶瓦"),
        BedrockDataValueEntry(id: 228, identifier: "minecraft:silver_glazed_terracotta", displayName: "淡灰色带釉陶瓦"),
        BedrockDataValueEntry(id: 229, identifier: "minecraft:cyan_glazed_terracotta", displayName: "青色带釉陶瓦"),
        BedrockDataValueEntry(id: 230, identifier: "minecraft:chalkboard", displayName: "黑板"),
        BedrockDataValueEntry(id: 231, identifier: "minecraft:blue_glazed_terracotta", displayName: "蓝色带釉陶瓦"),
        BedrockDataValueEntry(id: 232, identifier: "minecraft:brown_glazed_terracotta", displayName: "棕色带釉陶瓦"),
        BedrockDataValueEntry(id: 233, identifier: "minecraft:green_glazed_terracotta", displayName: "绿色带釉陶瓦"),
        BedrockDataValueEntry(id: 234, identifier: "minecraft:red_glazed_terracotta", displayName: "红色带釉陶瓦"),
        BedrockDataValueEntry(id: 235, identifier: "minecraft:black_glazed_terracotta", displayName: "黑色带釉陶瓦"),
        BedrockDataValueEntry(id: 236, identifier: "minecraft:concrete", displayName: "混凝土"),
        BedrockDataValueEntry(id: 237, identifier: "minecraft:concretePowder", displayName: "混凝土粉末"),
        BedrockDataValueEntry(id: 238, identifier: "minecraft:chemistry_table", displayName: "化学工作台（旧版共用 ID）"),
        BedrockDataValueEntry(id: 239, identifier: "minecraft:underwater_torch", displayName: "水下火把"),
        BedrockDataValueEntry(id: 240, identifier: "minecraft:chorus_plant", displayName: "紫颂植株"),
        BedrockDataValueEntry(id: 241, identifier: "minecraft:stained_glass", displayName: "染色玻璃"),
        BedrockDataValueEntry(id: 242, identifier: "minecraft:camera", displayName: "摄像机"),
        BedrockDataValueEntry(id: 243, identifier: "minecraft:podzol", displayName: "灰化土"),
        BedrockDataValueEntry(id: 244, identifier: "minecraft:beetroot", displayName: "甜菜根"),
        BedrockDataValueEntry(id: 245, identifier: "minecraft:stonecutter", displayName: "切石机（旧版）"),
        BedrockDataValueEntry(id: 246, identifier: "minecraft:glowingobsidian", displayName: "发光的黑曜石"),
        BedrockDataValueEntry(id: 247, identifier: "minecraft:netherreactor", displayName: "下界反应核"),
        BedrockDataValueEntry(id: 248, identifier: "minecraft:info_update", displayName: "数据更新方块"),
        BedrockDataValueEntry(id: 249, identifier: "minecraft:info_update2", displayName: "数据更新方块（第二种）"),
        BedrockDataValueEntry(id: 250, identifier: "minecraft:movingBlock", displayName: "活塞移动方块"),
        BedrockDataValueEntry(id: 251, identifier: "minecraft:observer", displayName: "侦测器"),
        BedrockDataValueEntry(id: 252, identifier: "minecraft:structure_block", displayName: "结构方块"),
        BedrockDataValueEntry(id: 253, identifier: "minecraft:hard_glass", displayName: "强化玻璃"),
        BedrockDataValueEntry(id: 254, identifier: "minecraft:hard_stained_glass", displayName: "强化染色玻璃"),
        BedrockDataValueEntry(id: 255, identifier: "minecraft:reserved6", displayName: "未命名预留方块（reserved6）"),
    ]

    private static let entriesByID: [Int: BedrockDataValueEntry] = {
        Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
    }()

    private static let entriesByIdentifier: [String: BedrockDataValueEntry] = {
        var result = Dictionary(uniqueKeysWithValues: blocks.map { ($0.identifier.lowercased(), $0) })
        let aliases: [String: Int] = [
            // Modern/flatter names and common aliases for the legacy families.
            "minecraft:grass_block": 2,
            "minecraft:oak_planks": 5,
            "minecraft:oak_sapling": 6,
            "minecraft:oak_log": 17,
            "minecraft:oak_leaves": 18,
            "minecraft:short_grass": 31,
            "minecraft:piston_arm_collision": 34,
            "minecraft:white_wool": 35,
            "minecraft:dandelion": 37,
            "minecraft:poppy": 38,
            "minecraft:smooth_stone_double_slab": 43,
            "minecraft:smooth_stone_slab": 44,
            "minecraft:oak_fence": 85,
            "minecraft:invisible_bedrock": 95,
            "minecraft:infested_stone": 97,
            "minecraft:stone_bricks": 98,
            "minecraft:oak_fence_gate": 107,
            "minecraft:lily_pad": 111,
            "minecraft:trip_wire": 132,
            "minecraft:skeleton_skull": 144,
            "minecraft:oak_double_slab": 157,
            "minecraft:oak_slab": 158,
            "minecraft:white_terracotta": 159,
            "minecraft:white_stained_glass_pane": 160,
            "minecraft:acacia_leaves": 161,
            "minecraft:acacia_log": 162,
            "minecraft:sea_lantern": 169,
            "minecraft:white_carpet": 171,
            "minecraft:sunflower": 175,
            "minecraft:red_sandstone_double_slab": 181,
            "minecraft:red_sandstone_slab": 182,
            "minecraft:hard_white_stained_glass_pane": 191,
            "minecraft:dirt_path": 198,
            "minecraft:item_frame": 199,
            "minecraft:colored_torch_red": 202,
            "minecraft:colored_torch_blue": 204,
            "minecraft:undyed_shulker_box": 205,
            "minecraft:white_shulker_box": 218,
            "minecraft:white_concrete": 236,
            "minecraft:white_concrete_powder": 237,
            "minecraft:compound_creator": 238,
            "minecraft:white_stained_glass": 241,
            "minecraft:moving_block": 250,
            "minecraft:hard_white_stained_glass": 254,
        ]
        for (alias, id) in aliases {
            if let entry = entriesByID[id] { result[alias.lowercased()] = entry }
        }
        return result
    }()

    static func block(forNumericID id: Int) -> BedrockDataValueEntry? {
        entriesByID[id]
    }

    static func block(forIdentifier identifier: String) -> BedrockDataValueEntry? {
        let normalized = normalizedIdentifier(identifier)
        return entriesByIdentifier[normalized]
    }

    static func identifier(forNumericID id: UInt16) -> String? {
        block(forNumericID: Int(id))?.identifier
    }

    static func numericID(forIdentifier identifier: String) -> UInt16? {
        guard let id = block(forIdentifier: identifier)?.id else { return nil }
        return UInt16(exactly: id)
    }

    static func blockIdentifier(forRawValue rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let decimal = Int(value), let entry = block(forNumericID: decimal) { return entry.identifier }
        if value.lowercased().hasPrefix("0x"),
           let hexadecimal = Int(value.dropFirst(2), radix: 16),
           let entry = block(forNumericID: hexadecimal) { return entry.identifier }
        return block(forIdentifier: value)?.identifier ?? normalizedIdentifier(value)
    }

    static func searchText(for state: BedrockBlockState) -> String {
        var values = [state.name]
        if let id = state.legacyID {
            values.append(String(id))
            values.append(String(format: "0x%02X", id))
            values.append("legacy:\(id):\(state.legacyData ?? 0)")
            if let entry = block(forNumericID: Int(id)) {
                values.append(entry.identifier)
                values.append(entry.displayName)
            }
        } else if let entry = block(forIdentifier: state.name) {
            values.append(String(entry.id))
            values.append(entry.hexadecimalID)
            values.append(entry.displayName)
        }
        return values.joined(separator: "\n")
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.contains(":") ? trimmed : "minecraft:\(trimmed)"
    }
}
