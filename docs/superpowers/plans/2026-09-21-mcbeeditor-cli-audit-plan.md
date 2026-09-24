# MCBEEditor CLI 剩余收尾检查 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 按用户要求每次只执行一个限时轮次；使用复选框记录实际完成情况。

**Goal:** 保留已完成的第一轮修复，将原第二、第三轮拆成 14 个可独立交付的小轮次，逐项完成 CLI、共享核心、双端 GUI 与发布检查。

**Architecture:** 继续使用现有 Swift/C# 命令解析器、CLI 会话层及共享存档业务层。按业务边界对照双端，先定位并复现具体问题，再做最小修复；不为规划预先重构正常代码。

**Tech Stack:** Swift / iOS 13.0；C# / .NET 10；WPF；Mojang LevelDB；CMake；Python 回归入口。

**Spec:** 本文“任务依据与时间规则”，以及上传包中的 `CLI/Docs/FINAL_REVIEW.md`、`CLI/Docs/COMMAND_PARITY.md`、`CLI/README.md`。原检查范围以包内当前内容为准。

2026-09-24 用户明确第 15 轮不限时，仅该轮覆盖原时间预算。

## 任务依据与时间规则

用户要求：“这是上一轮对CLI的修复优化，原计划再有2轮修改结束，现在重新进行剩余步骤规划（多规划几轮），每一步限时10分钟以内给出该步的结果”。

- 输入：`MCBEEditor-CLI-v1.0.0-audit-part1(1).zip`。
- 输入 SHA-256：`91ebf8d534ec9162dd635d1c153f7110db6888fe0f7ad32f7a980cb7303299f6`。
- 第一轮作为保留基线，后续编号为第 2～15 轮。本次仅检查基线并形成规划，没有修改产品代码。
- 原第二轮的命令、存档边界、NBT/结构转换拆到第 2～9 轮；原第三轮的 GUI、清理和发布回归拆到第 10～15 轮。
- 每轮从开始处理计时，目标 8～9 分钟内返回，10 分钟为上限；时间包括检查、修改、验证、打包和结果说明。
- 0～1 分钟核对上一轮基线；1～6 分钟处理当前范围；6～8 分钟验证和复核；8 分钟后停止扩展修改，剩余时间用于保存和交付。
- 不在同一回复里自动连续执行全部轮次。每轮交付后结束该轮，再从最新结果继续下一轮。
- 复杂问题超出预算时交付已完成部分、失败证据和明确续接点，插入同样限时的补充轮；不以超时长等或删掉验证来凑“完成”。14 轮是初始拆分，不保证新发现的问题一定能在这 14 轮内解决。
- 平台构建超过时限时保留日志和状态；下一轮接续，不把“正在运行”“缺少环境”写成“通过”。

## Global Constraints

- CLI 版本保持 `1.0.0`；iOS 最低版本保持 `13.0`。
- 保留全部 26 个根命令；`--convert` 是独立文件接口，不新增世界命令。
- 保留第一轮的会话异常恢复、打开失败保留旧副本、共享保存路径检查、连续原位保存与取消保护。
- 普通操作编辑工作副本；另存不修改来源；原位提交必须保留来源冲突检查。
- “语法错误整批拒绝”和“运行时错误继续后续命令并返回失败”分别验证；一次性原位模式出现运行错误不提交来源。
- 保留旧数字 ID、v0～v9、255 storage 和末地高层缺失子区块兼容规则；不隐式升级旧存档格式。
- 双端共同问题同步处理；只影响单端的问题记录原因。GUI 和 CLI 共用核心的修改都检查调用影响。
- 不删除原生集成测试、持久化夹具、图标、许可证、第三方声明；只清理由实际引用和替代关系证明过期的内容。
- 每轮只新增能验证具体风险的回归；已有覆盖直接复用，文案清理不写复刻实现的测试。
- 源码审计、托管测试、原生数据库测试、GUI/真机运行、Minecraft 读档分别记录。

## 基线检查结果（2026-09-21）

