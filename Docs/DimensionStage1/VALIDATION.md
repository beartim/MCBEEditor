# 第1轮验证记录

日期：2026-10-04。状态：计划和数据分析完成；dimension 命令尚未实现。

## 实际检查

- 原始源码 ZIP 583 条目；所有原运行时代码按字节保留。
- 示例 CURRENT 指向 MANIFEST-000018；两条 VersionEdit 得到三个活跃表 000014/000016/000019。
- 所有读取的 manifest 记录、SST index/data block 均通过 CRC32C；按 sequence 和删除墓碑合并后共 696 个有效用户键。
- DimensionNameIdTable.entries 为三个 Int32 自定义映射；三个命名根和 Overworld 均成功解码小端 NBT且无尾部。
- 主世界有 263 个含已识别区块记录的坐标、575 条区块记录；1001 有 2 个坐标、14 条区块记录。1000/1002 为已登记零区块维度。
- digp 有维度 0 和 1001 的记录，但 actor 引用列表均为空；actorprefix 为零。本样例不能代替实体删除、常加载区块、村庄和玩家引用的测试，后续需合成向量。
- level.dat 声明与实际 NBT 消耗均为 3078 字节，未在其中找到自定义维度表。
- 已定位 Swift/C# 区块键优先检查第8字节导致长格式 ID 低字节碰撞；parseDimension、spread、tickingarea 均存在原版限定。

## 复现命令

将 Tests/Fixtures/custom_dimensions.mcworld 解压到临时目录后：

```bash
python3 Scripts/Dimension/probe_fixture.py /absolute/path/to/unpacked-world --output /absolute/path/to/report.json
```

脚本为只读规划工具：适用于此无 WAL 的样例，支持 CURRENT/MANIFEST、活跃 SST 表、Snappy/zlib block 和普通小端 NBT。不是生产数据库读取器；不支持 WAL、加密/未知压缩或网络 NBT。不得用作软件运行时数据库实现。

## 未运行的项目构建

当前环境没有 swift/swiftc、dotnet、cmake。第一轮没有运行时修改，因此不声明新增功能或编译通过。后续编译验证应运行现有 Swift 核心测试、dotnet run --project Windows/MCBEEditor.Core.SelfTest 和 dotnet test CLI/Windows.Tests，并记录真实结果。
