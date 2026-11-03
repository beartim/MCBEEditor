MCBEEditor Commands 文件夹说明

此目录用于在进入存档时批量执行 MCBEEditor 命令。

使用方法：
1. 在本目录中自行创建 Command.txt，文件必须为 UTF-8 文本。
2. Command.txt 每行只能写一条命令；空行会被忽略。
3. 命令与软件“命令”栏目中的输入格式完全相同，不需要也不能添加开头的 / 斜杠。
4. 进入存档时，只要检测到 Command.txt，MCBEEditor 会直接进入“命令”栏目；若其中存在非空命令，会询问是否执行。
5. 用户确认后，程序会先检查全部命令语法。只要任意一行存在语法错误，本次 Command.txt 中所有命令都不会执行。
6. 全部语法检查通过后，命令会从上到下逐行执行，并在“命令”栏目中即时显示每一条命令及其执行结果。
7. 批量命令执行期间不能离开“命令”栏目，也不能关闭当前存档；运行时错误只影响对应命令，后续命令仍会继续执行。
8. MCBEEditor 不会自动创建、修改或删除 Command.txt。

当前支持的全部命令（与本版本 help 输出一致）：

help [命令]
无参数：显示全部命令；指定已存在的命令：显示该命令的使用方法。
示例：help
示例：help give
语法约定：[参数] 可省略，嵌套方括号从右向左省略；坐标必须成组填写。命令、子命令及 Auto/NULL/default/preserve/empty 不区分大小写；ALL 必须大写；ID 和 NBT 内容保持原样。目标、维度及坐标不推断。

info
无参数。输出信息栏目中的全部世界信息，每条信息单独一行。
示例：info

dimension
dimension query
dimension add 名称 ID
dimension empty 名称或ID
dimension purge 名称或ID
query 列出存档中存在的维度名称、ID 和区块数，包含已登记的空维度。add 支持有或无 namespace 的名称及 Int32 ID；名称、ID 不得重复。缺失原版维度可用 overworld 0、nether 1、the_end 2 重建。
示例：dimension query
示例：dimension add wzn:bear 1000
示例：dimension add bear 1003
示例：dimension add nether 1
empty 清空目标维度内容，保留维度登记；示例：dimension empty wzn:cat
示例：dimension empty 1001
purge 彻底删除维度及登记；受影响玩家迁到剩余主世界或最小ID维度，当前位置(0.5,65.62,0.5)，重生点(0,64,0)。无剩余维度且有玩家引用时拒绝。
示例：dimension purge wzn:bear
示例：dimension purge 1000
省略子命令时默认 query，只读查询。

clear 目标
目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。清除所有匹配玩家与实体的物品；村民交易数据不会清除。
示例：clear @e

clearspawnpoint 目标
目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。只对匹配的玩家清除出生点。
示例：clearspawnpoint @a

clone 源维度 x1 y1 z1 x2 y2 z2 目标维度 x3 y3 z3
维度接受当前存档的名称或 Int32 ID。复制源区域两角到目标维度的目标起点；v8 或更新的已知结构化 SubChunk 会逐方块复制所有实际存在的 storage，并把目标多余 storage 在复制位置清为空气；旧数字格式仍按 layer0 + LegacyBlockExtraData layer1 处理。涉及未加载区块时会先写入空气区块与生成完成状态；重叠区域使用命令开始时的原始源数据。
示例：clone overworld 0 0 0 5 100 46 nether 9 50 9
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。

chunk
chunk query [维度 [区块X 区块Z]]
chunk empty 维度 区块X 区块Z
chunk regenerate 维度 区块X 区块Z
维度接受当前存档的名称或 Int32 ID。query 无参数时按当前存档维度顺序逐行以蓝色显示全部已加载区块的信息与生成情况；只给维度时仅显示该维度；再给区块坐标时返回指定区块信息。所有 query 输出行都会追加 IsSlimeChunk=True/False 和 Ticking=True/False。empty 清空指定区块并写入最小空气区块与 FinalizedState=2；regenerate 删除指定区块记录，使游戏按世界种子重新生成。
示例：chunk query
示例：chunk query overworld
示例：chunk query overworld 0 0
示例：chunk empty nether -2 5
示例：chunk regenerate the_end 0 0
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
裸命令 chunk 等同 chunk query；要限定维度或区块仍须写 query。区块 X/Z 必须成对填写。

