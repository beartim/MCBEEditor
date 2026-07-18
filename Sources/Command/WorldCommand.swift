import Foundation

struct CommandBlockCoordinate: Hashable {
    let x: Int64
    let y: Int32
    let z: Int64
}

struct CommandBlockBox: Hashable {
    let minimum: CommandBlockCoordinate
    let maximum: CommandBlockCoordinate

    init(_ first: CommandBlockCoordinate, _ second: CommandBlockCoordinate) {
        self.minimum = CommandBlockCoordinate(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            z: min(first.z, second.z)
        )
        self.maximum = CommandBlockCoordinate(
            x: max(first.x, second.x),
            y: max(first.y, second.y),
            z: max(first.z, second.z)
        )
    }

    var volume: UInt64? {
        guard let width = Self.inclusiveSpan(minimum.x, maximum.x),
              let height = Self.inclusiveSpan(Int64(minimum.y), Int64(maximum.y)),
              let depth = Self.inclusiveSpan(minimum.z, maximum.z) else { return nil }
        let (plane, overflow1) = width.multipliedReportingOverflow(by: height)
        let (volume, overflow2) = plane.multipliedReportingOverflow(by: depth)
        return overflow1 || overflow2 ? nil : volume
    }

    private static func inclusiveSpan(_ minimum: Int64, _ maximum: Int64) -> UInt64? {
        let (difference, overflow) = maximum.subtractingReportingOverflow(minimum)
        guard !overflow, difference >= 0 else { return nil }
        let (inclusive, plusOverflow) = UInt64(difference).addingReportingOverflow(1)
        return plusOverflow ? nil : inclusive
    }

    func contains(_ coordinate: CommandBlockCoordinate) -> Bool {
        (minimum.x...maximum.x).contains(coordinate.x)
            && (minimum.y...maximum.y).contains(coordinate.y)
            && (minimum.z...maximum.z).contains(coordinate.z)
    }

    func intersects(_ other: CommandBlockBox) -> Bool {
        minimum.x <= other.maximum.x && maximum.x >= other.minimum.x
            && minimum.y <= other.maximum.y && maximum.y >= other.minimum.y
            && minimum.z <= other.maximum.z && maximum.z >= other.minimum.z
    }
}

struct CommandCloneTraversal {
    let startX: Int64
    let startY: Int32
    let startZ: Int64
    let stepX: Int64
    let stepY: Int32
    let stepZ: Int64

    init(source: CommandBlockBox, target: CommandBlockBox, sameDimension: Bool) {
        let overlaps = sameDimension && source.intersects(target)
        let deltaX = target.minimum.x - source.minimum.x
        let deltaY = target.minimum.y - source.minimum.y
        let deltaZ = target.minimum.z - source.minimum.z
        stepX = overlaps && deltaX > 0 ? -1 : 1
        stepY = overlaps && deltaY > 0 ? -1 : 1
        stepZ = overlaps && deltaZ > 0 ? -1 : 1
        startX = stepX > 0 ? source.minimum.x : source.maximum.x
        startY = stepY > 0 ? source.minimum.y : source.maximum.y
        startZ = stepZ > 0 ? source.minimum.z : source.maximum.z
    }
}

struct CommandBlockStateSpec {
    let name: String
    let states: [NBTNamedTag]

    var isAir: Bool {
        let value = name.lowercased()
        return value == "minecraft:air" || value == "minecraft:cave_air" || value == "minecraft:void_air"
    }

    func modernState(version: Int32?) -> BedrockBlockState {
        var tags = [
            NBTNamedTag(name: "name", value: .string(name)),
            NBTNamedTag(name: "states", value: .compound(states))
        ]
        tags.append(NBTNamedTag(name: "version", value: .int(version ?? BedrockBlockState.defaultPaletteVersion)))
        return BedrockBlockState(nbt: .compound(tags), legacyID: nil, legacyData: nil)
    }

    func canRemainLegacy(layer: Int) -> Bool {
        guard states.isEmpty else { return false }
        if layer == 1 { return isAir }
        return BedrockLegacyBlockCatalog.block(forIdentifier: name) != nil
    }

    func legacyState() throws -> BedrockBlockState {
        guard states.isEmpty else {
            throw BlocktopographError.unsupported("旧版数字 ID SubChunk 不能保存命令中的现代 states；请使用 NULL")
        }
        guard let block = BedrockLegacyBlockCatalog.block(forIdentifier: name) else {
            throw BlocktopographError.unsupported("方块 \(name) 没有可用的旧版数字 ID")
        }
        return BedrockBlockState(nbt: nil, legacyID: UInt16(block.id), legacyData: 0)
    }
}

enum CommandTarget: Hashable {
    case uniqueID(Int64)
    case localPlayer
    case allPlayers
    case allEntities
    case identifier(String)

    var displayText: String {
        switch self {
        case .uniqueID(let value): return String(value)
        case .localPlayer: return "@s"
        case .allPlayers: return "@a"
        case .allEntities: return "@e"
        case .identifier(let value): return value
        }
    }
}

enum CommandTeleportY: Hashable {
    case fixed(Int32)
    case automatic

    var displayText: String {
        switch self {
        case .fixed(let value): return String(value)
        case .automatic: return "Auto"
        }
    }
}

enum CommandWeatherCondition: String {
    case clear
    case rain
    case thunder
}

struct CommandWeatherSettings {
    let condition: CommandWeatherCondition
    let duration: Int32?
    let intensity: Float?
    let automaticChange: Bool
}

