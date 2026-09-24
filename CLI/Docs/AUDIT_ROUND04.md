# 第 4 轮：玩家与选择器命令审计

日期：2026-09-21。输入为 `MCBEEditor-CLI-v1.0.0-audit-part03.zip`，SHA-256：`a63d152cb8149785e076d7ac5ad602520875fb9b41d34b6f1e99d83f19a40eab`。

**状态：源码修订和新增回归用例已交付，静态检查通过；编译、行为运行和实际世界保存重开验证待补。** 本轮按 10 分钟时限收口。保留第 1～3 轮成果，版本保持 1.0.0，iOS 最低版本保持 13.0。

## 本轮修订

### 1. 双端 kick：按键族所属玩家匹配，避免数字出现在任意位置时误删

旧实现只要 player_ 开头的键在中间或末尾出现目标 UniqueID，就可能删除。例如执行 `kick 2002` 时，`player_server_9002_meta_2002`、`player_data_9002:2002`、`player_storage_9002_2002_meta` 都可能被当作玩家 2002 的记录删除。

Windows 与 Swift 现保留两条明确匹配规则：已选玩家的完整记录键及其 `_`、`:`、`/` 分隔的子键；或已知 `player_`、`player_server_`、`player_data_`、`player_storage_` 键族后紧接完整 UniqueID 的键及子键。禁止通过任意位置的数字推断归属。类似 ID（12002、20020）、其他玩家的元数据和本机玩家记录应保持原字节。未知布局的键不会仅因包含该数字而被删除。

修改位于 `Windows/MCBEEditor.Core/Entity/PlayerNbtStore.cs` 与 `Sources/World/PlayerNBTStore.swift`。

### 2. Swift teleport Auto：数值越界返回错误，避免转换陷阱

`Double(Int64.max)` 会舍入为 2^63，原先的 `floored <= Double(Int64.max)` 检查会放过不能存入 Int64 的数值，随后 `Int64(floored)` 可能直接触发运行时陷阱。例如 `teleport @s overworld 9223372036854775808 Auto 0`。

改为 `Int64(exactly: floored)`，无法表示时抛出已有错误。X、Z 共用此检查；可表示的负数仍先向下取整，不改变整数 Y / Auto 对玩家增加 1.62、显式浮点 Y 原值写入、实体不增加眼高的规则。

修改位于 `Sources/Command/WorldCommandExecutor.swift`。Windows 已有更窄的 Int32 方块坐标检查，不存在该转换入口；本轮未扩大 Windows 范围。

上述问题依据源码控制流和数值边界定位，**未取得产品修复前失败、修复后通过的运行记录**。

## 七个命令的核对结果

| 命令 | 已核对源码 | 结果边界 |
| --- | --- | --- |
| clearspawnpoint | 目标必须含玩家、无标签时报错、清理字段及写入顺序 | 发现清理范围和批量提交差异，列为补充项，未宣称一致 |
| experience | 本机/在线玩家选择、只读 query、0～24791 等级、总量曲线、溢出检测和批量写入 | 新增 XP 边界回转断言，待执行 |
| kick | 在线玩家限制、键族删除、本机保护 | 双端收紧归属匹配，新增未选记录原字节保护断言 |
| setworldspawn | level.dat 顶层 SpawnX/Y/Z，Int32 写入 | 本轮源码核对，既有保存重读用例未在本环境运行 |
| spawnpoint | SpawnDimension、SpawnForced、目标为玩家、多玩家批量提交 | 本轮源码核对，既有用例继续保留 |
| teleport | 整数/浮点/Auto Y、负坐标、Pos/Motion/维度、无目标 | 修复 Swift Auto 的 Int64 上界转换，新增边界与写入断言 |
| spread | 有地形的已加载区块、无可用列报错、玩家眼高、实体迁移 | 新增无地形失败且未写入断言；随机结果及真实区块待运行 |

@s、@a、@e、UniqueID 和 identifier 的现有选择器路径已源码对照；没有新增或删除命令。

## 新增回归

- `Windows/MCBEEditor.Core.SelfTest/PlayerTargetingAuditTests.cs` 接入完整核心自测及 `--cli-regression`。
- `Scripts/run_core_tests.sh` 的现有 Swift 命令执行测试加入 `verifyPlayerTargetingAudit()`。
- 双端覆盖：kick 删除目标和四类关联键、保留六个易误匹配键与本机/其他玩家原字节；传送整数/浮点/Auto 高度和负坐标；保留无关 NBT 标签；XP 总数 0、7、352、394、最大值回转；无地形 spread、无匹配目标报错且不写入。
- Swift 额外覆盖 X 和 Z 分别取 2^63 的 Auto 传送，要求抛出可捕获错误且整个内存数据库保持不变。

这些测试调用产品解析器、执行器和 NBT 编解码，数据库使用项目既有内存替身。Swift 此段测试还沿用既有 block-reader 测试替身，其非空气块高度固定为 70，因此 Auto 期望玩家 Y=72.62；Windows 用无地形数据库测试回退 Y=63、玩家 Y=64.62。两者并非真实地形对照验证，不能代替原生 LevelDB 或 Minecraft 读档。

## 实际验证

- `CLI/Tests/source_audit.py` 通过：26 命令、142 解析 fixture、62 个 Swift 编译输入及接线的静态检查。
- `CLI/Tests/build_audit.py` 通过。
- `CLI/Tests/windows_gui_overlap_click_audit.py` 通过。
- `bash -n Scripts/run_core_tests.sh`、`bash -n CLI/Scripts/build-apple.sh` 通过；此结果不证明内嵌 Swift 已编译。
- 已复核改动范围和新测试入口；产物完整性与上一轮文件保留情况在打包时核验。
- 本环境 `dotnet`、`swiftc` 均不存在，未运行 C#/Swift 编译、新增行为回归、原生 LevelDB、GUI、真机或 Minecraft 读档。

目标平台执行入口：

```powershell
dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release -- --cli-regression
& .\CLI\Scripts\build-windows.ps1 -Test
```

```bash
bash Scripts/run_core_tests.sh
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
```

## 明确保留的补充项

1. clearspawnpoint：Swift 递归处理更多出生点别名及嵌套容器，Windows 仅清理顶层五个字段；Swift 逐玩家保存，Windows 汇总后批量提交。需要用嵌套出生点、物品自定义同名标签、后续记录损坏的夹具核定正确清理范围并统一行为。本轮未改此路径，也未将第 4 轮标为全部验收通过。
2. teleport/spread：玩家批量提交后实体仍逐对象迁移，后续实体失败可能出现部分写入；两端均须用混合目标失败夹具验证，并纳入后续提交一致性修订。
3. 坐标范围：Windows teleport X/Z 限 Int32 方块坐标，Swift 部分路径接受更大范围；没有为了对齐而擅自缩窄 Swift 的兼容范围。此差异留待边界行为统一。
4. PlayerNBTStore 当前扫描全部 player_ 前缀的可解码 NBT；辅助记录与真正玩家记录的区分仍需真实键族样本校验。
5. 第 2、3 轮未运行的行为回归及已登记差异继续保留；目标平台编译和保存重开验证仍是发布前要求。

下一轮按原计划进入第 5 轮：setblock / fill / getblock。上述第 4 轮补充项须后续单独闭环，每个补充步骤仍不超过 10 分钟，不能在最终复核时默认为已解决。