daylock 0或1
1 表示锁定时间并将 level.dat 的 dodaylightcycle 写为 0；0 表示解除锁定并写为 1。命令不修改当前 time。
示例：daylock 1

effect give 目标 状态效果ID或ALL [持续游戏刻 [原始等级]]
effect clear 目标 [状态效果ID或ALL]
目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。状态效果 ID 必须存在于当前基岩版数据值中；ALL 必须大写。give 的持续时间接受完整 Int32（包括负数）；效果等级接受 -128～255，仍按 Bedrock Byte 原始值写入（例如 -1 与 255 都写为 0xFF）。持续时间单位为游戏刻；等级仍为原始 Byte 值，不额外加减 1。
示例：effect give @a strength 12000 50
示例：effect give @a strength -1 -1
示例：effect clear @e ALL
已收录冰冻效果 freezing（数字 ID 38）；命令参数使用字符串 ID，give、clear 和 ALL 均支持该效果。
示例：effect give @a freezing 200 1
示例：effect clear @e freezing
字符串 ID 可带 minecraft: 前缀；数字 ID 不作为命令参数。give 省略持续时间默认 600 游戏刻，省略原始等级默认 0；若指定等级，须先填写持续时间。clear 省略效果默认 ALL；目标必填。
示例：effect give @s freezing
示例：effect clear @s

entity [目标]
entity 维度 [x1 y1 z1 x2 y2 z2]
entity 目标 维度 [x1 y1 z1 x2 y2 z2]
只读查询玩家与普通实体，不包含方块实体。默认目标为 @e，entity 与 entity @e 完全等价，列出所有维度的全部实体（包括玩家）。
目标支持非零有符号 Int64 UniqueID、@s（本机玩家）、@a（全部玩家）、@e（全部实体，含玩家）或完整实体 identifier；minecraft:player 可用于选择玩家。UniqueID 会返回所有匹配的独立存储记录，不按 ID 去重。
单独数字始终表示 UniqueID，例如 entity 12345678；若要查询数字维度，写 entity @e 0。单个普通名称按维度解析，原版 minecraft:overworld/nether/the_end 别名保留；其他单个 namespace:name 按实体 identifier 解析。自定义 namespaced 维度请写在目标之后，例如 entity @e custom:moon。
维度接受当前存档的名称或 Int32 ID。六个范围坐标须整组填写，支持有限小数、负数、反向角点，范围包含边界；按玩家和实体的实际维度与 Pos 筛选，玩家坐标不加眼高补偿。没有有效坐标的记录仍可按目标/维度查询，显示 Pos=NULL，但不进入坐标范围结果。
每个实体一行：判断的实体类型 Dimension=维度名称(ID) Pos=(X,Y,Z) NBT=[全部MCBE-SNBT标签]。自定义维度可显示登记名称；无法读取名称时显示数字 ID。坐标保留 Double 精度。NBT 使用 MCBE-SNBT 文件格式的无损表示，保留全部标签、类型、顺序、嵌套列表、Int64 和 NaN 原始位，不向原 NBT 补写推断出的类型或坐标。
无匹配时返回“entity：没有匹配的实体。”；损坏实体记录仍显示扫描提示；查询不修改数据库或 level.dat。
示例：entity
示例：entity @s
示例：entity @a
示例：entity @e
示例：entity 12345678
示例：entity minecraft:pig
示例：entity overworld 50 60 65 100 120 150
示例：entity @a overworld 0 0 0 1 1 1
示例：entity @e 0
示例：entity @e custom:moon