enum ParsedWorldCommand {
    case help(command: String?)
    case clear(target: CommandTarget)
    case clearSpawnPoint(target: CommandTarget)
    case give(target: CommandTarget, itemIdentifier: String, count: Int64, itemTags: [NBTNamedTag])
    case kill(target: CommandTarget, killCreativePlayers: Bool)
    case kick(target: CommandTarget)
    case summon(identifier: String, dimension: Int32, position: CommandBlockCoordinate, additions: [NBTNamedTag])
    case effect(operation: CommandEffectOperation, target: CommandTarget, selection: CommandEffectSelection)
    case clone(
        sourceDimension: Int32,
        source: CommandBlockBox,
        targetDimension: Int32,
        destination: CommandBlockCoordinate
    )
    case fill(
        targetDimension: Int32,
        region: CommandBlockBox,
        layer0: CommandBlockStateSpec,
        layer1: CommandBlockStateSpec
    )
    case setBlock(
        targetDimension: Int32,
        position: CommandBlockCoordinate,
        layer0: CommandBlockStateSpec,
        layer1: CommandBlockStateSpec
    )
    case setWorldSpawn(position: CommandBlockCoordinate)
    case spawnPoint(target: CommandTarget, dimension: Int32, position: CommandBlockCoordinate)
    case teleport(target: CommandTarget, dimension: Int32, x: Int64, y: CommandTeleportY, z: Int64)
    case weather(settings: CommandWeatherSettings)
    case structure(operation: CommandStructureOperation)
    case tickingArea(operation: CommandTickingAreaOperation)
}

enum CommandStructureOperation {
    case save(name: String, dimension: Int32, region: CommandBlockBox)
    case load(name: String, dimension: Int32, destination: CommandBlockCoordinate)
    case delete(name: String?)
}

struct CommandTickingAreaSpec {
    let dimension: Int32
    let isCircle: Bool
    let minimumX: Int32
    let minimumZ: Int32
    let maximumX: Int32
    let maximumZ: Int32
    let name: String
    let preload: Bool
}

enum CommandTickingAreaOperation {
    case add(CommandTickingAreaSpec)
    case delete(name: String?)
    case list(dimension: Int32?)
}

enum CommandEffectSelection {
    case all
    case single(BedrockDataValueEntry)

    var displayText: String {
        switch self {
        case .all: return "ALL"
        case .single(let entry): return entry.identifier
        }
    }

    var entries: [BedrockDataValueEntry] {
        switch self {
        case .all: return BedrockDataValueCatalog.statusEffects
        case .single(let entry): return [entry]
        }
    }
}

enum CommandEffectOperation {
    case give(duration: Int32, amplifier: UInt8)
    case clear
}

enum CommandEffectNBT {
    static let rootName = "ActiveEffects"

    static func applying(
        operation: CommandEffectOperation,
        selection: CommandEffectSelection,
        to root: NBTValue
    ) throws -> (value: NBTValue, changed: Bool) {
        guard case .compound(var rootTags) = root else {
            throw BlocktopographError.malformedData("实体或玩家的 NBT 根必须是 Compound")
        }
        let matchingIndexes = rootTags.indices.filter {
            rootTags[$0].name.caseInsensitiveCompare(rootName) == .orderedSame
        }
        guard matchingIndexes.count <= 1 else {
            throw BlocktopographError.malformedData("NBT 根中存在多个 ActiveEffects 标签")
        }
        let activeIndex = matchingIndexes.first

        switch operation {
        case .give(let duration, let amplifier):
            var existing = try activeIndex.map { try effectValues(from: rootTags[$0].value) } ?? []
            let requestedIDs = Set(selection.entries.map(\.id))
            existing.removeAll { value in
                guard let id = try? effectID(in: value) else { return false }
                return requestedIDs.contains(id)
            }
            existing.append(contentsOf: selection.entries.map {
                effectCompound(id: $0.id, duration: duration, amplifier: amplifier)
            })
            let value: NBTValue = .list(.compound, existing)
            if let activeIndex = activeIndex {
                rootTags[activeIndex] = NBTNamedTag(name: rootTags[activeIndex].name, value: value)
            } else {
                rootTags.append(NBTNamedTag(name: rootName, value: value))
            }
            return (.compound(rootTags), true)

        case .clear:
            guard let activeIndex = activeIndex else { return (root, false) }
            if case .all = selection {
                rootTags.remove(at: activeIndex)
                return (.compound(rootTags), true)
            }
            let requestedIDs = Set(selection.entries.map(\.id))
            let existing = try effectValues(from: rootTags[activeIndex].value)
            var removed = false
            let remaining = try existing.filter { value in
                let id = try effectID(in: value)
                if requestedIDs.contains(id) {
                    removed = true
                    return false
                }
                return true
            }
            guard removed else { return (root, false) }
            if remaining.isEmpty {
                rootTags.remove(at: activeIndex)
            } else {
                rootTags[activeIndex] = NBTNamedTag(
                    name: rootTags[activeIndex].name,
                    value: .list(.compound, remaining)
                )
            }
            return (.compound(rootTags), true)
        }
    }

    static func effectCompound(id: Int, duration: Int32, amplifier: UInt8) -> NBTValue {
        .compound([
            NBTNamedTag(name: "Ambient", value: .byte(0)),
            NBTNamedTag(name: "Amplifier", value: .byte(Int8(bitPattern: amplifier))),
            NBTNamedTag(name: "DisplayOnScreenTextureAnimation", value: .byte(0)),
            NBTNamedTag(name: "Duration", value: .int(duration)),
            NBTNamedTag(name: "DurationEasy", value: .int(duration)),
            NBTNamedTag(name: "DurationNormal", value: .int(duration)),
            NBTNamedTag(name: "DurationHard", value: .int(duration)),
            NBTNamedTag(name: "Id", value: .byte(Int8(clamping: id))),
            NBTNamedTag(name: "ShowParticles", value: .byte(0))
        ])
    }

    private static func effectValues(from value: NBTValue) throws -> [NBTValue] {
        switch value {
        case .list(.compound, let values):
            guard values.allSatisfy({ $0.type == .compound }) else {
                throw BlocktopographError.malformedData("ActiveEffects 必须是 Compound List")
            }
            for value in values { _ = try effectID(in: value) }
            return values
        case .list(.end, let values) where values.isEmpty:
            return []
        default:
            throw BlocktopographError.malformedData("ActiveEffects 必须是 Compound List")
        }
    }

    private static func effectID(in value: NBTValue) throws -> Int {
        guard case .compound(let tags) = value,
              let tag = tags.first(where: { $0.name.caseInsensitiveCompare("Id") == .orderedSame }) else {
            throw BlocktopographError.malformedData("状态效果 Compound 缺少数字 Id 标签")
        }
        let raw: Int64
        switch tag.value {
        case .byte(let value): raw = Int64(UInt8(bitPattern: value))
        case .short(let value): raw = Int64(value)
        case .int(let value): raw = Int64(value)
        case .long(let value): raw = value
        default:
            throw BlocktopographError.malformedData("状态效果 Id 必须是数字标签")
        }
        guard raw >= 0, raw <= Int64(Int.max) else {
            throw BlocktopographError.malformedData("状态效果 Id 超出有效范围")
        }
        return Int(raw)
    }
}

