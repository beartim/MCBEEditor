# Entity Target Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 扩展 entity 查询玩家与目标，返回类型、维度、实际坐标和完整 MCBE-SNBT。

**Architecture:** 在现有 query request 中增加目标，扫描普通实体与玩家记录后用相同目标/维度/范围条件筛选；不调用写命令的去重与无匹配报错流程。

**Tech Stack:** Swift 6 / iOS 13，C# .NET 10，Python 共享用例与文件校验。

**Spec:** `docs/superpowers/specs/2026-10-29-entity-target-query-design.md`

## Global Constraints

- 版本 1.0.0，iOS 最低 13.0。
- 查询只读，不修改原 NBT、数据库或 level.dat；排除方块实体，不按 UniqueID 合并独立记录。
- 单个数字按非零 Int64 UniqueID；数值维度在 @e 后显式填写，范围坐标保持成组。
- 其他命令、ID/颜色表、旧存档转换与 kill 保持。
- 无 Git 仓库，在独立 entity-work 解压目录工作，以原 ZIP 为比较基线。

## Review Focus

- 负数、Int64 极值和超 2^53 的 UniqueID，不应误判为维度或丢失精度。
- 玩家缺少 Pos 时仍有可查询的维度，范围必须排除而全局保留。
- 同 UniqueID 的不同普通实体和玩家记录都应返回，不能借用写入去重。
- 玩家与普通实体真实坐标/维度应优先，digp 所属维度与 NBT 不一致不能漏选。
- 输出坐标/维度一行展示，NBT 不增删标签且完整往返；CLI 新格式保持只读预检。

### Task 1: 查询类型、解析与执行

**Files:** WorldCommand.swift、WorldCommandExecutor.swift、PlayerNBTStore.swift；EntityQueryCommand.cs、PlayerNbtStore.cs；新增或扩展两端 EntityQuery 测试。

**Interfaces:** 查询请求增加 target，保留维度与范围；PlayerStore 增加独立 CurrentDimension 读取；使用既有 MCBE-SNBT formatter。

- [x] 先写目标/玩家/输出及只读失败测试，运行旧解析器确认失败。
- [x] 实现目标组合、数字优先与玩家合并；边界/无位置/去重规则依 spec。
- [x] 运行两端目标回归，更新旧输出和不含玩家断言为新规范。

### Task 2: 四端说明、共享用例与 CLI

**Files:** command-inventory、parser-cases、两份 help、四个命令 store 与快照、COMMAND_SYNTAX.md、README、CLI/README、CLI entity 回归。

**Interfaces:** 消费 Task 1 的语法与输出；保留 CLI query request 为只读。

- [x] 共享用例补齐目标、数字歧义、额外参数/坐标缺项拒绝，覆盖四个选择器/identifier/UniqueID。
- [x] 更新所有当前命令说明与实体输出示例，历史说明注明旧格式。
- [x] 验证 CLI 真实 plan 及固定 ReadMe 实际读写。

### Task 3: 全量验证、审查与交付

**Files:** Docs/EntityTargetQuery/VALIDATION.md 与日志、源码 ZIP。

- [x] 运行 Swift/C# 完整核心回归、CLI smoke、帮助 audit、CLI/WPF 构建。
- [x] 按 requesting-code-review 执行一次独立最终审查，重要发现先以测试复现再修复。
- [x] 验证 ZIP CRC、原路径和前轮功能保留，保存同一源码文件的新版本。
