# 命令与 ReadMe 复核报告

日期：2026-10-04。基于维度功能最终源码 `4391db0`，本轮更新 ID 对照、中文显示名称及固定 ReadMe。验证使用 Linux、真实 Swift 6.2.3、.NET SDK 10.0.401，以及真实 Mojang LevelDB native 库。

## 本轮实际结果

| 检查 | 结果 | 实际范围 |
| --- | --- | --- |
| 官方 ID/名称核对 | PASS | 141 个实体 Short ID、89 个生物群系数字 ID、当前实体/效果/魔咒名称全集；固定来源哈希 |
| 两端编译后目录对比 | PASS | Swift/C# 全部 565 行；实体扫描器数字映射、中文搜索 |
| 四端 Commands ReadMe 文件测试 | PASS | 生产写入组件、实际临时文件、固定快照字节一致、帮助变化无影响、恢复默认说明、不创建/改写 Command.txt |
| 六份 ReadMe 静态来源审计 | PASS | 均为内置文字常量，源码与随包固定文本逐字节一致，所有命令段与当前 28 类帮助一致 |
| 完整 Swift 核心回归 | PASS | 生产解析/存储/执行逻辑，核心回归、231 共享解析用例及 98 项源码审计 |
| Swift 维度专项 | PASS | query/add/empty/purge，原版重建、任意维度、未知标签、村庄名称边界、冲突归属拒绝 |
| 完整 C# Core.SelfTest | PASS | 原有全部核心行为、区块/实体/玩家/结构/效果/天气等持久化，以及维度专项 |
| C# CLI 编译 | PASS | 0 warnings / 0 errors |
| 原生 CLI 集成 | PASS | 44 个主调用用例，另含 dimension/entity/summon/MCBE-SNBT 专项；真实 LevelDB、导出重开、输入完整性、失败恢复 |
| CLI 进程检查 | PASS | 293 项进程检查、231 个解析用例、全部 28 类命令 |
| 用户样例真实调用 | PASS | 27 次 CLI 调用；维度生命周期、名称与 ID、原版重建、字节碰撞、示例批次、导出重开、原存档哈希 |
| Windows GUI 交叉编译 | PASS | EnableWindowsTargeting=true，0 warnings / 0 errors |
| CLI 源码及构建契约审计 | PASS | 两端帮助、解析/执行路由、67 个 Swift CLI 输入、版本/iOS 13.0 要求 |
| Apple 构建生命周期脚本 | PASS（工具替身） | 失败保留旧产物的 shell 行为；不计作 Apple SDK 构建成功 |

详细日志见 `logs/`。本轮的 ID 与 ReadMe 缺陷均先观察到失败，再验证修正后通过：`catalog-red.log` 在未更新目录时报告 NPC 条目不匹配；`readme-red.log` 在未修正 Windows GUI 时报告从运行时帮助拼接内容。

## 全部 28 类命令的功能覆盖

下面的“已通过”指本轮重新运行的 Swift/C# 核心测试及真实 C# CLI 用例，不是仅检查命令能否解析，也不代表目标平台 GUI 已被实际点击操作。对应源码测试入口保留在 `Scripts/run_core_tests.sh`、`Scripts/test_dimension_query.sh`、`Windows/MCBEEditor.Core.SelfTest/`、`CLI/Windows.Tests/` 与 `CLI/Tests/`。

