#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/Stubs.swift" <<'SWIFT'
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
        let keys = values.keys.filter { key in prefix.map { key.starts(with: $0) } ?? true }
            .sorted { $0.lexicographicallyPrecedes($1) }
        let selected = limit > 0 ? Array(keys.prefix(limit)) : keys
        return selected.map { ($0, includeValues ? values[$0] : nil) }
    }
}

SWIFT

cat > "$TMP/Tests.swift" <<'SWIFT'
import Foundation

@main
enum Tests {
    static func modern(_ name: String, version: Int32 = 18_168_865) -> BedrockBlockState {
        BedrockBlockState(nbt: .compound([
            NBTNamedTag(name: "name", value: .string(name)),
            NBTNamedTag(name: "states", value: .compound([])),
            NBTNamedTag(name: "version", value: .int(version))
        ]), legacyID: nil, legacyData: nil)
    }

    static func old(version: UInt8 = 7, y: Int8 = 4, id: UInt16 = 35, data: UInt8 = 14) -> BedrockSubChunk {
        let air = BedrockBlockState(nbt: nil, legacyID: 0, legacyData: 0)
        let block = BedrockBlockState(nbt: nil, legacyID: id, legacyData: data)
        var indices = Array(repeating: UInt16(0), count: 4096)
        indices[(1 << 8) | (2 << 4) | 3] = 1
        return BedrockSubChunk(
            version: version, yIndex: y,
            storages: [SubChunkStorage(bitsPerBlock: 8, palette: [air, block], indices: indices)],
            trailingData: Data(repeating: 0x5a, count: 4096)
        )
    }

    static func roundTrip(_ subChunk: BedrockSubChunk, keyY: Int8) throws {
        let encoded = try subChunk.encodePersistent()
        let decoded = try BedrockSubChunk.decode(encoded, keyYIndex: keyY)
        let reencoded = try decoded.encodePersistent()
        precondition(reencoded == encoded)
    }

