# MCBEEditor CLI 累计进度

## 2026-09-14 阶段 01 实施前检查点

已读取断点规则并保存原始源码，完成 26 个命令的入口定位。确定五阶段边界。本轮目标为可脱离 GUI 编译的帮助和预检工具；当前未完成 CLI 工程或编译。采用每个阶段主动保存的方式，不猜测 Work 剩余额度。

## 2026-09-14 阶段 01 工程落盘与验证检查点

新增两端 CLI 帮助及预检工程，直接复用原 Swift 解析器和 C# 七类解析器。命令文件支持 UTF-8/BOM、三类换行、原始行号和全部错误报告。新增共享 26 命令清单、135 条解析输入、真实进程烟雾测试脚本、构建脚本和手动 GitHub Actions 检查流程。

源码覆盖与无 GUI 构建输入检查通过；Python、bash 和 YAML 结构检查通过；409 个原文件保留，仅原帮助目录新增 Names 接口。dotnet、swiftc、Xcode 和设备均不可用，编译、运行及实机行为明确未验证，未使用历史日志代替。

## 2026-09-14 阶段 01 交付检查点

已整理 CLI/README.md、阶段说明和命令对照；更新 WORK_CHECKPOINT.md，新增 STAGE01_REPORT.md 和阶段文件校验清单。交付名称为 MCBEEditor-CLI-stage01.zip 与 MCBEEditor-CLI-stage01-notes.md。停止本轮，阶段 02 从 Windows CLI 执行调度、工作副本和导出链路开始；未提前启动新的大型阶段。

## 2026-09-14 阶段 02 恢复检查点

已读取检查点并核对阶段 01 的 438 条文件哈希，完整匹配。前一轮 ZIP 保留。当前仍没有 dotnet、Swift 或 Xcode；不重复安装失败的工具链，不将未验证门禁标成通过。已定位 GUI 命令调度、WorldDocument、PortableWorldWorkspace、WorldArchiveService 与原生 LevelDB，开始 Windows 执行和导出阶段。

## 2026-09-14 阶段 02 中间检查点 A

独立 Windows 执行器、批量预检、参数解析、工作副本生命周期和受控导出已落盘。所有命令复用原业务类，structure import/export 仍按计划保留至阶段 04。核心工作副本复制修复了先创建嵌套缓存才拒绝的问题，并拒绝链接、使工作副本中的只读文件可写。编译和运行未验证，接着补集成验证工程。

## 2026-09-14 阶段 02 中间检查点 B

Windows 原生 LevelDB 合成世界测试、选择性原核心回归入口、PowerShell/CMD 构建脚本、手动阶段检查工作流已落盘。源码检查初次通过，尚未编译或运行。已复查所有执行器调用，并修正导出服务继承 GUI 缓存环境变量可能把临时文件写入源世界的问题；CLI 显式指定临时目录，GUI 调用保持原默认行为。正在记录最终静态检查结果、更新文档和生成阶段 02 完整快照；不要启动阶段 03。

## 2026-09-14 阶段 02 验证与交付检查点

Windows 命令执行、批量预检、工作副本、mcworld 导出和失败恢复源码完成；structure 文件接口仍留到阶段 04。新增原生合成世界集成测试、PowerShell/CMD 构建入口和手动检查工作流。命令清单已标记两端真实阶段状态，Windows 为 0.2.0-stage02，Swift 保持 0.1.0-stage01。

实际通过源码覆盖/执行接线、Python 语法、YAML 结构和基线哈希检查。409 个原文件均保留，相对原始上传的 5 个差异中，1 个来自阶段 01、4 个为本阶段必要核心/构建/测试接入。Swift 源码和历史检查记录保持不变。没有 dotnet、CMake、PowerShell、Swift/Xcode，编译、真实进程、原生数据库和设备测试均标为未运行，详见 CLI/Validation/Stage02/。

已整理 README、命令对照、STAGE02_REPORT.md 和本轮检查点。交付名称为 MCBEEditor-CLI-stage02.zip 与 MCBEEditor-CLI-stage02-notes.md，采用完整源码快照，保留上一轮产物。生成 stage02-files.sha256 后打包并核对归档字节。本轮停止在阶段 02 源码交付边界；下轮先读检查点，再进行阶段 03 的 Swift 无 UI 会话和命令执行接入。阶段 05 全量最终审计尚未开始。

