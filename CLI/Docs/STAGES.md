# MCBEEditor CLI 分阶段实施说明

总任务是把上传源码中 GUI 命令栏的全部功能制作成 CLI，最后提供可通过 GitHub Actions 构建 iOS arm64 裸二进制和 Windows 单 exe 的完整源码。采用用户 DOCX 规定的断点方式，默认一次只完成一个小断点并交付完整源码和说明；用户可明确指定连续完成多个相邻断点。本轮用户明确要求连续完成 05a、05b，并进一步明确 iOS 端可以只交付裸二进制。

## 2026-09-15 小断点计划（后续按本表执行）

原 01～05 编号继续表示功能范围，下面的字母编号表示每轮交付边界。历史阶段的源码接入与静态门禁不等于平台原生验证；05a/05b 同样只有在 Windows/macOS runner 实际运行后才能把对应发布构建标成通过。

| 断点 | 单轮范围 | 状态/退出条件 |
| --- | --- | --- |
| 03a | 核验第三次残留修改、修正续作记录、交付恢复快照 | 已交付；文件和静态检查通过，原生验证待做 |
| 03b | Windows 文件夹/mcworld 原位保存及另存为专项复核 | 本轮源码交付；修复 ZIP 路径匹配，新增 7 个回归场景，原生运行待做 |
| 03c | Swift 对应保存链路及 Apple 原生构建专项复核 | 已完成源码复核；源指纹支持重复提交，Apple 输入/语法检查通过，macOS/Xcode 原生运行待做 |
| 04a | structure 文件导入、三格式导出和路径参数 | 已完成源码；双端显式 --file/--overwrite、空格路径、整批预检及集成回归源码，原生运行待做 |
| 04b | 持续交互会话与 :open/:save/:quit | 已完成源码；双端会话状态、脏状态、重复原位保存回归源码，原生运行待做 |
| 04c | 历史、方向键、清屏和终端颜色 | 已完成源码；双端行编辑、:history/:clear、TTY 颜色与独立 stdout/stderr 重定向门禁，原生运行待做 |
| 04d | Commands 目录、固定 ReadMe 和 Command.txt 检测 | 已完成源码；固定 ReadMe 重写、不触碰 Command.txt、交互提示、整批预检/运行错误继续/退出状态，原生运行待做 |
| 04e | 已记录的两端解析边界和命令结果对齐 | 已完成源码；语法关键字大小写与方块 Int32 坐标边界统一，共享 fixtures 无平台特判，原生运行待做 |
| 05a | Windows 单 exe 发布与 Actions | 已完成源码；console launcher 嵌入 self-contained payload、程序旁 Commands/Cache、最终 EXE 启动探针，Windows runner 待实际运行 |
| 05b | iOS arm64 裸二进制发布与 Actions | 已完成源码；iOS 13 arm64、ad-hoc 签名、Mach-O/最低系统检查并直接上传 mcbe-cli，macOS runner 待实际运行 |
| 05c | 一次全量最终审计和最终报告 | 已完成；需求/回退/冗余/发布链/验证边界已复核，见 `WORK_FINAL_REPORT.md` |
| 06 | 独立 NBT/mcstructure 文件格式转换 | 已完成源码；双端复用 Standalone NBT codec，支持 BE/LE/LE-VarInt/JSON/mcstructure，不含编辑器功能，平台原生运行待验证 |

stage04e 之后，用户明确要求连续完成 **05a、05b**，并把 05b 范围收窄为 iOS arm64 裸二进制；随后完成 **05c 最终全量审计**。在此基线上，stage06 按新需求加入独立 NBT/mcstructure 格式转换入口；它是文件工具扩展，不增加世界命令，也不包含编辑器功能。当前环境仍不能运行 Windows/.NET 或 macOS/Xcode 发布构建；若后续获得 Actions/实机失败日志，应按真实日志修复并重新执行最终门禁。

## 阶段 01 命令清单和 CLI 基础工程

