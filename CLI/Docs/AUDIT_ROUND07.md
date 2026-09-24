# 第 7 轮：区域与区块命令审计

日期：2026-09-23。输入 `MCBEEditor-CLI-v1.0.0-audit-part06.zip`，SHA-256：`3da48d0678c6adb10eaab09a2366441801782f8b51beaf147aea3d8d9a9c7016`。

**状态：源码修订和回归用例已交付，静态检查通过；原生编译、行为回归、保存重开与游戏读档待目标平台验证。** 本轮按 10 分钟上限收口，完整保留前 6 轮成果，版本仍为 1.0.0，iOS 最低版本仍为 13.0。

## 修订

1. Swift clone 原先将 BlockEntity 按坐标转成字典，会覆盖重复记录、丢弃无法定位的记录，随后重写目标区块。现在独立规划实体操作：从原始源记录取得快照，源选区同坐标存在多条记录时拒绝；目标仅移除选区内记录，保留选区外重复记录、无法定位记录及其顺序。实体解析和编码在最终数据库批次前完成；当前解码器仅支持单根 VarInt 回退，因此 Swift clone 遇到需要拼接多个 VarInt 根时拒绝且不提交，新增整库不变断言。结构导入导出的旧字典路径仍留第 9 轮处理。
2. Swift clone 复制时更新已有 DimensionId / dimension 字段，并使用可容纳坐标的 Int/Long 标签，避免继承源 Byte/Short 类型后限幅。保留原有全部 storage、重叠 X/Y/Z 源快照、旧格式转换及提交机制。Windows clone 已有重复源拒绝及目标记录列表路径，本轮未修改该实现。
3. 双端圆形 tickingarea 查询先比较各轴与半径，再计算距离平方，避免极端区块坐标的平方和溢出；Swift 地图选区相交计算同样处理。
4. 双端矩形 tickingarea 数量在极端 Int32 范围下安全饱和到各自返回类型最大值，避免乘法溢出、负值或零值绕过数量判断。正常小范围计数不变。

上述判断来自源码数据流审查；由于工具链缺失，未取得修订前失败、修订后通过的原生测试记录。

## 检查范围

- clone：检查双端源快照、目标多余 storage 清空、跨维度实体迁移和批次提交。新增 Swift 用例覆盖重叠源快照、三层 storage、目标原实体替换、外部重复及无坐标记录保留、跨维度坐标/维度更新、重复源拒绝且整个内存数据库不变。
- chunk：核对 query 排序和状态字段、empty/regenerate 的区块及关联 actor/digp 处理和批次边界；本轮未作源码修改，复杂共享 actor 关系、真实 LevelDB 保存重开仍待验证。
- fillbiome：核对 Data3D 优先、Data2D 字节范围拒绝和高度适用差异，以及写入前的批次规划；本轮未作源码修改。已有 Data2D/Data3D 测试保留，未宣称运行通过。
- tickingarea：检查圆形/矩形与同名覆盖路径，保留既有用例；新增 Swift 和 Windows 极端坐标包含判断及超大矩形计数用例，Swift 另覆盖选区相交。

Windows 新增 `Windows/MCBEEditor.Core.SelfTest/RegionAuditTests.cs` 并接入完整自测与 `--cli-regression`。Swift 新增并调用 `verifyRegionAudit()`，位于现有 `Scripts/run_core_tests.sh` 命令执行测试内。测试使用项目已有内存数据库和产品编解码路径，不替代真实 LevelDB 或 Minecraft 读档。

## 实际验证与后续

- `CLI/Tests/source_audit.py` 通过：26 命令、142 解析 fixture、62 Swift 编译输入及接线检查。
- `CLI/Tests/build_audit.py`、`CLI/Tests/windows_gui_overlap_click_audit.py` 通过。
- `bash -n Scripts/run_core_tests.sh`、`bash -n CLI/Scripts/build-apple.sh` 通过。shell 语法通过不代表内嵌 Swift 已编译。
- 本轮确认环境无 `swiftc` 和 `dotnet`；新增用例与已有原生测试均未运行。未生成可执行发布包。
- 源码 ZIP 与第 6 轮归档逐文件比较，保留原文件清单，校验归档可完整读取。

目标平台应运行 `bash Scripts/run_core_tests.sh`、`bash Scripts/test_fillbiome_info_xz_selection.sh`、`dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release -- --cli-regression`，并验证 CLI 导出后重开及游戏读档。第 2～6 轮登记的差异和未验证项继续保留。

剩余专项：第 9 轮处理 structure 的实体整理与坐标类型；连续 NBT 的 VarInt 多根兼容需要专项核对，不能据本轮普通小端 NBT 用例认定已兼容。下一轮为第 8 轮独立 NBT 转换，每步仍不超过 10 分钟；第 13～15 轮补平台构建和最终验收，不自动勾选未执行项目。
