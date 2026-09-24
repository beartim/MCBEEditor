#!/usr/bin/env python3
"""Source wiring checks only; native behavior lives in test_map_projection_coordinates.sh."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
renderer = (root / "Sources/Chunk/BedrockCrossSection.swift").read_text()
picker = (root / "Sources/UI/WorldMapViewController.swift").read_text()
sample = renderer.split("func sample(horizontal:", 1)[1].split("func planeHasSubChunk", 1)[0]
assert "let planeX = axis == .x ? fixedX : horizontal" in sample
assert "let planeZ = axis == .z ? fixedZ : horizontal" in sample
assert "frontProjectionCoordinate" not in sample
assert "towardPositive: projectionDirection == .negativeToPositive" in renderer
assert "restrictToChunk: showUngeneratedSubChunks || transparentUngeneratedSubChunks" in renderer
picker = picker.split("private func showBlockAxisLine(", 1)[1].split("@objc private func toggleSelectionMode", 1)[0]
assert "depth: mode == .xray ? 129 : 128" in picker
assert "restrictToChunk: showUngeneratedChunks" in picker
assert "automaticSelectionMinimumCoordinate: automaticRange.lowerBound" in picker
assert "automaticSelectionMaximumCoordinate: automaticRange.upperBound" in picker
assert "preferHighlightedOre: mode == .xray" in picker
print("PASS: projection and picker source wiring (not native execution)")
