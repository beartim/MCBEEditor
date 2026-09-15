# MCBEEditor CLI stage06b 构建修复报告

日期：2026-09-15

## 来自用户日志的首个失败点

### Windows

GitHub Actions 在 CMake configure 阶段输出：

- `Ignoring extra path from command line: ".5"`
- `Invalid CMAKE_POLICY_VERSION_MINIMUM value "3"`

对应 `CLI/Scripts/build-windows.ps1` 的未引用参数 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`。PowerShell runner 将其拆成 `...=3` 和 `.5`。stage06b 改为 `"-DCMAKE_POLICY_VERSION_MINIMUM=3.5"`，保证 CMake 收到单一 argv。

### Apple host / iOS 发布链

macOS 15 host 在执行真正 CMake/Swift 编译前退出：

`CLI/Scripts/build-apple.sh: line 34: PLATFORM_OPTIONS[@]: unbound variable`

runner 使用系统 `/bin/bash`，空数组在 Bash 3.2 + `set -u` 下的展开行为与新 Bash 不同。stage06b 删除可为空的 `PLATFORM_OPTIONS`，改为 `configure_native()`；host 无附加参数调用，iOS 显式传 `-DCMAKE_SYSTEM_NAME=iOS`。

## 被前置错误遮住的下一层问题

stage06 新增的 `CLI/Windows.Tests/Program.cs` 在 `RunTests(string root, ...)` 内又声明 `var root = ...Documents.Single()`，C# 会报 CS0136。现改为 `rootDocument`，后续 `Path.Combine(root, ...)` 继续正确引用临时目录字符串。

## 回归门禁

新增 `CLI/Tests/stage06b_build_audit.py`，并接入：

- `CLI/Scripts/build-windows.ps1 -Test`
- `CLI/Scripts/build-apple.sh host ... --test`

门禁固定检查 PowerShell CMake 参数不可再次拆分、Apple host 不可恢复空数组 nounset、Windows 集成测试不可恢复 `root` 遮蔽，并确认 release workflow 仍实际走两个累计构建入口。

## 当前验证边界

本环境已重新执行源码审计、Python `py_compile`、Apple shell `bash -n`、Swift 前端解析。由于本机不是 Windows/MSVC/.NET 10 环境，也不是 macOS/Xcode，修复后的两个 GitHub Actions job 尚未在本环境真运行；应以本 stage06b 包直接复跑 Actions，若有下一层真实编译日志再从该基线继续。