| 命令 | 已通过的功能核对 |
| --- | --- |
| help | 全部 28 类列表、指定命令说明与非法输入检查 |
| info | 世界信息输出与只读执行 |
| dimension | query/add/empty/purge、空维度保留、名称/ID、原版重建、玩家迁移、安全拒绝、导出重开 |
| clear | 匹配玩家与实体物品清除、非目标与村民交易保护 |
| clearspawnpoint | 玩家出生点清除与目标筛选 |
| clone | 跨维度与重叠复制、多 storage、方块实体、旧格式及未生成区块 |
| chunk | query/empty/purge/regenerate、区块信息、删除内容/记录、实体清理与维度隔离 |
| daylock | 锁定/解除日夜变化、持久化及保留当前时间 |
| effect | 给出/清除效果、ALL、时长和强度边界、玩家与实体标签 |
| entity | 全维度、指定维度、浮点范围、完整 NBT、数字/字符串 identifier、只读性 |
| experience | 等级、进度、查询及目标匹配 |
| fill | 区域填充、多 storage、旧数字格式兼容、方块实体处理、边界拒绝 |
| fillbiome | 名称/数字 ID、已有 2D/3D 生物群系数据修改与持久化 |
| getblock | 全部 storage/方块实体 NBT、未生成位置、指定维度 |
| give | 玩家与实体、Auto/指定槽位、计数、容量和不兼容输入拒绝 |
| kill | 玩家/实体处理、actor/digp 或旧实体记录同步与非目标保护 |
| kick | 目标远程玩家记录删除、本地玩家保护 |
| setblock | 单/多 storage、方块状态、新切片/区块、旧数据兼容及原子拒绝 |
| setworldspawn | level.dat 世界出生点写入 |
| spawnpoint | 玩家出生点、任意维度解析与记录 |
| spread | 地面位置寻找、玩家/实体坐标、实体索引同步 |
| storage | query/set/clear/delete、0–254 层、255 storages、旧 layer1 兼容 |
| structure | save/load/query/delete、方块实体偏移；CLI 文件 import/export、格式转换及 mcbe-snbt 别名 |
| summon | default/显式 NBT、Auto/精确 Long ID、现代/旧实体存储、碰撞与引用拒绝、导出重开 |
| teleport | 浮点/整数/Auto、跨维度、玩家坐标语义、实体空间索引 |
| tickingarea | 方形/圆形添加、list/delete、登记名称、跨维度及持久化 |
| time | set/add/query、昼夜/游戏时间、数值校验及持久化 |
| weather | query/clear/rain/thunder、强度/时长/自动变化与持久化 |

新建空维度还没有生物群系记录；`fillbiome` 的功能是修改已有记录。这种输入的明确报错保留，没有把它误记为对空维度成功写入。

## 平台边界

- 没有 macOS/iOS SDK 或 Xcode：未实际构建、启动 iOS GUI 和 Apple CLI。Linux Swift 测试使用生产解析器、存储器与执行器，在数据库/文件系统等平台边界使用测试替身。
- 没有 Windows 桌面环境：WPF 完成交叉编译，未实际操作 GUI。两个 Windows FileShare 替换锁场景在 POSIX 明确 SKIP，需在 Windows 运行。
- 四个 Commands 文件组件均实际运行了写入测试；两个 Textures 的固定文本和写入路径已核查，其目标平台图片/GUI运行没有在本轮实机测试。
- 没有把源码审计、工具替身或成功解析计作目标平台运行成功。

## 原始样例与审查

源码里的 `Tests/Fixtures/custom_dimensions.mcworld` 与原始上传逐字节一致，SHA-256 为：

`b2b229bc4cc8c9937da461c08b5117501b12bb38791599eca5a6c7b6f63bdcd4`

独立只读代码审查未发现 Critical 或 Important 问题。一个 Minor 建议已处理：回归脚本现在同时核查实际 ReadMe 与随包快照，以及上游 ID/名称/哈希与验收快照。审查未修改工作区，复核确认该补充有效。

## 重跑入口

```text
python Scripts/test_catalog_sync.py
python Scripts/test_fixed_readme.py
bash Scripts/run_core_tests.sh
bash Scripts/test_dimension_query.sh
dotnet build Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj
dotnet Windows/MCBEEditor.Core.SelfTest/bin/Debug/net10.0/MCBEEditor.Core.SelfTest.dll
dotnet build CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj
dotnet CLI/Windows.Tests/bin/Debug/net10.0/MCBEEditor.Cli.Tests.dll <native_fixture_tool>
python CLI/Tests/smoke.py --backend windows -- <CLI executable>
python CLI/Tests/dimension_smoke.py -- <CLI executable>
dotnet build Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj -p:EnableWindowsTargeting=true
```

运行目录为源码根目录。native 集成需要按项目文档构建 Mojang LevelDB 桥接库与测试数据库工具；Linux 配置对应 `LD_LIBRARY_PATH`。源码归档不包含本轮临时工具链、bin/obj、native 编译产物或运行缓存。
