# 第 3 轮：实体操作命令审计

日期：2026-09-21。输入为 `MCBEEditor-CLI-v1.0.0-audit-part02.zip`，SHA-256：`01683196075b978cd1a8ad2168b77789c6a271ff917868dfa209081101cadc4d`。

**状态：源码修订及回归用例已交付；静态检查通过，编译和运行验证待补。** 保留前两轮全部成果；版本保持 1.0.0，iOS 最低版本保持 13.0。范围为 clear/give/kill/summon/effect。

## 本轮修订

### 1. 双端 give：不能将背包列表下标当作 Slot

旧代码在找不到指定 Slot 时，若指定数字小于列表长度，就替换该下标的物品。例如 Inventory 只有 Slot=5、Slot=9 两项，执行 `give @s 0 minecraft:diamond 3 NULL` 会替换原 Slot=5 物品，而不是向空闲的 Slot=0 添加物品。

Auto 旧逻辑只识别已经写入列表、Name 为空的槽位，无法把未记录的槽位视为空闲；缺少这些空记录时可能直接覆盖最后一项。

双端修改为：优先按实际 Slot 查找；目标不存在则添加，只有条目本身没有 Slot 时才保留原有按下标处理方式。Auto 从 0～35 选择第一个未占用槽位，包含列表中缺失的槽位；36 个槽位全占用时仍按原规则覆盖 Slot=35。

### 2. 双端 give：命令控制字段保留标准名称

附加 NBT 的 `name`、`count`、`slot`、`waspickedup` 等大小写变体原先会替换标准标签名。即使命令随后恢复字段值，写出的名称仍可能是小写。

恢复命令控制字段时，现统一写出 `Name`、`Count`、`Slot`、`WasPickedUp` 的标准名称和命令参数对应值。其他自定义标签保留；Count 现有 Byte/Short/Int/Long 选择规则未改变。

### 3. iOS give：跳过全部目标时不再报告世界已修改

对于没有可写 Mainhand 的实体，give 会跳过并报告数量。Windows 原来已经按实际写入返回 ChangedWorld；Swift 外层则固定返回 true，导致交互会话/GUI 错误进入未保存状态。

Swift give 现返回消息和实际修改标记，由成功修改的玩家/实体数量决定 changedWorld；没有写入时返回 false。保留不为实体凭空创建 Mainhand 的原规则。

以上问题由源码数据流定位，**本环境未取得修复前失败、修复后通过的动态记录**。

## 五个命令检查结果

| 命令 | 本轮核对内容 | 结果边界 |
| --- | --- | --- |
| clear | 目标解析、递归物品容器、交易容器排除、无可清除容器报错 | 源码核对；本轮未改生产逻辑 |
| give | Slot/Auto、缺失槽位、Mainhand 限制、数量编码、附加 NBT、修改标记 | 修订上述三类问题并补充用例；运行待补 |
| kill | 创造模式开关、玩家生命值、非玩家实体删除、无目标错误 | 源码核对；本轮未改生产逻辑 |
| summon | Float 范围内的有限坐标、default、受保护标签、UniqueID 分配及创建 | 源码核对；本轮未改生产逻辑 |
| effect | give/clear/ALL、Amplifier 原始 Byte、ActiveEffects 类型检查、先准备更新再提交 | 源码核对；保留既有回归与业务实现 |

本轮未新增命令，也没有改变 give 必须提供物品标签参数的现有语法；无附加标签仍填写 NULL。没有修改选择器规则、实体存储格式、区块/结构业务和第二轮环境命令路由。

## 回归覆盖

新增 `Windows/MCBEEditor.Core.SelfTest/EntityGiveAuditTests.cs`，接入完整核心自测与 `--cli-regression` 两个入口；Swift 在 `Scripts/run_core_tests.sh` 的现有命令执行测试中增加相同场景。

两端共用五类行为用例：

1. 稀疏背包只有 Slot=5/9，指定 Slot=0 时保留原物品并新增 Slot=0。
2. 同一稀疏背包使用 Auto，选择 Slot=0，原 Slot=5/9 保留。
3. Slot=0 已占用、Slot=9 是显式空项，Auto 优先填缺失的 Slot=1。
4. 36 槽全满时只替换 Slot=35，其他 35 个物品保持不变。
5. 附加 NBT 使用控制字段的小写名称时，命令输出仍包含标准字段名、正确数值/类型，自定义 note 标签保留。

Swift 另补两项断言：有 ChestItems 但无 Mainhand、同时无 ChestItems/Mainhand 的实体，give 跳过后 changedWorld=false；其中一项同时比较原始实体记录字节未变化。

测试运行真实产品解析器、命令执行器和 NBT 编解码；数据库使用项目已有内存测试替身。这些用例即使通过，也不能替代原生 LevelDB 和游戏读档验证。

## 实际验证

- 通过 `CLI/Tests/source_audit.py`：命令、解析/执行接线及 Swift 编译输入的静态检查。
- 通过 `CLI/Tests/build_audit.py`：构建与测试入口静态检查。
- 通过 `CLI/Tests/windows_gui_overlap_click_audit.py`：原有静态检查。
- 通过 `bash -n Scripts/run_core_tests.sh` 和 `bash -n CLI/Scripts/build-apple.sh`；仅证明 shell 语法，不证明内嵌 Swift 已编译。
- 完成差异复核、测试方法调用和包文件核对。
- 尝试执行 .NET 核心回归及检查 Swift 编译器时，分别因 `dotnet`、`swiftc` 不存在而阻塞。C#/Swift 编译、新增行为用例、原生数据库、GUI、真机及 Minecraft 读档均未运行。

目标平台的验证入口：

```powershell
dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release -- --cli-regression
& .\CLI\Scripts\build-windows.ps1 -Test
```

```bash
bash Scripts/run_core_tests.sh
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
```

## 接续与未完成项

- 本轮源码修订仍需目标平台编译和上述行为回归，尤其是实际保存重开后背包和实体内容；不得标为已运行通过。
- clear/give 在 Swift 中仍沿用逐对象保存，Windows 相应命令使用批量写入。多目标命令遇到后续记录损坏时的中途写入差异，列入第 3 轮补充项；本轮没有为赶时间重构整个实体写入层。
- 第二轮的 7 项进程回归及损坏 dodaylightcycle 标签查询差异继续保留，见 `AUDIT_ROUND02.md`。
- 下一轮为第 4 轮：玩家、选择器、出生点、经验、传送和 spread。继续以当前包为基线，保留所有待验证项。

