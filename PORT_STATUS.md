# MCBEEditor 当前状态

## iOS

- 版本：1.0.0 (100)，最低 iOS / iPadOS 13.0，Bundle ID `com.wzn.mcbeeditor`。
- iOS 世界管理保持现有能力；Windows 改为主页直接打开世界文件夹或 `.mcworld`/ZIP，并在临时工作副本中编辑。
- 地图：Y/X/Z、动态移动缩放、地表/高度/矿物/生物群系/常加载/史莱姆等模式、玩家/实体/方块实体/出生点/HardcodedSpawners/村庄图层、未生成纹理、框选与 PNG 导出。
- 实体：当前维度/全部维度扫描、范围和半径过滤、玩家/实体/方块实体 NBT 修改、现代 actor/digp 与旧式 Entity 世界格式支持。
- NBT：世界、玩家、村庄、结构、实体、方块实体、独立 NBT/mcstructure/JSON 编辑与转换。
- 命令：方块/区域、storage/biome、玩家/实体目标、物品/效果、时间/天气、tickingarea、structure、chunk 等；支持 `Commands/Command.txt` 批处理。
- `chunk query` 输出包含 `IsSlimeChunk=True/False` 与 `Ticking=True/False`。
- 地图显示状态不跨世界持久化；导出世界排除 MCBEEditor 私有设置/元数据。
- 不再保留因 MCBEEditor 自身版本升级而执行的旧编辑器数据迁移；Minecraft 世界格式兼容逻辑继续保留。

## Windows

- 平台：Windows 10/11 x64，WPF + .NET 10；最终以单一自包含 `MCBEEditor.exe` 发布，`leveldb-mcpe` 原生桥嵌入单文件载荷。
- 用户已在 Windows 10 + Visual Studio/MSVC 环境验证原生 DLL、真实 Bedrock 世界读取/写入及核心自测运行。
- Windows 功能已覆盖：level.dat/NBT、SubChunk v0–v9/LegacyTerrain、区块管理、Y/X/Z 地图、地图图层与动态续载、Textures/Colors.txt、六方向 PNG、玩家/实体/方块实体、村庄/结构、完整 NBT、临时世界工作副本、独立 NBT/mcstructure 工具和大部分命令系统。
- 地图点击支持方块选择器和同点多对象候选选择；框选支持直接拖边调整。
- 实体栏目默认扫描当前维度实体与方块实体，并提供全部/矩形/半径/Y/文字过滤。
- 命令栏目为 iOS 风格黑色终端，支持共享 `Commands/Command.txt` 批处理。
- `chunk query` 每个区块摘要追加 `IsSlimeChunk=True/False` 与 `Ticking=True/False`。
- 地图显示状态仅存在于当前会话，不写入世界或编辑器持久化设置。
- `.mcworld` 导出过滤 MCBEEditor 私有设置/元数据。
- Windows 不再写原始世界：打开后先复制/解压到 EXE 同级 `Cache`，所有编辑仅修改工作副本；主页“导出 .mcworld”是唯一持久化出口。最终 Windows 发布物为单一 `MCBEEditor.exe`，运行时 `Textures`/`Commands` 位于同级，`Cache` 在退出后自动清空。
- 已移除 Windows 源码、测试、文档和 CI 中用于开发阶段标识的编号命名；核心测试改用功能语义名称。
- 已移除因 MCBEEditor 自身历史版本产生的偏好、错误 digp 键和旧编辑器 tickingarea 布局迁移；Minecraft Bedrock 自身的旧/新存档格式兼容不受影响。

## 仍需同步

当前已知的 iOS→Windows 功能同步缺口已清零；后续主要是少量桌面交互细节与大数据量性能收尾。Windows 的 NBT Compound 粘贴/导入现已与 iOS 一致支持“覆盖 / 保留 / 取消”。

Windows PNG 已支持独立导出图层和“透明 / 空气 / 纹理”未生成区域模式；统一 NBT 编辑器也已支持多节点批量选择、复制、导出和删除。当前 iOS 玩家编辑器本身仍是通用 NBT 树，因此专用背包/装备槽位 UI 不属于现有 iOS→Windows 同步缺口。

