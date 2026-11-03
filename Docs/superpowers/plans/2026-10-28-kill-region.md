# kill 范围目标 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan. Steps use checkbox syntax.

**Goal:** 实现用户示例及创造模式开关语义，保持双端一致。
**Architecture:** 给现有目标枚举增加维度＋实体范围；kill 解析该目标，目标解析按实际坐标筛选后复用原 kill 执行逻辑。
**Tech Stack:** Swift / C# .NET 10 / 现有内存数据库测试。
**Spec:** ../specs/2026-10-28-kill-region-design.md

## Global Constraints

版本号不变；最低 iOS 13；保留旧 kill 语法；末尾必须显式 0 或 1；不修改其他命令语法。

## Review Focus

坐标边界及反向角点；其他维度／区域外记录；非创造模式在 0 时仍清零；相同 UniqueID 的不同记录；无 Pos／空选择与旧选择器兼容。均由下列行为测试覆盖。

### Task 1: 双端范围目标与 kill 行为

**Files:** WorldCommand.swift、WorldCommandExecutor.swift、TargetingCommand.cs、EntityActionCommand.cs、BedrockWorldObjectNBTStore.swift；新增 KillRegionTests.cs、KillRegionRegression.swift，接入现有测试入口。
**Interfaces:** 保留 `.kill(target:killCreativePlayers:)` 与 KillEntityActionCommandRequest；新增范围 CommandTarget / TargetingCommandTarget。

- [x] 写测试：用户示例 0／1、反向角点、非创造模式／创造模式、跨维度、旧连续记录与现代 actor、重复 ID、缺失位置、非法输入和旧目标。
- [x] 运行 C# `dotnet run --project Windows/MCBEEditor.Core.SelfTest -- --kill-region`，预期新语法解析失败；Swift 运行集成测试入口验证同样缺失。
- [x] 修改目标模型、解析及筛选，保留原批量删除与生命值处理。
- [x] 运行双端定向回归与现有完整核心测试；新增回归必须通过，记录环境限制或原有失败。

### Task 2: 帮助、核对与交付

**Files:** 两端帮助、四份 SharedCommandStore、四份固定 ReadMe、CLI/Shared/*.json、README.md、CHANGES_KILL_REGION.md。
**Interfaces:** 全部帮助描述同一语法和开关语义。

- [x] 同步语法、示例、边界、维度与创造模式说明，补充共享解析样例。
- [x] 运行 CLI 源码检查与解析样例；检查最终修改和 ZIP 完整性。
- [x] 交付完整源码 ZIP；本目录来自附件解压，不创建远端分支或推送。

独立复核补充：Swift 连续 actorprefix 部分删除必须保留 digp；补充双端回归，验证保留原始 NBT、索引和后续可见性，并验证最后一条删除后清理索引。新测试先复现失败再修改删除逻辑。
