#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

@main
struct ActorBinaryStorageKeyTest {
  static func main() throws {
    var raw = Data([0x0A, 0x00, 0x00])
    raw.append(contentsOf: [0x08, 0x0A, 0x00])
    raw.append(Data("StorageKey".utf8))
    raw.append(contentsOf: [0x08, 0x00, 0x00, 0x10, 0x00, 0x00, 0x02, 0x91, 0x00, 0x00])
    raw.append(contentsOf: [0x08, 0x0A, 0x00])
    raw.append(Data("identifier".utf8))
    let identifier = Data("minecraft:zombie_horse".utf8)
    raw.append(UInt8(identifier.count & 0xff))
    raw.append(UInt8((identifier.count >> 8) & 0xff))
    raw.append(identifier)
    raw.append(0x00)

    let decoded = try ConsecutiveNBTCodec.decode(raw)
    precondition(decoded.count == 1)
    precondition(decoded[0].encoding == .littleEndian)
    precondition(decoded[0].document.root.stringValue(named: "identifier") == "minecraft:zombie_horse")
    let encoded = try ConsecutiveNBTCodec.encode(decoded)
    precondition(encoded == raw, "binary StorageKey must round-trip byte-for-byte")

    let malformed = Data([0x0A, 0x00, 0x00, 0xFF])
    do {
      _ = try ConsecutiveNBTCodec.decode(malformed)
      preconditionFailure("malformed LE NBT must not be accepted as an empty VarInt root")
    } catch {
      // Expected.
    }

    print("Actor binary StorageKey NBT tests passed")
  }
}
SWIFT
swiftc -j 4 \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/NBT/ConsecutiveNBTCodec.swift" \
  -parse-as-library "$TMP/main.swift" -o "$TMP/test"
"$TMP/test"
