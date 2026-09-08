#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPTIONS="$ROOT/Sources/UI/MapExportOptionsViewController.swift"
STORE="$ROOT/Sources/Support/BlockTextureOverrideStore.swift"
APP="$ROOT/Sources/App/AppDelegate.swift"
SCENE="$ROOT/Sources/App/SceneDelegate.swift"
RENDER="$ROOT/Sources/Chunk/ChunkSurfaceRenderer.swift"
PLIST="$ROOT/Resources/Info.plist"
PROJECT="$ROOT/project.yml"

require() { grep -qF "$1" "$2" || { echo "missing: $1 in $2" >&2; exit 1; }; }
forbid() { ! grep -qF "$1" "$2" || { echo "forbidden: $1 in $2" >&2; exit 1; }; }

require 'private let control = UISegmentedControl(items: CrossSectionExportAngle.allCases.map(\.displayName))' "$OPTIONS"
require 'infinityButton.backgroundColor = .systemBlue' "$OPTIONS"
require 'infinityButton.layer.cornerRadius = 8' "$OPTIONS"
require 'minimumXInfinityButton' "$OPTIONS"
require 'minimumZInfinityButton' "$OPTIONS"
require 'maximumXInfinityButton' "$OPTIONS"
require 'maximumZInfinityButton' "$OPTIONS"
forbid 'tableView.reloadData()' "$OPTIONS"

require '<key>UIFileSharingEnabled</key>' "$PLIST"
require '<key>LSSupportsOpeningDocumentsInPlace</key>' "$PLIST"
require 'UIFileSharingEnabled: true' "$PROJECT"
require 'LSSupportsOpeningDocumentsInPlace: true' "$PROJECT"
require '.appendingPathComponent("Textures", isDirectory: true)' "$STORE"
require 'BlockTextureOverrideStore.prepareSharedDirectoryAndReload()' "$APP"
require 'BlockTextureOverrideStore.prepareSharedDirectoryAndReload()' "$SCENE"
require 'url.pathExtension.lowercased() == "png"' "$STORE"
require 'let stem = url.deletingPathExtension().lastPathComponent' "$STORE"
require 'BlockTextureOverrideStore.rgbHex(for: blockName)' "$RENDER"
require 'textures=\(BlockTextureOverrideStore.revision)' "$RENDER"

swiftc -parse "$OPTIONS" "$STORE" "$APP" "$SCENE" "$RENDER"
printf 'export sheet stability / six-way angle selector / shared texture override checks passed\n'