experience add 目标 整数
experience addlevel 目标 整数
experience level 目标 0到24791整数
experience percent 目标 0到1浮点数
experience query 目标
experience set 目标 非负整数
目标只能匹配玩家。基岩版实际保存 PlayerLevel 与 PlayerLevelProgress，经验总数由等级曲线计算。add 按总经验增减并自动换算等级和经验条；addlevel 增减经验等级并保留当前经验条百分比；level 直接设定经验等级并把经验条进度设为 0，等级范围均为 0～24791；percent 修改当前经验条百分比；query 逐行显示 minecraft:player、UniqueID、经验总数、等级和经验条进度；set 按总经验重新计算并写入 PlayerLevel 与 PlayerLevelProgress。
示例：experience add @a 100
示例：experience addlevel -4294967270 -3
示例：experience level @s 30
示例：experience percent @s 0.5
示例：experience query @a
示例：experience set @s 2500

fill 维度 x1 y1 z1 x2 y2 z2 方块ID [states] [方块ID [states] ...] [方块实体]
维度接受当前存档的名称或 Int32 ID。至少提供 storage0，layer1 及之后都可省略；每个方块 ID 表示一层，最多 255 个 storage。states 可输入 NULL 或任意 NBT 标签。只修改命令中实际提供的 storage，省略 layer1 时保留原 layer1 及更高层。旧数字 ID SubChunk 保持原格式，仅支持可无损转换为数字 ID 的 layer0/1；无法表示的方块或 states、超过两层的请求会报错，不会自动升级或写入部分修改。
最后的方块实体参数可省略，默认 preserve：preserve 保留原方块实体，empty 清空目标坐标的方块实体；也可传入方块实体的全部 MCBE-SNBT 标签，设定目标方块实体。允许任意 id，不要求与方块类型对应。根 x/y/z 可省略；输入的根坐标标签会自动忽略（名称不区分大小写），写入时按命令选定位置生成唯一的小写 Int 类型 x/y/z。 fill 将模板复制到闭合范围内每个坐标，每份方块实体均使用该位置的实际坐标。 嵌套坐标、Pos 和其他标签保持原样。全部检查及编码通过后一次提交方块、方块实体与区块元数据。
示例：fill overworld 0 64 0 15 64 15 minecraft:stone NULL preserve
示例：fill overworld 0 64 0 15 64 15 minecraft:stone NULL empty
示例：fill the_end 0 0 0 60 200 16 minecraft:leaves 'String'"old_leaf_type"="oak" minecraft:water NULL minecraft:air NULL empty
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
每层 states 可省略，默认 NULL（空 states）；方块 ID 必须使用完整字符串 ID。方块后第一个 NBT 参数属于该层 states；若要传入方块实体模板，必须先写该层 states 或 NULL 占位，再写模板。连续方块 ID 表示连续 storage；省略的高层 storage 保持原样。只允许末尾出现一个方块实体参数。
示例：fill overworld 0 64 0 15 64 15 minecraft:stone
示例：fill overworld 0 64 0 15 64 15 minecraft:stone minecraft:water empty

fillbiome 维度 x1 y1 z1 x2 y2 z2 生物群系数字ID或字符串ID
维度接受当前存档的名称或 Int32 ID。字符串 ID 必须能在内置生物群系表中找到对应数字 ID，否则报错；数字 ID 不要求存在于内置表，可输入 32 位整数原始值。Data3D 只修改两组坐标之间的 Y 范围；Data2D/Data2DLegacy 忽略 Y 坐标并修改水平选区（其格式只能保存 0～255）。
示例：fillbiome overworld 0 -64 0 15 319 15 minecraft:plains
示例：fillbiome nether -32 0 -32 31 127 31 178
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
已收录冰封洞穴 minecraft:ice_caves（数字 ID 196）。
示例：fillbiome overworld 0 -64 0 15 64 15 minecraft:ice_caves

getblock 维度 x y z
返回指定方块位置所有存在的 storage 方块状态以及该坐标的方块实体 NBT。Block 行使用蓝色，BlockEntity 行使用紫色；没有方块实体时显示 BlockEntity=NULL。
示例：getblock overworld -24 64 0
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。

