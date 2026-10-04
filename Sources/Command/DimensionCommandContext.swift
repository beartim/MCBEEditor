import Foundation

/// A memory-only registry projection. It never writes to the world database.
final class DimensionCommandContext {
    private let worldBound: Bool
    private var names: [String: Int32]
    private var occupiedKeys: Set<Data>

    init(dimensions: [DimensionRecord]? = nil, databaseKeys: [Data] = []) {
        worldBound = dimensions != nil
        names = Dictionary(uniqueKeysWithValues: (dimensions ?? []).map { ($0.name, $0.id) })
        occupiedKeys = Set(databaseKeys)
    }

    convenience init(database: MojangLevelDB) throws {
        self.init(dimensions: try DimensionStore(database: database).snapshot(),
                  databaseKeys: try database.entries(includeValues: false, limit: 0).map(\.key))
    }

    func resolve(_ token: String) throws -> Int32 {
        if let id = names[token] { return id }
        switch token.lowercased() {
        case "overworld", "minecraft:overworld": return 0
        case "nether", "minecraft:nether": return 1
        case "the_end", "minecraft:the_end": return 2
        default:
            if let id = Int32(token) { return id }
            if !worldBound {
                _ = try DimensionNameRules.validateAddition(name: token, id: 3)
                return 0 // syntax only; every execution binds the original text again.
            }
            throw MCBEEditorError.malformedData("维度名称或 ID 无效：\(token)")
        }
    }

    func apply(_ command: ParsedWorldCommand) throws {
        switch command {
        case .dimensionAdd(let rawName, let id):
            let name = try DimensionNameRules.validateAddition(name: rawName, id: id)
            let key = DimensionStore.dataKey(name: name)
            guard names[name] == nil, !names.values.contains(id) else {
                throw MCBEEditorError.malformedData("维度名称或 ID 已存在：\(name)=\(id)")
            }
            guard !occupiedKeys.contains(key) else { throw MCBEEditorError.malformedData("数据库键已存在：\(name)") }
            names[name] = id
            occupiedKeys.insert(key)
        case .dimensionPurge(let token), .dimensionEmpty(let token):
            let id = try resolve(token)
            let rows = names.filter { $0.value == id }
            guard !rows.isEmpty else {
                if worldBound { throw MCBEEditorError.malformedData("维度不存在：\(id)") }
                return
            }
            if case .dimensionPurge = command {
                for row in rows {
                    names.removeValue(forKey: row.key)
                    occupiedKeys.remove(DimensionStore.dataKey(name: row.key))
                }
                if id >= 0 && id <= 2 { occupiedKeys.remove(Data("dimension\(id)".utf8)) }
            } else if (id < 0 || id > 2), let row = rows.first, Int32(row.key) != nil {
                var name = "dimension_\(id)"
                while names[name] != nil || occupiedKeys.contains(DimensionStore.dataKey(name: name)) { name += "_" }
                names.removeValue(forKey: row.key)
                names[name] = id
                occupiedKeys.insert(DimensionStore.dataKey(name: name))
            }
        default: break
        }
    }
}
