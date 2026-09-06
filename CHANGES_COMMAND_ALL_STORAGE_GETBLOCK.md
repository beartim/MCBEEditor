# 命令层全 storage / getblock / storage / 负数 effect

本轮只扩展命令系统。地图、方块 NBT 编辑器、框选/区域等既有 UI 仍保持只支持 layer0 与 layer1。

## clone

- 对 v8 或更新的已知结构化 SubChunk，按源和目标实际 storage 数量逐坐标处理，不再固定 layer0/layer1。
- 源 storage2+ 会正常复制到目标；目标比源更多的 storage 在被复制坐标处会写为空气。
- 如果某个尾部 storage 在整个 SubChunk 中最终全为空气，允许安全裁掉；不会删除仍含非空气方块的高层。
- 重叠 clone 继续使用命令开始时冻结的源/目标 SubChunk 快照，避免连锁覆盖。
- 旧 numeric v0/v2-v7 仍按 layer0 + LegacyBlockExtraData layer1；遇到 storage2+ 或现代 states 时目标区块自动 modernize。

## setblock / fill

格式：

```text
setblock 维度 x y z storage0名称 storage0states [storage1名称 storage1states ...]
fill 维度 x1 y1 z1 x2 y2 z2 storage0名称 storage0states [storage1名称 storage1states ...]
```

- storage0 必填；layer1 及以上全部可省略。
- states 可为 `NULL`。
- 每个额外 storage 必须按“方块名 + states”成对提供。
- storage 数量使用 UInt8 持久化上限：1～255；第 256 个 storage 拒绝解析。
- 命令只修改实际提供的 storage；省略的高层 storage 保持原值。
- 旧 numeric SubChunk 若所有请求都可由 layer0/layer1 数字 ID 表示，则保留旧格式；否则升级为现代格式后写入。

## getblock

格式：

```text
getblock 维度 x y z
```

返回两行：

```text
Block=[Storage0=[...],Storage1=[...]...]
BlockEntity=[...]
```

- `Block` 行显示该位置所有实际 storage 的完整 block-state NBT（name/states/version 等），终端显示为蓝色。
- `BlockEntity` 行显示该坐标完整方块实体根 Compound，终端显示为紫色。
- 无方块实体时返回 `BlockEntity=NULL`。
- List/Compound/ByteArray/IntArray/LongArray 等嵌套 NBT 使用命令 NBT 文本格式展开。

## storage

仅存在四个子命令：`query`、`set`、`delete`、`clear`。**不兼容 `storage add`。**

```text
storage query 维度 x y z
storage set 维度 x y z 层数 方块名 states
storage delete 维度 x y z 层数
storage clear 维度 x y z 保留到的层数
```

- `query`：逐行以蓝色输出 `层N=[...]`，覆盖当前 SubChunk 的全部实际 storage。
- `set`：层索引 0～254。需要时自动补齐中间空气 storage，因此最多形成 255 个 storage。
- `delete`：物理删除指定 storage；后续层按数组语义前移，并安全裁掉最终全空气的尾部层。若删除后没有任何 storage，保留一个空气 storage0。
- `clear`：参数为 UInt8。`0` 只保留 storage0；`1` 保留 storage0/storage1；其余数字保留 storage0…storageN；`255` 不主动裁剪。
- `storage` 仅对 v8 或更新的**已知结构化** SubChunk执行。未知未来版本仍按 raw retention 保护，不能猜测结构化修改。

## effect 负数

- Duration 接受完整 Int32：`-2147483648...2147483647`。
- Amplifier 接受 `-128...255`，负数按 Byte 原始位模式保存；例如 `-1` 与 `255` 都对应 `0xFF`。

## 回归验证

已覆盖：

- setblock 1 层、3 层以及省略高层时保留原 storage；
- 255 storage 解析成功、256 storage 拒绝；
- storage set layer254 成功、layer255 拒绝；
- storage clear 255 成功、256 拒绝；
- `storage add` 明确拒绝；
- storage8 创建、query、clone、delete、clear；
- getblock 输出 Storage8、Chest BlockEntity、空 Compound List 和 NULL BlockEntity；
- Block/BlockEntity 终端蓝色/紫色样式；
- `effect give @s strength -5 -1` 写回 Duration=-5、Amplifier=-1；
- SubChunk v0-v9、LegacyTerrain、现代 actor、iPhone 旧数字方块绑定、metadata CRUD 等既有回归。
