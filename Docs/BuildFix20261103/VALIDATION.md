# 构建修复验证（2026-11-03）

## 输入与复现

上一版源码 SHA256：
`ebd0419b6a286a4d38ec7c6f23ca480b9a6d20d0682fcc31d5b8cbfff9ae0d9e`。

本轮两份 CLI 日志 ZIP 的内容完全相同，都含 Apple 与 Windows CLI 两个
作业。日志显示两个 CLI 的编译成功，失败发生在后续原生集成测试；iOS
GUI 的失败发生在 portable tests 的 Swift 编译阶段。

- iOS 原始 CI：生成测试文件 `CGRect.zero` 缺少 CoreGraphics 扩展。
- Windows CLI：在本机实际构建 Mojang LevelDB 0.8.0a8 / zlib 1.3.1 后，
  未修复测试在同一条 empty/nested List 断言失败；修复后通过。
- Apple CLI：把原生测试中实际的 player 夹具和 entity 断言代码，与生产
  Swift 解析器、执行器、codec 及项目内存数据库边界编译运行；原版准确
  复现 `entity empty read-only query`，修复版通过。此项不是 Apple 原生
  bridge 或 SDK 构建测试。

## 已执行的检查

| 检查 | 结果和范围 |
|---|---|
| .NET CLI 与测试项目构建 | 通过，0 warnings / 0 errors；Linux x64 / .NET SDK 10.0.100 |
| C# `--summon-native` | 原版 RED → 修复版 GREEN；真实 LevelDB 文件与导出/重开，无内存数据库替身 |
| C# CLI 全量原生集成 | 进程退出码 0；使用同一真实 native library；POSIX 明确跳过 Windows FileShare 替换锁案例 |
| C# 完整 Core.SelfTest | 通过 |
| Windows CLI 命令进程 smoke | 通过：446 次进程检查，384 条解析案例，28 种命令；托管程序运行于 Linux |
| Swift 完整 `Scripts/run_core_tests.sh` | 通过；384 条共享解析案例，最终 98 项源码审计通过；含 NBT 保存重开回归 |
| Swift 原生测试 entity 断言专项 | 原版 RED → 修复版 GREEN；运行实际测试断言及生产 parser/executor/codecs，内存数据库边界 |
| CLI source/build audits | 通过 |
| Apple build lifecycle | 通过；使用构建工具替身验证既有发布流程，不等于实际 Apple 编译/签名 |
| `NativeIntegration.swift` 语法解析 | 通过 |

Swift 本机版本为 6.0.3，实体专项另以 `-swift-version 5` 编译。日志中的旧
Swift driver 弃用提示来自本机启动参数。正式 macOS SDK/Xcode 编译、Apple
原生 bridge 执行、iOS 签名/设备运行、Windows PE 单文件发布未在本机执行。
这些阶段需由对应平台 CI 确认，不能从 Linux 结果推断已经完成。

## 专项复核

独立复核未发现 Critical、Important 或 Minor 问题。复核确认条件导入对应
实际 macOS 报错，CLI 检查继续验证完整载荷而非跳过错误；精确 Long
`9007199254740993` 和独立构造的 NBT 字节比较均保留。

复核未对上述不可用平台作出成功结论，也未扩大到未修改的运行时代码。

## 重跑专项

有 Swift 编译器时，可运行：

```bash
python3 Docs/BuildFix20261103/validate_swift_entity.py
```

用 `--root` 指定解压后的上一版源码，可重现旧断言失败。脚本从对应源树
提取实际测试方法和断言，复用完整 core runner 维护的生产输入清单。

原始失败摘录、复现及本轮通过日志保存在 `logs/`。
