#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/Stubs.swift" <<'SWIFT'
import Foundation

enum MCBEEditorError: Error {
    case malformedData(String)
    case unsupported(String)
}

enum NBTEncoding { case littleEndian }
struct NBTDocument { var marker: UInt8 }
struct ConsecutiveNBTRecord {
    var document: NBTDocument
    var rawData: Data
    var encoding: NBTEncoding
}

enum ConsecutiveNBTCodec {
    static func encode(_ roots: [ConsecutiveNBTRecord]) throws -> Data {
        Data(roots.map { $0.document.marker })
    }
    static func decode(_ data: Data) throws -> [ConsecutiveNBTRecord] {
        data.map { ConsecutiveNBTRecord(document: NBTDocument(marker: $0), rawData: Data([$0]), encoding: .littleEndian) }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

final class MojangLevelDB {
    var storage: [Data: Data] = [:]
    func get(_ key: Data) throws -> Data? { storage[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { storage[key] = value }
    func delete(_ key: Data, sync: Bool = true) throws { storage.removeValue(forKey: key) }
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        for key in deletes { storage.removeValue(forKey: key) }
        for item in puts { storage[item.key] = item.value }
    }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        storage.map { (key: $0.key, value: includeValues ? $0.value : nil) }
    }
}

final class WorldSession {
    let db = MojangLevelDB()
    func database() throws -> MojangLevelDB { db }
}
SWIFT

cat > "$TMP/Main.swift" <<'SWIFT'
import Foundation

@main
struct TestMain {
    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }

    static func main() throws {
        let session = WorldSession()
        let store = MetadataNBTStore(session: session)

        expect(try MetadataNBTStore.validatedKeyText(" Overworld ") == "Overworld", "fixed metadata key validation failed")
        expect(try MetadataNBTStore.validatedKeyText("map_123") == "map_123", "map metadata key validation failed")
        do {
            _ = try MetadataNBTStore.validatedKeyText("structuretemplate_bad")
            fatalError("unsupported metadata key was accepted")
        } catch { }

        let first = try store.create(keyText: "map_1", documents: [NBTDocument(marker: 0x11), NBTDocument(marker: 0x12)])
        expect(first.rawData == Data([0x11, 0x12]), "create changed NBT payload")
        expect(try store.contains(keyText: "map_1"), "created metadata not found")

        try store.rename(record: first, to: "map_2")
        expect(try session.db.get(Data("map_1".utf8)) == nil, "old key survived rename")
        expect(try session.db.get(Data("map_2".utf8)) == Data([0x11, 0x12]), "rename did not preserve raw bytes")

        let second = try store.create(keyText: "map_3", documents: [NBTDocument(marker: 0x33)])
        let renamedFirst = MetadataNBTStore.makeRecord(key: Data("map_2".utf8), value: Data([0x11, 0x12]))
        try store.renameBatch([
            MetadataNBTRename(record: renamedFirst, newKeyText: "map_20"),
            MetadataNBTRename(record: second, newKeyText: "map_30")
        ])
        expect(try session.db.get(Data("map_20".utf8)) == Data([0x11, 0x12]), "batch rename lost first payload")
        expect(try session.db.get(Data("map_30".utf8)) == Data([0x33]), "batch rename lost second payload")
        expect(try session.db.get(Data("map_2".utf8)) == nil, "batch rename kept old first key")
        expect(try session.db.get(Data("map_3".utf8)) == nil, "batch rename kept old second key")

        _ = try store.create(keyText: "map_99", documents: [NBTDocument(marker: 0x99)])
        let batchRecord = MetadataNBTStore.makeRecord(key: Data("map_20".utf8), value: Data([0x11, 0x12]))
        do {
            try store.renameBatch([MetadataNBTRename(record: batchRecord, newKeyText: "map_99")])
            fatalError("batch rename overwrote an unselected destination")
        } catch { }
        expect(try session.db.get(Data("map_20".utf8)) == Data([0x11, 0x12]), "failed batch rename mutated source")
        expect(try session.db.get(Data("map_99".utf8)) == Data([0x99]), "failed batch rename mutated destination")

        let toDelete = [
            MetadataNBTStore.makeRecord(key: Data("map_20".utf8), value: Data([0x11, 0x12])),
            MetadataNBTStore.makeRecord(key: Data("map_30".utf8), value: Data([0x33]))
        ]
        let count = try store.delete(records: toDelete)
        expect(count == 2, "batch delete count mismatch")
        expect(try session.db.get(Data("map_20".utf8)) == nil, "batch delete kept first key")
        expect(try session.db.get(Data("map_30".utf8)) == nil, "batch delete kept second key")

        print("Metadata CRUD and batch store regression passed")
    }
}
SWIFT

swiftc \
  "$TMP/Stubs.swift" \
  "$ROOT/Sources/World/MetadataNBTStore.swift" \
  "$TMP/Main.swift" \
  -o "$TMP/test_metadata_crud_batch"
"$TMP/test_metadata_crud_batch"

UI="$ROOT/Sources/UI/MetadataNBTViewControllers.swift"
STORE="$ROOT/Sources/World/MetadataNBTStore.swift"
grep -q 'barButtonSystemItem: .add' "$UI"
grep -q 'title: "重命名元数据键"' "$UI"
grep -q 'title: "删除世界元数据？"' "$UI"
grep -q 'promptBatchRename' "$UI"
grep -q 'deleteBatchSelection' "$UI"
grep -q 'copyBatchKeys' "$UI"
grep -q 'func renameBatch' "$STORE"
grep -q 'func delete(records:' "$STORE"
grep -q 'func create(keyText:' "$STORE"

echo 'Metadata UI create/delete/rename and batch actions passed'