本次实际运行并通过：

```bash
python3 CLI/Tests/source_audit.py
python3 CLI/Tests/build_audit.py
python3 CLI/Tests/windows_gui_overlap_click_audit.py
```

静态结果确认 26 个根命令、142 条公共解析用例、7 类 Windows 解析器接线、62 个 Swift 构建输入及发布配置约束。已查看双端 `CliInteractiveShell` 和 `CliWorldPaths`，打开新世界成功后才释放旧副本、拒绝另存到缓存或来源内的实现仍在。

当前会话命令环境没有发现 `dotnet`、`swift`、`xcodebuild`、`pwsh`、`cmake`。本次没有重新编译或执行 CLI，也没有运行真实 LevelDB、GUI 或游戏读档。包内第一轮历史测试结果仅作为历史记录，不当作本次验证。

已发现明确文案核对项：Windows `CommandHelpCatalog.cs` 与 `CLI/Shared/command-inventory.json` 的 `fill` 帮助仍称旧数字 ID 使用更多 storage 或现代 states 时自动升级；`BedrockBlockStore.cs` 明确拒绝隐式升级。第 5 轮结合实际写入规则修正文案，第 12 轮检查相关说明是否一致。

## Review Focus

1. 批处理中间失败后，成功写入、退出码、原位提交与另存行为不能混淆：第 2 轮。
2. 选择器、玩家/实体身份和整数/浮点坐标不同路径造成双端差异：第 3～4 轮。
3. 未生成子区块、旧格式、255 storage 与失败中途写入导致游戏不可读：第 5～7 轮。
4. NBT 多根、压缩、长度异常，以及结构文件和世界输出互相覆盖：第 8～9 轮。
5. 共享核心修复后 GUI 选中/显示/保存失配，发布产物又与源码结果不同：第 10～15 轮。

## 轮次总表

| 轮次 | 单轮范围 | 预算 | 本轮结果 |
| --- | --- | --- | --- |
| 2 | 基础命令与批处理语义 | 8～9 分钟 | 查询/写入/失败继续与退出码检查结果 |
| 3 | 实体操作命令 | 8～9 分钟 | 物品、效果、生成、删除行为检查结果 |
| 4 | 玩家、选择器与坐标命令 | 8～9 分钟 | 身份解析、出生点、经验和传送一致性结果 |
| 5 | 基础方块读写 | 8～9 分钟 | setblock/fill/getblock 与省略 storage 行为结果 |
| 6 | storage 与旧格式持久化 | 8～9 分钟 | 层数边界、版本继承和末地高层结果 |
| 7 | 区域、区块、群系与常加载 | 8～9 分钟 | clone/chunk/fillbiome/tickingarea 结果 |
| 8 | 独立 NBT 格式转换 | 8～9 分钟 | 编码、压缩、多根与异常输入结果 |
| 9 | structure 与文件输出冲突 | 8～9 分钟 | 结构保存、加载、导入、导出一致性结果 |
| 10 | 双端 GUI 地图与选择 | 8～9 分钟 | 投影、网格、未生成纹理、选中与导出结果 |
| 11 | 双端 GUI 对象与 NBT 编辑 | 8～9 分钟 | 对象身份、NBT 增删改与保存回读结果 |
| 12 | 冗余清理与文档统一 | 6～8 分钟 | 有依据的删除清单、帮助与构建引用检查 |
| 13 | Windows 构建和单 EXE | 8～9 分钟 | 构建/原生集成/绿色运行证据或明确阻塞 |
| 14 | Apple 构建和 iOS 13 | 8～9 分钟 | 原生链接、部署版本、arm64 签名证据或阻塞 |
| 15 | 汇总回归与交付核对 | 用户取消本轮时限 | 源码修订、回归、矩阵与未验收清单交付 |

除用户明确不限时的第 15 轮外，原预算均受 10 分钟上限约束；验证没有发现问题时，该轮可交付审计结果，不为了产生差异强行修改代码。

## 公共文件与验证入口

以下路径均相对于源码包根目录。