## 2026-09-14 阶段 03 恢复与需求调整

恢复阶段 02 的 464 条哈希全部匹配。用户新增要求：CLI 支持原位修改文件夹或 mcworld，仍支持另存为。采用 --in-place 与 --output 互斥；修改命令必须明确选择其一。原位模式仅在全部命令成功后提交，执行错误或取消保留副本且不提交源路径。此需求取代此前“永不写回源存档”的 CLI 限制；无需再次请求用户许可。

当前进入阶段 03：先调整 Windows 保存契约，再接通 Swift 执行与同样的保存路径。Swift 命令依赖 WorldSession 和方块列读取，准备为会话隔离 GUI 状态，并把方块列读取从 UIKit 渲染器提取为共享数据读取类。当前仍无 .NET、Swift/Xcode 或 CMake 工具链。阶段 04/05 边界不变。

## 2026-09-14 阶段 03 中间检查点 A

Windows 原位保存参数、源内容指纹、文件夹替换回滚与 mcworld 容器保留已写入；新增执行失败和外部修改冲突回归源码。Swift 已增加同契约的参数、计划、路径、文件系统、工作副本和执行入口。原 WorldSession 以 MCBE_CLI 条件隔离 GUI 状态；方块列读取移入共享 BedrockBlockReader，NBT 路径/修改原语从 UI 文件移入 NBT 目录，原 GUI 调用入口保留。原末地及核心检查脚本随共享类型位置调整，测试断言保留。

Apple 原生 CMake、固定依赖 bootstrap 与统一 host/iOS 构建脚本已落盘，57 个 Swift 输入的无 GUI 源码检查初次通过。尚无 Swift 原生集成测试文件与阶段 03 源码审计/工作流，未运行任何编译。下一步补测试和工作流，再逐项核对 API、记录可用静态检查与阶段交付说明。

## 2026-09-14 阶段 03 中间检查点 B

Swift 原生集成测试与阶段 03 手动 Actions 已写入，覆盖原位文件夹/mcworld、另存为、源变化与输出竞争、失败保留副本、取消、全部命令族及原始末地 v1/v8/空区块样本。Apple 构建连接原 Objective-C++ LevelDB/压缩桥，复用 Windows 的 leveldb-mcpe 0.8.0a8 与 zlib 1.3.1 构建输入。已补原回归脚本对提取后 NBT/方块读取类的输入连接，未改变原有测试断言。

阶段 03 源码审计初次通过，57 个 Swift 输入的项目内已声明类型均有对应输入，CLI 分支无 UIKit/WorldStore 依赖；命令条目已标记两端执行源码接通及两种保存模式。尚未运行编译或原生测试。剩余工作为最后的源码/脚本/工作流/重构字节核对、文档与完整 ZIP；本阶段不启动交互终端或最终发布打包。

## 2026-09-15 阶段 03a 恢复核验小断点

工作环境恢复后，实际找回上一轮阶段 03 的修改：相对第二版有 31 个文件变化、16 个文件新增，第二版 465 个文件没有丢失。已先保存未修改的恢复副本。用户重新上传的第二版 ZIP 与历史 SHA256 一致，CRC 及其 464 条文件哈希全部通过。不能以工作环境曾不可用推断源码已丢失；本轮未解压旧包覆盖现有工程。

本轮执行三个源码检查脚本、8 个 shell 脚本逐个 bash -n、4 个 Python 源码语法检查、3 个 CLI 工作流 YAML 结构检查，均通过。47 个找回的新增/修改文本没有空文件、NUL 或遗留冲突标记；方块读取与 NBT 修改代码提取前后保持方法正文，WorldCommandExecutor 只替换 4 个类型引用。9 个选定命令/编解码/桥接文件和 17 个历史报告/日志/清单与第二版逐字节相同，409 个原始文件全部保留。实际记录见 CLI/Validation/Stage03a/。

没有发现本轮需要改写的生产源码损坏迹象。已修复 README 和命令对照指向未生成阶段 03 报告/验证目录的问题，并将后续拆为 03b/03c、04a～04e、05a～05c。程序版本仍为 0.3.0-stage03，快照名称改为 stage03a 以明确这是恢复断点，不宣称完整阶段 03 已验收。dotnet、Swift/Xcode、clang、CMake、PowerShell 均不可用，编译、真实数据库执行、Actions、设备与游戏读档没有运行。

