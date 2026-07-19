# MCBEEditor iOS 13 v1.1.1

## 编译错误修复

根据 `logs_80055398915.zip` 中 Xcode 15.4 模拟器构建日志，修复 `WorldMapViewController.swift` 的全部 5 个编译错误：

1. 将不存在的 `UIGraphicsImageRendererContext.fillEllipse` 调用改为 `context.cgContext.fillEllipse`。
2. 导出当前地图区域调用 `renderRegion` 时补传 `tickingAreas`。
3. 将 `summaries.map(\.position)` 改为显式闭包并声明结果类型。
4. 将 HardcodedSpawners 筛选与映射的 KeyPath 简写改为显式闭包，避免 Swift 5 无法推断根类型。
5. 导出常加载区块模式时从 LevelDB 重新读取并按当前维度筛选 `tickingarea`。

同时修复 `ChunkBiomeEditorViewController.swift` 中一个“变量从未修改”的警告。

## 验证

- 全部 Swift 源文件和测试文件通过 `swiftc -frontend -parse`。
- `Scripts/run_core_tests.sh` 全部通过。
- 版本号更新为 1.1.1，构建号更新为 111。

> 当前环境没有 macOS、Xcode 和 iOS SDK，无法在本地再次执行 `xcodebuild`；本次修改逐项对应上传日志中的全部错误。