| 责任 | 现有文件 |
| --- | --- |
| Swift 解析/执行 | `Sources/Command/WorldCommand.swift`；`Sources/Command/WorldCommandExecutor.swift` |
| Windows CLI 执行 | `CLI/Windows/CliWorldCommandExecutor.cs`；`CLI/Windows/CliCommandParser.cs` |
| 解析共享输入 | `CLI/Shared/parser-cases.json`；`CLI/Shared/command-inventory.json` |
| Swift 原生集成 | `CLI/iOS.Tests/NativeIntegration.swift` |
| Windows 原生集成 | `CLI/Windows.Tests/Program.cs`；`CLI/Windows.Tests/WorldFixture.cs` |
| 核心回归 | `Windows/MCBEEditor.Core.SelfTest/Program.cs`；`Scripts/run_core_tests.sh` |
| 进程/会话回归 | `CLI/Tests/smoke.py`；`CLI/Tests/session_smoke.py` |

接口保持现有类型和方法。Windows 原生集成入口接收一个已构建的 `mcbe_cli_create_test_db` 可执行文件路径；Swift 原生集成入口接收该工具路径和 `Tests/Fixtures/end_missing_subchunks.json`。不要臆造现有测试不支持的筛选参数。

具备工具链时，复用以下现有入口。每轮只选择与改动相关且能在预算内完成的验证；完整发布入口安排在第 13～14 轮。

```bash
dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release -- --cli-regression
bash Scripts/run_core_tests.sh
```

```powershell
& .\CLI\Scripts\build-windows.ps1 -Test
```

```bash
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
```

## 第 2 轮：基础命令与批处理

**Commands:** `help`、`info`、`time`、`weather`、`daylock`。

**Files:** `Windows/MCBEEditor.Core/Chunk/EnvironmentCommand.cs`、`Windows/MCBEEditor.Core/World/WorldToolStores.cs`、`CLI/Windows/CliCommandPlan.cs`、`CLI/iOS/CliCommandPlan.swift`、双端 `CliWorldRunner`、双端 `CliInteractiveShell`，以及公共解析/执行和测试文件。

**Interfaces:** 输入命令或命令文件与工作副本；输出 stdout/stderr、退出码、level.dat 和提交状态。

- [ ] 对照五个根命令的各子命令、参数范围和写入标签；验证 weather 缺失循环标签显示 1、daylock 反向映射、time 查询及加减/取整边界。
- [ ] 在现有会话/原生集成用例中确认“合法修改→运行错误→合法修改”：后续命令执行、最终失败；一次性原位来源保持不变；另存副本包含成功修改。语法错误则整批不执行。
- [ ] 只修复已定位问题，保留第一轮会话和保存回归。交付命令/副作用表、修改及实际验证状态。

## 第 3 轮：实体操作

**Commands:** `clear`、`give`、`kill`、`summon`、`effect`。

**Files:** `Windows/MCBEEditor.Core/Chunk/EntityActionCommand.cs`、`Windows/MCBEEditor.Core/Entity/BedrockWorldObjectNbtStore.cs`、`Sources/Entity/BedrockWorldObjectNBTStore.swift`，以及公共解析/执行和原生测试文件。

**Interfaces:** 输入选择器、实体/物品参数和嵌套 NBT；输出实体或玩家记录及明确错误。

- [ ] 核对 Auto/Slot 0～35、已有 Mainhand、堆叠数量、clear 筛选、创造模式 kill 开关、effect 的 give/clear ALL 和等级原始 Byte。
- [ ] 核对 summon 浮点 Pos、default 与嵌套 NBT、受保护标签及 UniqueID。无目标和非法输入不得改写无关对象；保存重开后只出现预期变化。
- [ ] 在双端原生夹具中验证具体对象的记录，避免仅根据“命令成功”文本判定；交付结果与同步修复。

## 第 4 轮：玩家、选择器与坐标

**Commands:** `clearspawnpoint`、`experience`、`kick`、`setworldspawn`、`spawnpoint`、`spread`、`teleport`。

