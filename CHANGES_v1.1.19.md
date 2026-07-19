# MCBEEditor iOS 13 v1.1.19（129）

## 命令栏目

- 新增 `setblock 目标维度 x y z 层0方块名 层0states 层1方块名 层1states`，复用 `fill` 的严格方块状态与缺失区块写入逻辑，只修改一个坐标。
- 新增 `setworldspawn x y z`，写入 `level.dat` 的 `SpawnX/SpawnY/SpawnZ`。
- 新增 `spawnpoint 目标 维度 x y z`，仅修改匹配玩家的出生点，并写入 `SpawnDimension` 与 `SpawnForced=1`。
- 新增 `structure save/load/delete`：结构名称必须为 `namespace:name`；save 覆盖同名 `structuretemplate_`；load/delete 在名称不存在时失败；delete ALL 清空全部保存结构。
- 新增 `tickingarea add/delete/list`：支持 square/circle、三维度、名称、预加载标志、ALL 删除和按维度纵向列表。
- 所有新增命令严格检查参数数量、坐标范围、维度名称、结构名称与常加载区域限制，多余或缺少参数都不会执行写入。

## 结构保存与加载

- `structure save` 将指定区域的层0、层1和方块实体编码为 Bedrock mcstructure NBT。
- 调色板按完整方块状态去重，`block_indices` 使用完整双层体积，结构原点和尺寸经过溢出检查。
- `structure load` 支持写入已加载或缺失目标区块，自动适配 v7/v8/v9 SubChunk，并恢复方块实体坐标。
- 结构写入后读回验证；删除操作使用结构模板前缀批量处理。

## 常加载区域

- `tickingarea add square` 使用两组区块坐标建立矩形区域。
- `tickingarea add circle` 使用中心区块与边界区块计算半径，最大 4 区块。
- 名称按不区分大小写检查重复；单区域最多 100 区块，世界最多 10 个区域。
- `tickingarea list` 按要求输出矩形 `to` 或圆形 `radius` 的逐行列表。

## 验证

- 新增命令解析、世界/玩家出生点、单方块写入、结构保存加载删除、常加载区域增加列表删除的可执行内存数据库回归。
- Swift 源码语法、Shell 脚本、GitHub Actions YAML、补丁应用和 ZIP 完整性检查通过。
