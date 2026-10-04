# MCBEEditor CLI

当前 CLI 版本为 **1.0.0**。Windows x64 继续发布绿色单 `mcbe-cli.exe`，iOS 继续发布最低 iOS 13 arm64 裸二进制；独立 NBT/mcstructure 格式转换保持为工具功能，不加入 NBT 编辑器功能。

收尾检查的当前轮次、已运行验证和未完成范围统一见 [FINAL_REVIEW.md](Docs/FINAL_REVIEW.md)。命令覆盖与兼容限制见 [COMMAND_PARITY.md](Docs/COMMAND_PARITY.md)；功能接线不等于所有边界场景均已通过平台或游戏验证。

## 一次性执行与保存

修改命令必须明确选择 `--in-place` 或 `--output`；纯查询可以不指定保存方式。

```text
mcbe-cli --world "D:\Worlds\My World" --command "time set 6000" --in-place
mcbe-cli --world "D:\Worlds\My World.mcworld" --script "Commands\Command.txt" --in-place
mcbe-cli --world "D:\Worlds\My World.mcworld" --command "weather query" --output "D:\Output\Copy.mcworld"
```

`--in-place` 支持世界文件夹和 `.mcworld`；普通 ZIP 只能另存为 `.mcworld`。`--output` 与 `--in-place` 互斥，覆盖已有输出需 `--overwrite`。两种方式都先修改工作副本；一次性原位模式只在整批命令全部成功后提交，另存为保持既有“运行时错误后继续后续命令并可导出当前副本、最终返回失败”的行为。

mcworld 原位提交保留原容器中的世界根目录层级、世界外文件和编辑器私有文件，排除世界数据库 `db/LOCK`；另存为继续沿用 GUI 导出规则，只导出世界根并过滤编辑器私有元数据。Swift 与 Windows 成功原位提交后都会刷新源内容指纹，因此同一持续会话可以再次修改并再次 `:save`，同时仍能识别真正的外部源变化。

## 独立 NBT / mcstructure 格式转换

转换工具**不需要 `--world`**，只读输入文件并生成新文件，不进入 NBT 编辑器。普通编码转换保留可表达的标签类型和值；Java→Bedrock 结构转换会映射结构内容，须注意下述兼容降级规则。

```text
mcbe-cli --convert "input.nbt" --to big-endian --output "output-big.nbt"
mcbe-cli --convert "input.nbt" --to little-endian --output "output-little.nbt"
mcbe-cli --convert "input.nbt" --to little-varint --output "output-varint.nbt"
mcbe-cli --convert "input.mcstructure" --to json --output "output.json"
mcbe-cli --convert "java-structure.nbt" --to mcstructure --output "output.mcstructure"
mcbe-cli --convert "input.nbt" --to txt --output "output.txt"
mcbe-cli --convert "entity.txt" --to little-endian --output "entity.nbt"
```

可用 `mcbe-cli --help convert` 查看同一说明。输出文件已存在时默认拒绝覆盖；显式加 `--overwrite` 才覆盖。输出扩展名必须与目标格式匹配：前三种二进制编码使用 `.nbt`，JSON 使用 `.json`，Bedrock structure 使用 `.mcstructure`，MCBE-SNBT 使用 `.txt`。

输入由现有 `StandaloneNbtFileCodec` 自动识别：**Big Endian、Little Endian、Little Endian VarInt、JSON NBT、MCBE-SNBT (.txt)、连续多根 NBT，以及 GZip/Zlib 包装的 NBT**。二进制输出统一为未压缩。多根 NBT 可在三种 NBT 编码、JSON 和 MCBE-SNBT 之间互转；`.mcstructure` 只接受单根结构 NBT。Java structure NBT 转 `.mcstructure` 时继续复用现有 Java→Bedrock 转换器，因此兼容降级规则与 GUI 保持一致。

目标格式名固定为：`big-endian`、`little-endian`、`little-varint`、`json`、`mcstructure`、`txt`（也接受 `mcbe-snbt`）。MCBE-SNBT 文本使用严格 UTF-8；语法和无损根包装见 [格式说明](../Docs/MCBE-SNBT.md)。转换入口复用已有数据层，Windows/Swift 两端只调用原 NBT codec 与 structure converter。

## structure 文件接口

CLI 不打开 GUI 文件选择器，使用显式路径：

```text
structure import my:house --file "D:\Structures\house file.mcstructure"
structure import my:house --file "D:\Structures\house file.nbt" --overwrite
structure import my:house --file "D:\Structures\house file.json"
structure import my:house --file "D:\Structures\house file.txt"

structure export mcstructure my:house --file "D:\Output\house.mcstructure"
structure export nbt my:house --file "D:\Output\house.nbt"
structure export json my:house --file "D:\Output\house.json" --overwrite
structure export txt my:house --file "D:\Output\house.txt"
```

