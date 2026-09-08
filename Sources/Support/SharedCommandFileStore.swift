import Foundation

struct SharedCommandFileLine {
    let lineNumber: Int
    let text: String
}

/// Maintains the user-visible Documents/Commands directory used for optional
/// command batches. ReadMe.txt is fixed text embedded in the app and is reset
/// verbatim whenever the app starts. Command.txt is never created, overwritten
/// or deleted by MCBEEditor.
enum SharedCommandFileStore {
    private static let directoryName = "Commands"
    private static let commandFilename = "Command.txt"
    private static let readMeFilename = "ReadMe.txt"

    static var commandsDirectoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var commandFileURL: URL? {
        commandsDirectoryURL?.appendingPathComponent(commandFilename, isDirectory: false)
    }

    static var commandFileExists: Bool {
        guard let url = commandFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Called at startup. The folder is always created and the fixed ReadMe is
    /// atomically rewritten every launch so local edits never persist.
    static func prepareSharedDirectory() {
        guard let directory = commandsDirectoryURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let readMeURL = directory.appendingPathComponent(readMeFilename, isDirectory: false)
            try Data(readMeText.utf8).write(to: readMeURL, options: .atomic)
        } catch {
            // File sharing support is optional. A directory preparation failure
            // must never prevent the app itself from launching.
        }
    }

    /// Reads non-empty lines while preserving the original 1-based line number
    /// so syntax errors can point to the exact Command.txt row. Whitespace-only
    /// lines are ignored; command text is otherwise passed through unchanged to
    /// WorldCommandParser.
    static func readCommandLines() throws -> [SharedCommandFileLine] {
        guard let url = commandFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCBEEditorError.malformedData("Commands/Command.txt 必须使用 UTF-8 文本格式")
        }