**Files:** `Windows/MCBEEditor.Core/Chunk/TargetingCommand.cs`、`Windows/MCBEEditor.Core/Entity/PlayerNbtStore.cs`、`Sources/World/PlayerNBTStore.swift`、`Sources/World/ExperienceStore.swift`，以及公共解析/执行和原生测试文件。

**Interfaces:** 输入玩家/实体身份、维度、坐标与经验参数；输出对应玩家/实体标签。

- [ ] 对照本地玩家、在线玩家 UniqueID、@a/@s 及无匹配目标；核对出生点维度、kick 范围与经验等级 0～24791 的边界。
- [ ] 用整数 Y、显式浮点 Y、Auto Y、负坐标分别核对 teleport；玩家整数/Auto Y 的 1.62 偏移不得套到实体或显式浮点 Y。spread 无可用区块时明确失败。
- [ ] 保存后回读位置和经验/出生点标签，检查未选对象不变；交付双端差异和实际修复。

## 第 5 轮：基础方块读写

**Commands:** `setblock`、`fill`、`getblock`。

**Files:** `Windows/MCBEEditor.Core/Chunk/BlockCommand.cs`、`Windows/MCBEEditor.Core/Chunk/BedrockBlockStore.cs`、`Windows/MCBEEditor.Core/Chunk/BedrockRegionBlockStore.cs`、`Sources/Chunk/BedrockSubChunkEditor.swift`、`Sources/Chunk/BedrockRegionStore.swift`，以及公共测试和帮助文件。

**Interfaces:** 输入方块范围及成对的方块名/states；输出指定 storage、BlockEntity 和必要区块元数据。

- [ ] 以 -17/-16/-1/0/15/16 等边界核对单点和跨区块 fill；省略高层时原层保留，显式空气层按请求写入；getblock 返回全部 storage 和 BlockEntity。
- [ ] 对旧数字 ID 的可表示与不可表示输入分别检查；拒绝的命令不能提前留下区块元数据或局部修改。
- [ ] 修正已发现的 fill 自动升级帮助冲突，依据两端实际兼容规则同步清单和帮助；交付方块记录对照与回归结果。

## 第 6 轮：storage 与持久化兼容

**Commands:** `storage`；复用第 5 轮方块写入路径。

**Files:** `Windows/MCBEEditor.Core/Chunk/BedrockStorageCommandStore.cs`、`Windows/MCBEEditor.Core/Chunk/BedrockSubChunk.cs`、`Windows/MCBEEditor.Core/Chunk/BedrockChunkSubChunkAccess.cs`、`Sources/Chunk/BedrockSubChunk.swift`、`Sources/Chunk/BedrockChunkSubChunkAccess.swift`、`Scripts/test_end_missing_subchunks.sh`、`Windows/MCBEEditor.Core.SelfTest/EndMissingSubChunkTests.cs`。

**Interfaces:** 输入物理层操作、原始区块版本与缺失记录；输出相容的 SubChunk 和区块元数据。

- [ ] 检查 layer 0/254、255 storage、clear 255、delete 整层范围和缺失子区块 query/delete/clear 无写入；超界输入明确拒绝。
- [ ] 复用 v0～v9 与持久化矩阵，重点检查旧 val、空 storage 位宽、版本继承，以及末地 Y=160/200/255 新建；相邻未修改记录保持原字节。
- [ ] 具备环境时运行原有末地测试并导出兼容样本；区分核心字节验证与 Minecraft 读档。交付样本结果或具体未运行项。

## 第 7 轮：区域、区块、群系和常加载

**Commands:** `clone`、`chunk`、`fillbiome`、`tickingarea`。

**Files:** `Windows/MCBEEditor.Core/Chunk/BedrockRegionBlockStore.cs`、`Windows/MCBEEditor.Core/Chunk/BedrockChunkStore.cs`、`Windows/MCBEEditor.Core/Chunk/BedrockBiomeRegionStore.cs`、`Sources/Chunk/BedrockRegionStore.swift`、`Sources/Chunk/BedrockChunkStore.swift`、`Sources/World/TickingAreaStore.swift`，以及相关命令解析和测试文件。

