#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v swiftc >/dev/null || { echo "error: Swift compiler is required for audit regression tests" >&2; exit 127; }
AUDIT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/mcbeeditor-audit.XXXXXX")"
trap 'rm -rf -- "$AUDIT_TMP"' EXIT

cat > "$AUDIT_TMP/main.swift" <<'SWIFT'
import Foundation

@main
struct AuditTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            checks += 1
        }
        func rejects(_ description: String, _ body: () throws -> Void) {
            do { try body() } catch { checks += 1; return }
            preconditionFailure(description)
        }
        func color(_ name: String, id: UInt16? = nil, data: UInt8? = nil) -> UInt32? {
            BedrockBlockMapColorCatalog.rgbHex(for: name, legacyID: id, legacyData: data)
        }
        func state(_ name: String, properties: [String: String]) -> BedrockBlockState {
            BedrockBlockState(nbt: .compound([
                NBTNamedTag(name: "name", value: .string(name)),
                NBTNamedTag(name: "states", value: .compound(properties.map {
                    NBTNamedTag(name: $0.key, value: .string($0.value))
                }))
            ]), legacyID: nil, legacyData: nil)
        }

        // Golden cases: two states sharing one legacy identifier must render
        // like their distinct named modern variants without changing the NBT.
        let cases: [(String, [String: String], String)] = [
            ("minecraft:wool", ["color": "red"], "minecraft:red_wool"),
            ("minecraft:wool", ["color": "blue"], "minecraft:blue_wool"),
            ("minecraft:concretePowder", ["color": "cyan"], "minecraft:cyan_concrete_powder"),
            ("minecraft:stained_hardened_clay", ["color": "silver"], "minecraft:light_gray_terracotta"),
            ("minecraft:hard_stained_glass", ["color": "blue"], "minecraft:hard_blue_stained_glass"),
            ("minecraft:wooden_slab", ["wood_type": "dark_oak"], "minecraft:dark_oak_slab"),
            ("minecraft:leaves", ["old_leaf_type": "spruce"], "minecraft:spruce_leaves"),
            ("minecraft:sand", ["sand_type": "red"], "minecraft:red_sand"),
            ("minecraft:stone", ["stone_type": "diorite"], "minecraft:diorite"),
            ("minecraft:prismarine", ["prismarine_block_type": "dark"], "minecraft:dark_prismarine"),
            ("minecraft:sponge", ["sponge_type": "wet"], "minecraft:wet_sponge"),
            ("minecraft:red_flower", ["flower_type": "blue_orchid"], "minecraft:blue_orchid"),
            ("minecraft:double_plant", ["double_plant_type": "syringa"], "minecraft:lilac")
        ]
        for (name, properties, expected) in cases {
            let source = state(name, properties: properties)
            let input = BedrockBlockMapColorInput(state: source)
            check(input.identifier == name, "override identifier changed: \(name)")
            check(input.variantIdentifier == expected, "variant resolution: \(name)")
            check(color(input.variantIdentifier) == color(expected), "variant colour: \(name)")
        }
        check(color("minecraft:moss_carpet") == color("minecraft:moss_block"), "moss carpet became wool")
        check(color("minecraft:pale_moss_carpet") == color("minecraft:pale_moss_block"), "pale moss carpet became wool")
        check(color("minecraft:moss_carpet") != color("minecraft:white_carpet"), "moss must remain green")
        check(color("minecraft:red_nether_brick_stairs") == color("minecraft:red_nether_bricks"), "red nether stairs")
        check(color("minecraft:red_nether_brick_wall") == color("minecraft:red_nether_bricks"), "red nether wall")
        check(color("minecraft:deepslate_diamond_ore") == 0x535557, "deepslate ore rule unreachable")
        check(color("minecraft:infested_deepslate") == 0x3F4245, "infested host colour changed")
        check(color("red:wool") == color("minecraft:white_wool"), "namespace is not a dye")
        check(color("minecraft:double_wooden_slab", id: 157, data: 5) == color("minecraft:dark_oak_slab"), "legacy wood slab")
        check(color("minecraft:wooden_slab", id: 158, data: 13) == color("minecraft:dark_oak_slab"), "upper legacy wood slab")
        check(color("minecraft:prismarine", id: 168, data: 1) == color("minecraft:dark_prismarine"), "legacy prismarine")
        check(color("minecraft:sponge", id: 19, data: 1) == color("minecraft:wet_sponge"), "legacy wet sponge")

        // Bedrock numeric IDs, including the two IDs previously taken from Java.
        for id in [UInt16(35), 159, 160, 171, 218, 236, 237, 241, 254] {
            let converted = BedrockLegacyBlockStateConverter.stateForNumeric(
                BedrockBlockState(nbt: nil, legacyID: id, legacyData: 14)
            )
            check(converted.nbt?.compoundValue(named: "states")?.stringValue(named: "color") == "red", "legacy dye ID \(id)")
        }
        for id in [UInt16(251), 252] {
            let converted = BedrockLegacyBlockStateConverter.stateForNumeric(
                BedrockBlockState(nbt: nil, legacyID: id, legacyData: 5)
            )
            check(BedrockLegacyBlockStateConverter.paletteValue(in: converted) == 5, "observer/structure val lost")
        }
        let historical = BedrockBlockState(nbt: .compound([
            NBTNamedTag(name: "name", value: .string("minecraft:wool")),
            NBTNamedTag(name: "val", value: .short(14))
        ]), legacyID: nil, legacyData: nil)
        let historicalInput = BedrockBlockMapColorInput(state: historical)
        check(color(historicalInput.variantIdentifier, id: historicalInput.legacyID, data: historicalInput.legacyData) == color("minecraft:red_wool"), "historical val colour")

        let lines = SharedCommandFileStore.parseCommandLines("\u{FEFF}help\r\n\r\n info \r\ninvalid\n")
        check(lines.map(\.lineNumber) == [1, 3, 4], "CRLF source line numbers")
        check(lines.map(\.text) == ["help", "info", "invalid"], "BOM/whitespace handling")
        check(SharedCommandFileStore.parseCommandLines("\r\n\n \r").isEmpty, "blank commands")

        let bytes = Data([0xaa, 0xbb, 0x34, 0x12, 0x78])
        var slice = BinaryCursor(data: bytes.dropFirst(2))
        check(try slice.readUInt16LE() == 0x1234, "nonzero Data startIndex")
        check(try slice.readData(count: 1) == Data([0x78]), "sliced readData")
        rejects("readData count overflow") { _ = try slice.readData(count: Int.max) }
        rejects("fixed-width offset overflow") { _ = try bytes.littleEndianUInt32(at: Int.max) }
        check(bytes.dropFirst(2).hexDump().contains("34 12 78"), "sliced hex display")

        var u32 = BinaryCursor(data: Data([0xff, 0xff, 0xff, 0xff, 0x0f]))
        check(try u32.readUnsignedVarInt() == UInt64(UInt32.max), "UInt32 maximum")
        var u64 = BinaryCursor(data: Data(Array(repeating: UInt8(0xff), count: 9) + [1]))
        check(try u64.readUnsignedVarInt(maxBytes: 10) == UInt64.max, "UInt64 maximum")
        for (data, width) in [(Data([0xff, 0xff, 0xff, 0xff, 0x1f]), 5),
                              (Data(Array(repeating: UInt8(0xff), count: 9) + [2]), 10),
                              (Data([0x80]), 5)] {
            rejects("overflow/truncated VarInt accepted") {
                var cursor = BinaryCursor(data: data)
                _ = try cursor.readUnsignedVarInt(maxBytes: width)
            }
        }
        for encoding in [NBTEncoding.littleEndian, .bigEndian, .littleEndianVarInt] {
            let document = NBTDocument(rootName: "test", root: .compound([
                NBTNamedTag(name: "list", value: .list(.compound, [.compound([])])),
                NBTNamedTag(name: "empty", value: .list(.end, [])),
                NBTNamedTag(name: "ints", value: .intArray([Int32.min, 0, Int32.max])),
                NBTNamedTag(name: "longs", value: .longArray([Int64.min, Int64.max]))
            ]))
            let encoded = try BedrockNBTCodec.encode(document, encoding: encoding)
            let decoded = try BedrockNBTCodec.decode(encoded, encoding: encoding)
            check(try BedrockNBTCodec.encode(decoded, encoding: encoding) == encoded, "valid collection round trip")
            for type in [NBTTagType.list, .intArray, .longArray] {
                var writer = BinaryWriter()
                writer.writeByte(type.rawValue)
                if encoding == .littleEndianVarInt { writer.writeUnsignedVarInt(0) }
                else { writer.writeUInt16LE(0) }
                if type == .list { writer.writeByte(NBTTagType.int.rawValue) }
                switch encoding {
                case .littleEndian: writer.writeInt32LE(100_000_000)
                case .bigEndian: writer.writeInt32BE(100_000_000)
                case .littleEndianVarInt: writer.writeSignedVarInt(100_000_000)
                }
                rejects("impossible collection length accepted") { _ = try BedrockNBTCodec.decode(writer.data, encoding: encoding) }
            }
        }
        check(NBTValue.long(Int64.max).integerValue() == Int64.max, "Int64 precision")
        check(NBTValue.double(-1.75).integerValue() == -1, "truncation convention")
        check(NBTValue.double(-1.75).integerValue(rounding: .toNearestOrAwayFromZero) == -2, "rounding convention")
        for number in [Double.nan, Double.infinity, -Double.infinity, Double(Int64.max), 1e100] {
            check(NBTValue.double(number).integerValue() == nil, "invalid floating integer accepted")
        }
        check(MapCoordinate.chunkDistance(fromBlockDistance: Int64.max) == Int32.max, "distance overflow")
        check(MapCoordinate.blockDistance(fromChunkDistance: Int64.max) == (Int64.max / 16) * 16, "block distance overflow")
        print("Source audit regression tests passed (\(checks) checks)")
    }
}
SWIFT

swiftc -parse-as-library \
  "$ROOT/Sources/Support/Errors.swift" \
  "$ROOT/Sources/Support/Hex.swift" \
  "$ROOT/Sources/Support/BedrockDataValueCatalog.swift" \
  "$ROOT/Sources/Support/BedrockBlockIdentifier.swift" \
  "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift" \
  "$ROOT/Sources/Support/BedrockLegacyBlockStateConverter.swift" \
  "$ROOT/Sources/Support/SharedCommandFileStore.swift" \
  "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/BinaryCursor.swift" \
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift" \
  "$ROOT/Sources/Chunk/MapCoordinate.swift" \
  "$ROOT/Sources/Chunk/BedrockDBKey.swift" \
  "$ROOT/Sources/Chunk/BedrockMapRegion.swift" \
  "$ROOT/Sources/Chunk/BedrockSubChunk.swift" \
  "$ROOT/Sources/Chunk/BedrockBlockMapColorCatalog.swift" \
  "$ROOT/Sources/Chunk/BedrockBlockMapColorInput.swift" \
  "$AUDIT_TMP/main.swift" -o "$AUDIT_TMP/test"
"$AUDIT_TMP/test"
