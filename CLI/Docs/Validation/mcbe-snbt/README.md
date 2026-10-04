# MCBE-SNBT 验证记录

日期：2026-10-03。版本保持 1.0.0；恢复的原始工程及 entity、summon 增强均保留。本次已保存三个中途检查点，最终包另行归档。

## 已执行并通过

| 验证范围 | 结果与证据 |
| --- | --- |
| C# CoreSelfTest 完整回归 | 通过，含 45 个 MCBE-SNBT 共用样例、entity/summon、结构与存档兼容；`csharp-core-selftest.log` |
| C# CLI/测试项目 Release 编译 | 0 warning / 0 error；`csharp-cli-tests-build.log` |
| Windows WPF Release 交叉编译 | 0 warning / 0 error；`wpf-build.log` |
| 真实 Mojang LevelDB 集成 | 44 个主流程调用案例，另含 10 个 TXT 原生场景；`csharp-cli-native-tests.log` |
| C# 实际 CLI 的 MCBE-SNBT 转换 | 48 组检查 / 101 次进程调用；`snbt-csharp-fixtures.log` |
| Swift 编解码最终回归 | 48 组检查 / 87 次进程调用；`swift-codec-final.log` |
| Swift 生产转换器的 Linux 验证入口 | MCBE-SNBT 48 组 / 101 次调用、原有二进制/JSON 转换 46 次调用；`swift-converter-snbt.log`、`swift-converter-nbt.log` |
| C# → Swift / Swift → C# | 各 20 个有效样例，NBT 字节完全一致；`cross-csharp-to-swift.log`、`cross-swift-to-csharp.log` |
| Swift 共享核心全套脚本 | `Scripts/run_core_tests.sh` 通过；`swift-core.log`。随后针对最终空元素校验变更再次执行上表 codec 测试 |
| Swift GUI、CLI 与平台测试文件 | 69 个文件语法解析通过；`swift-ui-cli-parse.log` |
| CLI 原有行为 | 259 次进程检查，含 198 个解析样例及 27 个命令；原有 NBT 转换 46 次、结构路径预检 16 次；相应 `cli-*.log` |
| 源码、构建清单、Apple 构建脚本生命周期 | 通过；`source-audit.log`、`build-audit.log`、`apple-build-lifecycle.log` |

共用数据位于 `Tests/Fixtures/mcbe_snbt.json`，包含 20 个有效样例（含原始二进制 String）及 25 个无效样例；进程测试另加严格 UTF-8 与深度检查。有效样例的期望 NBT 字节由独立 Python 规则构造，不取自任一产品编码器。

本轮修正了复查发现的两点：Windows 独立文件导出先在异常处理范围内编码；紧凑 String List 不裁剪解码后的真实空白字符。新增共享样例保留 `\n`、`\t`、转义空格及尾随空格，并统一拒绝未显式标注的空列表元素。`escaped-list-before-fix.log` 保留修复前失败证据；最终两端测试均通过。

## 平台限制

- 测试宿主为 Linux；使用 .NET 10.0.100、Swift 5.10.1、工程固定版本 LevelDB 0.8.0a8 / zlib 1.3.1。
- WPF 已编译，但本次未执行 Windows GUI 点选。原生测试中两个仅适用于 Windows FileShare 的锁定场景由现有测试明确跳过。
- 未执行 Xcode/iOS 完整链接、签名或 iPhone 真机测试。Swift UI 的语法检查不能代替 UIKit 类型检查和真机运行。
- `FormatConverterProbe.swift` 与 `format_probe_bridge.c` 仅用于 Linux 验证入口。生产 `CliFormatConverter.swift`、Standalone NBT、MCBE-SNBT、JSON 与结构编码源码原样参与编译；平台文件发布及压缩桥采用 Linux 适配，不能据此声称 Apple 原生桥已执行。Apple 原生测试已经增加 TXT 用例并接入 `build-apple.sh host --test`，待 macOS/Xcode 环境执行。

## 在目标环境复跑

```text
bash Scripts/run_core_tests.sh
dotnet run --project Windows/MCBEEditor.Core.SelfTest -c Release
python3 CLI/Tests/mcbe_snbt_smoke.py --backend cli -- <mcbe-cli>
python3 CLI/Tests/nbt_conversion_smoke.py -- <mcbe-cli>
python3 CLI/Tests/structure_file_smoke.py -- <mcbe-cli>
```

完整平台构建验证使用现有 `CLI/Scripts/build-windows.ps1 -Test` 或 `CLI/Scripts/build-apple.sh host CLI/build/apple-host --test`。两端脚本均已接入新格式的进程测试。