盘点所有顶级命令、子命令和命令栏交互；固定源文件哈希和覆盖清单。创建 C# 和 Swift CLI 入口，接入原解析器，完成帮助、命令列表、版本、单条命令预检和 UTF-8 文件预检。提供覆盖全部命令的共享输入和独立检查工作流。

退出条件为命令清单与原源码一致，工程引用完整，没有 GUI 依赖，脚本和元数据通过可运行的检查。若有工具链则同时编译并运行测试；缺少工具链必须明确记录未验证。本轮完成这个阶段后停止。

## 阶段 02 Windows 命令执行和存档导出

从 MainWindow.xaml.cs 中抽出命令执行调度，复用现有各 CommandStore、WorldInfoService、NBT 和 LevelDB 核心。接入输入为世界文件夹、mcworld 或 ZIP 的工作副本生命周期，在 CLI 输出世界信息和所有非交互命令执行结果，支持明确的输出 mcworld 路径。

保留命令语义，包括 255 storage、缺失子区块新建、重叠 clone、玩家整数 Y 加 1.62、天气默认值和结构查询。结构导入导出的终端路径接口集中在阶段 04；本阶段实现其余结构 save/load/delete/query 执行。自动预检不能跳过运行时错误的报告。

退出条件为 Windows CLI 的查询、修改和导出形成完整链路；使用临时合成世界验证输入未被修改、导出可重新打开、异常时工作副本处理明确，并运行与改动直接相关的已有持久化回归。实机游戏读取仍需明确单列验证状态。

## 2026-09-14 保存模式调整

用户在阶段 03 开始时要求支持原位修改世界文件夹/mcworld，并保留另存为。两端统一采用 --in-place 与 --output 互斥；修改需要显式选择其一。原位模式先在副本执行，仅全部成功后提交；文件夹提交支持回滚，mcworld 保留容器布局和非世界文件。此项覆盖此前 CLI 不写回源存档的限制，阶段 04/05 边界不变。

## 阶段 03 iOS 命令执行和存档导出

为 WorldCommandExecutor 提供 CLI 的世界会话和文件系统环境，隔离 WorldSession 的 GUI 选择状态，不把 WorldStore 索引管理带进 CLI；提取共享方块读取与 NBT 数据原语，保持同一 Swift 执行器和原生 LevelDB 桥。补全文件夹和压缩世界副本、关闭数据库、原位提交、另存为与异常恢复；Windows 同步新增保存方式。

退出条件为与阶段 02 同范围的 Swift 执行功能接通，主机测试和 iOS arm64 交叉编译通过，或逐项记录工具链阻碍。将已有末地高层未生成子区块测试作为必须保持的回归用例，不能把主机模拟通过写成游戏实机验证通过。

## 阶段 04 命令栏交互和两端对齐

完成交互终端提示符、历史上下选择、左右光标、清屏、取消和退出。会话管理采用 `:open`、`:save`、`:history`、`:clear`、`:quit` 等独立名称，避免覆盖原本用于清理物品的 `clear` 命令。明确重定向输入时的行为，不能在无人交互的批处理里等待文件选择。

完成 Command.txt 的整体预检和逐条输出。任意语法错误拒绝整批；运行时错误显示后按原 GUI 继续后续命令，进程最终返回失败状态。GUI 的批处理期间冻结界面改为同一会话顺序执行，禁止并发写同一工作副本。

结构 import/export 增加明确路径，保留原 GUI 名称和格式参数；拟定扩展为 `structure import [名称] --file 路径` 和 `structure export mcstructure|nbt|json [名称] --file 路径`。支持包含空格的路径；交互模式可提示选择结构，无交互模式缺少必要参数立即报错。nbt 默认大端，mcstructure 使用基岩格式，json 保持类型信息。覆盖文件的规则与所有帮助需在实现时一并确定和验证。

本阶段同时解决已记录的跨端解析差异，扩充共同边界和存档结果对照。退出条件为命令清单和命令栏交互清单全部有对应实现和验证记录。

## 阶段 05 GitHub Actions 发布和最终审计

