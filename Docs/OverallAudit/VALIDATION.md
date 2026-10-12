# 整体检查与修复验证

2026-10-12。基于上一版完整源码包 `MCBEEditor-方块实体自动坐标.zip`，保留四端项目、版本 1.0.0、最低 iOS 13.0 及全部历史成果。本轮修复记录见 [REVIEW.md](REVIEW.md)，真实输出保存在 [logs](logs/)；历史报告保持原日期与验证边界。

## 本轮结果

完整 Swift/C# 核心回归、真实 C# CLI 保存重开及异常输入检查通过；Windows GUI/CLI 编译均为 0 warnings / 0 errors。独立最终审查提出的三个 Windows 地图问题均已复现、修正并通过专项行为测试。没有遗留本轮确认的 Critical/Important 缺陷；这不构成对所有存档和目标设备的无缺陷保证。

| 检查 | 结果和实际范围 | 日志 |
| --- | --- | --- |
| 原包基线 | 原包 SHA256 `9a8752488218ab09e796ef89fd8681ce7970885532d37b8315c5172a98bc45bf`；860 个文件逐字节恢复；原基线核心测试通过 | baseline-swift.log、baseline-csharp.log |
| 完整 Swift 核心 | PASS；生产 NBT/区块/维度/命令执行器、263 个共享解析用例、出生点和全 -1 结构新回归、方块实体全部 storage 移动、新旧格式及原子拒绝 | swift-core-final.log |
| 完整 C# 核心 | PASS；原有全部自测及本轮集合分配、结构体积溢出、维度名称冲突回归 | csharp-core-final.log |
| 公共 CLI 与解析 | PASS；325 项真实进程检查、263 个解析用例、28 类根命令及完整帮助 | cli-parser.log |
| 原生数据库集成 | PASS；真实 Mojang LevelDB 的 44 项主调用及既有专项，源完整性、失败恢复、保存重开；两项 Windows FileShare 场景在 POSIX 明确 SKIP | cli-native.log |
| 维度真实调用 | PASS；27 次调用，query/add/empty/purge、名称与 ID、无 namespace、原版重建、样例批次、导出重开、输入世界不变 | cli-dimensions.log |
| fill/setblock 方块实体 | PASS；21 次真实进程调用，72 个反向跨区块/自定义维度目标；preserve/empty/SNBT，根坐标可省略或忽略、唯一 Int 实际坐标、嵌套标签/Pos/任意 id；新增含单引号的 setblock 与 summon 保存重开 | cli-block-entity-final.log |
| NBT 独立转换 | PASS；48 次调用，三种编码、连续根、gzip/zlib、精确 Long、异常与同路径输出保护；新增两种过大 Java 结构不覆盖已有文件 | cli-conversion-final.log |
| MCBE-SNBT | PASS；71 个样例、152 次实际进程调用；空未指定 List、嵌套类型、转换、非法输入及输出完整性 | cli-mcbe-snbt.log |
| structure 文件接口 | PASS；16 次实际进程预检与输出生命周期检查 | cli-structure-files.log |
| CLI 会话/环境 | PASS；14 项会话、7 项环境/批次场景 | cli-session.log、cli-environment.log |
| iOS 地图定位方法 | PASS；14 项生产定位方法调用，X/Z 剖面 × 对象/玩家 × 三个原版维度，以及自定义维度明确拒绝；UI 与 render 边界为替身 | map-ios-headless.log |
| Windows 地图状态方法 | PASS；真实生产导航、队列、图层事件和初始化方法；地形阶段与对象读取阶段都设置阻塞门，覆盖忙碌/首次渲染、合并请求、旧定位 continuation、全开/全关、自定义维度默认中心；UI/数据库读取/render 边界为替身 | map-windows-final.log |
| Windows GUI/CLI 编译 | PASS；.NET 10.0.401，GUI 使用 EnableWindowsTargeting=true；各 0 warnings / 0 errors | windows-gui-final.log、windows-cli-final.log |
| 固定 ReadMe | PASS；四个 Commands 生产写入组件实际写文件，固定快照一致、帮助变化无影响、修改后恢复、Command.txt 不创建/改写；两个 Textures 的固定文字/启动恢复路径通过既有源码检查；六份快照字节未改 | fixed-readme.log、swift-core-final.log、package-content-check.json |
| ID/中文对照 | PASS；两端编译后全部 565 行、中文搜索、实体数字 ID 桥；既有上游快照哈希、141 实体 ID、89 生物群系 ID 一致。本轮没有重新联网扩大目录版本 | catalog.log |
| 接线与冗余候选 | PASS；28 类解析/执行/帮助、67 个 Swift CLI 输入、95 个 XAML handler；2230 个私有函数声明没有仅声明引用的候选，生命周期/selector 另行人工审查 | source-audit.log、build-audit.log、windows-source-parity.log、private-references.json |