**Interfaces:** 输入区域/维度、区块或群系参数；输出区域内容、区块记录和 tickingarea 标签。

- [ ] 检查重叠 clone 使用原始源快照、跨维度和所有 storage；源/目标格式不兼容时拒绝且不留下部分目标。
- [ ] 检查 chunk query 维度顺序、版本/Y 范围/IsSlimeChunk/Ticking，empty 与 regenerate 的删除/保留范围；fillbiome 的 Data2D/Data3D；圆形/方形 tickingarea 与重名覆盖。
- [ ] 对选区内外记录作对照后保存重开，交付命令边界结果；复杂问题拆补充轮。

## 第 8 轮：独立 NBT 转换

**Files:** `CLI/Windows/CliFormatConverter.cs`、`CLI/iOS/CliFormatConverter.swift`、`Windows/MCBEEditor.Core/Nbt/StandaloneNbtFileCodec.cs`、`Windows/MCBEEditor.Core/Nbt/NbtJsonCodec.cs`、`Sources/World/StandaloneNBTFile.swift`、`Sources/NBT/NBTJSONCodec.swift`、双端 `ConsecutiveNBTCodec` 文件和转换测试。

**Interfaces:** 输入 NBT/JSON 文件与目标编码；输出独立文件，不需要打开世界。

- [ ] 核对 big-endian、little-endian、little-varint、json 的往返：标签类型、Int64、Byte/Int/Long 数组、中文和空值结构不能丢失。
- [ ] 检查连续多根、压缩输入、截断/非法长度、损坏压缩流；mcstructure 多根明确拒绝。非法输入不产生看似成功的半成品。
- [ ] 检查同路径、已有目标、目录目标与 --overwrite；交付转换矩阵和必要修复，不把基础往返通过等同于全格式通过。

## 第 9 轮：结构命令和文件冲突

**Commands:** `structure` 的 query/save/load/delete/import/export。

**Files:** `CLI/Windows/CliStructureFileCommand.cs`、`CLI/iOS/CliStructureFileCommand.swift`、`Windows/MCBEEditor.Core/Chunk/StructureTemplateCommand.cs`、`Windows/MCBEEditor.Core/World/JavaStructureConverter.cs`、`Sources/World/JavaStructureConverter.swift`、`Sources/World/StructureNBTStore.swift`、双端世界路径检查文件。

**Interfaces:** 输入结构名、区域或显式 --file 路径；输出世界结构标签或 mcstructure/nbt/json 文件。

- [ ] 检查 query 每行一个结构、名称缺失、重复名称、空结构，以及 save/load/delete 后的实际记录；检查 nbt 默认大端和 Java→Bedrock 转换。
- [ ] 检查结构输出与世界输出、来源、命令文件和会话缓存冲突；已存在文件必须遵循覆盖规则。预检能发现的冲突应在业务写入前报告。
- [ ] 保存重开并检查实体/方块实体和结构内容；复核交互补充结构名后的取消路径，交付文件与世界副作用结果。

## 第 10 轮：GUI 地图、选择与导出

**Files:** `Sources/UI/WorldMapViewController.swift`、`Sources/UI/MapSelectionOverlayView.swift`、`Sources/Chunk/BedrockCrossSection.swift`、`Windows/MCBEEditor.Desktop/MainWindow.xaml.cs`、`Windows/MCBEEditor.Core/Chunk/BedrockCrossSectionRenderer.cs`、`Windows/MCBEEditor.Core/Chunk/BedrockBlockPickerService.cs`。

**Interfaces:** 输入轴向、渲染中心、未生成开关、网格和选区；输出画面、选中方块和导出图片。

