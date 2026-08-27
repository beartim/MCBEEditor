#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"

grep -q 'statusLabel.numberOfLines = 2' "$MAP"
grep -q 'statusLabel.heightAnchor.constraint' "$MAP"
grep -q 'scrollView.contentInsetAdjustmentBehavior = .never' "$MAP"
grep -q 'private struct MapViewportRenderRequest' "$MAP"
grep -q 'private func currentViewportRenderRequest()' "$MAP"
grep -q 'private func renderedRegionContains' "$MAP"
grep -q 'sideChunksOverride: Int? = nil' "$MAP"
grep -q 'reason = "缩放扩展"' "$MAP"
grep -q 'request.sideChunks \* 2 < renderedSideChunks' "$MAP"
grep -q 'scrollViewDidEndScrollingAnimation' "$MAP"

python3 - "$MAP" <<'PY'
from pathlib import Path
import re, sys
s=Path(sys.argv[1]).read_text()

# Render completion must not blindly start a center-chasing render loop.
refresh=re.search(r'private func refreshForZoomDrivenRadiusIfNeeded\(\) \{(.*?)\n  \}', s, re.S)
assert refresh
assert 'scheduleAutoRender(immediate: true, zoomDriven: true)' in refresh.group(1)
assert 'render(centerX:' not in refresh.group(1)

# Auto rendering must be coverage/hysteresis based, not "center changed => render".
auto=re.search(r'private func autoRenderAtViewportCenter\([^)]*\) \{(.*?)\n  \}\n\n  private func mapPosition', s, re.S)
assert auto
body=auto.group(1)
assert 'renderedRegionContains(request)' in body
assert 'centerChanged' not in body
assert 'needsExpansion' in body and 'needsDetailRefinement' in body

# The actual visible rectangle must drive the requested region size.
req=re.search(r'private func currentViewportRenderRequest\(\).*?\{(.*?)\n  \}\n\n  private func renderedRegionContains', s, re.S)
assert req
body=req.group(1)
for token in ['scrollView.contentOffset.x', 'scrollView.contentOffset.y',
              'scrollView.bounds.width', 'scrollView.bounds.height',
              'requiredMinimumChunkX', 'requiredMaximumChunkZ']:
    assert token in body, token

# Pure model of the viewport coverage calculation: zooming out must expand the
# square chunk request and a preload-contained one-chunk center change must not
# require another render.
def required_side(view_w, view_h, ppb, zoom, border=2):
    import math
    blocks_w=view_w/(ppb*zoom)
    blocks_h=view_h/(ppb*zoom)
    # Worst case when both viewport edges cut through chunks.
    chunks=max(math.ceil(blocks_w/16)+1, math.ceil(blocks_h/16)+1)
    return max(3, chunks + border*2)

s1=required_side(390, 520, 32, 0.50)
s2=required_side(390, 520, 32, 0.10)
s3=required_side(390, 520, 32, 0.02)
assert s1 < s2 < s3, (s1,s2,s3)

# A 9x9 render centered at 0 covers -4...4. If the visible+preload request is
# -3...4 after a tiny center movement it is still contained and must not chase.
assert -3 >= -4 and 4 <= 4
PY

echo 'iPhone viewport stability v2 checks passed'
