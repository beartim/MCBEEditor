# CHANGES_IPHONE_UNGENERATED_CHUNKS

本次继续完成以下修改：

1. iPhone 地图顶部两行控件间距适度拉开，避免过于紧密。
2. 地图对象图层新增“显示未生成区块”，默认关闭。
3. 未生成区块新增固定密度纹理显示；缩放重新渲染后纹理密度保持固定，不随缩放倍数改变。
4. 导出地图图片新增“未生成区块显示”：
   - 透明（默认）
   - 空气
   - 纹理
5. `getblock` 查询到未生成位置时显示 `Block=NULL`，`BlockEntity` 逻辑保持不变。
6. `storage query` 查询到未生成位置时不报错，返回绿色输出 `Block not generated`。
7. `storage` 命令仅保留 `query / set / delete / clear` 四种形式；不再兼容 `add`。

## 主要涉及文件

- `Sources/UI/WorldMapViewController.swift`
- `Sources/UI/MapExportOptionsViewController.swift`
- `Sources/Command/WorldCommandExecutor.swift`
- `Scripts/run_core_tests.sh`
