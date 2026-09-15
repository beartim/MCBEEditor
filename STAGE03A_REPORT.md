# MCBEEditor CLI stage03a 恢复核验说明

日期：2026-09-15。断点：03a，恢复第三次修改并保存完整进度。状态：恢复核验与静态检查完成；编译、原生运行及最终安装包尚未验证或完成。

## 恢复结论

第三次修改仍保留在工作区，未被第二版覆盖。开始核验时，相对第二版共有 31 个文件变化、16 个文件新增；第二版的 465 个文件全部存在。首先保存了检查前的完整恢复副本，再运行本断点检查。

用户本次上传的第二版 ZIP 与上一轮交付记录一致：

```text
SHA256: bea9a01e8541975c01e2a010cb490e209f941626943d9c3992ae4e6b5b4e96d1
```

第二版 ZIP 的 CRC 与内置 464 条文件哈希全部通过。找回的 47 个新增/修改文件均非空、UTF-8 解码正常，没有 NUL 字节或遗留合并冲突标记。未发现丢文件或明显截断迹象；这不等同于 C#/Swift 编译和功能验收通过。

本轮交付 `MCBEEditor-CLI-stage03a.zip`，包含可继续开发的完整工程、找回的第三次修改、本轮检查日志和最新续作记录。独立 `MCBEEditor-CLI-stage03a-notes.md` 与本说明内容相同。原始 GUI 工程仍在包内用于共享核心和对照；最终 CLI 功能范围仍只包括 GUI 的命令栏目。

## 找回的功能源码

| 范围 | 当前源码状态 |
| --- | --- |
| Windows 保存 | 新增 `--in-place`、源内容指纹、文件夹替换/回滚、保留 mcworld 原容器布局；另存为保留 |
| Swift 世界执行 | 参数、整批预检、路径检查、独立工作副本、原 WorldCommandExecutor 调用及退出状态已接通 |
| Swift 保存 | 文件夹/mcworld 原位提交、mcworld 另存为、关闭数据库、源变化检查与失败副本保留 |
| 共享 Swift 核心 | 为 WorldSession 隔离 GUI 状态；方块读取和 NBT 修改原语提取为共用类型 |
| 原生构建 | Apple CMake、固定依赖获取脚本、主机构建、iOS arm64 交叉编译入口及手动检查工作流已存在 |
| 测试源码 | 两端原位/另存为/冲突/恢复用例，Swift 真实 LevelDB 合成世界与末地样本测试已存在，尚未运行 |

两端程序版本沿用找回的 `0.3.0-stage03`；本次交付断点称为 **stage03a**，用于区分“已恢复并检查源码”和“完整阶段 03 已验收”。

## 原位保存和另存为用法

以下是源码定义的编译后用法；本轮没有在目标平台执行这些命令。

```text
mcbe-cli --world "D:\Worlds\My World" --command "time set 6000" --in-place
mcbe-cli --world "D:\Worlds\My World.mcworld" --script "Commands\Command.txt" --in-place
mcbe-cli --world "D:\Worlds\My World.mcworld" --command "weather clear 0" --output "D:\Output\Edited.mcworld"
```

iOS 终端使用对应文件路径，参数相同：

```sh
mcbe-cli --world "/var/mobile/Documents/My World.mcworld" --command "time set 6000" --in-place
mcbe-cli --world "/var/mobile/Documents/My World" --command "time set 6000" --output "/var/mobile/Documents/Edited.mcworld"
```

修改命令必须明确选择 `--in-place` 或 `--output`，两者互斥；纯查询可以不指定。原位模式支持文件夹和 `.mcworld`。普通 `.zip` 可以读取并另存为 `.mcworld`，当前不支持原位写回 ZIP。已有另存为输出默认不覆盖，需要额外指定 `--overwrite`；不能用另存为覆盖输入文件。

| 执行情况 | 原位模式 | 另存为模式 |
| --- | --- | --- |
| 全部命令成功 | 在副本执行完成后提交原路径 | 导出到指定 mcworld |
| 语法错误或暂未实现的结构文件操作 | 整批拒绝，不创建世界副本 | 同左 |
| 命令运行时错误 | 继续报告后续命令，但不提交本批结果；保留副本，返回 1 | 导出当前副本并明确提示包含部分结果；保留副本，返回 1 |
| 源内容在处理期间改变 | 拒绝提交，保留副本 | 原源文件不作为写入目标 |
| 命令边界取消 | 不提交，保留副本，返回 130 | 不导出，保留副本，返回 130 |
| 保存失败或输出冲突 | 报错并保留工作副本；目录回滚失败时报告旧世界路径 | 报错并保留工作副本 |

文件夹提交需要写入其父目录，先准备新目录，再暂存原目录并替换；替换失败时尝试回滚。两次目录移动并不是断电原子事务。mcworld 先生成完整新包再替换原文件；原位模式保留世界根目录层级、外部文件和编辑器私有文件内容，但不承诺 ZIP 条目属性逐字节不变。另存为沿用 GUI 的元数据过滤规则。

请处理已关闭的世界或完整备份。源内容指纹用于检测变化，不负责协调正在写入同一存档的游戏。失败后的工作副本路径会输出，可把它作为下一次 `--world` 输入继续处理或另存为。`--keep-work` 可在成功后保留副本。

## 本轮实际修改

本轮保留找回的生产源码和测试源码，没有继续展开大型重构或增加新命令功能。具体处理为：

