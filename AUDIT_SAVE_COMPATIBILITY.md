# iOS / Windows 存档写入兼容性审计

基于本次上传源码修复，应用版本保持 1.0.0。

## 修复内容

1. **未生成区块／子区块的方块格式。** 空气编辑模板和新建地形同时继承实际 SubChunk 版本、调色板结构和已保存的方块版本。旧 v1/v8 的 `name + val` 保持原结构；原来没有 `version` 的旧调色板不再被强加现代版本。目标维度没有记录时，参考同一存档的其他维度。
2. **旧版空 storage。** 写出 v1/v8 时使用至少 1 bit 的 storage，避免给早期读取器写入后来才支持的 BPB=0。v9 保留其单值编码。原存档中未被修改的地形记录保持原始字节。
3. **区块元数据。** 地图编辑、命令、区域复制等共用物理写入层；新建／部分缺失的区块按需补齐 Version/LegacyVersion、FinalizedState 和可用的地形辅助记录，不覆盖现有同类元数据。修复只有 SubChunk 而缺少区块元数据的写入路径。
4. **保留数字 ID 格式。** 删除普通编辑中自动把旧数字 ID 区块升级为 v9 的分支。已知 states 可无损换算回旧数字 ID/data 或 val；不能表示的方块／层数在写库前报错。避免将新格式数据写进仍由旧版游戏使用的区块。
5. **原子写入。** iOS 的 fill/setblock/clone/storage 将待生成元数据与地形一起提交，后续校验失败时不留下提前生成的空区块。LegacyTerrain 的空模板与编辑结果合并为同一最终值。
6. **两端行为修正。** iOS 保留命令显式指定的空 storage；新层编辑模板继承数字 ID／val 格式。两端的 storage query/delete/clear 遇到缺失子区块返回 `Block not generated`，不进行写入。
7. **清理与性能。** 删除自动升级模块、无调用转换函数、重复元数据写入和复制前的重复遍历；批量写入复用已经检测出的格式，减少全库扫描。生产 Swift/C# 源码相较上传包净减少 572 行。同步修正失效的测试依赖和要求旧升级实现存在的检查。

## 实际验证

| 验证项目 | 结果 |
| --- | --- |
| Windows Core 全部自测（含新增兼容性矩阵） | 通过 |
| Windows WPF Release 编译，启用 Windows targeting | 通过，0 警告、0 错误 |
| iOS 完整可移植核心测试入口 `Scripts/run_core_tests.sh` | 通过 |
| iOS UI/App Swift 语法解析 | 通过 |
| 原末地 v1/v8 样本：Y=160/200/255、新建图层、相邻原始记录保留 | 两端通过 |
| 数字 v0/v7、v1/v8 val、v8/v9 states，新区块／缺失子区块、空图层 | 两端通过 |
| 未知／不能表示的旧格式写入拒绝、命令不留半成品、显式空层 | 通过 |
| 独立 Python 磁盘格式检查 | 30 组通过；12 组相同操作的 Swift/C# 输出逐字节一致 |
| Windows 源码检查、96 个 XAML 事件绑定、Shell 语法、项目 XML | 通过 |

完整测试还覆盖 NBT、实体、命令、区域操作、纹理、方块颜色、导入导出等原有回归项。验证日志与本次生成的字节样本位于 `Validation/`。

**验证边界：**核心行为测试通过内存数据库替身执行产品源码；本环境未运行 Windows/iOS 应用界面、原生 LevelDB 集成测试、Xcode iOS 完整打包或 Minecraft 实机存档重载。因此这些结果证明所列写入路径和磁盘结构检查通过，不等同于已在所有游戏版本中实测兼容。

## 复核方法

```bash
bash Scripts/run_core_tests.sh
python3 Scripts/verify_persistence_vectors.py Validation/windows-vectors.json Validation/swift-vectors.json
```

```powershell
dotnet run --project Windows/MCBEEditor.Core.SelfTest/MCBEEditor.Core.SelfTest.csproj -c Release
# 原有 Windows/build.cmd 构建入口保持可用。
```

将环境变量 `MCBE_AUDIT_VECTORS` 设为输出 JSON 的完整路径后，再分别运行 Windows 核心测试和 `Scripts/test_end_missing_subchunks.sh`，可重新导出写入样本；随后交给独立 Python 检查器验证。

旧式 val 调色板和初期 v1/v8 storage 位宽的格式依据：[Mojang 开发者的格式说明](https://gist.github.com/Tomcc/a96af509e275b1af483b25c543cfbf37)。版本继承同时对照了源码包自带的原始末地记录。
