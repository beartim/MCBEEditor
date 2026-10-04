import Foundation

struct DimensionMutationSummary {
    let deletedKeyCount: Int
    let removedActorCount: Int
    let updatedKeyCount: Int
    let affectedPlayerCount: Int
    init(deletedKeyCount: Int, removedActorCount: Int, updatedKeyCount: Int, affectedPlayerCount: Int = 0) {
        self.deletedKeyCount = deletedKeyCount; self.removedActorCount = removedActorCount
        self.updatedKeyCount = updatedKeyCount; self.affectedPlayerCount = affectedPlayerCount
    }
}

struct DimensionContentPlan {
    var puts: [(key: Data, value: Data)] = []
    var deletes: Set<Data> = []
    var actorCount = 0

    static func build(database: MojangLevelDB, id: Int32, dimensions: [DimensionRecord]) throws -> DimensionContentPlan {
        var plan = DimensionContentPlan()
        let keys = try database.entries(includeValues: false, limit: 0).map(\.key)
        let roots = dimensions.map { row -> String in
            switch row.name { case "overworld": return "Overworld"; case "nether": return "Nether"; case "the_end": return "TheEnd"; default: return row.name }
        }
        let protected = Set(roots).union(DimensionDatabaseKeys.globalNames)
        let digestPrefix = Data("digp".utf8), actorPrefix = Data("actorprefix".utf8)
        var targetRefs: Set<Data> = [], otherRefs: Set<Data> = []
        var villages: [String: [Data]] = [:]
        for key in keys {
            let text = String(data: key, encoding: .utf8) ?? ""
            if protected.contains(text) || DimensionDatabaseKeys.preservedPrefixes.contains(where: { text.hasPrefix($0) }) || text.hasPrefix("portals") { continue }
            if key.starts(with: digestPrefix), key.count == 12 || key.count == 16 {
                let dimension: Int32 = key.count == 16 ? try key.littleEndianInt32(at: 12) : 0
                let value = try database.get(key) ?? Data()
                guard value.count % 8 == 0 else { throw MCBEEditorError.malformedData("digp actor 引用长度不是8的倍数") }
                for offset in stride(from: 0, to: value.count, by: 8) {
                    let reference = value.subdata(in: offset..<(offset + 8))
                    if dimension == id { targetRefs.insert(reference) } else { otherRefs.insert(reference) }
                }
                if dimension == id { plan.deletes.insert(key) }
                continue
            }
            if key.starts(with: actorPrefix) { continue }
            if text.hasPrefix("tickingarea") {
                let records = try ConsecutiveNBTCodec.decode(database.get(key) ?? Data())
                guard records.count == 1, let record = records.first,
                      let dimension = try owner(record.document.root, dimensions: dimensions) else {
                    throw MCBEEditorError.malformedData("常加载区块缺少唯一NBT根或维度")
                }
                if dimension == id { plan.deletes.insert(key) }
                continue
            }
            if text.hasPrefix("VILLAGE_") {
                var group = text
                for suffix in ["_INFO", "_POI", "_DWELLERS", "_PLAYERS", "_RAID"] where group.hasSuffix(suffix) {
                    group = String(group.dropLast(suffix.count)); break
                }
                villages[group, default: []].append(key); continue
            }
            if text.hasPrefix("structuretemplate_") { continue }
            if (9...11).contains(key.count) {
                if id == 0 { plan.deletes.insert(key) }
            } else if (13...15).contains(key.count), try key.littleEndianInt32(at: 8) == id {
                plan.deletes.insert(key)
            }
        }
        for reference in targetRefs.subtracting(otherRefs) {
            let key = actorPrefix + reference
            if try database.get(key) != nil { plan.deletes.insert(key); plan.actorCount += 1 }
        }
        for key in keys where key.count == 19 && key.starts(with: actorPrefix) {
            let reference = Data(key.suffix(8))
            if targetRefs.contains(reference) || otherRefs.contains(reference) { continue }
            let records = try ConsecutiveNBTCodec.decode(database.get(key) ?? Data())
            let kept = try records.filter { try owner($0.document.root, dimensions: dimensions) != id }
            if kept.count == records.count { continue }
            if kept.isEmpty { plan.deletes.insert(key); plan.actorCount += 1 }
            else { plan.puts.append((key, kept.reduce(into: Data()) { $0.append($1.rawData) })) }
        }
        for (name, group) in villages {
            var owners: Set<Int32> = []
            if let dimension = try villageKeyOwner(name, dimensions: dimensions) { owners.insert(dimension) }
            for key in group {
                for record in try ConsecutiveNBTCodec.decode(database.get(key) ?? Data()) {
                    if let dimension = try owner(record.document.root, dimensions: dimensions) { owners.insert(dimension) }
                }
            }
            guard owners.count <= 1 else { throw MCBEEditorError.malformedData("村庄记录包含冲突维度，未清理任何数据") }
            if (owners.first ?? 0) == id { plan.deletes.formUnion(group) }
        }
        if (0...2).contains(id), let bytes = try database.get(Data("dimension\(id)".utf8)) {
            let records = try ConsecutiveNBTCodec.decode(bytes)
            guard records.count == 1, case .compound = records[0].document.root else { throw MCBEEditorError.malformedData("旧版维度结构根必须为唯一 Compound") }
            plan.deletes.insert(Data("dimension\(id)".utf8))
        }
        for key in keys where (String(data: key, encoding: .utf8) ?? "").hasPrefix("portals") {
            guard let bytes = try database.get(key) else { continue }
            let records = try ConsecutiveNBTCodec.decode(bytes)
            guard records.count == 1 else { throw MCBEEditorError.malformedData("门户记录必须包含唯一NBT根") }
            var changed = false
            let root = try filterPortals(records[0].document.root, id: id, changed: &changed)
            if changed { plan.puts.append((key, try BedrockNBTCodec.encode(NBTDocument(rootName: records[0].document.rootName, root: root), encoding: records[0].encoding))) }
        }
        for name in ["mVillages", "villages", "AutonomousEntities"] {
            let key = Data(name.utf8)
            guard let bytes = try database.get(key) else { continue }
            let records = try ConsecutiveNBTCodec.decode(bytes)
            var changed = false, output = Data()
            for record in records {
                var recognized = false, rootChanged = false
                let root = try filterLists(record.document.root, hint: name, id: id, dimensions: dimensions, changed: &rootChanged, recognized: &recognized)
                if ["mVillages", "villages"].contains(name), !recognized, hasPayload(root), (try owner(root, dimensions: dimensions) ?? 0) == id {
                    changed = true
                    continue
                }
                if name == "AutonomousEntities", !recognized, hasPayload(root) {
                    throw MCBEEditorError.malformedData("AutonomousEntities 内容格式无法识别，未清理任何数据")
                }
                changed = changed || rootChanged
                if rootChanged { output.append(try BedrockNBTCodec.encode(NBTDocument(rootName: record.document.rootName, root: root), encoding: record.encoding)) }
                else { output.append(record.rawData) }
            }
            if changed {
                if output.isEmpty { output = try BedrockNBTCodec.encode(NBTDocument(rootName: records.first?.document.rootName ?? "", root: .compound([])), encoding: records.first?.encoding ?? .littleEndian) }
                plan.puts.append((key, output))
            }
        }
        return plan
    }

