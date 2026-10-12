# setblock / fill 方块实体自动坐标（2026-10-11）

四端同步：iOS GUI、Apple/iOS CLI、Windows GUI、Windows CLI。软件版本仍为 1.0.0，iOS 最低版本仍为 13.0。基线为上一轮完整 iOS 编译修复源码包，844 个文件全部保留。

方块实体模板的根 x/y/z 可省略，输入时按不区分大小写的名称忽略。每个目标位置都写入唯一的小写 Int 类型根 x/y/z；fill 使用闭合区域内各位置的实际坐标，支持反向两角和跨区块。嵌套坐标、Pos、其他标签的值、类型和相对顺序保留。完整语法见 [命令说明](../FillSetblockBlockEntity/README.md)；示例已改为省略根坐标。

| 本轮检查 | 结果 | 日志 |
| --- | --- | --- |
| Swift / C# 修复前回归 | 按预期失败：没有根 x 坐标的模板被旧实现拒绝 | `logs/swift-red.log`、`logs/csharp-red.log` |
| Swift / C# 修复后专项 | PASS：全部或部分省略、不一致值、非整数和越界 Long、大小写别名、唯一 Int 坐标、嵌套保留、Byte 输入不限制 fill | `logs/swift-focused.log`、`logs/csharp-focused.log` |
| Swift 全量核心测试 | PASS：262 个共享 parser 用例；新命令回归、原子失败、三种模式及既有回归；1740 个地图命中/锚点检查、98 项源审查 | `logs/swift-full.log` |
| C# 全量核心 SelfTest | PASS：新回归及既有命令、存储、维度和 MCBE-SNBT 回归 | `logs/csharp-full.log` |
| Windows CLI / 原生集成测试编译 | PASS：均为 0 warnings、0 errors | `logs/windows-cli-build.log`、`logs/cli-tests-build.log` |
| Windows GUI 交叉编译 | PASS：0 warnings、0 errors；只计编译 | `logs/windows-gui-build.log` |
| 实际 .NET CLI parser / help | PASS：324 次进程调用，262 个 parser 用例，28 类命令 | `logs/cli-parser.log` |
| 实际 .NET CLI 方块实体保存、重开 | PASS：19 次进程调用；省略/忽略根坐标、72 个跨区块位置逐一核验、嵌套和 Pos 保留、三种模式、任意 id、源存档不变及预检拒绝 | `logs/cli-entities.log` |
| Mojang LevelDB 原生 CLI 集成 | PASS：44 个主调用；POSIX 不支持的两个 Windows FileShare 场景由测试明确 SKIP | `logs/cli-native.log` |
| 四套固定 Commands ReadMe 的实际写入 | PASS：固定快照一致、运行时 help 改变不影响 ReadMe、恢复固定文本、用户 Command.txt 原字节保留 | `logs/fixed-readme.log` |
| 帮助与命令路由 / 构建契约 | PASS：28 类命令、67 个 Swift 编译输入、固定帮助匹配及 Apple 构建失败保留旧二进制的源/替身检查 | `logs/source-build-audit.log` |
| 独立只读审查 | 未发现 Critical / Important；可选测试补强建议已记录 | [REVIEW.md](REVIEW.md) |

Swift 工具链为官方 5.10.1，.NET SDK 为官方 10.0.401。Swift 命令测试编译生产 parser/executor，使用测试存储；.NET CLI 保存重开使用按既有配置编译的 pinned Mojang LevelDB 0.8.0a8 / zlib 1.3.1 原生桥。

```bash
bash Scripts/run_core_tests.sh
dotnet run --project Windows/MCBEEditor.Core.SelfTest -c Release -- --fill-setblock-block-entity
dotnet run --project Windows/MCBEEditor.Core.SelfTest -c Release
dotnet build CLI/Windows/MCBEEditor.Cli.csproj -c Release -m:1 -p:UseSharedCompilation=false
dotnet build CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj -c Release -m:1 -p:UseSharedCompilation=false
dotnet build Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj -c Release -p:EnableWindowsTargeting=true -m:1 -p:UseSharedCompilation=false
python3 CLI/Tests/smoke.py --backend windows -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/block_entity_smoke.py --fixture-tool CLI/build/native-tests/mcbe_cli_create_test_db -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
dotnet CLI/Windows.Tests/bin/Release/net10.0/MCBEEditor.Cli.Tests.dll CLI/build/native-tests/mcbe_cli_create_test_db
python3 Scripts/test_fixed_readme.py
python3 CLI/Tests/source_audit.py
```

Linux 原生集成先按 Windows/Native/CMakeLists.txt 编译 LevelDB 原生桥和 fixture tool，并将 Windows/Native/bin/x64 加入 LD_LIBRARY_PATH。Apple 环境可用同一个 block_entity_smoke.py 验证 Apple CLI；本轮未运行 Apple 原生 CLI、iOS/UIKit 真机或 Windows GUI，也未进行游戏内加载。

四份 Commands/ReadMe.txt 及其生产静态常量有意更新，仍是固定文本，不在运行时生成。两份 Textures/ReadMe.txt、示例维度存档、上一轮 iOS 地图菜单修复及 CoreGraphics 导入修复保持原字节。原有 preserve/empty、任意 id、未指定类型的空 List、安全定位已有记录和一次 WriteBatch 的原子提交规则均保留。

先前验证日志为历史记录；本轮自动坐标行为及测试结果以本文件和本目录日志为准。
