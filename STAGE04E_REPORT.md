# MCBEEditor CLI stage04e 报告

日期：2026-09-15。范围只处理项目文档已经记录的 Windows/Swift CLI 解析差异，并补共享 fixture；不重构业务命令、NBT 字符串或底层世界坐标类型。

## 语法关键字大小写

Swift `WorldCommandParser` 现在对根命令以及 effect/experience/chunk/storage/time/structure/tickingarea 等动作、维度、tickingarea shape、time period/weather condition 等**语法关键字**做大小写归一。Windows 原本大多数分支已如此，本轮补齐 `effect` 动作的 `ToLowerInvariant()`。

没有把整条命令转小写。`ALL`、`Auto`、`default`、NBT 字符串、结构名/tickingarea 名称、identifier 等语义参数保留原规则。例如：
- `EfFeCt ClEaR @e ALL`：共享有效 fixture；
- `effect clear @e all`：继续无效；
- 混合大小写命令中的 NBT `CustomName="MiXeD Value"` 不被改写。

## 方块坐标边界

Windows 方块命令入口一直使用 Int32 X/Y/Z。Swift 过去的 `CommandBlockCoordinate` X/Z 为 Int64，CLI 因此可接受比 Windows 更大的 X/Z。本轮只在 Swift CLI `parseCoordinates` 边界把 X/Y/Z 全部按 Int32 解析，再转换到现有 Int64 X/Z 数据结构。这样不改底层数据模型，同时两端 CLI 接受/拒绝相同范围。

共享 `parser-cases.json` 删除旧的 `expected_by_backend` 特判，并加入 mixed-case、Int32 最大/最小、正负溢出和语义大小写用例；当前共 142 个共享解析 fixture。

## 累计构建/测试门禁

`build-windows.ps1 -Test` 与 `build-apple.sh host ... --test` 现都串联 source、stage02、stage03、stage04、stage04c、stage04d、stage04e 源码审计，并继续执行各自进程 smoke 和原生集成测试。

本 Linux 环境实际通过：
- 全部 7 个累计源码审计；
- Swift 6.2.1 `-frontend -parse`：61 个生产 Swift 输入 + `CLI/iOS.Tests/NativeIntegration.swift`；
- `python3 -m py_compile CLI/Tests/*.py`；
- `bash -n CLI/Scripts/build-apple.sh`；
- `parser-cases.json` / `command-inventory.json` JSON 解析。

平台门禁未运行：本机无 dotnet/pwsh，不能执行 Windows C# 编译/原生测试；不是 macOS/Xcode，Apple host 脚本实际尝试后按预期在环境门禁退出 1；iOS arm64、GitHub Actions、设备/Minecraft 读档也未运行。详见 `CLI/Validation/Stage04e/`。

## 下一断点

04c、04d、04e 的源码范围到此结束。下一断点为 **05a Windows 单 exe 发布与 Actions**；如果先获得 Windows/macOS 编译或原生测试失败日志，应优先修复明确失败，而不是把静态检查当作平台通过。