准备交付 STAGE03A_REPORT.md 对应的独立说明与 MCBEEditor-CLI-stage03a.zip；下一轮只做 03b 的 Windows 保存专项复核，不提前展开交互终端或发布打包。用户要求原位修改文件夹/mcworld 并支持另存为继续有效，覆盖阶段 02 的源文件只读限制。

## 2026-09-15 阶段 03a 交付检查点

恢复核验和文档修正完成；本轮生产/测试源码未在已找回的状态上继续改动。将完整当前状态写入 MCBEEditor-CLI-stage03a.zip，同时导出 MCBEEditor-CLI-stage03a-notes.md。快照内部以 stage03a-files.sha256 校验每个文件（清单自身除外），打包后核对 ZIP CRC、文件字节及说明副本一致性。旧阶段产物保留，停止本轮；下一轮严格只进行 03b Windows 保存专项复核。

## 2026-09-15 阶段 03b 实施前检查点

stage03a 的 490 条哈希与完整 ZIP SHA256/CRC 核验通过，旧产物保留。本轮仅 Windows 原位/另存为复核。确认 CliInPlaceArchive 直接用 ZIP 条目原文匹配规范化世界前缀，会漏掉 ./World/ 或 Wrapper/../World/ 等同路径条目；工作副本删除文件后，这些旧条目可能被错误保留。准备规范化匹配并新增重开归档回归；补充原位取消、外部修改及受阻保存的源完整性/恢复断言。无编译器或原生工具链，不重试安装，不宣称实际测试运行。

## 2026-09-15 阶段 03b 源码与检查里程碑

已修改 CliInPlaceArchive：规范化旧条目的斜杠、空路径组件、. 与内部 .. 后匹配世界根目录，只用工作副本重建世界部分，无关条目保留原名。CliWorldRunner 取消提示补上“未导出或提交”。Windows 集成测试增加标准错误观察器并新增 7 个场景：嵌套归档别名/已删除标记重开、文件夹取消、mcworld 取消、归档源变化、原位归档替换受阻、另存为替换受阻、目录迁移前目标冲突；另补成功原位保存后副本清理断言。没有为测试新增生产故障注入接口。

三个已有源码检查通过，范围核对确认生产/测试代码仅上述两个 CLI 文件和一个 Windows 测试文件变化；Swift、GUI、原生/NBT/区块算法和 27 个历史记录保持原样。实际结果位于 CLI/Validation/Stage03b/。源码复核确认数据库在返回命令结果前关闭、失败默认保留副本、文件夹第二次迁移失败进入回滚；后两次迁移故障/回滚失败本轮没有实际注入执行。缺少 Windows/.NET/原生工具链，7 个新增测试及原有测试均未运行。

正在整理 STAGE03B_REPORT.md、最新检查点与完整 ZIP。下一轮仅进行 03c Swift 保存/Apple 原生构建复核；不展开结构文件接口、交互终端和最终发布。

## 2026-09-15 阶段 03b 交付检查点

STAGE03B_REPORT.md、README、细分计划和当前功能清单已整理，报告明确区分源码修复、已运行的静态检查和未运行的 Windows 原生回归。准备生成 stage03b-files.sha256、MCBEEditor-CLI-stage03b.zip 及一致的独立说明，并核对归档 CRC/逐文件字节/哈希；旧 stage03a 产物保留。停止本轮，下一轮仅推进 03c Swift 保存和 Apple 原生构建专项复核，Windows 编译/文件共享/真实数据库验证缺口继续保留。

## 2026-09-15 stage03c / 04a / 04b 综合检查点

用户明确要求本轮根据 stage03b 源码和说明连续完成 03c、04a、04b，因此本次例外一次推进三个已指定小断点，之后恢复逐断点交付。

03c 复核 Swift 保存链路和 Apple 构建输入。确认另存为继续走 GUI 世界根/私有元数据过滤，原位 mcworld 继续从完整容器重建并排除世界 db/LOCK。修正 Swift 成功原位提交后源指纹不刷新的生命周期问题；04b 接入时 Windows 同步刷新源指纹，为同一会话重复 :save 提供正确基线。Apple CMake/bridge/固定依赖算法未改。

