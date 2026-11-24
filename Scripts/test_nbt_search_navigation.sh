#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
for controller in NBTSearchTreeViewController NBTRootSearchViewController; do
  {
    printf '%s\n' 'import Foundation' '#if canImport(CoreGraphics)' 'import CoreGraphics' '#endif'
    sed '/^import UIKit$/d' "$ROOT/Sources/UI/$controller.swift"
  } > "$TEMP/$controller.swift"
done
swiftc -swift-version 5 \
  "$ROOT/Sources/Support/Errors.swift" "$ROOT/Sources/NBT/NBTTypes.swift" \
  "$ROOT/Sources/NBT/NBTTreeMutation.swift" "$ROOT/Sources/UI/NBTNode.swift" \
  "$TEMP/NBTSearchTreeViewController.swift" "$TEMP/NBTRootSearchViewController.swift" \
  "$ROOT/Scripts/Tests/NBTSearchNavigationTests.swift" -o "$TEMP/search-navigation"
"$TEMP/search-navigation"
