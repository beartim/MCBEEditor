# 第 15 轮：汇总回归与源码审计交付

日期：2026-09-24。用户明确本轮不限时。基线第 14 轮 ZIP，SHA-256：`c40c75a834f937d24b6135ca7beae7858dbabb5295d919a2ea8c8481ded2b9dc`。

状态：本轮源码修订、可用环境回归、独立复核与完整源码交付。保留前 14 轮成果；软件版本仍为 1.0.0，iOS 最低版本仍为 13.0。**全部历史专项、目标平台运行和 Minecraft 验收尚未完成。**

## 本轮修订

### Swift 出生点清理

原 clearspawnpoint 递归进入玩家 NBT 的 Compound/List，会删除物品、自定义容器中的同名字段。首次回归已观察到修复前 `clearspawnpoint deleted custom inventory tags` 失败。

现在与 Windows 既有规则一致，只删除玩家根节点中大小写不敏感的 SpawnX、SpawnY、SpawnZ、SpawnDimension、SpawnForced。所有选中玩家先完成编码，再一次 applyBatch 提交。原 PlayerNBTStore.save 只负责编码/写入，没有被绕过的附带验证。无匹配玩家和无可清除字段仍报错。

新增执行器用例验证根字段删除、Inventory/RespawnCustom 嵌套字段保留、重复清除拒绝且数据库不变，完整 Swift 回归通过。RespawnX、SpawnBlockPosition 等宽泛别名和嵌套 spawnpoint 不再递归清除，这是有意收窄，不宣称保留旧实现全部别名能力。新用例仅单玩家，多玩家单批次及失败注入尚未直接验证。

修改：Sources/Command/WorldCommandExecutor.swift、Scripts/run_core_tests.sh。

### Windows 方块实体连续保存

原 WPF 保存回调只为普通实体刷新快照，方块实体移动后继续使用旧坐标/记录引用。新增共享 BedrockWorldObjectNbtStore.RefreshedObject，GUI 两类对象保存后统一更新快照。按新维度/区块扫描，保留现代 actor 主键限制，用候选记录编码后的 NBT 字节匹配。不能唯一定位时明确提示“已保存，但无法唯一重新定位对象；请返回列表重新打开”，不任取第一项。

新增 ObjectEditorRefreshTests 使用同一编辑上下文，把 chest/water 两层方块实体从主世界 (1,64,1) 移到 (17,64,1)，再到 End (-17,64,1)，随后原位再次修改保存。断言位置、维度、NBT、两层方块和旧位置清理。新 API 缺失时曾编译失败，实现后完整 C# 核心与 WPF 交叉编译通过。实际 WPF 操作没有运行。

修改：Windows/MCBEEditor.Core/Entity/BedrockWorldObjectNbtStore.cs、Windows/MCBEEditor.Desktop/MainWindow.xaml.cs、新增核心测试、自测 Program 及 CLI/Tests/gui_nbt_audit.py。

### 实际运行揭示的测试入口

- BlockCommandAuditTests 两处 GetBlockText 使用不存在的四参数重载，实际报 CS1501；改为既有 (dimension, coordinate) API。
- ZIP 中 shell 子脚本权限为 0644，Swift 回归中途 Permission denied；七处改为显式 bash 调用，完整回归不再依赖解压后可执行权限。
- 两个 FileShare 阻止替换场景依赖 Windows；POSIX 允许替换已打开文件。保留原 Windows 断言，仅在非 Windows 输出 SKIP。集成日志标题改为 C# CLI，避免误认为 Windows OS 实测。

本地 Linux 原生桥使用 CMAKE_POSITION_INDEPENDENT_CODE=ON 解决 zlib PIC 链接问题，未修改产品 Windows/Apple 构建规则。C# 集成项目使用串行 MSBuild 审计调用，未加入项目级绕过。

## 验证与续接恢复

环境为 Ubuntu 24.04、.NET SDK 10.0.100、Swift 5.10.1、CMake 3.31.6。首次执行完成后，续接时本轮临时目录未保留；第 14 轮 ZIP 哈希完整。依据已记录的补丁恢复同一生产实现和测试意图，保存恢复检查点，重新安装工具链并重跑下列验证。随包日志均来自恢复后的最终执行；不把丢失的旧日志当作仍存在的文件。

| 验证 | 最终结果 | 边界 |
| --- | --- | --- |
| C# Core.SelfTest 完整入口 | 通过，含前轮专项及新增连续保存 | Linux 实际编译/执行，内存数据库 |
| Swift run_core_tests.sh 完整入口 | 通过，含命令、NBT、storage、旧格式、高层、投影等 | 核心执行用例及测试替身；部分 GUI/项目项是静态断言 |
| C# CLI Release | 编译通过，0 警告、0 错误 | 不是最终 Windows 单 EXE |
| smoke.py | 202 次进程、142 parser fixtures、26 根命令通过 | backend windows 指 C# 后端，OS 为 Linux |
| session_smoke.py | 14 项通过 | 会话/文件生命周期，未声称数据库覆盖 |
| environment_smoke.py | 7 场景通过 | 环境与批处理，未声称数据库覆盖 |
| nbt_conversion_smoke.py | 46 次真实 CLI 调用通过 | 有限编码/压缩/JSON/文件保护矩阵 |
| structure_file_smoke.py | 10 次真实 CLI 调用通过 | 路径预检，不需要数据库 |
| C# 原生 LevelDB 集成 | 44 项通过，2 个 Windows 文件锁场景 SKIP | Linux .so + 真实 Mojang LevelDB，含导出重开和来源保护 |
| WPF Desktop Release | 交叉编译通过，0 警告、0 错误 | EnableWindowsTargeting=true；GUI 未运行 |
| 五项源码/GUI/构建 audits | 通过 | 静态检查 |
| Apple 发布生命周期 | 六场景通过 | shell 流程与工具替身，不是 Apple 编译/签名 |
| shell/Python 语法 | 通过 | 语法证据 |

