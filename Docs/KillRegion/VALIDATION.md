# kill 范围目标验证

日期：2026-10-28。来源为本次上传源码；只修改本次命令补充、相关删除修复、测试和说明。

| 检查 | 结果 |
| --- | --- |
| `dotnet run --project Windows/MCBEEditor.Core.SelfTest -- --kill-region` | 通过：两种开关、正反角点、重复 ID、连续实体与现代 actor、四种玩家模式、区域外／跨维度、空选择、旧选择器 |
| `dotnet run --project Windows/MCBEEditor.Core.SelfTest --no-build` | 完整核心自测通过，包含新增混合 actor 根回归 |
| `bash Scripts/run_core_tests.sh` | 完整 Swift 核心测试通过，包含 276 个共享解析样例及新增范围／混合 actor 根回归 |
| `dotnet build CLI/Windows.Tests/MCBEEditor.Cli.Tests.csproj --disable-build-servers -m:1` | 通过，0 警告、0 错误 |
| `python3 CLI/Tests/smoke.py --backend windows -- dotnet <mcbe-cli.dll绝对路径>` | 338 项进程检查、276 个解析用例、28 个命令通过 |
| `python3 CLI/Tests/source_audit.py` | 命令路由、双端帮助清单和构建输入检查通过 |
| `python3 Scripts/test_fixed_readme.py` | 四端实际生成／重写 ReadMe 一致，用户 Command.txt 字节保持不变 |

新增行为回归使用内存数据库作为存储边界，运行实际生产解析器、NBT 编解码、扫描、筛选和写回。检查区域外连续记录的原始字节、现代 actor 的 digp 及后续扫描可见性；随后删除最后一条实体，检查键与索引一并清理。

先运行新增解析用例，复现旧版拒绝用户给定命令；再增加混合 actor 根用例，复现 `outside actor lost its digp reference`，调整生产删除逻辑后完整套件通过。

Swift 使用 Linux Swift 6.0.3 运行可移植测试。此沙箱的新 Swift driver 在编译调度时崩溃，改用工具链自带旧 driver 后运行完成；日志中的 driver 弃用警告来自该验证环境，项目构建参数未改变。C# 使用 .NET SDK 10.0.100。CLI 首次默认并行构建在沙箱内无诊断失败，关闭 build server 并串行构建后通过。

未在本环境构建 Xcode iOS GUI、WPF GUI 或执行 Minecraft 真机读档验收。保留原有缺失 Health、损坏／孤立记录处理和玩家／实体分阶段写入策略。

最终验证日志位于同目录 `logs/`。
