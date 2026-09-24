# 第 5 轮：基础方块读写审计

日期：2026-09-21。输入为 `MCBEEditor-CLI-v1.0.0-audit-part04.zip`，SHA-256：`7a8cf2320058ad3cd9fc040589c9a23b030543b5b145374b0582b9fff7469a54`。

**状态：源码修订、回归用例和帮助同步已交付；静态检查通过，编译及行为运行待补。** 本轮按 10 分钟上限收口，保留前 4 轮成果。版本保持 1.0.0，iOS 最低版本保持 13.0。

## 本轮修订

### 1. Swift setblock / fill 不再丢弃无关方块实体

原 `removeBlockEntities` 先通过坐标字典加载同一区块的全部 BlockEntity，再重写所有涉及区块。这会遗漏无法取得坐标的记录，合并重复坐标的记录，重排原记录；即便选区没有命中任何方块实体，也可能产生这种重写。

改为逐区块解析原连续 NBT，按原记录顺序过滤，只移除具有可解析坐标且位于选区内的记录。无法定位的记录、选区外同坐标的多条记录都保留；无命中时不安排该 BlockEntity 键的写入或删除。有命中时保留各记录的原编码类型，并通过既有编码器写回。删除计数按实际记录数累计，选区内两条重复记录算两条。

这与 Windows 现有的记录过滤方式对齐。仍在所有地形、元数据和方块实体编辑都准备完成后一次提交；遇到连续 NBT 解析错误时抛出错误，不跳过损坏记录后继续写入。

### 2. Swift getblock 的重复坐标查询与 Windows 一致

旧代码复用坐标字典，多个 BlockEntity 位于同一位置时返回最后一条。现在直接按存储顺序查找首条匹配记录，与 Windows 一致，保持查询只读。各 storage 的输出规则未修改。

以上两处均位于 `Sources/Command/WorldCommandExecutor.swift`，共享于 Swift CLI 与 GUI 命令入口。Windows 生产写入逻辑本轮无需修改。

### 3. 修正旧数字格式帮助

原帮助称“更多 storage 或现代 states 时自动升级”，与双端实际保护原格式、无法无损表示时拒绝的行为冲突。现明确：旧数字 ID SubChunk 保持原格式，只支持可无损转换的 layer0/1；不能表示的方块/states 或超过两层的请求会报错，不自动升级，不留下部分修改。

同步四处：Swift 命令帮助、Windows 命令帮助、Swift `SharedCommandFileStore` 的命令文件说明模板、CLI 公共命令清单。现代格式最多 255 个 storage、省略层保留、显式空气层写入等既有规则不变。

问题依据源码数据流定位。**本环境没有修复前失败、修复后通过的原生运行记录，不能把新增断言视为已执行通过。**

## 源码核对与回归覆盖

| 范围 | 核对结果及新增用例 | 验证边界 |
| --- | --- | --- |
| 负坐标与跨区块 fill | X=-17/-16/-1/0/15/16，Z=-1；只改 layer0 时 layer1/2 保留，X=17 邻接方块不变 | 双端新增产品执行路径用例，待运行 |
| 显式空气 | 只清空显式给出的 layer1，更高 layer2 保留 | 双端新增断言，待运行 |
| getblock | 返回全部 storage；重复坐标 BlockEntity 取首条，Swift 查询前后数据库相同 | Swift 生产修订；双端新增断言，待运行 |
| BlockEntity 清理 | 同坐标的选区外两条记录、无坐标记录按原顺序保留；选区内重复记录均删除 | Swift 生产修订；双端新增夹具及字节比较，待运行 |
| 没有命中的 BlockEntity | 不重写该键，原字节不变 | 双端新增断言，待运行 |
| 损坏的连续 NBT | 跨两个区块 fill，后续 BlockEntity 无法解析时整个数据库不变 | 双端新增失败夹具，待运行 |
| 旧数字格式拒绝 | 无旧版映射的方块、请求三层 storage 时拒绝；新目标区块不残留元数据或地形 | 双端新增全数据库快照断言，待运行 |
| 已有旧格式与高层创建 | 保留既有 v0/v7/v1/v8/v9 持久化和末地高层测试，不改格式推断与存储编码 | 本轮源码核对；真实游戏读档仍待验证 |

新增 `Windows/MCBEEditor.Core.SelfTest/BlockCommandAuditTests.cs`，接入完整自测和 `--cli-regression`。Swift 在 `Scripts/run_core_tests.sh` 的现有命令测试中新增并调用 `verifyBlockCommandAudit()`。

测试使用产品解析/执行或核心 region store、NBT 和 SubChunk 编解码；数据库仍是项目既有内存替身。Swift getblock、fill/setblock 走真实 CommandBlockStore，不能据此宣称真实 LevelDB、GUI 或 Minecraft 运行通过。

## 实际验证

- `CLI/Tests/source_audit.py` 通过：26 命令、142 解析 fixture、62 Swift 编译输入及接线的静态检查。
- `CLI/Tests/build_audit.py` 通过。
- `CLI/Tests/windows_gui_overlap_click_audit.py` 通过。
- `bash -n Scripts/run_core_tests.sh`、`bash -n CLI/Scripts/build-apple.sh` 通过；仅验证 shell 语法，不证明内嵌 Swift 已编译。
- 已核对新测试调用点、帮助清单同步及改动范围，打包时核验前轮文件保留与 ZIP 完整性。
- `dotnet` 和 `swiftc` 均不可用，因此未运行 C#/Swift 编译、新增行为用例、原生数据库、GUI、真机或 Minecraft 读档。

目标平台执行入口：

```powershell
dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release -- --cli-regression
& .\CLI\Scripts\build-windows.ps1 -Test
```

```bash
bash Scripts/run_core_tests.sh
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
```

## 接续事项

1. 本轮所有行为用例仍须目标平台编译、执行，并验证导出后重开及同版本游戏读档。
2. Swift clone / structure 仍使用按坐标整理 BlockEntity 的路径，异常/重复记录的处理须在第 7、9 轮分别审计；本轮修订只处理 fill/setblock 清理与 getblock 查询，不代表这些复用路径已解决。
3. Windows 与 Swift 的 X/Z 极值范围差异继续保留，见第四轮记录；本轮不扩大或缩窄既有坐标兼容范围。
4. 第 2～4 轮已登记的环境查询、提交一致性、出生点及玩家记录识别等补充项继续保留，最终复核不能自动视为完成。

下一轮为第 6 轮：storage 与持久化兼容，重点关注 255 层、缺失子区块及末地高层创建。每步仍不超过 10 分钟。
