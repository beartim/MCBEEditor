# fill / setblock 方块实体参数

iOS GUI、Apple/iOS CLI、Windows GUI 和 Windows CLI 同步修改，版本保持 1.0.0、iOS 最低版本保持 13.0。既有未指定类型的空 List 修复保留。

```text
setblock 维度 x y z 方块名 states [方块名 states ...] 方块实体
fill 维度 x1 y1 z1 x2 y2 z2 方块名 states [方块名 states ...] 方块实体
```

最后一个参数现在必填，旧脚本必须补上相应参数：

| 参数 | 行为 |
| --- | --- |
| `preserve` | 原样保留目标原方块实体；不解析或改写其 NBT，损坏的原记录也保持不变。 |
| `empty` | 删除目标位置全部可精确定位的方块实体，包括重复位置的记录；没有剩余记录时删除对应 BlockEntity 数据库键。 |
| 完整 MCBE-SNBT 标签列表 | 删除目标旧实体，然后逐位置写入一份给定模板。允许任意 id，不检查与方块类型的对应关系；自动补齐实际根坐标，不补充其他默认标签。 |

NBT 根 x/y/z 可以全部或部分省略。输入的根坐标标签会自动忽略，名称不区分大小写；数值不一致、非整数类型、x/X 等大小写别名均不影响目标位置。写入时删除输入根坐标，末尾添加唯一的小写 Int 类型 x/y/z，以命令选定位置为准。fill 可反向输入两角，闭合范围内每个位置分别写入其实际坐标；输入的 Byte/Short 等坐标类型不限制填充范围。其他标签（包括嵌套坐标、DimensionId、Pos）的相对顺序、值和类型保持不变。MCBE-SNBT 仍需语法正确；同一 Compound 内的同名重复标签等无效输入仍会拒绝。

```text
setblock overworld 0 64 0 minecraft:stone NULL minecraft:water NULL 'Byte'"Findable"="0",'List'''"Items"="",'String'"id"="Chest",'Byte'"isMovable"="1"
fill overworld 16 65 0 -1 64 -1 minecraft:stone NULL 'String'"id"="wzn:any_entity",'List'''"Items"=""
setblock overworld 0 64 0 minecraft:dirt NULL preserve
fill overworld 16 65 0 -1 64 -1 minecraft:stone NULL empty
```

完整可执行文件见 [FillSetblockBlockEntity.txt](../../CLI/Examples/FillSetblockBlockEntity.txt)。CLI 中含引号的命令建议写入 UTF-8 文件后通过 `--script` 执行，修改时照常指定 `--output` 或 `--in-place`。

原有 1…255 个 storage 和省略高层保留逻辑不变。NBT 解析、目标坐标检查、目标数据解析和最终编码全部在提交前完成，地形、缺失区块元数据和方块实体统一提交一次 WriteBatch。重复执行已经满足的 preserve/empty 命令会成功返回，不改动存档或标记未保存变化。失败不会留下部分写入；preserve 保留全部原实体字节，empty/模板仅移除具有唯一、整数、Int32 范围根坐标的目标记录，无关或无法安全定位的记录保留。普通 little-endian 实体的原字节与顺序保留；追加到旧单根 VarInt 实体记录时，把保留记录编码为 Bedrock 的 little-endian 流，保持原标签、根名称和顺序。

帮助、命令清单、四套固定 Commands/ReadMe.txt 及其生产常量均已同步。ReadMe 仍为内置静态文本，运行时不从 help 现生成；两份 Textures/ReadMe.txt 保持原字节。Windows 地图框选生成的 fill 命令显式追加 `empty`，自定义维度按原 Int32 ID 生成命令。两端既有测试及示例也补齐末尾参数。

当前自动坐标规则的验证命令、结果和平台限制见 [最新验证](../BlockEntityAutoCoordinates/VALIDATION.md)；必填参数引入时的历史记录见 [VALIDATION.md](VALIDATION.md)。
