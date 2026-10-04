#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mcbe-snbt-test.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT
sources=(
  "$ROOT/Sources/Support/Errors.swift"
  "$ROOT/Sources/Support/Hex.swift"
  "$ROOT/Sources/NBT/NBTTypes.swift"
  "$ROOT/Sources/NBT/BinaryCursor.swift"
  "$ROOT/Sources/NBT/BedrockNBTCodec.swift"
  "$ROOT/Sources/NBT/MCBESNBTCodec.swift"
)
swiftc -parse-as-library "${sources[@]}" "$ROOT/Scripts/Tests/MCBESNBTTests.swift" -o "$TMP/mcbe-snbt-tests"
"$TMP/mcbe-snbt-tests"
swiftc -parse-as-library "${sources[@]}" "$ROOT/Scripts/Tests/MCBESNBTProbe.swift" -o "$TMP/mcbe-snbt-probe"
python3 "$ROOT/CLI/Tests/mcbe_snbt_smoke.py" --backend probe -- "$TMP/mcbe-snbt-probe"
