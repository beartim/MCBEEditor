import Foundation

struct DimensionRecord {
    let name: String
    let id: Int32
    let chunkCount: Int

    var queryText: String { "\(name)=\(id)，区块=\(chunkCount)" }
}

/// World-scoped discovery. Registered empty dimensions remain visible.
final class DimensionStore {
    static let registryKey = Data("DimensionNameIdTable".utf8)
    private let database: MojangLevelDB

    init(database: MojangLevelDB) { self.database = database }

    func resolve(_ token: String) throws -> Int32 {
        if let row = try snapshot().first(where: { $0.name == token }) { return row.id }
        switch token.lowercased() {
        case "overworld", "minecraft:overworld": return 0
        case "nether", "minecraft:nether": return 1
        case "the_end", "minecraft:the_end": return 2
        default: if let id = Int32(token) { return id }
        }
        throw MCBEEditorError.malformedData("维度名称或 ID 无效：\(token)")
    }

    func purge(id: Int32) throws -> DimensionMutationSummary {
        let dimensions = try snapshot()
        guard let target = dimensions.first(where: { $0.id == id }) else { throw MCBEEditorError.malformedData("维度不存在：\(id)") }
        var plan = try DimensionContentPlan.build(database: database, id: id, dimensions: dimensions)
        let references = try DimensionReferencePlan.build(database: database, target: target, dimensions: dimensions)
        plan.puts.append(contentsOf: references.puts)
        plan.deletes.insert(Self.dataKey(name: target.name))
        if id >= 0 && id <= 2 { plan.deletes.insert(Self.dataKey(name: ["overworld", "nether", "the_end"][Int(id)])) }
        if let bytes = try database.get(Self.registryKey) {
            let document = try BedrockNBTCodec.decode(bytes)
            guard case .compound(var tags) = document.root, let index = tags.firstIndex(where: { $0.name == "entries" }),
                  case .compound(let entries) = tags[index].value else { throw MCBEEditorError.malformedData("维度登记格式错误") }
            let kept = entries.filter { if case .int(let value) = $0.value { return value != id }; return true }
            if kept.count != entries.count {
                tags[index] = NBTNamedTag(name: "entries", value: .compound(kept))
                plan.puts.append((Self.registryKey, try BedrockNBTCodec.encode(NBTDocument(rootName: document.rootName, root: .compound(tags)))))
            }
        }
        plan.deletes.subtract(plan.puts.map(\.key))
        try database.applyBatch(puts: plan.puts, deletes: Array(plan.deletes), sync: true)
        return DimensionMutationSummary(deletedKeyCount: plan.deletes.count, removedActorCount: plan.actorCount, updatedKeyCount: plan.puts.count, affectedPlayerCount: references.playerCount)
    }

    func empty(id: Int32) throws -> DimensionMutationSummary {
        let dimensions = try snapshot()
        guard let target = dimensions.first(where: { $0.id == id }) else { throw MCBEEditorError.malformedData("维度不存在：\(id)") }
        var plan = try DimensionContentPlan.build(database: database, id: id, dimensions: dimensions)
        var name = target.name
        if id < 0 || id > 2 {
            var registry = NBTDocument(rootName: "", root: .compound([NBTNamedTag(name: "entries", value: .compound([]))]))
            if let bytes = try database.get(Self.registryKey) { registry = try BedrockNBTCodec.decode(bytes) }
            if registry.root.compoundValue(named: "entries")?.intValue(named: name) != id {
                name = "dimension_\(id)"
                while try dimensions.contains(where: { $0.name == name }) || database.get(Self.dataKey(name: name)) != nil { name += "_" }
                guard case .compound(var tags) = registry.root, let index = tags.firstIndex(where: { $0.name == "entries" }), case .compound(var entries) = tags[index].value else { throw MCBEEditorError.malformedData("维度登记格式错误") }
                entries.append(NBTNamedTag(name: name, value: .int(id)))
                tags[index] = NBTNamedTag(name: "entries", value: .compound(entries))
                plan.puts.append((Self.registryKey, try BedrockNBTCodec.encode(NBTDocument(rootName: registry.rootName, root: .compound(tags)))))
            }
        }
        let key = Self.dataKey(name: name)
        var document = NBTDocument(rootName: "", root: .compound([]))
        if let bytes = try database.get(key) { document = try BedrockNBTCodec.decode(bytes) }
        guard case .compound(var tags) = document.root else { throw MCBEEditorError.malformedData("维度根必须为 Compound") }
        var dataTags: [NBTNamedTag] = []
        if let value = document.root.compoundValue(named: "data") {
            guard case .compound(let existing) = value else { throw MCBEEditorError.malformedData("维度 data 必须为 Compound") }
            dataTags = existing.filter { $0.name != "LimboEntities" && !(id == 2 && $0.name == "DragonFight") }
        }
        dataTags.append(NBTNamedTag(name: "LimboEntities", value: .list(.compound, [])))
        tags.removeAll { $0.name == "data" }; tags.append(NBTNamedTag(name: "data", value: .compound(dataTags)))
        plan.puts.append((key, try BedrockNBTCodec.encode(NBTDocument(rootName: document.rootName, root: .compound(tags)))))
        plan.deletes.subtract(plan.puts.map(\.key))
        try database.applyBatch(puts: plan.puts, deletes: Array(plan.deletes), sync: true)
        return DimensionMutationSummary(deletedKeyCount: plan.deletes.count, removedActorCount: plan.actorCount, updatedKeyCount: plan.puts.count)
    }

