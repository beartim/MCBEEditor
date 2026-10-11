# 空 List 的 MCBE-SNBT 验证记录

当前规范为 `'List'''"Items"=""`。仅未指定元素类型且长度为 0 的 List 使用空类型标记；已声明元素类型的空 List 保留原声明。

## 最终验证结果

| 检查 | 结果 | 记录 |
| --- | --- | --- |
| C# CoreSelfTest、CLI、CLI 测试项目编译 | PASS，0 警告、0 错误 | `logs/csharp-core-build.log`、`logs/csharp-cli-build.log` |
| C# 完整核心回归 | PASS | `logs/csharp-core-full.log` |
| 共用文件 codec 样例 | PASS，68 例：34 有效、34 无效 | `logs/csharp-codec-green.log` |
| C# 命令输出与文件/命令字节往返 | PASS，全部 13 种空元素类型、嵌套、首项单引号字符串 | `logs/csharp-output-green.log` |
| Swift 完整核心回归 | PASS，退出码 0，最后 98 项源代码审查门禁完成 | `logs/swift-core-full.log`、`logs/swift-core-result.json` |
| Swift 实际命令回归 | PASS，246 共用 parser 样例；summon/entity/getblock 的持久内容往返 | `logs/swift-command-targeted-green.log` |
| 实际 C# CLI 命令检查 | PASS，308 次调用、246 parser 样例、28 个顶层命令 | `logs/csharp-cli-process.log` |
| 实际 C# CLI 原有 NBT 转换 | PASS，46 次调用 | `logs/csharp-cli-conversion.log` |
| 实际 C# CLI MCBE-SNBT 转换与错误原子性 | PASS，71 场景、152 次调用 | `logs/csharp-cli-snbt.log` |
| Swift 生产文件 codec probe | PASS，71 场景、138 次调用 | `logs/swift-probe-fixtures.log` |
| Swift 导出 → C# 读取 | PASS，34 例逐字节一致 | `logs/cross-swift-to-csharp.log` |
| C# 导出 → Swift 读取 | PASS，34 例逐字节一致 | `logs/cross-csharp-to-swift.log` |
| Mojang LevelDB 原生集成 | PASS，44 主调用；附加 summon/entity 和 10 项结构 TXT 回归 | `logs/csharp-cli-native.log` |
| 命令覆盖及构建契约 | PASS | `logs/source-audit.log`、`logs/build-audit.log` |
| ReadMe 静态写入与 Command.txt 保护 | PASS，运行时帮助变化仍恢复固定字节 | `logs/fixed-readme.log` |
| 六份 ReadMe 与示例存档原字节 | PASS | `logs/preserved-files.json` |
| 完整输入源码保留 | PASS，747 个原文件均保留，16 个有意修改 | `logs/base-archive-comparison.json` |

`logs/verification-summary.json` 汇总最终结果；各最终 `*-results.json` 保存对应退出码。`logs/cli-canonical.json` 与 `logs/probe-canonical.json` 是本次实际导出文本，包含新空类型写法。

## 失败复现记录

以下是修复前预期失败或新增测试修正前的历史记录，不属于最终验证结果：

- `red-results.json` 及 `csharp-*-red.log`、`swift-codec-red.log`：原导出仍带 End，新增空类型输出断言失败。
- `command-input-red.log`：原生产 CLI 拒绝 `'List'''"Items"=""`，退出 2。
- `apostrophe-red-results.json`、`apostrophe-*-red.log`：新增匿名识别曾误判 `'hello'`；已补足上下文识别。
- `first-string-red-results.json`、`first-string-*-red.log`：首个字符串是类型样式时的往返失败；已补两个独立首项回归和完整匿名值检查。
- `swift-core-integration-red.log` 与其 result：新增 entity 测试曾把多行扫描诊断当作 SNBT；改为从 outputLines 提取实际实体行，随后完整核心回归通过。

## 平台范围

工具链与平台实测版本见 `logs/environment.json`。Swift 使用官方 6.2.3，C# 使用 .NET SDK 10.0.401；编译在资源受限环境中以串行方式执行，未修改项目构建配置。

Swift 文件 probe 直接编译生产 codec，命令测试执行生产 parser/executor 并使用测试存储；C# CLI 原生集成使用实际 Mojang LevelDB。iOS SDK/设备、Windows GUI 与 Windows 原生锁语义仍须在相应平台验证；POSIX 上的两项 Windows FileShare 用例有明确 SKIP 记录。

旧 `CLI/Docs/Validation/mcbe-snbt/` 中的日志和 canonical-output 是此前版本的历史验证，保留其原始内容。本次结果以本目录为准。