enum WorldCommandParser {
    static let commandNames = [
        "help", "clear", "clearspawnpoint", "clone", "effect", "fill", "give", "kill", "kick",
        "setblock", "setworldspawn", "spawnpoint", "structure", "summon", "teleport",
        "tickingarea", "weather"
    ]

    static let usage: [String: String] = [
        "help": "help [命令]\n无参数：显示全部命令；指定已存在的命令：显示该命令的使用方法。",
        "clear": "clear 目标\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。清除所有匹配玩家与实体的物品；村民交易数据不会清除。",
        "clearspawnpoint": "clearspawnpoint 目标\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。只对匹配的玩家清除出生点。",
        "clone": "clone 源维度 x1 y1 z1 x2 y2 z2 目标维度 x3 y3 z3\n维度必须为 overworld、nether 或 the_end。复制源区域两角到目标维度的目标起点；涉及未加载区块时会先写入空气区块与生成完成状态，再执行复制。重叠区域使用命令开始时的原始源数据。\n示例：clone overworld 0 0 0 5 100 46 nether 9 50 9",
        "effect": "effect give 目标 状态效果ID或ALL 持续时间 效果等级\neffect clear 目标 状态效果ID或ALL\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。状态效果 ID 必须存在于当前基岩版数据值中；ALL 必须大写。give 的持续时间写入 Duration、DurationEasy、DurationNormal、DurationHard，效果等级为零基数（输入 50 表示 51 级）。clear 只能输入三个参数。\n示例：effect give @a strength 12000 50\n示例：effect clear @e ALL",
        "fill": "fill 目标维度 x1 y1 z1 x2 y2 z2 层0方块名 层0states 层1方块名 层1states\n维度必须为 overworld、nether 或 the_end。states 可输入 NULL，或输入任意 NBT 标签类型；支持数组、List、Compound 与多重嵌套。旧版数字 ID SubChunk 遇到无数字 ID、非空气层 1 或非空 states 时会自动升级为新版 SubChunk。\n示例：fill the_end 0 0 0 60 200 16 minecraft:leaves 'String'\"old_leaf_type\"=\"oak\",'Byte'\"persistent_bit\"=\"0\",'Byte'\"update_bit\"=\"0\" minecraft:chest 'Int'\"facing_direction\"=\"3\"",
        "give": "give 目标 物品 数目 物品标签\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；物品必须使用完整字符串 ID；数目必须是大于 0 的 Int64。物品标签可输入 NULL，或输入任意类型、可多重嵌套的 NBT 标签。玩家写入物品栏第一个空槽位，物品栏已满时替换最后一格，其他实体替换 Mainhand；没有 Mainhand 标签的实体会跳过。\n示例：give minecraft:cow minecraft:lit_smoker 99 'Compound'\"tag\"=\"{'Byte'\"Unbreakable\"=\"1\"}\",'Short'\"Damage\"=\"1\"",
        "kill": "kill 目标 是否杀死创造模式玩家\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；第二个参数只能是 0 或 1。非玩家实体直接删除，玩家生命值 Current 设为 0.0；创造模式玩家在参数为 0 时保持不变。\n示例：kill @a 1",
        "kick": "kick 目标\n目标只能是在线玩家的非零 UniqueID或 @a。UniqueID 删除对应在线玩家数据，@a 删除全部在线玩家数据。",
        "setblock": "setblock 目标维度 x y z 层0方块名 层0states 层1方块名 层1states\nfill 的单方块版本。维度必须为 overworld、nether 或 the_end；states 格式与 fill 完全相同。\n示例：setblock overworld 0 64 0 minecraft:stone NULL minecraft:air NULL",
        "setworldspawn": "setworldspawn x y z\n设置世界重生点；坐标必须恰好输入三个整数。世界重生点位于主世界。\n示例：setworldspawn 0 80 0",
        "spawnpoint": "spawnpoint 目标 维度 x y z\n目标必须是非零 UniqueID、@s、@a、@e 或 minecraft:player，且最终只能匹配玩家；维度必须为 overworld、nether 或 the_end。\n示例：spawnpoint @a the_end 0 100 0",
        "structure": "structure save 名称 维度 x1 y1 z1 x2 y2 z2\nstructure load 名称 维度 x y z\nstructure delete 名称或ALL\n名称必须为 namespace:name。save 会直接覆盖同名 structuretemplate_ 记录；load/delete 找不到名称时失败。\n示例：structure save mystructure:1 overworld 0 0 0 50 50 50",
        "summon": "summon 实体类型 实体维度 x y z NBT标签或default\n实体维度必须为 overworld、nether 或 the_end；最后一个参数输入 default 时不修改实体通用 NBT，否则可输入任意类型、可多重嵌套的非空 NBT 标签，且不能为 NULL。\n示例：summon minecraft:pig overworld 0 64 0 default\n示例：summon minecraft:pig overworld 0 64 0 'Byte'\"Invulnerable\"=\"1\",'String'\"CustomName\"=\"MyPig\"",
        "teleport": "teleport 目标 维度 x y或Auto z\n目标只能是非零 UniqueID、@s、@a 或 @e；维度必须为 overworld、nether 或 the_end。Y 输入 Auto 时，会读取目标 X/Z 列中最高非空气方块并传送到其上方。\n示例：teleport -4294967270 the_end 10 70 10\n示例：teleport @a overworld 0 Auto 0",
        "tickingarea": "tickingarea add square 维度 x1 z1 x2 z2 名称 0或1\ntickingarea add circle 维度 区块X 区块Z 名称 0或1\ntickingarea delete 名称或ALL\ntickingarea list 维度或ALL\n圆形 add 只创建指定区块对应的单区块圆形常加载区域；list 逐行显示。\n示例：tickingarea add square nether 0 0 1 1 Base 1\n示例：tickingarea add circle overworld 0 0 Spawn 1\n示例：tickingarea list overworld",
        "weather": "weather clear 0或1\nweather rain 持续游戏刻 强度 0或1\nweather thunder 持续游戏刻 强度 0或1\n强度必须是 0.0～1.0 的浮点数；最后一个参数控制天气是否自动变化。clear 只接受自动变化参数。\n示例：weather clear 1\n示例：weather thunder 12000 1.0 0"
    ]

