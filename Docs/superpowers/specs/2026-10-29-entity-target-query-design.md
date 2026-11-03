# entity 目标查询与玩家支持

用户要求：查询选中范围内所有实体，包含玩家、排除方块实体；支持 UniqueID、@s、@a、@e 与实体 identifier；entity 默认为 @e；逐条展示判断出的实体类型、维度、实际坐标、全部 MCBE-SNBT 标签。

采用扩展原只读查询类型，直接合并现有玩家存储读取与普通实体扫描结果。复用实体浏览器的类型判断和 MCBE-SNBT 文件编解码器的命名标签格式化，避免旧 getblock 显示格式的精度/嵌套列表损失。不会借用写命令的目标解析执行器，因为它按 UniqueID 去重、无匹配时报错，会丢失查询应保留的独立记录与扫描提示。

语法：

```text
entity [目标]
entity 维度 [x1 y1 z1 x2 y2 z2]
entity 目标 维度 [x1 y1 z1 x2 y2 z2]
```

- 默认目标 @e 包含全部维度的玩家与普通实体，排除方块实体。
- @s 是本机玩家记录；@a 是全部玩家记录；UniqueID 为非零有符号 Int64，匹配玩家与实体；identifier 为完整 namespace:name，minecraft:player 匹配玩家。保留不同存储记录中重复 UniqueID 的所有结果。短玩家存储键若同时被扫描器当作二进制 Entity 键，仅合并同一存储键的重复视图。
- 单独数字优先 UniqueID，不再表示维度。数字维度可使用 entity @e 0 或原完整七参数范围写法。
- 单个普通名称仍按维度解析；原版 minecraft:overworld/nether/the_end 别名保留。其他单个 namespaced identifier 按实体类型解析，自定义 namespaced 维度可显式写 entity @e custom:moon，消除歧义。
- 仅接受 0/1/2/7/8 个参数。六个范围坐标整体输入，闭合范围、反向角点、有限小数与原限制保持一致。
- 玩家根据 PlayerNBTStore 当前位置与维度字段读取，不做 teleport 眼高补偿。无有效位置的对象仍可按目标/维度查询并显示 Pos=NULL，但不进入坐标范围结果。

每个匹配记录单独一行，格式：

```text
minecraft:pig Dimension=overworld(0) Pos=(0,64,0) NBT=[全部命名MCBE-SNBT标签]
```

维度显示名称和数字 ID；名称不可读时保留 ID 并输出提示。玩家的判断类型固定为 minecraft:player，显示类型不写回原 NBT。坐标使用区域无关、17 位有效数字格式，不舍弃原始 Double 精度。不存在的 UniqueID/选择器返回无匹配结果，不写入任何数据。原有实体损坏记录提示、无结果提示、逐行颜色和无限结果数保留。

版本保持 1.0.0、最低 iOS 13。同步 Swift/C#、GUI/CLI 路由、帮助、固定说明、全命令对照和测试。保留上一轮语法、ID、颜色和 kill 行为。

验证：目标组合与范围、玩家本机/在线、负数及超 2^53 ID、重复 ID、实际 NBT 维度优先、无 Pos、方块实体排除、完整 NBT 往返、只读世界字节不变、无匹配与坏记录提示、超过 200000 个结果、CLI 只读策略及固定 ReadMe。
