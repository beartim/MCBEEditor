# MCBEEditor CLI stage04c 报告

日期：2026-09-15。范围仅为交互终端历史/行编辑、清屏、颜色和重定向行为；不改世界数据库、NBT、区块或保存算法。

## 实现

Windows 新增 `CLI/Windows/CliTerminal.cs`，Swift 新增 `CLI/iOS/CliTerminal.swift`。交互会话现支持历史 ↑/↓、←/→、Home/End、Backspace/Delete，并加入 `:history` 与 `:clear`。`clear` 无冒号时仍进入原游戏命令解析器，保持清除物品语义。

真实 TTY 下结果按已有输出类型映射 ANSI 颜色，错误单独使用 stderr 颜色门禁。行编辑只在 stdin **和** stdout 都是 TTY 时启用；stdout 不是 TTY 时不输出 ANSI 或重绘控制序列，stderr 是否着色单独取决于 stderr 自身是否为 TTY。

实施后复核发现两个重定向边界并通过红→绿源码门禁修正：stdin 为 TTY 但 stdout 重定向时不应继续 raw editor；stdout 为 TTY 但 stderr 重定向时 stderr 不应继承 stdout 的 ANSI 状态。对应红灯日志保存在 `CLI/Validation/Stage04c/tdd_*_red.log`。

## 测试源码

Windows/Swift 原生集成测试加入回调/重定向交互场景：`:history → :clear → :quit` 必须正常结束且输出不含 ESC。`CLI/Tests/smoke.py` 也加入真实进程的管道输入场景；该进程 smoke 需要最终平台可执行文件，当前 Linux 环境没有相应 Windows/macOS CLI 成品，因此测试源码已接线但尚未实际运行。

## 本轮实际验证

通过：
- `python3 CLI/Tests/stage04c_source_audit.py`
- Linux Swift 6.2.1 对 `CliTerminal.swift` + 最小输出类型 stub 的 `-typecheck`
- 最终综合 Swift `-frontend -parse`（61 个生产输入 + `NativeIntegration.swift`，记录在 Stage04e）

未运行：Windows ConsoleKey 真实 TTY 集成、macOS/iOS 真实终端运行、真实 LevelDB 原生集成。源码完成不等同于这些平台门禁通过。
