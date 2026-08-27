#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/LegacyTerrainTestStubs.swift" <<'SWIFT'
import Foundation

final class MojangLevelDB {
    var values: [Data: Data] = [:]
    func get(_ key: Data) throws -> Data? { values[key] }
    func put(_ value: Data, for key: Data, sync: Bool = true) throws { values[key] = value }
    func delete(_ key: Data, sync: Bool = true) throws { values.removeValue(forKey: key) }
    func applyBatch(puts: [(key: Data, value: Data)], deletes: [Data], sync: Bool = true) throws {
        for key in deletes { values.removeValue(forKey: key) }
        for put in puts { values[put.key] = put.value }
    }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        let matches = values.keys.filter { key in
            guard let prefix else { return true }
            return key.starts(with: prefix)
        }.sorted { $0.lexicographicallyPrecedes($1) }
        let selected = limit > 0 ? Array(matches.prefix(limit)) : matches
        return selected.map { ($0, includeValues ? values[$0] : nil) }
    }
}
SWIFT

cat > "$TMP/LegacyTerrainTests.swift" <<'SWIFT'
import Foundation

@main
enum LegacyTerrainTests {
    static func modernState(_ name: String, value: Int32 = 0) -> BedrockBlockState {
        BedrockBlockState(nbt: .compound([
            NBTNamedTag(name: "name", value: .string(name)),
            NBTNamedTag(name: "states", value: .compound([
                NBTNamedTag(name: "test", value: .int(value))
            ])),
            NBTNamedTag(name: "version", value: .int(18_153_728))
        ]), legacyID: nil, legacyData: nil)
    }

    static func legacySubChunk(version: UInt8, y: Int8) -> BedrockSubChunk {
        let air = BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
        let stone = BedrockBlockState(nbt: nil, legacyID: 1, legacyData: 3)
        var indices = Array(repeating: UInt16(0), count: 4096)
        indices[(2 << 8) | (4 << 4) | 3] = 1
        return BedrockSubChunk(
            version: version,
            yIndex: y,
            storages: [SubChunkStorage(bitsPerBlock: 8, palette: [air, stone], indices: indices)],
            trailingData: Data((0..<32).map { UInt8($0) })
        )
    }

    static func assertRoundTrip(_ subChunk: BedrockSubChunk, keyY: Int8) throws {
        let encoded = try subChunk.encodePersistent()
        let decoded = try BedrockSubChunk.decode(encoded, keyYIndex: keyY)
        let reencoded = try decoded.encodePersistent()
        precondition(encoded == reencoded, "SubChunk v\(subChunk.version) round trip changed bytes")
    }