    static func parse(_ line: String) throws -> ParsedWorldCommand {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BlocktopographError.malformedData("请输入命令") }
        guard !trimmed.hasPrefix("/") else {
            throw BlocktopographError.malformedData("命令不需要斜杠，请直接输入命令名称")
        }
        let tokens = try tokenize(trimmed)
        guard let command = tokens.first else { throw BlocktopographError.malformedData("请输入命令") }
        let arguments = Array(tokens.dropFirst())
        switch command {
        case "help":
            guard arguments.count <= 1 else { throw usageError(command) }
            if let target = arguments.first, !commandNames.contains(target) {
                throw BlocktopographError.malformedData("不存在的命令：\(target)")
            }
            return .help(command: arguments.first)
        case "clear":
            guard arguments.count == 1 else { throw usageError(command) }
            return .clear(target: try parseTarget(arguments[0]))
        case "clearspawnpoint":
            guard arguments.count == 1 else { throw usageError(command) }
            return .clearSpawnPoint(target: try parseTarget(arguments[0]))
        case "effect":
            guard let action = arguments.first else { throw usageError(command) }
            switch action {
            case "give":
                guard arguments.count == 5 else { throw usageError(command) }
                return .effect(
                    operation: .give(
                        duration: try parseEffectDuration(arguments[3]),
                        amplifier: try parseEffectAmplifier(arguments[4])
                    ),
                    target: try parseTarget(arguments[1]),
                    selection: try parseEffectSelection(arguments[2])
                )
            case "clear":
                guard arguments.count == 3 else { throw usageError(command) }
                return .effect(
                    operation: .clear,
                    target: try parseTarget(arguments[1]),
                    selection: try parseEffectSelection(arguments[2])
                )
            default:
                throw usageError(command)
            }
        case "give":
            guard arguments.count == 4 else { throw usageError(command) }
            return .give(
                target: try parseTarget(arguments[0]),
                itemIdentifier: try parseNamespacedIdentifier(arguments[1], kind: "物品"),
                count: try parseItemCount(arguments[2]),
                itemTags: try parseStates(arguments[3])
            )
        case "kill":
            guard arguments.count == 2 else { throw usageError(command) }
            return .kill(
                target: try parseTarget(arguments[0]),
                killCreativePlayers: try parseBooleanFlag(arguments[1], name: "是否杀死创造模式玩家")
            )
        case "kick":
            guard arguments.count == 1 else { throw usageError(command) }
            let target = try parseTarget(arguments[0])
            switch target {
            case .uniqueID, .allPlayers:
                return .kick(target: target)
            default:
                throw usageError(command)
            }
        case "summon":
            guard arguments.count == 6 else { throw usageError(command) }
            let identifier = try parseNamespacedIdentifier(arguments[0], kind: "实体")
            let dimension = try parseDimension(arguments[1])
            let position = try parseCoordinates(Array(arguments[2...4]))[0]
            let additions: [NBTNamedTag]
            if arguments[5] == "default" {
                additions = []
            } else {
                additions = try parseStates(arguments[5])
                guard !additions.isEmpty else {
                    throw BlocktopographError.malformedData("summon 的最后一个参数只能是 default 或非空 NBT 标签")
                }
            }
            let protected = Set(["uniqueid", "pos", "dimensionid", "dimension", "identifier", "id", "definitions"])
            if let invalid = additions.first(where: { protected.contains($0.name.lowercased()) }) {
                throw BlocktopographError.malformedData("summon 不能覆盖由命令控制的标签：\(invalid.name)")
            }
            return .summon(identifier: identifier, dimension: dimension, position: position, additions: additions)
        case "clone":
            guard arguments.count == 11 else { throw usageError(command) }
            let sourceDimension = try parseDimension(arguments[0])
            let sourceCoordinates = try parseCoordinates(Array(arguments[1...6]))
            let targetDimension = try parseDimension(arguments[7])
            let destination = try parseCoordinates(Array(arguments[8...10]))[0]
            return .clone(
                sourceDimension: sourceDimension,
                source: CommandBlockBox(sourceCoordinates[0], sourceCoordinates[1]),
                targetDimension: targetDimension,
                destination: destination
            )
        case "fill":
            guard arguments.count == 11 else { throw usageError(command) }
            let targetDimension = try parseDimension(arguments[0])
            let coordinates = try parseCoordinates(Array(arguments[1...6]))
            let layer0 = try CommandBlockStateSpec(
                name: parseBlockName(arguments[7]),
                states: parseStates(arguments[8])
            )
            let layer1 = try CommandBlockStateSpec(
                name: parseBlockName(arguments[9]),
                states: parseStates(arguments[10])
            )
            return .fill(
                targetDimension: targetDimension,
                region: CommandBlockBox(coordinates[0], coordinates[1]),
                layer0: layer0,
                layer1: layer1
            )
        case "setblock":
            guard arguments.count == 8 else { throw usageError(command) }
            return .setBlock(
                targetDimension: try parseDimension(arguments[0]),
                position: try parseCoordinates(Array(arguments[1...3]))[0],
                layer0: CommandBlockStateSpec(
                    name: try parseBlockName(arguments[4]),
                    states: try parseStates(arguments[5])
                ),
                layer1: CommandBlockStateSpec(
                    name: try parseBlockName(arguments[6]),
                    states: try parseStates(arguments[7])
                )
            )
        case "setworldspawn":
            guard arguments.count == 3 else { throw usageError(command) }
            return .setWorldSpawn(position: try parseCoordinates(arguments)[0])
        case "spawnpoint":
            guard arguments.count == 5 else { throw usageError(command) }
            return .spawnPoint(
                target: try parseTarget(arguments[0]),
                dimension: try parseDimension(arguments[1]),
                position: try parseCoordinates(Array(arguments[2...4]))[0]
            )
        case "teleport":
            guard arguments.count == 5 else { throw usageError(command) }
            return .teleport(
                target: try parseTeleportTarget(arguments[0]),
                dimension: try parseDimension(arguments[1]),
                x: try parseTeleportHorizontalCoordinate(arguments[2], name: "X"),
                y: try parseTeleportY(arguments[3]),
                z: try parseTeleportHorizontalCoordinate(arguments[4], name: "Z")
            )
        case "weather":
            guard let condition = arguments.first.flatMap(CommandWeatherCondition.init(rawValue:)) else {
                throw usageError(command)
            }
            switch condition {
            case .clear:
                guard arguments.count == 2 else { throw usageError(command) }
                return .weather(settings: CommandWeatherSettings(
                    condition: .clear,
                    duration: nil,
                    intensity: nil,
                    automaticChange: try parseBooleanFlag(arguments[1], name: "天气是否自动变化")
                ))
            case .rain, .thunder:
                guard arguments.count == 4 else { throw usageError(command) }
                return .weather(settings: CommandWeatherSettings(
                    condition: condition,
                    duration: try parseWeatherDuration(arguments[1]),
                    intensity: try parseWeatherIntensity(arguments[2]),
                    automaticChange: try parseBooleanFlag(arguments[3], name: "天气是否自动变化")
                ))
            }
        case "structure":
            guard let action = arguments.first else { throw usageError(command) }
            switch action {
            case "save":
                guard arguments.count == 9 else { throw usageError(command) }
                let name = try parseNamespacedIdentifier(arguments[1], kind: "结构名称")
                let dimension = try parseDimension(arguments[2])
                let coordinates = try parseCoordinates(Array(arguments[3...8]))
                return .structure(operation: .save(
                    name: name,
                    dimension: dimension,
                    region: CommandBlockBox(coordinates[0], coordinates[1])
                ))
            case "load":
                guard arguments.count == 6 else { throw usageError(command) }
                return .structure(operation: .load(
                    name: try parseNamespacedIdentifier(arguments[1], kind: "结构名称"),
                    dimension: try parseDimension(arguments[2]),
                    destination: try parseCoordinates(Array(arguments[3...5]))[0]
                ))
            case "delete":
                guard arguments.count == 2 else { throw usageError(command) }
                if arguments[1] == "ALL" { return .structure(operation: .delete(name: nil)) }
                return .structure(operation: .delete(
                    name: try parseNamespacedIdentifier(arguments[1], kind: "结构名称")
                ))
            default:
                throw usageError(command)
            }
        case "tickingarea":
            guard let action = arguments.first else { throw usageError(command) }
            switch action {
            case "add":
                guard arguments.count >= 2 else { throw usageError(command) }
                let shape = arguments[1]
                guard shape == "square" || shape == "circle" else { throw usageError(command) }
                let area: CommandTickingAreaSpec
                if shape == "square" {
                    guard arguments.count == 9 else { throw usageError(command) }
                    let dimension = try parseDimension(arguments[2])
                    let x1 = try parseChunkCoordinate(arguments[3], name: "X1")
                    let z1 = try parseChunkCoordinate(arguments[4], name: "Z1")
                    let x2 = try parseChunkCoordinate(arguments[5], name: "X2")
                    let z2 = try parseChunkCoordinate(arguments[6], name: "Z2")
                    area = CommandTickingAreaSpec(
                        dimension: dimension,
                        isCircle: false,
                        minimumX: min(x1, x2),
                        minimumZ: min(z1, z2),
                        maximumX: max(x1, x2),
                        maximumZ: max(z1, z2),
                        name: try parseTickingAreaName(arguments[7]),
                        preload: try parseBooleanFlag(arguments[8], name: "是否预加载")
                    )
                } else {
                    guard arguments.count == 7 else { throw usageError(command) }
                    let dimension = try parseDimension(arguments[2])
                    let chunkX = try parseChunkCoordinate(arguments[3], name: "区块 X")
                    let chunkZ = try parseChunkCoordinate(arguments[4], name: "区块 Z")
                    let centerBlockX = Int64(chunkX) * 16
                    let centerBlockZ = Int64(chunkZ) * 16
                    guard let blockX = Int32(exactly: centerBlockX),
                          let blockZ = Int32(exactly: centerBlockZ) else {
                        throw BlocktopographError.malformedData("圆形常加载区域坐标溢出")
                    }
                    area = CommandTickingAreaSpec(
                        dimension: dimension,
                        isCircle: true,
                        minimumX: blockX,
                        minimumZ: blockZ,
                        maximumX: blockX,
                        maximumZ: blockZ,
                        name: try parseTickingAreaName(arguments[5]),
                        preload: try parseBooleanFlag(arguments[6], name: "是否预加载")
                    )
                }
                try validateTickingAreaSpec(area)
                return .tickingArea(operation: .add(area))
            case "delete":
                guard arguments.count == 2 else { throw usageError(command) }
                return .tickingArea(operation: .delete(name: arguments[1] == "ALL" ? nil : try parseTickingAreaName(arguments[1])))
            case "list":
                guard arguments.count == 2 else { throw usageError(command) }
                return .tickingArea(operation: .list(dimension: arguments[1] == "ALL" ? nil : try parseDimension(arguments[1])))
            default:
                throw usageError(command)
            }
        default:
            throw BlocktopographError.malformedData("不存在的命令：\(command)。输入 help 查看全部命令。")
        }
    }

    static func helpText(for command: String? = nil) -> String {
        if let command = command { return usage[command] ?? "不存在的命令：\(command)" }
        return commandNames.compactMap { usage[$0] }.joined(separator: "\n\n")
    }

    private static func usageError(_ command: String) -> BlocktopographError {
        .malformedData("参数格式错误。\n\(usage[command] ?? command)")
    }

    static func dimensionName(for rawValue: Int32) -> String {
        switch rawValue {
        case 0: return "overworld"
        case 1: return "nether"
        case 2: return "the_end"
        default: return "unknown(\(rawValue))"
        }
    }

    private static func parseDimension(_ text: String) throws -> Int32 {
        switch text {
        case "overworld": return 0
        case "nether": return 1
        case "the_end": return 2
        default:
            throw BlocktopographError.malformedData(
                "维度名称无效：\(text)。只能使用 overworld、nether 或 the_end"
            )
        }
    }

    private static func validateTickingAreaSpec(_ area: CommandTickingAreaSpec) throws {
        let count: Int64
        if area.isCircle {
            let centerX = (Int64(area.minimumX) + Int64(area.maximumX)) / 2
            let centerZ = (Int64(area.minimumZ) + Int64(area.maximumZ)) / 2
            let radiusBlocks = max(
                abs(Int64(area.maximumX) - centerX),
                abs(Int64(area.maximumZ) - centerZ)
            )
            let radius = (radiusBlocks + 15) / 16
            guard radius <= 4 else {
                throw BlocktopographError.unsupported("圆形常加载区域半径最多为 4 个区块")
            }
            var total: Int64 = 0
            for dz in -radius...radius {
                for dx in -radius...radius where dx * dx + dz * dz <= radius * radius { total += 1 }
            }
            count = total
        } else {
            count = (Int64(abs(Int64(area.maximumX) - Int64(area.minimumX))) + 1)
                * (Int64(abs(Int64(area.maximumZ) - Int64(area.minimumZ))) + 1)
        }
        guard count > 0, count <= 100 else {
            throw BlocktopographError.unsupported("每个常加载区域最多包含 100 个区块")
        }
    }

    private static func parseChunkCoordinate(_ text: String, name: String) throws -> Int32 {
        guard let value = Int32(text) else {
            throw BlocktopographError.malformedData("\(name) 必须是 Int32 区块坐标：\(text)")
        }
        return value
    }

    private static func parseTickingAreaName(_ text: String) throws -> String {
        guard !text.isEmpty, text != "ALL" else {
            throw BlocktopographError.malformedData("常加载区域名称不能为空，也不能使用保留字 ALL")
        }
        guard text.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil else {
            throw BlocktopographError.malformedData("常加载区域名称只能包含字母、数字、下划线、点、冒号和连字符")
        }
        return text
    }

    private static func parseTeleportTarget(_ text: String) throws -> CommandTarget {
        switch text {
        case "@s": return .localPlayer
        case "@a": return .allPlayers
        case "@e": return .allEntities
        default:
            guard let uniqueID = Int64(text), uniqueID != 0 else {
                throw BlocktopographError.malformedData("teleport 目标只能是非零 UniqueID、@s、@a 或 @e")
            }
            return .uniqueID(uniqueID)
        }
    }

    private static func parseTeleportHorizontalCoordinate(_ text: String, name: String) throws -> Int64 {
        guard let value = Int64(text) else {
            throw BlocktopographError.malformedData("teleport 的 \(name) 坐标必须是 Int64 整数：\(text)")
        }
        return value
    }

    private static func parseTeleportY(_ text: String) throws -> CommandTeleportY {
        if text == "Auto" { return .automatic }
        guard let value = Int32(text) else {
            throw BlocktopographError.malformedData("teleport 的 Y 坐标必须是 Int32 整数或 Auto：\(text)")
        }
        return .fixed(value)
    }

    private static func parseWeatherDuration(_ text: String) throws -> Int32 {
        guard let value = Int32(text), value >= 0 else {
            throw BlocktopographError.malformedData("天气持续时间必须是 0…2147483647 的游戏刻整数")
        }
        return value
    }

    private static func parseWeatherIntensity(_ text: String) throws -> Float {
        guard let value = Float(text), value.isFinite, value >= 0, value <= 1 else {
            throw BlocktopographError.malformedData("天气强度必须是 0.0～1.0 的浮点数")
        }
        return value
    }

    private static func parseTarget(_ text: String) throws -> CommandTarget {
        switch text {
        case "@s": return .localPlayer
        case "@a": return .allPlayers
        case "@e": return .allEntities
        default:
            if let uniqueID = Int64(text), uniqueID != 0 { return .uniqueID(uniqueID) }
            return .identifier(try parseNamespacedIdentifier(text, kind: "目标实体"))
        }
    }

    private static func parseNamespacedIdentifier(_ text: String, kind: String) throws -> String {
        let pattern = "^[a-z0-9_.-]+:[a-z0-9_./-]+$"
        guard text.range(of: pattern, options: .regularExpression) != nil else {
            throw BlocktopographError.malformedData("\(kind)字符串 ID 格式无效：\(text)")
        }
        return text
    }

    private static func parseEffectSelection(_ text: String) throws -> CommandEffectSelection {
        if text == "ALL" { return .all }
        guard let entry = BedrockDataValueCatalog.statusEffects.first(where: { $0.identifier == text }) else {
            throw BlocktopographError.malformedData(
                "状态效果字符串 ID 没有对应的数字 ID：\(text)"
            )
        }
        return .single(entry)
    }

    private static func parseEffectDuration(_ text: String) throws -> Int32 {
        guard let value = Int32(text), value >= 0 else {
            throw BlocktopographError.malformedData("状态效果持续时间必须是 0…2147483647 的整数")
        }
        return value
    }

    private static func parseEffectAmplifier(_ text: String) throws -> UInt8 {
        guard let value = UInt8(text) else {
            throw BlocktopographError.malformedData("状态效果等级必须是 0…255 的整数；输入值为零基数")
        }
        return value
    }

    private static func parseItemCount(_ text: String) throws -> Int64 {
        guard let value = Int64(text), value > 0 else {
            throw BlocktopographError.malformedData("物品数目必须是大于 0 的 Int64 整数")
        }
        return value
    }

    private static func parseBooleanFlag(_ text: String, name: String) throws -> Bool {
        switch text {
        case "0": return false
        case "1": return true
        default: throw BlocktopographError.malformedData("\(name)只能输入 0 或 1")
        }
    }

    private static func parseCoordinates(_ values: [String]) throws -> [CommandBlockCoordinate] {
        guard values.count % 3 == 0 else { throw BlocktopographError.malformedData("坐标必须每组三个整数") }
        var result = [CommandBlockCoordinate]()
        for offset in stride(from: 0, to: values.count, by: 3) {
            guard let x = Int64(values[offset]),
                  let y = Int32(values[offset + 1]),
                  let z = Int64(values[offset + 2]) else {
                throw BlocktopographError.malformedData("坐标必须是整数：\(values[offset...offset + 2].joined(separator: " "))")
            }
            result.append(CommandBlockCoordinate(x: x, y: y, z: z))
        }
        return result
    }

    private static func parseBlockName(_ text: String) throws -> String {
        let pattern = "^[a-z0-9_.-]+:[a-z0-9_./-]+$"
        guard text.range(of: pattern, options: .regularExpression) != nil else {
            throw BlocktopographError.malformedData("方块名称格式无效：\(text)")
        }
        return text
    }

    static func parseStates(_ text: String) throws -> [NBTNamedTag] {
        if text == "NULL" { return [] }
        guard !text.isEmpty else {
            throw BlocktopographError.malformedData("NBT 标签不能为空；不添加标签请填写 NULL")
        }
        var parser = CommandNBTTextParser(text: text)
        let tags = try parser.parseNamedTags()
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw BlocktopographError.malformedData("NBT 标签末尾存在无法识别的内容：\(parser.remainingText)")
        }
        return tags
    }

    private static func tokenize(_ text: String) throws -> [String] {
        var tokens = [String]()
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }
            let start = index
            if text[index] == "'" {
                var parser = CommandNBTTextParser(text: text, index: index)
                _ = try parser.parseNamedTags()
                index = parser.index
                if index < text.endIndex, !text[index].isWhitespace {
                    throw BlocktopographError.malformedData("NBT 参数后必须使用空格分隔下一个命令参数")
                }
            } else {
                while index < text.endIndex, !text[index].isWhitespace {
                    index = text.index(after: index)
                }
            }
            tokens.append(String(text[start..<index]))
        }
        return tokens
    }

    private indirect enum CommandNBTTypeDescriptor {
        case value(NBTTagType)
        case list(CommandNBTTypeDescriptor)

        var tagType: NBTTagType {
            switch self {
            case .value(let type): return type
            case .list: return .list
            }
        }
    }

    private struct CommandNBTTextParser {
        let text: String
        var index: String.Index

        init(text: String, index: String.Index? = nil) {
            self.text = text
            self.index = index ?? text.startIndex
        }

        var isAtEnd: Bool { index >= text.endIndex }
        var remainingText: String { isAtEnd ? "" : String(text[index...]) }

        mutating func skipWhitespace() {
            while !isAtEnd, text[index].isWhitespace { index = text.index(after: index) }
        }

        mutating func parseNamedTags(until closing: Character? = nil) throws -> [NBTNamedTag] {
            skipWhitespace()
            if let closing = closing, peek == closing { return [] }
            var tags = [NBTNamedTag]()
            var names = Set<String>()
            while true {
                let tag = try parseNamedTag()
                guard names.insert(tag.name).inserted else {
                    throw BlocktopographError.malformedData("同一 Compound 中存在重复 NBT 标签：\(tag.name)")
                }
                tags.append(tag)
                let endOfTag = index
                skipWhitespace()
                if let closing = closing, peek == closing { break }
                if peek != "," {
                    // At the command root, whitespace terminates the NBT argument.
                    // Restore the exact end so the tokenizer can keep the next
                    // command parameter separate. Nested Compound whitespace is
                    // still consumed because it has an explicit closing brace.
                    if closing == nil { index = endOfTag }
                    break
                }
                advance()
                skipWhitespace()
                if isAtEnd || (closing != nil && peek == closing) {
                    throw BlocktopographError.malformedData("NBT 标签列表末尾不能有逗号")
                }
            }
            return tags
        }

        private mutating func parseNamedTag() throws -> NBTNamedTag {
            let descriptor = try parseTypeDescriptor()
            let name = try parseQuotedString(quote: "\"")
            guard !name.isEmpty else { throw BlocktopographError.malformedData("NBT 标签名称不能为空") }
            try expect("=")
            try expect("\"")
            let value = try parsePayload(descriptor, listTerminator: "\"")
            try expect("\"")
            return NBTNamedTag(name: name, value: value)
        }

        private mutating func parseTypeDescriptor() throws -> CommandNBTTypeDescriptor {
            let name = try parseQuotedString(quote: "'")
            guard let type = tagType(named: name), type != .end else {
                throw BlocktopographError.malformedData("不支持的 NBT 类型：\(name)")
            }
            if type == .list {
                return .list(try parseTypeDescriptor())
            }
            return .value(type)
        }

        private func tagType(named name: String) -> NBTTagType? {
            switch name {
            case "Byte": return .byte
            case "Short": return .short
            case "Int": return .int
            case "Long": return .long
            case "Float": return .float
            case "Double": return .double
            case "ByteArray": return .byteArray
            case "String": return .string
            case "List": return .list
            case "Compound": return .compound
            case "IntArray": return .intArray
            case "LongArray": return .longArray
            default: return nil
            }
        }

        private mutating func parsePayload(
            _ descriptor: CommandNBTTypeDescriptor,
            listTerminator: Character
        ) throws -> NBTValue {
            switch descriptor {
            case .list(let element):
                return .list(element.tagType, try parseListValues(element: element, terminator: listTerminator))
            case .value(let type):
                switch type {
                case .byte:
                    let raw = try readScalarUntilQuote()
                    guard let number = Int8(raw) else { throw invalidValue(type, raw) }
                    return .byte(number)
                case .short:
                    let raw = try readScalarUntilQuote()
                    guard let number = Int16(raw) else { throw invalidValue(type, raw) }
                    return .short(number)
                case .int:
                    let raw = try readScalarUntilQuote()
                    guard let number = Int32(raw) else { throw invalidValue(type, raw) }
                    return .int(number)
                case .long:
                    let raw = try readScalarUntilQuote()
                    guard let number = Int64(raw) else { throw invalidValue(type, raw) }
                    return .long(number)
                case .float:
                    let raw = try readScalarUntilQuote()
                    guard let number = Float(raw), number.isFinite else { throw invalidValue(type, raw) }
                    return .float(number)
                case .double:
                    let raw = try readScalarUntilQuote()
                    guard let number = Double(raw), number.isFinite else { throw invalidValue(type, raw) }
                    return .double(number)
                case .string:
                    return .string(try readEscaped(until: "\""))
                case .byteArray:
                    let values: [Int8] = try parseNumericArray(type: type, convert: { Int8($0) })
                    return .byteArray(Data(values.map { UInt8(bitPattern: $0) }))
                case .intArray:
                    let values: [Int32] = try parseNumericArray(type: type, convert: { Int32($0) })
                    return .intArray(values)
                case .longArray:
                    let values: [Int64] = try parseNumericArray(type: type, convert: { Int64($0) })
                    return .longArray(values)
                case .compound:
                    try expect("{")
                    let tags = try parseNamedTags(until: "}")
                    try expect("}")
                    return .compound(tags)
                case .list, .end:
                    throw BlocktopographError.malformedData("NBT 类型描述无效")
                }
            }
        }

        private mutating func parseListValues(
            element: CommandNBTTypeDescriptor,
            terminator: Character
        ) throws -> [NBTValue] {
            skipWhitespace()
            if peek == terminator { return [] }
            var values = [NBTValue]()
            while true {
                values.append(try parseListElement(element, terminator: terminator))
                skipWhitespace()
                if peek == terminator { break }
                guard peek == "," else {
                    throw BlocktopographError.malformedData("List 元素之间必须使用英文逗号分隔")
                }
                advance()
                skipWhitespace()
                if peek == terminator {
                    throw BlocktopographError.malformedData("List 末尾不能有逗号")
                }
            }
            return values
        }

        private mutating func parseListElement(
            _ descriptor: CommandNBTTypeDescriptor,
            terminator: Character
        ) throws -> NBTValue {
            switch descriptor {
            case .list(let child):
                try expect("[")
                let values = try parseListValues(element: child, terminator: "]")
                try expect("]")
                return .list(child.tagType, values)
            case .value(let type):
                switch type {
                case .compound:
                    try expect("{")
                    let tags = try parseNamedTags(until: "}")
                    try expect("}")
                    return .compound(tags)
                case .byteArray:
                    let values: [Int8] = try parseNumericArray(type: type, convert: { Int8($0) })
                    return .byteArray(Data(values.map { UInt8(bitPattern: $0) }))
                case .intArray:
                    return .intArray(try parseNumericArray(type: type, convert: { Int32($0) }))
                case .longArray:
                    return .longArray(try parseNumericArray(type: type, convert: { Int64($0) }))
                case .string:
                    return .string(try readListScalar(terminator: terminator, preserveWhitespace: true))
                case .byte:
                    let raw = try readListScalar(terminator: terminator)
                    guard let number = Int8(raw) else { throw invalidValue(type, raw) }
                    return .byte(number)
                case .short:
                    let raw = try readListScalar(terminator: terminator)
                    guard let number = Int16(raw) else { throw invalidValue(type, raw) }
                    return .short(number)
                case .int:
                    let raw = try readListScalar(terminator: terminator)
                    guard let number = Int32(raw) else { throw invalidValue(type, raw) }
                    return .int(number)
                case .long:
                    let raw = try readListScalar(terminator: terminator)
                    guard let number = Int64(raw) else { throw invalidValue(type, raw) }
                    return .long(number)
                case .float:
                    let raw = try readListScalar(terminator: terminator)
                    guard let number = Float(raw), number.isFinite else { throw invalidValue(type, raw) }
                    return .float(number)
                case .double:
                    let raw = try readListScalar(terminator: terminator)
                    guard let number = Double(raw), number.isFinite else { throw invalidValue(type, raw) }
                    return .double(number)
                case .list, .end:
                    throw BlocktopographError.malformedData("List 元素类型无效")
                }
            }
        }

        private mutating func parseNumericArray<T>(
            type: NBTTagType,
            convert: (String) -> T?
        ) throws -> [T] {
            try expect("[")
            skipWhitespace()
            if peek == "]" { advance(); return [] }
            var values = [T]()
            while true {
                let raw = try readUntilAny([",", "]"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty, let value = convert(raw) else { throw invalidValue(type, raw) }
                values.append(value)
                guard let character = peek else {
                    throw BlocktopographError.malformedData("\(type.displayName) 缺少右中括号")
                }
                if character == "]" { advance(); break }
                advance()
                skipWhitespace()
                if peek == "]" { throw BlocktopographError.malformedData("数组末尾不能有逗号") }
            }
            return values
        }

        private mutating func readScalarUntilQuote() throws -> String {
            let raw = try readEscaped(until: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { throw BlocktopographError.malformedData("数值 NBT 标签不能为空") }
            return raw
        }

        private mutating func readListScalar(
            terminator: Character,
            preserveWhitespace: Bool = false
        ) throws -> String {
            var result = ""
            var escaped = false
            while let character = peek {
                if escaped {
                    result.append(character)
                    escaped = false
                    advance()
                    continue
                }
                if character == "\\" {
                    escaped = true
                    advance()
                    continue
                }
                if character == "," || character == terminator { break }
                result.append(character)
                advance()
            }
            if escaped { result.append("\\") }
            let value = preserveWhitespace ? result : result.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty, !preserveWhitespace {
                throw BlocktopographError.malformedData("List 中存在空元素")
            }
            return value
        }

        private mutating func readEscaped(until terminator: Character) throws -> String {
            var result = ""
            var escaped = false
            while let character = peek {
                if escaped {
                    result.append(character)
                    escaped = false
                    advance()
                    continue
                }
                if character == "\\" {
                    escaped = true
                    advance()
                    continue
                }
                if character == terminator { return result }
                result.append(character)
                advance()
            }
            throw BlocktopographError.malformedData("NBT 字符串缺少结束引号")
        }

        private mutating func readUntilAny(_ terminators: Set<Character>) throws -> String {
            var result = ""
            while let character = peek, !terminators.contains(character) {
                result.append(character)
                advance()
            }
            guard peek != nil else { throw BlocktopographError.malformedData("NBT 数组未闭合") }
            return result
        }

        private mutating func parseQuotedString(quote: Character) throws -> String {
            try expect(quote)
            let value = try readEscaped(until: quote)
            try expect(quote)
            return value
        }

        private func invalidValue(_ type: NBTTagType, _ value: String) -> BlocktopographError {
            .malformedData("\(type.displayName) 值无效：\(value)")
        }

        private var peek: Character? { isAtEnd ? nil : text[index] }

        private mutating func advance() {
            guard !isAtEnd else { return }
            index = text.index(after: index)
        }

        private mutating func expect(_ expected: Character) throws {
            guard peek == expected else {
                throw BlocktopographError.malformedData("NBT 格式错误：应为 \(expected)，当前位置为 \(remainingText.prefix(24))")
            }
            advance()
        }
    }
}
