# MCBEEditor CLI 阶段 02 说明

日期：2026-09-14。阶段：Windows 命令执行与存档导出。状态：源码与阶段静态检查完成；编译、真实数据库执行和游戏内验证未完成。

本轮交付完整可续作源码包 `MCBEEditor-CLI-stage02.zip`，不是差异包。包含上一阶段全部内容、本轮源码、测试、检查日志以及最新断点记录。独立说明 `MCBEEditor-CLI-stage02-notes.md` 与本文件内容相同。上一阶段 ZIP 保留。

## 本轮完成的功能源码

Windows CLI 从 `0.1.0-stage01` 更新为 `0.2.0-stage02`。26 个根命令均有执行调度入口；structure 的 query/save/load/delete 接入原业务类，import/export 的终端文件接口按既定计划留到阶段 04，当前执行模式会明确拒绝。iOS 保持阶段 01 的帮助与语法预检入口。

| 功能 | 当前实现 |
| --- | --- |
| 世界输入 | 文件夹、mcworld、ZIP；先建立独立工作副本 |
| 单条/连续命令 | `--command` 可重复；沿用原始七类解析器和请求类型 |
| 批量脚本 | `--script 文件` 或 `--script -`；UTF-8/BOM、原始行号、整批预检 |
| 命令调度 | 方块、storage、生物群系、玩家/实体、天气时间、常加载区、结构、区块、世界信息和帮助 |
| 世界输出 | 修改必须指定 `--output 文件.mcworld`；数据库关闭后导出 |
| 输出冲突 | 默认拒绝已有输出；`--overwrite` 显式替换输出，仍禁止覆盖输入 |
| 恢复 | 命令错误、最终导出失败或取消时保留副本并输出恢复路径 |
| 取消 | Ctrl+C 等当前命令结束后停止后续命令；退出码 130 |
| Windows 构建 | PowerShell/CMD 入口构建原生 DLL 和 CLI；可带 `-Test` |
| 阶段工作流 | 手动运行的 Windows 编译、解析器和存档集成测试检查 |

原存档操作直接复用各 CommandStore、WorldInfoService、WorldDocument 和存档导出服务。没有另写简化版 NBT 解析器或假数据库来代替生产路径。测试专用的原生工具创建空 LevelDB；生产数据库打开逻辑仍要求数据库已经存在。

## 使用示例

以下为编译后的用法，本轮环境没有实际运行这些命令：

```text
mcbe-cli --world "D:\Worlds\My World" --command "info" --command "weather query"
mcbe-cli --world "D:\Input\My World.mcworld" --command "time set 6000" --output "D:\Output\Edited.mcworld"
mcbe-cli --world "D:\Input\My World.zip" --script "CLI\Examples\EditCommands.txt" --output "D:\Output\Edited.mcworld"
```

`--command` 与 `--script` 不能混用。命令文件没有注释语法；复杂 NBT 建议放在文件中。默认副本位置为程序旁 `Cache/Worlds`，可用 `--cache-dir` 指定可写目录。完整参数与退出码见 `CLI/README.md`。

语法或当前不可执行的命令会在创建副本前拒绝整批。运行时错误逐条报告并继续；如果有输出路径，仍导出发生错误后的当前副本，返回 1 并保留副本。多条命令不是一个事务，出错命令可能已经写入部分数据。输出和恢复消息明确区分这种结果与全部成功。

正常成功并导出后会清理副本，`--keep-work` 可保留。恢复时把输出的工作副本目录作为新一次 `--world` 输入，再选择新输出路径。不会自动清空旧缓存。正常运行也会在标准错误输出副本路径，请按退出码判断成功。

## 对原核心的必要调整

| 文件 | 本轮改动及目的 |
| --- | --- |
| `Windows/MCBEEditor.Core/World/PortableWorldWorkspace.cs` | 先校验再创建缓存，避免拒绝请求仍写入源世界；复制时拒绝链接、跳过 db/LOCK，并只解除副本文件的只读属性 |
| `Windows/MCBEEditor.Core/World/WorldToolStores.cs` | 给导出方法增加可选临时目录参数；CLI 使用明确路径，避免继承 GUI 缓存变量后写入源世界；原 GUI 调用保持原默认逻辑 |
| `Windows/Native/CMakeLists.txt` | 增加默认关闭的合成数据库测试工具目标；普通生产构建无需该工具 |
| `Windows/MCBEEditor.Core.SelfTest/Program.cs` | 新增 `--cli-regression`，选择运行与本阶段直接相关的原有三组回归；原默认完整自检入口保留 |

409 个原始文件全部保留，相对上传基线共有 5 个文件变化：上述 4 个，加上阶段 01 已有的 `CommandHelpCatalog.cs` 命令名称接口。没有删除原源码。本轮没有修改 Swift 源码及原始持久化算法。

## 验证事实

