# MCBEEditor 整体检查与清理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 复核四个版本的功能接线及真实读写行为，修复确认的问题，删除有证据的无用生产代码。

**Architecture:** Swift 与 C# 共享核心分别服务 GUI/CLI。独立模块只读审查并行进行，主代理负责复现、修改及最终验证，避免共享文件冲突。

**Tech Stack:** Swift 5.10.1、.NET SDK 10.0.401、Mojang LevelDB 0.8.0a8、zlib 1.3.1、Python 检查脚本。

**Spec:** 当前用户指令“进行一次整体检查确保功能正常并无冗余代码”，以及 README.md、CLI/Docs/COMMAND_PARITY.md 中现有行为。

## Global Constraints

- iOS GUI、Apple/iOS CLI、Windows GUI、Windows CLI；版本 1.0.0，最低 iOS 13.0。
- 任意登记维度或 Int32 ID；保留此前维度命令和地图菜单/编译修复。
- setblock/fill 末尾方块实体参数必填；模板根 x/y/z 可省略或忽略，写入为实际目标位置的唯一小写 Int 坐标；嵌套标签保持。
- MCBE-SNBT 空未指定类型 List 使用 `'List'''"Items"=""`。
- Commands/Textures ReadMe 为固定文本，启动恢复；用户 Command.txt、源世界保护及已授权 CLI 保存模式保持。
- 不进行平台重写或整文件拆分；仅删除确认没有生产/动态/测试入口的代码，不因短文本引用数少而删除生命周期入口。

## Review Focus

- 命令参数有效但运行失败：核对 parser、执行路由和最终数据库内容。
- 自定义维度、负坐标及反向跨区块：核对记录键和每个目标坐标。
- NBT 格式/压缩/连续根：核对导出重开后精确值、标签类型及完整性。
- GUI 点击和编辑后刷新：核对 selector/XAML 入口、实际几何函数、旧对象引用。
- 保存失败/只读查询/启动重置：核对源文件快照、恢复结果和固定文本，不掩盖错误。

### Task 1: 建立检查基线

**Files:** 只读现有 Sources、Windows、CLI、Scripts 与 Tests；新建本计划和 Docs/OverallAudit/VALIDATION.md。

- [x] 核对最新完整包所有 860 个文件与基线 SHA256；确认独立工作区。
- [x] 使用现有官方工具链或恢复同版本；运行 Swift/C# 全核心、源码/构建/固定 ReadMe 检查并保存真实结果。
- [x] 建立 28 类命令 parser、真实 LevelDB CLI、GUI 交叉编译和平台限制的验证矩阵。

### Task 2: 修复与清理

**Files:** 仅修改独立审查和复现明确指出的生产文件及对应现有测试；确切文件在问题确认时补入检查记录。

- [x] 汇总命令、GUI、格式/文件生命周期审查，逐项确认实际影响和调用路径。
- [x] 对功能缺陷先写行为回归并观察失败，再作最小修改，运行专项验证。
- [x] 对无用代码核对全项目引用及 selector/XAML/条件编译入口后删除；对逻辑重复保留唯一实现并用既有行为回归验证。
- [x] 不因风格、文件大小或单一引用计数清理正常代码；未确认候选写明保留理由。

### Task 3: 验证与交付

**Files:** Docs/OverallAudit/VALIDATION.md、REVIEW.md 和本轮日志；完整源码 ZIP。

- [x] 运行修改涉及的完整核心与 CLI 原生套件，确认 parser/help、存档保存重开、源完整性和固定 ReadMe。
- [x] 编译 Windows CLI 和 GUI；明确 iOS 真机、Apple 原生构建、游戏加载的可验证边界。
- [x] 审查最终差异，核对无误删和编译清单无遗漏；运行 git diff --check。
- [x] 验证 ZIP CRC、全部跟踪文件字节一致、所有原始文件保留（有意删除的无用源码例外）以及不含构建缓存；交付短名完整包。
