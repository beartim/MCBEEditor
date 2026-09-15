# MCBEEditor CLI

当前 CLI 版本为 **1.0.0**。Windows x64 继续发布绿色单 `mcbe-cli.exe`，iOS 继续发布最低 iOS 13 arm64 裸二进制；独立 NBT/mcstructure 格式转换保持为工具功能，不加入 NBT 编辑器功能。

源码审计与 Linux Swift 前端语法解析可在当前环境运行；当前环境没有 .NET/PowerShell，也不是 macOS/Xcode，因此新 Windows 单 exe 的真实发布/启动、Apple Objective-C++/LevelDB 链接、iOS arm64 裸二进制、GitHub Actions 和 Minecraft 实际读档仍是独立的未运行门禁。发布脚本和 Actions 已接线，但不要把静态检查写成平台构建通过。

## 一次性执行与保存

修改命令必须明确选择 `--in-place` 或 `--output`；纯查询可以不指定保存方式。

```text
mcbe-cli --world "D:\Worlds\My World" --command "time set 6000" --in-place
mcbe-cli --world "D:\Worlds\My World.mcworld" --script "Commands\Command.txt" --in-place
mcbe-cli --world "D:\Worlds\My World.mcworld" --command "weather query" --output "D:\Output\Copy.mcworld"
```

`--in-place` 支持世界文件夹和 `.mcworld`；普通 ZIP 只能另存为 `.mcworld`。`--output` 与 `--in-place` 互斥，覆盖已有输出需 `--overwrite`。两种方式都先修改工作副本；一次性原位模式只在整批命令全部成功后提交，另存为保持既有“运行时错误后继续后续命令并可导出当前副本、最终返回失败”的行为。

mcworld 原位提交保留原容器中的世界根目录层级、世界外文件和编辑器私有文件，排除世界数据库 `db/LOCK`；另存为继续沿用 GUI 导出规则，只导出世界根并过滤编辑器私有元数据。Swift 与 Windows 成功原位提交后都会刷新源内容指纹，因此同一持续会话可以再次修改并再次 `:save`，同时仍能识别真正的外部源变化。

## 独立 NBT / mcstructure 格式转换（stage06）

转换工具**不需要 `--world`**，只读输入文件并生成新文件；不会进入 NBT 编辑器，也不会修改标签内容。

```text
mcbe-cli --convert "input.nbt" --to big-endian --output "output-big.nbt"
mcbe-cli --convert "input.nbt" --to little-endian --output "output-little.nbt"
mcbe-cli --convert "input.nbt" --to little-varint --output "output-varint.nbt"
mcbe-cli --convert "input.mcstructure" --to json --output "output.json"
mcbe-cli --convert "java-structure.nbt" --to mcstructure --output "output.mcstructure"
```

可用 `mcbe-cli --help convert` 查看同一说明。输出文件已存在时默认拒绝覆盖；显式加 `--overwrite` 才覆盖。输出扩展名必须与目标格式匹配：前三种二进制编码使用 `.nbt`，JSON 使用 `.json`，Bedrock structure 使用 `.mcstructure`。

输入由现有 `StandaloneNbtFileCodec` 自动识别：**Big Endian、Little Endian、Little Endian VarInt、JSON NBT、连续多根 NBT，以及 GZip/Zlib 包装的 NBT**。二进制输出统一为未压缩。多根 NBT 可在三种 NBT 编码和 JSON 之间互转；`.mcstructure` 只接受单根结构 NBT。Java structure NBT 转 `.mcstructure` 时继续复用现有 Java→Bedrock 转换器，因此兼容降级规则与 GUI 保持一致。

目标格式名固定为：`big-endian`、`little-endian`、`little-varint`、`json`、`mcstructure`。stage06 没有复制 GUI 编辑逻辑，Windows/Swift 两端只调用原 NBT codec 与 structure converter。

## structure 文件接口（04a）

CLI 不打开 GUI 文件选择器，使用显式路径：

