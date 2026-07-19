# MCBEEditor iOS 13 v1.1.3

## 实体与方块实体新建

- 实体栏目右上角新增“+”入口，根据当前“实体/方块实体”选项创建对应对象。
- 新建现代实体时写入独立 `actorprefix<UniqueID>` 记录，并把 UniqueID 加入目标区块 `digp` 摘要。
- 新建方块实体时追加到目标区块 `BlockEntity(0x31)` 连续 NBT。
- 支持从空白基础模板创建，也支持从现有对象完整复制后修改坐标、维度、ID 和 UniqueID。
- 可直接使用当前地图选中的方块或实体位置。
- 方块实体目标坐标已存在记录时拒绝重复创建。

## 删除

- 对象详情、长按菜单、侧滑菜单和 NBT 编辑器工具栏新增删除。
- 删除现代实体时同步删除/更新 actorprefix 与 digp，使用一个 LevelDB WriteBatch 原子提交。
- 删除旧版区块实体或方块实体时，只移除匹配的连续 NBT 记录；记录为空时删除对应区块键。
- 新增“复制为新实体/方块实体”，避免直接破坏原对象。

## UniqueID 修改

- NBT 编辑器允许直接修改实体 `UniqueID` 的 Long 值。
- 现代实体修改 UniqueID 时会创建新 actorprefix 键、删除旧键，并把所有相关 digp 引用从旧 ID 改为新 ID。
- 同时修改坐标、维度和 UniqueID 时，会一次完成 actor 键和源/目标摘要迁移。
- 保存前检查目标 UniqueID 是否已被现代或旧版实体占用。
- UniqueID 标签仍禁止删除与重命名。

## 其他

- 修复实体栏目控件栈中重复加入“实体/方块实体”分段控件的问题。
- 新增实体创建、删除、UniqueID 与跨区块迁移的内存 LevelDB 回归测试。
- MARKETING_VERSION：1.1.3
- CURRENT_PROJECT_VERSION：113
