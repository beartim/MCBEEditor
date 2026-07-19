#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"
PLAYER="$ROOT/Sources/World/PlayerNBTStore.swift"
JSON="$ROOT/Sources/NBT/NBTJSONCodec.swift"
CLIPBOARD="$ROOT/Sources/UI/NBTEditingUI.swift"

grep -q '^name: MCBEEditor$' "$ROOT/project.yml"
grep -q 'CFBundleDisplayName: MCBEEditor' "$ROOT/project.yml"
grep -q 'PRODUCT_NAME: MCBEEditor' "$ROOT/project.yml"
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.wzn.mcbeeditor$' "$ROOT/project.yml"
grep -q 'text="MCBEEditor"' "$ROOT/Resources/LaunchScreen.storyboard"
grep -q '<string>MCBEEditor</string>' "$ROOT/Resources/Info.plist"

grep -q 'private var showPlayers = true' "$MAP"
grep -q 'configure(localPlayerLayer, fill: .systemYellow)' "$MAP"
grep -q 'configure(onlinePlayerLayer, fill: .systemBlue)' "$MAP"
grep -q 'func appendStar(center: CGPoint' "$MAP"
grep -q 'showPlayerDetails(hit.player)' "$MAP"
grep -q 'PlayerNBTEditorViewController(record: player.record' "$MAP"
grep -q 'currentPosition(for record: PlayerNBTRecord)' "$PLAYER"
grep -q 'isLocalPlayer(_ record: PlayerNBTRecord)' "$PLAYER"

python3 - "$MAP" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index('@objc private func showOverlayOptions()')
end=s.index('private func refreshObjectOverlays', start)
part=s[start:end]
order=['let playerTitle', 'let entityTitle', 'let blockTitle', 'let spawnTitle', 'let spawnerTitle', 'let villageTitle']
pos=[part.index(item) for item in order]
assert pos == sorted(pos), pos
assert 'defaults.set(modeControl.selectedSegmentIndex' not in s
assert 'defaults.removeObject(forKey: mapStatePrefix + "mode")' in s
assert 'modeControl.selectedSegmentIndex = 0' in s
# renderRegion has one declaration and two call sites; all call sites must
# supply the playerCoordinates argument after the player-map-layer change.
assert s.count('playerCoordinates:') == 3, s.count('playerCoordinates:')
PY

grep -q 'private static let formatIdentifier = "mcbeeditor-nbt-json"' "$JSON"
grep -q 'private static let legacyFormatIdentifier = "blocktopograph-nbt-json"' "$JSON"
grep -q 'com.wzn.mcbeeditor.nbt-tag' "$CLIPBOARD"
grep -q 'com.wzn.blocktopograph.nbt-tag' "$CLIPBOARD"

# Old name is allowed only in explicit backward-compatibility constants and the upstream source URL.
while IFS= read -r line; do
  case "$line" in
    *legacyFormatIdentifier*|*legacyTagPasteboardType*|*legacyBatchTagPasteboardType*|*github.com/oO0oO0oO0o0o00/blocktopograph*|*test_mcbeeditor_map_player_rename.sh*) ;;
    *) echo "unexpected stale product field: $line" >&2; exit 1 ;;
  esac
done < <(grep -RIn --exclude-dir=leveldb-mcpe -E 'Blocktopograph|blocktopograph|BLOCKTOPOGRAPH' "$ROOT/Sources" "$ROOT/Resources" "$ROOT/project.yml" "$ROOT/.github" "$ROOT/Scripts" "$ROOT/Tests" || true)

swiftc -parse "$MAP" "$PLAYER" "$JSON" "$CLIPBOARD"
echo 'MCBEEditor rename, player map layer and session-only render mode checks passed'