04a 新增双端 CLI structure 文件接口：显式 --file、--overwrite，支持带空格引号路径、mcstructure/Big Endian nbt/json，复用既有 Standalone NBT codec、Java→Bedrock 转换器和 structure store。非交互模式缺名称或文件参数在整批执行前拒绝；交互模式允许名称提示。双端原生集成测试源码新增导出→导入→LevelDB 验证及缺名称整批预检场景。

04b 新增 --interactive 及 :open/:save/:quit/:quit --discard。会话保存成功后继续打开，潜在修改命令失败后保守保持 dirty；原位会话支持连续保存。双端新增 1111→save→2222→save 回归源码验证源指纹刷新。

实际通过 source/stage02/stage03/stage04 四个源码审计，以及 Linux Swift 6.2.1 对 59 个生产输入和 NativeIntegration.swift 的前端语法解析。当前无 dotnet/pwsh，且不是 macOS/Xcode，Windows/Apple 原生编译、真实 LevelDB 集成、Actions、设备/游戏读档未运行。下一轮仅 04c。

## 2026-09-15 stage04c / 04d / 04e 综合检查点

用户明确批准按既定设计连续完成 04c、04d、04e。本轮不改 LevelDB/NBT/区块持久化核心。

04c 新增双端终端适配层：历史上下、左右/Home/End、Backspace/Delete、`:history`、`:clear` 和结果颜色。重定向复核发现并修正两个边界：stdin 为 TTY 但 stdout 重定向时必须关闭 raw 行编辑；stderr 重定向必须独立关闭错误 ANSI。两项都先扩充源码门禁并观察失败，再修改实现转绿。游戏 `clear` 语义未变。

04d 新增 Commands 固定说明/用户 Command.txt 管理。启动只重写 ReadMe，不触碰 Command.txt；交互 :open 后检测并确认，先整批语法预检，再串行运行；运行错误继续后续命令并累积最终失败状态。无人值守只通过显式 --script。Windows/Swift 原生集成测试源码同步新增 ReadMe/Command.txt 所有权、运行错误继续和语法整批拒绝场景。

04e 对齐此前记录的双端 parser 边界：Swift 只对语法关键字做大小写归一，Windows effect 动作同步；ALL/Auto/default/NBT/名称等语义 token 不整体 lower。Swift 方块 CLI X/Y/Z 收紧为 Int32，与 Windows 公共边界一致，底层 X/Z Int64 数据类型不重构。共享 parser fixtures 删除平台特判并扩展到 142 条。

最终累计 7 个源码审计通过；Swift 6.2.1 前端语法解析 61 个生产输入 + NativeIntegration.swift 通过，CliTerminal 最小依赖 typecheck、Python py_compile 和 build-apple.sh bash -n 通过。本机仍无 dotnet/pwsh 且不是 macOS/Xcode；Apple host 构建实际尝试在环境门禁退出 1，Windows/Apple 原生集成、Actions、设备和 Minecraft 读档未运行。下一断点为 05a Windows 单 exe；若先收到真实平台失败日志，优先修复。

## 2026-09-15 stage05a / stage05b 发布检查点

用户批准继续实现 05a/05b，并明确 iOS 可以只提供裸二进制。本轮不修改 LevelDB/NBT/区块/命令业务算法，集中完成发布层。

05a 新增 Windows 专用 console portable launcher。托管 CLI 先以 win-x64 self-contained/single-file 方式发布并把本机库纳入自提取 payload，再作为资源嵌入外层 `mcbe-cli.exe`。launcher 只释放自己的 `Cache/Runtime/<pid>`，通过 portable root/cache 环境变量让 Commands 和世界工作目录继续位于外层 exe 同级，并保留 stdio、参数与退出码。release 脚本强制 payload 和 dist 都为单文件并从空目录实际探测最终外层 exe。审阅时发现最初继承 GUI `SetCurrentDirectory` 会破坏 CLI 相对路径，新增红灯门禁后移除该行为；现在 child 保留调用者 CWD，而 Commands 仍锚定 exe 目录。

