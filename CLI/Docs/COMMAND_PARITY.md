# MCBEEditor CLI 命令覆盖对照

以下清单以上传源码为准，共 26 个顶级命令。Windows 与 Swift 的世界执行已接入；stage04a 已补 structure import/export 的 CLI 文件路径接口，stage04b～04d 已补持续会话、终端行编辑与 Command.txt 流程，stage04e 已处理此前明确记录的解析边界差异。两端支持 --in-place 原位更新与 --output 另存为。stage05a/05b 只增加 Windows 单 exe 与 iOS arm64 裸二进制发布层，没有改变命令语义；stage05c 已完成最终全量源码审计与冗余清理。源码覆盖检查通过，平台发布构建和实际原生运行仍需 Windows/macOS runner 验证；“接入”指源码状态。

| 命令 | 必须保留的范围 | Windows 原始解析器 |
| --- | --- | --- |
| `help` | 全部帮助；单命令帮助；未知命令提示 | CLI 的 help 路由，帮助复用原目录 |
| `info` | 世界信息逐行输出 | StorageBiomeCommandParser |
| `clear` | 目标选择器；清除物品 | EntityActionCommandParser |
| `clearspawnpoint` | 玩家出生点清除 | TargetingCommandParser |
| `clone` | 跨维度；重叠复制；全部 storage | BlockCommandParser |
| `chunk` | query；empty；regenerate；SubChunk 版本与 Y 范围；IsSlimeChunk；Ticking | ChunkCommandParser |
| `daylock` | 0/1 与 dodaylightcycle 反向映射 | EnvironmentCommandParser |
| `effect` | give；clear；ALL；原始 Byte 等级 | EntityActionCommandParser |
| `experience` | add；addlevel；level；percent；query；set；等级 0 至 24791 | TargetingCommandParser |
| `fill` | 多 storage；省略 storage 保留；255 storage | BlockCommandParser |
| `fillbiome` | 数字或字符串 ID；Data2D 和 Data3D | StorageBiomeCommandParser |
| `getblock` | 全部 storage；BlockEntity | BlockCommandParser |
| `give` | Auto 或 Slot 0 至 35；嵌套 NBT；已有 Mainhand | EntityActionCommandParser |
| `kill` | 创造模式开关 | EntityActionCommandParser |
| `kick` | 在线玩家 UniqueID 或 @a | EntityActionCommandParser |
| `setblock` | 多 storage；未生成区块和子区块 | BlockCommandParser |
| `setworldspawn` | 世界出生点 | TargetingCommandParser |
| `spawnpoint` | 玩家出生点和维度 | TargetingCommandParser |
| `spread` | 已加载区块随机分散；Auto Y | TargetingCommandParser |
| `storage` | query；set；delete；clear；层 0 至 254；clear 255 | StorageBiomeCommandParser |
| `structure` | query；save；load；delete；import；export；mcstructure；nbt 大端；json | StructureTemplateCommandParser |
| `summon` | 浮点 Pos；default 或 NBT；禁止覆盖受保护标签 | EntityActionCommandParser |
| `teleport` | 浮点坐标；Auto Y；玩家整数 Y 加 1.62 | TargetingCommandParser |
| `tickingarea` | add square；add circle；delete；list；重名覆盖 | EnvironmentCommandParser |
| `time` | query daytime；query gametime；query day；add；set；ceil；floor | EnvironmentCommandParser |
| `weather` | query；clear；rain；thunder；缺失 doWeatherCycle 显示 1 | EnvironmentCommandParser |

Swift 全部调用 `Sources/Command/WorldCommand.swift` 的 `WorldCommandParser`。Windows 七类解析器位于 `Windows/MCBEEditor.Core/Chunk/`，由 `CLI/Windows/CliCommandParser.cs` 统一调度。完整原 GUI 帮助保存在 command-inventory.json 的 gui_usage 字段。

## 命令栏周边功能