    private static func villageKeyOwner(_ key: String, dimensions: [DimensionRecord]) throws -> Int32? {
        let body = String(key.dropFirst("VILLAGE_".count))
        let candidates = (dimensions.map { (name: $0.name, id: $0.id) } +
                          [(name: "overworld", id: Int32(0)), (name: "nether", id: Int32(1)), (name: "the_end", id: Int32(2))])
            .filter { row in
                body.hasPrefix(row.name + "_") || ((0...2).contains(row.id) && body.lowercased().hasPrefix(row.name.lowercased() + "_"))
            }
        if let length = candidates.map({ $0.name.count }).max() {
            let owners = Set(candidates.filter { $0.name.count == length }.map(\.id))
            guard owners.count == 1 else { throw MCBEEditorError.malformedData("村庄键维度名称有歧义：\(key)") }
            return owners.first
        }
        if body.contains("_") { throw MCBEEditorError.malformedData("村庄键维度名称无法解析：\(key)") }
        return nil
    }

    private static func filterPortals(_ value: NBTValue, id: Int32, changed: inout Bool) throws -> NBTValue {
        guard case .compound(var tags) = value else { throw MCBEEditorError.malformedData("门户根必须为Compound") }
        guard let dataIndex = tags.firstIndex(where: { $0.name == "data" }) else {
            guard !hasPayload(value) else { throw MCBEEditorError.malformedData("门户缺少data，未清理任何数据") }
            return value
        }
        guard tags.filter({ $0.name == "data" }).count == 1, case .compound(var data) = tags[dataIndex].value else { throw MCBEEditorError.malformedData("门户data格式错误") }
        guard let index = data.firstIndex(where: { $0.name == "PortalRecords" }) else {
            guard !hasPayload(tags[dataIndex].value) else { throw MCBEEditorError.malformedData("门户缺少PortalRecords") }
            return value
        }
        guard data.filter({ $0.name == "PortalRecords" }).count == 1, case .list(let type, let records) = data[index].value,
              type == .compound || records.isEmpty else { throw MCBEEditorError.malformedData("PortalRecords必须为Compound列表") }
        var kept: [NBTValue] = []
        for record in records {
            guard case .compound(let fields) = record, fields.filter({ $0.name == "DimId" }).count == 1,
                  case .int(let dimension)? = record.compoundValue(named: "DimId") else { throw MCBEEditorError.malformedData("门户DimId必须为唯一Int") }
            if dimension != id { kept.append(record) }
        }
        guard kept.count != records.count else { return value }
        changed = true
        data[index] = NBTNamedTag(name: "PortalRecords", value: .list(type, kept))
        tags[dataIndex] = NBTNamedTag(name: "data", value: .compound(data))
        return .compound(tags)
    }

