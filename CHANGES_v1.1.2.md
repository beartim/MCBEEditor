# Blocktopograph iOS 13 v1.1.2

## 修复：Minecraft 可识别的常加载区域

上一版错误地把所有常加载区域作为连续 NBT 根标签写进单个 LevelDB 键 `tickingarea`。Minecraft 实际使用一条区域对应一条 LevelDB 记录：键名以 `tickingarea_` 开头，值为一个普通 Little-Endian NBT Compound。

本版改为：

- 扫描所有以 `tickingarea` 开头的 LevelDB 记录；
- 对游戏原生的 `tickingarea_*` 记录逐条读取和保存；
- 新区域使用 `tickingarea_<UUID>` 唯一键；
- 每个值只编码一个 NBT 文档；
- 保存使用 LevelDB 原子批处理；
- 保留已有记录中的 `EntityId`、`IsAlwaysActive`、`MaxDistToPlayers` 等未知扩展标签；
- 自动把 v1.1.0/v1.1.1 的单键连续 NBT 拆分迁移为独立记录；

## 地图框选

- “框选区域操作”新增“常加载区域编辑…”；
- 自动换算为框选所覆盖的区块范围；
- 显示与选区相交的常加载区域；
- 右上角“+”以当前选区外接矩形预填新增区域；
- 支持编辑、删除和批量预加载操作。

## 区块菜单

- 单个区块的“管理”菜单新增“常加载区域编辑…”；
- 批量区块菜单将原“添加为常加载区域”升级为“常加载区域编辑…”；
- 批量入口可编辑与所选区块外接矩形相交的已有区域，也可新增区域。

## 版本

- MARKETING_VERSION：1.1.2
- CURRENT_PROJECT_VERSION：112