```text
structure import my:house --file "D:\Structures\house file.mcstructure"
structure import my:house --file "D:\Structures\house file.nbt" --overwrite
structure import my:house --file "D:\Structures\house file.json"

structure export mcstructure my:house --file "D:\Output\house.mcstructure"
structure export nbt my:house --file "D:\Output\house.nbt"
structure export json my:house --file "D:\Output\house.json" --overwrite
```

支持 `.mcstructure`、Big Endian `.nbt` 和保留 NBT 类型信息的 `.json`。路径可包含空格，需在命令字符串内使用引号。导入同名结构或导出覆盖已有文件都必须显式 `--overwrite`。两端直接复用现有 Standalone NBT codec、Java→Bedrock 转换器和结构存储，不另写格式算法。

一次性 `--command/--script` 模式下，structure import/export 的结构名和 `--file` 都必须完整提供；漏项在整批预检阶段失败。交互模式允许省略名称并按提示输入；export 会先列出已有结构。

## 持续交互会话（04b～04c）

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

`:open ... --in-place` 允许无路径 `:save` 原位提交；普通 `:open` 只打开工作副本，保存时需给出另存为路径。保存成功后会话保持打开。潜在修改命令如果在运行中抛错，dirty 状态保守保持，因为原业务命令可能已经完成部分写入；`:quit` 不允许静默丢弃，需先保存或显式 `:quit --discard`。

04c 在真实终端加入历史 ↑/↓、←/→ 光标、Home/End、Backspace/Delete、`:history` 与 `:clear`。`clear` 没有冒号，仍是原游戏“清除物品”命令，不与清屏混用。

真实 TTY 输出按原命令结果类型使用 ANSI 样式；错误为红色，玩家/实体/方块等保持各自终端颜色映射。stdin 或 stdout 不是 TTY 时禁用原始按键行编辑；stdout 重定向时不输出 ANSI/重绘序列，stderr 是否着色单独依据 stderr 自身是否为 TTY，因此 `>out.txt`、`2>err.txt` 和管道得到纯文本。

## Commands 目录与 Command.txt（04d）

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

## 解析边界对齐（04e）

stage04e 只修复已经记录的双端差异，没有把整条命令统一转小写：

- 根命令、子命令、维度、tickingarea shape、time/weather 等**语法关键字**在 Windows 与 Swift 上都按大小写不敏感处理。
- `ALL`、`Auto`、`default`、NBT 字符串、结构名/区域名、identifier 等**语义参数**仍遵守原命令规则；例如 `effect clear @e all` 继续无效，而 `EfFeCt ClEaR @e ALL` 有效。
- CLI 方块编辑/查询坐标 X/Y/Z 的公共输入范围统一为 `Int32`。Swift 底层 `CommandBlockCoordinate` 的 X/Z 类型仍保留 Int64，以免无关重构数据层，只在 CLI 解析边界收紧。
- `CLI/Shared/parser-cases.json` 已不再使用 `expected_by_backend`，新增 mixed-case、Int32 极值/溢出以及语义大小写 fixture，两端进程烟雾测试读取同一套预期。

这不改变 `give` 数量等本来就是 Int64 的非坐标字段，也不改变实体浮点坐标、UniqueID/NBT Long 等原有范围。

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

26 个根命令继续复用原解析器和存档业务逻辑。命令不需要 `/` 前缀。

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

stage06 在当前 Linux 环境继续执行累计源码审计、Python/bash/JSON/YAML 静态检查与 Swift `-frontend -parse`；新增的双端原生集成测试源码会在 Windows/macOS `-Test` 构建时实际跑转换链。因为这里仍不是 Windows/.NET 或 macOS/Xcode 环境，Windows 最终 EXE、Apple 原生链接、iOS arm64/codesign 及真实转换进程测试仍需对应平台确认。

## 最终状态与后续维护

stage05c 仍作为此前全量审计基线；当前功能快照为 stage06。后续优先读取 `WORK_FINAL_REPORT.md` 与 `WORK_CHECKPOINT.md`；不要用 stage05c 或更早快照覆盖当前工程。若 Windows/macOS Actions、iOS 设备或 Minecraft 实际读档出现失败，以真实日志为准修复，并重新执行累计 stage05c + stage06 门禁与对应平台发布脚本。
