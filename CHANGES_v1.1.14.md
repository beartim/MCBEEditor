# MCBEEditor iOS 13 v1.1.14（124）

## 命令结果颜色

- 所有成功执行的命令结果统一使用绿色文字。
- 命令回显继续使用终端默认文字颜色，错误结果继续使用红色。
- 使用 attributed text 追加输出，避免后续内容覆盖前面记录的颜色。

## 未加载区块与 SubChunk 持久化

- 不再固定使用现代 Version 或由编辑占位方块强制决定 SubChunk 格式。
- 全新目标区块会扫描同一维度已有记录，选择匹配的 Version 或 LegacyVersion。
- 现代区块复制同维度 Data3D 高度/生物群系元数据模板，旧版区块复制 Data2D/Data2DLegacy 模板。
- 复用同维度实际方块调色板版本；无法读取时才使用安全后备版本。
- 写入 FinalizedState=2，并在写入后逐项读回版本、地形元数据和目标 SubChunk。
- 现代维度中的旧数字方块输入会转换为现代字符串方块状态，避免 Version 与 v7 数字 SubChunk 混写。
- 仅有 LegacyVersion 的旧版维度继续创建 v7 数字 SubChunk。
- 方块 NBT、fill、clone 均使用上述匹配逻辑；命令生成区块后也会验证元数据确实存在于 LevelDB。

## kill @e 1

- 修复多个旧版实体共用同一个 Entity(0x32) 连续 NBT 值时，逐个删除导致后续扫描索引失效的问题。
- 所有目标先按源 LevelDB 键分组，每个连续 NBT 值只解码一次。
- 记录索引按降序统一移除，并与 actorprefix/digp 更新放入同一个 LevelDB WriteBatch。
- 发生解析或写入错误时不会留下“已删一部分再报数据格式错误”的状态。

## give

- 玩家空槽仅认定为：物品栏 List 内的 Compound，且该 Compound 的 Name 字符串标签为空。
- 在所有空槽中使用 Slot 数值最小的一项；没有空 Compound 时按物品栏已满处理并替换最后一格。
- 对非玩家实体写入 Mainhand 时，物品 Compound 额外写入 Byte 类型 WasPickedUp=1。
- 村民交易数据仍不受 clear/give 影响。

## summon 与实体通用 NBT

- summon 最后一个参数支持小写 `default`，表示不对实体通用 NBT进行任何额外覆盖。
- 仍支持严格的 `'类型'"名称"="值"` 逗号列表，参数数量不能多或少。
- `IsAutonomous` 默认值改为 0。
- `ShowBottom` 默认值改为 0。
- 新增 Byte 类型 `IsEating=0`。
- 删除 LinksTag、FireImmune、HasCollision、HasGravity、HasOwner、Age。

## 验证

- 96 个 Swift 源码和测试文件通过语法解析。
- 三个实体共用同一 Entity(0x32) 记录的原子批量删除可执行测试通过。
- 现代 Version/Data3D/v9 与旧版 LegacyVersion/Data2D/v7 两套缺失区块写入测试通过。
- 方块 NBT 写入后的元数据和 SubChunk 读回验证通过。
- 项目核心回归前半段与后半段分段执行全部通过。
- Shell 脚本语法与 project.yml YAML 解析通过。

当前环境没有 macOS、Xcode 和 iOS SDK，因此未执行最终 xcodebuild 真机编译。
