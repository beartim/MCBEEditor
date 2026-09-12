# 当前同步变更

## Windows 开发阶段编号清理

- Windows 生产源码、测试、构建日志、CI、README 与验证资料不再使用 `Step*` 编号作为类名、文件名、测试名或阶段标识。
- 原临时命令实现名称已改为功能语义名称，例如 storage/biome、targeting、entity action、environment、structure template 等。
- 历史 `CHANGES_WINDOWS_PORT_STEP*.md`、`CHANGES_WINDOWS_STEP*.md` 与 `WINDOWS_PARITY_AUDIT_STEP*.md` 已移除；当前状态统一由 `PORT_STATUS.md`、`WINDOWS_PARITY_AUDIT.md` 和本文件记录。
- 核心 SelfTest 覆盖仍保留，只删除编号式开发阶段名称。

## chunk query 史莱姆区块字段

- iOS 与 Windows 的 `chunk query` 每一行区块摘要均追加 `IsSlimeChunk=True/False`。
- 史莱姆区块判定直接使用区块 X/Z，因此指定查询尚未生成的区块时也可以返回该字段。
- Windows SelfTest 已增加输出字段断言；iOS 命令帮助同步说明。

## 删除 MCBEEditor 自身版本迁移

以下仅用于兼容旧 MCBEEditor 版本产物的逻辑已经移除：

- 地图显示偏好版本迁移/恢复；
- 早期编辑器产生的非标准 16-byte overworld `digp` 自动修复/合并；
- 旧编辑器单一 `tickingarea` 布局向原生键布局的自动迁移；
- 经验值写回时顺带清理旧编辑器私有 XP 标签；
- 为旧编辑器错误 SubChunk 写入提供的补偿性识别/修复。

对应回归测试也改为当前原则：非标准旧 MCBEEditor 私有数据不会在打开或编辑世界时被主动迁移。

保留的兼容逻辑仅针对 Minecraft Bedrock 自身世界格式，例如 LegacyTerrain、旧式 Entity(0x32)、现代 actor/digp、不同 SubChunk/biome 格式等。

## 导出安全

`.mcworld` 导出继续排除 MCBEEditor 私有设置和元数据。该行为是导出过滤规则，不属于版本迁移，目的是确保导出的世界不包含编辑器自身文件。

## 验证

- iOS 相关 Swift 文件通过 `swiftc -parse`。
- `Scripts/test_*.sh` 专项回归全集通过。
- 完整 `run_core_tests.sh` 在当前环境运行 240 秒后因执行时间上限终止；终止前已通过大量核心测试且没有功能断言失败。
- Windows 端当前环境无 .NET/MSBuild，需在 Windows 上继续运行 `Windows\\build.cmd` 完成真实编译验证。

## Windows 单 EXE 绿色运行模式

- Windows 最终发布改为 `Windows\dist\MCBEEditor.exe` 单一文件。构建脚本先发布 .NET 10 x64 自包含单文件载荷，再由原生 `/MT` 便携启动器把该载荷嵌入最终 EXE。
- 启动器在 .NET 载荷启动前把 `DOTNET_BUNDLE_EXTRACT_BASE_DIR`、MCBEEditor 工作缓存和临时导出目录统一指向 EXE 同级 `Cache`；主程序退出后等待载荷完全结束，再递归清空 `Cache`。下次启动也会先清理异常退出遗留缓存。
- `leveldb-mcpe` 原生桥与 zlib 使用静态 MSVC Runtime，最终绿色发布不要求目标机器额外安装 VC++ Runtime；.NET Runtime 也随单文件自包含。
- 程序启动后自动在 EXE 同级创建 `Textures`、`Commands` 并固定重写各自 `ReadMe.txt`；不再创建或读取用户 Documents 下的 MCBEEditor 目录。`Command.txt` 仍完全由用户管理。
- GitHub Windows 构建产物也改为只上传 `Windows\dist\MCBEEditor.exe`。

## Windows 源世界只读 / 唯一 mcworld 保存出口

