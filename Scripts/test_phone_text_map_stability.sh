#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"
TEXT="$ROOT/Sources/UI/CompactTextSupport.swift"
APP="$ROOT/Sources/App/AppDelegate.swift"

test -f "$TEXT"
grep -q 'adjustsFontSizeToFitWidth = true' "$TEXT"
grep -q 'cell.mcbe_enableCompactText()' "$ROOT/Sources/UI/ChunkListViewController.swift"
grep -q 'UISegmentedControl.appearance().setTitleTextAttributes' "$APP"

grep -q 'private var isMapInteractionActive' "$MAP"
grep -q 'cancelInFlightRenderForUserInteraction()' "$MAP"
grep -q 'scrollView.bounces = false' "$MAP"
grep -q 'scrollView.bouncesZoom = false' "$MAP"
grep -q 'prepareZoomRangeForUserGesture()' "$MAP"

# Mid-gesture scroll callbacks may update overlays, but must not start render work.
python3 - "$MAP" <<'PY'
from pathlib import Path
import re, sys
s=Path(sys.argv[1]).read_text()
m=re.search(r'func scrollViewDidScroll\([^\{]+\) \{(.*?)\n  \}', s, re.S)
assert m, 'scrollViewDidScroll missing'
assert 'scheduleAutoRender' not in m.group(1), 'mid-scroll auto render still present'
m=re.search(r'func scrollViewDidZoom\([^\{]+\) \{(.*?)\n  \}', s, re.S)
assert m, 'scrollViewDidZoom missing'
assert 'expandZoomRangeIfNeeded' not in m.group(1), 'zoom bounds still mutate every pinch frame'
assert 'scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating' in s
PY

echo 'phone text + map stability checks passed'
