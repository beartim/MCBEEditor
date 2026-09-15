# Windows GUI 重叠地图对象点击修复

日期：2026-09-15
基线：MCBEEditor-CLI-stage06

## 问题根因

Windows 地图的重叠对象菜单由 `MainWindow.xaml.cs` 中的 `TryShowMapPointChoice` 统一生成。菜单项虽然显示“查看实体 / 查看方块实体 / 查看本地玩家 / 查看在线玩家”，但 `MapPointChoiceCandidate` 原先只有一个 `Action Select`，菜单点击和普通单击共享该动作。对象候选因此只执行 `SelectMapObjectRow(...)`，从未进入 `EditObjectNbtAsync(...)`，所以不会弹出 NBT 编辑器。

直接双击单个实体标记之所以正常，是因为 `MapObjectMarker_MouseLeftButtonDown` 的双击分支直接调用了 `EditObjectNbtAsync(...)`，与重叠菜单不是同一条执行路径。

## 修复

1. `MapPointChoiceCandidate` 拆分为：
   - `Select`：普通单击 / 单候选时使用，保持只选中对象的原行为；
   - `OpenFromMenu`：只有真正出现重叠菜单并点击菜单项时使用，可执行完整查看/编辑动作。
2. 实体、方块实体、本地玩家、在线玩家的重叠菜单项现在先选中目标，再调用现有 `EditObjectNbtAsync(...)`，与对象列表和直接双击共用同一个 NBT 保存链。
3. 村庄和 HardcodedSpawners 也补齐 `OpenFromMenu`，重叠菜单不再成为只能选中、无法进入现有编辑界面的死路；直接双击改为复用相同 helper，避免两条路径以后再次漂移。
4. 兴趣点方块和出生点没有独立 NBT 编辑动作，仍保持原来的方块选择 / 地图详情行为。
5. 单候选分支仍明确执行 `ordered[0].Select()`，因此单击普通实体标记不会因为本修复变成自动弹出 NBT 编辑器。

## 重叠点击路径审计

统一菜单的 5 个调用入口均已检查：

- `MapImage_MouseLeftButtonUp`
- `MapSpawnFeature_MouseLeftButtonDown`
- `MapSpawnerFeature_MouseLeftButtonDown`
- `MapVillageFeature_MouseLeftButtonDown`
- `MapObjectMarker_MouseLeftButtonDown`

候选类型共 5 类：村庄中心、兴趣点方块、出生点、玩家/实体/方块实体、HardcodedSpawners。未发现第二套独立的地图重叠菜单实现。

## 回归测试

新增 `CLI/Tests/windows_gui_overlap_click_audit.py`，固定：

- 普通单击选择与重叠菜单完整打开动作必须分离；
- 单候选仍只能走 `Select`；
- 实体/方块实体/玩家菜单项必须进入 `EditObjectNbtAsync`；
- 村庄和 HardcodedSpawners 重叠菜单必须能进入已有编辑 UI；
- 5 个重叠点击入口和 5 类候选数量变化时必须重新审计。

当前 Linux 环境没有 .NET / MSVC / WPF 构建链，因此没有把静态审计冒充 Windows 真编译。已有 CLI/source 累计审计与新增 Windows GUI 重叠点击审计均已实际执行通过，修改后的 C# 文件还通过了词法括号/分隔符平衡检查。最终仍建议在 Windows 10 + .NET 10 / MSVC 环境执行 `Windows\\build.cmd` 后做一次 GUI 实机点击验证。

## 完整性清单

本修复包新增 `CLI/Shared/stage06a-windows-gui-overlap-files.sha256` 作为当前快照的完整性清单；原 `stage06-files.sha256` 保留为输入基线的历史记录，不再代表修复后的工作树。
