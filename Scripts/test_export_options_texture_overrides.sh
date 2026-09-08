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

# PNG naming: only the iOS-safe namespace_block.png form is accepted. The
# first underscore becomes the single namespace colon; literal-colon filenames
# are explicitly rejected.
require 'url.pathExtension.lowercased() == "png"' "$STORE"
require 'let stem = url.deletingPathExtension().lastPathComponent' "$STORE"
require 'guard !trimmed.isEmpty, !trimmed.contains(":"),' "$STORE"
require 'let underscore = trimmed.firstIndex(of: "_")' "$STORE"
require 'return BedrockBlockIdentifier.normalized("\(namespace):\(path)")' "$STORE"
require 'minecraft_bedrock.png -> minecraft:bedrock' "$STORE"
require 'minecraft_polished_blackstone.png -> minecraft:polished_blackstone' "$STORE"
require 'minecraft:bedrock.png）不受支持' "$STORE"

# colors.txt: colon-form block id + #RRGGBB. Invalid lines are skipped by the
# guards, duplicate assignment is sequential (last valid line wins), and text
# entries are merged after PNGs so text always has priority.
require 'private static let colorsFilename = "colors.txt"' "$STORE"
require 'let fields = trimmed.split(whereSeparator: { $0.isWhitespace })' "$STORE"
require 'guard fields.count == 2 else { return }' "$STORE"
require 'guard text.count == 7, text.first == "#" else { return nil }' "$STORE"
require 'result[BedrockBlockIdentifier.normalized(identifierText)] = color' "$STORE"
require 'if let textColors = parseColorsFile(at: colorsURL)' "$STORE"
require 'loaded[identifier] = color' "$STORE"
require 'colors.txt 有效条目 > 对应 PNG > MCBEEditor 内置方块颜色。' "$STORE"

# ReadMe is rewritten atomically every preparation/activation.
require 'private static let readMeFilename = "ReadMe.txt"' "$STORE"
require 'try writeReadMe(in: directory)' "$STORE"
require 'try Data(readMeText.utf8).write(to: url, options: .atomic)' "$STORE"

require 'BlockTextureOverrideStore.rgbHex(for: blockName)' "$RENDER"
require 'textures=\(BlockTextureOverrideStore.revision)' "$RENDER"

swiftc -parse "$OPTIONS" "$STORE" "$APP" "$SCENE" "$RENDER"
printf 'export UI / iOS-safe PNG names / colors.txt priority / ReadMe reset checks passed\n'
