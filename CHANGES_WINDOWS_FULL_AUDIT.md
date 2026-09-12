# Windows 全体代码审计 / iOS 功能完整同步

本轮不是按单一报错修补，而是重新以当前 iOS 源码为基准，对 Windows Core、WPF 入口、LevelDB/NBT 写入、地图/区块/区域、实体、常加载区域、独立 NBT 工具与便携单 EXE 资源做全量静态审计。

## 审计中发现并补齐的真实功能缺口

- 区块页补齐单区块：复制区块内容、方块搜索/替换、HardcodedSpawners 编辑。
- 区块列表改为 Ctrl/Shift 精确多选并补齐批处理：搜索替换、layer/storage 替换、生物群系、常加载区域、删除 HardcodedSpawners、清空、重新生成。
- 地图框选高级操作补齐：常加载区域编辑、整垂直范围区域复制、清空区域、重新生成区域。
- 地图框选补齐“对齐区块边界”。
- 区域复制按 iOS 语义实现：整区块且不重叠时走原始区块记录快速复制；其它情况先快照源 SubChunk，支持重叠复制，只处理 editable storage 0/1，并同步 biome 与 BlockEntity。普通实体、ticks、HardcodedSpawners 不随区域复制。
- 实体列表补齐直接“导出实体 NBT/JSON”和“复制坐标”。
- NBT 编辑器补齐“复制值”“复制路径和值”。
- 新建/复制实体或方块实体窗口补齐“使用当前选中位置”；复制对象时仍可从原对象位置一键切到地图/实体列表当前选中坐标。
- 常加载区域窗口补齐 Ctrl/Shift 多选、批量开启预加载、批量关闭预加载、批量删除；Core 一次保存完整 tickingarea 记录集，不在 UI 中循环多次写库。
- Windows 主界面补齐“说明与许可证”，GNU AGPL-3.0 文本嵌入 WPF 单文件载荷，不依赖外置许可证文件。

## 区块/区域复制一致性

- `BedrockChunkStore.CopyChunk` 复制 Data3D/Version/Data2D/SubChunk/LegacyTerrain/BlockEntity/LegacyBlockExtraData/BiomeState/FinalizedState/BorderBlocks/Checksums 等区块记录。
- 不复制普通 Entity、actor/digp、pending/random ticks、HardcodedSpawners，与 iOS `copyChunk` 保持一致。
- BlockEntity 的 x/z 及 pairx/pairz 等坐标通过共享 `BedrockBlockEntityCoordinateTools` 统一平移，避免区块复制与区域复制保留两套重复实现。
- 非整区块区域复制先完整读取源数据再写目标，源/目标重叠时不会读取刚刚写入的目标数据。

## 移植阶段冗余/缓解代码清理

确认无调用点后删除：

- `BedrockRegionBlockStore.StateSummary()` 调试摘要。
- `BedrockRegionBlockStore` 未使用的 `GetCurrent()`。
- `BedrockRegionAdvancedStore.ReplaceByName()` 早期测试/UI compatibility wrapper；自测统一使用正式 `ReplaceCoordinated()`。
- `BedrockBlockStore.PlanCopyBlock()` 未使用包装。
- `StructureNbtStore.ValidateImportDocument()` 未使用包装。
- `BedrockBiomeLayer.WithValues()`、`BedrockBiomeDocument.UpdateBiomeId()` 等无调用帮助方法。
- `BinaryDataReader/Writer` 中无调用的 UInt32/UInt64 Big/Little Endian API。
- `MapExportFrame`/overlay 等无调用帮助代码。

收敛重复缓解逻辑：

- 地图方块选点不再额外渲染一次地表并静默吞异常，而直接使用已经读取的方块列确定初始 Y。
- 纹理重新加载的可选目录 I/O 容错只保留在 `BlockTextureOverrideStore`，地图渲染/PNG 导出调用点不再各包一层静默 `try/catch`。
- `WorldInfoService` 不再把数据库/文件枚举失败静默伪装成玩家数、实体数、区块数、村庄数或文件大小为 0；错误向上报告。工具修改成功但世界信息刷新失败时会明确显示错误，而不会静默忽略。
- 旧数字 SubChunk 版本探测只捕获预期的数据/格式/范围异常，不再使用裸 `catch {}`。
- tickingarea LevelDB 键 UTF-8 解码只处理预期的 `DecoderFallbackException`。
- 时间预设越界不再静默吞掉 `OverflowException`。

## 明确保留的兼容代码

以下不是移植缓解措施，不能删除：

- LegacyTerrain、LegacyBlockExtraData、旧数字 ID SubChunk。
- SubChunk v0-v9 以及未知/未来版本的只读原样保留策略。
- Data2D/Data2DLegacy/Data3D biome。
- 旧式 Entity(0x32) 与现代 actorprefix/digp。
- 不同 Minecraft 版本使用的 Version/FinalizedState/BorderBlocks 等区块记录。
- 单个损坏区块/实体记录的局部隔离，避免一个坏记录阻断整个地图/对象扫描。

这些分支服务于 Minecraft Bedrock 世界格式本身，不是 MCBEEditor 历史版本迁移 shim。

## 代码完整性检查

- MainWindow XAML 事件入口静态核对：96 个，全部存在对应 code-behind 方法。
- 私有方法/字段全局标识符扫描：未发现只声明不使用的候选。
- 新增 `Scripts/test_windows_full_parity_audit.sh`，覆盖区域/区块/常加载/NBT/对象/许可证入口和已删除 dead-code wrapper 的回归检查。
- `Scripts/test_windows_parity_icon_cleanup.sh` 改为检查实际纹理 Store 行为，不再依赖已删除的历史注释文本。
- `Scripts/test_*.sh` 当前全集通过。
- `MCBEEditor.Core.SelfTest` 新增部分区域复制与 tickingarea 批量预加载/批量删除断言；当前 Linux 容器没有 .NET SDK/MSBuild，因此最终 C# 编译与 SelfTest 运行仍需由 Windows `build.cmd` 执行。

## 单 EXE 图标

继续沿用上一轮结果：WPF payload 与 PortableLauncher 都使用与 iOS AppIcon 相同的图案，仅把与图像边缘连通的白色背景转换为透明 Alpha；最终发布仍只有 `Windows\dist\MCBEEditor.exe`。
