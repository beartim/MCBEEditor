# Blocktopograph iOS 13 v1.1.13（123）

## 实体通用 NBT

- 新增 `BedrockEntityCommonNBT`，空白新建实体和 `summon` 会建立通用实体标签。
- 包含身份与索引所需的 `definitions`、`UniqueID`、`DimensionId`、`LastDimensionId`、`Pos`，以及 `Age`、`Air`、`Motion`、`Rotation`、`OnGround`、`Fire`、`PortalCooldown`、`Persistent`、`Invulnerable`、`LinksTag`、`Tags`、变种和基础状态标签。
- 从现有实体复制或从文件导入时，保留已有实体专用标签，只补齐缺少的通用标签；坐标、维度、UniqueID 和实体身份按创建表单重新写入。
- 旧式区块 Entity 继续保持数字 `id`，现代 Actor 继续使用 namespaced identifier。

## 连续多根实体 NBT 导入

- 空白“新建实体”页面新增“从连续多根 NBT 文件导入…”。
- 选择文件前必须填写实体 ID、维度、XYZ 和起始 UniqueID。
- 仅接受 `.nbt`，并要求至少包含两个连续根标签。
- 第一个根使用填写的 UniqueID，后续根按顺序递增；检测 Int64 溢出。
- 文件读入后进入“检查实体 NBT”页面，逐根显示 identifier、UniqueID、维度和坐标。
- 每个根均可进入完整 NBT 编辑器修改，返回检查页后再执行“导入全部”。
- 导入时按世界实际格式分别写入旧版区块 `Entity(0x32)` 或现代 `actorprefix/digp`。

## 实体连续 NBT 导出

- 实体列表长按菜单和实体详情菜单新增“导出连续多根 NBT”。
- 导出所选实体所在原始 LevelDB 值中的全部连续 NBT 根标签。
- 输出为 Little Endian 连续 NBT 文件，适合再次从“新建实体”页面导入和编辑。

## 未加载区块自动生成

- 方块 NBT 保存遇到缺失 SubChunk 时，不再报“方块所在 SubChunk 尚未生成”。
- 先写入空气区块的版本记录和 `FinalizedState=2`，再创建 v9 空气 SubChunk 并保存目标方块状态。
- `fill` 会为区域覆盖的所有未加载区块先写入空气区块生成状态，然后执行层 0、层 1 和方块实体清理。
- `clone` 会分别为缺失的源、目标区块写入空气区块生成状态；缺失源区块按空气参与快照，目标区块随后接收复制结果。
- 新区块只写入最小生成完成骨架和实际需要的 SubChunk，不使用世界种子生成地形。

## 地图与命令刷新

- 地图点选位置没有可用渲染高度时，方块列默认打开 Y=0，而不是不选中任何 Y。
- 命令输入行和闪烁块状光标移到大终端面板顶部，输出记录位于其下方。
- 命令完成后使用主线程世界变化通知，保持当前 LevelDB 句柄打开。
- 实体、方块实体等对象页面收到通知后自动重新扫描，避免关闭数据库与后台扫描并发造成闪退。

## give

- 对玩家执行 `give` 时扫描槽位 0…35，并写入第一个没有被占用的槽位。
- 物品栏 36 个槽位全部占用时替换槽位 35。
- 对普通实体仍替换 `Mainhand`；缺少主手标签的实体继续跳过。

## summon

格式：

```text
summon 实体类型 实体维度 x y z NBT标签
```

示例：

```text
summon minecraft:pig overworld 0 64 0 'Byte'"Invulnerable"="1",'String'"CustomName"="MyPig"
```

规则：

- 实体类型必须是完整 namespaced identifier。
- 维度只能是 `overworld`、`nether`、`the_end`。
- XYZ 必须完整提供三个整数。
- 最后一个参数必须是严格的 `'类型'"键"="值"` 列表，不能为 `NULL`。
- 支持 `Byte`、`Short`、`Int`、`Long`、`Float`、`Double`、`String`。
- 命令先创建实体通用 NBT，再用指定标签增补或覆盖。
- 禁止覆盖 `UniqueID`、`Pos`、维度、identifier/id 和 definitions 等由命令负责的索引关键标签。
- UniqueID 自动生成，实体存储格式按当前世界自动选择。

## 验证

- 96 个 Swift 源码和测试文件通过语法解析。
- 项目前半段核心测试运行至实体创建、删除、UniqueID、存储格式和位置迁移均通过。
- 后半段方块 NBT、地图、区块、村庄、常加载区域、NBT 导入等回归全部通过。
- 未加载方块 NBT 保存的空气区块元数据、`FinalizedState=2` 和 SubChunk 写入可执行测试通过。
- `give` 第一个空槽位、未加载区块 `fill`、跨维度不同 Y `clone`、`summon` 通用 NBT 可执行测试通过。
- 命令、实体及区块核心在 Linux Swift 工具链中完成独立类型检查。
- Shell 脚本语法与 `git diff --check` 通过。

当前环境没有 macOS、Xcode 和 iOS SDK，因此未执行最终 `xcodebuild` 真机编译。
