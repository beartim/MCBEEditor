# entity 目标查询验证（2026-10-29）

基于 `MCBEEditor-command-syntax-unified-source.zip` 更新，保留前轮语法统一、ID/颜色和 kill 功能。版本保持 1.0.0，最低 iOS 13.0。格式见 [全命令对照](../../COMMAND_SYNTAX.md)，修改摘要见 [CHANGES_ENTITY_TARGET_QUERY.md](../../CHANGES_ENTITY_TARGET_QUERY.md)。

## 验证结果

| 检查 | 结果与范围 |
|---|---|
| C# 完整 Core.SelfTest | 通过；含 entity 新目标/玩家及原 >200000 结果回归，原命令/存档/结构/NBT 回归 |
| Swift 完整 run_core_tests.sh | 通过；384 条共享语法、entity/kill/召唤等执行回归及 98 项源码审计通过 |
| entity 目标专项 | 双端真实解析器、扫描器、玩家读取、执行器通过；测试数据库为项目内存夹具 |
| MCBE-SNBT 完整性 | 查询文本解码后与原 NBT 字节一致；覆盖空/嵌套/不同子列表类型、数组、Long、原始 NaN 位与 Double 精度 |
| Windows CLI 进程 | 446 次检查、384 条共享解析用例、28 命令通过；含转换与预检，不代表原生 LevelDB 集成执行 |
| CLI 路由/只读策略 | 新目标全部仍为只读，执行不要求输出文件；残缺选择器范围在宽松维度预检中明确拒绝 |
| 四份 Fixed ReadMe | 实际目录准备器通过；恢复 ReadMe，不创建或修改用户 Command.txt |
| 共享帮助 | inventory、Swift/C# help 和四份固定说明一致，源码审计通过 |
| C# CLI/测试项目 | 构建 0 警告、0 错误；--entity-query 解析与只读策略通过 |
| Windows WPF | 交叉构建 0 警告、0 错误 |
| 独立审查 | 无 Critical/Important/Minor；独立执行 C# --entity-query 与 >200000 记录回归 |

## 行为与边界

- `entity` = `entity @e`，包含玩家和普通实体，不含方块实体。@s 本机玩家，@a 全部玩家，完整 identifier 与非零 Int64 UniqueID 可进一步接维度、六坐标范围。
- 单个数字解释为 UniqueID；`entity 12345678` 返回所有同 ID 的独立记录。数字维度显式写 `entity @e 0`；原完整维度+六坐标写法保留。单个 namespaced 实体 ID 优先于自定义维度名，原版维度别名保留；命名冲突维度可写在目标后。
- 玩家维度独立于 Pos 读取；无 Pos 的记录在无范围时显示 NULL，在范围查询时排除。使用实际坐标，不添加玩家眼高。
- 合并时仅排除同一玩家存储键被扫描器当成二进制 Entity 键的重复视图，例如 9 字节的 player_42；不同记录的相同 UniqueID 不合并。
- 输出为 `类型 Dimension=名称(ID) Pos=(x,y,z) NBT=[完整标签]`。NBT 复用文件 MCBE-SNBT 无损编码，而非旧 getblock 展示格式；旧 getblock 输出不改变。
- 无匹配结果仍正常返回；损坏普通实体的扫描提示保留。数据库和 level.dat 字节、写入次数检查确认查询不写入。

## 测试修订与复现

新测试先在旧版本失败（@e 被当作维度）；短玩家键重复与旧展示格式的 NBT 往返损失均先复现再修复。最终预检发现缺少最后坐标的 @e 可能被宽松维度 resolver 当作旧维度形式，新增专用失败测试后双端修复。旧的 entity 0 数字维度用例按新要求改为零 UniqueID 拒绝，并已有 entity @e 0 正例；旧召唤回归中 entity 输出提取更新为新元数据前缀，完整字节往返断言保留。

```text
dotnet build Windows/MCBEEditor.Core.SelfTest --disable-build-servers -m:1
dotnet Windows/MCBEEditor.Core.SelfTest/bin/Debug/net10.0/MCBEEditor.Core.SelfTest.dll
dotnet build CLI/Windows.Tests --disable-build-servers -m:1
dotnet CLI/Windows.Tests/bin/Debug/net10.0/MCBEEditor.Cli.Tests.dll --entity-query
python3 CLI/Tests/smoke.py --backend windows -- dotnet CLI/Windows/bin/Debug/net10.0/mcbe-cli.dll
bash Scripts/run_core_tests.sh
python3 CLI/Tests/source_audit.py
python3 Scripts/test_fixed_readme.py
dotnet build Windows/MCBEEditor.Desktop --disable-build-servers -m:1 -p:EnableWindowsTargeting=true
```

## 平台限制

本次使用 Linux、.NET SDK 10.0.100 与 Swift 6.0.3；Swift 运行库和 legacy driver 包装均位于源码外，未改生产构建配置。Windows GUI 只做交叉编译；本轮没有启动 Windows/iOS GUI、没有 Xcode 签名构建、没有 Minecraft 游戏内读档验收。CLI 原生 LevelDB 集成用例已同步新行为并编译，本轮未运行该集成套件。继承的损坏/非支持存储格式处理仍由原扫描器与玩家存储实现。
