# iPhone 顶部地图控制行排版修复

本次只调整 iPhone 地图页顶部控制区域的排版，不改变地图渲染、坐标或开关功能。

## 修改内容

- 第一行固定为三个完整的开关组合：`自动 + 开关`、`网格 + 开关`、`区块 + 开关`。
- 不再使用 `.fillEqually` 把每个开关组合强行拉伸到屏幕三分之一宽度。旧布局会让文字停在分区左侧、开关跑到分区右侧，看起来像标题和开关不属于同一组。
- iPhone 改用 `.equalCentering`，每个“文字 + 开关”保持紧邻，再把三个完整组合均匀分布在一行。
- `compactSwitch` 在 iPhone 上使用 required content-hugging / compression-resistance，防止内部标题或整个组合被 UIStackView 再次横向拉长。
- 第二行固定只显示渲染中心相关控件：`中心`、`X`、`Z`、`渲染`；同样使用等中心分布，避免某个标题吞掉多余空间。
- iPad / regular-width 布局保持原逻辑。

## 验证

- 更新了 `Scripts/test_iphone_layout_legacy_block_link.sh`，检查 iPhone 两行布局和新的紧凑分布约束。
- 全部 Swift 源文件通过 `swiftc -parse` 语法检查。
