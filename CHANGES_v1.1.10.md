# MCBEEditor iOS 13 v1.1.10 修改说明

## 命令执行完成后闪退

- 命令执行器不再从后台队列直接调用 `WorldSession.invalidateAfterExternalChange()`。
- 命令的数据库写入结束、临时方块存储对象释放后，命令界面回到主线程，再关闭 LevelDB 缓存并发送世界变化通知。
- `WorldSession.invalidateAfterExternalChange()` 增加主线程保护；即使未来从后台调用，也会自动切换到主线程后再通知 UIKit 界面。
- 输出滚动改为定位到文本末尾的零长度范围，避免极短输出或清屏后的越界滚动。

## clone 重叠区域修复

- 修复源区域与目标区域重叠时，刚写入的目标方块又被作为后续源方块读取，造成单个方块沿偏移方向连续复制的问题。
- 重叠复制改为类似 `memmove` 的反向遍历：目标相对源向正方向移动时，从对应轴的最大坐标开始复制；向负方向移动时从最小坐标开始复制。
- 方块实体在写入前单独读取源区域快照，避免重叠时产生连锁复制。
- 示例 `clone overworld 0 0 0 4 70 4 overworld 1 0 1` 中，若源区域只有 `(0,70,0)` 为目标方块，则目标区域只有 `(1,70,1)` 得到该方块，不会继续扩散到 `(2,70,2)…(5,70,5)`。

## 跨维度命令格式

维度名称严格限定为：

- `overworld`
- `nether`
- `the_end`

`clone` 新格式：

```text
clone 源维度 x1 y1 z1 x2 y2 z2 目标维度 x3 y3 z3
```

示例：

```text
clone overworld 0 0 0 5 100 46 nether 9 50 9
```

`fill` 新格式：

```text
fill 目标维度 x1 y1 z1 x2 y2 z2 层0名称 层0states 层1名称 层1states
```

示例：

```text
fill the_end 0 0 0 60 200 16 minecraft:leaves 'String'"old_leaf_type"="oak",'Byte'"persistent_bit"="0",'Byte'"update_bit"="0" minecraft:chest 'Int'"facing_direction"="3"
```

- `clone` 可在不同维度之间复制层 0、层 1和方块实体。
- 源维度中未加载的区块和目标维度中未加载的区块分别跳过，不创建新目标区块。
- `fill` 只操作命令中指定目标维度的已加载区块。
- 旧的无维度参数格式会被严格拒绝。

## 命令行界面

- 移除命令栏目的维度选择框。
- 输入维度直接写在 `clone` 或 `fill` 命令参数中。
- 增加深色等宽字体输入行，输入内容会在终端中实时显示。
- 输入行增加持续闪烁的块状命令光标。
- 点击输入行即可呼出键盘；单双引号、空格及 states 内容会按实际输入原样显示。

## 版本

- Marketing Version：1.1.10
- Build：120
- 最低系统：iOS / iPadOS 13.0
