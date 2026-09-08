# X/Z 网格、导出、矿物视图与 chunk 命令修正

## 1. 子区块网格线居中对齐方块边界

- 文件：`Sources/Chunk/BedrockCrossSection.swift`
- 子区块网格不再用细 `strokePath()` 依赖 CoreGraphics 像素吸附。
- 改为以计算出的 16 方块边界为中心，绘制宽度为 `gridLineWidth` 的填充矩形。
- 因此现在是“网格线中心”对准方块边界，而不是“网格线一侧边缘”对准方块边界。

## 2. X/Z 模式导出时未生成子区块默认显示为空气

- 文件：`Sources/UI/WorldMapViewController.swift`
- X/Z 垂直切片导出选项默认 `ungeneratedDisplay = .air`。
- Y 模式仍保持原有 `.transparent` 默认值。
- 只修改默认选项，不移除用户在导出界面切换未生成区域显示方式的能力。

## 3. X/Z 矿物视图读取当前 X/Z 到 X/Z-128

- 文件：`Sources/UI/WorldMapViewController.swift`
- 矿物视图投影深度改为 129 个坐标值，即包含：
  - 当前 X/Z
  - 当前 X/Z - 1
  - ...
  - 当前 X/Z - 128
- 普通 X/Z 模式继续保持原先的 128 深度行为。
- 全部已加载范围导出时，矿物模式的投影筛选同步改为向负方向 128 方块，避免实时显示和导出范围不一致。

## 4. X/Z 矿物视图点击默认选择最大 X/Z 的矿物

- 文件：`Sources/UI/BlockAxisPickerViewController.swift`
- 自动选择器新增范围上下界与“优先矿物”选项。
- 矿物视图点击一列后，只在当前坐标到当前坐标-128 范围内寻找矿物。
- 结果列表已有从大坐标到小坐标的顺序，因此默认选中范围内 X/Z 最大的矿物方块。
- 普通模式仍按原逻辑优先选择最大坐标的非空气方块。

## 5. 新增 `chunk` 命令

### query

```text
chunk query
chunk query overworld
chunk query overworld 0 0
```

- `chunk query`：按 `overworld -> nether -> the_end` 顺序打印全部已加载区块。
- 每个区块单独一行，输出样式使用 `.block`，命令终端中显示为蓝色。
- `chunk query <维度>`：只打印指定维度。
- `chunk query <维度> <区块X> <区块Z>`：返回指定区块的信息及生成情况；不存在的坐标也会明确返回未生成状态。
- 生成情况会结合 `FinalizedState` 和已有区块记录判断。

### empty

```text
chunk empty overworld 0 0
```

- 调用 `BedrockChunkStore.clearChunk`。
- 与区块 UI 的“清空”使用同一套实现：删除原记录后写入最小空气区块骨架，并写入 `FinalizedState=2`。

### regenerate

```text
chunk regenerate overworld 0 0
```

- 调用 `BedrockChunkStore.regenerateChunk`。
- 与区块 UI 的“重新生成”使用同一套实现：删除该区块全部记录及相关实体索引，使游戏之后按世界种子重新生成。

## 6. 回归检查

已通过：

- 修改文件 `swiftc -parse` 语法检查。
- `Scripts/test_nbt_tree_cross_section.sh`。
- `Scripts/test_chunk_command_xz_export.sh`。
- `chunk` 命令执行级测试：
  - 三维度顺序与蓝色输出样式；
  - 指定存在/不存在区块查询；
  - `empty` 后 `FinalizedState=2`；
  - `regenerate` 后区块记录数为 0。
- `help chunk` 帮助字典/示例检查。

完整 `Scripts/run_core_tests.sh` 也进行了长程运行；在执行环境超时前已通过大量既有测试段，未出现断言失败。由于脚本总运行时间超过单次执行窗口，不能声明整套脚本已完整跑到底。