支持 `.mcstructure`、Big Endian `.nbt`、保留 NBT 类型信息的 `.json` 和 MCBE-SNBT `.txt`。路径可包含空格，需在命令字符串内使用引号。导入同名结构或导出覆盖已有文件都必须显式 `--overwrite`。两端直接复用现有 Standalone NBT codec、Java→Bedrock 转换器和结构存储，不另写格式算法。导出前还会检查源世界、缓存、世界输出、脚本、同批结构输入，以及输出文件与父目录的冲突；`--overwrite` 不绕过这些路径保护。同批次重复导出到同一个文件时，后一次必须显式 `--overwrite`。多个结构文件与世界保存不构成统一事务，前序文件导出成功后不保证随后续命令失败而回滚。

一次性 `--command/--script` 模式下，structure import/export 的结构名和 `--file` 都必须完整提供；漏项在整批预检阶段失败。交互模式允许省略名称并按提示输入；export 会先列出已有结构。

## 持续交互会话

```text
mcbe-cli --interactive
```

会话命令：

```text
:open "D:\Worlds\My World.mcworld" --in-place
:open "D:\Worlds\My World.mcworld"
:save
:save "D:\Output\Copy.mcworld"
:save "D:\Output\Copy.mcworld" --overwrite
:history
:clear
:quit
:quit --discard
```

`:open ... --in-place` 允许无路径 `:save` 原位提交；普通 `:open` 只打开工作副本，保存时需给出另存为路径。保存成功后会话保持打开。另存副本后仍可用无路径 `:save` 将当前内容写回原位来源；另存不会取消待写回状态。输出必须位于源世界和缓存目录之外。输入错误或打开新世界失败时保留当前会话；不能把当前会话的临时副本重新作为来源打开。潜在修改命令如果在运行中抛错，dirty 状态保守保持，因为原业务命令可能已经完成部分写入；`:quit` 不允许静默丢弃，需先保存或显式 `:quit --discard`。

真实终端支持历史 ↑/↓、←/→ 光标、Home/End、Backspace/Delete、`:history` 与 `:clear`。`clear` 没有冒号，仍是原游戏“清除物品”命令，不与清屏混用。

真实 TTY 输出按原命令结果类型使用 ANSI 样式；错误为红色，玩家/实体/方块等保持各自终端颜色映射。stdin 或 stdout 不是 TTY 时禁用原始按键行编辑；stdout 重定向时不输出 ANSI/重绘序列，stderr 是否着色单独依据 stderr 自身是否为 TTY，因此 `>out.txt`、`2>err.txt` 和管道得到纯文本。

## Commands 目录与 Command.txt

程序启动时准备 Commands 目录并**重写固定 `ReadMe.txt`**；`Command.txt` 始终属于用户，程序不会自动创建、覆盖或删除它。

Windows 默认目录在程序旁：

```text
Commands\ReadMe.txt
Commands\Command.txt   （可选，由用户创建）
```

iOS/Apple CLI 默认使用用户 Documents 下的 `Commands/`，与原 iOS 软件可写目录语义一致。

交互会话成功 `:open` 世界后，如果检测到非空 `Command.txt`，会询问是否执行。确认后先对整个文件做语法预检：任一语法错误则整批一条也不执行；预检通过后按物理行顺序执行。运行时某条命令失败会记录该行错误并继续执行后续命令，最终会话退出码仍保留失败状态。若用户在运行错误后选择 `:save`，可以保存其余成功命令留下的工作副本修改。

无人值守/非交互模式不会等待确认；需要明确调用：

```text
mcbe-cli --world "世界.mcworld" --script "Commands/Command.txt" --in-place
```

`Command.txt` 与 `--check-file`/`--script` 共用严格 UTF-8/BOM、LF/CRLF/CR、空行忽略和原始物理行号处理。

## 解析边界

两端对语法关键字和语义参数分别处理：

- 根命令、子命令、维度、tickingarea shape、time/weather 等**语法关键字**在 Windows 与 Swift 上都按大小写不敏感处理。
- `ALL`、`Auto`、`default`、NBT 字符串、结构名/区域名、identifier 等**语义参数**仍遵守原命令规则；例如 `effect clear @e all` 继续无效，而 `EfFeCt ClEaR @e ALL` 有效。
- CLI 方块编辑/查询坐标 X/Y/Z 的公共输入范围统一为 `Int32`。Swift 底层 `CommandBlockCoordinate` 的 X/Z 类型仍保留 Int64，以免无关重构数据层，只在 CLI 解析边界收紧。
- `CLI/Shared/parser-cases.json` 已不再使用 `expected_by_backend`，新增 mixed-case、Int32 极值/溢出以及语义大小写 fixture，两端进程烟雾测试读取同一套预期。

