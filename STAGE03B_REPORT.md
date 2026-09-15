# MCBEEditor CLI stage03b 说明

日期：2026-09-15。范围：仅 Windows 文件夹/mcworld 原位保存与另存为专项复核。状态：本轮源码修复、回归源码和静态检查完成；Windows 编译、真实 CLI/数据库运行尚未验证。

交付 `MCBEEditor-CLI-stage03b.zip` 为完整工程快照，包含 stage03a 找回的全部两端源码及本轮改动。独立 `MCBEEditor-CLI-stage03b-notes.md` 与本文件一致。程序版本沿用 `0.3.0-stage03`，没有生成最终单 exe 或 deb。

## 本轮修复

Windows 原位 mcworld 写入存在一处路径匹配问题：导入时会将 `./World/file`、`Wrapper/../World/file` 等路径规范化到实际世界目录，但保存时曾直接用旧条目的原始名称匹配 `World/` 前缀。

因此，部分本属世界内部的旧条目会被当作外部文件保留。若该文件已从工作副本删除，原位输出仍可能把它带回；同一世界文件也可能出现不同路径写法的重复条目。

本轮统一规范化旧条目名称中的分隔符、`.` 和内部 `..`，再匹配世界根目录。世界部分由当前工作副本重建，外部条目仍按原名称复制。世界名匹配保留目录边界，`World2/` 不会被当作 `World/`；`db/LOCK` 仍不写回。导入时的越界路径拒绝逻辑保持原样。

同时将 Windows 取消提示补齐为“未导出或提交”，明确原位模式也不会提交已取消批次的结果。

## 文件改动

| 文件 | 改动及目的 |
| --- | --- |
| `CLI/Windows/CliInPlaceArchive.cs` | 规范化旧 ZIP 条目名称，避免路径别名导致旧世界文件遗留 |
| `CLI/Windows/CliWorldRunner.cs` | 补齐原位取消后的提示文字 |
| `CLI/Windows.Tests/Program.cs` | 新增 7 个保存/恢复场景；补成功原位保存后副本清理断言 |
| `CLI/README.md`、`CLI/Docs/COMMAND_PARITY.md` | 记录修复、当前验证状态与最新报告位置 |
| `CLI/Docs/STAGES.md`、`CLI/Shared/command-inventory.json` | 标记 stage03b 源码交付，下一轮改为 03c |
| `CLI/Validation/Stage03b/` | 保存本轮实际源码检查日志、代码变化范围和未运行项 |
| 根目录检查点、累计进度、本报告、快照清单 | 提供下一轮可直接恢复的状态 |

没有修改 Swift、GUI、原生桥、NBT 或区块持久化算法。本轮生产/测试代码仅上述 3 个 Windows CLI 文件变化。没有增加生产代码的故障注入接口；测试沿用输出观察方式，在临时测试目录制造明确冲突。

## 新增回归源码

这些用例通过实际 `CliApp.Run` 入口和现有真实 LevelDB 合成世界执行。下表描述的是待运行的断言，并非测试已通过。

| 场景名称 | 验证目标 |
| --- | --- |
| `in-place-archive-normalized-paths` | 使用 `./World/`、内部 `..`、重复分隔符的嵌套世界；从副本删除标记文件后保存并重新解压，检查旧文件不再出现，世界修改和外部文件保留 |
| `in-place-folder-cancel` | 当前命令完成后取消；源目录文件哈希不变、副本保留当前结果、后续命令不执行 |
| `in-place-archive-cancel` | 同样的取消边界；原 mcworld 字节不变，恢复副本保留 |
| `in-place-archive-source-change` | 命令执行期间由外部更新原归档；拒绝原位提交，保留外部版本与本批恢复副本 |
| `in-place-archive-publish-blocked` | 允许读取源归档但阻止替换，验证保存失败后原文件字节和恢复数据 |
| `save-as-publish-blocked` | 明确允许覆盖，但目标被占用而无法替换；原输出不变，新修改留在恢复副本 |
| `in-place-folder-move-blocked` | 在迁移前制造恢复目录名称冲突；原世界与冲突目录均不被覆盖，修改副本仍可恢复 |

归档路径回归删除的是测试标记文件，用于检查归档是否会恢复已删除文件；它不声称本轮已验证真实游戏的数据库压缩过程。

