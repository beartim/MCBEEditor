# 验证记录（2026-10-11）

基线为最后交付的空 List 修复源码包，806 个文件完整恢复后在独立 git 工作区修改。工具链使用官方 Swift 6.2.3、.NET SDK 10.0.401 和 pinned Mojang LevelDB；未改软件版本或最低 iOS 版本。

| 检查 | 结果 / 覆盖 | 记录 |
| --- | --- | --- |
| C# 全核心 SelfTest | PASS；包括新增三种模式、用户示例、任意 id、反向范围、72 位置跨区块、自定义维度、原子失败、辅助 Pos、歧义坐标和 VarInt peer 回归 | `logs/csharp-core.log` |
| Swift 全量核心回归 | PASS；新增三种模式、重复 preserve/empty 无变化、72 位置跨区块、原子失败与 258 个共享 parser 样例；全部既有核心回归及 98 项源审查通过 | `logs/swift-core-full.log` |
| Windows CLI 编译 | PASS，0 warnings / 0 errors | `logs/windows-cli-build.log` |
| Windows GUI 交叉编译 | PASS，0 warnings / 0 errors；使用 EnableWindowsTargeting，只计编译 | `logs/windows-gui-build.log` |
| 实际 Windows CLI parser/help 检查 | PASS，320 次进程调用、258 parser 样例、28 类命令 | `logs/cli-parser-smoke.log` |
| 实际 CLI 方块实体保存重开 | PASS，17 次进程调用；完整用户示例、任意 id、72 个目标坐标逐一核验、三种模式、Pos、原存档不变和预检拒绝 | `logs/cli-block-entities.log` |
| Mojang LevelDB 全原生 CLI 集成 | PASS，44 个主调用；含 summon/entity、10 项结构 TXT 回归；两项 Windows FileShare 场景在 POSIX 明确 SKIP | `logs/cli-native.log` |
| CLI 持续会话 | PASS，14 个场景 | `logs/cli-session.log` |
| 示例维度存档实际检查 | PASS，27 次调用；生命周期、自定义名称、原版维度重建、导出重开、原存档保持 | `logs/cli-dimension.log` |
| 固定 ReadMe 实际文件写入 | PASS，四个 Commands 生产组件写出固定快照，修改 help 不影响输出，保留 Command.txt 原字节 | `logs/fixed-readme.log` |
| 命令路由、源文件、构建生命周期 | PASS，28 类命令、67 个 Swift 构建输入、双端帮助匹配、iOS 13.0/构建失败保留旧二进制契约 | `logs/source-build-audit.log` |

## 可重跑命令

```bash
dotnet build Windows/MCBEEditor.Core.SelfTest -m:1 -p:BuildInParallel=false -p:UseSharedCompilation=false
dotnet Windows/MCBEEditor.Core.SelfTest/bin/Debug/net10.0/MCBEEditor.Core.SelfTest.dll
dotnet Windows/MCBEEditor.Core.SelfTest/bin/Debug/net10.0/MCBEEditor.Core.SelfTest.dll --fill-setblock-block-entity
bash Scripts/run_core_tests.sh
dotnet build CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj -m:1 -p:BuildInParallel=false -p:UseSharedCompilation=false
dotnet build Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj -p:EnableWindowsTargeting=true -m:1 -p:BuildInParallel=false -p:UseSharedCompilation=false
python3 CLI/Tests/smoke.py --backend windows -- dotnet CLI/Windows/bin/Debug/net10.0/mcbe-cli.dll
python3 CLI/Tests/block_entity_smoke.py --fixture-tool CLI/build/native-tests/mcbe_cli_create_test_db -- dotnet CLI/Windows/bin/Debug/net10.0/mcbe-cli.dll
python3 Scripts/test_fixed_readme.py
python3 CLI/Tests/source_audit.py
```

Linux 原生集成需要先按既有 CMake 配置编译 Mojang LevelDB 和 fixture tool，并把 `Windows/Native/bin/x64` 加入 LD_LIBRARY_PATH。Apple CLI 可在 Apple 环境用同一个 `block_entity_smoke.py` 检查实际可执行文件。

## 失败复现和审查

- C#、Swift 在修改前均实际接受缺少末尾参数的命令，新增断言失败：`csharp-required-red.log`、`swift-required-red.log`。
- 审查发现 Windows 原通用定位器优先 Pos；增加冲突 Pos 测试后实际失败，再切换两端命令层为唯一整数根 x/y/z 定位：`csharp-pos-red.log`。
- 重复 preserve/empty 在原 Swift 行为中误报“区域内没有产生任何方块变化”；新增回归实际失败后改为成功的无变化结果，不标记存档已修改：`swift-noop-red.log`。
- 两个审查问题（Pos 定位、iOS 原生集成旧语法）均已修正并经第二次只读审查确认；重复命令无变化处理与 Windows 自定义维度格式化也经补充审查确认，未发现新的 Critical/Important。
- 新 Swift VarInt peer 测试最初少写 try，修正后专项重编及全部尾段回归通过。这是测试编译修正，不是生产逻辑失败。

上述 `*-red.log` 为修复前预期失败记录，不是最终测试结果。

## 保留范围与平台限制

`Tests/Fixtures/custom_dimensions.mcworld` 保持 SHA256 `b2b229bc4cc8c9937da461c08b5117501b12bb38791599eca5a6c7b6f63bdcd4`；两份 Textures/ReadMe.txt 保持原字节。四份 Commands/ReadMe.txt 有意更新，仍为生产静态常量。先前各轮验证日志保持历史原内容，本轮结果以本目录为准。

Swift 命令回归直接编译生产 parser/executor，使用测试存储；Windows CLI 使用实际 Mojang LevelDB。当前环境不能运行 iOS/UIKit 真机、Apple 原生 CLI 或 Windows GUI，未把共享核心测试或交叉编译称作这些平台的运行验证。游戏内加载也未实测；任意 id 与不匹配方块类型的原样写入遵循用户明确要求。
