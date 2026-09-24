# 第 2 轮：基础命令与批处理审计

日期：2026-09-21。输入为 `MCBEEditor-CLI-v1.0.0-audit-part1(1).zip`，SHA-256 为 `91ebf8d534ec9162dd635d1c153f7110db6888fe0f7ad32f7a980cb7303299f6`。

**状态：完成本轮源码检查、源码修订和测试接线；编译、真实进程及原生集成验证未完成。本包为待目标平台验证的源码交付，不是已通过全部测试的发布包。** 第一轮修改完整保留；软件版本仍为 1.0.0，iOS 最低版本仍为 13.0。

## 实际修订

Windows CLI 原先在环境命令分发前统一调用 `document.OpenDatabase(...)`。`time`、`weather`、`daylock` 的执行实际只读取或写入 level.dat，却因此依赖 LevelDB 能否打开；空/损坏 db 或缺失原生组件会阻断这些命令。Swift 对应分支没有这个依赖。

- `CLI/Windows/CliWorldCommandExecutor.cs`：在打开数据库前分发只操作 level.dat 的环境命令。
- `Windows/MCBEEditor.Core/Chunk/EnvironmentCommand.cs`：增加只接收 WorldDocument 的构造入口；保留原有接收数据库的入口。数据库访问集中到有明确错误提示的属性，tickingarea 继续要求真实数据库。
- `info` 要统计玩家、实体、区块等记录，继续读取数据库。第一轮会话生命周期、批处理提交规则、NBT/地形持久化算法均未修改。
- Swift 环境命令已有按需访问方式，本轮没有为对齐而改动其业务代码；双端使用同一新增进程回归入口。

本问题由源码调用链直接定位，**未在本环境动态复现**；不能将源码核对写成修复前失败、修复后通过。

## 五个命令与批处理核对

| 项目 | 源码核对结果 | 本轮运行验证 |
| --- | --- | --- |
| help | 两端检查未知命令并规范化目标命令大小写；预检阶段拒绝未知帮助目标 | 未运行 CLI |
| info | 查询世界元数据与数据库统计；标记为只读 | 原生集成未运行 |
| weather | 缺失 doWeatherCycle 的查询默认 1；持续时间和有限强度参数检查存在 | 新用例已写，未运行 |
| daylock | 1 写 dodaylightcycle=0；0 写 1 | 新用例已写，未运行 |
| time | Int64 范围检查、加法溢出拒绝、负数取余与按日对齐逻辑存在 | 新用例已写，未运行 |
| 全批预检 | 在创建工作副本和执行命令前完成；错误返回 2 | 新用例已写，未运行 |
| 运行错误继续 | 两端逐条捕获错误，继续后续命令，最终返回 1 | 新用例已写，未运行 |
| 一次性原位 | 只有无运行错误且包含修改时才提交来源；失败保留工作副本 | 新用例已写，未运行 |
| 另存为 | 可导出有运行错误的工作副本，仍返回失败并保留恢复副本 | 新用例已写，未运行 |
| 交互 Command.txt | 现有原生用例覆盖错误后继续、保存成功修改、最终失败，以及语法错误整批拒绝 | 现有原生用例未重跑 |

## 新增真实进程回归

`CLI/Tests/environment_smoke.py` 使用手工编码的最小 level.dat 和不含有效 LevelDB 的 db 目录，直接启动实际 CLI。它不会模拟产品执行器，也不声称覆盖真实数据库。

1. help/weather/time 只读查询不打开数据库，来源字节保持不变。
2. time 负数、day/daytime、floor/ceil，以及 weather/daylock 写入的数值和 NBT 类型。
3. `time set Int64.max → time add 1 → time query gametime → time set 7`：失败不破坏当前 Time，后续继续，另存结果为 7，退出码为 1。
4. 同一溢出序列在原位模式下不提交来源，恢复副本保留 Time=7。
5. 成功原位更新写入预期时间/天气/循环标签，db 文件保持不变。
6. 天气强度 NaN 导致整批预检拒绝，前面的 time set 不执行。
7. 未知 help 目标导致整批预检拒绝，不创建输出和缓存。

Windows `build-windows.ps1 -Test` 和 Apple `build-apple.sh host ... --test` 均接入此脚本；`build_audit.py` 检查两端接线。

## 实际验证与限制

通过：`source_audit.py`、`build_audit.py`、`windows_gui_overlap_click_audit.py`；新增/修改 Python 文件语法检查；Apple 构建脚本 `bash -n`；测试夹具编解码辅助函数自检；修改差异复核。

尝试运行新增进程回归时，启动 `dotnet` 失败：`FileNotFoundError: No such file or directory: 'dotnet'`。当前环境没有 .NET、Swift/Xcode、PowerShell、CMake。没有生成 Windows/iOS 可执行文件；没有真实 CLI、原生 LevelDB、GUI、真机或 Minecraft 读档结果。辅助函数自检不是产品行为测试，静态检查也不等同于编译。

有工具链后首先运行以下原有构建入口，它们会执行新增用例及原有测试：

```powershell
& .\CLI\Scripts\build-windows.ps1 -Test
```

```bash
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
```

## 需接续的项目

- 在目标平台运行新增 7 个场景；针对本轮基础命令路由变更，保留 tickingarea 原生集成回归，确认数据库业务仍正常。
- 损坏标签边界：当 dodaylightcycle 存在但不是整数时，Swift 的 time query 会因读取完整时间设置而报错，Windows 查询只读取 Time。源码已识别此差异，本轮未改变损坏存档处理策略；留在第 2 轮补充项，需具体夹具和动态验证。
- 按总计划，第 3 轮进入 clear/give/kill/summon/effect；上述待验证项持续保留，不能因进入下一轮而记为已通过。

## 执行记录

- 第一轮输入哈希核对通过，在独立目录制作本轮副本；原始上传包未改动。
- 决策：用户要求每轮 10 分钟内交付，本轮保留已核对的源码修订和可执行回归脚本，明确标记未完成动态验证；不等待不可用的工具链，不将其称为测试通过。
- 本轮没有添加生产阶段标记，没有提高版本号，没有删除原有源文件、测试、GUI 资源或许可证。

