# CHANGES_BUILD_UNGENERATED_TEXTURE_SCOPE_FIX

## 报错原因

GitHub Actions 的 portable core tests 全部通过，但 Xcode 模拟器编译在 `WorldMapViewController.swift` 失败：

- `cannot find 'ungeneratedTextureRects' in scope`
- 报错位置在地图主渲染路径中网格绘制后的纹理延迟绘制代码。

上一版为了避免区块网格覆盖纹理连接点，把纹理改成“先收集矩形、网格绘制后再统一绘制”。但是补丁只在导出路径中加入了 `ungeneratedTextureRects` 的声明与收集，在主地图渲染路径只留下了最终引用，因此 Xcode 的完整类型检查能够发现作用域错误；单纯 `swiftc -parse` 不会发现这种名称解析问题。

## 修复

- 在主地图渲染闭包中增加独立的 `var ungeneratedTextureRects = [CGRect]()`。
- 未生成区块处于 `.texture` 模式时不立即绘制，而是把对应 `rect` 加入数组。
- 区块网格绘制完成后再统一遍历这些矩形并调用 `drawUngeneratedChunkTexture(...)`。
- `.air` 与 `.transparent` 仍走原来的 placeholder 逻辑。
- 导出路径保持同样的延后绘制结构。

## 回归保护

`Scripts/test_iphone_layout_legacy_block_link.sh` 新增静态检查：工程必须恰好存在两处局部 `ungeneratedTextureRects` 声明，分别对应地图主渲染和导出渲染。这样以后若某一条路径再次只保留引用而丢失声明，portable tests 会提前失败，而不是等到 Xcode 编译阶段才发现。

## 验证

- `Scripts/test_iphone_layout_legacy_block_link.sh`：通过。
- `Scripts/test_legacy_zlib_and_selection_export.sh`：通过。
- `Sources + Tests` 共 109 个 Swift 文件逐个 `swiftc -parse`：通过。
