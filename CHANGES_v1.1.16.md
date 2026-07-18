# Blocktopograph iOS 13 v1.1.16（126）

## 构建报错修复

本次日志中的失败发生在 `Scripts/run_core_tests.sh`，尚未进入 Xcode Swift 编译。

错误信息为：

```text
error: unloaded-chunk air generation is incomplete
```

实际的未加载区块生成代码已在 v1.1.15 中扩展为：

```swift
let allPuts = metadataPuts + upgradedSubChunkPuts + [(key: key, value: encoded)]
```

旧回归检查仍只查找 v1.1.13 的：

```swift
metadataPuts + [(key: key, value: encoded)]
```

因此把完整实现误判为缺失。现已更新检查条件，使其匹配包含区块升级写入的 `allPuts` 逻辑。

## 地图默认中心

- 地图初次打开时读取本地玩家的维度和 `Pos`，默认切换到该维度并以玩家实际 X/Z 坐标为视口中心。
- 切换到本地玩家所在维度时，默认重新定位到玩家坐标。
- 切换到另外两个维度时，默认使用方块坐标 `(0,0)`；视口锚点为该方块中心 `(0.5,0.5)`。
- 维度切换不再沿用上一维度的视口中心，避免把主世界坐标直接带入下界或末地。
- 保留当前缩放比例、地图模式、对象图层和其他显示设置。
- 无法读取本地玩家位置时，默认使用主世界 `(0,0)`。

## 回归检查

- 增加玩家维度与非玩家维度默认中心的静态回归检查。
- 未加载区块生成检查同步适配 v1.1.15 的旧区块升级写入路径。
