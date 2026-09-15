# MCBEEditor CLI 阶段 01 交付说明

本轮完成第 1 个断点：命令盘点与 CLI 基础工程。当前源码提供两端的帮助、命令列表和语法预检入口；整个 CLI 移植尚未完成，当前不能编辑或导出存档，也还没有最终 deb 或单 exe 发布流程。

## 五个断点

| 阶段 | 内容 | 当前状态 |
| --- | --- | --- |
| 01 | 26 个命令清单、两端 CLI 入口、帮助与语法预检 | 本轮完成源码与可用检查；编译未验证 |
| 02 | Windows 命令执行、世界工作副本、存档导出 | 下一阶段 |
| 03 | iOS 命令执行、原生 LevelDB、工作副本和导出 | 待完成 |
| 04 | 两端交互终端、历史清屏、完整批处理、结构文件路径操作和功能对齐 | 待完成 |
| 05 | GitHub Actions Windows 单 exe 与 iOS arm64 deb、最终审计 | 待完成 |

## 本轮实际成果

已确认原源码的 26 个顶级命令及其全部子命令范围，包含 kick、experience percent、weather query、structure query/import/export 等。新增 command-inventory.json 和命令对照说明，标出后续每项执行功能的接入阶段。

Windows 新增独立 net10.0 控制台工程，调用原来的七类命令解析器；帮助文本直接引用原帮助目录。iOS 新增 Swift CLI 入口，使用原 WorldCommandParser，并提供 macOS 主机测试构建脚本及 iOS arm64 交叉编译脚本。两端 CLI 的构建输入均不包含 GUI 窗口依赖。

当前入口支持 --help、--help 命令、--list-commands、--version、--check 完整命令、--check-file 路径，以及 --check-file - 从标准输入读取。命令文件支持严格 UTF-8、BOM、LF/CRLF/CR、忽略空行和实际错误行号；预检不修改命令文件、不打开存档、不执行命令。

已准备 135 条实际解析器测试输入，覆盖所有顶级命令、嵌套 NBT、255/256 storage 边界、错误参数及已知大小写差异。CLI/Tests/smoke.py 会在真实程序编译后运行这些输入，并检查退出码、标准输出/标准错误、中文路径、编码和原文件不变等行为。这些运行测试本轮没有执行。

原 ZIP 的 409 个源码和附带文件全部保留。仅修改了 Windows/MCBEEditor.Desktop/CommandHelpCatalog.cs，增加只读 Names 接口供 CLI 输出原命令顺序；原帮助内容未改。其余为新增 CLI 工程、检查脚本、用例、说明和检查点。没有删除原文件，也未重新实现或修改原 NBT、LevelDB 和命令语法核心。

## 验证结果

| 验证 | 结果 |
| --- | --- |
| 26 个命令、两端帮助目录、CLI 解析路由与清单一致 | 通过 |
| Windows 工程引用及 Swift 17 个构建输入完整，无 GUI 框架依赖 | 通过 |
| 135 条测试输入覆盖所有命令与关键边界 | 覆盖检查通过，输入的运行结果未验证 |
| 新增 Python 脚本语法 | 通过 |
| 两个新增 bash 构建脚本语法 | 通过 |
| 新增 GitHub Actions YAML 结构 | 通过 |
| 与原 ZIP 对照的文件完整性 | 通过，409 个原文件保留，仅 1 个原文件有上述修改 |
| C# 和 Swift 编译、真实 CLI 测试输入运行 | 未验证，当前环境没有 dotnet 或 swiftc |
| iOS arm64 链接、签名、deb 安装和 Windows 单 exe | 未验证；最终打包在阶段 05 |
| 真实存档写入、导出和游戏内读取 | 未验证；执行功能尚未接入 |

验证日志保存在 CLI/Validation/Stage01。原包 Validation 目录中的日志是历史资料，未计入本轮验证。

## 需要继续处理的事项

结构 import/export 的原实现调用 GUI 文件协调器，后续必须补齐 CLI 路径、结构选择、覆盖文件和格式行为。现在这些命令只能预检语法，帮助中窗口描述仍是原 GUI 功能说明。

Windows 多数命令大小写不敏感，Swift 大多数命令要求小写；部分坐标类型也存在 Int32/Int64 差异。本轮如实记录，后续对齐时处理，不能宣称目前两端完全等价。

当前包包含用于对照和复用的完整 GUI 基线，CLI 构建并不引用 GUI 工程。原 GUI 工作流也仍保留；最终 CLI 发布入口和无用对照内容的清理将在阶段 05 统一处理。

## GitHub Actions 与当前用法

如果需要提前检查本轮源码，可手动运行新增工作流 CLI stage 01 parser checks。它只负责阶段检查，不生成最终安装包；本轮没有触发或读取远程 Actions 结果。等全部源码阶段完成后再运行最终打包流程，也符合本任务安排。

完整本地构建及预检命令见 CLI/README.md。例如，编译后可运行：

```text
mcbe-cli --help structure
mcbe-cli --check "weather query"
mcbe-cli --check-file "Commands/Command.txt"
```

## 下一轮准确入口

继续任务时先读取根目录 WORK_CHECKPOINT.md、WORK_PROGRESS.md，确认检查点列出的实际文件和快照校验文件存在。不要重新解压原 ZIP 覆盖现有进度，不要重做已确认完成的命令盘点。

先检查可用的 dotnet/Swift 工具链或用户补充的阶段检查日志，补做能执行的编译门禁；缺少工具链则保留未验证状态。接着从阶段 02 开始：抽出 Windows MainWindow.xaml.cs 的命令执行调度，接入 PortableWorldWorkspace 和 WorldDocument，完成查询、修改、关闭数据库及导出 mcworld 的链路。

首先查看 CLI/Windows/CliCommandParser.cs、CLI/Windows/Program.cs、Windows/MCBEEditor.Desktop/MainWindow.xaml.cs、Windows/MCBEEditor.Core/World/PortableWorldWorkspace.cs、Windows/MCBEEditor.Core/World/WorldDatabaseAbstractions.cs，以及 CLI/Docs/STAGES.md。

## 交付内容

MCBEEditor-CLI-stage01.zip 是当前完整可恢复源码，解压后根目录为 MCBEEditor-CLI。WORK_CHECKPOINT.md 记录本轮完整状态和下一阶段步骤，WORK_PROGRESS.md 保存累计历史。CLI/Shared/stage01-files.sha256 记录阶段快照文件的 SHA256，用于解压后核对内容；校验清单不包含它自身。

本说明另附为 MCBEEditor-CLI-stage01-notes.md，ZIP 内也有 STAGE01_REPORT.md。原输入 ZIP 的 SHA256 为 7794b4db43827a530fbdee62aae860516e00f1ab12276bece5b10de53aed5246。

本轮按用户要求停在阶段 01。下次发送“继续任务”即可从检查点进入阶段 02，不需要重新说明任务。
