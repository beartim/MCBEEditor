# MCBEEditor CLI stage04d 报告

日期：2026-09-15。范围为 Commands 目录、固定 `ReadMe.txt`、可选 `Command.txt` 检测和交互批处理；不改变现有 `--script` 文件格式或世界持久化算法。

## 实现

Windows 新增 `CLI/Windows/CliSharedCommandStore.cs`，默认 `Commands/` 位于程序目录；Swift 新增 `CLI/iOS/CliSharedCommandStore.swift`，默认使用用户 Documents 下的 `Commands/`。程序启动会创建目录并重写固定 `ReadMe.txt`，但 `Command.txt` 始终为用户所有：不会自动创建、覆盖或删除。

交互 `:open` 成功后如果存在非空 `Command.txt`，先询问是否执行。确认后调用与 `--script` 同一严格 UTF-8/物理行号读取器和 `CliCommandPlan` 做**整批预检**：有任何语法错误则整批不执行。预检通过后顺序执行；某条运行时错误会记录实际行号并继续后续命令，最终会话退出状态保留失败。若其余命令产生了可用修改，用户仍可显式 `:save`。

非交互/无人值守不会出现确认提示；继续要求调用者显式使用 `--script "Commands/Command.txt"`。

## 测试源码

双端原生集成测试新增：
- `Prepare` 后 `Command.txt` 字节必须完全不变，固定 ReadMe 包含 `--script`、`:clear`、structure 文件接口；
- `time set 3333 → structure load 不存在结构 → time set 4444`：中间运行时错误后仍执行最后一条，允许保存结果，但最终退出码为 1；
- `time set 5555 → weather nope → time set 6666`：整批预检失败，首条也不能写入，最终退出码为 2。

## 本轮实际验证

通过 `stage04d_source_audit.py` 和最终综合 Swift 前端语法解析。Windows/.NET 原生测试、Apple host 原生测试当前工具链不可用，因此这些集成场景尚未实际执行。
