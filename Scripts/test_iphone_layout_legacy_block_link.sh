#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP="$ROOT/Sources/UI/WorldMapViewController.swift"
PANEL="$ROOT/Sources/UI/MapBlockDetailPanelView.swift"
STORE="$ROOT/Sources/Chunk/BedrockSubChunkEditor.swift"

# Portrait iPhone controls use two compact centered rows, but keep the same
# complete labels as iPad.  Intrinsic-width groups prevent the large empty
# holes that equalCentering created in the previous layout.
grep -q 'coordinates = UIStackView(arrangedSubviews: \[displayOptions, renderControls\])' "$MAP"
grep -q 'coordinates.alignment = .center' "$MAP"
grep -q 'displayOptions.distribution = .fill' "$MAP"
grep -q 'renderControls.distribution = .fill' "$MAP"
grep -q 'displayOptions.spacing = compactPhone ? 14 : 14' "$MAP"
grep -q 'centerCoordinateTitle = label("渲染中心坐标")' "$MAP"
grep -q 'titleLabel.text = title' "$MAP"
grep -q 'titleLabel.setContentHuggingPriority(compactPhone ? .required : .defaultLow' "$MAP"
grep -q 'stack.setContentHuggingPriority(.required, for: .horizontal)' "$MAP"
! grep -q 'case "自动渲染": titleLabel.text = "自动"' "$MAP"
! grep -q 'case "区块网格": titleLabel.text = "网格"' "$MAP"
! grep -q 'case "选择区块": titleLabel.text = "区块"' "$MAP"
! grep -q 'centerCoordinateTitle.text = "中心"' "$MAP"
grep -q 'modeControl.setTitle("常加载"' "$MAP"
grep -q 'modeControl.setTitle("史莱姆"' "$MAP"
grep -q 'min(250, max(200, view.bounds.width \* 0.50))' "$MAP"

# The block panel should compact its controls but give the NBT tree more width.
grep -q 'jumpButton.setTitle(isCompactPhone ? "查看"' "$PANEL"
grep -q 'returnToSearchButton.setTitle(isCompactPhone ? "结果"' "$PANEL"
grep -q 'statusLabel.numberOfLines = isCompactPhone ? 2 : 0' "$PANEL"
grep -q 'tableView.isScrollEnabled = tableView.contentSize.height > tableView.bounds.height + 1' "$PANEL"

# Legacy numeric name/id are a protected linked pair. Editing one synchronizes
# the other, name shows a chain marker, and invalid mappings disable saving.
grep -q 'private func isProtectedLegacyPairNode' "$PANEL"
grep -q 'private func synchronizeLegacyPair' "$PANEL"
grep -q 'with: .int(Int32(entry.id))' "$PANEL"
grep -q 'with: .string(entry.identifier)' "$PANEL"
grep -q 'let linkedMarker = isLegacyTopLevelNode(node, named: "name") ? " 🔗" : ""' "$PANEL"
grep -q 'name 与 legacy_id 为绑定字段，不能重命名' "$PANEL"
grep -q 'name 与 legacy_id 为绑定字段，不能删除' "$PANEL"
grep -q 'saveButton.isEnabled = dirty && legacyError == nil' "$PANEL"
grep -q '旧版方块无法保存' "$PANEL"

# The persistence layer is a second line of defence: numeric SubChunks must
# never silently modernize because the linked textual name was changed.
! grep -q 'requestsModern = currentState.legacyID' "$STORE"
grep -q 'A name without a legacy numeric mapping is rejected' "$STORE"
grep -q '没有旧版数字 ID 对照，不能写入旧版数字 ID SubChunk' "$STORE"
grep -q '与 legacy_id .* 不匹配' "$STORE"
grep -q '旧版数字 ID 方块不能保存现代 states' "$STORE"

echo 'iPhone compact layout and linked legacy block ID checks passed'
