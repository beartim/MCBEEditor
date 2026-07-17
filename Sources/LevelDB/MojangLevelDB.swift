import Foundation

final class MojangLevelDB {
    private let bridge: BTLevelDBBridge

    init(path: URL, readOnly: Bool = true) throws {
        self.bridge = try BTLevelDBBridge(path: path.path, readOnly: readOnly)
    }

    deinit { bridge.close() }

    func get(_ key: Data) throws -> Data? {
        let result = bridge.readResult(forKey: key)
        if let error = result.error {
            throw error
        }
        return result.found ? result.value : nil
    }

    func put(_ value: Data, for key: Data, sync: Bool = true) throws {
        try bridge.put(value, forKey: key, sync: sync)
    }

    func delete(_ key: Data, sync: Bool = true) throws {
        try bridge.deleteKey(key, sync: sync)
    }

    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        let entries = puts.map { BTLevelDBEntry(key: $0.key, value: $0.value) }
        try bridge.applyBatch(puts: entries, deleteKeys: deletes, sync: sync)
    }

    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        let entries = try bridge.entries(withPrefix: prefix, includeValue: includeValues, limit: UInt(max(0, limit)))
        return entries.map { ($0.key, $0.value) }
    }

    func close() { bridge.close() }
}
