# 实体导入与浮点坐标修正

软件版本保持 MCBEEditor 1.0.0（构建号 100）。

## 实体 NBT/JSON 导入

- 导入准备阶段不再调用空白实体的通用 NBT 模板，也不补充 Air、Motion、Rotation、definitions、identifier、DimensionId 等默认标签。
- 只覆盖/补入 `Pos` 和 `UniqueID`，源文件中的其他顶层标签保持不变。
- 导入记录只要求根为 Compound，并存在有效的 `Pos` 与非零 `UniqueID`；不再要求 identifier。
- `DimensionId` 不是导入 NBT 的必需标签：
  - 已存在时按原值决定实体写入维度，并保持该标签原样；
  - 缺少时，点击“导入全部”弹出“选择维度”窗口，可选主世界/下界/末地；选择结果只决定 LevelDB 的实体存储位置，不会向 NBT 中新增 `DimensionId`。

## teleport

- X/Z 支持有限整数或浮点数；Y 支持有限整数、浮点数或 `Auto`。
- `Auto` 使用 X/Z 所在方块列（对浮点 X/Z 向下取整）计算落脚 Y。
- 对玩家：
  - Y 参数以整数形式输入时，在计算值上增加 1.62 后写入 `Pos[1]`；
  - Y 为 `Auto` 时同样增加 1.62；
  - Y 以浮点形式输入时（包括 `70.0`）不增加 1.62，直接写入。
- 普通实体不应用 1.62 偏移。

## spread

- 玩家仍使用 Auto 地形高度，但实际写入的 `Pos[1]` 增加 1.62。
- spread 输出玩家坐标时显示实际写入的浮点 Y。

## summon

- X/Y/Z 均支持有限整数或浮点数，并直接写入实体 `Pos`。

## 回归测试

- 验证实体导入不会生成默认标签，且缺少 DimensionId 时使用外部选择维度但不写回该标签。
- 验证 teleport 整数 Y、浮点 Y、Auto 与 spread 玩家 1.62 偏移。
- 验证 summon 浮点坐标写入。
