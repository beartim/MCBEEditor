# CLI 构建测试修复验证

日期：2026-10-04。基于完整源码包 `MCBEEditor-iOS-Windows-CLI-v1.0.0-dimension-final.zip` 的上一版内容，输入源码 ZIP 的 SHA-256 为 `00cb683a684a891cfd3f69908ceb9a51442f97d44b682adf920086a4ab167669`。修复说明见根目录 `CHANGES_CLI_BUILD_FIX_20261004.md`。

## 本次执行结果

| 检查 | 最终结果 | 日志 |
| --- | --- | --- |
| 原生 C++ LevelDB 与数据库夹具构建 | 通过 | native-build.log |
| C# CLI 编译 | 0 warnings / 0 errors | csharp-build.log |
| 会话生命周期 | 14/14；强制 CP1252 下通过 | session-final.log |
| 环境与批处理 | 7/7；强制 CP1252 下通过 | environment-final.log |
| UTF-8 诊断与夹具错误 | 2 个测试方法通过；中文输出含 CP1252/UTF-8 子用例 | support-final.log |
| CLI 进程与解析 | 293 检查、231 解析用例、28 类命令 | process.log |
| NBT 转换 | 46 次实际 CLI 调用 | nbt-conversion.log |
| MCBE-SNBT | 48 场景、101 次实际 CLI 调用 | mcbe-snbt.log |
| 结构文件预检 | 16 次实际 CLI 调用 | structure-files.log |
| C# CLI 原生集成 | 44 项主集成；附加维度、实体、summon、MCBE-SNBT 回归通过 | native-tests.log |
| 完整 C# 核心回归 | 通过 | csharp-core.log |
| 完整 Swift 共享核心回归 | 退出码 0；88 行日志；末尾 98 项 source audit 门禁存在 | swift-core-full.log / swift-core-result.json |
| ID / 中文名称对照 | 两端各 565 行、实体 lookup 和中文搜索通过 | catalog-sync.log |
| 固定 ReadMe 运行时写入 | 四个写入器通过；用户 Command.txt 保留 | fixed-readme.log |
| Apple 构建 shell 生命周期 | 通过；包括 host 夹具顺序与失败时产物保留 | apple-lifecycle-final.log |
| PowerShell 脚本语法 | 两个脚本通过 | powershell-syntax.log |
| 源码与构建接线 | 通过 | source-audit-final.log / build-audit-final.log |

`csharp-results.json`、`process-results.json`、`final-check-results.json` 保存对应检查的退出码，全部为 0。`swift-core-result.json` 同时确认总入口完成和最后门禁输出，避免将子集日志当作总入口结果。`swift-snbt-initial.log` 只记录首个 MCBE-SNBT 子集；全套以 `swift-core-full.log` 为准。

## 红/绿证据

- `uploaded-ios-build.log` / `uploaded-windows-build.log`：用户上传的原始 build step 日志。
- `session-red.log`：在修复前的真实 C# CLI 上复现 10/14 会话失败。
- `environment-red.log`：在修复前复现环境命令因无效数据库失败。
- `encoding-red.log`：在 CP1252 strict 环境复现原始中文日志 `UnicodeEncodeError`。
- `encoding-regression-red.log`：受控移除 UTF-8 配置时，中文错误输出回归按预期失败；配置已恢复。
- `fixture-diagnostic-red.log`：加入诊断断言后、修复前，夹具底层错误文本缺失的回归按预期失败。
- `apple-lifecycle-red.log`：修改构建脚本前，host 分支未提前构建和传递夹具工具，新增行为门禁按预期失败。
- 所有 `*-green.log` 与 `*-final.log` 均为修复后的通过记录。红日志是已解决问题的证据。

## 可复跑命令

目标发布在对应操作系统运行现有入口：

```powershell
./CLI/Scripts/build-windows-release.ps1 -Test
```

```bash
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
bash CLI/Scripts/build-apple.sh ios CLI/build/apple-ios
```

Ubuntu 下验证 C# CLI 和真实原生库，可在已安装 .NET 10 / CMake / git / C++ 编译器的环境运行：

```bash
bash CLI/Scripts/bootstrap-apple-native.sh
cmake -S Windows/Native -B CLI/build/linux-native \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DLEVELDB_MCPE_ROOT="$PWD/CLI/build/deps/leveldb-mcpe" \
  -DZLIB_SOURCE_ROOT="$PWD/CLI/build/deps/zlib" \
  -DMCBE_BUILD_CLI_TEST_TOOLS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build CLI/build/linux-native --parallel 4
dotnet build CLI/Windows/MCBEEditor.Cli.csproj -c Release -m:1 -p:BuildInParallel=false -p:UseSharedCompilation=false
export LD_LIBRARY_PATH="$PWD/Windows/Native/bin/x64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
python3 CLI/Tests/smoke.py --backend windows -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
PYTHONIOENCODING=cp1252:strict python3 CLI/Tests/test_smoke_support.py
PYTHONIOENCODING=cp1252:strict python3 CLI/Tests/session_smoke.py \
  --fixture-tool "$PWD/CLI/build/native-tests/mcbe_cli_create_test_db" \
  -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
PYTHONIOENCODING=cp1252:strict python3 CLI/Tests/environment_smoke.py \
  --fixture-tool "$PWD/CLI/build/native-tests/mcbe_cli_create_test_db" \
  -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/nbt_conversion_smoke.py -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/mcbe_snbt_smoke.py --backend cli -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/structure_file_smoke.py -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
dotnet build CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj -c Release -m:1 -p:BuildInParallel=false -p:UseSharedCompilation=false
dotnet CLI/Windows.Tests/bin/Release/net10.0/MCBEEditor.Cli.Tests.dll "$PWD/CLI/build/native-tests/mcbe_cli_create_test_db"
dotnet build Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release -m:1 -p:BuildInParallel=false -p:UseSharedCompilation=false
dotnet Windows/MCBEEditor.Core.SelfTest/bin/Release/net10.0/MCBEEditor.Core.SelfTest.dll
```

Swift 核心及固定文案检查需要 Swift 编译器和 .NET 在 PATH 中：

```bash
bash Scripts/run_core_tests.sh
python3 Scripts/test_catalog_sync.py
python3 Scripts/test_fixed_readme.py
python3 CLI/Tests/apple_build_lifecycle.py
python3 CLI/Tests/source_audit.py
python3 CLI/Tests/build_audit.py
```

## 环境与范围

实际执行环境为 Ubuntu 24.04、.NET 10.0.401、Swift 6.2.3、CMake 3.31.6、Python 3.12.14。原生依赖来自既有 pinned tag：leveldb-mcpe `0.8.0a8`（`327630b4ce17986963b80bf4dbcba32b19c13b88`）、zlib `v1.3.1`（`51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf`）。本地 Swift 编译适配只将显式 `-j` 参数设为 1，未修改项目脚本或源码。

Apple 生命周期测试使用工具替身，仅证明实际 shell 的编排、参数与产物保留。PowerShell 语法由实际 7.5.2 parser 校验。两项 Windows FileShare 行为在 POSIX 集成中明确 SKIP；这些检查都不升级为 Apple SDK、iOS 设备、Windows 单 EXE、Windows Ctrl-C、GUI 或 Minecraft 读档验证。

用户上传的两个日志 ZIP 与示例 `.mcworld` 均未修改。只读代码复核最终没有未处理问题。