    static func validateAddition(name: String, id: Int32) throws -> String {
        try DimensionNameRules.validateAddition(name: name, id: id)
    }

    static func dataKey(name: String) -> Data {
        switch name {
        case "overworld": return Data("Overworld".utf8)
        case "nether": return Data("Nether".utf8)
        case "the_end": return Data("TheEnd".utf8)
        default: return Data(name.utf8)
        }
    }

    func add(name: String, id: Int32) throws {
        let name = try Self.validateAddition(name: name, id: id)
        let existing = try snapshot()
        guard !existing.contains(where: { $0.name == name || $0.id == id }) else {
            throw MCBEEditorError.malformedData("维度名称或 ID 已存在：\(name)=\(id)")
        }
        let key = Self.dataKey(name: name)
        guard try database.get(key) == nil else { throw MCBEEditorError.malformedData("数据库键已存在：\(name)") }
        let root = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "data", value: .compound([
                NBTNamedTag(name: "LimboEntities", value: .list(.compound, []))
            ]))
        ]))
        var puts: [(key: Data, value: Data)] = [(key, try BedrockNBTCodec.encode(root))]
        if id < 0 || id > 2 {
            var registry = NBTDocument(rootName: "", root: .compound([NBTNamedTag(name: "entries", value: .compound([]))]))
            if let bytes = try database.get(Self.registryKey) { registry = try BedrockNBTCodec.decode(bytes) }
            guard case .compound(var tags) = registry.root,
                  tags.filter({ $0.name == "entries" }).count == 1,
                  let index = tags.firstIndex(where: { $0.name == "entries" }),
                  case .compound(var entries) = tags[index].value else {
                throw MCBEEditorError.malformedData("维度登记表必须包含唯一的 entries Compound")
            }
            entries.append(NBTNamedTag(name: name, value: .int(id)))
            tags[index] = NBTNamedTag(name: "entries", value: .compound(entries))
            registry = NBTDocument(rootName: registry.rootName, root: .compound(tags))
            puts.append((Self.registryKey, try BedrockNBTCodec.encode(registry)))
        }
        try database.applyBatch(puts: puts, deletes: [], sync: true)
    }

    func snapshot() throws -> [DimensionRecord] {
        var names: [Int32: String] = [:]
        if let bytes = try database.get(Self.registryKey) {
            let document = try BedrockNBTCodec.decode(bytes, encoding: .littleEndian)
            guard case .compound(let entries)? = document.root.compoundValue(named: "entries") else {
                throw MCBEEditorError.malformedData("DimensionNameIdTable.entries 必须为 Compound")
            }
            for entry in entries {
                guard case .int(let id) = entry.value, !entry.name.isEmpty else {
                    throw MCBEEditorError.malformedData("维度登记必须为非空名称及 Int ID")
                }
                if let existing = names[id], existing != entry.name {
                    throw MCBEEditorError.malformedData("维度 ID \(id) 有重复名称：\(existing)、\(entry.name)")
                }
                names[id] = entry.name
            }
        }
        let keys = try database.entries(includeValues: false, limit: 0).map(\.key)
        let keySet = Set(keys)
        let namedRoots = Set((Array(names.values) + ["overworld", "nether", "the_end"]).map { Self.dataKey(name: $0) })
        let roots: [(String, String, Int32)] = [("Overworld", "overworld", 0), ("Nether", "nether", 1), ("TheEnd", "the_end", 2)]
        for (key, name, id) in roots where keySet.contains(Data(key.utf8)) || keySet.contains(Data("dimension\(id)".utf8)) {
            if names[id] == nil { names[id] = name }
        }
        var positions: [Int32: Set<ChunkPosition>] = [:]
        let digestPrefix = Data("digp".utf8)
        for key in keys {
            let text = String(data: key, encoding: .utf8) ?? ""
            if namedRoots.contains(key) || DimensionDatabaseKeys.globalNames.contains(text) || DimensionDatabaseKeys.preservedPrefixes.contains(where: { text.hasPrefix($0) }) { continue }
            let position: ChunkPosition
            if key.starts(with: digestPrefix), key.count == 12 || key.count == 16 {
                position = ChunkPosition(
                    x: try key.littleEndianInt32(at: 4), z: try key.littleEndianInt32(at: 8),
                    dimension: key.count == 16 ? try key.littleEndianInt32(at: 12) : 0)
            } else {
                if ["digp", "actorprefix", "tickingarea", "VILLAGE_", "portals"].contains(where: { text.hasPrefix($0) }) { continue }
                guard let rawPosition = BedrockRawChunkKey.position(from: key) else { continue }
                position = rawPosition
            }
            positions[position.dimension, default: []].insert(position)
            if names[position.dimension] == nil {
                names[position.dimension] = roots.first { $0.2 == position.dimension }?.1 ?? String(position.dimension)
            }
        }
        guard Set(names.values).count == names.count else {
            throw MCBEEditorError.malformedData("维度名称重复，无法唯一定位维度")
        }
        return names.map { DimensionRecord(name: $0.value, id: $0.key, chunkCount: positions[$0.key]?.count ?? 0) }
            .sorted { $0.id < $1.id }
    }
}
