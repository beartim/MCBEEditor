# 应用 Blocktopograph iOS 13 v1.1.8 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修复：

- `Sources/Chunk/BedrockSubChunkEditor.swift`：方块 NBT 保存时不再依赖 `BedrockBlockColumn.swift` 中的 `stateForEditing(layer:)` 辅助方法，而是由存储层直接解析当前图层状态；
- `CHANGES_v1.1.8.md`：记录本次 GitHub Actions portable core tests 编译修复。

重新生成 Xcode 工程后，版本号为 1.1.8，构建号为 118。
