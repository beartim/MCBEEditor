# 命令语法统一验证（2026-10-29）

基于 `MCBEEditor-drop4-ID-sync-source.zip` 更新，版本保持 1.0.0，iOS 最低 13.0。全命令规则见 [COMMAND_SYNTAX.md](../../COMMAND_SYNTAX.md)。

## 验证范围

| 检查 | 结果 |
|---|---|
| C# 完整 Core.SelfTest | 通过；包含原有存档、NBT、实体、区块、结构和前轮 ID 同步回归 |
| Swift 完整 run_core_tests.sh | 通过；包含命令执行、356 条共享语法、ID/颜色和 98 项源码审计 |
| 新默认值等价 | 两端各 41 组，另验 NBT 分界、255 层、额外参数拒绝 |
| 共享语法用例 | Swift 实际解析与 Windows CLI 均 356 条通过，覆盖全部 28 命令 |
| Windows CLI smoke | 418 次进程检查通过 |
| CLI 读写策略 | 两端真实 plan/policy：12 类只读查询、11 类写命令，错误行阻止整份脚本预检 |
| Fixed ReadMe | 四个实际目录准备器通过；覆盖恢复 ReadMe 与用户 Command.txt 字节保留 |
| Windows CLI/测试项目 | 构建通过，0 警告／0 错误；新增 CLI 语法与维度回归通过 |
| Windows WPF | Linux 交叉构建通过，0 警告／0 错误 |
| 帮助一致性 | inventory、Swift/C# 两份帮助一致；四份固定快照与对应常量通过实际读写检查 |
| 独立审查 | 未发现 Critical/Important；已修正 README 旧必填描述、storage 表格误列解释句及 coverage 旧文案 |

## 默认值与执行语义

所有默认值在解析阶段转换为既有命令类型。未更改执行器写入逻辑。kill 的完整混合玩家/实体夹具新增省略开关运行，确认创造玩家跳过、其他玩家清零、非玩家删除；原有显式 0/1、闭合范围、重复 ID 与现代 actor 回归仍通过。fill/setblock 的省略方块实体通过已有真实执行夹具验证为 preserve，原记录与未提供的高层 storage 不受额外清除。

完整原语法继续有效。旧测试中将省略参数视为非法、将 Auto 大小写视为非法的断言按新规范改为默认值或大小写兼容断言，参数越界、残缺坐标、重复 NBT 与数据原子性检查继续保留。

## 复跑

```text
dotnet build Windows/MCBEEditor.Core.SelfTest --disable-build-servers -m:1
dotnet Windows/MCBEEditor.Core.SelfTest/bin/Debug/net10.0/MCBEEditor.Core.SelfTest.dll
dotnet build CLI/Windows.Tests --disable-build-servers -m:1
dotnet CLI/Windows.Tests/bin/Debug/net10.0/MCBEEditor.Cli.Tests.dll --command-syntax
dotnet CLI/Windows.Tests/bin/Debug/net10.0/MCBEEditor.Cli.Tests.dll --dimension
python3 CLI/Tests/smoke.py --backend windows -- dotnet CLI/Windows/bin/Debug/net10.0/mcbe-cli.dll
bash Scripts/run_core_tests.sh
python3 CLI/Tests/source_audit.py
python3 Scripts/test_fixed_readme.py
dotnet build Windows/MCBEEditor.Desktop --disable-build-servers -m:1 -p:EnableWindowsTargeting=true
```

本次使用 .NET SDK 10.0.100 和 Swift 6.0.3。Linux Swift 使用容器外部运行库及 legacy driver 包装；源码的生产构建配置未因此修改。

## 验证边界

Swift 执行回归链接真实解析器/执行器，数据库与平台边界沿用项目的测试夹具；Windows 核心使用项目内存数据库。Windows WPF 仅交叉编译；未在本轮启动原生 GUI，未做 iOS Xcode 签名构建或 Minecraft 游戏内读取验收。

ID/颜色目录、旧版方块转换、应用版本、前轮 kill actor 删除修复与命令执行器通过交付前原文件逐字节比较保留。构建产物和本地测试工具链不打入源码包。
