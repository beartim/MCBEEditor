# MCBEEditor iOS 13 v1.1.8（118）修改说明

## 修复 portable core tests 编译失败

修复 `Sources/Chunk/BedrockSubChunkEditor.swift` 中的编译错误：

```text
value of type 'BedrockBlockRecord' has no member 'stateForEditing'
```

`stateForEditing(layer:)` 定义在 `BedrockBlockColumn.swift` 中，但方块 NBT 编辑专项测试使用轻量级 `BedrockBlockRecord` 桩类型，只编译 `BedrockSubChunkEditor.swift`，因此该调用在测试目标中不可见。

现已将保存方块 NBT 时的当前图层状态解析移入 `BedrockBlockNBTStore`：

- 图层存在时直接读取 `block.layers[storageIndex]`；
- 图层不存在时，根据已有调色板版本生成可编辑空气状态；
- 不再依赖 UI/方块列文件中的辅助方法；
- 实际 App 中的编辑行为保持不变；
- portable core tests 可独立编译并继续验证现代与旧版数字方块写回逻辑。

## 版本

- MARKETING_VERSION：1.1.8
- CURRENT_PROJECT_VERSION：118
- 最低系统：iOS 13.0