    private static func hasPayload(_ value: NBTValue) -> Bool {
        switch value {
        case .compound(let tags): return tags.contains { hasPayload($0.value) }
        case .list(_, let values): return !values.isEmpty
        default: return true
        }
    }

    private static func normalized(_ name: String) -> String { String(name.lowercased().filter { $0.isLetter || $0.isNumber }) }

    private static func owner(_ value: NBTValue, dimensions: [DimensionRecord]) throws -> Int32? {
        switch value {
        case .compound(let tags):
            var directOwners: Set<Int32> = []
            for tag in tags where ["dimension", "dimensionid", "dimensionindex", "dim"].contains(normalized(tag.name)) {
                directOwners.insert(try directOwner(tag.value, dimensions: dimensions))
            }
            guard directOwners.count <= 1 else { throw MCBEEditorError.malformedData("内容记录包含冲突维度") }
            if let id = directOwners.first { return id }
            var found: Set<Int32> = []
            for tag in tags { if let id = try owner(tag.value, dimensions: dimensions) { found.insert(id) } }
            guard found.count <= 1 else { throw MCBEEditorError.malformedData("内容记录包含冲突维度") }
            return found.first
        case .list(_, let values):
            var found: Set<Int32> = []
            for child in values { if let id = try owner(child, dimensions: dimensions) { found.insert(id) } }
            guard found.count <= 1 else { throw MCBEEditorError.malformedData("内容记录包含冲突维度") }
            return found.first
        default: break
        }
        return nil
    }

    private static func directOwner(_ value: NBTValue, dimensions: [DimensionRecord]) throws -> Int32 {
        switch value {
        case .byte(let number): return Int32(number)
        case .short(let number): return Int32(number)
        case .int(let number): return number
        case .long(let number): if let id = Int32(exactly: number) { return id }
        case .string(let name):
            if let id = Int32(name) { return id }
            if let record = dimensions.first(where: { $0.name == name }) { return record.id }
            switch name.lowercased() { case "overworld", "minecraft:overworld": return 0; case "nether", "minecraft:nether": return 1; case "the_end", "end", "minecraft:the_end": return 2; default: break }
        default: break
        }
        throw MCBEEditorError.malformedData("内容记录的维度无法解析")
    }

