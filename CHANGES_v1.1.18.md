# Blocktopograph iOS 13 v1.1.18（128）

## effect 命令

命令栏目新增严格格式的状态效果命令：

```text
effect give 目标 状态效果ID或ALL 持续时间 效果等级
effect clear 目标 状态效果ID或ALL
```

示例：

```text
effect give @a strength 12000 50
effect clear @e ALL
```

- `give` 必须恰好输入 5 个参数；`clear` 必须恰好输入 3 个参数，多一个或少一个都会拒绝执行。
- 目标沿用 `@s`、`@a`、`@e`、非零 UniqueID 和实体 identifier。
- 状态效果字符串 ID 必须存在于“基岩版数据值 → 状态效果 ID”表并具有数字 ID，否则整个命令在写入前报错。
- `ALL` 必须大写；与 `give` 组合时为每个当前数据值中的状态效果建立 Compound，与 `clear` 组合时删除整个 `ActiveEffects` 标签。
- 持续时间必须是 `0…2147483647` 的整数，并同时写入 `Duration`、`DurationEasy`、`DurationNormal` 和 `DurationHard`。
- 效果等级输入范围为 `0…255`，按基岩版零基数 Amplifier 保存；例如输入 50 表示 51 级效果。

## ActiveEffects NBT

新增状态效果 Compound 采用：

- `Ambient: Byte = 0`
- `Amplifier: Byte = 命令等级`
- `DisplayOnScreenTextureAnimation: Byte = 0`
- `Duration: Int = 命令持续时间`
- `DurationEasy: Int = 命令持续时间`
- `DurationNormal: Int = 命令持续时间`
- `DurationHard: Int = 命令持续时间`
- `Id: Byte = 状态效果数字 ID`
- `ShowParticles: Byte = 0`

不会创建 `FactorCalculationData`。

给予单个效果时会替换同数字 ID 的旧 Compound；给予 `ALL` 时会创建或更新当前数据表中的全部效果。移除单个效果时只删除匹配数字 ID 的 Compound；删除后列表为空则同时删除根 `ActiveEffects` 标签。没有对应效果或没有根标签时跳过该目标，不作为命令错误。

## 批量写入安全性

- 在任何 LevelDB 写入前，先解析并验证全部目标的 `ActiveEffects` 结构；任一目标数据格式错误时不会先修改其他目标。
- 多个旧版实体共用同一条区块 `Entity(0x32)` 连续 NBT 时，只解码和重写该记录一次。
- 玩家记录、旧版区块实体和现代 `actorprefix` 的修改合并到同一个 LevelDB WriteBatch 中提交，避免选择器执行产生部分结果或扫描索引失效。

## 测试

- 增加 `effect give`、`effect clear`、`ALL`、未知 ID、参数数量、持续时间和等级边界解析测试。
- 验证四个 Duration、Amplifier、Id、显示标志及不含 `FactorCalculationData`。
- 使用一个本地玩家和两个共用连续 Entity 记录的实体执行实际命令，验证原子给予、移除、无效果跳过和 `ALL` 全量创建。
- Swift 命令执行器与相关存档模块通过 Linux 可执行类型检查和专项回归。
