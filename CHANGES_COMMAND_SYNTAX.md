# 命令语法统一（2026-10-29）

已检查并统一全部 28 条命令在 Swift/C#、GUI/CLI 中的必填参数、可省略参数与默认值。原完整格式保留，版本仍为 1.0.0，最低 iOS 13。

完整格式、每个子命令及说明见 [COMMAND_SYNTAX.md](COMMAND_SYNTAX.md)，验证与平台边界见 [验证记录](Docs/CommandSyntax/VALIDATION.md)。

- give 槽位默认 Auto、数量默认 1、标签默认 NULL；effect give 默认 600 游戏刻和原始等级 0，clear 省略效果默认 ALL，支持 minecraft: 效果前缀。
- fill/setblock 每层 states 默认 NULL，末尾方块实体默认 preserve；多层状态与模板有明确 NBT 占位规则。storage set 可省略 states。
- summon 可省略 NBT 为 default，UniqueID 默认 Auto；指定 ID 时仍需 NBT/default 占位。
- kill 目标或完整范围后的开关可省略为 0，只跳过创造模式玩家；其他选中玩家清零、非玩家删除。
- dimension、chunk、structure、time、weather 裸命令为只读查询；time query 默认 daytime。tickingarea 裸命令/list/query 默认 ALL，query 为 list 别名。
- weather clear 自动变化默认 1；rain/thunder 默认 6000 游戏刻、强度 1.0、自动变化 1。tickingarea add 的预加载默认 0，名称必填。
- Auto/NULL/default/preserve/empty 大小写统一，ALL 继续大写；目标、维度、坐标和 storage 层号继续显式填写。四份固定命令说明已同步。

保留上一轮 kill 范围及 actor 修复、Drop 4 ID 与颜色同步。原执行器和存档转换未改变。
