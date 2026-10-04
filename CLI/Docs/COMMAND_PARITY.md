# MCBEEditor CLI 命令覆盖对照

当前共 27 个根命令，双端都有解析和执行入口。本清单描述当前路由和必须保留的行为，不是验收通过清单；当前轮次与未完成项见 [FINAL_REVIEW.md](FINAL_REVIEW.md)。

| 命令 | 必须保留的范围 | Windows 原始解析器 |
| --- | --- | --- |
| `help` | 全部帮助；单命令帮助；未知命令提示 | CLI 的 help 路由，帮助复用原目录 |
| `info` | 世界信息逐行输出 | StorageBiomeCommandParser |
| `clear` | 目标选择器；清除物品 | EntityActionCommandParser |
| `clearspawnpoint` | 玩家出生点清除 | TargetingCommandParser |
| `clone` | 跨维度；重叠复制；现代格式全部 storage，旧数字格式 layer0/layer1 | BlockCommandParser |
| `chunk` | query；empty；regenerate；SubChunk 版本与 Y 范围；IsSlimeChunk；Ticking | ChunkCommandParser |
| `daylock` | 0/1 与 dodaylightcycle 反向映射 | EnvironmentCommandParser |
| `effect` | give；clear；ALL；原始 Byte 等级 | EntityActionCommandParser |
| `entity` | 全维度/指定维度/闭合浮点范围；实体类型与完整 NBT；只读 | EntityQueryCommandParser |
| `experience` | add；addlevel；level；percent；query；set；等级 0 至 24791 | TargetingCommandParser |
| `fill` | 多 storage；省略 storage 保留；255 storage | BlockCommandParser |
| `fillbiome` | 数字或字符串 ID；Data2D 和 Data3D | StorageBiomeCommandParser |
| `getblock` | 全部 storage；BlockEntity | BlockCommandParser |
| `give` | Auto 或 Slot 0 至 35；必填物品标签或 NULL；嵌套 NBT；已有 Mainhand | EntityActionCommandParser |
| `kill` | 创造模式开关 | EntityActionCommandParser |
| `kick` | 在线玩家 UniqueID 或 @a | EntityActionCommandParser |
| `setblock` | 多 storage；未生成区块和子区块 | BlockCommandParser |
| `setworldspawn` | 世界出生点 | TargetingCommandParser |
| `spawnpoint` | 玩家出生点和维度 | TargetingCommandParser |
| `spread` | 已加载区块随机分散；Auto Y | TargetingCommandParser |
| `storage` | query；set；delete；clear；层 0 至 254；clear 255 | StorageBiomeCommandParser |
| `structure` | query/save/load/delete/import/export；mcstructure/nbt 大端/json/txt (MCBE-SNBT)；现有 save/load 仅 layer0/layer1，普通实体复制未实现 | StructureTemplateCommandParser |
| `summon` | 浮点 Pos；default 或附加 NBT；末尾 Auto/Long UniqueID；直接实体 NBT | EntityActionCommandParser |
| `teleport` | 浮点坐标；Auto Y；玩家整数 Y 加 1.62 | TargetingCommandParser |
| `tickingarea` | add square；add circle；delete；list；重名覆盖 | EnvironmentCommandParser |
| `time` | query daytime；query gametime；query day；add；set；ceil；floor | EnvironmentCommandParser |
| `weather` | query；clear；rain；thunder；缺失 doWeatherCycle 显示 1 | EnvironmentCommandParser |

Swift 全部调用 `Sources/Command/WorldCommand.swift` 的 `WorldCommandParser`。Windows 八类解析器位于 `Windows/MCBEEditor.Core/Chunk/`，由 `CLI/Windows/CliCommandParser.cs` 统一调度。完整原 GUI 帮助保存在 command-inventory.json 的 gui_usage 字段。

