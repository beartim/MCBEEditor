import Foundation

struct BedrockWeatherSettings {
    var rainLevel: Float
    var rainTime: Int32
    var lightningLevel: Float
    var lightningTime: Int32

    var conditionName: String {
        if lightningLevel > 0.01 { return "雷暴" }
        if rainLevel > 0.01 { return "下雨" }
        return "晴朗"
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
            throw BlocktopographError.malformedData("level.dat 根标签不是 Compound")
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
        return BedrockWeatherSettings(
            rainLevel: min(1, max(0, float("rainLevel"))),
            rainTime: max(0, integer("rainTime")),
            lightningLevel: min(1, max(0, float("lightningLevel"))),
            lightningTime: max(0, integer("lightningTime"))
        )
    }

    func save(_ settings: BedrockWeatherSettings) throws {
        var file = try session.document.readLevelDat()
        guard case .compound(var tags) = file.document.root else {
            throw BlocktopographError.malformedData("level.dat 根标签不是 Compound")
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
        file.document.root = .compound(tags)
        try session.document.writeLevelDat(file)
    }
}
