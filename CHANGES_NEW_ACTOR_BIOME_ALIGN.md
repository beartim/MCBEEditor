# MCBEEditor 1.0.0 — 新版 Actor / Data3D / 框选兼容修复

软件版本保持 **1.0.0（构建号 100）**。

## 新版 actorprefix / UniqueID

对用户上传的新版本 Minecraft 存档实测发现，例如某实体的：

- actorprefix 键后 8 字节：`00 00 00 01 00 00 00 13`
- 同一实体 NBT `UniqueID`：`-4294967277`

两者不再是同一个数值。修复后：

- 列表、详情、目标选择器和命令统一显示/匹配实体 NBT `UniqueID`；
- actorprefix/digp 仍保留原始 8 字节 Actor 存储引用用于数据库定位；
- 保存坐标或跨维度移动时移动原始 digp 引用；
- 修改 NBT `UniqueID` 不再重命名 actorprefix 键或改写 digp 引用；
- 删除实体按原始 Actor 存储引用清理所有 digp；
- `scanEntities(uniqueIDs:)` 通过 actor NBT 反查 NBT UniqueID，不再把 UniqueID 直接拼成 actorprefix 键；
- 新建实体仍同时检查 NBT UniqueID 冲突与将要创建的 actorprefix 键冲突。

## 生物群系 Data3D

- 读取 `0xff` 未单独保存的 Data3D 层时，使用前一保存层最高 Y 平面作为有效生物群系并向上继承；`isAbsent` 仍保留，因此未编辑时重新编码仍可写回 `0xff`。
- 层列表显示每个生物群系的完整 `ID:名称×数量`，不再只预览前几项。
- 新增“整区块设置”，一次覆盖 Data3D 全部 24 层、即 16×384×16 个位置，并将所有层显式保存。

## 其他

- `minecraft:sulfur_cube` 中文名改为“硫方怪”。
- 框选面板新增“对齐区块边界”，使用 `expandedToChunkBounds` 向外扩展到所有相交区块的完整 X/Z 边界。
