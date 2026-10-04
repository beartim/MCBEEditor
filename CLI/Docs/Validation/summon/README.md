# summon 本轮验证记录

日期：2026-10-02。源码版本：1.0.0。环境：Linux x86_64、.NET SDK 10.0.100、Swift 5.10.1。

所有随附最终日志对应的命令均返回 0。主要入口：

```sh
bash Scripts/run_core_tests.sh
dotnet build Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release
dotnet Windows/MCBEEditor.Core.SelfTest/bin/Release/net10.0/MCBEEditor.Core.SelfTest.dll
dotnet build CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj -c Release
dotnet CLI/Windows.Tests/bin/Release/net10.0/MCBEEditor.Cli.Tests.dll /path/to/mcbe_cli_create_test_db
python3 CLI/Tests/smoke.py --backend windows -- dotnet CLI/Windows/bin/Release/net10.0/mcbe-cli.dll
dotnet build Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj -c Release -p:EnableWindowsTargeting=true
python3 CLI/Tests/source_audit.py
swiftc -frontend -parse CLI/iOS/CliCommandPlan.swift CLI/iOS.Tests/NativeIntegration.swift
```

原生测试使用项目固定版本的 LevelDB/zlib 与 Windows/Native 构建出来的 Linux 共享库；运行时将其目录加入 LD_LIBRARY_PATH。Swift 在本环境通过临时包装器使用单编译进程、whole-module-optimization（保留默认 Onone 和断言）、显式 Clang 资源目录及可写模块缓存；没有修改项目构建脚本的编译参数。

- Swift 全量测试包含新增 summon 存储回归及全部 192 个共享解析用例。
- C# 全量与原生集成覆盖 raw/normal ID 冲突、损坏尾部前的完整 digp 引用、Auto 重试、旧式存储、精确 Long、原始 NBT 字节、导出重新打开。
- CLI 冒烟结果：253 process checks / 192 parser cases / 27 commands。
- C# Core、CLI、WPF 编译均为 0 警告、0 错误。
- swift-cli-syntax-final.log 为空，表示语法检查正常退出且没有诊断。
- POSIX 上的两个 Windows FileShare 测试按原有条件跳过；iOS 真机、完整 Xcode 构建与 Windows GUI 实际运行未执行。

`files.sha256` 覆盖本次交付源码及文档，不包括历史验证目录、本验证目录或临时检查点。完整说明见根目录 CHANGES_SUMMON_COMMAND.md。