give 目标 [Slot] 物品ID [数目 [物品标签]]
Slot 只能是 Auto 或 0～35 的整数。目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；物品必须使用完整字符串 ID；数目必须是大于 0 的 Int64。物品标签可输入 NULL，或输入任意类型、可多重嵌套的 NBT 标签。玩家：Auto 沿用第一个空 Inventory 槽位、满时最后一格的逻辑，整数 Slot 写入对应 Inventory 槽位。非玩家实体必须已经存在可写入的 Mainhand 标签，否则直接跳过；命令任何时候都不会创建 Mainhand。实体 Auto 写入已有 Mainhand；整数 Slot 在有 ChestItems 时写入对应槽位，超过槽位数时写入最后槽位并同步写入已有 Mainhand；没有 ChestItems 时只写入已有 Mainhand。
示例：give @s Auto minecraft:stone 64 NULL
示例：give @a 5 minecraft:diamond 3 NULL
示例：give minecraft:cow 2 minecraft:lit_smoker 99 'Compound'"tag"="{'Byte'"Unbreakable"="1"}",'Short'"Damage"="1"
省略 Slot 默认 Auto；省略数目默认 1；省略物品标签默认 NULL。槽位若填写仍位于物品 ID 之前，以 Auto/整数和完整物品 ID 区分；提供标签时须先填写数目。
示例：give @s minecraft:stone
示例：give @s 5 minecraft:diamond 3

kill 目标 [是否杀死创造模式玩家]
kill 维度 x1 y1 z1 x2 y2 z2 [是否杀死创造模式玩家]
目标支持非零 UniqueID、@s、@a、@e、实体 identifier，或指定维度与两角坐标。范围包含边界，支持小数、负数和反向角点，按实际 Pos 筛选玩家与非玩家实体，不包含方块实体。
末尾开关只能是 0 或 1，且只影响创造模式玩家：0 跳过创造模式玩家，1 将其生命值 Current 设为 0.0。选中的非创造模式玩家无论开关为 0 或 1 都将生命值 Current 设为 0.0；选中的非玩家实体直接删除。
示例：kill @a 1
示例：kill overworld 0 0 0 1 1 1 1
示例：kill overworld 0 0 0 1 1 1 0
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
省略末尾开关默认 0，仅跳过创造模式玩家；目标或维度与完整六坐标范围仍须填写。
示例：kill @e
示例：kill overworld 0 0 0 1 1 1

kick 目标
目标只能是在线玩家的非零 UniqueID或 @a。UniqueID 删除对应在线玩家数据，@a 删除全部在线玩家数据。
示例：kick @a
示例：kick -4294967270

setblock 维度 x y z 方块ID [states] [方块ID [states] ...] [方块实体]
fill 的单方块版本。至少提供 storage0，layer1 及之后均可省略；最多 255 个 storage。省略的 storage 保持原样。
最后的方块实体参数可省略，默认 preserve：preserve 保留原方块实体，empty 清空目标坐标的方块实体；也可传入方块实体的全部 MCBE-SNBT 标签，设定目标方块实体。允许任意 id，不要求与方块类型对应。根 x/y/z 可省略；输入的根坐标标签会自动忽略（名称不区分大小写），写入时按命令选定位置生成唯一的小写 Int 类型 x/y/z。 嵌套坐标、Pos 和其他标签保持原样。全部检查及编码通过后一次提交方块、方块实体与区块元数据。
示例：setblock overworld 0 64 0 minecraft:stone NULL preserve
示例：setblock overworld 0 64 0 minecraft:stone NULL empty
示例：setblock overworld 0 64 0 minecraft:stone NULL minecraft:water NULL empty
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
每层 states 可省略，默认 NULL（空 states）；方块 ID 必须使用完整字符串 ID。方块后第一个 NBT 参数属于该层 states；若要传入方块实体模板，必须先写该层 states 或 NULL 占位，再写模板。连续方块 ID 表示连续 storage；省略的高层 storage 保持原样。只允许末尾出现一个方块实体参数。
示例：setblock overworld 0 64 0 minecraft:stone
示例：setblock overworld 0 64 0 minecraft:stone minecraft:water empty

setworldspawn x y z
设置世界重生点；坐标必须恰好输入三个整数。世界重生点位于主世界。
示例：setworldspawn 0 80 0

