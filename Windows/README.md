# MCBEEditor Windows

MCBEEditor Windows 版面向 **Windows 10/11 x64**，使用 C# / WPF、.NET 10 和 Bedrock `leveldb-mcpe` 原生数据库桥。应用版本保持 **1.0.0**，功能语义以当前 iOS 版为基准同步。

## 构建

需要：

1. Windows 10/11 x64
2. .NET 10 SDK
3. Visual Studio“使用 C++ 的桌面开发”工作负载（MSVC + CMake）
4. 首次构建可访问 GitHub，以获取 `Amulet-Team/leveldb-mcpe 0.8.0a8` 和 `madler/zlib v1.3.1`

运行：

```bat
Windows\build.cmd
```

构建流程会准备原生 LevelDB 桥、运行 `MCBEEditor.Core.SelfTest`、发布自包含单文件载荷，并把载荷嵌入便携启动器。最终发布目录严格只保留一个文件：

```text
Windows\dist\MCBEEditor.exe
```

目标机器无需单独安装 .NET 或 VC++ Runtime。运行后会在 EXE 同级按需创建 `Textures`、`Commands` 与临时 `Cache`；程序完全退出后 `Cache` 会自动清空。

原生依赖已经构建时可使用：

```powershell
.\build.ps1 -SkipNative
```

## 当前能力

- `level.dat`、Big/Little Endian 与 Bedrock VarInt NBT 读写。
- Mojang/Bedrock LevelDB x64 原生桥；Bloom filter、block cache、write buffer、zlib/raw-deflate 配置与 iOS 数据层保持一致。
- SubChunk v0–v9、LegacyTerrain、现代 palette、legacy 数字 ID、多 storage、未知未来版本保留。
- Y/X/Z 地图、地表/高度/矿物/生物群系/常加载/史莱姆等模式、动态视口、对象图层、未生成区域纹理和六方向 PNG 导出；PNG 范围支持两组 `(x,z)`、四个 ±∞ 边界以及自动大图降采样。
- 玩家、实体、方块实体、村庄、HardcodedSpawners、结构、区块与数据库浏览；实体可直接导出 NBT/JSON、复制坐标和定位地图。
- 完整 NBT 树编辑、搜索、导入导出、独立 NBT/mcstructure/JSON 工具与 Java Structure 转换。
- 方块/区域编辑：`getblock`、`setblock`、`fill`、`clone`、storage、biome、单/批量区块复制与管理、框选区域复制、搜索替换、常加载、HardcodedSpawners、清空/重新生成。
- 实体与世界命令：目标选择器、传送/分散/经验、物品、效果、实体创建删除、时间、天气、常加载区域、structure 等。
- `chunk query` 每行输出生成情况以及 `IsSlimeChunk=True/False` 与 `Ticking=True/False`。
- EXE 同级 `Commands\Command.txt` 批处理与黑色 CMD 风格命令终端；输出可选择/复制，底部 `>` 输入支持方向键历史和标准文本编辑，`help` 内容逐命令与 iOS 同步；启动时自动创建 `Commands\ReadMe.txt`。
- 主页直接打开世界文件夹或 `.mcworld`/ZIP。程序先复制/解压到 EXE 同级 `Cache` 临时工作副本，所有编辑只作用于工作副本；“重新读取源存档”会丢弃当前工作副本并从原始来源重新复制/解压；源世界始终不修改，主页“导出 .mcworld”是唯一持久化出口。
- EXE 同级自动创建 `Textures` 与 `Commands`，不再创建或读取用户 Documents 下的 MCBEEditor 目录。主界面“说明与许可证”内置 AGPL-3.0 文本。

## 数据兼容原则

MCBEEditor 只保留 **Minecraft Bedrock 世界格式本身**所需的兼容读取/写入，例如 LegacyTerrain、旧式 Entity、现代 actor/digp、不同 SubChunk 和 biome 格式。不会因为 MCBEEditor 自身版本更新而在打开世界时执行应用版本迁移或修复旧版编辑器私有状态。

导出 `.mcworld` 时会排除 MCBEEditor 私有设置/元数据，防止编辑器自身文件进入导出的世界；该过滤仅影响编辑器私有路径，不影响普通世界资源。

## 写入与便携运行

- 原始世界文件夹、原始 `.mcworld`/ZIP 只作为输入来源；所有编辑都发生在 EXE 同级 `Cache\Worlds` 的临时副本中。
- 导出时禁止覆盖原始世界文件、禁止写入原始世界文件夹内部，也禁止导出到 `Cache`；只有主页“导出 .mcworld”会产生可长期保存的新文件。
- `Textures`、`Commands` 与各自 `ReadMe.txt` 位于 EXE 同级；缓存、单文件运行时解包和临时导出文件统一位于 `Cache`。
- 主程序退出后外层便携启动器等待进程完全结束并递归清空 `Cache`；下次启动也会先清理异常退出遗留缓存。
- 现代/旧版 Minecraft 格式写入仍会先做结构与目标范围验证，多记录操作尽量使用单次 WriteBatch。

## 自测

`MCBEEditor.Core.SelfTest` 覆盖 NBT 编码、DB key、SubChunk/LegacyTerrain、地图/剖面、方块与区域事务、对象/实体存储、命令、结构、便携工作副本与 `.mcworld` 导出、独立 NBT 转换、地图动态采样和 X/Z 投影等核心路径。构建脚本会在生成最终单 EXE 前自动运行这些回归测试。

更详细的当前同步状态见根目录 `PORT_STATUS.md`；尚未同步项目见 `WINDOWS_PARITY_AUDIT.md`。