详见 `WINDOWS_PARITY_AUDIT.md`。
- Windows 顶部操作区和地图工具区已改为响应式多行布局；已移除重新读取源存档操作，保留打开和导出入口。
- Windows 命令页已改为 CMD 式 RichTextBox 输出 + 底部 `>` 输入，支持文本选择/右键复制、细粒度滚轮、↑/↓ 历史与 ←/→ 原生光标移动；help/Commands ReadMe 使用同一份逐命令 iOS 帮助目录。

## Current Windows fixes

- X/Z normal projection now continues through missing front SubChunks when the ungenerated layer is hidden, preserving the full 128-block negative-direction projection. Showing ungenerated SubChunks still limits projection to the current 16-block chunk.
- Windows header/map controls use a more compact vertical layout.
- Command history recall uses Up/Down before TextBox default handling; completed manual commands always jump to the latest output.
- Generic parser usage errors are rewritten to the exact single-command iOS help entry, and unknown/leading-slash errors match iOS text.

## Latest synchronization

- iOS 命令页右上角在键盘按钮左侧增加 ↑/↓/←/→：上下键调用本次运行的命令历史，左右键移动真实输入光标；终端镜像行会显示光标前后文本，因此光标位置可见。
- Windows PNG 导出改为两组 `(x,z)` + 四个 ±∞ + 六方向；无穷边界使用当前维度已加载区块边界，X/Z 使用指定范围作为投影深度，Y± 使用同一矩形范围。
- Windows 大范围 PNG 自动降低 px/方块，最长输出边不超过 4096 像素；单次精确 X/Z 坐标跨度限制为 4096 方块以保持 1:1 方块采样。


## Latest NBT / PNG synchronization

- Windows NBT 树增加批量选择、全选、复制所选、导出所选和删除所选；批量删除会规范化父子重复选择并继续遵守受保护根标签限制。
- Windows PNG 导出增加独立对象图层选项与“透明 / 空气 / 纹理”未生成显示；透明输出使用真实 Alpha，且不会改变实时地图的未生成投影规则。


## Latest parity / icon / cleanup

- Windows NBT Compound 粘贴/导入已同步 iOS 冲突语义：空名称才自动生成唯一名；同名标签统一提示“覆盖 / 保留 / 取消”，并覆盖批量内部冲突。
- Windows WPF 载荷与最终 PortableLauncher 单 EXE 共同使用 iOS AppIcon 图案；只移除原图边缘连通白色背景并保留透明 Alpha。
- 纹理重载的重复外层静默 try/catch 已移除；失败处理集中到 `BlockTextureOverrideStore.Reload()`，保持上一次成功载入结果，与 iOS 非致命纹理覆盖行为一致。
- 再次审计 Windows 源码，没有保留 MCBEEditor 旧版本迁移 shim/Step 编号实现；Minecraft 世界格式自身的 LegacyTerrain、旧 Entity、actor/digp、SubChunk/biome 兼容路径继续保留。

## 2026-09 Windows 全量同步再审计

- 区块页和框选区域高级页已补齐此前漏掉的 iOS 操作，包括区块/区域复制、搜索替换、HardcodedSpawners、批量 layer/biome、常加载、清空和重新生成。
- 常加载区域支持 Ctrl/Shift 批量开启/关闭预加载及批量删除；实体页补齐导出 NBT/JSON 与复制坐标；NBT 补齐复制值/路径和值；对象创建补齐“使用当前选中位置”。
- Windows 主界面增加“说明与许可证”，AGPL 文本嵌入单 EXE payload。
- 对移植阶段 compatibility wrapper、死代码、重复 try/catch 再次清理；Minecraft Bedrock 自身格式兼容分支不作为冗余删除。
- 当前源码级 iOS→Windows 世界内部功能审计没有已知缺口；所有 shell 回归通过。最终发布仍需 Windows `build.cmd` 完成 .NET/WPF 真编译和 Core SelfTest。