- 修复 `CLI/README.md` 对尚不存在的阶段 03 报告的引用，指向本报告。
- 修复 `CLI/Docs/COMMAND_PARITY.md` 的验证目录引用，指向实际生成的 Stage03a 日志。
- 更新 `CLI/Docs/STAGES.md`，把后续工作拆成每轮一个小断点。
- 在命令清单中增加 stage03a 恢复状态，保留两端功能仍需编译/运行验证的标记。
- 新增 `CLI/Validation/Stage03a/` 的本轮结果和日志；覆盖最新 `WORK_CHECKPOINT.md`，只追加 `WORK_PROGRESS.md`，新增本报告和当前快照哈希清单。

找回的全部新增/变化文件列表见 `CLI/Validation/Stage03a/recovery-initial.json`。第三次修改的主要代码入口为 `CLI/Windows/`、`CLI/iOS/`、`CLI/iOS.Tests/`、`CLI/Native/Apple/` 和 `Sources/NBT/NBTTreeMutation.swift`；这些均包含在本次 ZIP 内。

## 验证事实

| 检查 | 结果与范围 |
| --- | --- |
| 第二版基线 | ZIP SHA256、CRC、464 条内部哈希通过；465 个文件全部保留 |
| 恢复文件 | 47 个新增/变化文本文件无空内容、NUL 或冲突标记 |
| 原始文件保留 | 409 个原始文件全部保留，累计有 17 个原文件发生过修改 |
| 重构正文 | 方块读取与 NBT 修改原语保持第二版正文；Swift 执行器仅有 4 处读取器类型引用变化 |
| 选定核心与历史 | 9 个命令/编解码/原生桥文件和 17 个历史报告、日志、清单与第二版逐字节一致 |
| 三项源码检查 | `source_audit.py`、`stage02_source_audit.py`、`stage03_source_audit.py` 全部通过 |
| 引用与覆盖清单 | 57 个 Swift 输入存在；项目内声明类型依赖、26 根命令及 135 条测试输入覆盖的静态检查通过 |
| 脚本语法 | 8 个 shell 脚本逐个通过 `bash -n`；4 个 Python 文件通过内存字节码编译 |
| 工作流结构 | 3 个 CLI 工作流 YAML 解析、手动触发和仓库只读权限配置检查通过；没有在 GitHub 执行 |
| C#/Swift/Objective-C++ 编译 | 未运行：缺少 dotnet、swiftc/Xcode、clang、CMake、PowerShell |
| 原生数据库、实际 CLI、135 条解析输入、末地回归 | 测试源码或输入已存在，但本轮未编译和执行 |
| iOS arm64 编译、设备/游戏读档 | 未运行 |

机器可读结果为 `CLI/Validation/Stage03a/results.json`，同目录保留实际日志。本轮是恢复和有限静态核验，没有执行阶段 05c 的全量最终审计。

## 构建入口和当前边界

Windows 待运行：

```powershell
./CLI/Scripts/build-windows.ps1 -Test
```

macOS/Xcode 环境待运行：

```sh
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
bash CLI/Scripts/build-apple.sh ios CLI/build/apple-ios
```

现有手动工作流为 `CLI stage 03 in-place and Apple world checks`。它是检查流程，当前不生成最终单 exe/deb 发布产物。本轮没有连接仓库或运行远程工作流。已有脚本沿用固定的 leveldb-mcpe 0.8.0a8、zlib 1.3.1 依赖；Apple 工作流配置的 Xcode 路径和构建结果仍需实际运行确认。

尚未完成：structure 的终端文件导入/导出、持续交互会话、历史和行编辑、自动检测 Command.txt、两端解析差异对齐，以及最终 Windows 单 exe / iOS arm64 deb 打包。Swift 压缩包处理仍继承 MiniZipArchive 的大小和内存限制，没有在本恢复断点改造大世界流式导出。

## 后续小断点

| 断点 | 范围 |
| --- | --- |
| 03b（下一轮） | 只复核 Windows 文件夹/mcworld 原位保存与另存为，处理明确问题和相关回归 |
| 03c | Swift 对应保存、真实原生构建与相关回归复核 |
| 04a | structure 文件导入和三格式导出 |
| 04b | 持续会话与 :open/:save/:quit |
| 04c | 历史、方向键、清屏、颜色 |
| 04d | Command.txt 与 Commands 目录 |
| 04e | 两端解析边界和结果对齐 |
| 05a | Windows 单 exe 构建与发布 |
| 05b | iOS arm64 deb 构建与发布 |
| 05c | 全量最终审计、清理和最终报告 |

每轮交付完整进度 ZIP、说明、最新检查点及追加进度，不必一次完成上表全部内容。单项仍过大时继续细分，不以剩余额度估算代替主动保存。

下轮先读取 `WORK_CHECKPOINT.md`、本报告和 `CLI/Validation/Stage03a/results.json`，再依次查看：

1. `CLI/Windows/CliWorldPaths.cs`、`CliRunOptions.cs`、`CliWorldRunner.cs`。
2. `CLI/Windows/CliWorldSession.cs`、`CliSourceStamp.cs`、`CliInPlaceArchive.cs`。
3. `Windows/MCBEEditor.Core/World/PortableWorldWorkspace.cs`。
4. `CLI/Windows.Tests/Program.cs`、`WorldFixture.cs` 和 `CLI/Scripts/build-windows.ps1`。

后续实现持续会话时，必须处理每次成功原位保存后的源内容指纹更新；当前执行入口是一次性批处理，不能直接把现有指纹生命周期用于多次 :save。

不要用第二版覆盖当前工程，不要删除上一轮有效产物，不要重新盘点已经确认的命令清单，也不要把历史静态检查当作新一轮真实运行结果。当前快照校验清单是 `CLI/Shared/stage03a-files.sha256`，不包含清单自身；stage01/stage02 清单只校验其对应历史包。
