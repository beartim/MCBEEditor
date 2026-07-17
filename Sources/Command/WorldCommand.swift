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
        if let version = version { tags.append(NBTNamedTag(name: "version", value: .int(version))) }
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

enum ParsedWorldCommand {
    case help(command: String?)
    case clear(uniqueID: Int64?)
    case clearSpawnPoint(uniqueID: Int64?)
    case clone(source: CommandBlockBox, destination: CommandBlockCoordinate)
    case fill(region: CommandBlockBox, layer0: CommandBlockStateSpec, layer1: CommandBlockStateSpec)
}

enum WorldCommandParser {
    static let commandNames = ["help", "clear", "clearspawnpoint", "clone", "fill"]

    static let usage: [String: String] = [
        "help": "help [命令]\n无参数：显示全部命令；指定已存在的命令：显示该命令的使用方法。",
        "clear": "clear [玩家UniqueID]\n无参数：清除本地玩家的物品；指定本地或在线玩家 UniqueID：清除该玩家物品。",
        "clearspawnpoint": "clearspawnpoint [玩家UniqueID]\n无参数：清除本地玩家出生点；指定本地或在线玩家 UniqueID：清除该玩家出生点。",
        "clone": "clone x1 y1 z1 x2 y2 z2 x3 y3 z3\n复制源区域两角 (x1,y1,z1) 与 (x2,y2,z2) 到目标起点 (x3,y3,z3)。未加载区块会整块跳过；重叠区域按坐标顺序直接覆盖。",
        "fill": "fill x1 y1 z1 x2 y2 z2 层0方块名 层0states 层1方块名 层1states\nstates 必须为 NULL，或严格使用 '类型'\"键\"=\"值\" 并以英文逗号分隔。支持 Byte、Short、Int、Long、Float、Double、String。"
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
            guard arguments.count <= 1 else { throw usageError(command) }
            return .clear(uniqueID: try arguments.first.map(parseUniqueID))
        case "clearspawnpoint":
            guard arguments.count <= 1 else { throw usageError(command) }
            return .clearSpawnPoint(uniqueID: try arguments.first.map(parseUniqueID))
        case "clone":
            guard arguments.count == 9 else { throw usageError(command) }
            let coordinates = try parseCoordinates(arguments)
            return .clone(source: CommandBlockBox(coordinates[0], coordinates[1]), destination: coordinates[2])
        case "fill":
            guard arguments.count == 10 else { throw usageError(command) }
            let coordinates = try parseCoordinates(Array(arguments.prefix(6)))
            let layer0 = try CommandBlockStateSpec(
                name: parseBlockName(arguments[6]),
                states: parseStates(arguments[7])
            )
            let layer1 = try CommandBlockStateSpec(
                name: parseBlockName(arguments[8]),
                states: parseStates(arguments[9])
            )
            return .fill(region: CommandBlockBox(coordinates[0], coordinates[1]), layer0: layer0, layer1: layer1)
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

    private static func parseUniqueID(_ text: String) throws -> Int64 {
        guard let value = Int64(text), value != 0 else {
            throw BlocktopographError.malformedData("玩家 UniqueID 必须是非零 Int64 整数")
        }
        return value
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
