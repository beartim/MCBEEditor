import Foundation

struct BedrockDataValueEntry: Hashable {
    let id: Int
    let identifier: String
    let displayName: String

    var hexadecimalID: String { String(format: "0x%02X", UInt32(id)) }
}

enum BedrockDataValueCatalog {
    /// Entity short IDs used by Bedrock's entity type table.
    static let entities: [BedrockDataValueEntry] = [
        value(1, "minecraft:undefined_test_only", "仅测试未定义实体"),
        value(10, "minecraft:chicken", "鸡"),
        value(11, "minecraft:cow", "牛"),
        value(12, "minecraft:pig", "猪"),
        value(13, "minecraft:sheep", "绵羊"),
        value(14, "minecraft:wolf", "狼"),
        value(15, "minecraft:villager", "村民（旧版）"),
        value(16, "minecraft:mooshroom", "哞菇"),
        value(17, "minecraft:squid", "鱿鱼"),
        value(18, "minecraft:rabbit", "兔子"),
        value(19, "minecraft:bat", "蝙蝠"),
        value(20, "minecraft:iron_golem", "铁傀儡"),
        value(21, "minecraft:snow_golem", "雪傀儡"),
        value(22, "minecraft:ocelot", "豹猫"),
        value(23, "minecraft:horse", "马"),
        value(24, "minecraft:donkey", "驴"),
        value(25, "minecraft:mule", "骡"),
        value(26, "minecraft:skeleton_horse", "骷髅马"),
        value(27, "minecraft:zombie_horse", "僵尸马"),
        value(28, "minecraft:polar_bear", "北极熊"),
        value(29, "minecraft:llama", "羊驼"),
        value(30, "minecraft:parrot", "鹦鹉"),
        value(31, "minecraft:dolphin", "海豚"),
        value(32, "minecraft:zombie", "僵尸"),
        value(33, "minecraft:creeper", "苦力怕"),
        value(34, "minecraft:skeleton", "骷髅"),
        value(35, "minecraft:spider", "蜘蛛"),
        value(36, "minecraft:zombie_pigman", "僵尸猪灵"),
        value(37, "minecraft:slime", "史莱姆"),
        value(38, "minecraft:enderman", "末影人"),
        value(39, "minecraft:silverfish", "蠹虫"),
        value(40, "minecraft:cave_spider", "洞穴蜘蛛"),
        value(41, "minecraft:ghast", "恶魂"),
        value(42, "minecraft:magma_cube", "岩浆怪"),
        value(43, "minecraft:blaze", "烈焰人"),
        value(44, "minecraft:zombie_villager", "僵尸村民（旧版）"),
        value(45, "minecraft:witch", "女巫"),
        value(46, "minecraft:stray", "流浪者"),
        value(47, "minecraft:husk", "尸壳"),
        value(48, "minecraft:wither_skeleton", "凋灵骷髅"),
        value(49, "minecraft:guardian", "守卫者"),
        value(50, "minecraft:elder_guardian", "远古守卫者"),
        value(51, "minecraft:npc", "NPC"),
        value(52, "minecraft:wither", "凋灵"),
        value(53, "minecraft:ender_dragon", "末影龙"),
        value(54, "minecraft:shulker", "潜影贝"),
        value(55, "minecraft:endermite", "末影螨"),
        value(56, "minecraft:agent", "智能体"),
        value(57, "minecraft:vindicator", "卫道士"),
        value(58, "minecraft:phantom", "幻翼"),
        value(59, "minecraft:ravager", "劫掠兽"),
        value(61, "minecraft:armor_stand", "盔甲架"),
        value(62, "minecraft:tripod_camera", "相机"),
        value(63, "minecraft:player", "玩家"),
        value(64, "minecraft:item", "掉落物"),
        value(65, "minecraft:tnt", "点燃的 TNT"),
        value(66, "minecraft:falling_block", "下落的方块"),
        value(67, "minecraft:moving_block", "移动的方块"),
        value(68, "minecraft:xp_bottle", "附魔之瓶"),
        value(69, "minecraft:xp_orb", "经验球"),
        value(70, "minecraft:eye_of_ender_signal", "末影之眼"),
        value(71, "minecraft:ender_crystal", "末地水晶"),
        value(72, "minecraft:fireworks_rocket", "烟花火箭"),
        value(73, "minecraft:thrown_trident", "三叉戟"),
        value(74, "minecraft:turtle", "海龟"),
        value(75, "minecraft:cat", "猫"),
        value(76, "minecraft:shulker_bullet", "潜影弹"),
        value(77, "minecraft:fishing_hook", "浮漂"),
        value(78, "minecraft:chalkboard", "黑板"),
        value(79, "minecraft:dragon_fireball", "末影龙火球"),
        value(80, "minecraft:arrow", "箭"),
        value(81, "minecraft:snowball", "雪球"),
        value(82, "minecraft:egg", "鸡蛋"),
        value(83, "minecraft:painting", "画"),
        value(84, "minecraft:minecart", "矿车"),
        value(85, "minecraft:fireball", "火球"),
        value(86, "minecraft:splash_potion", "喷溅药水"),
        value(87, "minecraft:ender_pearl", "末影珍珠"),
        value(88, "minecraft:leash_knot", "拴绳结"),
        value(89, "minecraft:wither_skull", "凋灵之首"),
        value(90, "minecraft:boat", "船"),
        value(91, "minecraft:wither_skull_dangerous", "蓝色凋灵之首"),
        value(93, "minecraft:lightning_bolt", "闪电"),
        value(94, "minecraft:small_fireball", "小火球"),
        value(95, "minecraft:area_effect_cloud", "区域效果云"),
        value(96, "minecraft:hopper_minecart", "漏斗矿车"),
        value(97, "minecraft:tnt_minecart", "TNT 矿车"),
        value(98, "minecraft:chest_minecart", "运输矿车"),
        value(100, "minecraft:command_block_minecart", "命令方块矿车"),
        value(101, "minecraft:lingering_potion", "滞留药水"),
        value(102, "minecraft:llama_spit", "羊驼唾沫"),
        value(103, "minecraft:evocation_fang", "尖牙"),
        value(104, "minecraft:evocation_illager", "唤魔者"),
        value(105, "minecraft:vex", "恼鬼"),
        value(106, "minecraft:ice_bomb", "冰弹"),
        value(107, "minecraft:balloon", "气球"),
        value(108, "minecraft:pufferfish", "河豚"),
        value(109, "minecraft:salmon", "鲑鱼"),
        value(110, "minecraft:drowned", "溺尸"),
        value(111, "minecraft:tropicalfish", "热带鱼"),
        value(112, "minecraft:cod", "鳕鱼"),
        value(113, "minecraft:panda", "熊猫"),
        value(114, "minecraft:pillager", "掠夺者"),
        value(115, "minecraft:villager_v2", "村民"),
        value(116, "minecraft:zombie_villager_v2", "僵尸村民"),
        value(117, "minecraft:shield", "盾牌"),
        value(118, "minecraft:wandering_trader", "流浪商人"),
        value(120, "minecraft:elder_guardian_ghost", "远古守卫者幽灵"),
        value(121, "minecraft:fox", "狐狸"),
        value(122, "minecraft:bee", "蜜蜂"),
        value(123, "minecraft:piglin", "猪灵"),
        value(124, "minecraft:hoglin", "疣猪兽"),
        value(125, "minecraft:strider", "炽足兽"),
        value(126, "minecraft:zoglin", "僵尸疣猪兽"),
        value(127, "minecraft:piglin_brute", "猪灵蛮兵"),
        value(128, "minecraft:goat", "山羊"),
        value(129, "minecraft:glow_squid", "发光鱿鱼"),
        value(130, "minecraft:axolotl", "美西螈"),
        value(131, "minecraft:warden", "监守者"),
        value(132, "minecraft:frog", "青蛙"),
        value(133, "minecraft:tadpole", "蝌蚪"),
        value(134, "minecraft:allay", "悦灵"),
        value(138, "minecraft:camel", "骆驼"),
        value(139, "minecraft:sniffer", "嗅探兽"),
        value(140, "minecraft:breeze", "旋风人"),
        value(141, "minecraft:breeze_wind_charge_projectile", "旋风弹"),
        value(142, "minecraft:armadillo", "犰狳"),
        value(143, "minecraft:wind_charge_projectile", "风弹"),
        value(144, "minecraft:bogged", "沼骸"),
        value(145, "minecraft:ominous_item_spawner", "不祥之物生成器"),
        value(146, "minecraft:creaking", "嘎枝"),
        value(147, "minecraft:happy_ghast", "快乐恶魂"),
        value(148, "minecraft:copper_golem", "铜傀儡"),
        value(149, "minecraft:nautilus", "鹦鹉螺"),
        value(150, "minecraft:zombie_nautilus", "僵尸鹦鹉螺"),
        value(151, "minecraft:parched", "焦骸"),
        value(152, "minecraft:camel_husk", "骆驼尸壳"),
        value(153, "minecraft:sulfur_cube", "硫磺方块"),
        value(154, "minecraft:cushion", "坐垫"),
        value(157, "minecraft:trader_llama", "行商羊驼"),
        value(218, "minecraft:chest_boat", "运输船"),
    ]