| 门禁 | 本轮结果 |
| --- | --- |
| 26 命令清单、两端帮助、七类 Windows 原解析器接线 | 通过源码检查 |
| 22 个具体请求及其他命令族的执行路由、项目引用、原生测试接线 | 通过源码检查 |
| 135 条共享解析输入的覆盖清单 | 通过静态检查；尚未执行这些输入 |
| 三个 Python 检查脚本的语法 | 通过 |
| 两个阶段 GitHub Actions 的 YAML 结构及手动触发配置 | 通过结构检查；未在 GitHub 运行 |
| 原文件保留、允许改动范围、Swift 与历史验证日志完整性 | 通过文件哈希检查 |
| Windows .NET、原生 LevelDB、测试工具编译 | 未运行：没有 dotnet、CMake 或 Windows C++ 工具链 |
| PowerShell/CMD 构建脚本执行 | 未运行：没有对应运行环境 |
| 真实 CLI 进程/解析器测试、原核心三组回归 | 未运行：需要编译后的程序 |
| 原生合成世界集成测试 | 已写入测试源码，未编译/运行 |
| Swift/macOS/iOS 编译、真实游戏和设备读档 | 未运行；Swift 执行工作从阶段 03 开始 |

机器可读结果在 `CLI/Validation/Stage02/results.json`，实际日志位于同目录。阶段 01 的日志保持历史原样，没有把旧测试日志当作本轮结果。尚未进行阶段 05 的全量最终审计。

新增原生集成测试会验证：原世界与命令文件不变；完整命令族执行；导出重新打开；天气缺省值；末地未生成高层子区块；v8 与 255 storage；重叠 clone；结构 save/load/delete；玩家整数 Y 的 1.62 偏移；未知数据库记录保留；语法整批拒绝；运行时错误继续；输出文件竞争；取消；只读源文件；继承缓存环境变量；压缩包嵌套世界根目录及越界路径拒绝。这是待运行的测试覆盖说明，不是通过声明。

## 如何在 Windows 或 Actions 运行门禁

需要 .NET 10 SDK、CMake、Visual Studio C++ 工具链，测试另需 Python。原生依赖沿用上传源码中的固定版本 bootstrap。

```powershell
./CLI/Scripts/build-windows.ps1 -Test
```

GitHub Actions 中手动运行 `CLI stage 02 Windows world checks`。本轮没有连接仓库或运行远程工作流；如后续有构建失败日志，应先修复具体编译/回归问题再以其结果更新验证状态。

当前构建输出为需要 .NET 10 x64 运行时及同目录依赖的 `mcbe-cli.exe` 程序目录。最终 Windows 单 exe、iOS arm64 deb、签名及安装布局将在阶段 05 完成；当前 ZIP 不含已构建的最终安装包。

## 仍未完成与使用边界

- iOS 世界命令执行、LevelDB 会话和世界导出：阶段 03。
- 交互终端、历史方向键、清屏、自动检测 Command.txt、颜色输出、structure 文件导入导出及跨端差异：阶段 04。
- 最终打包、实际 Actions 产物检查及一次全量最终审计：阶段 05。
- 符号链接及目录联接输入暂不支持；使用实际路径。大命令和复制/导出不会被强行中断。
- 使用已经关闭的世界或完整备份；并发被游戏写入的源数据库不能保证复制一致性。
- 本阶段编译与运行缺口明确保留，不能认定两个目标平台或游戏内读档已经验证。

## 下一轮恢复入口

先读根目录 `WORK_CHECKPOINT.md` 和 `WORK_PROGRESS.md`，再看本报告。继续阶段 03 时首先读取：

1. `CLI/iOS/CliMain.swift`、`CLI/iOS/CliCommandFile.swift`、`CLI/iOS/sources.txt`。
2. `Sources/Command/WorldCommandExecutor.swift`。
3. `Sources/World/WorldSession.swift`、`WorldDocument.swift`、`WorldStore.swift`、`MiniZipArchive.swift`。
4. `Sources/LevelDB/MojangLevelDB.swift` 和原有 iOS 依赖构建脚本。
5. `CLI/Windows/CliWorldRunner.cs`、`CliWorldSession.cs`、`CLI/Windows.Tests/Program.cs`，作为本轮参数、失败恢复及持久化边界的参考。

下一步先拆出可无 UI 使用的 Swift 会话环境，再接入同一命令执行器和文件系统链路；保留已有末地缺失子区块回归，提供阶段 03 验证记录和完整进度 ZIP。本轮在阶段 02 停止，不继续展开阶段 03。

不要重新解压原 ZIP 覆盖进度，不要重新清点 26 个命令，不要删除唯一有效的旧 ZIP，不要把 `stage01-files.sha256` 当作当前快照。当前快照校验文件是 `CLI/Shared/stage02-files.sha256`，不包含其自身哈希。
