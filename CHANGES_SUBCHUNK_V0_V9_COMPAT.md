# SubChunk v0–v9 读写兼容性完善

本次修改依据用户提供的 `v0-v8.docx` 与 `v9.docx` 建议，对 MCBEEditor 的 SubChunk v0–v9 持久化读写做了系统性补强，同时严格保留现有产品约束：**可结构化编辑的 block storage 仍固定为 layer 0 / layer 1 两层**。storage2+ 只做读取、保留和原格式写回，不开放 UI、setblock、fill、clone 等编辑能力。

## 1. v0 / v2–v7：LegacyBlockExtraData (0x34)

新增 `Sources/Chunk/BedrockLegacyBlockExtraData.swift`，实现旧数字 ID SubChunk 配套的第二方块层：

- 解码/编码 `count + location + blockID + blockData`。
- `location` 按旧格式拆分为 X/Z/absolute Y，并映射到对应虚拟 SubChunk 的 layer 1。
- 未识别尾部字节通过 `trailingData` 原样保留。
- `blockData` 按 **完整 UInt8 (0...255)** 保存；它不是 v0–v7 主层 metadata 的 4-bit nibble。
- 主层 layer 0 仍按原 v0/v2–v7：4096 byte ID + 2048 byte Data nibble + 原 trailing data 写回。

`BedrockChunkSubChunkAccess` 现在会：

- 对 numeric v0/v2–v7 的 0x2F 记录自动挂接 0x34 为 layer 1。
- 如果某个 Y 切片只有 0x34、没有实体 0x2F 主层，也会建立一个全空气的虚拟 numeric 主层供读取。
- 编辑 layer 1 后只更新 chunk-wide 0x34；未修改的 0x2F 主层保持字节不变。
- LegacyTerrain (0x30) 与 0x34 继续视为两个不同历史体系，不会错误互相套用。

## 2. 旧 numeric chunk -> v9 升级

`BedrockLegacyChunkUpgrade` 现在升级 numeric v0/v2–v7 时会同时读取 0x34：

- storage0 = 原 numeric 主方块层。
- storage1 = LegacyBlockExtraData 第二层。
- 成功写出 v9 后删除旧的 0x34，避免同一区块残留两套第二层语义。
- 只有 0x34、没有 0x2F 的旧 Y 切片也会参与迁移。

这修复了旧世界中雪层、叠层方块/附加方块在现代化时丢失的问题。

## 3. legacyData / val 的无损迁移

新增 `Sources/Support/BedrockLegacyBlockStateConverter.swift`：

- numeric `legacyID + legacyData` 转现代 palette 时，不再简单生成 `states: {}` 并丢掉 data。
- 对高置信常见映射生成结构化 states，例如：
  - wool / stained glass / carpet / concrete 等颜色；
  - planks 木材类型；
  - stone/dirt/sand/sandstone/quartz/prismarine/red sandstone 常见变种。
- 对尚未可靠映射的非零 metadata，不猜测 states；保留为带历史 palette version 的 `val`，避免信息丢失。
- v1/v8 老 palette 中本来存在的 `val` 可以原样 round-trip。
- UI 的状态显示会优先把已知 `val` 显示为对应 state；未知值显示为 `legacy_val`。
- 普通改名不再自动制造 `val + states` 混合结构；只有明确、可安全转换时才生成 states。

## 4. v8 / v9 storageCount

去掉原先 `storageCount <= 16` 的人为格式限制：

- v8/v9 按磁盘 UInt8 完整读取 0...255 个 storage。
- 编码时同样允许 UInt8 范围。
- **`BedrockBlockRecord.editableLayerCount` 仍为 2。**
- storage2+ 会被解析并在编辑 layer0/layer1 时保留，不允许通过主编辑功能直接修改。
- 清理空 layer1 的逻辑只在 `storages.count == 2` 时删除末层，不会误删 storage2+。

专项测试构造了 17 storage 的 v8 与 v9，并完成持久化往返。

## 5. BPB = 127 空 storage sentinel

新增 `SubChunkStoragePersistentKind.emptySentinel127`：

