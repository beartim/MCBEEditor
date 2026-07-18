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

enum ParsedWorldCommand {
    case help(command: String?)
    case clear(target: CommandTarget)
    case clearSpawnPoint(target: CommandTarget)
    case give(target: CommandTarget, itemIdentifier: String, count: Int64)
    case kill(target: CommandTarget, killCreativePlayers: Bool)
    case kick(target: CommandTarget)
    case summon(identifier: String, dimension: Int32, position: CommandBlockCoordinate, additions: [NBTNamedTag])
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
}

enum WorldCommandParser {
    static let commandNames = ["help", "clear", "clearspawnpoint", "clone", "fill", "give", "kill", "kick", "summon"]

    static let usage: [String: String] = [
        "help": "help [命令]\n无参数：显示全部命令；指定已存在的命令：显示该命令的使用方法。",
        "clear": "clear 目标\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。清除所有匹配玩家与实体的物品；村民交易数据不会清除。",
        "clearspawnpoint": "clearspawnpoint 目标\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。只对匹配的玩家清除出生点。",
        "clone": "clone 源维度 x1 y1 z1 x2 y2 z2 目标维度 x3 y3 z3\n维度必须为 overworld、nether 或 the_end。复制源区域两角到目标维度的目标起点；涉及未加载区块时会先写入空气区块与生成完成状态，再执行复制。重叠区域使用命令开始时的原始源数据。\n示例：clone overworld 0 0 0 5 100 46 nether 9 50 9",
        "fill": "fill 目标维度 x1 y1 z1 x2 y2 z2 层0方块名 层0states 层1方块名 层1states\n维度必须为 overworld、nether 或 the_end。states 必须为 NULL，或严格使用 '类型'\"键\"=\"值\" 并以英文逗号分隔。支持 Byte、Short、Int、Long、Float、Double、String；涉及未加载区块时先写入空气区块与生成完成状态。\n示例：fill the_end 0 0 0 60 200 16 minecraft:leaves 'String'\"old_leaf_type\"=\"oak\",'Byte'\"persistent_bit\"=\"0\",'Byte'\"update_bit\"=\"0\" minecraft:chest 'Int'\"facing_direction\"=\"3\"",
        "give": "give 目标 物品 数目\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；物品必须使用完整字符串 ID；数目必须是大于 0 的 Int64。玩家写入物品栏第一个空槽位，物品栏已满时替换最后一格，其他实体替换 Mainhand；没有 Mainhand 标签的实体会跳过。\n示例：give minecraft:cow minecraft:redstone_wire 97",
        "kill": "kill 目标 是否杀死创造模式玩家\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；第二个参数只能是 0 或 1。非玩家实体直接删除，玩家生命值 Current 设为 0.0；创造模式玩家在参数为 0 时保持不变。\n示例：kill @a 1",
        "kick": "kick 目标\n目标只能是在线玩家的非零 UniqueID或 @a。UniqueID 删除对应在线玩家数据，@a 删除全部在线玩家数据。",
        "summon": "summon 实体类型 实体维度 x y z NBT标签或default\n实体维度必须为 overworld、nether 或 the_end；最后一个参数输入 default 时不修改实体通用 NBT，否则必须严格使用 '类型'\"键\"=\"值\" 格式且不能为 NULL。\n示例：summon minecraft:pig overworld 0 64 0 default\n示例：summon minecraft:pig overworld 0 64 0 'Byte'\"Invulnerable\"=\"1\",'String'\"CustomName\"=\"MyPig\""
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
        case "give":
            guard arguments.count == 3 else { throw usageError(command) }
            return .give(
                target: try parseTarget(arguments[0]),
                itemIdentifier: try parseNamespacedIdentifier(arguments[1], kind: "物品"),
                count: try parseItemCount(arguments[2])
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
        guard !text.isEmpty else { throw BlocktopographError.malformedData("states 不能为空；空 states 请填写 NULL") }
        let components = try splitStateComponents(text)
        guard !components.isEmpty else { throw BlocktopographError.malformedData("states 格式无效") }
        var names = Set<String>()
        return try components.map { component in
            let expression = try parseStateComponent(component)
            guard names.insert(expression.name).inserted else {
                throw BlocktopographError.malformedData("states 中存在重复键：\(expression.name)")
            }
            return expression
        }
    }

    private static func parseStateComponent(_ text: String) throws -> NBTNamedTag {
        let pattern = "^'(Byte|Short|Int|Long|Float|Double|String)'\"((?:[^\"\\\\]|\\\\.)+)\"=\"((?:[^\"\\\\]|\\\\.)*)\"$"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.range == range,
              let typeRange = Range(match.range(at: 1), in: text),
              let nameRange = Range(match.range(at: 2), in: text),
              let valueRange = Range(match.range(at: 3), in: text) else {
            throw BlocktopographError.malformedData("states 项格式无效：\(text)")
        }
        let type = String(text[typeRange])
        let name = unescape(String(text[nameRange]))
        let rawValue = unescape(String(text[valueRange]))
        guard !name.isEmpty else { throw BlocktopographError.malformedData("states 键不能为空") }
        let value: NBTValue
        switch type {
        case "Byte":
            guard let number = Int8(rawValue) else { throw invalidStateValue(type, rawValue) }
            value = .byte(number)
        case "Short":
            guard let number = Int16(rawValue) else { throw invalidStateValue(type, rawValue) }
            value = .short(number)
        case "Int":
            guard let number = Int32(rawValue) else { throw invalidStateValue(type, rawValue) }
            value = .int(number)
        case "Long":
            guard let number = Int64(rawValue) else { throw invalidStateValue(type, rawValue) }
            value = .long(number)
        case "Float":
            guard let number = Float(rawValue), number.isFinite else { throw invalidStateValue(type, rawValue) }
            value = .float(number)
        case "Double":
            guard let number = Double(rawValue), number.isFinite else { throw invalidStateValue(type, rawValue) }
            value = .double(number)
        case "String": value = .string(rawValue)
        default: throw BlocktopographError.malformedData("不支持的 states 类型：\(type)")
        }
        return NBTNamedTag(name: name, value: value)
    }

    private static func invalidStateValue(_ type: String, _ value: String) -> BlocktopographError {
        .malformedData("states 的 \(type) 值无效：\(value)")
    }

    private static func splitStateComponents(_ text: String) throws -> [String] {
        var result = [String]()
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\", inDouble {
                current.append(character)
                escaped = true
                continue
            }
            if character == "'", !inDouble { inSingle.toggle(); current.append(character); continue }
            if character == "\"", !inSingle { inDouble.toggle(); current.append(character); continue }
            if character == ",", !inSingle, !inDouble {
                guard !current.isEmpty else { throw BlocktopographError.malformedData("states 中存在空项") }
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        guard !inSingle, !inDouble, !escaped else { throw BlocktopographError.malformedData("states 引号未闭合") }
        guard !current.isEmpty else { throw BlocktopographError.malformedData("states 末尾不能有逗号") }
        result.append(current)
        return result
    }

    private static func tokenize(_ text: String) throws -> [String] {
        var tokens = [String]()
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\", inDouble {
                current.append(character)
                escaped = true
                continue
            }
            if character == "'", !inDouble { inSingle.toggle(); current.append(character); continue }
            if character == "\"", !inSingle { inDouble.toggle(); current.append(character); continue }
            if character.isWhitespace, !inSingle, !inDouble {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        guard !inSingle, !inDouble, !escaped else { throw BlocktopographError.malformedData("命令中的引号未闭合") }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if escaped { result.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        if escaped { result.append("\\") }
        return result
    }
}
