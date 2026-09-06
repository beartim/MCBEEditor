# CHANGES_BUILD_CORE_TEST_FIX

修复 GitHub Actions / portable core tests 在 iPhone 顶部布局调整后退出码为 1 的问题。

根因：`Scripts/test_iphone_layout_legacy_block_link.sh` 仍固定检查旧布局中的
`displayOptions.spacing = compactPhone ? 14 : 14`，而新版布局已经按需求将间距调整为
`compactPhone ? 20 : 16`，并把两行纵向间距改为 6。应用源码本身没有在该日志位置发生编译错误，
是静态回归测试条件未同步导致流程停止。

修复：
- 更新 iPhone 布局回归条件到当前 20/16 的水平间距。
- 增加 `coordinates.spacing = 6` 检查。
- 保留完整文字、两行布局和旧数字 ID 方块关联检查。
- 重新验证 command executor、legacy zlib/selection export、modern actor、metadata CRUD 回归。
