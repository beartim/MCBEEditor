# 应用 Blocktopograph 1.0.0 完整源码

本压缩包为完整工程源码，不是增量补丁。将目录内容覆盖到现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

地图矩形区域编辑新增了 `BedrockMapRegion.swift`、`BedrockRegionStore.swift` 和 `MapRegionOperationsViewControllers.swift`；使用旧工程手工合并时必须同时加入 Xcode target。通过 `project.yml` 重新生成工程会自动包含 `Sources` 下全部文件。

本版同时修改了 `WorldMapViewController.swift`、`MapSelectionOverlayView.swift`、`EntityBrowserViewController.swift`、`BedrockWorldObjectScanner.swift`、`WorldDetailTabBarController.swift`、`ChunkListViewController.swift`、`BulkLayerReplaceViewController.swift`、`BedrockRegionStore.swift` 与 `BedrockSubChunkEditor.swift`，用于选框手势、区域批量替换、独立区块栏目和全世界实体范围筛选。


独立文件工具新增 `StandaloneNBTFile.swift`、`StandaloneNBTFileViewController.swift`、`StandaloneNBTEditorViewController.swift`；使用旧工程手工合并时必须加入 App target。
