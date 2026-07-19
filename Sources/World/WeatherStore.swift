import Foundation

struct BedrockWeatherSettings {
    var rainLevel: Float
    var rainTime: Int32
    var lightningLevel: Float
    var lightningTime: Int32
    var automaticChange: Bool

    var conditionName: String {
        if lightningLevel > 0.01 { return "雷暴" }
        if rainLevel > 0.01 { return "下雨" }
        return "晴朗"
    }

    static func clear(automaticChange: Bool, duration: Int32 = 12_000) -> BedrockWeatherSettings {
        BedrockWeatherSettings(
            rainLevel: 0,
            rainTime: max(0, duration),
            lightningLevel: 0,
            lightningTime: max(0, duration),
            automaticChange: automaticChange
        )
    }

    static func rain(duration: Int32, intensity: Float, automaticChange: Bool) -> BedrockWeatherSettings {
        let level = min(1, max(0, intensity))
        return BedrockWeatherSettings(
            rainLevel: level,
            rainTime: max(0, duration),
            lightningLevel: 0,
            lightningTime: max(0, duration),
            automaticChange: automaticChange
        )
    }

    static func thunder(duration: Int32, intensity: Float, automaticChange: Bool) -> BedrockWeatherSettings {
        let level = min(1, max(0, intensity))
        return BedrockWeatherSettings(
            rainLevel: level,
            rainTime: max(0, duration),
            lightningLevel: level,
            lightningTime: max(0, duration),
            automaticChange: automaticChange
        )
    }
}

final class WeatherStore {
    private let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func read() throws -> BedrockWeatherSettings {
        let file = try session.document.readLevelDat()
        guard case .compound(let tags) = file.document.root else {
            throw MCBEEditorError.malformedData("level.dat 根标签不是 Compound")
        }
        func value(_ name: String) -> NBTValue? { tags.first(where: { $0.name == name })?.value }
        func float(_ name: String) -> Float {
            switch value(name) {
            case .float(let number): return number
            case .double(let number): return Float(number)
            case .int(let number): return Float(number)
            default: return 0
            }
        }
        func integer(_ name: String) -> Int32 {
            switch value(name) {
            case .byte(let number): return Int32(number)
            case .short(let number): return Int32(number)
            case .int(let number): return number
            case .long(let number): return Int32(clamping: number)
            default: return 0
            }
        }
        func boolean(_ name: String, default defaultValue: Bool) -> Bool {
            guard value(name) != nil else { return defaultValue }
            return integer(name) != 0
        }
        return BedrockWeatherSettings(
            rainLevel: min(1, max(0, float("rainLevel"))),
            rainTime: max(0, integer("rainTime")),
            lightningLevel: min(1, max(0, float("lightningLevel"))),
            lightningTime: max(0, integer("lightningTime")),
            automaticChange: boolean("doWeatherCycle", default: true)
        )
    }

    func save(_ settings: BedrockWeatherSettings) throws {
        var file = try session.document.readLevelDat()
        guard case .compound(var tags) = file.document.root else {
            throw MCBEEditorError.malformedData("level.dat 根标签不是 Compound")
        }
        func set(_ name: String, _ value: NBTValue) {
            if let index = tags.firstIndex(where: { $0.name == name }) {
                tags[index].value = value
            } else {
                tags.append(NBTNamedTag(name: name, value: value))
            }
        }
        set("rainLevel", .float(min(1, max(0, settings.rainLevel))))
        set("rainTime", .int(max(0, settings.rainTime)))
        set("lightningLevel", .float(min(1, max(0, settings.lightningLevel))))
        set("lightningTime", .int(max(0, settings.lightningTime)))
        set("doWeatherCycle", .byte(settings.automaticChange ? 1 : 0))
        file.document.root = .compound(tags)
        try session.document.writeLevelDat(file)
    }
}