    /// Numeric status-effect IDs from the Bedrock data-values table.
    static let statusEffects: [BedrockDataValueEntry] = [
        value(1, "speed", "迅捷"),
        value(2, "slowness", "缓慢"),
        value(3, "haste", "急迫"),
        value(4, "mining_fatigue", "挖掘疲劳"),
        value(5, "strength", "力量"),
        value(6, "instant_health", "瞬间治疗"),
        value(7, "instant_damage", "瞬间伤害"),
        value(8, "jump_boost", "跳跃提升"),
        value(9, "nausea", "反胃"),
        value(10, "regeneration", "生命恢复"),
        value(11, "resistance", "抗性提升"),
        value(12, "fire_resistance", "抗火"),
        value(13, "water_breathing", "水下呼吸"),
        value(14, "invisibility", "隐身"),
        value(15, "blindness", "失明"),
        value(16, "night_vision", "夜视"),
        value(17, "hunger", "饥饿"),
        value(18, "weakness", "虚弱"),
        value(19, "poison", "中毒"),
        value(20, "wither", "凋零"),
        value(21, "health_boost", "生命提升"),
        value(22, "absorption", "伤害吸收"),
        value(23, "saturation", "饱和"),
        value(24, "levitation", "飘浮"),
        value(25, "fatal_poison", "中毒（致命）"),
        value(26, "conduit_power", "潮涌能量"),
        value(27, "slow_falling", "缓降"),
        value(28, "bad_omen", "不祥之兆"),
        value(29, "village_hero", "村庄英雄"),
        value(30, "darkness", "黑暗"),
        value(31, "trial_omen", "试炼之兆"),
        value(32, "wind_charged", "蓄风"),
        value(33, "weaving", "盘丝"),
        value(34, "oozing", "渗浆"),
        value(35, "infested", "寄生"),
        value(36, "raid_omen", "袭击之兆"),
        value(37, "breath_of_the_nautilus", "鹦鹉螺之息"),
    ]

