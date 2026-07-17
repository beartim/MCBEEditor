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

/// 从地图框选或区块菜单进入常加载区域管理时使用的区块范围。
struct TickingAreaSelectionContext: Equatable {
    let dimension: Int32
    let minimumX: Int32
    let minimumZ: Int32
    let maximumX: Int32
    let maximumZ: Int32

    init(dimension: Int32, minimumX: Int32, minimumZ: Int32, maximumX: Int32, maximumZ: Int32) {
        self.dimension = dimension
        self.minimumX = min(minimumX, maximumX)
        self.minimumZ = min(minimumZ, maximumZ)
        self.maximumX = max(minimumX, maximumX)
        self.maximumZ = max(minimumZ, maximumZ)
    }

    init(chunk: ChunkPosition) {
        self.init(
            dimension: chunk.dimension,
            minimumX: chunk.x,
            minimumZ: chunk.z,
            maximumX: chunk.x,
            maximumZ: chunk.z
        )
    }

    init(region: BedrockMapRegion) {
        self.init(
            dimension: region.dimension,
            minimumX: region.minimumChunkX,
            minimumZ: region.minimumChunkZ,
            maximumX: region.maximumChunkX,
            maximumZ: region.maximumChunkZ
        )
    }

    init?(chunks: [ChunkPosition]) {
        guard let first = chunks.first,
              chunks.allSatisfy({ $0.dimension == first.dimension }) else { return nil }
        self.init(
            dimension: first.dimension,
            minimumX: chunks.map(\.x).min() ?? first.x,
            minimumZ: chunks.map(\.z).min() ?? first.z,
            maximumX: chunks.map(\.x).max() ?? first.x,
            maximumZ: chunks.map(\.z).max() ?? first.z
        )
    }

    var suggestedArea: BedrockTickingArea {
        BedrockTickingArea(
            dimension: dimension,
            isCircle: false,
            minimumX: minimumX,
            minimumZ: minimumZ,
            maximumX: maximumX,
            maximumZ: maximumZ,
            name: "",
            preload: false
        )
    }

    var detailText: String {
        let dimensionText = BedrockDimension(rawValue: dimension)?.displayName ?? "维度 \(dimension)"
        return "\(dimensionText) · 区块 X \(minimumX)…\(maximumX)，Z \(minimumZ)…\(maximumZ)"
    }

    func intersects(_ area: BedrockTickingArea) -> Bool {
        let value = area.normalized
        guard value.dimension == dimension,
              value.maximumX >= minimumX, maximumX >= value.minimumX,
              value.maximumZ >= minimumZ, maximumZ >= value.minimumZ else { return false }
        guard value.isCircle else { return true }

        let center = value.centerChunk
        let closestX = min(max(Int64(center.x), Int64(minimumX)), Int64(maximumX))
        let closestZ = min(max(Int64(center.z), Int64(minimumZ)), Int64(maximumZ))
        let dx = Int64(center.x) - closestX
        let dz = Int64(center.z) - closestZ
        let radius = Int64(value.radius)
        return dx * dx + dz * dz <= radius * radius
    }
}

struct BedrockTickingAreaRecord {
    let stableID: String
    var area: BedrockTickingArea
    fileprivate var source: ConsecutiveNBTRecord
    fileprivate var databaseKey: Data?
}

final class TickingAreaStore {
    /// Minecraft stores one ordinary NBT document in each LevelDB entry whose key begins with `tickingarea_`.
    static let databaseKeyPrefix = Data("tickingarea_".utf8)
    /// v1.1.0/v1.1.1 incorrectly stored all records consecutively under this single key.
    static let legacyDatabaseKey = Data("tickingarea".utf8)
    private static let databaseScanPrefix = Data("tickingarea".utf8)

    static let maximumAreaCount = 10
    static let maximumChunksPerArea = 100
    static let maximumCircleRadius: Int32 = 4

    private let session: WorldSession

    init(session: WorldSession) {
        self.session = session
    }

    func records(migratingLegacy: Bool = false) throws -> [BedrockTickingAreaRecord] {
        let entries = try session.database().entries(
            prefix: Self.databaseScanPrefix,
            includeValues: true
        )
        var result = [BedrockTickingAreaRecord]()
        var needsMigration = false
        for entry in entries {
            guard let raw = entry.value, !raw.isEmpty else { continue }
            let roots = try ConsecutiveNBTCodec.decode(raw)
            guard !roots.isEmpty else { continue }

            let hasNativeKey = entry.key.starts(with: Self.databaseKeyPrefix)
            let isLegacyContainer = !hasNativeKey || roots.count > 1
            needsMigration = needsMigration || isLegacyContainer
            for (index, source) in roots.enumerated() {
                let area = try Self.decodeArea(from: source.document)
                let keyText = String(data: entry.key, encoding: .utf8) ?? entry.key.hexString
                result.append(BedrockTickingAreaRecord(
                    stableID: roots.count == 1 ? keyText : "\(keyText)#\(index)",
                    area: area,
                    source: source,
                    databaseKey: isLegacyContainer ? nil : entry.key
                ))
            }
        }

        if migratingLegacy, needsMigration {
            try save(result)
            return try records(migratingLegacy: false)
        }
        return result
    }

    func save(_ records: [BedrockTickingAreaRecord]) throws {
        try Self.validate(records)

        let database = try session.database()
        let existingKeys = try database.entries(
            prefix: Self.databaseScanPrefix,
            includeValues: false
        ).map(\.key)

        var usedKeys = Set<Data>()
        var puts = [(key: Data, value: Data)]()
        puts.reserveCapacity(records.count)

        for record in records {
            var source = record.source
            source.document = Self.document(byUpdating: source.document, with: record.area.normalized)

            let key: Data
            if let existingKey = record.databaseKey,
               existingKey.starts(with: Self.databaseKeyPrefix),
               !usedKeys.contains(existingKey) {
                key = existingKey
            } else {
                key = Self.makeUniqueDatabaseKey(excluding: usedKeys)
            }
            usedKeys.insert(key)

            // A tickingarea value is one normal little-endian NBT document, not a stream of roots.
            let value = try BedrockNBTCodec.encode(source.document, encoding: source.encoding)
            puts.append((key, value))
        }

        let deletes = existingKeys.filter { !usedKeys.contains($0) }
        try database.applyBatch(puts: puts, deletes: deletes, sync: true)
    }

    func makeRecord(area: BedrockTickingArea) throws -> BedrockTickingAreaRecord {
        try Self.validate(area)
        let document = Self.document(
            byUpdating: NBTDocument(rootName: "", root: .compound([])),
            with: area.normalized
        )
        let source = ConsecutiveNBTRecord(document: document, rawData: Data(), encoding: .littleEndian)
        return BedrockTickingAreaRecord(
            stableID: UUID().uuidString,
            area: area.normalized,
            source: source,
            databaseKey: nil
        )
    }

    static func validate(_ records: [BedrockTickingAreaRecord]) throws {
        guard records.count <= maximumAreaCount else {
            throw BlocktopographError.unsupported("基岩版每个世界最多支持 \(maximumAreaCount) 个常加载区域")
        }
        for record in records {
            try validate(record.area)
        }
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

    private static func makeUniqueDatabaseKey(excluding usedKeys: Set<Data>) -> Data {
        while true {
            let suffix = UUID().uuidString.lowercased()
            let key = Data("tickingarea_\(suffix)".utf8)
            if !usedKeys.contains(key) { return key }
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
