# MCBEEditor CLI Stage 05a 报告：Windows x64 单 exe 发布

日期：2026-09-15。输入基线为 `stage04e`。本阶段只增加 Windows CLI 的发布/启动层，不修改 LevelDB、NBT、区块、命令执行和存档提交算法。

## 已实现源码

1. 新增 `CLI/Windows/CliPortablePaths.cs`。外层 launcher 可通过 `MCBEEDITOR_PORTABLE_ROOT` 与 `MCBEEDITOR_CACHE_ROOT` 把用户可见目录固定到外层 `mcbe-cli.exe` 同级；普通开发构建没有这些变量时仍退回 `AppContext.BaseDirectory`。
2. `CliRunOptions`、`CliInteractiveShell`、`CliSharedCommandStore` 的默认 `Cache/Worlds` 与 `Commands` 改为统一使用 `CliPortablePaths`。显式 `--cache-dir` 仍优先，不改变已有参数语义。
3. 新增 `CLI/Windows/PortableLauncher/`：
   - console subsystem，不使用 GUI 单实例锁；
   - 将 self-contained/single-file 托管 payload 作为 RCDATA 嵌入最终 exe；
   - 每个进程只释放到 `Cache/Runtime/<pid>`，设置 `DOTNET_BUNDLE_EXTRACT_BASE_DIR`；
   - stdin/stdout/stderr 与全部参数传给托管 CLI，最终返回托管进程退出码；
   - 退出时只删除自己的 runtime，不递归删除整个 Cache，避免丢失失败恢复副本或 `--keep-work` 数据；
   - 保持调用者当前工作目录，不像 GUI launcher 那样切换到 exe 目录，因此 `--world .\World`、相对 `--script/--check-file` 仍按 shell 当前目录解析。
4. 新增 `CLI/Scripts/build-windows-release.ps1`：
   - 先运行现有开发构建，可用 `-Test` 跑累计回归；
   - `dotnet publish -r win-x64 --self-contained true`；
   - `PublishSingleFile=true`、`IncludeNativeLibrariesForSelfExtract=true`、`IncludeAllContentForSelfExtract=true`，把运行时、本机 DLL 与内容收进单 payload；
   - payload 发布目录必须恰好只有 `mcbe-cli.exe`；
   - 再用 CMake/MSVC 构建外层 console launcher；
   - `CLI/Windows/dist/` 最终必须恰好只有一个 `mcbe-cli.exe`。
5. release 脚本不会只检查“文件存在”。它把最终外层 exe 复制到空临时 `bin`，从另一 `cwd` 实际执行 `--version`、`--help`、`--check`、相对 `--check-file`；同时检查重定向无 ANSI、Commands 位于外层 exe 同级、不会自动创建 `Command.txt`、payload runtime 不残留。
6. Windows 原生集成测试源码增加 portable root/cache 环境变量的路径断言。
7. `.github/workflows/cli-release.yml` 新增 Windows job：`windows-latest` + .NET 10 + Python 3.12，执行 `build-windows-release.ps1 -Test`，只上传 `CLI/Windows/dist/mcbe-cli.exe`。

## TDD / 复核记录

`CLI/Tests/stage05a_source_audit.py` 先在 stage04e 基线上运行并按预期失败，证明旧快照没有 05a 发布链；实现后转绿。

交付前审阅又发现外层 launcher 最初沿用了 GUI 的 `SetCurrentDirectory(exeRoot)` 思路，这会破坏 CLI 相对路径。门禁先扩充为“禁止 launcher 改 CWD + 最终 exe 相对文件探针”，在旧实现上再次观察失败，再删除 CWD 改写并让 child 继承调用者目录，门禁转绿。

## 当前环境实际验证

当前 Linux 环境实际可运行并通过：累计 Python 源码审计、Python 语法检查、YAML 解析、Swift 前端语法解析以及 shell 语法检查。05a 新源码审计已通过。

当前环境没有 `dotnet`、`pwsh`、MSVC/Windows SDK，因此以下内容**没有运行**：

- `dotnet publish win-x64`；
- Windows C++ launcher 编译/资源嵌入；
- 最终外层 `mcbe-cli.exe` 的真实启动探针；
- Mojang LevelDB Windows 原生集成回归；
- GitHub Actions Windows job。

这些真实平台门禁已经写进 `build-windows-release.ps1 -Test` 和 `.github/workflows/cli-release.yml`，但本报告不把源码接线写成平台构建通过。
