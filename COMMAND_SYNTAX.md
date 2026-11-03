# 命令格式与省略参数对照（2026-10-29）

适用于 iOS/Windows GUI 与 Apple/Windows CLI。全部 28 个命令已逐项检查，旧完整写法继续有效。

## 统一规则

- `[参数]` 表示可省略，嵌套方括号表示尾部参数从右向左省略；方括号本身不要输入。
- 目标、维度和坐标显式填写。三坐标、六坐标和区块 X/Z 必须成组，不支持 `~` 或 `^` 相对坐标。
- 命令/子命令、Auto、NULL、default、preserve、empty 不区分大小写。字符串 ID 与 NBT 内容保留原样；物品/方块/实体仍用完整 namespace:name。
- `ALL` 保持大写，以免把名为 `all` 的区域或维度解释成全部对象。开关仍严格使用 `0` 或 `1`。
- 方块、群系、出生点及结构坐标为 Int32 整数；实体查询/kill 范围、summon 和 teleport 接受可写入 Float 的有限小数。teleport 整数 Y 与小数 Y 的原有玩家眼高差异保留；区块操作使用区块坐标。
- effect 和 weather 的持续时间均以游戏刻计；effect 的等级为存档 Byte 原始值（0 表示原始 0），不是界面显示等级。显式 0、负持续时间及原始等级 -1/255 不会被默认值替换。

## 全部命令

| 命令 | 格式 | 可省略参数与必填项 |
|---|---|---|
| `help` | `help [命令]` | 省略命令名称显示全部帮助。 |
| `info` | `info` | 无参数，多余参数拒绝。 |
| `dimension` | `dimension` | 裸命令默认 query；add/empty/purge 参数必填。 |
|  | `dimension query` |  |
|  | `dimension add 名称 ID` |  |
|  | `dimension empty 名称或ID` |  |
|  | `dimension purge 名称或ID` |  |
| `clear` | `clear 目标` | 目标必填，不隐式选择 @s 或 @e。 |
| `clearspawnpoint` | `clearspawnpoint 目标` | 玩家目标必填。 |
| `clone` | `clone 源维度 x1 y1 z1 x2 y2 z2 目标维度 x3 y3 z3` | 源/目标维度和全部九个坐标必填。 |
| `chunk` | `chunk` | 裸命令默认 query；query 可省略维度，再可整组省略区块 X/Z。 |
|  | `chunk query [维度 [区块X 区块Z]]` |  |
|  | `chunk empty 维度 区块X 区块Z` |  |
|  | `chunk regenerate 维度 区块X 区块Z` |  |
| `daylock` | `daylock 0或1` | 0/1 必填，无隐式开关。 |
| `effect` | `effect give 目标 状态效果ID或ALL [持续游戏刻 [原始等级]]` | give：600 游戏刻、原始等级 0；clear：效果默认 ALL；目标必填。 |
|  | `effect clear 目标 [状态效果ID或ALL]` |  |
| `entity` | `entity [目标]` | 默认 @e，含玩家；支持非零 Int64 UniqueID、@s、@a、@e、完整 identifier。单独数字为 UniqueID。 |
|  | `entity 维度 [x1 y1 z1 x2 y2 z2]` | 目标默认 @e；完整六坐标仍支持原写法。 |
|  | `entity 目标 维度 [x1 y1 z1 x2 y2 z2]` | 可按目标和维度继续限定完整坐标范围；数字或 namespaced 维度写在目标后。 |
| `experience` | `experience add 目标 整数` | 操作、目标、数值必填；query 不接数值。 |
|  | `experience addlevel 目标 整数` |  |
|  | `experience level 目标 0到24791整数` |  |
|  | `experience percent 目标 0到1浮点数` |  |
|  | `experience query 目标` |  |
|  | `experience set 目标 非负整数` |  |
| `fill` | `fill 维度 x1 y1 z1 x2 y2 z2 方块ID [states] [方块ID [states] ...] [方块实体]` | 每层 states 默认 NULL，方块实体默认 preserve；两角坐标必填。 |
| `fillbiome` | `fillbiome 维度 x1 y1 z1 x2 y2 z2 生物群系数字ID或字符串ID` | 维度、六坐标及群系 ID 必填。 |
| `getblock` | `getblock 维度 x y z` | 维度和三坐标必填。 |
| `give` | `give 目标 [Slot] 物品ID [数目 [物品标签]]` | 槽位 Auto、数目 1、标签 NULL；指定标签须先写数目。 |
| `kill` | `kill 目标 [是否杀死创造模式玩家]` | 末尾开关默认 0；必须写目标或维度与完整范围。 |
|  | `kill 维度 x1 y1 z1 x2 y2 z2 [是否杀死创造模式玩家]` |  |
| `kick` | `kick 目标` | 在线玩家 UniqueID 或 @a 必填。 |
| `setblock` | `setblock 维度 x y z 方块ID [states] [方块ID [states] ...] [方块实体]` | 每层 states 默认 NULL，方块实体默认 preserve；三坐标必填。 |
| `setworldspawn` | `setworldspawn x y z` | 世界主世界三坐标必填。 |
| `spawnpoint` | `spawnpoint 目标 维度 x y z` | 玩家目标、维度和三坐标必填。 |
| `spread` | `spread 目标` | 目标必填。 |
| `storage` | `storage query 维度 x y z` | 仅 set 的 states 可省略为 NULL；层号、delete/clear 范围必填。 |
|  | `storage set 维度 x y z 层数 方块ID [states]` |  |
|  | `storage delete 维度 x y z 层数` |  |
|  | `storage clear 维度 x y z 保留到的层数` |  |
| `structure` | `structure` | 裸命令 query；import/export 名称仅在可交互场景省略，导出格式必填。 |
|  | `structure query` |  |
|  | `structure import [名称]` |  |
|  | `structure export mcstructure\|nbt\|json\|txt [名称]` |  |
|  | `structure save 名称 维度 x1 y1 z1 x2 y2 z2` |  |
|  | `structure load 名称 维度 x y z` |  |
|  | `structure delete 名称或ALL` |  |
| `summon` | `summon 实体类型 维度 x y z [NBT标签或default [UniqueID或Auto]]` | NBT 默认 default，UniqueID 默认 Auto；指定 ID 需先写 NBT/default。 |
|  | `summon 实体NBT标签` |  |
| `teleport` | `teleport 目标 维度 x y或Auto z` | 目标、维度、X/Y/Z 必填；Y 可用 Auto，不能删除 Y 占位。 |
| `tickingarea` | `tickingarea` | 裸命令/list/query 默认 ALL，add 预加载默认 0；名称必填。 |
|  | `tickingarea add square 维度 x1 z1 x2 z2 名称 [预加载0或1]` |  |
|  | `tickingarea add circle 维度 x1 z1 半径 名称 [预加载0或1]` |  |
|  | `tickingarea delete 名称或ALL` |  |
|  | `tickingarea list [维度或ALL]` |  |
|  | `tickingarea query [维度或ALL]` |  |
| `time` | `time` | 裸命令/query 默认查询 daytime；写操作及其数值/时段必填。 |
|  | `time query [daytime\|gametime\|day]` |  |
|  | `time add 整数` |  |
|  | `time set 非负整数` |  |
|  | `time ceil day\|sunset\|night\|sunrise\|noon\|midnight` |  |
|  | `time floor day\|sunset\|night\|sunrise\|noon\|midnight` |  |
| `weather` | `weather` | 裸命令 query；clear 自动变化默认 1；rain/thunder 默认 6000 游戏刻、1.0、1。 |
|  | `weather query` |  |
|  | `weather clear [自动变化0或1]` |  |
|  | `weather rain [持续游戏刻 [强度 [自动变化0或1]]]` |  |
|  | `weather thunder [持续游戏刻 [强度 [自动变化0或1]]]` |  |

