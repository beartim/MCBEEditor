import Foundation

enum HardcodedSpawnerKind: Equatable {
    case netherFortress
    case swampHut
    case oceanMonument
    case pillagerOutpost
    case custom(UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 1: self = .netherFortress
        case 2: self = .swampHut
        case 3: self = .oceanMonument
        case 5: self = .pillagerOutpost
        default: self = .custom(rawValue)
        }
    }

    var rawValue: UInt8 {
        switch self {
        case .netherFortress: return 1
        case .swampHut: return 2
        case .oceanMonument: return 3
        case .pillagerOutpost: return 5
        case .custom(let value): return value
        }
    }

    var displayName: String {
        switch self {
        case .netherFortress: return "下界要塞"
        case .swampHut: return "沼泽小屋"
        case .oceanMonument: return "海底神殿"
        case .pillagerOutpost: return "掠夺者前哨站"
        case .custom(let value): return "未知类型 \(value)"
        }
    }
}

struct HardcodedSpawnerArea: Equatable {
    var minimumX: Int32
    var minimumY: Int32
    var minimumZ: Int32
    var maximumX: Int32
    var maximumY: Int32
    var maximumZ: Int32
    var kind: HardcodedSpawnerKind

    var rangeText: String {
        "(\(minimumX), \(minimumY), \(minimumZ)) → (\(maximumX), \(maximumY), \(maximumZ))"
    }

    func validated() throws -> HardcodedSpawnerArea {
        guard minimumX <= maximumX, minimumY <= maximumY, minimumZ <= maximumZ else {
            throw MCBEEditorError.malformedData("最小坐标必须小于或等于最大坐标")
        }
        return self
    }
}

struct HardcodedSpawnersDocument: Equatable {
    var areas: [HardcodedSpawnerArea]

    static func decode(_ data: Data) throws -> HardcodedSpawnersDocument {
        var cursor = BinaryCursor(data: data)
        let count = Int(try cursor.readInt32LE())
        guard count >= 0, count <= 1_000_000 else {
            throw MCBEEditorError.malformedData("HardcodedSpawners 数量无效：\(count)")
        }
        guard cursor.remaining == count * 25 else {
            throw MCBEEditorError.malformedData(
                "HardcodedSpawners 长度不匹配：声明 \(count) 项，剩余 \(cursor.remaining) 字节"
            )
        }
        var areas = [HardcodedSpawnerArea]()
        areas.reserveCapacity(count)
        for _ in 0..<count {
            let area = HardcodedSpawnerArea(
                minimumX: try cursor.readInt32LE(),
                minimumY: try cursor.readInt32LE(),
                minimumZ: try cursor.readInt32LE(),
                maximumX: try cursor.readInt32LE(),
                maximumY: try cursor.readInt32LE(),
                maximumZ: try cursor.readInt32LE(),
                kind: HardcodedSpawnerKind(rawValue: try cursor.readByte())
            )
            areas.append(try area.validated())
        }
        return HardcodedSpawnersDocument(areas: areas)
    }

    func encoded() throws -> Data {
        guard areas.count <= Int(Int32.max) else {
            throw MCBEEditorError.malformedData("HardcodedSpawners 项目过多")
        }
        var writer = BinaryWriter()
        writer.writeInt32LE(Int32(areas.count))
        for original in areas {
            let area = try original.validated()
            writer.writeInt32LE(area.minimumX)
            writer.writeInt32LE(area.minimumY)
            writer.writeInt32LE(area.minimumZ)
            writer.writeInt32LE(area.maximumX)
            writer.writeInt32LE(area.maximumY)
            writer.writeInt32LE(area.maximumZ)
            writer.writeByte(area.kind.rawValue)
        }
        return writer.data
    }
}
