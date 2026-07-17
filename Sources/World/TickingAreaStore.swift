import Foundation

struct BedrockTickingArea: Equatable {
    var dimension: Int32
    var isCircle: Bool
    var minimumX: Int32
    var minimumZ: Int32
    var maximumX: Int32
    var maximumZ: Int32
    var name: String
    var preload: Bool

    var normalized: BedrockTickingArea {
        var copy = self
        copy.minimumX = min(minimumX, maximumX)
        copy.maximumX = max(minimumX, maximumX)
        copy.minimumZ = min(minimumZ, maximumZ)
        copy.maximumZ = max(minimumZ, maximumZ)
        return copy
    }

    var dimensionName: String {
        BedrockDimension(rawValue: dimension)?.displayName ?? "维度 \(dimension)"
    }

    var centerChunk: ChunkPosition {
        let value = normalized
        let centerX = Int64(value.minimumX) + (Int64(value.maximumX) - Int64(value.minimumX)) / 2
        let centerZ = Int64(value.minimumZ) + (Int64(value.maximumZ) - Int64(value.minimumZ)) / 2
        return ChunkPosition(
            x: Int32(clamping: centerX),
            z: Int32(clamping: centerZ),
            dimension: value.dimension
        )
    }

    var radius: Int32 {
        let value = normalized
        let width = Int64(value.maximumX) - Int64(value.minimumX)
        let depth = Int64(value.maximumZ) - Int64(value.minimumZ)
        return Int32(clamping: max(width, depth) / 2)
    }

    var chunkCount: Int {
        let value = normalized
        if value.isCircle {
            let r = Int64(value.radius)
            guard r <= 4_096 else { return Int.max }
            var count = 0
            for dz in -r...r {
                for dx in -r...r where dx * dx + dz * dz <= r * r { count += 1 }
            }
            return count
        }
        let width = Int64(value.maximumX) - Int64(value.minimumX) + 1
        let height = Int64(value.maximumZ) - Int64(value.minimumZ) + 1
        let product = max(0, width) * max(0, height)
        return product > Int64(Int.max) ? Int.max : Int(product)
    }

    func contains(chunkX: Int32, chunkZ: Int32) -> Bool {
        let value = normalized
        guard chunkX >= value.minimumX, chunkX <= value.maximumX,
              chunkZ >= value.minimumZ, chunkZ <= value.maximumZ else { return false }
        guard value.isCircle else { return true }
        let center = value.centerChunk
        let dx = Int64(chunkX) - Int64(center.x)
        let dz = Int64(chunkZ) - Int64(center.z)
        let r = Int64(value.radius)
        return dx * dx + dz * dz <= r * r
    }

    var detailText: String {
        let value = normalized
        let shape: String
        if value.isCircle {
            let center = value.centerChunk
            shape = "圆形：中心 (\(center.x), \(center.z))，半径 \(value.radius)"
        } else {
            shape = "矩形：(\(value.minimumX), \(value.minimumZ)) 至 (\(value.maximumX), \(value.maximumZ))"
        }
        return "\(value.dimensionName) · \(shape) · \(value.chunkCount) 个区块 · \(value.preload ? "预加载" : "非预加载")"
    }
}

struct BedrockTickingAreaRecord {
    let stableID: String
    var area: BedrockTickingArea
    fileprivate var source: ConsecutiveNBTRecord
}

final class TickingAreaStore {
    static let databaseKey = Data("tickingarea".utf8)
    static let maximumAreaCount = 10
    static let maximumChunksPerArea = 100
    static let maximumCircleRadius: Int32 = 4

    private let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func records() throws -> [BedrockTickingAreaRecord] {
        guard let raw = try session.database().get(Self.databaseKey), !raw.isEmpty else { return [] }
        let roots = try ConsecutiveNBTCodec.decode(raw)
        return try roots.enumerated().map { index, source in
            let area = try Self.decodeArea(from: source.document)
            return BedrockTickingAreaRecord(
                stableID: "\(index):\(area.dimension):\(area.minimumX):\(area.minimumZ):\(area.maximumX):\(area.maximumZ):\(area.name)",
                area: area,
                source: source
            )
        }
    }