## 常用省略写法

```text
give @s minecraft:stone
give @s 5 minecraft:diamond 3
effect give @a freezing
effect clear @s
kill overworld 0 0 0 1 1 1
setblock overworld 0 64 0 minecraft:stone
fill overworld 0 64 0 15 64 15 minecraft:stone minecraft:water empty
summon minecraft:pig overworld 0 64 0
storage set overworld 0 64 0 1 minecraft:water
weather thunder 12000 0.5
tickingarea add circle overworld 0 0 1 Spawn
```

`give @s minecraft:stone` 等同于 `give @s Auto minecraft:stone 1 NULL`。

`kill ...` 省略末尾开关等同于 0：跳过创造模式玩家，选中的其他玩家生命值清零，非玩家实体删除。省略开关不会省略目标或范围。

## 方块 states 与方块实体的分界

方块 ID 后的第一个 NBT 是该层 states。只有在 states 已消费之后，另一个位于末尾的 NBT 才是方块实体模板。要明确设置方块实体而 states 为空时，填写 NULL 占位：

```text
setblock overworld 0 64 0 minecraft:stone NULL 'String'"id"="Chest"
```

省略方块实体保留当前位置原有方块实体；`empty` 清除；`preserve` 显式保留。每层 states 可独立省略，但省略 states 表示空 states，不表示保留该层原 states。只有未提供的高层 storage 保持原样。仍最多 255 层，旧数字格式的无损转换限制不变。

## 仍需明确填写的参数

clear、kick、spread、spawnpoint 等命令不会默认选择当前玩家。带写入含义的子命令、坐标、storage 层号和结构导出格式保持必填，以便直接判断影响范围。

`structure import [名称]` 与 `structure export 格式 [名称]` 在 GUI/交互 CLI 中可继续通过对话选择名称。非交互脚本必须指定名称和 `--file` 路径，覆盖文件仍须 `--overwrite`。这与尾部数值参数的默认值是不同的交互条件。

没有为 `entity` 增加 query 子命令：现有存档可以存在名为 query 的维度，`entity query` 继续表示查询该维度，不改变已有脚本含义。`tickingarea query` 是新增的 list 别名，不与维度参数冲突。

## entity 查询目标与输出（2026-10-29）

`entity` 等同 `entity @e`，查询所有维度的玩家与普通实体，排除方块实体。`@s` 为本机玩家，`@a` 为全部玩家，`minecraft:player` 也可选择玩家。单个数字解释为非零有符号 Int64 UniqueID；`entity 12345678` 查询所有匹配该 ID 的独立记录，包含玩家且保留重复 ID。按数字维度查询可写 `entity @e 0`。其他单个 namespaced identifier 按实体类型解释，原版 namespaced 维度别名保留；自定义 namespaced 维度写在目标之后，例如 `entity @e custom:moon`。

每条结果包含类型、维度名称与 ID、实际坐标和全部 MCBE-SNBT：

```text
minecraft:pig Dimension=overworld(0) Pos=(0,64,0) NBT=['String'"identifier"="minecraft:pig",'Long'"UniqueID"="12345678",'List''Double'"Pos"="0.0,64.0,0.0"]
```

坐标字段不加玩家眼高，缺少有效位置时显示 `Pos=NULL`；无位置的记录不匹配坐标范围。NBT 使用无损 MCBE-SNBT 编解码器格式；嵌套 List 保留各子项类型，数值不截断精度，NaN 用 `bits:` 表示原始位。显示出的类型/维度/坐标不会写回原 NBT。