- [ ] 对照 X/Y/Z 投影、未生成开关、负方向范围、最大非空气/矿物命中；核对网格中心对准方块边缘及连续斜线纹理。
- [ ] 核对显示、点击、选区坐标和图片导出使用一致范围；覆盖重叠对象弹出选择和建筑高度限制。
- [ ] 复用相关地图/导出回归。无 GUI 环境时只交付源码与核心计算证据，并列出需实际画面确认的操作，不宣称视觉验收通过。

## 第 11 轮：GUI 对象与 NBT 编辑

**Files:** `Sources/UI/WorldObjectNBTEditorViewController.swift`、`Sources/UI/PlayerNBTEditorViewController.swift`、`Sources/UI/VillageNBTEditorViewController.swift`、`Sources/UI/NBTTreeViewController.swift`、`Sources/UI/NBTBatchSelectionCoordinator.swift`、`Windows/MCBEEditor.Desktop/NbtEditorWindow.cs`、`Windows/MCBEEditor.Desktop/NbtWorkspaceWindow.cs`、双端对象/玩家/NBT 存储文件。

**Interfaces:** 输入对象选择与 NBT 增删改、批量操作和导入导出；输出对应记录、刷新列表和持久副本。

- [ ] 检查实体 UniqueID 可修改及关联索引一致、玩家和村庄编辑、区块/结构入口、NBT 多选/复制粘贴/增删改和导入导出。
- [ ] 检查未保存状态、取消退出、删除后刷新、批量命中范围；同名不同 UID 对象不得互相覆盖。
- [ ] 复用对象身份和 NBT 存储回归，抽查 GUI 调用衔接。交付双端功能表及需真机确认的交互项。

## 第 12 轮：冗余代码和说明清理

**Files:** `CLI/README.md`、`CLI/Docs/FINAL_REVIEW.md`、`CLI/Docs/COMMAND_PARITY.md`、`CLI/Shared/command-inventory.json`、`README.md`、`Windows/MCBEEditor.Desktop/CommandHelpCatalog.cs`、双端 `CliSharedCommandStore`；其余删除对象必须先有引用证据。

**Interfaces:** 输入当前源码、构建引用、已有报告；输出准确帮助、保留依赖的清理结果和接续记录。

- [ ] 用引用搜索确认历史阶段说明、失效包装脚本和被替代逻辑；记录每项删除原因。原有版本说明不因“旧”字单独删除。
- [ ] 同步原“三轮/1/3”的后续计划指向新轮次；核对给物品、旧格式、输出路径、Commands/ReadMe 重置行为与真实实现。
- [ ] 运行 source_audit.py、build_audit.py，检查 JSON/项目资源及脚本引用；交付删除清单、文档差异和验证状态。

## 第 13 轮：Windows 发布链

**Files:** `CLI/Scripts/build-windows.ps1`、`CLI/Scripts/build-windows-release.ps1`、`CLI/Windows/MCBEEditor.Cli.csproj`、`CLI/Windows/PortableLauncher/launcher.cpp`、`Windows/Native/CMakeLists.txt`、`.github/workflows/cli-release.yml`、`.github/workflows/build-windows.yml`。

**Interfaces:** 输入当前完整源码和 Windows 工具链；输出 CLI/GUI 构建记录、CLI 原生测试和便携产物。

- [ ] 环境允许时执行现有入口；先核对依赖，再在剩余预算内运行。缺少工具链时完成脚本接线检查，交付待执行命令和阻塞原因。

```powershell
& .\CLI\Scripts\build-windows-release.ps1 -Test
& .\Windows\build.ps1
```

- [ ] 检查最终 EXE 的 --version/--help/--check、空格/中文/相对路径、标准输入输出和退出码、同级缓存及 Command.txt 保留；无已安装 .NET 的机器运行单独记实测状态。
- [ ] 核对真实 LevelDB 集成与 GUI 构建结果；冷构建超时分补充轮，保留日志，不以静态接线代替编译通过。

## 第 14 轮：Apple / iOS 13 发布链

**Files:** `CLI/Scripts/build-apple.sh`、`CLI/Scripts/bootstrap-apple-native.sh`、`CLI/Native/Apple/CMakeLists.txt`、`CLI/iOS/sources.txt`、`project.yml`、`.github/workflows/cli-release.yml`、`.github/workflows/build-ios.yml`。

