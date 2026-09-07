# CHANGES_BUILD_PHOTO_TEST_PORTABILITY_FIX

修复 GitHub Actions 在 `Run portable core tests` 阶段完成 metadata UI 回归后直接以 exit code 1 退出的问题。

## 原因

`Scripts/test_photo_export_tabs_keyboard.sh` 原本把 Swift 源码片段直接作为 BSD/GNU `grep` 的基本正则表达式匹配。检查内容包含 Swift 的 `\\(`、`[`/`]`、中文全角括号等字符；这种写法依赖不同 `grep` 实现的正则转义行为，并且脚本启用了 `set -e`，所以 macOS runner 上任意一项匹配失败时只会无提示退出，日志中只能看到前一项 metadata 测试通过和最终 exit code 1。

## 修复

- 将这组检查改成 `grep -Fq` 固定字符串匹配，不再把 Swift 代码当正则表达式解释。
- 设置 `LC_ALL=C`，按字节匹配 UTF-8 源码，避免 runner locale 影响。
- 新增 `require_contains` / `require_absent`，失败时明确输出检查项、文件和缺失/禁止的字符串。
- `run_core_tests.sh` 使用 `bash Scripts/test_photo_export_tabs_keyboard.sh` 调用，并在调用前输出测试名称，避免执行位或 shebang 差异导致难以定位。
- 没有移除照片保存、底部 Tab 固定标题或命令键盘按钮的任何功能代码。