spawnpoint 目标 维度 x y z
目标必须是非零 UniqueID、@s、@a、@e 或 minecraft:player，且最终只能匹配玩家；维度接受当前存档的名称或 Int32 ID。
示例：spawnpoint @a the_end 0 100 0
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。

spread 目标
目标可以是非零 UniqueID、@s、@a、@e 或实体 identifier。每个匹配对象会独立随机选择一个有已加载区块的维度、一个已加载区块及其中一列非全空气的 X/Z，再按 teleport Auto 逻辑传送。输出格式为 identifier UniqueID 维度 X Y Z，并优先显示玩家。
示例：spread @e
示例：spread minecraft:cow

storage query 维度 x y z
storage set 维度 x y z 层数 方块ID [states]
storage delete 维度 x y z 层数
storage clear 维度 x y z 保留到的层数
直接操作指定坐标所在 v8 或更新的已知结构化 SubChunk 的物理 storage。query 逐行用蓝色显示所有 storage 在该坐标的方块状态；set 可设置 layer 0～254，并按需要创建中间空气 storage，最多 255 层；delete 删除整个指定 storage（该 SubChunk 内 4096 个位置都会受影响）并在安全时裁掉后续全空气 storage；clear 参数为 UInt8，0 仅保留 storage0，1 保留 storage0/1，其余类推，255 表示不主动裁剪。
示例：storage query overworld 0 64 0
示例：storage set overworld 0 64 0 8 minecraft:water NULL
示例：storage delete overworld 0 64 0 8
示例：storage clear overworld 0 64 0 1
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
storage set 省略 states 默认 NULL；层数仍必填。delete/clear 作用于整个 SubChunk 的 storage，层号或保留到的层数不可省略。

structure
structure query
structure import [名称]
structure export mcstructure|nbt|json|txt [名称]
query 每行显示一个结构；import 打开文件选择器，export 打开保存窗口；省略名称时通过窗口选择或输入；nbt 为 Big Endian，mcstructure 为 Little Endian；txt 为保留 NBT 类型与根标签的 MCBE-SNBT。
structure save 名称 维度 x1 y1 z1 x2 y2 z2
structure load 名称 维度 x y z
structure delete 名称或ALL
save/load/delete 的名称必须为 namespace:name。save 会直接覆盖同名 structuretemplate_ 记录；load/delete 找不到名称时失败。
示例：structure save mystructure:1 overworld 0 0 0 50 50 50
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
裸命令 structure 默认 query。save/load/delete 的名称、维度及坐标按对应格式必填；导出格式必填。GUI 或交互 CLI 可省略 import/export 名称并按提示选择；非交互 CLI 的名称与 --file 必填。

summon 实体类型 维度 x y z [NBT标签或default [UniqueID或Auto]]
summon 实体NBT标签
实体维度接受当前存档的名称或 Int32 ID；x/y/z 均接受整数或浮点数并直接写入 Pos。第一种格式的 NBT 参数输入 default 时使用实体通用 NBT，否则接受任意类型、可多重嵌套的非空附加标签，不能为 NULL，也不能覆盖命令控制的身份、坐标、维度标签。
末尾 UniqueID 接受 Auto 或非零 Long 整数（-9223372036854775808～9223372036854775807）；省略时按 Auto 处理。Auto 自动生成未占用 ID，手动 ID 与已有实体或要使用的 actor 存储引用冲突时拒绝创建。
第二种格式直接保留提供的 NBT 标签、类型和顺序，必须包含恰好三个可写入 Float 的有限数值组成的 Pos 或 Position List；UniqueID 若提供必须为非零 Long，缺少时自动生成。DimensionId 或 Dimension 必须为 Int32 范围内的整数标签，缺少时写入主世界且不补写维度标签。
示例：summon minecraft:pig overworld 0 64 0 default Auto
示例：summon minecraft:pig overworld 10.5 64.25 -3.75 default 9007199254740993
示例：summon minecraft:pig overworld 0 64 0 'Byte'"Invulnerable"="1",'String'"CustomName"="MyPig" Auto
示例：summon 'String'"identifier"="minecraft:cow",'List''Float'"Pos"="0.0,64.0,0.0",'Long'"UniqueID"="12345678"
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
省略 NBT 参数默认 default，省略 UniqueID 默认 Auto。若指定 UniqueID，须先提供 NBT 或 default 占位；NULL 不代替 default。完整 NBT 写法的 Pos、Dimension 和 UniqueID 规则保持不变。
示例：summon minecraft:pig overworld 0 64 0

