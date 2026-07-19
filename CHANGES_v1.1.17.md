# MCBEEditor iOS 13 v1.1.17（127）

## 存档实测与 SubChunk v8 修复

对用户提供的存档进行 LevelDB 记录检查后确认，主世界 `(0,0)` 附近区块使用：

- `LegacyVersion = 19`
- `Data2D`
- 调色板格式 `SubChunk v8`
- Y=80–95 对应的 SubChunk 5 原本不存在

此前缺失 SubChunk 会被创建为旧数字 ID v7，或被强制升级为 v9，导致同一区块出现不兼容的格式组合。Minecraft 进入世界后可能忽略修改、重新生成区块或恢复为空。

现在：

- `BedrockEmptyChunkProfile` 记录维度实际使用的 SubChunk 版本；
- 修改缺失 SubChunk 时，优先扫描目标区块已有兄弟 SubChunk；
- `LegacyVersion/Data2D` 与调色板 v8 被视为合法组合，不再误判为数字 ID 旧格式；
- 已有区块只新增目标 SubChunk，不重写其 Version、Data2D/Data3D 或 FinalizedState；
- 完全缺失的区块按当前维度模板写入匹配的元数据和 SubChunk 版本；
- 方块 NBT、`fill` 与 `clone` 使用同一版本选择逻辑；
- 只有 v0/v2–v7 数字 ID SubChunk 遇到现代方块或 states 时，才执行整区 v9 升级。

## 实体导出

长按实体或打开实体详情后可选择“导出实体 NBT”。导出只包含当前选中实体自身的完整 Compound，不再导出同一旧版区块 Entity 记录中的其他实体。

可选格式：

- 实体 JSON `.json`
- Little Endian NBT
- Little Endian VarInt NBT
- Big Endian NBT

实体 JSON 使用 `mcbeeditor-nbt-json` version 1，实体根 Compound 的每个子标签作为 `documents` 数组中的一项保存。

## 实体导入

新建实体页面改为“从实体 NBT／JSON 文件导入…”。

支持：

- 单根 NBT；
- 连续多根 NBT；
- 实体标签数组 JSON；
- 普通 MCBEEditor 类型化 JSON；
- 可推断类型的普通 JSON。

仍需先指定实体类型、维度、坐标和起始 UniqueID。读取后进入实体 NBT 检查页面，用户可修改每个实体后再确认导入。

## 界面

- 命令栏目打开后不再显示初始说明文字，终端输出区默认为空；
- MCBEEditor 主页的 NBT 工具图标改为圆角半径更大的圆润卡片造型。

## 测试

- 增加 `LegacyVersion=19 + Data2D + v8` 缺失 Y=80 SubChunk 的持久化回归；
- 验证新增 SubChunk 保持 v8，且不生成 Version/Data3D；
- 增加实体标签数组 JSON 编码和解码往返测试；
- 完成实体、方块 NBT、区块、命令、地图、村庄、常加载区域等分段核心回归；
- 全部 Swift 源码通过语法解析。