        return text.components(separatedBy: .newlines).enumerated().compactMap { offset, raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return SharedCommandFileLine(lineNumber: offset + 1, text: trimmed)
        }
    }

    private static let readMeText = """
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

info
无参数。输出信息栏目中的全部世界信息，每条信息单独一行。
示例：info

clear 目标
目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。清除所有匹配玩家与实体的物品；村民交易数据不会清除。
示例：clear @e

clearspawnpoint 目标
目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。只对匹配的玩家清除出生点。
示例：clearspawnpoint @a

clone 源维度 x1 y1 z1 x2 y2 z2 目标维度 x3 y3 z3
维度必须为 overworld、nether 或 the_end。复制源区域两角到目标维度的目标起点；v8 或更新的已知结构化 SubChunk 会逐方块复制所有实际存在的 storage，并把目标多余 storage 在复制位置清为空气；旧数字格式仍按 layer0 + LegacyBlockExtraData layer1 处理。涉及未加载区块时会先写入空气区块与生成完成状态；重叠区域使用命令开始时的原始源数据。
示例：clone overworld 0 0 0 5 100 46 nether 9 50 9

chunk query [维度 [区块X 区块Z]]
chunk empty 维度 区块X 区块Z
chunk regenerate 维度 区块X 区块Z
维度必须为 overworld、nether 或 the_end。query 无参数时按 overworld、nether、the_end 顺序逐行以蓝色显示全部已加载区块的信息与生成情况；只给维度时仅显示该维度；再给区块坐标时返回指定区块信息与生成情况。empty 清空指定区块并写入最小空气区块与 FinalizedState=2；regenerate 删除指定区块记录，使游戏按世界种子重新生成。
示例：chunk query
示例：chunk query overworld
示例：chunk query overworld 0 0
示例：chunk empty nether -2 5
示例：chunk regenerate the_end 0 0

daylock 0或1
1 表示锁定时间并将 level.dat 的 dodaylightcycle 写为 0；0 表示解除锁定并写为 1。命令不修改当前 time。
示例：daylock 1

effect give 目标 状态效果ID或ALL 持续时间 效果等级
effect clear 目标 状态效果ID或ALL
目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier。状态效果 ID 必须存在于当前基岩版数据值中；ALL 必须大写。give 的持续时间接受完整 Int32（包括负数）；效果等级接受 -128～255，仍按 Bedrock Byte 原始值写入（例如 -1 与 255 都写为 0xFF）。clear 只能输入三个参数。
示例：effect give @a strength 12000 50
示例：effect give @a strength -1 -1
示例：effect clear @e ALL

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

fill 目标维度 x1 y1 z1 x2 y2 z2 层0方块名 层0states [层1方块名 层1states ...]
维度必须为 overworld、nether 或 the_end。至少提供 storage0，layer1 及之后都可省略；后续参数必须按 方块名+states 成对出现，最多 255 个 storage。states 可输入 NULL 或任意 NBT 标签。只修改命令中实际提供的 storage，省略 layer1 时保留原 layer1 及更高层。旧数字 ID SubChunk 仅能原地表示 layer0/1 的数字 ID；使用更多 storage 或现代 states 时自动升级为现代 SubChunk。
示例：fill overworld 0 64 0 15 64 15 minecraft:stone NULL
示例：fill the_end 0 0 0 60 200 16 minecraft:leaves 'String'"old_leaf_type"="oak" minecraft:water NULL minecraft:air NULL

fillbiome 维度 x1 y1 z1 x2 y2 z2 生物群系数字ID或字符串ID
维度必须为 overworld、nether 或 the_end。字符串 ID 必须能在内置生物群系表中找到对应数字 ID，否则报错；数字 ID 不要求存在于内置表，可输入 32 位整数原始值。Data3D 只修改两组坐标之间的 Y 范围；Data2D/Data2DLegacy 忽略 Y 坐标并修改水平选区（其格式只能保存 0～255）。
示例：fillbiome overworld 0 -64 0 15 319 15 minecraft:plains
示例：fillbiome nether -32 0 -32 31 127 31 178

getblock 维度 x y z
返回指定方块位置所有存在的 storage 方块状态以及该坐标的方块实体 NBT。Block 行使用蓝色，BlockEntity 行使用紫色；没有方块实体时显示 BlockEntity=NULL。
示例：getblock overworld -24 64 0

give 目标 Slot 物品 数目 物品标签
Slot 只能是 Auto 或 0～35 的整数。目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；物品必须使用完整字符串 ID；数目必须是大于 0 的 Int64。物品标签可输入 NULL，或输入任意类型、可多重嵌套的 NBT 标签。玩家：Auto 沿用第一个空 Inventory 槽位、满时最后一格的逻辑，整数 Slot 写入对应 Inventory 槽位。非玩家实体必须已经存在可写入的 Mainhand 标签，否则直接跳过；命令任何时候都不会创建 Mainhand。实体 Auto 写入已有 Mainhand；整数 Slot 在有 ChestItems 时写入对应槽位，超过槽位数时写入最后槽位并同步写入已有 Mainhand；没有 ChestItems 时只写入已有 Mainhand。
示例：give @s Auto minecraft:stone 64 NULL
示例：give @a 5 minecraft:diamond 3 NULL
示例：give minecraft:cow 2 minecraft:lit_smoker 99 'Compound'"tag"="{'Byte'"Unbreakable"="1"}",'Short'"Damage"="1"

kill 目标 是否杀死创造模式玩家
目标必须是非零 UniqueID、@s、@a、@e 或实体 identifier；第二个参数只能是 0 或 1。非玩家实体直接删除，玩家生命值 Current 设为 0.0；创造模式玩家在参数为 0 时保持不变。
示例：kill @a 1

kick 目标
目标只能是在线玩家的非零 UniqueID或 @a。UniqueID 删除对应在线玩家数据，@a 删除全部在线玩家数据。
示例：kick @a
示例：kick -4294967270

setblock 目标维度 x y z 层0方块名 层0states [层1方块名 层1states ...]
fill 的单方块版本。至少提供 storage0，layer1 及之后均可省略；最多 255 个 storage。省略的 storage 保持原样。
示例：setblock overworld 0 64 0 minecraft:stone NULL
示例：setblock overworld 0 64 0 minecraft:stone NULL minecraft:water NULL

setworldspawn x y z
设置世界重生点；坐标必须恰好输入三个整数。世界重生点位于主世界。
示例：setworldspawn 0 80 0

spawnpoint 目标 维度 x y z
目标必须是非零 UniqueID、@s、@a、@e 或 minecraft:player，且最终只能匹配玩家；维度必须为 overworld、nether 或 the_end。
示例：spawnpoint @a the_end 0 100 0

spread 目标
目标可以是非零 UniqueID、@s、@a、@e 或实体 identifier。每个匹配对象会独立随机选择一个有已加载区块的维度、一个已加载区块及其中一列非全空气的 X/Z，再按 teleport Auto 逻辑传送。输出格式为 identifier UniqueID 维度 X Y Z，并优先显示玩家。
示例：spread @e
示例：spread minecraft:cow

storage query 维度 x y z
storage set 维度 x y z 层数 方块名 states
storage delete 维度 x y z 层数
storage clear 维度 x y z 保留到的层数
直接操作指定坐标所在 v8 或更新的已知结构化 SubChunk 的物理 storage。query 逐行用蓝色显示所有 storage 在该坐标的方块状态；set 可设置 layer 0～254，并按需要创建中间空气 storage，最多 255 层；delete 删除整个指定 storage（该 SubChunk 内 4096 个位置都会受影响）并在安全时裁掉后续全空气 storage；clear 参数为 UInt8，0 仅保留 storage0，1 保留 storage0/1，其余类推，255 表示不主动裁剪。
示例：storage query overworld 0 64 0
示例：storage set overworld 0 64 0 8 minecraft:water NULL
示例：storage delete overworld 0 64 0 8
示例：storage clear overworld 0 64 0 1

structure save 名称 维度 x1 y1 z1 x2 y2 z2
structure load 名称 维度 x y z
structure delete 名称或ALL
名称必须为 namespace:name。save 会直接覆盖同名 structuretemplate_ 记录；load/delete 找不到名称时失败。
示例：structure save mystructure:1 overworld 0 0 0 50 50 50

summon 实体类型 实体维度 x y z NBT标签或default
实体维度必须为 overworld、nether 或 the_end；x/y/z 均接受整数或浮点数并直接写入 Pos。最后一个参数输入 default 时不额外覆盖实体通用 NBT，否则可输入任意类型、可多重嵌套的非空 NBT 标签，且不能为 NULL。
示例：summon minecraft:pig overworld 0 64 0 default
示例：summon minecraft:pig overworld 10.5 64.25 -3.75 default
示例：summon minecraft:pig overworld 0 64 0 'Byte'"Invulnerable"="1",'String'"CustomName"="MyPig"

teleport 目标 维度 x y或Auto z
目标可以是非零 UniqueID、@s、@a、@e 或实体 identifier；维度必须为 overworld、nether 或 the_end。x/z 接受整数或浮点数，Y 接受整数、浮点数或 Auto。实体缺少 identifier 标签时会读取 definitions[0]（例如 +minecraft:cow）。Y 输入 Auto 时，主世界和末地使用最高非空气方块上方；下界会越过最上层非空气方块与其下方空气层，优先落在更低一层非空气方块上方。回退规则为最高非空气方块上方，整列无非空气方块时使用 Y=63。玩家目标在 Y 参数为整数或 Auto 时，实际写入 Pos 的 Y 会在落脚点基础上增加 1.62；若 Y 参数以浮点数形式输入（例如 70.0），则不增加 1.62。
示例：teleport -4294967270 the_end 10.5 70.25 10
示例：teleport @a overworld -10.0 64 5
示例：teleport @a overworld 100.0 70.0 100.0
示例：teleport @a overworld 0 Auto 0

tickingarea add square 维度 x1 z1 x2 z2 名称 0或1
tickingarea add circle 维度 x1 z1 半径 名称 0或1
tickingarea delete 名称或ALL
tickingarea list 维度或ALL
圆形 add 的 x1/z1 是中心区块坐标，半径单位为区块，允许 0～4；list 逐行显示。
示例：tickingarea add square nether 0 0 1 1 Base 1
示例：tickingarea add circle overworld 0 0 4 Spawn 1
示例：tickingarea list overworld

time query daytime|gametime|day
time add 整数
time set 非负整数
time ceil day|sunset|night|sunrise|noon|midnight
time floor day|sunset|night|sunrise|noon|midnight
day=0、noon=6000、sunset=12001、night=13801、midnight=18000、sunrise=22201；24000 等价于下一天的 0。query daytime 同时显示当前时段进度和全天进度。
示例：time query daytime
示例：time add -1000
示例：time ceil sunset
示例：time floor midnight

weather clear 0或1
weather rain 持续游戏刻 强度 0或1
weather thunder 持续游戏刻 强度 0或1
强度必须是 0.0～1.0 的浮点数；最后一个参数控制天气是否自动变化。clear 只接受自动变化参数。
示例：weather clear 1
示例：weather thunder 12000 1.0 0

注意：本 ReadMe.txt 是当前版本内置的固定文本，并会在 MCBEEditor 每次启动时重置为默认内容。
"""
}