    private static func filterLists(_ value: NBTValue, hint: String, id: Int32, dimensions: [DimensionRecord], changed: inout Bool, recognized: inout Bool) throws -> NBTValue {
        switch value {
        case .list(let type, let values) where ["mvillages", "villages", "villagecollection", "villagelist", "autonomousentitylist"].contains(normalized(hint)):
            recognized = true
            let kept = try values.filter { (try owner($0, dimensions: dimensions) ?? 0) != id }
            if kept.count != values.count { changed = true }
            return .list(type, kept)
        case .compound(let tags):
            if ["mvillages", "villages", "villagecollection", "villagelist", "autonomousentitylist"].contains(normalized(hint)), !tags.isEmpty,
               tags.allSatisfy({ if case .compound = $0.value { return true }; return false }) {
                let owners = try tags.map { try owner($0.value, dimensions: dimensions) }
                if owners.allSatisfy({ $0 != nil }) {
                    recognized = true
                    let kept = zip(tags, owners).filter { $0.1 != id }.map { $0.0 }
                    if kept.count != tags.count { changed = true }
                    return .compound(kept)
                }
            }
            var result: [NBTNamedTag] = []
            for tag in tags { result.append(NBTNamedTag(name: tag.name, value: try filterLists(tag.value, hint: tag.name, id: id, dimensions: dimensions, changed: &changed, recognized: &recognized))) }
            return .compound(result)
        case .list(let type, let values):
            var result: [NBTValue] = []
            for child in values { result.append(try filterLists(child, hint: hint, id: id, dimensions: dimensions, changed: &changed, recognized: &recognized)) }
            return .list(type, result)
        default: return value
        }
    }
}

struct DimensionReferencePlan {
    var puts: [(key: Data, value: Data)] = []
    var playerCount = 0
    private static func normalize(_ name: String) -> String { String(name.lowercased().filter { $0.isLetter || $0.isNumber }) }
    private static let currentNames = Set(["dimensionid", "dimension"])
    private static let spawnNames = Set(["spawndimension", "respawndimension", "spawndimensionid"])
    private static let nestedNames = Set(["respawn", "spawn", "spawnpoint", "playerspawn", "bedspawn", "respawnpoint"])

    static func build(database: MojangLevelDB, target: DimensionRecord, dimensions: [DimensionRecord]) throws -> DimensionReferencePlan {
        var plan = DimensionReferencePlan()
        let remaining = dimensions.filter { $0.id != target.id }
        let fallback = remaining.first(where: { $0.id == 0 }) ?? remaining.first
        for entry in try database.entries(includeValues: false, limit: 0) {
            let name = String(data: entry.key, encoding: .utf8) ?? ""
            guard name == "~local_player" || name == "LocalPlayer" || name.hasPrefix("player_") || name.hasPrefix("legacy_console_player_") else { continue }
            let records = try ConsecutiveNBTCodec.decode(database.get(entry.key) ?? Data())
            var output = Data(), changed = false
            for record in records {
                var rootChanged = false
                let root = try migrate(record.document.root, target: target.id, fallback: fallback, dimensions: dimensions, nested: false, changed: &rootChanged)
                changed = changed || rootChanged
                if rootChanged { output.append(try BedrockNBTCodec.encode(NBTDocument(rootName: record.document.rootName, root: root), encoding: record.encoding)) }
                else { output.append(record.rawData) }
            }
            if changed { plan.puts.append((entry.key, output)); plan.playerCount += 1 }
        }
        if let bytes = try database.get(Data("WorldClocks".utf8)) {
            let records = try ConsecutiveNBTCodec.decode(bytes)
            guard records.count == 1, case .compound(var tags) = records[0].document.root,
                  let index = tags.firstIndex(where: { $0.name == "clocks" }), case .list(let type, let clocks) = tags[index].value else { throw MCBEEditorError.malformedData("WorldClocks格式错误") }
            let kept = try clocks.filter { clock in
                guard let name = clock.stringValue(named: "Name") else { throw MCBEEditorError.malformedData("维度时钟缺少Name") }
                return clockID(name, dimensions: dimensions) != target.id
            }
            if kept.count != clocks.count {
                tags[index] = NBTNamedTag(name: "clocks", value: .list(type, kept))
                plan.puts.append((Data("WorldClocks".utf8), try BedrockNBTCodec.encode(NBTDocument(rootName: records[0].document.rootName, root: .compound(tags)), encoding: records[0].encoding)))
            }
        }
        return plan
    }