    func save(_ records: [BedrockTickingAreaRecord]) throws {
        guard records.count <= Self.maximumAreaCount else {
            throw BlocktopographError.unsupported("基岩版每个世界最多支持 \(Self.maximumAreaCount) 个常加载区域")
        }
        let updated = try records.map { record -> ConsecutiveNBTRecord in
            try Self.validate(record.area)
            var source = record.source
            source.document = Self.document(byUpdating: source.document, with: record.area.normalized)
            return source
        }
        let database = try session.database()
        if updated.isEmpty {
            try database.delete(Self.databaseKey, sync: true)
        } else {
            try database.put(try ConsecutiveNBTCodec.encode(updated), for: Self.databaseKey, sync: true)
        }
    }

    func makeRecord(area: BedrockTickingArea) throws -> BedrockTickingAreaRecord {
        try Self.validate(area)
        let document = Self.document(byUpdating: NBTDocument(rootName: "", root: .compound([])), with: area.normalized)
        let source = ConsecutiveNBTRecord(document: document, rawData: Data(), encoding: .littleEndian)
        return BedrockTickingAreaRecord(stableID: UUID().uuidString, area: area.normalized, source: source)
    }

    static func validate(_ area: BedrockTickingArea) throws {
        let value = area.normalized
        guard BedrockDimension(rawValue: value.dimension) != nil else {
            throw BlocktopographError.unsupported("不支持维度 \(value.dimension)")
        }
        if value.isCircle, value.radius > maximumCircleRadius {
            throw BlocktopographError.unsupported("圆形常加载区域半径最多为 \(maximumCircleRadius) 个区块")
        }
        guard value.chunkCount > 0, value.chunkCount <= maximumChunksPerArea else {
            throw BlocktopographError.unsupported("每个常加载区域最多包含 \(maximumChunksPerArea) 个区块")
        }
    }

    private static func decodeArea(from document: NBTDocument) throws -> BedrockTickingArea {
        guard case .compound(let tags) = document.root else {
            throw BlocktopographError.malformedData("tickingarea 根标签不是 Compound")
        }
        func value(_ name: String) -> NBTValue? { tags.first(where: { $0.name == name })?.value }
        func integer(_ name: String) -> Int32? {
            switch value(name) {
            case .byte(let number): return Int32(number)
            case .short(let number): return Int32(number)
            case .int(let number): return number
            case .long(let number): return Int32(clamping: number)
            default: return nil
            }
        }
        func boolean(_ name: String) -> Bool {
            (integer(name) ?? 0) != 0
        }
        func text(_ name: String) -> String {
            if case .string(let result) = value(name) { return result }
            return ""
        }
        guard let dimension = integer("Dimension"),
              let minX = integer("MinX"), let minZ = integer("MinZ"),
              let maxX = integer("MaxX"), let maxZ = integer("MaxZ") else {
            throw BlocktopographError.malformedData("tickingarea 缺少 Dimension/MinX/MinZ/MaxX/MaxZ")
        }
        return BedrockTickingArea(
            dimension: dimension,
            isCircle: boolean("IsCircle"),
            minimumX: minX,
            minimumZ: minZ,
            maximumX: maxX,
            maximumZ: maxZ,
            name: text("Name"),
            preload: boolean("Preload")
        ).normalized
    }

    private static func document(byUpdating document: NBTDocument, with area: BedrockTickingArea) -> NBTDocument {
        var result = document
        var tags: [NBTNamedTag]
        if case .compound(let existing) = document.root { tags = existing } else { tags = [] }

        func set(_ name: String, _ value: NBTValue) {
            if let index = tags.firstIndex(where: { $0.name == name }) {
                tags[index].value = value
            } else {
                tags.append(NBTNamedTag(name: name, value: value))
            }
        }
        set("Dimension", .int(area.dimension))
        set("IsCircle", .byte(area.isCircle ? 1 : 0))
        set("MaxX", .int(area.maximumX))
        set("MaxZ", .int(area.maximumZ))
        set("MinX", .int(area.minimumX))
        set("MinZ", .int(area.minimumZ))
        set("Name", .string(area.name))
        set("Preload", .byte(area.preload ? 1 : 0))
        result.root = .compound(tags)
        return result
    }
}
