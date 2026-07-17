# Blocktopograph iOS 13 v1.1.6

## 现代实体创建与复制修复

上一版在主世界创建或复制现代实体时，把摘要写成了：

```text
digp + chunkX + chunkZ + DimensionID(0)
```

游戏实际使用的主世界区块键不包含维度字段，应为：

```text
digp + chunkX + chunkZ
```

因此应用能够扫描到自己写入的 `actorprefix`，但 Minecraft 不会通过标准摘要加载该实体，`/kill` 也无法命中它。

本版改为：

- 主世界始终使用 12 字节 `digp + X + Z` 键；
- 下界、末地等非零维度继续使用 `digp + X + Z + DimensionID`；
- 打开实体栏目或创建新实体时，自动扫描并迁移 v1.1.3–v1.1.5 产生的错误主世界摘要键；
- 迁移时合并标准键中已有的 ActorUniqueID，并通过 LevelDB WriteBatch 原子写入和删除旧键；
- 删除现代实体时扫描并移除所有摘要引用，包括旧版错误键；
- 实体总览只显示被有效 `digp` 引用的现代实体；孤立 `actorprefix` 仅产生诊断，不再作为存活实体出现。

新建实体基础模板还补充了 `definitions`、`Persistent`、`IsAutonomous`、`Motion`、`Rotation`、`OnGround`、`FallDistance`、`Fire` 和 `Air` 等基础标签。复制实体并修改 identifier 时，会同步替换原实体类型 definition，避免 NBT 的 `identifier` 与 `definitions` 不一致。

## 数字方块 ID

新增旧版 Bedrock 方块数字 ID 0–255 对照：

- 数字 ID → 数据值表中的旧版 `minecraft:*` 字符串 ID；
- 旧版字符串 ID及现代常用别名 → 数字 ID；
- 支持十进制和十六进制查询；
- 旧版数字 SubChunk 在地图方块信息、方块列和搜索结果中显示对应字符串 ID，并同时显示原数字 ID 与 metadata；
- 方块搜索名称字段支持数字 ID、十六进制 ID、字符串 ID 和 `legacy:id:data`；
- 在现代调色板替换名称时，输入数字 ID会自动转成对应的字符串 ID；
- “信息 → 基岩版数据值”新增“方块ID”查询列表。

数字 ID 表用于旧版存档兼容，0–255 的主对应名称采用链接数据值表中的旧版字符串 ID，并参考 PMMP 的 `block_legacy_id_map.json` 交叉核对；例如数字 ID 5 对应 `minecraft:planks`，`minecraft:oak_planks` 作为现代别名也可反查。现代世界仍以方块状态 NBT 的字符串 identifier 和 states 为准。

## 版本

- MARKETING_VERSION：1.1.6
- CURRENT_PROJECT_VERSION：116
- 最低系统：iOS 13.0