05a 添加 Windows x64 单 exe 发布。托管 CLI 先发布成 self-contained/single-file payload，连同 .NET 运行时和 `MCBEEditor.LevelDB.Native.dll` 的自提取内容一起嵌入专用 console launcher。launcher 保留 stdin/stdout/stderr 与参数转发，在外层 exe 同级设置 `MCBEEDITOR_PORTABLE_ROOT` / `MCBEEDITOR_CACHE_ROOT`，仅把自己的 payload/.NET bundle 提取到 `Cache/Runtime/<pid>`，退出时不递归删除可能因失败或 `--keep-work` 需要保留的世界工作副本。发布脚本要求 `dist` 恰好只有 `mcbe-cli.exe`，并从空临时目录实际运行最终外层 exe 的 `--version`、`--help`、`--check` 和 Commands 路径探针。Windows 单文件发布仍显式使用 .NET 单文件/本机库自提取属性。[Microsoft 单文件部署说明](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)

05b 按用户 2026-09-15 的明确调整只发布 **iOS 13 arm64 裸二进制**，不制作 deb，也不再划分 rootful/rootless 安装布局。`build-apple.sh ios` 继续直接链接 Apple 原生 LevelDB bridge，检查 Mach-O 只有 arm64 且最低系统为 iOS 13.0，然后使用 Apple `codesign -s -` 做 ad-hoc 结构签名并验证。GitHub Actions 直接上传 `CLI/build/apple-ios/mcbe-cli`；下载后是否放入 `/usr/bin`、`/var/jb/usr/bin` 或其他路径由用户的越狱/部署环境决定，不在 05b 构建产物中硬编码。

05c 已完成一次全量最终审计：覆盖原始需求、临时代码和多余缓解、重复实现、构建/回归结果及阶段间功能回退；移除失效的 ZIP-overlay CI 清理步骤，补齐 CLI 构建产物忽略规则，并生成 `WORK_FINAL_REPORT.md`。真实 Windows/macOS runner、iOS 设备和 Minecraft 内未完成的检查继续明确保留为未验证。

## 阶段 06 NBT / mcstructure 独立格式转换

在不打开世界、不进入 NBT 编辑器的情况下提供 `--convert` 文件转换入口。输入继续复用 Standalone NBT 自动识别能力，支持 Big Endian、Little Endian、Little Endian VarInt、JSON、连续多根 NBT 和 GZip/Zlib 包装；输出支持 `big-endian`、`little-endian`、`little-varint`、`json`、`mcstructure`。

多根 NBT 在三种 NBT 编码与 JSON 间保持根标签数量；mcstructure 仅允许单根结构 NBT，并复用既有 JavaStructureConverter 进行 Java structure → Bedrock 转换。输出默认不覆盖，需显式 `--overwrite`。本阶段只新增 CLI 参数解析、文件原子发布、帮助和双端集成回归，不复制 GUI 的树编辑、搜索、增删标签等功能。

退出条件为 Windows/Swift 两端入口和格式名一致、现有 codec 被直接复用、构建门禁包含 stage06 审计、双端原生集成测试源码覆盖 BE/LE/VarInt/JSON/mcstructure/多根/覆盖规则；当前 Linux 环境至少完成源码审计和 Swift 前端解析，真实 Windows/macOS 运行继续单列未验证。

## 断点纪律

每次主要修改或验证里程碑后更新 WORK_CHECKPOINT.md，WORK_PROGRESS.md 只追加历史。开始大型重构或构建前先落盘。每轮 ZIP 包含可恢复的完整状态，不只打包差异，不删除上一轮唯一有效产物。当前无法可靠读取 Work 剩余额度，因此不猜测额度或使用比例，以阶段和里程碑主动保存。stage04e 之后用户明确要求连续完成 05a 与 05b，并说明 iOS 可以只提供裸二进制；05c 也已完成；随后新增 stage06 格式转换工具。最终快照不把 deb/rootful/rootless 作为缺口。后续若收到平台编译/原生失败日志，以 stage06 为当前功能基线修复并重新验证，同时保留 stage05c 历史审计门禁。
