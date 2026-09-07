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
require_fixed 'horizontalScrollView.isDirectionalLockEnabled = true' 'Sources/UI/NBTTreeCell.swift' 'horizontal NBT row scrolling must use the current UIScrollView directional-lock API'
require_fixed 'private lazy var rowTapGesture: UITapGestureRecognizer' 'Sources/UI/NBTTreeCell.swift' 'nested NBT scroll view must forward real taps back to the table editor'
require_fixed 'gesture.cancelsTouchesInView = true' 'Sources/UI/NBTTreeCell.swift' 'forwarded NBT taps must not also reach the table selection recognizer a second time'
require_fixed 'delegate.tableView?(tableView, didSelectRowAt: indexPath)' 'Sources/UI/NBTTreeCell.swift' 'single-tap NBT editing/expansion must be forwarded to the existing table delegate'
forbid_fixed 'horizontalScrollView.directionalLockEnabled = true' 'Sources/UI/NBTTreeCell.swift' 'deprecated pre-Swift-renaming UIScrollView directionalLockEnabled API must not return'
forbid_fixed 'private var indentationWidth:' 'Sources/UI/NBTTreeCell.swift' 'custom NBT indentation state must not shadow UITableViewCell.indentationWidth'
require_fixed 'private var treeIndentationStep: CGFloat = 18' 'Sources/UI/NBTTreeCell.swift' 'NBT tree indentation state must use a non-UIKit property name'
require_fixed 'let iconX = contentLeading + CGFloat(depth) * treeIndentationStep' 'Sources/UI/NBTTreeCell.swift' 'NBT icon must move with hierarchy depth'
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
require_fixed 'private var sliceCenterY: Int32 = 0' 'Sources/UI/WorldMapViewController.swift' 'Y top-down mode must start with render-center Y=0'
require_fixed 'sliceCenterY = 63' 'Sources/UI/WorldMapViewController.swift' 'X/Z section mode must reset render-center Y to 63'
require_fixed 'yField.text = "63"' 'Sources/UI/WorldMapViewController.swift' 'vertical slice center field must show Y=63'
require_fixed 'sliceCenterY = 0' 'Sources/UI/WorldMapViewController.swift' 'switching back to Y mode must reset render-center Y to 0'
require_fixed 'yField.text = "0"' 'Sources/UI/WorldMapViewController.swift' 'Y mode coordinate field must show Y=0'
require_fixed 'chunkSelectionSwitch.isEnabled = !verticalSlice' 'Sources/UI/WorldMapViewController.swift' 'chunk selection must be disabled in X/Z sections'
require_fixed 'gridOptionTitleLabel?.text = verticalSlice ? "子区块网格" : "区块网格"' 'Sources/UI/WorldMapViewController.swift' 'grid label must switch to subchunk grid in X/Z sections'
require_fixed 'title = "选择\(result.axis.displayName)轴方块"' 'Sources/UI/BlockAxisPickerViewController.swift' 'X/Z taps must open the corresponding axis block picker'
require_fixed 'for coordinate in stride(from: upper, through: cappedLower, by: -1)' 'Sources/Chunk/BedrockCrossSection.swift' 'axis picker must list positive/high coordinates above negative/low coordinates'
require_fixed 'let y = maximumY - Int64(min(verticalBlockCount - 1, row * sampleStride))' 'Sources/Chunk/BedrockCrossSection.swift' 'cross-section screen top must represent positive/high Y'
require_fixed 'drawSubChunkGrid: Bool' 'Sources/Chunk/BedrockCrossSection.swift' 'X/Z section renderer must support subchunk grid drawing'
require_fixed 'lineDashPattern = [8, 5]' 'Sources/UI/WorldMapViewController.swift' 'build-height overlay must be dashed'
require_fixed 'strokeColor = UIColor.systemRed.cgColor' 'Sources/UI/WorldMapViewController.swift' 'build-height overlay must be red'
require_fixed 'private var showBuildHeightLimits = true' 'Sources/UI/WorldMapViewController.swift' 'build-height limits must default to visible'
require_fixed 'UIAlertAction(title: heightLimitTitle' 'Sources/UI/WorldMapViewController.swift' 'X/Z object-layer menu must expose build-height limit visibility'
require_fixed 'private let crossSectionSelectionHalfRange: Int64 = 128' 'Sources/UI/WorldMapViewController.swift' 'X/Z read/selection working range must be centered at ±128 blocks'
require_fixed 'let minimumCoordinate = centerCoordinate - crossSectionSelectionHalfRange' 'Sources/UI/WorldMapViewController.swift' 'axis picker must begin 128 blocks below the current X/Z center'
require_fixed 'let maximumCoordinate = centerCoordinate + crossSectionSelectionHalfRange' 'Sources/UI/WorldMapViewController.swift' 'axis picker must end 128 blocks above the current X/Z center'
require_fixed 'selectedBlockLayer' 'Sources/UI/WorldMapViewController.swift' 'X/Z selected blocks must have their own overlay layer'
require_fixed 'key: "selected-block-blink"' 'Sources/UI/WorldMapViewController.swift' 'X/Z selected block overlay must blink'
require_fixed 'cached.biomeDocument?.biomeID(localX: localX, y: Int(y), localZ: localZ)' 'Sources/Chunk/BedrockCrossSection.swift' 'X/Z biome mode must read the biome at the actual section Y coordinate'
require_fixed '$0.contains(chunkX: value.chunkX, chunkZ: value.chunkZ)' 'Sources/Chunk/BedrockCrossSection.swift' 'X/Z ticking-area mode must read the sliced chunk ticking property'
require_fixed 'BedrockSlimeChunk.isSlimeChunk(x: value.chunkX, z: value.chunkZ)' 'Sources/Chunk/BedrockCrossSection.swift' 'X/Z slime mode must read the sliced chunk slime property'
require_fixed 'showUngeneratedSubChunks: Bool = false' 'Sources/Chunk/BedrockCrossSection.swift' 'vertical sections must track missing SubChunks independently from missing chunks'
require_fixed 'if showUngeneratedSubChunks, !value.hasSubChunk' 'Sources/Chunk/BedrockCrossSection.swift' 'missing-section texture must be based on SubChunk generation state'
require_fixed 'func rasterEdge(_ blockOffset: Int64) -> CGFloat' 'Sources/Chunk/BedrockCrossSection.swift' 'subchunk grid must snap to rendered block/sample cell edges'
require_fixed 'verticalSlice ? "子区块网格" : "区块网格"' 'Sources/UI/WorldMapViewController.swift' 'X/Z map option must identify its grid as a subchunk grid'
require_fixed 'ungeneratedTitle = showUngeneratedChunks ? "✓ 显示未生成子区块" : "显示未生成子区块"' 'Sources/UI/WorldMapViewController.swift' 'X/Z object layer must rename missing-chunk display to missing SubChunks'
require_fixed 'if !verticalSlice {' 'Sources/UI/WorldMapViewController.swift' 'village object action must be omitted in vertical-section mode'
require_fixed 'isCrossSection ? 4 : 5' 'Sources/UI/MapExportOptionsViewController.swift' 'X/Z export options must hide the village layer row'
require_fixed 'startCrossSectionImageExport(scope: scope, layers: layers)' 'Sources/UI/WorldMapViewController.swift' 'X/Z export must use the section-image exporter'
require_fixed 'intersectingSummaries = allSummaries.filter' 'Sources/UI/WorldMapViewController.swift' 'all-loaded X/Z export must traverse every loaded chunk intersecting the current section plane'
require_fixed 'horizontalRange: horizontalRange' 'Sources/UI/WorldMapViewController.swift' 'all-loaded section export must pass its full horizontal range explicitly instead of the ±128 picker range'
require_fixed 'verticalRange: verticalRange' 'Sources/UI/WorldMapViewController.swift' 'all-loaded section export must pass the full loaded SubChunk Y range explicitly'
require_fixed 'let currentHorizontalRange = renderedCrossHorizontalStart...(' 'Sources/UI/WorldMapViewController.swift' 'current X/Z export range must form a ClosedRange instead of a newline-terminated PartialRangeFrom'
require_fixed 'horizontalRange = MapCoordinate.blockOrigin(ofChunk: minimumChunk)...(' 'Sources/UI/WorldMapViewController.swift' 'all-loaded X/Z export range must form a ClosedRange instead of a newline-terminated PartialRangeFrom'
require_fixed '不受 ±128 选择范围限制' 'Sources/UI/MapExportOptionsViewController.swift' 'cross-section export UI must state that all-loaded export is not limited by the picker range'

printf 'NBT tree horizontal reveal / hierarchy guide and X-Y-Z cross-section regression checks passed\n'
