# iOS → Windows 功能同步全量审计

本文件记录当前源码级审计结论。Windows 版世界入口采用“源存档只读 → EXE 同级 Cache 工作副本 → 导出 `.mcworld`”的桌面绿色版设计，因此 iOS 的 App 沙盒世界列表、文件共享目录扫描等平台专属入口不要求逐按钮复制；世界内部编辑能力、数据语义和可执行操作以当前 iOS 版为同步基准。

## 地图 / 框选区域

Windows 已覆盖 Y/X/Z 地图、地表/高度/矿物/生物群系/常加载/史莱姆模式、对象图层、未生成区域、动态续载、两点框选、拖边调整、区块边界对齐及六方向 PNG 导出。

框选区域高级操作已与 iOS 对齐：常加载区域编辑、区域内实体/方块实体、区域复制、方块搜索/替换、layer/storage 批量替换、生物群系、HardcodedSpawners、清空区域、重新生成区域。

区域复制区分两条路径：完整区块对齐且源/目标不重叠时直接复制 iOS 同一组原始区块记录；其它区域先快照源 SubChunk，再写 storage 0/1、biome 和 BlockEntity，因此重叠复制不会读到本次刚写入的数据。

## 区块

Windows 区块列表支持 Ctrl/Shift 多选。单区块可查询/编辑生物群系、复制区块、方块搜索/替换、HardcodedSpawners、清空、重新生成和地图定位；多选可执行搜索替换、layer/storage 替换、生物群系、常加载区域、删除 HardcodedSpawners、清空和重新生成。

`CopyChunk` 不复制普通实体、actor/digp、ticks 或 HardcodedSpawners；BlockEntity 坐标随目标区块平移，与 iOS 语义一致。

## 实体 / 方块实体

Windows 已覆盖当前维度/全部维度扫描、范围与文字过滤、NBT 查看修改、新建、复制、导入 NBT/JSON、批量删除、方块实体移动、地图定位，并补齐直接导出实体 NBT/JSON和复制坐标。

新建/复制窗口会使用当前地图/实体选择作为默认位置；复制对象时仍可点击“使用当前选中位置”覆盖模板原坐标，对齐 iOS 入口。

## NBT / 结构 / 元数据

统一 NBT 树支持搜索、修改、新增、删除、重命名、复制粘贴、单/批量导入导出、多节点批量选择，以及“复制值”“复制路径和值”。Compound 同名插入规则为：空名称生成唯一名；真正同名提示覆盖/保留/取消；同一批次内部冲突使用同一规则。

结构与元数据重命名已具备同名目标检测和确认覆盖语义；Windows 文案与 iOS 不完全相同，但操作结果等价。独立 NBT/mcstructure/JSON 与 Java Structure 转换能力保持同步。

## 常加载区域

Windows 常加载区域管理支持新增、编辑、定位、按当前区块/当前框选区域新增，以及 Ctrl/Shift 多选后的批量开启预加载、关闭预加载、删除。批量修改由 Core 一次性保存完整原生 `tickingarea_*` 记录集。

## 命令 / 世界工具

命令终端、Command.txt 预检批处理、逐命令 help、方向键历史、storage/biome、玩家/实体、时间/天气、tickingarea、structure、chunk 等保持同步。`chunk query` 包含 `IsSlimeChunk=True/False` 与 `Ticking=True/False`。

Windows 另提供桌面源世界只读工作副本、安全导出和单 EXE 运行模式；这些是平台设计差异，不改变世界编辑语义。

## 说明 / 许可证

Windows 主界面已补齐“说明与许可证”，AGPL-3.0 文本作为嵌入资源随单 EXE payload 发布。

## 冗余代码审计

已删除确认无调用的调试帮助函数、早期 compatibility wrapper、未使用二进制读写 API 和重复 UI 级容错。纹理目录的非致命 I/O 容错集中在纹理 Store；世界信息读取不再把失败静默伪装成 0。

LegacyTerrain、旧式 Entity、actor/digp、SubChunk v0-v9、Data2D/Data3D biome、未知记录隔离等继续保留，因为它们属于 Minecraft Bedrock 世界格式兼容，而不是移植阶段缓解措施。

## 当前结论

本轮重新从 iOS 控制器/操作入口与 Windows Core/WPF 两侧交叉审计后，**未发现仍未接入的世界内部编辑功能缺口，也未发现可证明无用途而仍应删除的私有成员或移植 compatibility wrapper**。

源码静态完整性：MainWindow XAML 96 个事件入口全部有实现；私有方法/字段扫描无只声明未使用候选；`Scripts/test_*.sh` 全集通过。当前执行环境没有 .NET SDK/MSBuild，因此“源码级无已知缺口”不等同于替代最终 Windows 编译验证；发布前仍必须在 Windows 运行 `Windows\build.cmd`，它会运行 Core SelfTest 后再生成最终单 EXE。
