#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v swiftc >/dev/null || { echo "error: Swift compiler is required for End missing-SubChunk regression tests" >&2; exit 127; }
END_TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/mcbeeditor-end.XXXXXX")"
trap 'rm -rf -- "$END_TEST_TMP"' EXIT

cat > "$END_TEST_TMP/Stubs.swift" <<'SWIFT'
import Foundation

final class MojangLevelDB {
    var values = [Data: Data]()
    func get(_ key: Data) throws -> Data? { values[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { values[key] = value }
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        for key in deletes { values.removeValue(forKey: key) }
        for put in puts { values[put.key] = put.value }
    }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        let keys = values.keys.filter { key in prefix.map { key.starts(with: $0) } ?? true }
            .sorted { $0.lexicographicallyPrecedes($1) }
        return (limit > 0 ? Array(keys.prefix(limit)) : keys).map { ($0, includeValues ? values[$0] : nil) }
    }
}
final class WorldSession {
    let db = MojangLevelDB()
    func database() throws -> MojangLevelDB { db }
}
final class ChunkSurfaceRenderer {
    let database: MojangLevelDB
    init(database: MojangLevelDB) { self.database = database }
}
SWIFT

cat > "$END_TEST_TMP/Tests.swift" <<'SWIFT'
import Foundation

struct Fixture: Decodable {
    struct Entry: Decodable { let keyBase64: String; let valueBase64: String }
    let paletteVersion: Int32
    let v8Chunk: [Int32]
    let v1Chunk: [Int32]
    let emptyChunk: [Int32]
    let entries: [Entry]
}

@main
enum Tests {
    static func main() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        func load() -> WorldSession {
            let session = WorldSession()
            for entry in fixture.entries {
                session.db.values[Data(base64Encoded: entry.keyBase64)!] = Data(base64Encoded: entry.valueBase64)!
            }
            return session
        }
        for coordinates in [fixture.v8Chunk, fixture.v1Chunk, fixture.emptyChunk] {
            let session = load()
            let original = session.db.values
            let position = ChunkPosition(x: coordinates[0], z: coordinates[1], dimension: coordinates[2])
            let renderer = ChunkSurfaceRenderer(database: session.db)
            let store = BedrockBlockNBTStore(session: session)
            let expectedVersion: UInt8 = coordinates == fixture.v1Chunk ? 1 : 8
            let expectedPaletteVersion: Int32? = expectedVersion == 1 ? nil : fixture.paletteVersion
            for y in [Int32(160), 200, 255] {
                let x = Int64(position.x) * 16
                let z = Int64(position.z) * 16
                let block = try renderer.block(blockX: x, y: y, blockZ: z, dimension: 2)
                precondition(!block.isGenerated, "fixture high slice must start absent")
                // Exercise the actual map -> editable template -> save path;
                // do not seed an already-correct palette version by hand.
                let air = block.stateForEditing(layer: 0)
                precondition(air.nbt != nil && air.paletteVersion == expectedPaletteVersion,
                             "missing End slice must inherit its palette version")
                guard case .compound(var tags)? = air.nbt,
                      let nameIndex = tags.firstIndex(where: { $0.name == "name" }) else {
                    preconditionFailure("missing editable air name")
                }
                tags[nameIndex] = NBTNamedTag(name: "name", value: .string("minecraft:diamond_block"))
                _ = try store.save(block: block, storageIndex: 0,
                                   document: NBTDocument(rootName: "", root: .compound(tags)))
                let keyY = Int8(y / 16)
                let key = BedrockDBKey.subChunk(x: position.x, z: position.z, dimension: 2, index: keyY)
                let saved = try BedrockSubChunk.decode(session.db.values[key]!, keyYIndex: keyY)
                precondition(saved.version == expectedVersion)
                let written = saved.storages[0].blockState(x: 0, y: Int(y % 16), z: 0)
                precondition(written?.name == "minecraft:diamond_block")
                precondition(written?.paletteVersion == expectedPaletteVersion)
                precondition(saved.storages[0].blockState(x: 1, y: Int(y % 16), z: 0)?.isAir == true)
                let reread = try renderer.block(blockX: x, y: y, blockZ: z, dimension: 2)
                precondition(reread.isGenerated && reread.name == "minecraft:diamond_block")
            }
            for (key, value) in original { precondition(session.db.values[key] == value, "existing terrain/metadata changed") }
        }

        // Creating layer 1 first must retain compatible air in storage 0.
        let session = load()
        let renderer = ChunkSurfaceRenderer(database: session.db)
        let missing = try renderer.block(blockX: 0, y: 200, blockZ: 0, dimension: 2)
        let air = missing.stateForEditing(layer: 1)
        precondition(air.paletteVersion == fixture.paletteVersion)
        let state: NBTValue = .compound([
            NBTNamedTag(name: "name", value: .string("minecraft:water")),
            NBTNamedTag(name: "states", value: .compound([])),
            NBTNamedTag(name: "version", value: .int(fixture.paletteVersion))
        ])
        _ = try BedrockBlockNBTStore(session: session).save(
            block: missing, storageIndex: 1, document: NBTDocument(rootName: "", root: state))
        let reread = try renderer.block(blockX: 0, y: 200, blockZ: 0, dimension: 2)
        precondition(reread.layers.count == 2 && reread.layers[0].isAir && reread.layers[1].name == "minecraft:water")
        precondition(reread.layers.allSatisfy { $0.paletteVersion == fixture.paletteVersion })
        try PersistenceCompatibilityChecks.run()
        print("End missing-SubChunk fixture tests passed: actual map templates, v1/v8 creation, layer 1 and byte-preserved neighbors")
    }
}
SWIFT

swiftc -j 4 \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Support/BedrockBlockIdentifier.swift" \
  "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift" \
  "$ROOT/Sources/Support/BedrockLegacyBlockStateConverter.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/Chunk/MapCoordinate.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockLegacyBlockExtraData.swift" \
  "$ROOT/Sources/Chunk/BedrockChunkSubChunkAccess.swift" \
  "$ROOT/Sources/Chunk/BedrockBiomeData.swift" \
  "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift" \
  "$ROOT/Sources/Chunk/BedrockBlockColumn.swift" \
  "$END_TEST_TMP/Stubs.swift" \
  "$ROOT/Scripts/Fixtures/PersistenceCompatibility.swift" \
  -parse-as-library "$END_TEST_TMP/Tests.swift" -o "$END_TEST_TMP/tests"
"$END_TEST_TMP/tests" "$ROOT/Tests/Fixtures/end_missing_subchunks.json"
