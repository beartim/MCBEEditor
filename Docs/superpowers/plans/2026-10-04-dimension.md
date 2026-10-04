# 任意维度与 dimension 命令 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 采用主代理直接执行；每轮不超过 10 分钟。Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为全部版本增加 dimension query/empty/purge/add，并让所有世界命令接受任意存档维度名称或 Int32 ID。

**Architecture:** Swift/C# 各建立世界范围的维度登记服务，读取真实 DimensionNameIdTable 和数据键；命令通过 resolver 绑定当前世界。删除采用先规划后单次数据库批处理；CLI 使用纯内存预检状态支持同批 add 后操作新名称。

**Tech Stack:** Swift/Foundation、小端 NBT、Mojang LevelDB；C#/.NET 10、现有 IWorldDatabase；Python 3 只读样例审计。

**Spec:** docs/superpowers/specs/2026-10-04-dimension-design.md

**最终状态（2026-10-04）：** 八轮功能源码已全部完成。用户授权第 7、8 轮连续完成且不设时限，覆盖下述两轮时间上限；早期记录的编译待验证状态已由最终 Linux Swift/C# 验证补全。Apple 平台构建与 Windows 实机验收的边界见 Docs/DimensionStage8/VALIDATION.md。


## Global Constraints

- 每轮不超过 10 分钟，每轮交付独立完整源码压缩包；超时前停止扩展当轮范围并保存已验证检查点。
- 保留版本号 1.0.0、iOS 13 最低兼容要求和 Windows 导出 .mcworld 的保存方式。
- add 名称原样保存，支持无 namespace；原版名称固定到 overworld=0、nether=1、the_end=2。
- ID 为有符号 Int32；解除 0/1/2 白名单；缺失名称不猜 ID。
- empty 保留维度；purge 去除维度登记与全部可归属内容；不误删其它维度或玩家记录。
- 用户原始 mcworld 始终保留；破坏性验证仅在复制品/内存数据库进行。

## Review Focus

- 已登记零区块维度应可查询且重开后仍存在（轮2/3）。
- ID 43/44/47/118 与区块类型字节碰撞，必须读取到正确维度（轮2）。
- actor 被多维度共享引用、旧实体及非枚举区块标签，删除不能误删/遗漏（轮4/5）。
- 同命令文件 add→setblock→purge，预检不能提前拒绝新名称，失败不得部分修改（轮7）。
- purge 后玩家位置、村庄、tickingarea、WorldClocks 残留可能重新产生维度或悬空引用（轮5/8）。

---

### 第1轮：存档与代码审计（已完成，目标 8 分钟）

