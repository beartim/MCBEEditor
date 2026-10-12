namespace MCBEEditor.Desktop;

internal static class CommandHelpCatalog
{
    private static readonly string[] CommandOrder =
    [
        "help",
        "info",
        "dimension",
        "clear",
        "clearspawnpoint",
        "clone",
        "chunk",
        "daylock",
        "effect",
        "entity",
        "experience",
        "fill",
        "fillbiome",
        "getblock",
        "give",
        "kill",
        "kick",
        "setblock",
        "setworldspawn",
        "spawnpoint",
        "spread",
        "storage",
        "structure",
        "summon",
        "teleport",
        "tickingarea",
        "time",
        "weather",
    ];

    private static readonly IReadOnlyDictionary<string, string> Usage = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["help"] = "help [命令]\n无参数：显示全部命令；指定已存在的命令：显示该命令的使用方法。\n示例：help\n示例：help give",
        ["info"] = "info\n无参数。输出信息栏目中的全部世界信息，每条信息单独一行。\n示例：info",
        ["dimension"] = "dimension query\ndimension add 名称 ID\ndimension empty 名称或ID\ndimension purge 名称或ID\nquery 列出存档中存在的维度名称、ID 和区块数，包含已登记的空维度。add 支持有或无 namespace 的名称及 Int32 ID；名称、ID 不得重复。缺失原版维度可用 overworld 0、nether 1、the_end 2 重建。\n示例：dimension query\n示例：dimension add wzn:bear 1000\n示例：dimension add bear 1003\n示例：dimension add nether 1\nempty 清空目标维度内容，保留维度登记；示例：dimension empty wzn:cat\n示例：dimension empty 1001\npurge 彻底删除维度及登记；受影响玩家迁到剩余主世界或最小ID维度，当前位置(0.5,65.62,0.5)，重生点(0,64,0)。无剩余维度且有玩家引用时拒绝。\n示例：dimension purge wzn:bear\n示例：dimension purge 1000",
        ["entity"] = "entity [维度 [x1 y1 z1 x2 y2 z2]]\n只读查询普通实体，不包含玩家或方块实体。无参数时显示所有维度的全部实体；只给维度时显示该维度全部实体；再给两组坐标时显示两角之间闭合长方体范围内的实体，坐标支持整数或浮点数，顺序不限，按实际 Pos 的 X/Y/Z 筛选。维度接受当前存档的名称或 Int32 ID。每个实体单独一行，格式为 实体类型=[全部 NBT 标签]，NBT 格式与 getblock 一致；实体类型解析复用实体栏目。\n示例：entity\n示例：entity overworld\n示例：entity overworld 50 60 65 100 120 150\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["clear"] = "clear 目标\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。清除所有匹配玩家与实体的物品；村民交易数据不会清除。\n示例：clear @e",
        ["clearspawnpoint"] = "clearspawnpoint 目标\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。只对匹配的玩家清除出生点。\n示例：clearspawnpoint @a",
        ["daylock"] = "daylock 0或1\n1 表示锁定时间并将 level.dat 的 dodaylightcycle 写为 0；0 表示解除锁定并写为 1。命令不修改当前 time。\n示例：daylock 1",
        ["clone"] = "clone 源维度 x1 y1 z1 x2 y2 z2 目标维度 x3 y3 z3\n维度接受当前存档的名称或 Int32 ID。复制源区域两角到目标维度的目标起点；v8 或更新的已知结构化 SubChunk 会逐方块复制所有实际存在的 storage，并把目标多余 storage 在复制位置清为空气；旧数字格式仍按 layer0 + LegacyBlockExtraData layer1 处理。涉及未加载区块时会先写入空气区块与生成完成状态；重叠区域使用命令开始时的原始源数据。\n示例：clone overworld 0 0 0 5 100 46 nether 9 50 9\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["chunk"] = "chunk query [维度 [区块X 区块Z]]\nchunk empty 维度 区块X 区块Z\nchunk regenerate 维度 区块X 区块Z\n维度接受当前存档的名称或 Int32 ID。query 无参数时按当前存档维度顺序逐行以蓝色显示全部已加载区块的信息与生成情况；只给维度时仅显示该维度；再给区块坐标时返回指定区块信息。所有 query 输出行都会追加 IsSlimeChunk=True/False 和 Ticking=True/False。empty 清空指定区块并写入最小空气区块与 FinalizedState=2；regenerate 删除指定区块记录，使游戏按世界种子重新生成。\n示例：chunk query\n示例：chunk query overworld\n示例：chunk query overworld 0 0\n示例：chunk empty nether -2 5\n示例：chunk regenerate the_end 0 0\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["effect"] = "effect give 目标 状态效果ID或ALL 持续时间 效果等级\neffect clear 目标 状态效果ID或ALL\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。状态效果 ID 必须存在于当前基岩版数据值中；ALL 必须大写。give 的持续时间接受完整 Int32（包括负数）；效果等级接受 -128～255，仍按 Bedrock Byte 原始值写入（例如 -1 与 255 都写为 0xFF）。clear 只能输入三个参数。\n示例：effect give @a strength 12000 50\n示例：effect give @a strength -1 -1\n示例：effect clear @e ALL",
        ["experience"] = "experience add 目标 整数\nexperience addlevel 目标 整数\nexperience level 目标 0到24791整数\nexperience percent 目标 0到1浮点数\nexperience query 目标\nexperience set 目标 非负整数\n目标只能匹配玩家。基岩版实际保存 PlayerLevel 与 PlayerLevelProgress，经验总数由等级曲线计算。add 按总经验增减并自动换算等级和经验条；addlevel 增减经验等级并保留当前经验条百分比；level 直接设定经验等级并把经验条进度设为 0，等级范围均为 0～24791；percent 修改当前经验条百分比；query 逐行显示 minecraft:player、UniqueID、经验总数、等级和经验条进度；set 按总经验重新计算并写入 PlayerLevel 与 PlayerLevelProgress。\n示例：experience add @a 100\n示例：experience addlevel -4294967270 -3\n示例：experience level @s 30\n示例：experience percent @s 0.5\n示例：experience query @a\n示例：experience set @s 2500",
        ["fill"] = "fill 目标维度 x1 y1 z1 x2 y2 z2 层0方块名 层0states [层1方块名 层1states ...] 方块实体\n维度接受当前存档的名称或 Int32 ID。至少提供 storage0，layer1 及之后都可省略；后续参数必须按 方块名+states 成对出现，最多 255 个 storage。states 可输入 NULL 或任意 NBT 标签。只修改命令中实际提供的 storage，省略 layer1 时保留原 layer1 及更高层。旧数字 ID SubChunk 保持原格式，仅支持可无损转换为数字 ID 的 layer0/1；无法表示的方块或 states、超过两层的请求会报错，不会自动升级或写入部分修改。\n最后的方块实体参数必填：preserve 保留原方块实体，empty 清空目标坐标的方块实体；也可传入方块实体的全部 MCBE-SNBT 标签，设定目标方块实体。允许任意 id，不要求与方块类型对应。根 x/y/z 可省略；输入的根坐标标签会自动忽略（名称不区分大小写），写入时按命令选定位置生成唯一的小写 Int 类型 x/y/z。 fill 将模板复制到闭合范围内每个坐标，每份方块实体均使用该位置的实际坐标。 嵌套坐标、Pos 和其他标签保持原样。全部检查及编码通过后一次提交方块、方块实体与区块元数据。\n示例：fill overworld 0 64 0 15 64 15 minecraft:stone NULL preserve\n示例：fill overworld 0 64 0 15 64 15 minecraft:stone NULL empty\n示例：fill the_end 0 0 0 60 200 16 minecraft:leaves 'String'\"old_leaf_type\"=\"oak\" minecraft:water NULL minecraft:air NULL empty\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["fillbiome"] = "fillbiome 维度 x1 y1 z1 x2 y2 z2 生物群系数字ID或字符串ID\n维度接受当前存档的名称或 Int32 ID。字符串 ID 必须能在内置生物群系表中找到对应数字 ID，否则报错；数字 ID 不要求存在于内置表，可输入 32 位整数原始值。Data3D 只修改两组坐标之间的 Y 范围；Data2D/Data2DLegacy 忽略 Y 坐标并修改水平选区（其格式只能保存 0～255）。\n示例：fillbiome overworld 0 -64 0 15 319 15 minecraft:plains\n示例：fillbiome nether -32 0 -32 31 127 31 178\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["give"] = "give 目标 Slot 物品 数目 物品标签\nSlot 只能是 Auto 或 0～35 的整数。目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；物品必须使用完整字符串 ID；数目必须是大于 0 的 Int64。物品标签可输入 NULL，或输入任意类型、可多重嵌套的 NBT 标签。玩家：Auto 沿用第一个空 Inventory 槽位、满时最后一格的逻辑，整数 Slot 写入对应 Inventory 槽位。非玩家实体必须已经存在可写入的 Mainhand 标签，否则直接跳过；命令任何时候都不会创建 Mainhand。实体 Auto 写入已有 Mainhand；整数 Slot 在有 ChestItems 时写入对应槽位，超过槽位数时写入最后槽位并同步写入已有 Mainhand；没有 ChestItems 时只写入已有 Mainhand。\n示例：give @s Auto minecraft:stone 64 NULL\n示例：give @a 5 minecraft:diamond 3 NULL\n示例：give minecraft:cow 2 minecraft:lit_smoker 99 'Compound'\"tag\"=\"{'Byte'\"Unbreakable\"=\"1\"}\",'Short'\"Damage\"=\"1\"",
        ["kill"] = "kill 目标 是否杀死创造模式玩家\n目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；第二个参数只能是 0 或 1。非玩家实体直接删除，玩家生命值 Current 设为 0.0；创造模式玩家在参数为 0 时保持不变。\n示例：kill @a 1",
        ["kick"] = "kick 目标\n目标只能是在线玩家的非零 UniqueID或 @a。UniqueID 删除对应在线玩家数据，@a 删除全部在线玩家数据。\n示例：kick @a\n示例：kick -4294967270",
        ["setblock"] = "setblock 目标维度 x y z 层0方块名 层0states [层1方块名 层1states ...] 方块实体\nfill 的单方块版本。至少提供 storage0，layer1 及之后均可省略；最多 255 个 storage。省略的 storage 保持原样。\n最后的方块实体参数必填：preserve 保留原方块实体，empty 清空目标坐标的方块实体；也可传入方块实体的全部 MCBE-SNBT 标签，设定目标方块实体。允许任意 id，不要求与方块类型对应。根 x/y/z 可省略；输入的根坐标标签会自动忽略（名称不区分大小写），写入时按命令选定位置生成唯一的小写 Int 类型 x/y/z。 嵌套坐标、Pos 和其他标签保持原样。全部检查及编码通过后一次提交方块、方块实体与区块元数据。\n示例：setblock overworld 0 64 0 minecraft:stone NULL preserve\n示例：setblock overworld 0 64 0 minecraft:stone NULL empty\n示例：setblock overworld 0 64 0 minecraft:stone NULL minecraft:water NULL empty\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["getblock"] = "getblock 维度 x y z\n返回指定方块位置所有存在的 storage 方块状态以及该坐标的方块实体 NBT。Block 行使用蓝色，BlockEntity 行使用紫色；没有方块实体时显示 BlockEntity=NULL。\n示例：getblock overworld -24 64 0\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["storage"] = "storage query 维度 x y z\nstorage set 维度 x y z 层数 方块名 states\nstorage delete 维度 x y z 层数\nstorage clear 维度 x y z 保留到的层数\n直接操作指定坐标所在 v8 或更新的已知结构化 SubChunk 的物理 storage。query 逐行用蓝色显示所有 storage 在该坐标的方块状态；set 可设置 layer 0～254，并按需要创建中间空气 storage，最多 255 层；delete 删除整个指定 storage（该 SubChunk 内 4096 个位置都会受影响）并在安全时裁掉后续全空气 storage；clear 参数为 UInt8，0 仅保留 storage0，1 保留 storage0/1，其余类推，255 表示不主动裁剪。\n示例：storage query overworld 0 64 0\n示例：storage set overworld 0 64 0 8 minecraft:water NULL\n示例：storage delete overworld 0 64 0 8\n示例：storage clear overworld 0 64 0 1\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["setworldspawn"] = "setworldspawn x y z\n设置世界重生点；坐标必须恰好输入三个整数。世界重生点位于主世界。\n示例：setworldspawn 0 80 0",
        ["spawnpoint"] = "spawnpoint 目标 维度 x y z\n目标必须是非零 UniqueID、@s、@a、@e 或 minecraft:player，且最终只能匹配玩家；维度接受当前存档的名称或 Int32 ID。\n示例：spawnpoint @a the_end 0 100 0\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["spread"] = "spread 目标\n目标可以是非零 UniqueID、@s、@a、@e 或实体 identifier。每个匹配对象会独立随机选择一个有已加载区块的维度、一个已加载区块及其中一列非全空气的 X/Z，再按 teleport Auto 逻辑传送。输出格式为 identifier UniqueID 维度 X Y Z，并优先显示玩家。\n示例：spread @e\n示例：spread minecraft:cow",
        ["structure"] = "structure query\nstructure import [名称]\nstructure export mcstructure|nbt|json|txt [名称]\nquery 每行显示一个结构；import 打开文件选择器，export 打开保存窗口；省略名称时通过窗口选择或输入；nbt 为 Big Endian，mcstructure 为 Little Endian；txt 为保留 NBT 类型与根标签的 MCBE-SNBT。\nstructure save 名称 维度 x1 y1 z1 x2 y2 z2\nstructure load 名称 维度 x y z\nstructure delete 名称或ALL\nsave/load/delete 的名称必须为 namespace:name。save 会直接覆盖同名 structuretemplate_ 记录；load/delete 找不到名称时失败。\n示例：structure save mystructure:1 overworld 0 0 0 50 50 50\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["summon"] = "summon 实体类型 实体维度 x y z NBT标签或default [UniqueID]\nsummon 实体NBT标签\n实体维度接受当前存档的名称或 Int32 ID；x/y/z 均接受整数或浮点数并直接写入 Pos。第一种格式的 NBT 参数输入 default 时使用实体通用 NBT，否则接受任意类型、可多重嵌套的非空附加标签，不能为 NULL，也不能覆盖命令控制的身份、坐标、维度标签。\n末尾 UniqueID 接受 Auto 或非零 Long 整数（-9223372036854775808～9223372036854775807）；省略时按 Auto 处理。Auto 自动生成未占用 ID，手动 ID 与已有实体或要使用的 actor 存储引用冲突时拒绝创建。\n第二种格式直接保留提供的 NBT 标签、类型和顺序，必须包含恰好三个可写入 Float 的有限数值组成的 Pos 或 Position List；UniqueID 若提供必须为非零 Long，缺少时自动生成。DimensionId 或 Dimension 必须为 Int32 范围内的整数标签，缺少时写入主世界且不补写维度标签。\n示例：summon minecraft:pig overworld 0 64 0 default Auto\n示例：summon minecraft:pig overworld 10.5 64.25 -3.75 default 9007199254740993\n示例：summon minecraft:pig overworld 0 64 0 'Byte'\"Invulnerable\"=\"1\",'String'\"CustomName\"=\"MyPig\" Auto\n示例：summon 'String'\"identifier\"=\"minecraft:cow\",'List''Float'\"Pos\"=\"0.0,64.0,0.0\",'Long'\"UniqueID\"=\"12345678\"\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["teleport"] = "teleport 目标 维度 x y或Auto z\n目标可以是非零 UniqueID、@s、@a、@e 或实体 identifier；维度接受当前存档的名称或 Int32 ID。x/z 接受整数或浮点数，Y 接受整数、浮点数或 Auto。实体缺少 identifier 标签时会读取 definitions[0]（例如 +minecraft:cow）。Y 输入 Auto 时，主世界和末地使用最高非空气方块上方；下界会越过最上层非空气方块与其下方空气层，优先落在更低一层非空气方块上方。回退规则为最高非空气方块上方，整列无非空气方块时使用 Y=63。玩家目标在 Y 参数为整数或 Auto 时，实际写入 Pos 的 Y 会在落脚点基础上增加 1.62；若 Y 参数以浮点数形式输入（例如 70.0），则不增加 1.62。\n示例：teleport -4294967270 the_end 10.5 70.25 10\n示例：teleport @a overworld -10.0 64 5\n示例：teleport @a overworld 100.0 70.0 100.0\n示例：teleport @a overworld 0 Auto 0\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["tickingarea"] = "tickingarea add square 维度 x1 z1 x2 z2 名称 0或1\ntickingarea add circle 维度 x1 z1 半径 名称 0或1\ntickingarea delete 名称或ALL\ntickingarea list 维度或ALL\n圆形 add 的 x1/z1 是中心区块坐标，半径单位为区块，允许 0～4；list 逐行显示。\n示例：tickingarea add square nether 0 0 1 1 Base 1\n示例：tickingarea add circle overworld 0 0 4 Spawn 1\n示例：tickingarea list overworld\n维度参数接受当前存档登记名称（含或不含 namespace）或有符号 Int32 ID；原版名称为 overworld、nether、the_end，也接受 minecraft: 别名。",
        ["time"] = "time query daytime|gametime|day\ntime add 整数\ntime set 非负整数\ntime ceil day|sunset|night|sunrise|noon|midnight\ntime floor day|sunset|night|sunrise|noon|midnight\nday=0、noon=6000、sunset=12001、night=13801、midnight=18000、sunrise=22201；24000 等价于下一天的 0。query daytime 同时显示当前时段进度和全天进度。\n示例：time query daytime\n示例：time add -1000\n示例：time ceil sunset\n示例：time floor midnight",
        ["weather"] = "weather query\nquery 打印 rainLevel、rainTime、lightningLevel、lightningTime、doWeatherCycle；时间单位为游戏刻；doWeatherCycle 缺失时显示 1，与天气界面默认开关一致，其他缺失标签显示 NULL。\nweather clear 0或1\nweather rain 持续游戏刻 强度 0或1\nweather thunder 持续游戏刻 强度 0或1\n强度必须是 0.0～1.0 的浮点数；最后一个参数控制天气是否自动变化。clear 只接受自动变化参数。\n示例：weather clear 1\n示例：weather thunder 12000 1.0 0",
    };

    public static IReadOnlyList<string> Names => Array.AsReadOnly(CommandOrder);

    public static string AllUsageText => string.Join("\n\n", CommandOrder.Select(command => Usage[command]));

    public static bool IsKnownCommand(string command)
        => Usage.ContainsKey(command);

    public static bool TryGetUsage(string command, out string usage)
        => Usage.TryGetValue(command, out usage!);
}
