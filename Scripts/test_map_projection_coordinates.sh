#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v swiftc >/dev/null 2>&1; then
  echo 'SKIP: swiftc is required for projection coordinate behavior tests' >&2
  exit 77
fi
TMP_PROJECTION="$(mktemp -d)"
trap 'rm -rf "$TMP_PROJECTION"' EXIT
cat > "$TMP_PROJECTION/main.swift" <<'SWIFT'
import Foundation

// Inclusive projection lengths, both directions, negative chunk boundaries,
// ore depth, and integer extremes. These exercise the production helper.
precondition(MapCoordinate.projectionRange(plane: 5, depth: 128) == -122...5)
precondition(MapCoordinate.projectionRange(plane: 5, depth: 129) == -123...5)
precondition(MapCoordinate.projectionRange(plane: 5, depth: 128, towardPositive: true) == 5...132)
precondition(MapCoordinate.projectionRange(plane: 5, depth: 128, restrictToChunk: true) == 0...15)
precondition(MapCoordinate.projectionRange(plane: -1, depth: 128, restrictToChunk: true) == -16 ... -1)
precondition(MapCoordinate.projectionRange(plane: -16, depth: 129, towardPositive: true, restrictToChunk: true) == -16 ... -1)
precondition(MapCoordinate.projectionRange(plane: -17, depth: 128, restrictToChunk: true) == -32 ... -17)
precondition(MapCoordinate.projectionRange(plane: 5, depth: 0) == 5...5)
precondition(MapCoordinate.projectionRange(plane: Int64.min, depth: 128) == Int64.min...Int64.min)
precondition(MapCoordinate.projectionRange(plane: Int64.max, depth: 128, towardPositive: true) == Int64.max...Int64.max)
precondition(MapCoordinate.projectionRange(plane: Int64.min, depth: 128, restrictToChunk: true) == Int64.min...(Int64.min + 15))
precondition(MapCoordinate.projectionRange(plane: Int64.max, depth: 128, restrictToChunk: true) == (Int64.max - 15)...Int64.max)
print("PASS: 12 production projection coordinate cases")
SWIFT
swiftc "$ROOT/Sources/Chunk/MapCoordinate.swift" "$TMP_PROJECTION/main.swift" -o "$TMP_PROJECTION/projection-tests"
"$TMP_PROJECTION/projection-tests"
