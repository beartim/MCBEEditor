# MCBEEditor iOS 13 v1.1.9 修改说明

## 命令栏目

- 在 NBT 与信息之间新增“命令”顶层栏目，提供带主世界／下界／末地选择器的命令行窗口。
- 命令输入不使用斜杠；运行期间锁定输入和维度选择，输出区使用等宽字体显示命令、结果和错误。
- 新增 `help`、`clear`、`clearspawnpoint`、`clone`、`fill` 五条严格格式命令。

## 命令行为

- `help [命令]`：无参数显示全部命令和格式；指定参数时只接受已存在的命令名称。
- `clear [UniqueID]`：无参数清除本地玩家的 Inventory、Armor、Offhand、Mainhand 等物品容器；指定参数时按本地或在线玩家 NBT 中的 UniqueID 精确查找。
- `clearspawnpoint [UniqueID]`：删除玩家 SpawnX／SpawnY／SpawnZ／SpawnDimension／SpawnForced 及兼容命名的出生点标签。
- `clone x1 y1 z1 x2 y2 z2 x3 y3 z3`：复制层 0、层 1 与方块实体；源或目标涉及未加载区块时整块跳过。源目标重叠时不建立源快照，按坐标顺序直接覆盖，后续读取可看到前面已写入的结果。
- `fill x1 y1 z1 x2 y2 z2 层0名称 层0states 层1名称 层1states`：同时写入两层方块状态，并清理范围内旧方块实体；层 1 指定空气且原 SubChunk 不存在层 1 时不会创建第二 storage。

## 严格参数与 states

- `clone` 必须恰好提供 9 个整数参数；`fill` 必须恰好提供 6 个整数坐标和 4 个方块参数，缺少或多余参数都会拒绝执行。
- 方块名称必须为 namespaced identifier。
- states 只接受大写 `NULL`，或 `'Byte'"键"="值"`、`'Int'"键"="值"`、`'String'"键"="值"` 等格式；多项以英文逗号连接。
- 支持 Byte、Short、Int、Long、Float、Double、String，重复键、引号未闭合、类型和值不匹配均会报错。

## 区块与格式兼容

- `clone` 与 `fill` 仅修改当前命令页选择维度内已经存在的区块记录，未加载区块不会被创建。
- 已加载区块中缺失的垂直 SubChunk 可按需创建；层 0 和非空气层 1 会触发创建，纯空气写入不会无意义创建记录。
- 支持现代调色板 SubChunk；旧版数字 ID SubChunk 可在 states 为 NULL 且方块存在旧版数字 ID 对照时填充。混合格式复制会在可无损转换时转换，否则拒绝写入。
- 方块和方块实体通过同一个 LevelDB WriteBatch 提交，避免只写入一半。

## 版本

- Marketing Version：1.1.9
- Build：119
- 最低系统：iOS／iPadOS 13.0
