#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LC_ALL=C

require_fixed() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if ! grep -Fq -- "$needle" "$ROOT/$file"; then
    printf 'NBT/cross-section regression failed: %s\n  file: %s\n  missing: %s\n' "$message" "$file" "$needle" >&2
    exit 1
  fi
}

forbid_fixed() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if grep -Fq -- "$needle" "$ROOT/$file"; then
    printf 'NBT/cross-section regression failed: %s\n  file: %s\n  forbidden: %s\n' "$message" "$file" "$needle" >&2
    exit 1
  fi
}

# NBT hierarchy: the icon and text must share one horizontally scrollable
# surface, and trailing deletion must only become available after hidden
# content has been revealed.
require_fixed 'private final class NBTTreeHorizontalScrollView: UIScrollView' 'Sources/UI/NBTTreeCell.swift' 'tree rows must use a horizontal scroll surface'
require_fixed 'let iconX = contentLeading + CGFloat(depth) * indentationWidth' 'Sources/UI/NBTTreeCell.swift' 'NBT icon must move with hierarchy depth'
require_fixed 'let textX = iconX + iconSize.width + 8' 'Sources/UI/NBTTreeCell.swift' 'NBT text must remain attached to the shifted icon'
require_fixed 'contentOffset.x >= maximumOffset - 1' 'Sources/UI/NBTTreeCell.swift' 'scroll view must detect when hidden row content is fully revealed'
require_fixed 'velocity.x < 0' 'Sources/UI/NBTTreeCell.swift' 'only a new left swipe at the end should be handed to UITableView'
require_fixed 'cell.canRevealMoreHorizontally' 'Sources/UI/NBTTreeViewController.swift' 'world NBT delete swipe must wait for horizontal reveal'
require_fixed 'case .end:' 'Sources/UI/NBTTreeCell.swift' 'hierarchy guide must have an L-shaped terminal segment'
require_fixed 'path.addLine(to: CGPoint(x: currentIconCenterX - 10, y: iconCenterY))' 'Sources/UI/NBTTreeCell.swift' 'L tail must point at the last child icon'
require_fixed 'NBTTreeHierarchyGuide.lines(' 'Sources/UI/MapBlockDetailPanelView.swift' 'map block NBT must use the common hierarchy guide'
require_fixed 'NBTTreeHierarchyGuide.lines(' 'Sources/UI/PlayerNBTEditorViewController.swift' 'player NBT must use the common hierarchy guide'
require_fixed 'NBTTreeHierarchyGuide.lines(' 'Sources/UI/WorldObjectNBTEditorViewController.swift' 'entity/object NBT must use the common hierarchy guide'
forbid_fixed 'cell.indentationLevel = searchQuery.isEmpty ? node.depth : 0' 'Sources/UI/NBTTreeViewController.swift' 'legacy text-only indentation must not return to world NBT rows'

# Map X/Y/Z rendering controls and section behavior.
require_fixed 'private let sliceAxisControl = UISegmentedControl(items: MapSliceAxis.allCases.map(\.displayName))' 'Sources/UI/WorldMapViewController.swift' 'map must expose X/Y/Z render axis selector'
require_fixed 'sliceAxisControl.selectedSegmentIndex = MapSliceAxis.y.rawValue' 'Sources/UI/WorldMapViewController.swift' 'Y must remain the default render axis'
require_fixed 'yField.text = "63"' 'Sources/UI/WorldMapViewController.swift' 'vertical slice center Y must default to 63'
require_fixed 'chunkSelectionSwitch.isEnabled = !verticalSlice' 'Sources/UI/WorldMapViewController.swift' 'chunk selection must be disabled in X/Z sections'
require_fixed 'gridOptionTitleLabel?.text = verticalSlice ? "子区块网格" : "区块网格"' 'Sources/UI/WorldMapViewController.swift' 'grid label must switch to subchunk grid in X/Z sections'
require_fixed 'title = "选择\(result.axis.displayName)轴方块"' 'Sources/UI/BlockAxisPickerViewController.swift' 'X/Z taps must open the corresponding axis block picker'
require_fixed 'for coordinate in stride(from: upper, through: cappedLower, by: -1)' 'Sources/Chunk/BedrockCrossSection.swift' 'axis picker must list positive/high coordinates above negative/low coordinates'
require_fixed 'let y = maximumY - Int64(min(side - 1, row * sampleStride))' 'Sources/Chunk/BedrockCrossSection.swift' 'cross-section screen top must represent positive/high Y'
require_fixed 'drawSubChunkGrid: Bool' 'Sources/Chunk/BedrockCrossSection.swift' 'X/Z section renderer must support subchunk grid drawing'
require_fixed 'lineDashPattern = [8, 5]' 'Sources/UI/WorldMapViewController.swift' 'build-height overlay must be dashed'
require_fixed 'strokeColor = UIColor.systemRed.cgColor' 'Sources/UI/WorldMapViewController.swift' 'build-height overlay must be red'
require_fixed 'private var showBuildHeightLimits = true' 'Sources/UI/WorldMapViewController.swift' 'build-height limits must default to visible'
require_fixed 'UIAlertAction(title: heightLimitTitle' 'Sources/UI/WorldMapViewController.swift' 'X/Z object-layer menu must expose build-height limit visibility'

printf 'NBT tree horizontal reveal / hierarchy guide and X-Y-Z cross-section regression checks passed\n'
