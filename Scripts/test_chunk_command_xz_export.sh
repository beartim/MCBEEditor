#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
require() { grep -qF "$1" "$2" || { echo "missing: $1 in $2" >&2; exit 1; }; }
require '"chunk"' Sources/Command/WorldCommand.swift
require 'case "chunk":' Sources/Command/WorldCommand.swift
require 'case .chunk(let operation):' Sources/Command/WorldCommandExecutor.swift
require 'style: .block' Sources/Command/WorldCommandExecutor.swift
require 'allowedDimensions: [Int32] = dimension.map { [$0] } ?? [0, 1, 2]' Sources/Command/WorldCommandExecutor.swift
require 'store.clearChunk(position)' Sources/Command/WorldCommandExecutor.swift
require 'store.regenerateChunk(position)' Sources/Command/WorldCommandExecutor.swift
require 'ungeneratedDisplay: verticalSlice ? .air : .transparent' Sources/UI/WorldMapViewController.swift
require 'projectionDepth: mode == .xray ? 129 : 128' Sources/UI/WorldMapViewController.swift
require 'preferHighlightedOre: self.currentMode == .xray' Sources/UI/WorldMapViewController.swift
require 'BedrockBlockIdentifier.isHighlightedOre(block.primaryState.name)' Sources/UI/BlockAxisPickerViewController.swift
require 'x: x - gridLineWidth * 0.5' Sources/Chunk/BedrockCrossSection.swift
require 'y: y - gridLineWidth * 0.5' Sources/Chunk/BedrockCrossSection.swift
swiftc -parse Sources/Command/WorldCommand.swift Sources/Command/WorldCommandExecutor.swift
swiftc -parse Sources/Chunk/BedrockCrossSection.swift Sources/UI/BlockAxisPickerViewController.swift Sources/UI/WorldMapViewController.swift
printf 'chunk command / XZ export / centered SubChunk grid regression checks passed\n'