这不改变 `give` 数量等本来就是 Int64 的非坐标字段，也不改变实体浮点坐标、UniqueID/NBT Long 等原有范围。

## entity 实体查询

```text
mcbe-cli --world "MyWorld" --command "entity"
mcbe-cli --world "MyWorld" --command "entity overworld"
mcbe-cli --world "MyWorld" --command "entity overworld -16 0 -16 16 128 16"
```

`entity [维度 [x1 y1 z1 x2 y2 z2]]` 为只读查询，无需 `--output` 或 `--in-place`。
无参数列出全部维度普通实体；只写维度列出该维度全部实体；两角定义包含边界的长方体，支持小数、负数及反向角点，按实际实体坐标筛选。
维度为 `overworld`、`nether`、`the_end`，不包含玩家或方块实体。缺少坐标的实体仍出现在无范围查询中。
每个实体一行：`minecraft:pig=['String'"identifier"="minecraft:pig",'Long'"UniqueID"="12345678"]`。
类型复用实体栏目的识别；NBT 使用 `getblock` 的完整递归格式，不补写推断出的标签。
混合子类型的嵌套列表会给每个子列表显式标注类型；这种扩展展示用于完整查看 NBT，不作为命令输入格式。
损坏记录及孤立 actor 等扫描诊断显示为“entity 扫描提示”。

## summon UniqueID 与直接 NBT 输入

```text
summon minecraft:pig overworld 0 64 0 default Auto
summon minecraft:pig overworld 0 64 0 default 9007199254740993
summon 'String'"identifier"="minecraft:cow",'List''Float'"Pos"="0.0,64.0,0.0",'Long'"UniqueID"="12345678"
```

第一种格式为 `summon 实体类型 维度 x y z NBT标签或default [UniqueID]`。末尾填写 `Auto` 自动生成 ID，或填写非零的有符号 64 位整数；省略仍按 `Auto` 处理，兼容原有脚本。手动 Long 保留全部精度，ID 冲突时拒绝创建。

第二种格式直接保存标签、类型和顺序，不填充实体通用 NBT。必须包含三个可写入 Float 的有限数值组成的 `Pos`（或 `Position`）List；提供的 `UniqueID` 必须是非零 Long，缺少时自动追加。`DimensionId`（或 `Dimension`）应为 Int32 范围内的整数标签，缺少时存入主世界，不补写维度标签；追加 `'Int'"DimensionId"="1"` 可写入下界。关键字段及其别名不能重复。

CLI 批处理的 `summon` 仍需 `--output` 或 `--in-place`。含有引号的 NBT 建议写入 UTF-8 命令文件，通过 `--script` 执行，避免外壳处理引号。

## 帮助、预检和退出码

```text
mcbe-cli --help
mcbe-cli --help structure
mcbe-cli --help convert
mcbe-cli --list-commands
mcbe-cli --version
mcbe-cli --check "weather query"
mcbe-cli --check-file "Commands/Command.txt"
```

27 个根命令继续复用原解析器和存档业务逻辑。命令不需要 `/` 前缀。

退出码：`0` 成功；`1` 命令运行失败；`2` 参数或整批预检失败；`3` 文件/编码/保存错误；`130` 取消。交互 Command.txt 的运行错误或预检错误会保留到最终退出状态，即使用户随后保存并正常 `:quit`。

## 构建与验证

Windows 开发/回归构建：

```powershell
./CLI/Scripts/build-windows.ps1 -Test
```

Windows **最终单 exe**：

```powershell
./CLI/Scripts/build-windows-release.ps1 -Test
```

需要 .NET 10 SDK、Visual Studio C++ 工具链、CMake、Python。release 脚本先运行普通构建/累计测试，再将 CLI 发布成 self-contained single-file payload，并把 payload 嵌入专用 console launcher。最终 `CLI/Windows/dist/` 必须只包含一个 `mcbe-cli.exe`。脚本会复制该最终外层 exe 到空临时目录，实际执行 `--version`、`--help`、`--check`，验证重定向输出没有 ANSI、`Commands/ReadMe.txt` 创建在外层 exe 同级且不自动创建 `Command.txt`，并检查 payload runtime 没有残留。

launcher 不采用 GUI 的单实例限制，也不会递归清空整个 `Cache`。每个进程仅使用 `Cache/Runtime/<pid>` 释放内部 payload 和 .NET bundle；世界失败副本/`--keep-work` 数据仍可留在 `Cache/Worlds`。`MCBEEDITOR_PORTABLE_ROOT` 与 `MCBEEDITOR_CACHE_ROOT` 使托管 payload 即使从 Cache 启动，Commands/世界缓存仍按绿色软件外层目录解释。