    static func main() throws {
        // v8/v9 storageCount is a full UInt8. Decoding/persistence must no
        // longer impose the old <=16 implementation limit. Editing remains a
        // separate two-layer policy checked by the shell script below.
        let single = SubChunkStorage(bitsPerBlock: 0, palette: [modern("minecraft:air")], indices: Array(repeating: 0, count: 4096))
        let seventeen = Array(repeating: single, count: 17)
        try roundTrip(BedrockSubChunk(version: 8, yIndex: 2, storages: seventeen, trailingData: Data([0xa1])), keyY: 2)
        try roundTrip(BedrockSubChunk(version: 9, yIndex: -4, storages: seventeen, trailingData: Data([0xa2])), keyY: -4)

        // BPB=127 compatibility sentinel: one header byte, no words/palette.
        let sentinelRaw = Data([9, 1, UInt8(bitPattern: Int8(-4)), 0xfe])
        let sentinel = try BedrockSubChunk.decode(sentinelRaw, keyYIndex: -4)
        precondition(sentinel.storages.count == 1)
        precondition(sentinel.storages[0].persistentKind == .emptySentinel127)
        precondition(sentinel.storages[0].blockState(x: 0, y: 0, z: 0)?.isAir == true)
        let sentinelReencoded = try sentinel.encodePersistent()
        precondition(sentinelReencoded == sentinelRaw)

        // Unknown future versions are raw-retained instead of poisoning chunk
        // enumeration. The payload must remain byte-for-byte identical.
        let futureRaw = Data([10, 0xde, 0xad, 0xbe, 0xef])
        let future = try BedrockSubChunk.decode(futureRaw, keyYIndex: 7)
        precondition(future.isRawPreservedUnknownVersion)
        precondition(future.version == 10 && future.yIndex == 7)
        let futureReencoded = try future.encodePersistent()
        precondition(futureReencoded == futureRaw)

        // v1/v8 val-only palettes remain val-only and can still be understood
        // by the compatibility view. No states:{} is synthesized on round-trip.
        let valState = BedrockBlockState(nbt: .compound([
            NBTNamedTag(name: "name", value: .string("minecraft:wool")),
            NBTNamedTag(name: "val", value: .short(14)),
            NBTNamedTag(name: "version", value: .int(BedrockLegacyBlockStateConverter.historicalPaletteVersion))
        ]), legacyID: nil, legacyData: nil)
        let valStorage = SubChunkStorage(bitsPerBlock: 0, palette: [valState], indices: Array(repeating: 0, count: 4096))
        let v1 = BedrockSubChunk(version: 1, yIndex: 4, storages: [valStorage], trailingData: Data())
        let v1Raw = try v1.encodePersistent()
        let v1Decoded = try BedrockSubChunk.decode(v1Raw, keyYIndex: 4)
        let v1Reencoded = try v1Decoded.encodePersistent()
        precondition(v1Reencoded == v1Raw)
        precondition(BedrockLegacyBlockStateConverter.paletteValue(in: v1Decoded.storages[0].palette[0]) == 14)
        precondition(v1Decoded.storages[0].palette[0].stateProperties.contains { $0.0 == "color" && $0.1.contains("red") })

        // Numeric ID+meta -> NBT must retain metadata. Known mappings become
        // structured states; unknown mappings retain a historical val.
        let redWool = BedrockLegacyBlockStateConverter.stateForNumeric(
            BedrockBlockState(nbt: nil, legacyID: 35, legacyData: 14)
        )
        precondition(redWool.stateProperties.contains { $0.0 == "color" && $0.1.contains("red") })
        let unknownMeta = BedrockLegacyBlockStateConverter.stateForNumeric(
            BedrockBlockState(nbt: nil, legacyID: 78, legacyData: 200)
        )
        precondition(BedrockLegacyBlockStateConverter.paletteValue(in: unknownMeta) == 200)

        // 0x34 physical layout is [count LE][Y][X/Z][00][00][id][data]. The
        // data byte is intentionally >15 to prove it is not a nibble.
        let location = try BedrockLegacyBlockExtraEntry.location(x: 3, absoluteY: 70, z: 5)
        let extra = BedrockLegacyBlockExtraData(entries: [
            BedrockLegacyBlockExtraEntry(location: location, blockID: 78, blockData: 200)
        ], trailingData: Data([0xcc, 0xdd]))
        let extraRaw = try extra.encodePersistent()
        precondition(extraRaw[0] == 1 && extraRaw[1] == 0 && extraRaw[2] == 0 && extraRaw[3] == 0)
        precondition(extraRaw[4] == 70 && extraRaw[5] == 0x35 && extraRaw[6] == 0 && extraRaw[7] == 0)
        precondition(extraRaw[8] == 78 && extraRaw[9] == 200)
        let extraDecoded = try BedrockLegacyBlockExtraData.decode(extraRaw)
        let extraReencoded = try extraDecoded.encodePersistent()
        precondition(extraReencoded == extraRaw)

        // Unified access attaches 0x34 as virtual layer 1 without changing the
        // physical v7 layer-0 record.
        let db = MojangLevelDB()
        let pos = ChunkPosition(x: 12, z: -8, dimension: 0)
        let primaryKey = BedrockDBKey.subChunk(x: pos.x, z: pos.z, dimension: pos.dimension, index: 4)
        let primaryRaw = try old().encodePersistent()
        try db.put(primaryRaw, for: primaryKey)
        let extraKey = BedrockDBKey(position: pos, recordType: .legacyBlockExtraData, subChunkIndex: nil).encoded()
        try db.put(extraRaw, for: extraKey)
        guard let record = try BedrockChunkSubChunkAccess.record(database: db, position: pos, yIndex: 4) else {
            preconditionFailure("numeric subchunk + 0x34 not found")
        }
        precondition(record.subChunk.storages.count == 2)
        let extraState = record.subChunk.storages[1].blockState(x: 3, y: 6, z: 5)
        precondition(extraState?.legacyID == 78 && extraState?.legacyData == 200)

        // Replacing only layer 1 keeps layer 0 byte-for-byte and writes the full
        // 8-bit extra data value back to 0x34, including unknown tail bytes.
        var indices = record.subChunk.storages[1].indices
        var palette = record.subChunk.storages[1].palette
        palette.append(BedrockBlockState(nbt: nil, legacyID: 79, legacyData: 201))
        indices[(3 << 8) | (5 << 4) | 6] = UInt16(palette.count - 1)
        let changedExtraLayer = SubChunkStorage(bitsPerBlock: 8, palette: palette, indices: indices)
        let changed = BedrockSubChunk(
            version: record.subChunk.version, yIndex: record.subChunk.yIndex,
            storages: [record.subChunk.storages[0], changedExtraLayer],
            trailingData: record.subChunk.trailingData
        )
        let puts = try BedrockChunkSubChunkAccess.persistentPuts(database: db, position: pos, edited: [4: changed])
        let primaryPut = puts.first { BedrockDBKey.parse($0.key)?.recordType == .subChunk }
        let extraPut = puts.first { BedrockDBKey.parse($0.key)?.recordType == .legacyBlockExtraData }
        precondition(primaryPut?.value == primaryRaw)
        guard let extraOut = extraPut?.value else { preconditionFailure("0x34 write missing") }
        let decodedExtraOut = try BedrockLegacyBlockExtraData.decode(extraOut)
        precondition(decodedExtraOut.trailingData == Data([0xcc, 0xdd]))
        precondition(decodedExtraOut.entries.first { $0.location == location }?.blockID == 79)
        precondition(decodedExtraOut.entries.first { $0.location == location }?.blockData == 201)

        // Whole-chunk modernisation consumes 0x34 and migrates it to v9 storage1.
        let plan = try BedrockLegacyChunkUpgrade.plan(database: db, position: pos, preferredPaletteVersion: 18_168_865)
        precondition(plan.metadataDeletes.contains(extraKey))
        guard let upgradedPut = plan.subChunkPuts.first(where: { BedrockDBKey.parse($0.key)?.subChunkIndex == 4 }) else {
            preconditionFailure("v7 -> v9 upgraded subchunk missing")
        }
        let upgraded = try BedrockSubChunk.decode(upgradedPut.value, keyYIndex: 4)
        precondition(upgraded.version == 9 && upgraded.storages.count >= 2)
        let migratedExtra = upgraded.storages[1].blockState(x: 3, y: 6, z: 5)
        precondition(BedrockLegacyBlockStateConverter.paletteValue(in: migratedExtra!) == 200)

        // Unknown raw v10 must not win preferred-version inference over a known
        // v9 record in the same chunk.
        let knownKey = BedrockDBKey.subChunk(x: 99, z: 99, dimension: 0, index: 0)
        let rawKey = BedrockDBKey.subChunk(x: 99, z: 99, dimension: 0, index: 1)
        try db.put(try BedrockSubChunk(version: 9, yIndex: 0, storages: [single], trailingData: Data()).encodePersistent(), for: knownKey)
        try db.put(futureRaw, for: rawKey)
        let inferredVersion = try BedrockEmptyChunk.preferredSubChunkVersion(
            database: db, at: ChunkPosition(x: 99, z: 99, dimension: 0), fallback: 9
        )
        precondition(inferredVersion == 9)

        print("SubChunk v0-v9 compatibility extension tests passed")
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
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockLegacyBlockExtraData.swift" \
  "$TMP/Stubs.swift" \
  "$ROOT/Sources/Chunk/BedrockChunkSubChunkAccess.swift" \
  "$ROOT/Sources/Chunk/BedrockBiomeData.swift" \
  "$ROOT/Sources/Chunk/BedrockEmptyChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockLegacyChunkUpgrade.swift" \
  -parse-as-library "$TMP/Tests.swift" -o "$TMP/tests"

"$TMP/tests"

grep -q 'static let editableLayerCount = 2' "$ROOT/Sources/Chunk/BedrockBlockColumn.swift" || {
  echo 'error: editable storage layer limit must remain 2' >&2
  exit 1
}