26 命令对应关系见 REGRESSION_MATRIX.md。完整日志及命令见 Validation/round15/README.md。工具链、依赖和编译产物不交付。255 storage 已获双端核心证据；C# 真实数据库还验证 End (3,220,5) 第 254 层、v8 共 255 层，以及 (35,200,5) 新区块高层导出重开，仍不能代替游戏读档。

## 独立复核

本轮进行一次只读差异审查，排除构建产物。没有确认的 Critical/Important 回归；两项 Minor：新 RefreshedObject 普通实体分支没有直接新增用例；Swift 出生点用例未直接验证多玩家单批次/提交失败。既有实体用例仍覆盖 UID、旧记录、迁移和重复保存，不能冒充新方法的直接覆盖。

审查确认 Swift 批写未遗漏保存附带行为，普通实体位置解析最终调用相同实现。未接受恢复递归清理、歧义匹配取首项或模拟 POSIX 为 Windows 锁语义。续接恢复不扩展生产修改，重新执行全部已列验证。保存成功但刷新失败后的 GUI 恢复体验仍待实测。

## 平台和游戏待验收

没有 Windows OS、macOS/Xcode/Apple SDK、iOS 设备或 Minecraft 执行环境，没有已通过目标平台验收的 EXE、Mach-O 或 IPA。

1. Windows：PowerShell 5.1/7 执行 CLI/Scripts/build-windows-release.ps1 -Test；两个 FileShare 场景、原生 DLL、最终单 EXE、无预装 .NET 的干净机器；Windows/build.cmd 构建 GUI 后实际操作对象连续保存与地图。
2. Apple：不同输出目录执行 build-apple.sh host ... --test 与 ios ...，真实 Swift/ObjC++/LevelDB 编译，核对 arm64/IOS/minos 13.0、动态依赖、签名；现有脚本构建 GUI/IPA，在允许执行的 iOS 13 环境检查启动、权限、缓存、文件访问和 Ctrl-C。ad-hoc 验签不证明设备允许执行。
3. 发布一致性：Apple 报告与二进制分次发布，非整体事务；磁盘故障、并发输出、平台缓存和 runner SDK 可用性仍待验。
4. 游戏：复制世界，记录同版本 Minecraft、输入/导出 SHA-256、命令、坐标、打开和退出重进结果；每组独立副本，保留原世界。

以下坐标来自 Tests/Fixtures/end_missing_subchunks.json。夹具只有地形记录，不是可独立打开的完整世界，须用对应完整世界或等价测试副本。每组均要求编辑器回读、游戏打开及退出重进后保持新块/数据与邻近原内容。

| 区域 | 方块坐标 | 操作 |
| --- | --- | --- |
| End v8 chunk (0,0) | (0,160,0)、(0,200,0)、(0,255,0) | 原缺失高层用 GUI 模板或 setblock 写 diamond_block |
| End v1 chunk (-121,-58) | (-1936,160,-928)、(-1936,200,-928)、(-1936,255,-928) | 负坐标/v1 新建高层，核对编码和邻块 |
| End metadata-only chunk (0,7) | (0,160,112)、(0,200,112)、(0,255,112) | 只有元数据的区块新建高层 |
| End 新区块/255 层 | (35,200,5)；(3,220,5) 第 254 层 | 对照原生用例；255 是层数，写入索引 255 必须拒绝 |
| 方块实体连续移动 | 主世界 (1,64,1)→(17,64,1)，再到 End (-17,64,1) | 同一编辑器连续保存、再原位修改，核对 NBT/两层方块/旧位置 |

旧数字 ID / LegacyTerrain 副本另验 v0～v9 支持范围，不为现代 states/多层隐式升级。玩家/普通实体组记录实际 UniqueID，检查出生点、物品自定义标签、XP、跨维度和未选记录；地图另留六方向 PNG、网格与点击结果。

## 剩余专项与完整性

优先补混合目标提交一致性、Swift clear/give 逐对象保存；随后 NBT 输入歧义/压缩边界、空结构/畸形索引、GUI 与平台/游戏。畸形环境字段、玩家辅助记录、坐标范围、普通 JSON 重复键/深度/超 Int64 策略未闭环；structure 普通实体复制未实现，save/load 仅 layer0/layer1。地图异步/下采样/巨大范围/像素、玩家村庄并发/路径重排、独立连续根退出和重名 Compound 继续保留。见 FINAL_REVIEW.md。

完整包保留第 14 轮的 485 个文件，加入本轮测试、报告和日志；不含 build/bin/obj、工具链、下载依赖或 core dump。文件哈希见 Validation/round15/files.sha256（不含自身），差异清单见 changes.json。包经 ZIP CRC、基线文件保留及哈希核验。测试通过未将历史缺口自动勾为完成。