Apple/macOS host 验证与 **iOS arm64 裸二进制**：

```sh
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
bash CLI/Scripts/build-apple.sh ios CLI/build/apple-ios
```

需要 macOS、Xcode、CMake、git 和 Python。host `--test` 运行累计源码门禁、原末地缺失高层/255 storage 回归、进程 smoke 与真实 LevelDB 集成测试。iOS 构建直接输出 `CLI/build/apple-ios/mcbe-cli`，目标是 `arm64-apple-ios13.0`；脚本用 `lipo`/`vtool` 校验架构和最低系统，再用 `codesign -s -` 进行 ad-hoc 结构签名并验证。**不生成 deb**。GitHub Actions 的 `MCBEEditor-CLI-iOS13-arm64` artifact 直接上传这个 Mach-O 文件；artifact 下载后如权限丢失，需要在设备部署前执行 `chmod +x mcbe-cli`。

独立发布工作流为 `.github/workflows/cli-release.yml`：Windows job 上传 `CLI/Windows/dist/mcbe-cli.exe`，macOS job 先跑 host 原生测试再交叉编译并上传 iOS 裸二进制。

通用源码检查：

```sh
python3 CLI/Tests/source_audit.py
python3 CLI/Tests/build_audit.py
```

针对已构建的可执行文件：

```sh
python3 CLI/Tests/smoke.py --backend windows -- 路径/mcbe-cli.exe
python3 CLI/Tests/session_smoke.py --fixture-tool CLI/build/native-tests/mcbe_cli_create_test_db.exe -- 路径/mcbe-cli.exe
python3 CLI/Tests/environment_smoke.py --fixture-tool CLI/build/native-tests/mcbe_cli_create_test_db.exe -- 路径/mcbe-cli.exe
# Apple host 将 --backend 改为 swift，并使用 host 二进制。
# Apple fixture tool 位于 CLI/build/apple-host/native/tools/mcbe_cli_create_test_db。
```

`smoke.py` 检查帮助、全部根命令的公共解析用例、UTF-8/物理行号和格式转换。`session_smoke.py` 与 `environment_smoke.py` 用原生工具生成真实空数据库，并使用手工编码的最小 level.dat 检查输入恢复、工作副本、保存和环境命令；维度预检会打开数据库，不能再用只有空 db 文件夹的世界。两端测试构建入口会先构建夹具工具并传入 `--fixture-tool`。这些测试仍不代替区块、实体等完整原生集成测试。Windows 构建以 Python UTF-8 模式运行测试，会话和环境测试也会将自身日志设为 UTF-8，保证中文失败信息正常输出。macOS 进程测试应使用没有自定义 `~/Documents/Commands/Command.txt` 的测试账户，避免批处理提示影响输入。POSIX 下另测 SIGINT 取消后的输入不能触发保存；Windows 控制台 Ctrl-C 的实际即时响应仍需目标终端验证。

上述检查与现有 C# 核心回归、Swift/C# 原生 LevelDB 集成测试继续由平台构建的 `-Test` / `--test` 入口运行。历史阶段日志、哈希快照、按 stage 分割的校验和重复工作流已经清理；当前发布入口统一为 `cli-release.yml`。本轮没有移除核心存档测试、夹具、GUI、图标、许可证或第三方声明。

## 后续检查

分轮计划见 [审计计划](../docs/superpowers/plans/2026-09-21-mcbeeditor-cli-audit-plan.md)，当前轮次与下一步只在 [FINAL_REVIEW.md](Docs/FINAL_REVIEW.md) 更新。各轮源码、静态检查、原生运行和游戏验收分别记录；结构、转换、地图与对象专项未闭环前不能结案。

第 8 轮补充：`nbt_conversion_smoke.py` 已接入双端构建测试，独立检查三种二进制编码、JSON、压缩与文件保护。JSON 导出的 Long/LongArray 使用十进制字符串；Compound 重名标签无法由当前 JSON 对象格式完整表示，导出会拒绝。匿名数值根等大小端歧义输入仍按原优先顺序探测，显式输入编码选项待补，详见 [第 8 轮记录](Docs/AUDIT_ROUND08.md)。

第 9 轮补充：structure 文件操作在执行前检查来源、缓存、脚本、同批结构输入与输出冲突；先导出再导入同一路径请分两次执行。新增 `structure_file_smoke.py` 已接入构建测试；结构加载的普通实体和多于两层 storage 不在本轮新增能力范围内。