teleport 目标 维度 x y或Auto z
目标可以是非零 UniqueID、@s、@a、@e 或实体 identifier；维度接受当前存档的名称或 Int32 ID。x/z 接受整数或浮点数，Y 接受整数、浮点数或 Auto。实体缺少 identifier 标签时会读取 definitions[0]（例如 +minecraft:cow）。Y 输入 Auto 时，主世界和末地使用最高非空气方块上方；下界会越过最上层非空气方块与其下方空气层，优先落在更低一层非空气方块上方。回退规则为最高非空气方块上方，整列无非空气方块时使用 Y=63。玩家目标在 Y 参数为整数或 Auto 时，实际写入 Pos 的 Y 会在落脚点基础上增加 1.62；若 Y 参数以浮点数形式输入（例如 70.0），则不增加 1.62。
示例：teleport -4294967270 the_end 10.5 70.25 10
示例：teleport @a overworld -10.0 64 5
示例：teleport @a overworld 100.0 70.0 100.0
示例：teleport @a overworld 0 Auto 0
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。

tickingarea
tickingarea add square 维度 x1 z1 x2 z2 名称 [预加载0或1]
tickingarea add circle 维度 x1 z1 半径 名称 [预加载0或1]
tickingarea delete 名称或ALL
tickingarea list [维度或ALL]
圆形 add 的 x1/z1 是中心区块坐标，半径单位为区块，允许 0～4；list 逐行显示。
示例：tickingarea add square nether 0 0 1 1 Base 1
示例：tickingarea add circle overworld 0 0 4 Spawn 1
示例：tickingarea list overworld
维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。
tickingarea query [维度或ALL]
裸命令 tickingarea、list 和 query 都默认列出 ALL；query 是 list 的别名。add 省略末尾预加载开关默认 0，区域名称仍必填；delete 必须显式提供名称或大写 ALL。坐标单位保持不变：square 的 X/Z 为区块坐标，circle 的中心和半径也以区块为单位。
示例：tickingarea list
示例：tickingarea add circle overworld 0 0 1 Spawn

time
time query [daytime|gametime|day]
time add 整数
time set 非负整数
time ceil day|sunset|night|sunrise|noon|midnight
time floor day|sunset|night|sunrise|noon|midnight
day=0、noon=6000、sunset=12001、night=13801、midnight=18000、sunrise=22201；24000 等价于下一天的 0。query daytime 同时显示当前时段进度和全天进度。
示例：time query daytime
示例：time add -1000
示例：time ceil sunset
示例：time floor midnight
裸命令 time 和 time query 均默认查询 daytime，不修改时间。

weather
weather query
query 打印 rainLevel、rainTime、lightningLevel、lightningTime、doWeatherCycle；时间单位为游戏刻；doWeatherCycle 缺失时显示 1，与天气界面默认开关一致，其他缺失标签显示 NULL。
weather clear [自动变化0或1]
weather rain [持续游戏刻 [强度 [自动变化0或1]]]
weather thunder [持续游戏刻 [强度 [自动变化0或1]]]
强度必须是 0.0～1.0 的浮点数；最后一个参数控制天气是否自动变化。clear 只接受可省略的自动变化参数。
示例：weather clear 1
示例：weather thunder 12000 1.0 0
裸命令 weather 默认 query。clear 省略自动变化默认 1；rain/thunder 从右向左省略时，持续时间默认 6000 游戏刻、强度默认 1.0、自动变化默认 1。指定后项时须补齐前项；显式的 0 不使用默认值。
示例：weather rain
示例：weather thunder 12000 0.5