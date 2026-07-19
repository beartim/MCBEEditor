import Foundation

struct BedrockTimeSettings {
    var time: Int64
    var automaticProgression: Bool

    var daytime: Int64 { BedrockTimeStore.positiveRemainder(time, divisor: 24_000) }
    var day: Int64 { BedrockTimeStore.floorDivision(time, by: 24_000) }
    var summary: String { BedrockTimeStore.daytimeSummary(time) }
}

enum BedrockTimeStore {
    static func read(session: WorldSession) throws -> BedrockTimeSettings {
        let file = try session.document.readLevelDat()
        guard case .compound(let tags) = file.document.root else {
            throw MCBEEditorError.malformedData("level.dat 根标签不是 Compound")
        }
        return BedrockTimeSettings(
            time: try integer(named: "Time", in: tags, default: 0),
            automaticProgression: try boolean(named: "dodaylightcycle", in: tags, default: true)
        )
    }

    static func save(_ settings: BedrockTimeSettings, session: WorldSession) throws {
        var file = try session.document.readLevelDat()
        guard case .compound(var tags) = file.document.root else {
            throw MCBEEditorError.malformedData("level.dat 根标签不是 Compound")
        }
        set(name: "Time", value: .long(settings.time), in: &tags)
        set(name: "dodaylightcycle", value: .byte(settings.automaticProgression ? 1 : 0), in: &tags)
        file.document.root = .compound(tags)
        try session.document.writeLevelDat(file)
    }

    static func saveTime(_ time: Int64, session: WorldSession) throws {
        var settings = try read(session: session)
        settings.time = time
        try save(settings, session: session)
    }

    static func startTick(named period: String) -> Int64? {
        switch period {
        case "day": return 0
        case "noon": return 6_000
        case "sunset": return 12_001
        case "night": return 13_801
        case "midnight": return 18_000
        case "sunrise": return 22_201
        default: return nil
        }
    }

    static func alignedTime(_ current: Int64, startTick: Int64, roundingUp: Bool) throws -> Int64 {
        let dayIndex = roundingUp
            ? ceilingDivision(current, by: 24_000)
            : floorDivision(current, by: 24_000)
        let (dayBase, multiplyOverflow) = dayIndex.multipliedReportingOverflow(by: 24_000)
        guard !multiplyOverflow else {
            throw MCBEEditorError.malformedData("time 对齐结果超出 Int64 范围")
        }
        let (result, addOverflow) = dayBase.addingReportingOverflow(startTick)
        guard !addOverflow else {
            throw MCBEEditorError.malformedData("time 对齐结果超出 Int64 范围")
        }
        return result
    }

    static func daytimeSummary(_ time: Int64) -> String {
        let daytime = positiveRemainder(time, divisor: 24_000)
        let segment = daytimeSegment(for: daytime)
        let segmentPercent = roundedPercent(
            numerator: daytime - segment.start,
            denominator: segment.end - segment.start
        )
        let wholePercent = roundedPercent(numerator: daytime, denominator: 24_000)
        return "daytime=\(daytime)，\(segment.name)\(segmentPercent)%，全天\(wholePercent)%"
    }

    static func daytimeSegment(for daytime: Int64) -> (name: String, start: Int64, end: Int64) {
        switch daytime {
        case 0...12_000: return ("白天", 0, 12_000)
        case 12_001...13_800: return ("日落", 12_001, 13_800)
        case 13_801...22_200: return ("夜晚", 13_801, 22_200)
        default: return ("日出", 22_201, 23_999)
        }
    }

    static func floorDivision(_ value: Int64, by divisor: Int64) -> Int64 {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }

    static func ceilingDivision(_ value: Int64, by divisor: Int64) -> Int64 {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder > 0 ? quotient + 1 : quotient
    }

    static func positiveRemainder(_ value: Int64, divisor: Int64) -> Int64 {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }

    static func roundedPercent(numerator: Int64, denominator: Int64) -> Int {
        guard denominator > 0 else { return 100 }
        let value = (Double(numerator) * 100.0 / Double(denominator)).rounded()
        return min(100, max(0, Int(value)))
    }

    private static func integer(named name: String, in tags: [NBTNamedTag], default defaultValue: Int64) throws -> Int64 {
        guard let value = tags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value else {
            return defaultValue
        }
        switch value {
        case .byte(let number): return Int64(number)
        case .short(let number): return Int64(number)
        case .int(let number): return Int64(number)
        case .long(let number): return number
        default: throw MCBEEditorError.malformedData("level.dat 的 \(name) 标签必须是整数类型")
        }
    }

    private static func boolean(named name: String, in tags: [NBTNamedTag], default defaultValue: Bool) throws -> Bool {
        guard tags.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return defaultValue }
        return try integer(named: name, in: tags, default: defaultValue ? 1 : 0) != 0
    }

    private static func set(name: String, value: NBTValue, in tags: inout [NBTNamedTag]) {
        let matches = tags.indices.filter { tags[$0].name.caseInsensitiveCompare(name) == .orderedSame }
        if let first = matches.first {
            tags[first] = NBTNamedTag(name: name, value: value)
            for index in matches.dropFirst().reversed() { tags.remove(at: index) }
        } else {
            tags.append(NBTNamedTag(name: name, value: value))
        }
    }
}
