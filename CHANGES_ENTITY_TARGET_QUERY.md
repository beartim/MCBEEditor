# entity 目标查询与玩家支持（2026-10-29）

版本保持 1.0.0，iOS 最低 13.0。Swift/C# 及 GUI/CLI 同步。

- entity 与 entity @e 完全等价，查询所有维度玩家与普通实体，排除方块实体。
- 新增非零有符号 Int64 UniqueID、@s、@a、@e、完整实体 identifier；支持再接维度和完整六坐标范围。
- 单个数字表示 UniqueID；数字维度写在目标之后，例如 entity @e 0。自定义 namespaced 维度也可显式写在目标后。
- 每条结果显示判断的类型、维度名称及 ID、实际坐标和全部无损 MCBE-SNBT。无 Pos 的记录显示 NULL，无范围时保留，有范围时排除。
- 保留独立存储记录中相同 UniqueID 的所有结果；短玩家键的重复扫描视图按存储键合并。
- 使用 MCBE-SNBT 文件编解码器，保持全部数值精度、嵌套类型与 NaN 位；不补写 NBT 标签、不改变存档。

完整参数和例子见 [COMMAND_SYNTAX.md](COMMAND_SYNTAX.md)，测试结果与限制见 [验证记录](Docs/EntityTargetQuery/VALIDATION.md)。
