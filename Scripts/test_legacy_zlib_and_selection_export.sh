#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/Sources/Bridge/BTLevelDBBridge.mm"
CHUNKS="$ROOT/Sources/Chunk/BedrockChunkStore.swift"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"
OPTIONS="$ROOT/Sources/UI/MapExportOptionsViewController.swift"

grep -q 'options\.compressors\[0\] = &zlib;' "$BRIDGE" || {
  echo 'error: LevelDB writes must prefer legacy-compatible zlib compression ID 2' >&2
  exit 1
}
grep -q 'options\.compressors\[1\] = &zlibRaw;' "$BRIDGE" || {
  echo 'error: raw-deflate decompressor must remain registered for modern worlds' >&2
  exit 1
}
! grep -q 'for y in Int8(0)\.\.\.Int8(7).*subChunkYs' "$CHUNKS" || {
  echo 'error: LegacyTerrain virtual slices must not be counted as physical SubChunk records' >&2
  exit 1
}
grep -q 'let hasLegacyTerrain: Bool' "$CHUNKS" || {
  echo 'error: chunk summary must expose physical LegacyTerrain presence' >&2
  exit 1
}
grep -q 'LegacyTerrain 1（8 虚拟切片）' "$CHUNKS" || {
  echo 'error: chunk list must label LegacyTerrain explicitly' >&2
  exit 1
}
grep -q 'case selectedRegion' "$OPTIONS" || {
  echo 'error: map export options are missing selected-region scope' >&2
  exit 1
}
grep -q 'hasSelectedRegion: isSelectionMode && selectedRegion != nil' "$MAP" || {
  echo 'error: selected-region map export must only be offered for an active selection' >&2
  exit 1
}
grep -q 'cropMapExportImage' "$MAP" || {
  echo 'error: selected-region export is missing exact block-boundary cropping' >&2
  exit 1
}

echo 'Legacy zlib write compatibility, physical chunk summary, and selection export checks passed'