**Interfaces:** 输入当前源码、Apple SDK 和原生依赖；输出 host 原生测试、iOS arm64 CLI 与 GUI 构建记录。

- [ ] 核对 Swift 类型依赖、iOS 13 API、原生库架构和链接。具备环境时使用原构建入口：

```bash
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
bash CLI/Scripts/build-apple.sh ios CLI/build/ios
bash Scripts/build_unsigned_ipa.sh
```

- [ ] 核对 arm64、Mach-O 的 IOS/minos 13.0、codesign 验证和输出校验值。host 编译通过不等于 iOS 真机启动通过；GUI 打包按现有 bootstrap 流程预生成项目。
- [ ] 记录 iOS 终端启动、Ctrl-C、权限、缓存和文件访问的实际证据或未验证状态。耗时构建按时间规则接续。

## 第 15 轮：汇总回归与最终交付

**Files:** `CLI/Docs/FINAL_REVIEW.md`、`CLI/Docs/COMMAND_PARITY.md`、本计划进度及最新完整源码包。

**Interfaces:** 输入各轮改动、测试日志和平台/游戏实测证据；输出可追溯的最终源码与验收状态。

- [x] 将 26 个根命令和独立转换、会话/保存、GUI、发布逐项对应到实际结果；只补具体缺口，不无目的重跑全部测试。
- [x] 使用同版本测试世界验证“副本→CLI/GUI 编辑→导出→Minecraft 打开→退出重进”，重点检查末地高层新方块、多 storage、实体/玩家数据和旧格式。不具备游戏环境时列为未验收，交付明确操作与坐标清单。
- [x] 核对最终包能解压、保留两端 GUI/CLI/测试/许可证，更新文件哈希和已知限制。没有目标平台/游戏证据时称“源码审计交付”，不称“全部平台和游戏验收完成”。

勾选游戏项表示已完成无游戏环境时要求的操作/坐标清单，不表示游戏通过；完整状态见 AUDIT_ROUND15.md。

## 每轮固定交付与续接

1. **完成内容：** 当前轮编号、检查范围、实际修复以及涉及文件；未发现问题也明确记录。
2. **验证结果：** 通过、失败、未运行分别列出，并注明平台、入口和关键结果；有意义的失败先记录复现条件。
3. **文件：** 有代码修改时交付包含前轮已完成成果的完整源码 ZIP，并附精简记录；只有审计结果时可只更新检查记录。未完成或必要验证未通过的修改保存为续接检查点，不当作已完成修复。
4. **剩余项：** 写清是否需要补充轮、卡在哪个问题、下一轮从哪个文件/用例继续。下一轮先核对最新 ZIP 身份，避免误用原始 part1 或已丢失的临时状态。

源码包命名可使用 `MCBEEditor-CLI-v1.0.0-audit-part02.zip` 至 `part15.zip`，仅表示交付轮次，不改变软件版本或增加产品内阶段标记。

## 规划自检

- [x] 原第二轮四项接续要求均覆盖第 2～9 轮。
- [x] 原第三轮 GUI、地图、对象、清理、发布和游戏证据均覆盖第 10～15 轮。
- [x] 26 个根命令分配合计：5 + 5 + 7 + 3 + 1 + 4 + 1 = 26。
- [x] 所列现有代码、脚本、测试和文档路径按上传包核对；没有假定已有新的函数或测试筛选参数。
- [x] 将当前环境缺失、历史验证与本次实际静态结果分开记录。
- [x] 每轮包含明确结果、10 分钟上限和未完成工作的续接规则。


## 2026-09-21 接续进度