- 打开世界文件夹、`.mcworld` 或 ZIP 时，先复制/解压到 `Cache\Worlds` 的临时工作副本。`WorldDocument`、LevelDB、NBT、命令、方块、实体、区块等所有写入只针对该工作副本。
- 原始世界文件夹/归档永不作为写目标。工作副本修改通过 mutation callback 标记为“未导出”，切换世界或关闭程序前会提示是否丢弃。
- 主页“导出 .mcworld”是世界编辑结果唯一持久化出口；程序禁止覆盖原始世界归档、禁止导出到原始世界文件夹内部，也禁止导出到 `Cache`。
- 原世界管理列表及打开/删除/复制/重命名列表项工作流已移除；主页直接提供打开世界文件夹、打开 `.mcworld/ZIP`、NBT/mcstructure 工具、导出 `.mcworld` 与重新读取源存档。
- “编辑所选方块”入口只保留在地图右侧“方块 NBT”面板；地图其它工具栏入口已删除。
- 世界内部编辑窗口的“保存”语义改为“应用到工作副本”；独立 NBT/mcstructure 文件工具仍按独立文件自身的导入导出语义工作。

## chunk query 常加载字段

- iOS 与 Windows 的 `chunk query` 每行最终格式统一追加 `IsSlimeChunk=True/False · Ticking=True/False`。
- `Ticking` 按维度与标准 `tickingarea_` 矩形/圆形区域判断，即使目标区块尚未生成仍可计算。
- Windows Core SelfTest 与 iOS 专项脚本均增加该字段回归检查。

## Windows 顶部布局与 CMD 式命令终端

- Windows 主窗口顶部改为两层响应式布局：世界名称/源路径独立显示，世界打开、NBT 工具、导出与重新读取操作放到下一行，避免世界标题和操作按钮相互挤压。
- 地图顶部参数、纹理/渲染工具和地图操作提示改为可换行布局；缩放/框选/区域/刷怪/常加载工具也独立于说明文字，窄窗口下不再强行挤在一行。
- “重新读取工作副本”更名并改造为“重新读取源存档”：重新从原始世界文件夹或原始 `.mcworld`/ZIP 创建新的 Cache 工作副本。存在未导出修改时仍先确认是否丢弃；不会执行 Commands/Command.txt。
- 命令页改为 cmd 风格：输出在上、底部始终显示 `>` + 真正 TextBox 输入光标。方向键 ↑/↓ 浏览命令历史，←/→ 由 TextBox 原生处理光标移动；输入支持标准选择、剪切、复制、粘贴与 Ctrl/Shift 键行为。
- 命令输出改用只读 RichTextBox，保留逐行颜色，同时允许任意文本选择、Ctrl+C 与右键复制/全选。滚轮按像素小步滚动，不再按 ListBox 整项跳动。
- Command.txt 批处理期间只锁定其它栏目和输入/执行按钮，输出区保持可滚动、选择和复制。
- Windows `help` 使用独立逐命令帮助目录，顺序和每个命令的说明/示例均直接同步当前 iOS `WorldCommandParser.usage`；`clear`、`give`、`kill` 等不再返回整组 EntityAction Usage。EXE 同级 `Commands/ReadMe.txt` 也使用同一帮助目录生成，避免两处再次失配。

## Windows X/Z projection + CMD interaction refinement

- Fixed the hidden-ungenerated X/Z path so missing front SubChunks no longer truncate the normal 128-block projection.
- Compressed the Windows title/map control area to leave more vertical room for the map.
- Command history now reliably fills the input with Up/Down, completed commands jump to the newest output, and parser usage failures are normalized to the exact single-command iOS help text.
- Unknown command and leading-slash errors now match iOS text.


## iOS command arrows + Windows PNG range parity

