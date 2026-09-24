# 第 15 轮最终验证日志

日期：2026-09-24。此目录记录续接恢复后的实际执行输出。Ubuntu 24.04、.NET 10.0.100、Swift 5.10.1、CMake 3.31.6。全部所列入口 exit 0；regression-results.json 记录进程/集成/静态入口退出码。日志中历史测试标题含“iOS semantics”“Windows parity”仅描述对照目标，不代表相应 OS 已执行。

core-final / swift-core-final 为完整核心回归；cli-build / wpf-final / native-csharp-final 为构建；native-build 为真实 C++/Mojang LevelDB 构建；native-integration-final 为 C# 调用真实 Linux .so 的 44 项集成，两个 Windows FileShare 用例明确 SKIP。其他文件按原脚本名命名。没有复制丢失的首轮原始失败日志；先前复现事实见 AUDIT_ROUND15.md 的会话记录说明。

在源码根目录、工具已位于 PATH 的等价 Linux 环境可复跑：

```bash
dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release
bash Scripts/run_core_tests.sh
dotnet build CLI/Windows/MCBEEditor.Cli.csproj -c Release --nologo
dotnet build Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj -c Release -p:EnableWindowsTargeting=true --nologo
python3 CLI/Tests/smoke.py --backend windows -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/session_smoke.py -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/environment_smoke.py -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/nbt_conversion_smoke.py -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
python3 CLI/Tests/structure_file_smoke.py -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
```

Swift 使用本地解压的 libncurses6 支持库；这属于 Linux 审计环境，不修改 Apple 链接规则。C# 集成项目使用串行 MSBuild，避免本环境并行项目图异常。

```bash
bash CLI/Scripts/bootstrap-apple-native.sh
cmake -S Windows/Native -B /tmp/mcbe-round15-native -DCMAKE_BUILD_TYPE=Release -DLEVELDB_MCPE_ROOT="$PWD/CLI/build/deps/leveldb-mcpe" -DZLIB_SOURCE_ROOT="$PWD/CLI/build/deps/zlib" -DMCBE_BUILD_CLI_TEST_TOOLS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build /tmp/mcbe-round15-native --parallel 4
dotnet build CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj -c Release --nologo -m:1 -p:BuildInParallel=false -nodeReuse:false
LD_LIBRARY_PATH="$PWD/Windows/Native/bin/x64" dotnet CLI/Windows.Tests/bin/Release/net10.0/MCBEEditor.Cli.Tests.dll "$PWD/CLI/build/native-tests/mcbe_cli_create_test_db"
```

静态/流程入口为 CLI/Tests 下 source_audit.py、build_audit.py、gui_nbt_audit.py、map_projection_audit.py、windows_gui_overlap_click_audit.py、apple_build_lifecycle.py。最后一个使用工具替身；不能当作 Apple 原生编译/签名。syntax.log 列出四个 shell 和十二个 Python 文件的语法检查。

files.sha256 从源码包根目录以 `sha256sum -c CLI/Docs/Validation/round15/files.sha256` 校验，不包含自身。changes.json 比较第 14 轮基线，记录新增、变更与未删除情况。平台/GUI/游戏待验收仍见上级报告，不由这些日志升级。
