# Command Syntax Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 统一 28 条命令的可省略参数、帮助与两端行为，同时保留完整旧语法。

**Architecture:** 在已有解析器中展开默认值；fill/setblock 使用各语言共享的层参数解析函数消除歧义；现有执行器不重构。共享 JSON 保持 GUI/CLI 语法回归同步。

**Tech Stack:** Swift 6 编译兼容现有 iOS 13 项目、C# .NET 10、Python 审计工具。

**Spec:** `docs/superpowers/specs/2026-10-29-command-syntax-design.md`

## Global Constraints

- 保留所有原本有效完整语法及语义，版本保持 1.0.0。
- 目标、维度、坐标不推断；0/1 严格，ALL 大写，NBT 原样。
- 不修改 ID/颜色目录、旧存档转换与 kill 执行逻辑。
- 无 Git 仓库；从已保存 ZIP 独立解压工作，原 ZIP 作为逐字节比较基线。

## Review Focus

- 多层方块、空 states 与尾部 NBT 模板之间的分界：至少测试两个相邻 NBT 参数及带空层的混合层。
- 省略参数不能把多余参数吞掉：测试所有扩展分支的超长输入。
- kill 数字 UniqueID 与维度 ID 的歧义：按完整参数数量选择，测试两种默认写法。
- ALL 不得误选名为 all 的对象或维度；测试名称保留与缺省查询。
- CLI 静态预检必须识别默认查询为只读；测试新查询别名与默认写命令。

### Task 1: 类型等价与解析实现

**Files:** C# Chunk 下 EntityAction/Block/StorageBiome/Environment/Dimension/Chunk/StructureTemplateCommand.cs；Swift WorldCommand.swift；新增 CommandSyntaxTests.cs、CommandSyntaxRegression.swift；两个核心运行入口。

**Interfaces:** 消费原解析器；返回既有 typed request/ParsedWorldCommand，不新增执行器分支。

- [x] 先写显式与省略参数的等价测试、歧义拒绝用例，运行确认旧解析器拒绝新默认写法。
- [x] 实现设计表中的默认值与大小写规则，逐项运行目标测试通过。
- [x] 将旧的“省略必错”用例改为相应默认值断言，保留全部数据写入回归。

### Task 2: 全命令说明和共享语法

**Files:** command-inventory.json、parser-cases.json、两端帮助、四份固定命令说明与四个写入常量；COMMAND_SYNTAX.md、README.md、CLI/README.md。

**Interfaces:** 消费 Task 1 的精确默认值；提供完整 28 命令审计表和实际生成的固定帮助。

- [x] 用共享用例覆盖默认写法、完整写法、半组坐标和额外参数，先在旧清单中确认新增规则缺失。
- [x] 同步帮助、快照、默认值和歧义说明；检查旧示例仍有效。
- [x] 运行 CLI smoke、固定 ReadMe 实际读写、源代码帮助一致性检查。

### Task 3: 完整验证与交付

**Files:** Docs/CommandSyntax/VALIDATION.md、日志、源码 ZIP。

**Interfaces:** 消费前两步最终结果；提供完整可下载源码。

- [x] 运行 Swift/C# 核心全回归、CLI 构建和相关 CLI 预检，处理实际失败。
- [x] 按 requesting-code-review 执行一次独立最终审查，重要问题以失败用例先复现再修复。
- [x] 检查 ZIP CRC、原文件路径保留、无构建产物、版本和前轮功能保留，然后保存同一源文件的新版本。