    static func main() throws {
        for version in [UInt8(0), 2, 3, 4, 5, 6, 7] {
            try assertRoundTrip(legacySubChunk(version: version, y: 4), keyY: 4)
        }

        let air = modernState("minecraft:air")
        let stone = modernState("minecraft:stone", value: 1)
        let water = modernState("minecraft:water", value: 2)
        let single = SubChunkStorage(bitsPerBlock: 0, palette: [air], indices: Array(repeating: 0, count: 4096))
        try assertRoundTrip(BedrockSubChunk(version: 1, yIndex: 2, storages: [single], trailingData: Data([0x91])), keyY: 2)

        var twoIndices = Array(repeating: UInt16(0), count: 4096)
        twoIndices[(1 << 8) | (2 << 4) | 3] = 1
        let two = SubChunkStorage(bitsPerBlock: 1, palette: [stone, water], indices: twoIndices)
        try assertRoundTrip(BedrockSubChunk(version: 8, yIndex: 3, storages: [single, two], trailingData: Data([0x92, 0x93])), keyY: 3)
        try assertRoundTrip(BedrockSubChunk(version: 9, yIndex: -4, storages: [single, two], trailingData: Data([0x94])), keyY: 7)

        let emptyRaw = BedrockLegacyTerrain.emptyPersistentData
        precondition(emptyRaw.count == BedrockLegacyTerrain.persistentByteCount)
        var terrain = try BedrockLegacyTerrain.decode(emptyRaw)
        let untouchedEnvironment = emptyRaw.subdata(in: (BedrockLegacyTerrain.blockIDCount + BedrockLegacyTerrain.nibbleCount)..<BedrockLegacyTerrain.persistentByteCount)
        let editedSlice = legacySubChunk(version: 0, y: 4)
        try terrain.replaceSubChunk(yIndex: 4, with: editedSlice)
        let editedRaw = try terrain.encodePersistent()
        precondition(editedRaw.count == 83_200)
        precondition(editedRaw.subdata(in: (BedrockLegacyTerrain.blockIDCount + BedrockLegacyTerrain.nibbleCount)..<83_200) == untouchedEnvironment)
        let verifySlice = try BedrockLegacyTerrain.decode(editedRaw).subChunk(yIndex: 4)
        let verifyState = verifySlice.storages[0].blockState(x: 2, y: 3, z: 4)
        precondition(verifyState?.legacyID == 1 && verifyState?.legacyData == 3)

        let db = MojangLevelDB()
        let existingPosition = ChunkPosition(x: 0, z: 8, dimension: 0)
        let legacyKey = BedrockDBKey(position: existingPosition, recordType: .legacyTerrain, subChunkIndex: nil).encoded()
        try db.put(editedRaw, for: legacyKey)
        let records = try BedrockChunkSubChunkAccess.records(database: db, position: existingPosition)
        precondition(records.count == 8)
        precondition(records.map(\.yIndex) == Array(0...7).map(Int8.init))
        precondition(records.allSatisfy { if case .legacyTerrain = $0.backing { return true }; return false })

        guard let y4 = try BedrockChunkSubChunkAccess.record(database: db, position: existingPosition, yIndex: 4) else {
            preconditionFailure("LegacyTerrain virtual Y=4 was not found")
        }
        let mergedPuts = try BedrockChunkSubChunkAccess.persistentPuts(
            database: db, position: existingPosition, edited: [4: y4.subChunk]
        )
        precondition(mergedPuts.count == 1)
        precondition(BedrockDBKey.parse(mergedPuts[0].key)?.recordType == .legacyTerrain)
        precondition(mergedPuts[0].value.count == 83_200)

        // A stray SubChunkPrefix from an older editor build must not make a
        // predominantly LegacyTerrain 0.10.x dimension switch formats.
        let strayPosition = ChunkPosition(x: 99, z: 99, dimension: 0)
        try db.put(
            try legacySubChunk(version: 0, y: 4).encodePersistent(),
            for: BedrockDBKey.subChunk(x: strayPosition.x, z: strayPosition.z, dimension: 0, index: 4)
        )
        let profile = try BedrockEmptyChunk.profile(database: db, dimension: 0)
        precondition(profile.usesLegacyTerrain)
        precondition(profile.subChunkVersion == 0)
        let missingPosition = ChunkPosition(x: 1, z: 8, dimension: 0)
        let metadata = BedrockEmptyChunk.metadataRecords(at: missingPosition, profile: profile)
        precondition(metadata.count == 1 && metadata[0].recordType == .legacyTerrain)
        precondition(metadata[0].value.count == 83_200)
        let newPuts = try BedrockChunkSubChunkAccess.persistentPuts(
            database: db,
            position: missingPosition,
            edited: [4: legacySubChunk(version: 0, y: 4)],
            preferLegacyTerrainIfMissing: true
        )
        precondition(newPuts.count == 1)
        precondition(BedrockDBKey.parse(newPuts[0].key)?.recordType == .legacyTerrain)
        precondition(newPuts[0].value.count == 83_200)

        if CommandLine.arguments.count > 1 {
            let sampleURL = URL(fileURLWithPath: CommandLine.arguments[1])
            let sample = try Data(contentsOf: sampleURL)
            precondition(sample.count == 83_200)
            let real = try BedrockLegacyTerrain.decode(sample)
            let roundTrip = try real.encodePersistent()
            precondition(roundTrip == sample, "real LegacyTerrain record did not round-trip byte-for-byte")
            var visible = 0
            var maxY = -1
            for x in 0..<16 {
                for z in 0..<16 {
                    var columnTop: Int? = nil
                    for y in stride(from: 127, through: 0, by: -1) {
                        let slice = try real.subChunk(yIndex: Int8(y >> 4))
                        let state = slice.storages[0].blockState(x: x, y: y & 15, z: z)
                        if state?.isAir == false {
                            columnTop = y
                            break
                        }
                    }
                    if let columnTop {
                        visible += 1
                        maxY = max(maxY, columnTop)
                    }
                }
            }
            precondition(visible == 256)
            print("Real LegacyTerrain sample: visible columns=\(visible), maxY=\(maxY)")
        }
        print("LegacyTerrain and SubChunk v0-v9 persistence tests passed")
    }
}
SWIFT

swiftc -j 4 \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunk.swift" \
  "$TMP/LegacyTerrainTestStubs.swift" \
  "$ROOT/Sources/Chunk/BedrockChunkSubChunkAccess.swift" \
  "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" \
  -parse-as-library "$TMP/LegacyTerrainTests.swift" \
  -o "$TMP/legacy-terrain-tests"

if [[ $# -gt 0 ]]; then
  "$TMP/legacy-terrain-tests" "$1"
else
  "$TMP/legacy-terrain-tests"
fi