- 遇到 persistent storage header 的 bits-per-block = 127 时，逻辑上作为全空气 storage 读取。
- 未修改时重新编码仍输出原来的单字节 sentinel，不擅自规范化成 BPB=0。
- 如果该 storage 真正被编辑，必须先转换为 normal storage，防止把修改后的内容错误编码成空 sentinel。

Runtime/network palette (header LSB=1) 仍明确拒绝，因为 MCBEEditor 操作的是 LevelDB 持久化世界，不把网络 runtime ID 当作磁盘 palette 解释。

## 6. 未知未来 SubChunk 版本 raw retention

对于 v10+ 等当前未知版本：

- 不再直接 throw 导致整个 chunk 枚举失败。
- 保存原始 `rawPersistentData`，允许列表/复制/导出等无损保留。
- `encodePersistent()` 在未结构化修改时逐字节输出原数据。
- 未知版本不提供结构化方块编辑。
- 未知版本不会参与“新建 SubChunk 应采用哪个已知版本”的推导。

因此未来版本出现时，MCBEEditor 至少不会因为一条未知 SubChunk 让整个区块变得不可访问，也不会猜格式后损坏数据。

## 7. palette version / SubChunk version 推导

`BedrockEmptyChunk` 的推导逻辑进行了调整：

- 新建/补全 SubChunk 优先使用当前 chunk 已持久化的已知 SubChunk 版本。
- block palette version 优先取当前 chunk、同维度、全世界已有 persistent palette 中实际出现的 version。
- unknown raw SubChunk 与 BPB=127 sentinel 不提供虚假的 palette version。
- 固定 `1.21.1.0` 数值只作为真正无法从世界取得任何 palette version 时的最后安全 fallback。

没有把 `level.dat.lastOpenedWithVersion` 直接位打包成 block-state version：产品版本号与 block-state schema version 不保证长期完全同构，错误推导比保留安全 fallback 风险更大。

## 8. 命令与区域编辑

`WorldCommandExecutor`、`BedrockSubChunkEditor`、`BedrockChunkStore`、`BedrockRegionStore` 等路径已同步到新模型：

- layer 0 / layer 1 的两层编辑限制保持不变。
- numeric layer1 可以落回 0x34，不再因为“第二层”本身强制升级到 v9。
- 只有真正需要写现代 NBT block state 到 numeric chunk 时才进行整 chunk modernize。
- modernize 时使用 legacy ID/data 转换器，并合并 0x34。
- storage2+ 在普通 layer0/1 修改中保持。

## 9. 回归测试

新增 `Scripts/test_subchunk_v0_v9_compat.sh`，覆盖：

- v8 17 storages round-trip。
- v9 17 storages round-trip。
- editable layer 硬限制仍为 2。
- BPB=127 sentinel 原字节 round-trip。
- 未知 v10 raw round-trip。
- v1 `val` palette round-trip。
- 已知 numeric metadata -> states。
- 未知 metadata -> `val` 保留。
- 0x34 location 物理布局。
- 0x34 `blockData > 15` 的 8-bit 保存。
- v7 + 0x34 联合读取。
- 只修改 layer1 时 v7 主记录不变。
- 0x34 trailing bytes 保留。
- v7 + 0x34 -> v9 storage0/storage1。
- modernize 后删除旧 0x34。
- 未知 v10 不污染 v9 版本推导。

原有 `test_legacy_terrain_subchunks.sh` 继续覆盖 LegacyTerrain 与 v0–v9 基础 persistence。

最终验证：

- 108 个 Swift 源文件全部通过 `swiftc -parse`。
- `test_subchunk_v0_v9_compat.sh` 通过。
- `test_legacy_terrain_subchunks.sh` 通过。
- `viewed_unsaved_sync`、旧 zlib/框选导出、modern actor binary TAG_String、iPhone legacy block link、metadata CRUD 专项均通过。
- 完整 `run_core_tests.sh` 因单次执行时长超过工具上限，按实际中断点连续分段执行至脚本末尾；所有段落均通过，无失败项。