    /// Numeric enchantment IDs from the Bedrock data-values table.
    static let enchantments: [BedrockDataValueEntry] = [
        value(0, "protection", "保护"),
        value(1, "fire_protection", "火焰保护"),
        value(2, "feather_falling", "摔落缓冲"),
        value(3, "blast_protection", "爆炸保护"),
        value(4, "projectile_protection", "弹射物保护"),
        value(5, "thorns", "荆棘"),
        value(6, "respiration", "水下呼吸"),
        value(7, "depth_strider", "深海探索者"),
        value(8, "aqua_affinity", "水下速掘"),
        value(9, "sharpness", "锋利"),
        value(10, "smite", "亡灵杀手"),
        value(11, "bane_of_arthropods", "节肢杀手"),
        value(12, "knockback", "击退"),
        value(13, "fire_aspect", "火焰附加"),
        value(14, "looting", "抢夺"),
        value(15, "efficiency", "效率"),
        value(16, "silk_touch", "精准采集"),
        value(17, "unbreaking", "耐久"),
        value(18, "fortune", "时运"),
        value(19, "power", "力量"),
        value(20, "punch", "冲击"),
        value(21, "flame", "火矢"),
        value(22, "infinity", "无限"),
        value(23, "luck_of_the_sea", "海之眷顾"),
        value(24, "lure", "饵钓"),
        value(25, "frost_walker", "冰霜行者"),
        value(26, "mending", "经验修补"),
        value(27, "binding_curse", "绑定诅咒"),
        value(28, "vanishing_curse", "消失诅咒"),
        value(29, "impaling", "穿刺"),
        value(30, "riptide", "激流"),
        value(31, "loyalty", "忠诚"),
        value(32, "channeling", "引雷"),
        value(33, "multishot", "多重射击"),
        value(34, "piercing", "穿透"),
        value(35, "quick_charge", "快速装填"),
        value(36, "soul_speed", "灵魂疾行"),
        value(37, "swift_sneak", "迅捷潜行"),
        value(38, "wind_burst", "风爆"),
        value(39, "density", "致密"),
        value(40, "breach", "破甲"),
        value(41, "lunge", "突进"),
    ]

    private static let entityEntriesByID: [Int: BedrockDataValueEntry] = {
        Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
    }()

    private static let entityEntriesByIdentifier: [String: BedrockDataValueEntry] = {
        Dictionary(uniqueKeysWithValues: entities.map { ($0.identifier.lowercased(), $0) })
    }()

    static func entity(forNumericID id: Int64) -> BedrockDataValueEntry? {
        guard id >= Int64(Int.min), id <= Int64(Int.max) else { return nil }
        return entityEntriesByID[Int(id)]
    }

    static func entity(forIdentifier identifier: String) -> BedrockDataValueEntry? {
        entityEntriesByIdentifier[identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    static func entityIdentifier(forRawValue rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let decimal = Int64(value), let entry = entity(forNumericID: decimal) {
            return entry.identifier
        }
        if value.lowercased().hasPrefix("0x"),
           let hexadecimal = Int64(value.dropFirst(2), radix: 16),
           let entry = entity(forNumericID: hexadecimal) {
            return entry.identifier
        }
        return value
    }

    static func search(_ entries: [BedrockDataValueEntry], query rawQuery: String) -> [BedrockDataValueEntry] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            String(entry.id).contains(query)
                || entry.hexadecimalID.lowercased().contains(query)
                || entry.identifier.lowercased().contains(query)
                || entry.displayName.lowercased().contains(query)
        }
    }

    private static func value(_ id: Int, _ identifier: String, _ displayName: String) -> BedrockDataValueEntry {
        BedrockDataValueEntry(id: id, identifier: identifier, displayName: displayName)
    }
}
