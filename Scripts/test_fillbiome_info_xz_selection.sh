#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"
COMMAND="$ROOT/Sources/Command/WorldCommand.swift"
EXECUTOR="$ROOT/Sources/Command/WorldCommandExecutor.swift"
REGION="$ROOT/Sources/Chunk/BedrockRegionStore.swift"
CATALOG="$ROOT/Sources/Support/BedrockDataValueCatalog.swift"
INSPECTOR="$ROOT/Sources/World/WorldInspector.swift"

fail() { echo "fillbiome/info/X-Z regression failed: $*" >&2; exit 1; }
require_fixed() {
  local file="$1" text="$2" label="$3"
  grep -Fq -- "$text" "$file" || fail "$label ($file)"
}

require_fixed "$MAP" 'let maximumCoordinate = centerCoordinate' 'X/Z picker must not select beyond the current rendered plane'
if grep -Fq -- 'let maximumCoordinate = centerCoordinate + crossSectionSelectionHalfRange' "$MAP"; then
  fail 'X/Z picker still extends into the positive/unprojected axis'
fi

require_fixed "$COMMAND" '"fillbiome"' 'fillbiome must be registered'
require_fixed "$COMMAND" 'case fillBiome(targetDimension: Int32, region: CommandBlockBox, biome: CommandBiomeID)' 'fillbiome parsed command case is missing'
require_fixed "$COMMAND" 'case "fillbiome":' 'fillbiome parser is missing'
require_fixed "$COMMAND" 'parseBiomeID(arguments[7])' 'fillbiome biome parser is not wired'
require_fixed "$COMMAND" 'case "info":' 'info parser is missing'
require_fixed "$COMMAND" 'guard arguments.isEmpty else { throw usageError(command) }' 'info must reject arguments'
require_fixed "$CATALOG" 'static func biome(forIdentifier identifier: String) -> BedrockDataValueEntry?' 'string biome ID lookup must resolve through numeric catalog'

require_fixed "$EXECUTOR" 'case .fillBiome(let targetDimension, let region, let biome):' 'fillbiome executor is missing'
require_fixed "$EXECUTOR" 'data3DYRange: region.minimum.y...region.maximum.y' 'fillbiome Data3D Y range is not forwarded'
require_fixed "$EXECUTOR" 'case .info:' 'info executor is missing'
require_fixed "$EXECUTOR" 'let rows = try WorldInspector().inspect(session: session)' 'info must reuse WorldInspector output'
require_fixed "$EXECUTOR" 'outputLines: lines' 'info must emit one terminal output line per world-info row'

require_fixed "$REGION" 'data3DYRange: ClosedRange<Int32>?' 'Y-aware biome editing overload is missing'
require_fixed "$REGION" 'case .data2D, .data2DLegacy:' 'Data2D biome path is missing'
require_fixed "$REGION" 'case .data3D:' 'Data3D biome path is missing'

require_fixed "$INSPECTOR" 'title: "种子"' 'world info seed row is missing'
require_fixed "$INSPECTOR" '"RandomSeed"' 'world seed must read RandomSeed'
require_fixed "$INSPECTOR" 'title: "附魔种子"' 'world info enchantment-seed row is missing'
require_fixed "$INSPECTOR" '"EnchantmentSeed"' 'enchantment seed must read player EnchantmentSeed'

python3 - "$INSPECTOR" <<'PY'
import sys
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
need=[
    'title: "名称"',
    'title: "种子"',
    'title: "附魔种子"',
    'title: "玩家数目"',
]
pos=[]
for token in need:
    i=s.find(token)
    if i < 0:
        raise SystemExit(f"fillbiome/info/X-Z regression failed: missing {token}")
    pos.append(i)
if pos != sorted(pos):
    raise SystemExit('fillbiome/info/X-Z regression failed: world-info row order must be 名称 -> 种子 -> 附魔种子 -> 玩家数目')
PY

echo "fillbiome / info / X-Z selection regression checks passed"
