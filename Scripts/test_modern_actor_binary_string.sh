#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/MojangLevelDBStub.swift" <<'SWIFT'
import Foundation
final class MojangLevelDB {
    let values: [Data: Data]
    init(values: [Data: Data]) { self.values = values }
    func get(_ key: Data) throws -> Data? { values[key] }
    func entries(prefix: Data? = nil, includeValues: Bool = false, limit: Int = 0) throws -> [(key: Data, value: Data?)] {
        let matches = values.keys.filter { key in
            guard let prefix = prefix else { return true }
            return key.starts(with: prefix)
        }.sorted { $0.lexicographicallyPrecedes($1) }
        let selected = limit > 0 ? Array(matches.prefix(limit)) : matches
        return selected.map { ($0, includeValues ? values[$0] : nil) }
    }
}
SWIFT

cat > "$TMP/test.swift" <<'SWIFT'
import Foundation

@main
struct Test {
    static func main() throws {
        // 1.26.33 actor records can store the raw 8-byte actor storage
        // reference inside a TAG_String. 0x91 makes this intentionally invalid
        // UTF-8 and reproduced the real-world "unknown entity" regression.
        let reference = Data([0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x02, 0x91])
        precondition(String(data: reference, encoding: .utf8) == nil)
        let rawString = NBTRawStringCodec.decode(reference)
        precondition(NBTRawStringCodec.rawData(in: rawString) == reference)

        let uid: Int64 = -68_719_476_079
        let document = NBTDocument(rootName: "", root: .compound([
            NBTNamedTag(name: "identifier", value: .string("minecraft:zombie_horse")),
            NBTNamedTag(name: "UniqueID", value: .long(uid)),
            NBTNamedTag(name: "Pos", value: .list(.float, [
                .float(-247.07564), .float(64), .float(334.75916)
            ])),
            NBTNamedTag(name: "internalComponents", value: .compound([
                NBTNamedTag(name: "EntityStorageKeyComponent", value: .compound([
                    NBTNamedTag(name: "StorageKey", value: .string(rawString))
                ]))
            ]))
        ]))

        let encoded = try BedrockNBTCodec.encode(document, encoding: .littleEndian)
        let records = try ConsecutiveNBTCodec.decode(encoded)
        precondition(records.count == 1)
        guard case .compound(let rootTags) = records[0].document.root else { fatalError() }
        guard let identifierTag = rootTags.first(where: { $0.name == "identifier" }),
              case .string(let identifier) = identifierTag.value else { fatalError() }
        precondition(identifier == "minecraft:zombie_horse")
        guard let internalTag = rootTags.first(where: { $0.name == "internalComponents" }),
              case .compound(let internalTags) = internalTag.value,
              let storageComponent = internalTags.first(where: { $0.name == "EntityStorageKeyComponent" }),
              case .compound(let storageTags) = storageComponent.value,
              let storageKeyTag = storageTags.first(where: { $0.name == "StorageKey" }),
              case .string(let decodedRawString) = storageKeyTag.value else { fatalError() }
        precondition(NBTRawStringCodec.rawData(in: decodedRawString) == reference)
        let roundTrip = try ConsecutiveNBTCodec.encode(records)
        precondition(roundTrip == encoded)

        var actorKey = Data("actorprefix".utf8)
        actorKey.append(reference)
        var digestKey = Data("digp".utf8)
        digestKey.appendLE(Int32(-16))
        digestKey.appendLE(Int32(20))
        let database = MojangLevelDB(values: [actorKey: encoded, digestKey: reference])
        let scanned = try BedrockWorldObjectScanner(database: database).scanAll(
            dimensions: [0], includeEntities: true, includeBlockEntities: false
        )
        precondition(scanned.objects.count == 1)
        precondition(scanned.objects[0].identifier == "minecraft:zombie_horse")
        precondition(scanned.objects[0].uniqueID == uid)
        precondition(scanned.objects[0].storage.actorStorageReference == reference)

        // Before the fix, any little-endian failure was blindly retried as
        // VarInt NBT. This byte sequence can look like an empty VarInt compound
        // with trailing garbage, so it must now be rejected.
        let falseVarIntFallback = Data([0x0A, 0x00, 0x00, 0xFF])
        do {
            _ = try ConsecutiveNBTCodec.decode(falseVarIntFallback)
            fatalError("false VarInt fallback was accepted")
        } catch {
            // Expected.
        }

        print("Modern actor binary TAG_String regression tests passed")
    }
}
SWIFT

swiftc \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Chunk/MapCoordinate.swift" \
  "$ROOT/Sources/Chunk/BedrockMapRegion.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/NBT/ConsecutiveNBTCodec.swift" \
  "$TMP/MojangLevelDBStub.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObject.swift" \
  "$ROOT/Sources/Entity/BedrockWorldObjectScanner.swift" \
  -parse-as-library "$TMP/test.swift" -o "$TMP/test"
"$TMP/test"
