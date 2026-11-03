# Drop 4 Catalog Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans; steps use checkbox syntax.

**Goal:** 同步第 4 次小更新的基岩版 ID、命令可用性与地图配色。
**Architecture:** 现有主表增量更新，保留稳定快照并添加独立预览证据；新版数字方块与旧版转换目录分开。
**Tech Stack:** Swift、C#/.NET 10、Python 审计与共享 JSON。
**Spec:** ../specs/2026-10-28-drop4-catalog-design.md

## Global Constraints

版本 1.0.0；iOS 13；保留 kill 范围功能；旧版 0–255 方块映射不变；不猜测未公布的 Bedrock 数字 ID。

## Review Focus

实体完整 ID 与短 ID 一致；freezing 名称／数字 NBT／ALL 同步；群系列表与颜色跨平台一致；新方块不能写入旧版数值区块；材质覆盖仍优先，冰晶／冰锥／脆冰不落入错误颜色。

### Task 1: 数据与命令

**Files:** 双端 BedrockDataValueCatalog、BedrockEntityCatalog、BedrockBiomeCatalog、EntityActionCommand，Scripts/test_catalog_sync.py，Docs/CatalogSync 中独立预览引用与来源；现有 ID 对照 UI。
**Interfaces:** 现有 entry/search API；新增只读 modernBlocks 列表，与 legacyBlocks 分离。

- [x] 保存可复核的新增事实、来源和版本界限。
- [x] 为新增实体、群系、状态效果以及已确认新版方块的搜索／桥接／命令执行编写回归并复现旧版缺失。
- [x] 更新生产表、实体数值桥与 effect 消费者，接入新版方块列表，不更改旧版转换规则。
- [x] 运行目录同步及两端命令回归。

### Task 2: 颜色与交付

**Files:** 双端 BedrockBlockMapColorCatalog、BedrockBiomeCatalog、配色回归与数据说明／固定 ReadMe。
**Interfaces:** 复用现有地图颜色查询；明确冰系材质，不改变 Colors.txt 覆盖机制。

- [x] 为新冰系方块、生物群系和既有颜色保留编写行为回归，确认旧版缺失。
- [x] 增加双端一致的材质颜色，同步来源、测试快照、帮助和新内容说明。
- [x] 完整运行 Swift 与 C# 核心、目录和 CLI 测试；独立复核后打包全部源码。