第 15 轮实际证据见 [REGRESSION_MATRIX.md](REGRESSION_MATRIX.md)。Linux C#/Swift 核心、C# 进程与真实数据库集成已运行；目标平台发布、GUI、Minecraft 仍分别待验。clearspawnpoint 现仅清除玩家根 SpawnX/Y/Z、SpawnDimension、SpawnForced，保留嵌套自定义标签，不递归清除宽泛 Respawn 别名。

## 终端与文件接口

| 项目 | 当前行为 |
| --- | --- |
| 交互会话 | `:open` / `:save` / `:quit` / `:quit --discard` |
| 行编辑 | 真实 TTY 的历史、光标移动和删除；重定向时禁用原始输入编辑 |
| 清屏、历史 | `:clear` / `:history`；游戏 `clear` 仍清物品 |
| 输出 | stdout/stderr 各自按终端状态决定 ANSI；管道保持文本 |
| Commands | 启动重写 ReadMe.txt；Command.txt 由用户管理，交互打开后询问 |
| 批处理 | 语法和结构路径预检后执行；前置失败整批拒绝，运行错误逐条报告并继续；原位仅全成功后提交 |
| structure 文件 | `--file` 显式路径；已有文件/同批重复输出须 `--overwrite`；受保护路径及文件/父目录冲突仍拒绝；导出与世界保存非统一事务 |
| 保存 | 修改工作副本；明确选择原位或另存；源变更冲突时拒绝原位提交 |
| 格式转换 | 全局 `--convert` 不打开世界，不新增世界命令或 NBT 编辑器 |

## 需要保留的细节

`weather query` 的 doWeatherCycle 缺失时显示 1。`chunk query` 要保留 SubChunk 版本、Y 范围、IsSlimeChunk 和 Ticking。`structure query` 一行一个结构；`structure export nbt` 默认大端。`teleport` 对玩家的整数 Y 和 Auto Y 加 1.62，显式浮点 Y 保留原值。`give` 当前源码要求提供物品标签参数，空标签写 NULL。

读取覆盖 v0 至 v9 已知子区块格式，不代表所有格式都能写入任意现代方块和 255 层。旧数字格式仅在数字 ID/data 可无损表达且层数可表示时写入；不支持的 states/层数会拒绝，LegacyTerrain 还有 Y 范围限制。255 storage 和末地高层新建主要走现代格式路径，原生及游戏读档结果须单独验收。批处理的“语法错误整批拒绝”和“运行时错误逐条报告后继续”是两个不同步骤，不能混淆。

## 解析与格式约定

根命令、子命令、维度等语法关键字大小写不敏感；`ALL`、`Auto`、`default`、NBT 字符串、名称与 identifier 保持各自语义规则。方块 X/Y/Z 的 CLI 输入限制为 Int32；非坐标 Long 字段和实体浮点坐标保持原范围。两端读取同一份 `CLI/Shared/parser-cases.json`。

独立格式转换目标为 `big-endian`、`little-endian`、`little-varint`、`json`、`mcstructure`、`txt`（别名 `mcbe-snbt`）。输入复用 Standalone NBT codec 的格式识别、连续多根和压缩支持；mcstructure 接受单根结构，Java→Bedrock 转换继续使用现有转换器。

## 可复跑验证

- `CLI/Tests/source_audit.py`：清单与双端 27 条完整帮助文本、解析/执行路由、无 GUI 编译依赖、Swift 本地类型依赖。
- `CLI/Tests/build_audit.py`：双端构建输入、原生测试接线、单 EXE 和 iOS 13.0 发布约束。
- `CLI/Tests/smoke.py`：真实进程的公共解析、编码、帮助和转换。
- `CLI/Tests/session_smoke.py`：真实进程的会话和文件生命周期，不依赖数据库操作。
- `CLI/Windows.Tests` / `CLI/iOS.Tests`：真实 Mojang LevelDB 集成；保存重开、冲突恢复、命令、转换和末地高层测试。
- `Windows/MCBEEditor.Core.SelfTest` / `Scripts/run_core_tests.sh`：现有平台核心回归。

源码检查和托管自测不能替代平台原生构建、设备测试或 Minecraft 读档验证。
