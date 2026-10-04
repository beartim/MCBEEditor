# entity 更新验证记录

运行环境：Linux x86_64，.NET SDK 10.0.100，Swift 5.10.1，CMake 3.31.6。以下日志对应本次交付源码，所有列出的验证命令退出码均为 0。

| 日志 | 检查内容 |
| --- | --- |
| source-audit-final.log | 27 个命令、160 个解析用例、共享帮助及执行路由 |
| swift-core-final.log | Swift 全量核心回归及新增 entity 查询回归 |
| csharp-core-build.log | C# Core.SelfTest Release 编译 |
| csharp-core-final.log | C# 全量核心测试、200,001 条实体及混合列表测试 |
| csharp-cli-build.log | C# CLI 与测试项目 Release 编译 |
| csharp-native-final.log | 真实 LevelDB entity 查询及原有 44 个 CLI 场景 |
| cli-smoke-final.log | Windows CLI：221 个进程检查、160 个解析用例 |
| wpf-build-final.log | WPF 交叉编译，0 警告、0 错误 |
| native-build.log | LevelDB 原生桥接库及测试夹具工具编译 |
| files.sha256 | 交付源文件及说明文件的 SHA-256；不包括本目录日志 |

从源码根目录运行：

```sh
python3 CLI/Tests/source_audit.py
bash Scripts/run_core_tests.sh
dotnet build Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release --nologo -m:1 -p:BuildInParallel=false -nodeReuse:false
dotnet Windows/MCBEEditor.Core.SelfTest/bin/Release/net10.0/MCBEEditor.Core.SelfTest.dll
dotnet build CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj -c Release --nologo -m:1 -p:BuildInParallel=false -nodeReuse:false
dotnet build Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj -c Release -p:EnableWindowsTargeting=true --nologo -m:1 -p:BuildInParallel=false -nodeReuse:false
python3 CLI/Tests/smoke.py --backend windows -- dotnet "$PWD/CLI/Windows/bin/Release/net10.0/mcbe-cli.dll"
```

真实 LevelDB 集成额外使用：

```sh
bash CLI/Scripts/bootstrap-apple-native.sh
cmake -S Windows/Native -B ../native-build -DCMAKE_BUILD_TYPE=Release -DLEVELDB_MCPE_ROOT="$PWD/CLI/build/deps/leveldb-mcpe" -DZLIB_SOURCE_ROOT="$PWD/CLI/build/deps/zlib" -DMCBE_BUILD_CLI_TEST_TOOLS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build ../native-build --parallel 2
LD_LIBRARY_PATH="$PWD/Windows/Native/bin/x64" dotnet CLI/Windows.Tests/bin/Release/net10.0/MCBEEditor.Cli.Tests.dll "$PWD/CLI/build/native-tests/mcbe_cli_create_test_db"
```

本环境为避免 Swift 并行编译器崩溃，通过临时 swiftc 包装器将 `-j 4` 替换为 `-j 1 -whole-module-optimization`；未开启优化，所有 precondition 仍执行。该包装器不属于产品源码，源码脚本保留既有编译参数。

平台限制：Swift 核心测试使用内存数据库替身，并运行实际解析器、扫描器、NBT 编解码与命令执行实现。Apple 原生 CLI、iOS App 构建及设备运行未在本环境验证；WPF 仅交叉编译，未运行 GUI。C# 原生集成中的两个 Windows FileShare 专用测试在 Linux 按既有逻辑跳过，详见日志。
