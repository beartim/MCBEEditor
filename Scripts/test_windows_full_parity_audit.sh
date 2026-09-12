#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/Windows/MCBEEditor.Desktop/MainWindow.xaml.cs"
XAML="$ROOT/Windows/MCBEEditor.Desktop/MainWindow.xaml"
REGION="$ROOT/Windows/MCBEEditor.Desktop/RegionAdvancedWindows.cs"
CHUNK_UI="$ROOT/Windows/MCBEEditor.Desktop/ChunkManagementWindows.cs"
CHUNK_CORE="$ROOT/Windows/MCBEEditor.Core/Chunk/BedrockChunkStore.cs"
REGION_CORE="$ROOT/Windows/MCBEEditor.Core/Chunk/BedrockRegionAdvancedStore.cs"
TICK_UI="$ROOT/Windows/MCBEEditor.Desktop/ChunkConvenienceWindows.cs"
TICK_CORE="$ROOT/Windows/MCBEEditor.Core/Chunk/EnvironmentCommand.cs"
NBT="$ROOT/Windows/MCBEEditor.Desktop/NbtEditorWindow.cs"
CREATE="$ROOT/Windows/MCBEEditor.Desktop/WorldObjectCreateWindow.cs"
WORLDINFO="$ROOT/Windows/MCBEEditor.Core/World/WorldInfoService.cs"
CSPROJ="$ROOT/Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj"

# Region-selection parity: ticking areas / copy / clear / regenerate plus chunk alignment.
grep -q '常加载区域编辑' "$REGION"
grep -q '复制区域内容到等大区域' "$REGION"
grep -q '清空区域' "$REGION"
grep -q '重新生成区域' "$REGION"
grep -q 'CopyRegion(' "$REGION_CORE"
grep -q 'ClearRegion(' "$CHUNK_CORE"
grep -q 'RegenerateRegion(' "$CHUNK_CORE"
grep -q 'AlignMapRegionToChunkBounds_Click' "$XAML"
grep -q 'AlignMapRegionToChunkBounds_Click' "$MAIN"

# Chunk UI parity, including true extended multi-selection and direct single-chunk tools.
grep -q 'SelectionMode = DataGridSelectionMode.Extended' "$XAML" || grep -q 'SelectionMode="Extended"' "$XAML"
grep -q 'CopyChunk' "$CHUNK_UI" "$MAIN"
grep -q 'HardcodedSpawners' "$CHUNK_UI"
grep -q '批量处理' "$CHUNK_UI"

# Ticking-area iOS batch actions are available and committed through one core save path.
grep -q '开启预加载' "$TICK_UI"
grep -q '关闭预加载' "$TICK_UI"
grep -q 'SetTickingAreaPreload' "$TICK_CORE"
grep -q 'DeleteTickingAreas' "$TICK_CORE"
grep -q 'SelectionMode=DataGridSelectionMode.Extended' "$TICK_UI"

# NBT/object convenience parity.
grep -q '复制路径和值' "$NBT"
grep -q '复制值' "$NBT"
grep -q '使用当前选中位置' "$CREATE"
grep -q '说明与许可证' "$XAML"
grep -q 'AGPL-3.0.txt' "$CSPROJ"

# C# pattern variables live in the containing block. Keep the visible-node iterator
# distinct from the `node` pattern variable above it (prevents CS0136).
python3 - "$NBT" <<'PY'
import sys
s=open(sys.argv[1], encoding='utf-8').read()
bad = 'if (includeCurrent && item.Tag is NbtEditorNode node) yield return node;\n        if (!item.IsExpanded) yield break;\n        foreach (var child in item.Items.OfType<TreeViewItem>())\n        foreach (var node in VisibleBatchNodes(child, includeCurrent: true))'
if bad in s:
    raise SystemExit('NbtEditorWindow VisibleBatchNodes still contains the CS0136 node shadowing regression')
if 'foreach (var visibleNode in VisibleBatchNodes(child, includeCurrent: true))' not in s:
    raise SystemExit('Expected VisibleBatchNodes iterator rename is missing')
print('NBT visible-node scope audit passed')
PY

# Confirm the porting-time compatibility wrappers/dead helpers removed in the audit stay gone.
! grep -R -q 'compatibility wrapper for early tests' "$ROOT/Windows"
! grep -R -q 'private static string StateSummary' "$ROOT/Windows"
! grep -R -q 'public BedrockSubChunk GetCurrent' "$ROOT/Windows/MCBEEditor.Core/Chunk/BedrockRegionBlockStore.cs"
! grep -R -q 'public static void ValidateImportDocument' "$ROOT/Windows"
! grep -R -q 'PlanCopyBlock' "$ROOT/Windows"

# World info must not silently manufacture zero counts when DB/file enumeration fails.
! grep -q 'catch { }' "$WORLDINFO"

# No XAML event handler may be missing from MainWindow code-behind.
python3 - "$XAML" "$MAIN" <<'PY'
import re, sys
xaml=open(sys.argv[1],encoding='utf-8').read(); cs=open(sys.argv[2],encoding='utf-8').read()
attrs=set(re.findall(r'\b(?:Click|SelectionChanged|Checked|Unchecked|Drop|DragOver|Closing|Loaded|PreviewMouseWheel|ScrollChanged|MouseLeftButtonDown|MouseMove|MouseLeftButtonUp|MouseRightButtonUp|MouseDoubleClick|TextChanged|KeyDown)="([A-Za-z_]\w*)"', xaml))
missing=[name for name in sorted(attrs) if not re.search(r'\b'+re.escape(name)+r'\s*\(', cs)]
if missing:
    raise SystemExit('Missing XAML handlers: '+', '.join(missing))
print(f'XAML handler audit passed: {len(attrs)} handlers')
PY

echo 'Windows full parity/dead-code audit regression checks passed'
