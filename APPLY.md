# 应用 Blocktopograph iOS 13 v1.1.6 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修改了以下核心文件：

- `Sources/Entity/BedrockWorldObjectNBTStore.swift`：主世界现代实体改用标准 `digp + chunkX + chunkZ` 键；自动迁移旧错误键，并在删除时清理全部摘要引用；
- `Sources/Entity/BedrockWorldObjectScanner.swift`：优先读取标准摘要键，并忽略没有 `digp` 引用的孤立 `actorprefix`；
- `Sources/Support/BedrockLegacyBlockCatalog.swift`：新增旧版数字方块 ID 0–255 与字符串 ID、别名和十六进制 ID 对照；
- `Sources/Chunk/BedrockSubChunk.swift`、`BedrockSubChunkEditor.swift`：旧数字方块显示字符串 ID，并支持按数字/十六进制/字符串搜索；
- `Sources/UI/WorldToolsViewController.swift`：增加“方块ID”数据值查询；
- `Tests/BlocktopographTests.swift`、`Scripts/run_core_tests.sh`：增加标准实体摘要迁移和数字方块 ID 回归检查。

重新生成 Xcode 工程后，版本号为 1.1.6，构建号为 116。