| GUI 功能 | CLI 对应行为 | 计划阶段 |
| --- | --- | --- |
| 命令输入和结果列表 | 交互提示符、逐条标准输出、错误输出、颜色适配 | 04 |
| 上下方向键和左右移动 | 已完成：TTY 历史与行编辑；重定向禁用 raw editor | 04c |
| 清屏按钮 | 已完成：`:clear`，保留 `clear` 清物品语义 | 04c |
| 输出选择与复制 | 已完成颜色门禁：TTY ANSI；stdout/stderr 分别重定向时纯文本 | 04c |
| 键盘呼出收起 | 由 iOS 终端宿主管理，不引入 UIKit 键盘窗口 | 04 |
| Commands 目录和固定 ReadMe | 已完成：重写固定说明而不创建/覆盖/删除 Command.txt | 04d |
| 进入世界检测 Command.txt | 已完成：交互 :open 后提示；非交互显式 --script，不等待确认 | 04d |
| 整批语法检查 | 两端均已接入文件预检及执行前整批门禁 | 01～03 已接入 |
| 批处理期间冻结界面 | 两端已接入同一副本串行执行、逐行显示、运行时错误后继续 | 02、03 已接入；交互 04 |
| structure 选择和保存窗口 | 带空格路径、可交互结构选择、格式选择 | 04 |
| 世界导入和导出 | 两端已接入工作副本、原位更新/另存为、关闭数据库及失败恢复 | 02、03 已接入 |

## 需要保留的细节

`weather query` 的 doWeatherCycle 缺失时显示 1。`chunk query` 要保留 SubChunk 版本、Y 范围、IsSlimeChunk 和 Ticking。`structure query` 一行一个结构；`structure export nbt` 默认大端。`teleport` 对玩家的整数 Y 和 Auto Y 加 1.62，显式浮点 Y 保留原值。`give` 当前源码要求提供物品标签参数，空标签写 NULL。

方块编辑必须保留 v0 至 v9 子区块、255 storage、缺失区块和末地高层缺失子区块的持久化行为。批处理的“语法错误整批拒绝”和“运行时错误逐条报告后继续”是两个不同步骤，不能混淆。

## stage04e 已处理的两端解析差异

此前记录的两个明确差异已在 stage04e 收口：

- Windows 原本对多数根命令/子命令大小写不敏感，而 Swift 多处分支严格小写。现在 Swift 仅对根命令、子命令、维度、time/weather/tickingarea 等**语法关键字**做 `lowercased()` 后匹配；Windows 补齐 `effect` 子命令的相同行为。
- Swift 部分方块 X/Z CLI 参数原先可接受 Int64，而 Windows 对应入口是 Int32。现在 Swift CLI 方块坐标 X/Y/Z 都先按 Int32 解析，再写入现有 Int64 X/Z 数据结构；底层结构类型不做无关重构。

不能简单小写整条命令。`ALL`、`Auto`、`default`、NBT 字符串、结构名称、tickingarea 名称和 identifier 等仍按其原语义处理。共享 `parser-cases.json` 已删除平台专用 `expected_by_backend`，增加 mixed-case、Int32 极值/溢出和语义大小写用例；例如 `EfFeCt ClEaR @e ALL` 有效，而 `effect clear @e all` 仍无效。

structure import/export 的原执行路径在 GUI 协调器中，不能只把原 GUI 解析结果接到 WorldCommandExecutor。stage04a 已在 CLI 层加入显式 --file/--overwrite，并复用原 Standalone NBT codec、Java 转换器和 Structure store；GUI 选择窗口逻辑没有被复制到 CLI。

## 阶段 02 验证范围

Windows 集成测试源码覆盖全部根命令，并检查源世界不变、输出重新打开、255 storage、末地新建高层子区块、重叠 clone、玩家 Y 偏移、天气默认值，以及预检失败、执行错误、输出冲突、取消与缓存恢复。原核心三组选定回归也纳入构建脚本。这些测试尚未编译/运行，不能据此宣称游戏内读档通过。实际执行的静态检查结果见 `CLI/Validation/Stage02/results.json`。


