# 应用 Blocktopograph iOS 13 v1.1.7 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修改了以下核心文件：

- `Sources/Entity/BedrockWorldObjectNBTStore.swift`：根据世界实际实体存储代际，自动选择区块 `Entity(0x32)` 或现代 `actorprefix/digp`；复制旧实体时继续使用旧版区块记录并保留数字 `id` 标签类型；
- `Sources/UI/WorldObjectCreationViewController.swift`：显示新建实体采用的实际存储来源；
- `Sources/UI/MapBlockDetailPanelView.swift`：旧版数字方块以可编辑 NBT 形式显示 `legacy_id`、`legacy_data` 与字符串名称；
- `Sources/Chunk/BedrockSubChunkEditor.swift`：支持旧版 SubChunk 数字 ID/数据值修改及持久化重编码；
- `Sources/UI/WorldMapViewController.swift`：方块坐标模式使用输入方块中心作为渲染视口中心；
- `Tests/BlocktopographTests.swift`、`Scripts/run_core_tests.sh`：增加旧版方块写回、实体存储自动选择和精确方块中心回归检查。

重新生成 Xcode 工程后，版本号为 1.1.7，构建号为 117。
