# Blocktopograph iOS 13 v1.1.15（125）

## 旧版数字 ID SubChunk 自动升级

- 方块 NBT、`fill` 和 `clone` 在旧版数字 ID SubChunk 中写入以下内容时，不再返回“不支持”或生成混合格式记录：
  - 没有旧版数字 ID 的方块；
  - 包含任意非空 `states` 的方块；
  - 需要实际创建非空气层 1 的方块。
- 首次需要现代方块状态时，会把目标区块内全部旧版 SubChunk 从 v0/v2–v7 转换为 v9。
- 同一个 LevelDB WriteBatch 中同步完成：
  - 写入现代 `Version`；
  - 把 `Data2D`／`Data2DLegacy` 扩展为 `Data3D`；
  - 保留高度图和原有二维生物群系值；
  - 写入 `FinalizedState=2`；
  - 删除 `LegacyVersion`、`Data2D` 和 `Data2DLegacy`；
  - 写入全部升级后的 SubChunk 和本次方块修改。
- 如果目标方块仍可由旧版数字 ID 表示且 `states` 为空，则继续使用旧版 SubChunk，不进行无意义升级。
- `clone` 向旧版 SubChunk 复制层 1 空气时不会仅因为缺失第二层而触发升级。

## 命令 NBT 递归解析

`fill`、`summon` 和 `give` 的 NBT 参数现在支持全部 NBT 标签类型：

- `Byte`、`Short`、`Int`、`Long`、`Float`、`Double`、`String`
- `ByteArray`、`IntArray`、`LongArray`
- `List`
- `Compound`

支持任意层级的 List／Compound／Array 嵌套，并允许空数组、空 List 和空 Compound。

示例：

```text
'ByteArray'"Name"="[0,1]"
'List''IntArray'"Name"="[],[5,2]"
'Compound'"Name"="{'String'"Name"="Tom",'List''Int'"Num"="1,2,3,4"}"
'List''Compound'"Name"="{'Int'"Num"="0"},{}"
```

- 同一 Compound 内出现同名标签时拒绝执行。
- 数组、List、Compound 的括号与引号必须完整闭合。
- 命令参数数量仍然严格校验。
- 修复层 0 NBT 参数后仍有层 1 方块参数时，后续参数可能被错误并入 NBT 的边界问题。

## `give` 第四参数

格式改为：

```text
give 目标 物品 数目 物品标签
```

- 第四参数输入 `NULL` 时不增加额外物品标签。
- 非 `NULL` 时可一次增加或覆盖多个顶层物品 NBT 标签。
- 专用参数 `Name`、`Count`、`Slot` 和非玩家实体的 `WasPickedUp` 仍由命令本身控制。

示例：

```text
give minecraft:cow minecraft:lit_smoker 99 'Compound'"tag"="{'Byte'"Unbreakable"="1"}",'Short'"Damage"="1"
```

结果会增加 Compound `tag`，并把顶层 `Damage` 修改为 Short 1。

## 检查

- 全部 Swift 源码通过语法解析。
- 递归 NBT 解析器通过标量、三种 Array、List、Compound、List<Compound>、空容器与多重嵌套测试。
- `fill` 中间 NBT 参数与后续命令参数分隔测试通过。
- 旧版区块的 `LegacyVersion/Data2D/v7` 到 `Version/Data3D/v9` 原子迁移测试通过。
- 同一区块多个旧版 SubChunk 一并升级并读回测试通过。
- 实际 `fill` 命令触发升级测试通过。
- `give` 嵌套 Compound `tag` 与顶层 `Damage` 写入测试通过。
