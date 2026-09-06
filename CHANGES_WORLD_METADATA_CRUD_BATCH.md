# 世界元数据 CRUD / 批量操作

本轮完善 `NBT -> 元数据` 页面，操作对象是世界 LevelDB 中的元数据记录本身，而不只是记录内部的 NBT 根标签。

## 单项操作

- 元数据列表右上角新增 `+`：可新建世界元数据记录。
  - 支持当前编辑器识别的固定元数据键：`AutonomousEntities`、`BiomeData`、`mVillages`、`Nether`、`Overworld`、`TheEnd`、`portals`、`dimension0`、`scoreboard`、`mobevents`、`schedulerWT`。
  - 支持 `map_*` 地图元数据键。
  - 新建时继续使用现有 NBT 根标签创建/导入界面，可建立一个或多个连续 NBT 根标签；新记录按 Bedrock Little Endian NBT 写入。
  - 同名键不会静默覆盖。
- 元数据列表左滑新增：
  - `重命名`：只移动 LevelDB key，原 value 按原始字节保留。
  - `删除`：确认后删除完整元数据记录。
  - `复制键`：复制原始 LevelDB UTF-8 键名。
- 单项重命名到已存在的元数据键时必须二次确认；确认后才会替换目标。
- 键名会校验为空、换行、NUL 以及是否属于世界元数据命名范围，避免误覆盖 actor、structuretemplate 等其他 LevelDB 数据。

## 批量操作

元数据列表右上角新增 `选择`：

- 可在当前搜索结果中全选/取消全选；搜索切换不会丢失已经选中的其他记录。
- `复制键名`：把所选键名按行复制到剪贴板。
- `批量删除`：使用单个 LevelDB WriteBatch 原子删除。
- `批量重命名`：支持 `查找 -> 替换 + 前缀 + 后缀` 规则，并先显示最多 5 条预览。
  - 所有生成的目标键都会重新执行元数据键校验。
  - 目标键之间有重复时整批拒绝。
  - 目标键已经被未选中的数据库记录占用时整批拒绝。
  - 支持所选键之间相互交换/移动；实际写入使用一个原子 WriteBatch。
  - 只改变键名，不重新编码 NBT value，因此原始 value 字节保持不变。

## 记录内部 NBT

原有功能保持：进入某一元数据记录后仍可新建、重命名、删除根标签，并支持根标签批量选择、复制、导出和删除；保存后写回原元数据 key。

## 回归测试

新增 `Scripts/test_metadata_crud_batch.sh`，并接入 `run_core_tests.sh`，覆盖：

- 固定元数据键与 `map_*` 校验；
- 非元数据键拒绝；
- 新建多根 NBT；
- 单项重命名时 value 原始字节不变；
- 批量重命名时多个 value 原始字节不变；
- 未选中目标键冲突时整批拒绝且数据库不发生部分修改；
- 批量删除数量与结果；
- UI 新建/删除/重命名/批量入口存在性。

本轮再次运行：

- `test_metadata_crud_batch.sh`：通过；
- `test_viewed_unsaved_sync.sh`：通过；
- `test_metadata_variant_search.sh`：通过；
- `test_modern_actor_binary_string.sh`：通过；
- `test_legacy_zlib_and_selection_export.sh`：通过；
- 全部 106 个 Swift 源文件 `swiftc -parse`：通过。

完整 `run_core_tests.sh` 因执行时间超过当前环境单次运行窗口被截断；截断前没有测试失败。本轮改动只涉及 `MetadataNBTStore`、`MetadataNBTViewControllers` 与测试脚本，相关专项/交叉回归均已单独通过。