05b 最终范围调整为 iOS 13 arm64 裸 Mach-O，不做 deb/rootful/rootless。现有 Apple 编译链后增加 lipo/vtool 检查和 `codesign -s -` ad-hoc 签名验证。新增 `cli-release.yml`，Windows job 上传单 `mcbe-cli.exe`，macOS job 先跑 host 原生测试再交叉编译并只上传 iOS 裸 `mcbe-cli`。双端版本更新为 0.5.0-stage05b。

stage05a/stage05b source audit 都先在 stage04e 基线观察到预期失败，再在当前源码转绿；累计 9 个源码门禁、Swift 前端解析、Python/bash/YAML 检查在 Linux 实际通过。当前没有 dotnet/pwsh 且不是 macOS/Xcode，所以最终 Windows exe、Apple 原生链接、iOS arm64/codesign、Actions 和设备运行仍未执行，不用静态结果冒充平台构建。下一轮只做 05c 最终全量审计，除非先收到真实平台失败日志。

## 2026-09-15 stage05c 最终审计

完成计划内最后断点 05c。全量核对 26 个根命令、终端交互、原位/另存为、structure 文件接口、Commands 批处理、stage04e 解析对齐及 05a/05b 发布链；未发现需要改写 Bedrock 持久化核心的证据。

审计发现并清理两个收尾问题：CLI 新构建目录/Python cache 未被 `.gitignore` 覆盖；GUI iOS Actions 仍保留早期 ZIP overlay 无法删除旧文件时的 `rm -f` 过渡步骤。新增 `stage05c_final_audit.py` 固定最终契约并接入 Windows/Apple 累计门禁。运行时版本不变，最终验证边界详见 `WORK_FINAL_REPORT.md`。

05c 差异复核额外发现 Windows 累计脚本初次插入最终审计后，stage05b 的失败可能被 stage05c 成功退出码覆盖；新增最终门禁先观察失败，再修正为逐阶段立即检查并使用独立错误信息。

## 2026-09-15 stage06 NBT/mcstructure 格式转换

用户在 stage05c 基线上新增要求：CLI 提供 NBT/mcstructure 工具的格式转换能力，但不需要编辑器功能。本轮将其定义为独立文件工具，不作为新的世界命令，也不依赖打开存档。

先新增 stage06 源码门禁并观察预期红灯；随后 Windows/Swift 双端增加 `--convert 输入 --to 格式 --output 输出 [--overwrite]`，输出格式固定为 Big Endian、Little Endian、Little Endian VarInt、JSON 和 mcstructure。实现直接复用已有 Standalone NBT codec 与 JavaStructureConverter，没有复制 NBT 树编辑、搜索、增删标签等 UI 逻辑。多根 NBT 保留三种二进制编码/JSON 互转，mcstructure 继续限制单根结构。

双端原生集成测试源码新增 help、LE、LE-VarInt、JSON、mcstructure、覆盖保护、多根保留和多根禁止转 mcstructure 场景；累计构建脚本加入 stage06 audit。当前环境继续按 Linux 可用门禁验证，Windows/macOS 原生运行状态单独记录。


## 2026-09-15 stage06b CLI 平台构建失败修复

用户提供的 Windows/iOS CLI Actions 日志实际来自同一次双 job 运行。iOS/macOS host 的首个失败点为 `build-apple.sh: line 34: PLATFORM_OPTIONS[@]: unbound variable`；Windows 首个失败点为 CMake 收到错误的 `CMAKE_POLICY_VERSION_MINIMUM=3` 和额外参数 `.5`。两者均发生在真正 CLI 编译之前。

先新增 `stage06b_build_audit.py` 并观察红灯，然后修复：Windows 将 decimal CMake define 作为完整引号参数传递；Apple 去掉 host 模式空数组展开，改用 `configure_native "$@"` 的 Bash 3.2 兼容路径。继续审计 stage06 差异时发现 Windows 原生集成测试把 `RunTests` 参数 `root` 再声明为 NBT `root`，这是 C# CS0136 的确定性后续失败；同样先扩展门禁观察失败，再改名 `rootDocument`。

本 Linux 环境重新通过累计源码门禁、Python 编译、Apple shell `bash -n`、62 个 Swift 生产输入 + NativeIntegration 的前端解析。这里仍不能运行 Windows .NET/MSVC 或 macOS/Xcode，所以不能宣称修复后的 Actions 已真构建通过；下一步应直接用 stage06b 在两个 runner 上复跑。
