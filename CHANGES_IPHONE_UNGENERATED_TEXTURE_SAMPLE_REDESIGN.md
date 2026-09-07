# CHANGES_IPHONE_UNGENERATED_TEXTURE_SAMPLE_REDESIGN

本次根据用户提供的 2×2 区块示意图，重新设计了“未生成区块”的纹理，并顺手清理了相应绘制代码。

## 1. 按样例重做未生成区块纹理
- 每个未生成区块现在固定绘制 **3 条灰色斜线**：
  1. 一条从左上到右下，贯穿整个区块。
  2. 一条从上边中点到右边中点。
  3. 一条从左边中点到下边中点。
- 这样四个相邻区块拼在一起时，整体视觉与用户给出的示意图保持一致。

## 2. 降低锯齿感
- 改用更规整的几何绘制方式，不再依赖上一版的“区块外延长线 + 裁切”方案。
- 对绘制矩形先做 `integral` 对齐，减少半像素坐标带来的毛边。
- 线条端点改为 `.butt`，避免上一版线帽在边缘处产生额外模糊或发虚。
- 统一在同一路径中绘制 3 条线，降低重复状态切换带来的不稳定效果。

## 3. 代码结构优化
- 保留统一的 `drawUngeneratedChunkPlaceholder(...)` 入口。
- `drawUngeneratedChunkTexture(...)` 内部逻辑简化为固定 3 条线的直接绘制，更容易维护，也更符合需求。
- 去除了上一版中已不再需要的偏移计算与延长线参数，使代码更直观。

## 4. 回归检查
- `WorldMapViewController.swift` 已通过 `swiftc -parse` 语法检查。
- `Scripts/test_iphone_layout_legacy_block_link.sh` 已通过。
