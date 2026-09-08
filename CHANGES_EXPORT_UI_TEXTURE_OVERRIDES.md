# X/Z 导出界面稳定性与 Textures 覆盖

- X/Z 导出范围保留两组 `(x,z)` 输入，但四个边界现在分别拥有独立的无穷按钮：
  - `x1` -> `-∞`
  - `z1` -> `-∞`
  - `x2` -> `+∞`
  - `z2` -> `+∞`
- 四个无穷按钮统一为蓝色圆角矩形。
- `x+ / x- / y+ / y- / z+ / z-` 改成单行六段 `UISegmentedControl`。
- X/Z 导出设置中的对象图层与未生成显示切换不再调用 `tableView.reloadData()`；仅更新相关可见勾选，避免 inset-grouped 表格在估算高度变化时偶发跳回顶部。
- 保持 `UIFileSharingEnabled = true` 与 `LSSupportsOpeningDocumentsInPlace = true`，默认支持 iTunes File Sharing / 文件 App。
- App 每次启动（以及从文件 App 返回前台）都会确保共享 Documents 根目录下存在 `Textures` 文件夹，并重新扫描 PNG。
- 自定义 PNG 使用完整方块 identifier 作为文件名，例如 `Textures/minecraft:bedrock.png`。
- PNG 可见像素被缩合为 alpha 加权平均 RGB，并优先于内置地图颜色表用于该方块的地表/X-Z 普通方块着色。
- 渲染缓存键包含 Textures 修订号，因此从文件 App 修改 PNG 后，回到程序再次渲染即可使用新颜色。

验证：
- `Scripts/run_core_tests.sh` 完整通过（退出码 0）。
- `Scripts/test_export_options_texture_overrides.sh` 通过。
- `Scripts/test_nbt_tree_cross_section.sh`、`test_fillbiome_info_xz_selection.sh`、`test_chunk_command_xz_export.sh`、`test_legacy_zlib_and_selection_export.sh` 通过。
- 两套 block-color audit 均通过。
