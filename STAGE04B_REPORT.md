# MCBEEditor CLI stage04b 报告

日期：2026-09-15。范围：持续交互会话、`:open/:save/:quit`、重复保存源指纹与失败状态。本快照同时包含本轮用户明确要求完成的 03c 和 04a。

## 会话入口与状态

新增：

```text
mcbe-cli --interactive
```

当前会话命令：

```text
:open "世界路径" [--in-place]
:save ["输出.mcworld"] [--overwrite]
:quit
:quit --discard
```

`:open ... --in-place` 的无参数 `:save` 原位提交；普通 `:open` 必须在 `:save` 时给出另存为路径。保存成功后工作副本继续保持打开，可继续执行普通世界命令。`:quit` 在存在未保存修改时拒绝退出；`:quit --discard` 明确放弃本会话工作副本。

潜在修改命令如果执行失败，会保守地把会话标记为 dirty，因为原命令可能在抛错前已经写入部分数据。这样不会误认为失败后的副本“已保存”。

structure import/export 在交互模式仍要求 `--file`，但名称可省略：import 提示输入名称；export 先列出现有结构名称再提示输入。非交互模式仍由 04a 的整批预检要求名称完整。

## 重复原位保存

Windows `CliWorldSession` 与 Swift `CliWorldWorkspace` 都在每次成功原位提交后刷新源内容指纹。因此以下序列合法：第一次 `:save` → 继续修改 → 第二次 `:save`。若两次保存之间是外部程序修改了源世界，新指纹检查仍会拒绝覆盖。

双端集成测试源码均增加 `1111 → :save → 2222 → :save` 的同一 mcworld 会话场景，并在重新打开后断言最终时间为 2222。该场景专门防止“第一次保存后第二次被自己旧指纹阻塞”的回归。

## 未包含的 04c/04d 内容

04b 没有提前实现历史上下选择、左右光标、`:clear`、终端颜色和重定向纯文本；这些属于 04c。Commands/ReadMe、进入世界检测 Command.txt 和交互确认属于 04d。原游戏 `clear` 仍保持物品清理语义。

## 实际验证

通过：原 `source_audit.py`、`stage02_source_audit.py`、`stage03_source_audit.py`、新增 `stage04_source_audit.py`；全部 59 个 Swift 生产输入加 `NativeIntegration.swift` 使用 Linux Swift 6.2.1 前端语法解析通过；相关 shell/Python 语法检查通过。

未运行：Windows C# 编译/.NET 集成测试、Windows 文件共享行为、Apple Objective-C++/LevelDB 链接、macOS host 原生集成、iOS arm64 编译、Actions、设备和 Minecraft 实际读档。本环境没有 dotnet/pwsh，也不是 macOS/Xcode。详情见 `CLI/Validation/Stage04b/`。

下一断点为 **04c**。