## 保持的行为

- 所有命令继续接受登记维度名称或 Int32 ID；地图渲染器仍支持三个原版维度。自定义维度定位现在明确提示，Windows 默认本地玩家定位保留主世界出生点回退，避免使用错误地图。
- setblock/fill 最后一个方块实体参数必填。模板根坐标输入时忽略，写入依据实际单点/区域；嵌套 x/y/z 不受影响。
- 未指定元素类型的空 List 继续输出/接受 `'List'''"Items"=""`。
- 普通 NBT 修改不联动地形。方块实体改变坐标/维度且源实际有方块时，全部 storage、地形与实体 NBT 在同一次批提交中迁移；无地形/全空气源继续允许 NBT-only 移动，保持任意方块实体 id 的既有契约。
- 源存档、Command.txt、固定 ReadMe、版本与最低系统要求保持。CLI 仍依明确保存模式导出或原位提交；拒绝路径不发布半成品。

## 复跑入口

需要 Swift 5.10.1、.NET 10 SDK、Python 3.10+；原生套件需要按项目脚本构建 Mojang LevelDB 及数据库 fixture tool。

```bash
bash Scripts/run_core_tests.sh
dotnet run --project Windows/MCBEEditor.Core.SelfTest -c Release
python3 Scripts/test_map_navigation.py windows
python3 Scripts/test_fixed_readme.py
python3 Scripts/test_catalog_sync.py
python3 CLI/Tests/source_audit.py
python3 CLI/Tests/build_audit.py
dotnet build Windows/MCBEEditor.Desktop -c Release -p:EnableWindowsTargeting=true
dotnet build CLI/Windows -c Release
```

Windows 上使用 `CLI/Scripts/build-windows.ps1 -Test` 运行有接线的原生/进程套件。独立进程检查示例（末尾必须是实际 CLI 启动命令）：

```bash
python3 CLI/Tests/smoke.py --backend windows -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/nbt_conversion_smoke.py -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/block_entity_smoke.py --fixture-tool CLI/build/native-tests/mcbe_cli_create_test_db -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/dimension_smoke.py -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
dotnet run --project CLI/Windows.Tests -c Release -- CLI/build/native-tests/mcbe_cli_create_test_db
```

Linux 调用原生库需将 `Windows/Native/bin/x64` 加入 `LD_LIBRARY_PATH`。本轮 Linux Swift 编译因环境资源约束只在外部编译器 wrapper 使用 `-j 1`；产品构建脚本的并发设置未改。

## 平台边界与交付

本环境没有 Xcode/iOS SDK、Windows GUI runtime 或 Minecraft。未完成 Apple/iOS 原生编译、真机地图触摸/菜单、Windows GUI 实际操作、两个 Windows FileShare 场景及游戏读档；源码接线、交叉编译和 headless 方法测试分别记录，不替代这些验收。既有 structure 普通实体复制与 save/load layer0/layer1 等范围未扩大，见 [命令对照](../../CLI/Docs/COMMAND_PARITY.md)。

完整包包含所有原始 860 个文件、修复源码、可复跑测试及本轮记录。`package-content-check.json` 核对六份 ReadMe/版本元数据/原样例未变、无误删；`files.sha256` 记录本轮变化文件和证据哈希。ZIP 交付前完成 CRC 与全部跟踪文件字节校验，并排除编译缓存、外部工具链和本地工作区元数据。