**Files:** 新增本计划、spec、Docs/DimensionStage1/*、Scripts/Dimension/probe_fixture.py、Tests/Fixtures/custom_dimensions.mcworld；运行时代码无改动。

**Interfaces:** 输出真实 registry 格式、四个维度、当前实现限制与样例校验报告，供第2轮使用。

- [x] 解包全部源码；检查真实维度表、独立根、区块/digp、level.dat。
- [x] 校验 CURRENT/MANIFEST 活跃表、内部序列号、墓碑和 CRC32C。
- [x] 定位 Swift/C# 解析限制与底层键歧义。
- [x] 生成设计、分轮计划、样例 JSON 与基线完整源码包。

### 第2轮：维度发现、区块键修复与 query（源码实现已交付；原生编译待验证，目标 8 分钟）

**Files:** Create Sources/World/DimensionStore.swift、Windows/MCBEEditor.Core/World/DimensionStore.cs、Windows/MCBEEditor.Core/Chunk/DimensionCommand.cs；Modify Sources/Chunk/BedrockDBKey.swift、Windows/MCBEEditor.Core/Chunk/BedrockDbKey.cs、Sources/Command/WorldCommand.swift、Sources/Command/WorldCommandExecutor.swift、Windows/MCBEEditor.Desktop/CommandHelpCatalog.cs、Windows/MCBEEditor.Desktop/RegionCommandWindow.cs、CLI/Windows/CliCommandParser.cs、CLI/Windows/CliWorldCommandExecutor.cs、CLI/Windows/CliCommandPolicy.cs、CLI/iOS/CliCommandPlan.swift。Test Scripts/Tests/DimensionTests.swift、Windows/MCBEEditor.Core.SelfTest/DimensionTests.cs。

**Interfaces:** Swift DimensionRecord(name: String, id: Int32)、DimensionStore(database: MojangLevelDB).snapshot() throws -> [DimensionRecord]；C# DimensionRecord(string Name, int Id)、DimensionStore(IWorldDatabase).Snapshot() -> IReadOnlyList<DimensionRecord>。无名数据维度记录 Name 为十进制 ID 字符串。

- [ ] 写测试：sampleIDs == [0,1000,1001,1002]；无 Nether/End；登记的零区块维度保留；长键 ID 43/44/47/118 均按长格式解析。
- [ ] 执行测试确认缺少 DimensionStore 的失败；实现读取表/根/数据合并，并按完整键长度修复两端 BedrockDBKey。
- [ ] 增加 dimension query 到所有路由、只读策略与帮助；暂不暴露未实现的写入子命令。
- [ ] 验证 query 不更改数据库；输出整包和第2轮状态。

### 第3轮：dimension add（源码实现已交付；原生编译待验证，目标 8 分钟）

**Files:** Modify 两端 DimensionStore、DimensionCommand/WorldCommand 解析与执行；Test 两端 DimensionTests。

**Interfaces:** Swift add(name: String, id: Int32) throws；C# Add(string name, int id)；将登记表与独立维度根一次 ApplyBatch 持久化。

- [ ] 写失败测试：add bear 1000 的 entries 与数据库根正确；关闭重开仍可 query；缺失的三原版维度按 canonical ID 添加。
- [ ] 覆盖重复名、重复ID、Int32 溢出、非法/纯数字名称、全局数据库键冲突；逐例断言失败前后全库字节相同。
- [ ] 实现 add，复用现有 NBT codec，不重新实现二进制序列化；保留已有未知 NBT 标签。
- [ ] 验证并交付完整第3轮源码包。

### 第4轮：dimension empty（目标 8 分钟）

**Files:** Modify 两端 DimensionStore；复用 Sources/World/TickingAreaStore.swift、Sources/World/VillageNBTStore.swift、Sources/Entity/BedrockWorldObjectNBTStore.swift 的数据格式；C# 对应 WorldToolStores/BedrockWorldObjectNbtStore；Test 两端 DimensionTests。

**Interfaces:** Swift empty(id: Int32) throws -> DimensionMutationSummary；C# Empty(int id) -> DimensionMutationSummary。Summary 包含 deletedKeyCount、removedActorCount、affectedPlayerCount。

- [ ] 写失败测试：目标清空后区块/digp/实体/方块实体/limbo/维度 tickingarea/村庄为零；registry 和根保留；其它维度所有字节相同。
- [ ] 增加共享 actor 引用、未知合法区块标签、未生成区块、旧实体与无内容维度用例。
- [ ] 实现统一删除计划，正确匹配完整维度 ID；原子提交删除/根更新。
- [ ] 在样例复制品执行 empty 1001，再 query 验证仍有 1001；交付第4轮整包。

### 第5轮：dimension purge（目标 8 分钟）

**Files:** Modify 两端 DimensionStore；必要时修改玩家/WorldClocks/旧元数据引用处理；Test 两端 DimensionTests。

**Interfaces:** Swift purge(id: Int32) throws -> DimensionMutationSummary；C# Purge(int id) -> DimensionMutationSummary；复用第4轮内容删除计划。

- [ ] 写失败测试：purge 1001 后 registry/root/chunks/digp 均无 1001；再次 query 和重开均不出现；add 同名同ID可成功。
- [ ] 覆盖缺失目标、仅登记无区块目标、原版维度、共享actor、含玩家当前位置/重生引用、WorldClocks 及最后一个维度。
- [ ] 实现登记删除与引用处理，先完成全部校验再一次批处理；结果报告实际清理与玩家迁移数量。
- [ ] 在复制样例执行 purge wzn:cat，验证其它三维度保留；交付第5轮整包。

### 第6轮：GUI 任意维度命令解析与执行（目标 8 分钟）

**Files:** Modify Sources/Command/WorldCommand.swift、WorldCommandExecutor.swift、Sources/UI/WorldCommandViewController.swift、Sources/World/TickingAreaStore.swift；Windows/MCBEEditor.Core/Chunk/{BlockCommand,ChunkCommand,StorageBiomeCommand,TargetingCommand,EntityActionCommand,EntityQueryCommand,EnvironmentCommand,StructureTemplateCommand}.cs、Windows/MCBEEditor.Desktop/RegionCommandWindow.cs、SharedCommandFileStore.cs。

**Interfaces:** Swift WorldCommandParser.parse(_ text: String, dimensionResolver: ((String) throws -> Int32)? = nil) throws -> ParsedWorldCommand；C# parser Parse(string text, Func<string,int>? dimensionResolver = null) 的兼容重载；DimensionStore.resolve(_ token: String) throws -> Int32 / Resolve(string token) -> int。

- [ ] 写失败测试：setblock/getblock/fill/clone跨维度/entity/summon/storage/fillbiome/structure/tickingarea/teleport/spawnpoint 可使用 wzn:cat、1001 和无 namespace 名称。
- [ ] 接入世界范围 resolver；移除 tickingarea 两端验证器的原版枚举检查以及 spread 的 [0,1,2] 过滤。
- [ ] 检查召唤NBT格式、随机 spread、Auto Y、命令输出名称，以及未知数值 ID 无白名单阻拦。
- [ ] 回归原版命令与错误无写入行为，交付第6轮整包。

### 第7轮：CLI 与命令文件的维度上下文（已完成；本次不限时）

**Files:** Modify CLI/iOS/{CliCommandPlan,CliStructureFileCommand,CliWorldRunner,CliInteractiveShell}.swift、CLI/Windows/{CliCommandParser,CliCommandPlan,CliWorldRunner,CliWorldCommandExecutor,CliCommandPolicy,CliStructureFileCommand}.cs；Test CLI/Windows.Tests/DimensionCommandTests.cs、CLI/Tests/dimension_smoke.py。

**Interfaces:** CLI plan 接收维度 snapshot；纯内存预检投影 add/purge 状态；执行时复用 GUI 核心服务。

- [x] 写失败测试：同文件 dimension add bear 1000 → setblock bear ... → dimension query → dimension purge bear。
- [x] 验证后续语法错误导致整个文件预检失败且无写入；重复 add、先 purge 后使用旧名称均有正确错误。
- [x] 覆盖无世界 validate、交互模式、命令文件、自动读取 Commands/Command.txt 四条入口。
- [x] 更新只读/修改策略，验证 export/reopen 中新维度不丢失；交付第7轮整包。

### 第8轮：整体验证、帮助与最终交付（已完成；本次不限时）

**Files:** Modify 全部命令帮助、ReadMe.txt 生成源、CLI/Examples/Command.txt；完善上述 tests 和 Docs/DimensionStage8/VALIDATION.md。

**Interfaces:** 无新核心接口；最终功能覆盖矩阵与源码整包。

- [x] 逐条核对所有命令的维度参数，搜索残留原版白名单与错误提示；保留原版专有规则（如 Nether Auto Y），不误当白名单删除。
- [x] 运行 Swift 专项测试、C# 核心自测、Windows CLI 测试、样例复制品 add/empty/purge/export/reopen 测试。
- [x] 原版缺失后 add、ID 字节碰撞、unknown tag、actor/limbo/player/tickingarea/village/clock 的回归用例全部核对。
- [x] 更新完整命令示例；记录确实运行和无法运行的构建检查；交付最终源码包。

## 轮次规则

阶段时间包含检查、修改、验证与保存。预留最后 2 分钟验证并打包。若任务在本轮不能完成，产出明确标注未完成项的检查点，下一轮接着同阶段，不越过未完成依赖。阶段包必须可独立恢复，不依赖当前临时目录。