## 阶段 03 新增状态

Swift 以 MCBE_CLI 构建原 WorldSession 的数据会话分支，命令执行器改用共享 BedrockBlockReader；原 GUI 渲染器委托同一读取器。NBTPathComponent 与 NBTTreeMutation 从 UI 文件移到数据目录，方法原文保留。原命令语法及持久化编解码算法未改动。

原位更新只在全部命令成功后提交；另存为允许在运行时错误后导出当前副本并返回失败状态。新增两端原位/冲突/恢复测试及 Swift 原生末地样本测试。测试源码存在，不代表已编译或执行。2026-09-15 已在恢复断点 stage03a 核验这些文件；实际静态验证记录见 `CLI/Validation/Stage03a/`。后续功能与平台验证按 `STAGES.md` 中的小断点执行。

## stage03b Windows 保存复核

Windows 原位 mcworld 的旧条目匹配已规范化路径，修复 `./World/`、内部 `..` 等写法可能使已删除文件被重新带入输出的问题。取消提示补齐“未导出或提交”。新增 7 个真实 CLI 入口的集成测试场景，检查归档重开、两种输入取消、归档外部修改、原位/另存为替换受阻和目录冲突；测试源码已接入现有构建入口，尚未编译/运行。本轮实际静态记录见 `CLI/Validation/Stage03b/`，不改变既有命令语法或 Swift 源码。

## stage03c / 04a / 04b 状态

Swift 保存链路已复核：原位 mcworld 继续从完整解压容器重建并排除世界 `db/LOCK`，另存为继续按 GUI 规则只导出世界根并过滤编辑器私有元数据。Swift 与 Windows 在成功原位提交后都会刷新源指纹，支持同一会话连续两次 `:save`，同时仍能检测两次保存之间的外部修改。

structure 文件接口现为 CLI 专用扩展：`structure import 名称 --file 路径 [--overwrite]` 与 `structure export mcstructure|nbt|json 名称 --file 路径 [--overwrite]`。两端复用原结构 NBT 编解码/Java 转换/结构数据库存储；非交互批处理缺少名称或 `--file` 时在整批执行前失败，交互会话可省略名称后提示输入。路径 tokenizer 支持带空格的引号路径。

持续会话通过 `--interactive` 启动。04c 已补历史方向键、左右/Home/End/删除编辑、`:history`、`:clear` 和 TTY ANSI 映射；stdin/stdout 不是 TTY 时禁用 raw editor，stdout/stderr 各自按自身重定向状态禁用 ANSI，避免控制序列污染管道或文件。04d 已补 Commands 固定 ReadMe 和 Command.txt 检测：交互打开世界后提示，整批预检，运行时错误继续后续命令并保留最终失败状态；无人值守继续使用显式 `--script`。04e 已完成上述共享解析边界对齐。平台原生编译/运行仍待对应工具链验证。


## stage05c 最终审计

stage05c 复核 26 个根命令、9 项终端功能、保存/structure/Commands/parser 对齐和两条发布链；未修改命令执行、NBT、Chunk、World 或 LevelDB 持久化算法。最终审计新增独立门禁，清理失效的 ZIP-overlay CI 删除步骤，并补齐 CLI 生成物忽略规则。平台原生发布、设备运行和 Minecraft 实际读档仍按 `WORK_FINAL_REPORT.md` 明确保留为未验证。

## stage06 独立格式转换工具

stage06 不新增第 27 个世界命令，因此 26 个根命令清单保持不变。新增全局 `--convert`：

`mcbe-cli --convert 输入 --to big-endian|little-endian|little-varint|json|mcstructure --output 输出 [--overwrite]`

Windows/Swift 都直接复用各自现有 Standalone NBT codec；输入可自动识别 Big/Little/VarInt、JSON、连续多根 NBT 和 GZip/Zlib。mcstructure 只接收单根结构并继续使用 JavaStructureConverter。该入口不打开世界、不修改 NBT 标签，也不复用 GUI 编辑器。