- iOS `WorldCommandViewController` 在键盘按钮左侧加入 ↑/↓/←/→ 四个按钮。↑/↓ 使用与 Windows 相同的会话命令历史和草稿恢复语义，←/→ 移动 UITextField 实际 caret；终端镜像输入拆成 caret 前/后两段以显示真实位置。
- `Scripts/test_photo_export_tabs_keyboard.sh` 增加四个方向按钮与处理器回归断言。
- Windows `MapExportOptionsWindow` 增加 x1/z1/x2/z2、四个 ±∞ 和六方向导出范围。
- Windows Y± 对指定矩形做精确导出；X±/Z± 将对应坐标区间作为明确投影范围，并从已加载 SubChunk 自动求垂直范围。
- `BedrockCrossSectionRenderer.Render` 新增可选显式投影最小/最大坐标，仅供导出路径覆盖 Live View 的默认 128/当前区块规则；默认调用语义不变。
- 大范围 PNG 会自动降低 px/方块，最长输出边控制在 4096 像素，避免高分辨率导出造成过量内存占用。

## Windows NBT 批量操作 + PNG 未生成区域同步

- Windows 统一 `NbtEditorWindow` 增加多节点批量选择、全选/取消全选、复制所选、导出所选、删除所选；普通粘贴入口同时支持单标签和连续多根批量剪贴板。
- 批量删除会折叠父/子重复目标，并禁止删除根节点或受保护标签；修改仍需“应用 NBT”写入 Cache 工作副本。
- Windows PNG 导出窗口新增独立玩家/实体/方块实体/HardcodedSpawners/村庄/出生点/网格开关，以及“透明 / 空气 / 纹理”未生成区域模式。
- 透明模式输出真实 PNG Alpha；Y 使用实际已加载 Chunk 掩码，X/Z 使用所选剖面实际 SubChunk 掩码；导出状态不再依赖地图页实时未生成开关。
- 重新审计确认当前 iOS 玩家编辑器也是通用 NBT 树，玩家背包/装备专用 UI 不再作为 Windows 同步缺口。


## Windows NBT 冲突 / 单 EXE 图标 / 移植清理

- `NbtEditorWindow` 的 Compound 粘贴/导入不再对真正同名标签自动改名，改为与 iOS `NBTEditingUI` 一致的“覆盖 / 保留 / 取消”；空根名称仍生成 `导入的标签`、`导入的标签 2` 等唯一名称。
- 最终 `MCBEEditor.exe` 的外层原生 PortableLauncher 与内层 WPF payload 都嵌入同一个 Windows ICO。ICO 来自 iOS 1024×1024 AppIcon，仅把与画布边缘连通的白色背景改成透明，图案本身不重绘。
- 删除地图普通渲染/PNG 导出路径对纹理重载的重复静默异常包装，把“纹理目录不可枚举时保留上次结果”的非致命策略收口在纹理 Store 内，避免同一缓解逻辑散落在 UI 调用点。
- `WINDOWS_PARITY_AUDIT.md` 更新为当前已知 iOS→Windows 功能缺口清零。

## Windows 全量 parity / dead-code 再审计

- 重新按当前 iOS UI/Core 对 Windows 做全体审计，发现上一轮“缺口清零”结论过早，并补齐区块单项/批处理、框选区域复制/清空/重生成/常加载、实体导出/复制坐标、NBT 复制值/路径、对象创建“使用当前选中位置”、tickingarea 批量预加载/删除和“说明与许可证”。
- 区块/区域复制共享 BlockEntity 坐标平移工具；区域复制按 iOS 的整区块快速路径与重叠安全快照路径实现。
- 删除无调用的 StateSummary、GetCurrent、PlanCopyBlock、ValidateImportDocument、早期 ReplaceByName wrapper、无调用 BinaryData UInt API 等；收敛纹理/地图选择等重复外层容错。
- WorldInfoService 不再静默把数据库/文件系统读取失败伪装为 0；局部损坏 Bedrock 记录隔离和旧世界格式兼容继续保留。
- 新增 `Scripts/test_windows_full_parity_audit.sh`；MainWindow 96 个 XAML 事件均有实现，私有成员扫描未发现只声明未使用候选，当前 `Scripts/test_*.sh` 全部通过。