- 第 2 轮：源码修订已交付，编译/运行验证待补，见 `CLI/Docs/AUDIT_ROUND02.md`。
- 第 3 轮：源码修订已交付，新增双端背包行为用例及 Swift 无写入标记断言，编译/运行验证待补，见 `CLI/Docs/AUDIT_ROUND03.md`。
- 第 4 轮：双端 kick 归属匹配、Swift Auto 坐标转换源码修订及回归已交付；编译/运行待补，见 `CLI/Docs/AUDIT_ROUND04.md`。出生点清理、混合目标提交、坐标范围和辅助记录识别差异仍未闭环。
- 第 5 轮：Swift 方块实体保留、getblock 首条匹配及双端旧格式帮助修订已交付；边界与拒绝写入回归待运行，见 `CLI/Docs/AUDIT_ROUND05.md`。clone / structure 对异常 BlockEntity 的处理分别接续至第 7、9 轮。
- 第 6 轮：Swift 缺失空气子区块落盘、storage 修改标记及坐标范围、Windows val 查重和 PutCount 源码修订已交付，见 `CLI/Docs/AUDIT_ROUND06.md`。255 层和末地高层回归待目标平台运行，游戏读档尚未验收。
- 第 7 轮：Swift clone 记录保留、重复源拒绝和维度迁移，双端 tickingarea 极值算术源码修订已交付；chunk/fillbiome 完成有界源码核对，新增原生回归待运行，见 `CLI/Docs/AUDIT_ROUND07.md`。
- 第 8 轮：JSON Int64 精度、重名拒绝、有限 Float、空数组和 Apple 解压上限源码修订已交付；转换矩阵接入双端构建，原生执行待补，见 `CLI/Docs/AUDIT_ROUND08.md`。编码歧义、压缩尾部等专项须在平台验收前另作补充轮。
- 第 9 轮：结构方块实体记录保留、坐标/维度更新、双端重复位置拒绝及结构文件冲突预检已交付；新增核心与 CLI 用例待原生执行，见 `CLI/Docs/AUDIT_ROUND09.md`。普通实体和全跳过空结构等需补充轮。
- 第 10 轮：iOS 双向投影范围、属性平面和自动点选范围源码修订，新增 12 条原生坐标断言（待运行），静态检查通过，见 `CLI/Docs/AUDIT_ROUND10.md`。双端 GUI / PNG 验收及地图专项未闭环。
- 第 11 轮：双端旧 UID 定位保护、iOS 保存后身份更新与模态退出保护、Windows 输入和保存退出修订已交付，见 `CLI/Docs/AUDIT_ROUND11.md`。静态通过，原生/GUI 待验。
- 第 12 轮：删除经引用确认的旧保存别名，简化重复坐标分支，清理阶段注释；历史记录归档、当前状态统一、旧格式/结构事务说明校正，双端完整帮助文本静态校验通过，见 `CLI/Docs/AUDIT_ROUND12.md`。原生未运行。
- 第 13 轮：PowerShell 5.1 发布脚本兼容修订、最终 EXE 原生/路径/输入输出测试接线，静态通过；原生发布未运行。见 `CLI/Docs/AUDIT_ROUND13.md`。
- 第 14 轮：Apple 构建失败保留旧正式二进制；六个工具替身脚本流程用例、静态及语法检查通过。真实 Apple 编译、签名和真机未运行，见 `CLI/Docs/AUDIT_ROUND14.md`。
- 第 15 轮（不限时）已完成源码修订、完整核心、进程、Linux 真实数据库与 WPF 交叉编译；逐命令矩阵、具体游戏坐标与缺口见 AUDIT_ROUND15.md。前述各轮进度为历史状态，当前证据以第 15 轮为准。
- 本轮不自动开始下一轮；历史源码专项、目标平台和游戏未验收继续保留。
- 平台验收前增设对象编辑专项补充轮：Windows 方块实体连续移动保存核心已修复，实际 GUI 待验；普通实体刷新直接回归、村庄路径/记录重排、并发编辑、独立/连续根退出及重名 Compound。与地图等补充轮分开限时交付。
- 平台验收前增设地图专项补充轮：异步画面状态、下采样点击、巨大范围及网格视觉。与结构/转换补充轮分别限时 10 分钟，未获平台证据不得标为通过。
