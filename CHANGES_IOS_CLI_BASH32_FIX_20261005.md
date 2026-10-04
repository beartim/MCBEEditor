# iOS CLI 构建生命周期测试修复（2026-10-05）

本次修复 `logs_100792496542.zip` 中 Apple job 的新失败。版本号保持 1.0.0，发布目标保持 arm64 / iOS 13.0。

## 原因与修改

日志显示 Apple host 原生库及 Swift CLI 已编译，随后停在 `CLI/Tests/apple_build_lifecycle.py` 的 host 成功分支，断言发布文件应为 `new-binary`。失败来自上轮新增测试夹具：它的源码清单仅有 `CliEntry.swift`；真实构建脚本在编译测试入口时会移除该文件，因而得到空的 `test_sources` 数组。

已用 GNU Bash 3.2.57 精确复现：脚本在 `set -u` 下展开空数组时报 `test_sources[@]: unbound variable`，该路径返回 0，却保留了上一份二进制。因此退出码检查通过，后续文件内容检查失败。原测试在 Bash 5.2.21 下通过，不能揭示 macOS 默认 Bash 3.2 的差异。

修改仅涉及测试：补充实际的入口与普通 Swift 源码文件，并将两者写入夹具清单，符合真实清单中入口和非入口源码并存的结构。成功分支同时检查 stderr，并在文件内容断言失败时显示 stdout/stderr。五项 iOS 失败保护、成功发布、host 夹具构建顺序、夹具失败保护和临时目录清理检查均保留。

生产构建脚本、Swift/C# 源码、命令、维度实现及源码清单均未修改。六份固定 ReadMe.txt、其他原有文件和示例存档在打包时逐字节核对；唯一修改的原有文件为 `CLI/Tests/apple_build_lifecycle.py`。

## 验证

- 原测试在 Bash 3.2.57 下复现同一 host 内容断言失败；附加跟踪日志记录了空数组错误及旧产物内容。
- 修复后全部 8 个生命周期场景分别在 Bash 3.2.57、5.2.21 下通过。将工具替身也改用 Bash 3.2 的额外验证通过。
- 源码审计、构建配置审计、两项 UTF-8/夹具诊断测试、两版 Bash 的生产脚本语法检查、Python 语法检查和 `git diff --check` 均通过。
- 独立只读复核重复验证了两版 Bash 的全部场景，并确认原测试在 Bash 3.2 下失败；无未处理发现。

本次上传的 Windows job 已通过原生测试与单 EXE 发布，包括 46 项 C# CLI 原生集成和外层 EXE 的中文/相对路径检查。这是上传的 CI 日志证据，未作为本次 Linux 环境执行的结果。

本次生命周期验证运行真实构建 shell 和工具替身，不调用 Apple SDK，不证明实际 iOS 编译、签名或设备运行成功。请重新运行 `.github/workflows/cli-release.yml`，完成目标平台发布验证。上一轮完整核心回归记录保留为历史证据，本次没有重复执行这些未受改动影响的回归。

完整红/绿日志、上传的两个 build step 日志及复跑方式见 `CLI/Docs/Validation/ios-cli-lifecycle-2026-10-05/README.md`。