文件占用场景使用 Windows 文件共享规则允许读取而不允许删除共享，预期让最后替换步骤失败；依据为微软的 [FileShare 定义](https://learn.microsoft.com/en-us/dotnet/api/system.io.fileshare?view=net-10.0) 和 [File.Move 覆盖及访问失败说明](https://learn.microsoft.com/en-us/dotnet/api/system.io.file.move?view=net-10.0)。具体测试结果仍需 Windows 实际运行确认。

本轮还对现有源码进行了有限复核：命令执行器在返回结果前释放数据库；原位保存只在整批成功后进入；保存异常时会保留工作副本；文件夹第二次迁移失败会尝试恢复原目录。**目录第二次迁移失败、回滚再次失败及突然断电，本轮没有实际注入或运行验证**。新增目录冲突用例覆盖的是第一次迁移被拒绝，不能代替回滚测试。

## 实际验证结果

| 检查 | 本轮结果 |
| --- | --- |
| stage03a 恢复 | 490 条文件哈希、交付 ZIP SHA256 和 CRC 全部通过；491 个上一轮文件保留 |
| 原源码审计 | `source_audit.py`、`stage02_source_audit.py`、`stage03_source_audit.py` 全部通过 |
| 修改范围 | 生产/测试代码只改动上述 3 个文件，Swift 与共享核心算法未改 |
| 历史完整性 | 27 个历史报告、日志和清单与 stage03a 逐字节一致 |
| 测试接入 | 原有场景保留，新增 7 个命名场景；现有 `-Test` 构建入口会运行更新后的测试程序 |
| C# / PowerShell / 原生构建 | 未运行：当前没有 dotnet、csc/mono、CMake、PowerShell 或 Windows 工具链 |
| 新增与已有原生测试、真实解析输入、末地回归 | 未运行，未使用历史或静态日志代替 |
| Actions、游戏和设备读档 | 未运行 |

实际日志与机器可读结果位于 `CLI/Validation/Stage03b/`，其中 `change-scope.json` 列出源码变化和新增用例。本轮没有重跑无关的 Swift、shell 或工作流结构检查，也没有执行全量最终审计。

## 用法保持一致

以下是编译后的使用方式，本轮未执行：

```text
mcbe-cli --world "D:\Worlds\My World" --command "time set 6000" --in-place
mcbe-cli --world "D:\Worlds\My World.mcworld" --script "Commands\Command.txt" --in-place
mcbe-cli --world "D:\Worlds\My World.mcworld" --command "time set 6000" --output "D:\Output\Edited.mcworld"
```

`--in-place` 与 `--output` 互斥。修改命令必须选其一，纯查询可以不选。原位输入支持文件夹和 mcworld；普通 ZIP 仍需另存为 mcworld。另存为覆盖已有输出需 `--overwrite`，不能覆盖输入世界或命令文件。

两种方式均在工作副本执行。原位只在全部命令成功后提交；执行错误或命令边界取消时不提交本批结果并保留副本。另存为沿用“运行时出错后仍导出当前副本，返回失败并保留恢复副本”的行为。`--keep-work` 可保留成功后的副本。

请使用已关闭的世界或完整备份；源指纹不负责协调正在写入同一存档的游戏。文件夹提交仍包含两次目录移动，并非断电原子事务。成功和失败时的副本/恢复路径以程序实际输出为准。

## Windows 待运行的检查

```powershell
./CLI/Scripts/build-windows.ps1 -Test
```

需要 .NET 10 SDK、Visual Studio C++ 工具链、CMake 和 Python。也可在现有手动工作流 `CLI stage 03 in-place and Apple world checks` 中运行 Windows 检查任务。脚本会编译 CLI 和真实原生依赖，并运行进程/解析测试、选定原核心回归及更新后的集成测试。本轮没有连接远程仓库或触发该工作流。

若后续取得失败日志，应先修复具体编译或回归失败，再更新验证状态。静态检查不能代替 Windows 文件共享、目录迁移或实际 LevelDB 行为验证。

## 下一轮与恢复入口

下一轮只进行 **03c：Swift 保存和 Apple 原生构建专项复核**。先读 `WORK_CHECKPOINT.md`、本报告和 `CLI/Validation/Stage03b/results.json`，核验 `CLI/Shared/stage03b-files.sha256`，再读取：

1. `CLI/iOS/CliWorldWorkspace.swift`、`CliFileSystem.swift`、`CliWorldPaths.swift`、`CliWorldRunner.swift`。
2. `Sources/World/MiniZipArchive.swift`、`WorldSession.swift`。
3. `CLI/iOS.Tests/NativeIntegration.swift`。
4. `CLI/Scripts/build-apple.sh`、`bootstrap-apple-native.sh`、`CLI/Native/Apple/CMakeLists.txt` 和 `CLI/iOS/sources.txt`。

优先复核压缩包重建、文件路径、关闭数据库、源变化/保存失败处理和实际 Apple 构建输入；保留末地高层、255 storage 与真实桥接回归。不要顺带展开结构文件接口或持续交互会话。

后续仍按 04a 结构文件、04b 会话、04c 历史/行编辑、04d Command.txt、04e 两端对齐、05a Windows 单 exe、05b iOS deb、05c 最终审计推进。每轮只完成一个小断点并交付完整 ZIP 和说明。

不要重新解压第二版或 stage03a 覆盖本轮工程，不要删除旧产物，也不要把旧哈希清单用于当前快照。当前清单为 `CLI/Shared/stage03b-files.sha256`，不包含自身。Windows 原生运行缺口继续保留，不因进入 Swift 复核而自动视为完成。
