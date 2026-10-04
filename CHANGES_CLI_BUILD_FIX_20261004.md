# CLI 构建测试修复（2026-10-04）

本次基于上一版完整源码修复 iOS 与 Windows CLI 的发布测试失败，版本号保持 1.0.0，iOS 发布目标保持 arm64 / iOS 13.0。

## 日志定位

用户提供的 `cli-ios.zip` 与 `cli-win.zip` 完全相同，各自都包含 Apple 和 Windows 两个 job 的日志。两份 ZIP 的 SHA-256 均为 `a2e68354053199a5613ac132fbe5e4674819fdf7c70d02581896376df68e1a20`。

源码编译已成功：Windows 明确显示 `Build succeeded`、0 warnings、0 errors；Apple 已完成 host CLI 编译并通过进程/解析测试。随后两个 job 都停在 `session_smoke.py`。

1. 会话测试仍使用只有空 `db` 文件夹的合成世界。维度预检现在需要读取真实数据库；原生桥接按 `create_if_missing=false` 打开数据库，因缺少 LevelDB 文件而失败，导致修改命令未执行、dirty 状态未建立、保存断言失败。Apple 日志为 10/14 项会话测试失败。
2. Windows 在输出上述中文失败信息时，Python 的重定向 stdout 使用 CP1252，额外触发 `UnicodeEncodeError`，掩盖后续诊断。
3. `environment_smoke.py` 同样使用无效数据库，修复会话测试后也需要同步修复。已在实际 C# CLI 上复现其数据库打开失败。

原始 build step 日志与本次红/绿回归日志保存在 `CLI/Docs/Validation/cli-build-fix-2026-10-04/`。

## 修改

- 新增 `CLI/Tests/smoke_support.py`：调用已有原生夹具工具生成有效的空 Mojang LevelDB。Windows 使用 ASCII 相对参数 `db`；进程退出后再将数据库移动到包含中文和空格的世界路径。夹具创建失败会保留原生错误文本，不发布数据库。
- `session_smoke.py`、`environment_smoke.py` 增加必需参数 `--fixture-tool`，使用有效数据库。会话测试检查整个源世界的文件字节未改变；环境测试继续检查来源保护、缓存预检、批处理提交、无关文件保留和导出中的数据库。
- Apple host `--test` 与 Windows `-Test` 都先构建并验证夹具工具，再传给两个 smoke 脚本。完整原生集成继续使用同一工具。
- 会话与环境测试将 stdout/stderr 配置为 UTF-8；Windows 开发构建和单 EXE 发布测试的 Python 调用均使用 `-X utf8`。
- 增加中文失败输出和夹具错误诊断回归。Apple 构建生命周期测试补充 host 分支，验证夹具构建顺序，以及夹具失败时保留上一份二进制。
- 更新当前 CLI 使用说明中的测试运行方式。

命令解析、维度管理、实体与区块实现，以及生产数据库的打开策略均沿用上一版源码。固定的 Commands/Textures ReadMe 正文和六份 ReadMe.txt 快照也沿用上一版。

## 验证范围

本次在 Ubuntu 24.04、.NET SDK 10.0.401、Swift 6.2.3、CMake 3.31.6、Python 3.12.14 下执行构建和回归。C# CLI 调用的是实际编译的 Mojang LevelDB Linux 原生库；`--backend windows` 是 parser 对照目标，不代表操作系统为 Windows。

已通过 C# CLI 编译（0 警告、0 错误）、14 项会话测试、7 项环境测试、293 项进程检查（231 个解析用例、28 类命令）、46 次 NBT 转换调用、48 项 MCBE-SNBT 场景/101 次进程调用、16 次结构文件预检调用、44 项原生 CLI 集成及维度/实体/summon 附加回归，以及完整 C# 核心回归。最终会话、环境与诊断测试还在强制 `PYTHONIOENCODING=cp1252:strict` 的条件下通过。

双端各 565 行 ID/中文名称对照检查与四个运行时 ReadMe 写入器检查通过。用户示例 `Tests/Fixtures/custom_dimensions.mcworld` 的 SHA-256 保持 `b2b229bc4cc8c9937da461c08b5117501b12bb38791599eca5a6c7b6f63bdcd4`。

Swift 共享核心总入口 `Scripts/run_core_tests.sh` 完整运行通过：最终日志 88 行，退出码 0，并确认到达最后的 98 项 source audit 门禁。独立只读复核已完成，发现的夹具错误信息遗漏已修复并增加红/绿回归，最终无未处理问题。

PowerShell 7.5.2 的实际语法解析通过。Apple 生命周期验证使用工具替身，验证 shell 顺序和产物保留；不代表 Apple SDK 编译、iOS 签名或设备执行。Windows 单 EXE、控制台 Ctrl-C、两项 FileShare 锁测试仍需在 Windows 上验证，后两项在 Linux 原生集成日志中明确标为 SKIP。目标平台发布应重新运行 `.github/workflows/cli-release.yml`。

完整结果与复跑命令见验证目录的 `README.md`、各 `*-results.json` 和对应日志。目录中的 `*-red.log` 是修复前或受控回退时的预期失败证据。
