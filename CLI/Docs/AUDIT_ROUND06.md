# 第 6 轮：storage 与持久化兼容审计

日期：2026-09-21。输入为 `MCBEEditor-CLI-v1.0.0-audit-part05.zip`，SHA-256：`7174e0bde4239c7b7c053445c6547f104e376289eef695eff607319c4d5f9366`。

**状态：源码修订及回归用例已交付，静态检查通过；原生编译、行为测试与游戏读档验证待补。** 本轮按 10 分钟上限收口，保留前 5 轮成果。版本仍为 1.0.0，iOS 最低版本仍为 13.0。

## 本轮修订

### 1. Swift 显式写入空气时创建缺失子区块

`setState` 在内存中建立空气子区块后，如果请求 layer0 的状态恰好也是初始空气，原逻辑会认为没有变化，不把新子区块纳入提交。结果可能只写了区块元数据，后续 storage query 仍提示 Block not generated。

现在分别记录“新建子区块”和“修改已有状态”，显式要求创建时，即使初始空气等于请求状态，也提交该子区块。覆盖 storage set，也修正共享路径中 fill/setblock 的相同情况；不改变其他路径的 createWhenAir=false 规则。

### 2. Swift storage 返回实际修改标记

原外层通过消息是否为 Block not generated 判断 changedWorld，导致 clear 255、保留到已有最高层、重复设置相同状态等无写入操作仍标记世界已修改。

storage 方法现返回消息与修改标记，由实际编辑/提交路径决定，外层直接传递。缺失子区块的 query/delete/clear 仍不写入。delete 仍遵循整层删除及安全裁剪规则。

### 3. Swift storage 水平坐标先校验再定位

storage 各入口通过 subKey 计算区块，但原先没有像 fill/getblock 一样验证水平范围。MapCoordinate 的 Int32 截断/限幅可能把越界坐标映射到边界区块。

现于 subKey 统一验证 X/Z 必须处于 Bedrock Int32 区块可表示的方块范围，再进行区块计算和读写。现有正常坐标范围不变；未把 Swift 缩窄为 Windows 的 Int32 方块坐标范围。

### 4. Windows storage set 先统一旧 val 调色板格式

旧逻辑把现代 states 形式送入旧 val 调色板的查重，再在持久化阶段转换回 val。反复设置同一方块可能反复追加最终内容相同的条目，造成多余写入和调色板增长。

现在先按目标调色板格式转换，再查找/替换条目，与已有 region 写入路径保持一致。末地缺失高层的原格式推断、v8/v9 头和空 storage 位宽策略不变。

### 5. Windows delete / clear 使用真实 Put 数量

原结果把 PutCount 固定为 1，即使 Persist 已过滤掉全部相同字节，也会使 CLI 报告已修改。现传回 Persist 的实际返回值，既能正确报告 0，也能反映必要元数据带来的多条 Put。

上述问题均依据源码数据流定位。本环境没有取得修复前失败、修复后通过的原生运行记录，不能把新增断言视为已运行通过。

## 回归与核对范围

新增 `Windows/MCBEEditor.Core.SelfTest/StorageAuditTests.cs`，接入完整自测与 `--cli-regression`；Swift 在现有命令执行测试内加入并调用 `verifyStorageAudit()`。

| 场景 | 新增断言 | 状态 |
| --- | --- | --- |
| 缺失子区块 query/delete/clear | 不创建数据，不报告修改 | 待原生执行 |
| 末地 Y=160/200/255，layer0=air | 实际生成可回读的 SubChunk，保留 v8 val / v9 格式 | 待原生执行 |
| v8 旧 val | 空 storage 至少一位索引、保留 val 且不增加 version | 待原生执行 |
| layer254 | 创建并查询全部 255 层 | 待原生执行 |
| clear255 / clear254 | 已有 255 层时无裁剪、无字节变化，Swift changedWorld=false | 待原生执行 |
| 重复 set | 同一状态不追加重复旧 val 条目，Windows PutCount=0、Swift changedWorld=false | 待原生执行 |
| delete0 | 整个 storage 前移，验证同子区块另一坐标和原 layer254 的移动 | 待原生执行 |
| 原末地记录 | 原有低层 seed 字节保持不变 | 待原生执行 |
| 非法层数 | set255、Swift clear256 拒绝且不写入 | 待原生执行 |
| Swift 越界 X/Z | query/set/delete/clear 越界报错，整个内存数据库保持原值 | 待原生执行 |
| Windows 删除唯一空层 | Persist 无写入时结果 PutCount=0 | 待原生执行 |

测试使用产品存储命令路径、真实 NBT/SubChunk 编解码与项目已有内存数据库替身。不能代替原生 LevelDB、导出重开和同版本 Minecraft 读档。

已有 v0～v9、旧数字 ID/LegacyTerrain、未知格式、v1/v8/v9 缺失高层等测试和 fixture 全部保留；本轮未改底层编解码，也不把未运行的版本矩阵标为通过。

## 实际验证

- `CLI/Tests/source_audit.py` 通过：26 命令、142 解析 fixture、62 Swift 编译输入及接线静态检查。
- `CLI/Tests/build_audit.py`、`CLI/Tests/windows_gui_overlap_click_audit.py` 通过。
- `bash -n Scripts/run_core_tests.sh`、`bash -n Scripts/test_end_missing_subchunks.sh`、`bash -n CLI/Scripts/build-apple.sh` 通过。仅证明 shell 语法，不证明内嵌 Swift 编译通过。
- 实际尝试 `bash Scripts/test_end_missing_subchunks.sh`：因 swiftc 不存在退出 127，未进入测试。
- 实际尝试 .NET 核心 CLI 回归：因 dotnet 不存在退出 127，未进入编译或测试。
- 已核对新增测试入口、改动范围与前轮修订保留情况；打包时核验 ZIP 完整性。

目标平台验证入口：

```powershell
dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release -- --cli-regression
& .\CLI\Scripts\build-windows.ps1 -Test
```

```bash
bash Scripts/run_core_tests.sh
bash Scripts/test_end_missing_subchunks.sh
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
```

## 接续与限制

1. 尚未生成经原生执行验证的末地样本；必须在具备工具链的平台完成新增用例、原 fixture、保存重开和同版本游戏读档后，才能验收游戏兼容。
2. Swift 删除唯一空 storage 仍沿用原重新提交路径；Windows 会过滤相同字节。本轮修正实际结果标记，没有将所有重复写入策略统一。
3. 前 2～5 轮的待验证项与已登记差异继续保留。第五轮发现的 clone / structure 方块实体整理路径分别接续第 7、9 轮。
4. 下一轮为第 7 轮：clone、chunk、fillbiome、tickingarea。每步仍限时 10 分钟，最终复核不得自动勾选未完成项。
