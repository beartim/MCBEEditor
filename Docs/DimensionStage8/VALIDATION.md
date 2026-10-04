# 任意维度命令最终验证

日期：2026-10-04。验证针对最终恢复、修正后的完整源码。原始样例只读保留；实际删除、写入与导出验证仅使用工作副本或内存数据库。

## 交付内容

- `dimension query`：合并登记表、原版根、区块和 digp，列出实际存在的维度；已登记零区块维度仍可见，未知区块标签也可发现。
- `dimension add 名称 ID`：支持 namespace 和普通名称、完整有符号 Int32；缺失原版维度可按 overworld=0、nether=1、the_end=2 建立；冲突或非法输入无写入。
- `dimension empty 名称或ID`：清空目标可归属区块、实体与相关内容，保留维度根/登记。未登记的数据维度清空后获得持久化名称。
- `dimension purge 名称或ID`：删除内容、根与登记，处理玩家及维度时钟引用；无安全迁移目标时拒绝。之后允许重建同名同 ID。
- entity、chunk、clone、fill、fillbiome、getblock、setblock、storage、structure、spawnpoint、teleport、summon、tickingarea 的维度参数接受当前存档精确登记名称或 Int32 ID；原版别名大小写不敏感。spread 的随机维度候选来自实际存档。
- CLI 与 GUI Command.txt 先用纯内存维度投影校验整批命令，支持 add 后立即操作新名称、purge 后重建。预检失败不开始执行；运行时错误仍采用已有逐条执行规则，每次维度修改独立原子提交。
- 版本号 1.0.0、iOS 13.0 最低要求及 Windows GUI 导出 .mcworld 的保存方式保留。

## 实际执行结果

环境为 Linux；使用真实 Swift 6.2.3、.NET SDK 10.0.401 和真实 Mojang LevelDB。native 依赖固定为 leveldb-mcpe 0.8.0a8 / zlib 1.3.1。

| 检查 | 结果 | 范围 |
| --- | --- | --- |
| Swift 维度专项 | PASS | query/add/empty/purge、原版重建、共享 actor、玩家迁移、原始未知标签、村庄最长名称、冲突标签拒绝与无写入 |
| 完整 Swift 核心套件 | PASS | 原有全部核心回归，真实 CLI parser/plan 预检、世界解析/命令执行、231 共享 parser fixtures；最后 98 项 source audit 通过 |
| C# 完整 Core.SelfTest | PASS | 原有全部核心回归及维度发现、增删清空、解析、预检和安全专项 |
| C# CLI 编译 | PASS | 0 warnings、0 errors |
| CLI native integration | PASS | 44 主调用用例，以及额外 dimension/entity/summon/MCBE-SNBT 实际数据库用例；工作副本、导出重开、原始数据完整性及失败恢复 |
| CLI 共享 smoke | PASS | 293 process checks，231 parser cases，28 commands |
| 用户样例 smoke | PASS | 27 次真实 CLI 调用；空维度保留、purge、同名同 ID 重建、缺失原版重建、名称操作、43/44/47/118 与 Int32 两端、导出重开及预检失败无输出 |
| Dimension.txt 示例 | PASS | 包含在上述 27 次调用；17 条命令完整执行，空 wzn:demo=1004 保留、bear=1003 删除，导出重开一致 |
| Windows GUI 交叉编译 | PASS | EnableWindowsTargeting=true，0 warnings、0 errors |
| 源码/构建审计 | PASS | 两端帮助一致、67 个 Swift CLI 输入完整、解析与执行路由、1.0.0/iOS 13.0 配置 |
| Apple build lifecycle | PASS（模拟工具边界） | 编译、平台、架构、签名等失败不替换旧二进制的 shell 控制流；使用 tool doubles，不代表 Apple 平台构建成功 |

Swift Linux 专项和命令执行测试链接生产 parser/store/executor，使用测试数据库与文件系统边界替身；真实数据库和导出持久化测试由 C# CLI 完成。没有把替身测试计作 Apple 应用或 CLI 二进制构建。

## 原始样例完整性

`Tests/Fixtures/custom_dimensions.mcworld` 与上传的样例逐字节一致。SHA-256：

`b2b229bc4cc8c9937da461c08b5117501b12bb38791599eca5a6c7b6f63bdcd4`

每次真实样例调用后都重新核对该哈希；解包工作副本与导出结果位于独立临时目录，原始存档没有被修改。

## 平台验收待完成

- 没有 Xcode、macOS/iOS SDK：未实际构建或启动 iOS GUI、Apple CLI；Linux Swift 结果与 Apple 构建脚本源码检查不能代替它们。
- 没有 Windows 桌面运行环境：WPF 只完成交叉编译，未实机操作。两项 Windows FileShare 替换锁测试在 POSIX 按既有测试规则 SKIP，仍须在 Windows 执行。
- purge 玩家迁移使用帮助中声明的固定坐标，没有进行地形探测。
- fillbiome 修改已有的生物群系记录；新建空维度尚无该记录，生命周期示例不包含对空维度的 fillbiome。

## 回归入口与证据

- `bash Scripts/test_dimension_query.sh`
- `bash Scripts/run_core_tests.sh`
- `dotnet run --project Windows/MCBEEditor.Core.SelfTest`
- `dotnet run --project CLI/Windows.Tests -- 原生测试数据库工具路径`
- `python CLI/Tests/smoke.py --backend windows -- CLI程序`
- `python CLI/Tests/dimension_smoke.py -- CLI程序`
- `python CLI/Tests/source_audit.py`、`build_audit.py`、`apple_build_lifecycle.py`

本目录 logs/ 保存最后一次实际执行日志；审查详情及处置见 REVIEW.md。源码归档不包含临时编译器、native 产物、bin/obj 或执行缓存。
