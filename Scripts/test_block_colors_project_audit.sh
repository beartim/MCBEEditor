#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/mcbeeditor-block-color-audit"
rm -rf "$TMP"
mkdir -p "$TMP"

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

@main
struct Main {
    static func main() throws {
        func color(_ name: String, _ legacyID: UInt16? = nil, _ data: UInt8? = nil) -> UInt32 {
            BedrockBlockMapColorCatalog.rgbHex(for: name, legacyID: legacyID, legacyData: data)
                ?? BedrockBlockMapColorCatalog.fallbackRGB(for: name)
        }

        precondition(color("minecraft:soul_sand") == 0x544034)
        precondition(color("minecraft:soul_sand") != color("minecraft:sand"))
        precondition(color("minecraft:red_sandstone") == 0xB96A39)
        precondition(color("minecraft:red_sandstone") != color("minecraft:red_sand"))
        precondition(color("minecraft:waterlily") != color("minecraft:water"))
        precondition(color("minecraft:underwater_torch") != color("minecraft:water"))
        precondition(color("minecraft:mossy_cobblestone") != color("minecraft:moss_block"))
        precondition(color("minecraft:stone_bricks") == 0x777777)
        precondition(color("minecraft:prismarine_bricks") == 0x63A89A)
        precondition(color("minecraft:white_terracotta") != color("minecraft:white_wool"))
        precondition(color("minecraft:sand", 12, 1) == 0xB65A27)
        precondition(color("minecraft:wool", 35, 14) == 0xB02E26)
        precondition(color("minecraft:planks", 5, 5) == 0x4B3422)
        precondition(BedrockBlockIdentifier.isAir("minecraft:void_air"))
        precondition(BedrockBlockIdentifier.isWater("minecraft:flowing_water"))
        precondition(!BedrockBlockIdentifier.isWater("minecraft:waterlily"))
        precondition(!BedrockBlockIdentifier.isWater("minecraft:underwater_torch"))

        guard CommandLine.arguments.count == 2 else { preconditionFailure("legacy catalogue path missing") }
        let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"BedrockDataValueEntry\(id:\s*\d+, identifier:\s*\"([^\"]+)\""#)
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let names = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
        precondition(names.count == 256)
        let fallback = names.filter { BedrockBlockMapColorCatalog.rgbHex(for: $0) == nil }
        precondition(Set(fallback) == Set(["minecraft:unused_166", "minecraft:reserved6"]))
        print("Block map color catalogue tests passed (256 legacy identifiers, 254 semantic colors)")
    }
}
SWIFT

swiftc -parse-as-library \
  "$ROOT/Sources/Support/BedrockBlockIdentifier.swift" \
  "$ROOT/Sources/Chunk/BedrockBlockMapColorCatalog.swift" \
  "$TMP/main.swift" -o "$TMP/test"
"$TMP/test" "$ROOT/Sources/Support/BedrockLegacyBlockCatalog.swift"

# Renderer must preserve legacy metadata long enough for the color catalogue to distinguish
# old wool/sand/wood variants.  It must not regress to the old name-only substring cascade.
grep -Fq 'var visibleStates = Array<BedrockBlockState?>' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift"
grep -Fq 'let input = BedrockBlockMapColorInput(state: value.state)' "$ROOT/Sources/Chunk/BedrockCrossSection.swift"
grep -Fq 'legacyID: input.legacyID' "$ROOT/Sources/Chunk/BedrockCrossSection.swift"
grep -Fq 'legacyData: input.legacyData' "$ROOT/Sources/Chunk/BedrockCrossSection.swift"
grep -Fq 'variantIdentifier: input.variantIdentifier' "$ROOT/Sources/Chunk/BedrockCrossSection.swift"
grep -Fq 'BedrockBlockMapColorCatalog.rgbHex' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift"
if grep -Fq 'private func dyedBlockColor' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift"; then
  echo 'error: obsolete renderer-local dyedBlockColor cascade returned' >&2
  exit 1
fi
if grep -Fq 'name.contains("water")' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift"; then
  echo 'error: broad water substring classification returned to map renderer' >&2
  exit 1
fi
if [[ $(grep -R --include='*.swift' -c 'func isHighlightedOre' "$ROOT/Sources" | awk -F: '{sum += $2} END {print sum+0}') -ne 1 ]]; then
  echo 'error: highlighted-ore identifier rules are duplicated instead of centralized' >&2
  exit 1
fi
grep -Fq 'BedrockBlockIdentifier.isHighlightedOre' "$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift"
grep -Fq 'BedrockBlockIdentifier.isHighlightedOre' "$ROOT/Sources/Chunk/BedrockCrossSection.swift"

# Audit cleanup: negative-coordinate division has one source of truth, and the confirmed dead
# modernBlockState helper must not return.
FLOOR_DIV_DECLS=$(grep -R --include='*.swift' -c 'func floorDiv16' "$ROOT/Sources" | awk -F: '{sum += $2} END {print sum+0}')
if [[ "$FLOOR_DIV_DECLS" -ne 1 ]]; then
  echo "error: expected one floorDiv16 declaration, found $FLOOR_DIV_DECLS" >&2
  exit 1
fi
if grep -Fq 'private func modernBlockState(from root:' "$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift"; then
  echo 'error: dead modernBlockState helper returned' >&2
  exit 1
fi
grep -Fq 'MapCoordinate.floorDiv16(y)' "$ROOT/Sources/Command/WorldCommandExecutor.swift"
grep -Fq 'MapCoordinate.floorDiv16(coordinate.y)' "$ROOT/Sources/Command/WorldCommandExecutor.swift"
grep -Fq 'BedrockBlockIdentifier.isAir($0)' "$ROOT/Sources/Command/WorldCommandExecutor.swift"
if grep -Eq 'wide >= 0 \? wide / 16|wideY >= 0 \? wideY / 16' "$ROOT/Sources/Command/WorldCommandExecutor.swift"; then
  echo 'error: executor-local negative coordinate division returned' >&2
  exit 1
fi

echo 'Block-color and source-audit regression checks passed'
