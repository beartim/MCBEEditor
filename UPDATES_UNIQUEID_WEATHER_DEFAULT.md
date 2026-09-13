# Windows 实体 UniqueID 与双端天气查询更新

## Windows 实体 UniqueID

- 实体 NBT 编辑窗口允许直接修改 `UniqueID` 数值，修改方式与 iOS 一致；删除、重命名及批量删除该标签仍受保护。
- 保存前检查非零有效值，并检查现代 Actor 与旧式 Entity 记录中的 NBT UniqueID 是否重复。校验失败不写入数据库。
- 改号只修改实体 NBT，保留原始 `actorprefix` 键与 `digp` 的 8 字节存储引用。同时修改坐标或维度时，沿用原始引用完成区块归属迁移。
- 旧式连续 Entity 记录使用修改后的 UniqueID 检查目标区块冲突，保留其余实体和目标记录的编码。
- 每次应用成功后，窗口重新取得已保存实体的身份、坐标与记录位置，支持继续修改、保存。

## iOS / Windows 天气查询

- `weather query` 在 `doWeatherCycle` 标签缺失时输出 `doWeatherCycle=1`，与天气界面默认开启的自动变化开关一致。
- 已存在的 `0` 和 `1` 按原值输出；其他天气标签缺失时仍输出 `NULL`。
- 查询不会补写标签或更改 `level.dat`；双端帮助和 Commands/ReadMe 说明同步更新。

## 验证

- .NET SDK 10.0.401：Windows WPF 工程 Release 编译成功，0 警告、0 错误。
- Windows `MCBEEditor.Core.SelfTest` 通过。新增实体回归覆盖 Int64 边界、重复 ID、无效值、旧式连续记录、原始 Actor 引用保留、跨区块/维度迁移及刷新实体后的连续保存。
- Swift 6.2.3：编译并运行 `Scripts/run_core_tests.sh` 中的完整世界命令执行器测试段，通过天气默认值、UI 开关语义一致和查询前后文件字节不变的验证。该段后续的现代 Actor、旧版存储及元数据回归也通过。
- `Scripts/test_shared_command_file.sh` 通过：固定 ReadMe 与命令帮助一致，相关 Swift 源文件语法检查通过。
- 未进行 Windows 图形界面实机操作、Xcode/iOS 整包构建或 Minecraft 游戏内读取测试。

可在对应构建环境重跑：

```sh
dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release
dotnet build Windows/MCBEEditor.Desktop/MCBEEditor.Desktop.csproj -c Release -p:EnableWindowsTargeting=true
bash Scripts/run_core_tests.sh
```