    private static func clockID(_ name: String, dimensions: [DimensionRecord]) -> Int32? {
        if let row = dimensions.first(where: { $0.name == name }) { return row.id }
        switch name.lowercased() {
        case "overworld", "minecraft:overworld": return 0
        case "nether", "minecraft:nether": return 1
        case "the_end", "minecraft:the_end": return 2
        default: return Int32(name)
        }
    }
    private static func referenceID(_ value: NBTValue, dimensions: [DimensionRecord]) throws -> Int32 {
        switch value {
        case .int(let id): return id
        case .byte(let id): return Int32(id)
        case .short(let id): return Int32(id)
        case .long(let id): if let exact = Int32(exactly: id) { return exact }
        case .string(let name): if let id = clockID(name, dimensions: dimensions) { return id }
        default: break
        }
        throw MCBEEditorError.malformedData("玩家维度引用无法解析，未删除任何数据")
    }
    private static func migrate(_ value: NBTValue, target: Int32, fallback: DimensionRecord?, dimensions: [DimensionRecord], nested: Bool, changed: inout Bool) throws -> NBTValue {
        guard case .compound(var tags) = value else { throw MCBEEditorError.malformedData("玩家NBT根或重生位置必须为Compound") }
        let dimensionTags = tags.filter { (nested ? currentNames.union(spawnNames) : currentNames).contains(normalize($0.name)) }
        let positionExists = tags.contains { ["pos", "position"].contains(normalize($0.name)) }
        let currentIDs = Set(try dimensionTags.map { try referenceID($0.value, dimensions: dimensions) })
        guard currentIDs.count <= 1 else { throw MCBEEditorError.malformedData("玩家当前位置维度冲突") }
        let currentAffected = try dimensionTags.contains { try referenceID($0.value, dimensions: dimensions) == target } || (dimensionTags.isEmpty && (positionExists || (nested && tags.contains { ["x", "z", "spawnx", "spawnz"].contains(normalize($0.name)) })) && target == 0)
        let spawnTags = tags.filter { spawnNames.contains(normalize($0.name)) }
        let spawnExists = tags.contains { ["spawnx", "spawnz"].contains(normalize($0.name)) }
        let spawnIDs = Set(try spawnTags.map { try referenceID($0.value, dimensions: dimensions) })
        guard spawnIDs.count <= 1 else { throw MCBEEditorError.malformedData("玩家重生维度冲突") }
        let spawnReferenceAffected = try spawnTags.contains { try referenceID($0.value, dimensions: dimensions) == target }
        let spawnAffected = !nested && (spawnReferenceAffected || (spawnTags.isEmpty && spawnExists && target == 0))
        if currentAffected || spawnAffected {
            guard let fallback = fallback else { throw MCBEEditorError.malformedData("玩家仍引用此维度，且没有可迁入的剩余维度") }
            changed = true
            func set(_ name: String, _ value: NBTValue) { tags.removeAll { $0.name == name }; tags.append(NBTNamedTag(name: name, value: value)) }
            let replacedNames = nested ? currentNames.union(spawnNames) : (currentAffected ? currentNames : Set<String>()).union(spawnAffected ? spawnNames : Set<String>())
            tags = tags.map { replacedNames.contains(normalize($0.name)) ? NBTNamedTag(name: $0.name, value: .int(fallback.id)) : $0 }
            if currentAffected {
                if dimensionTags.isEmpty { set(nested ? "SpawnDimension" : "DimensionId", .int(fallback.id)) }
                for index in tags.indices where ["pos", "position"].contains(normalize(tags[index].name)) {
                    let y: Float = nested ? 64 : 65.62
                    tags[index] = NBTNamedTag(name: tags[index].name, value: .list(.float, [.float(0.5), .float(y), .float(0.5)]))
                }
                if !nested && !positionExists { set("Pos", .list(.float, [.float(0.5), .float(65.62), .float(0.5)])) }
            }
            if spawnAffected || nested {
                if spawnTags.isEmpty && !nested { set("SpawnDimension", .int(fallback.id)) }
                for index in tags.indices {
                    let key = normalize(tags[index].name)
                    if ["spawnx", "spawnz", "spawnforced", "forced"].contains(key) || (nested && ["x", "z"].contains(key)) { tags[index] = NBTNamedTag(name: tags[index].name, value: key.contains("forced") ? .byte(0) : .int(0)) }
                    if key == "spawny" || (nested && key == "y") { tags[index] = NBTNamedTag(name: tags[index].name, value: .int(64)) }
                }
                if !nested { set("SpawnX", .int(0)); set("SpawnY", .int(64)); set("SpawnZ", .int(0)); set("SpawnForced", .byte(0)) }
            }
        }
        if !nested {
            for index in tags.indices where nestedNames.contains(normalize(tags[index].name)) {
                tags[index] = NBTNamedTag(name: tags[index].name, value: try migrate(tags[index].value, target: target, fallback: fallback, dimensions: dimensions, nested: true, changed: &changed))
            }
        }
        return .compound(tags)
    }
}
