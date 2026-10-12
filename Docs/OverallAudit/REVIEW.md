# 本轮问题与清理记录

2026-10-12，针对当前完整四端源码进行命令/格式/GUI 三个模块的独立审查、生产路径复现与最终差异复核。修改依据实际行为与调用路径，不按文件体积或单个文本引用数删除代码。

| 问题 | 修复与验证 |
| --- | --- |
| 同名维度映射到多个 ID | 双端 snapshot 在创建命令上下文前拒绝歧义；避免 Swift 字典 fatal 和 C# ToDictionary 异常。非法记录保持原字节且无批写入。 |
| C# 畸形集合提前大量分配 | NBT List/IntArray/LongArray 按编码与元素最小字节验证剩余输入，先拒绝再分配；三种编码及合法空集合回归。 |
| C# Java 结构尺寸乘法溢出 | 在第二次乘法前按最大体积做除法界限检查；`1073741824×1073741824×16` 不再绕过限制。真实 CLI 另验证旧输出不被覆盖。 |
| 双端 CLI 对无关命令应用文件路径引号解析 | 只对 structure import/export 使用路径 tokenizer；合法 MCBE-SNBT 字符串 `O'Brien` 交给命令原解析器。263 个共享样例及真实 setblock/summon 保存重开。 |
| Swift 玩家当前位置被显示为出生点 | 玩家根不再以 Pos 回退为 spawn；嵌套真实 Respawn 的 Pos 保持可读；clearspawnpoint 后不出现虚假标记。 |
| Swift 全 -1 结构意外生成空气区块 | 两层均无写入的坐标跳过；只初始化实际需写的区块；返回真实 changed 标志。实际 executor 在远端未生成区块载入全 mask，数据库与 dirty 状态不变。 |
| iOS 方块实体坐标修改只迁移 NBT | 先完整规划全部 terrain storage 与 NBT，最后单次同步批提交；跨区块/维度和同切片保存保留编辑值及兄弟记录。兼容数字格式/0x34/LegacyTerrain/v1，未知/冲突/不兼容拒绝前不写入；无地形或全空气源继续允许原有 NBT-only 移动。 |
| iOS X/Z 地图定位仍用旧剖面 | 玩家/对象共用位置准备方法，更新切片 X/Y/Z 与 Y 输入；三原版维度行为回归。 |
| 不支持的地图维度无提示或误用原版地图 | iOS 对象/玩家/方块请求与 Windows 对象/区块入口统一明确拒绝；所有命令的任意维度支持保持。 |
| Windows 定位先触发旧中心渲染、busy 时丢操作 | 程序修改维度控件时抑制事件；等待期间合并为一条最新渲染请求；半径/视口参数等待后再消费；地形结果过时就跳过。覆盖首次渲染和多次控件变化。 |
| Windows 图层开关在 busy 时漏刷新 | 图层单项和全开/全关接入同一队列，覆盖 terrain 和 marker await 阶段；marker/feature 读取完成后不发布已有更新请求对应的过时结果。 |
| Windows 旧区块定位 continuation 覆盖新目标 | 复用现有 interaction version，定位和控件变化更新版本，await 后只让仍有效的区块定位设置选择与详情。区块→实体与区块→区块两种交叠回归。 |
| Windows 本地玩家默认中心遗漏自定义维度保护 | 初始化也先核对地图维度，再更新中心；维度 3 保留出生点回退，三原版维度及负浮点 floor 结果不变。 |

独立最终审查报告无 Critical，提出最后三项 Important（图层、过时定位 continuation、本地玩家默认维度）；主实现逐项运行新增用例观察失败，再修复并运行完整 Windows headless 导航回归和 WPF 交叉编译。原失败分别在 `logs/map-layers-red.log`、`map-navigation-race-red.log`、`map-initial-dimension-red.log`，最终成功输出在 `logs/map-windows-final.log`。其他本轮失败证据也保留；名称包含 `red` 的日志是修复前的预期失败，不是当前未解决的失败。

方块实体迁移曾考虑直接禁止更改坐标；该处理违背已有自由编辑 NBT 与任意 id 的契约，未采用。当前迁移只在源实际有方块时联动地形，测试明确覆盖孤立/空气方块实体保留既有行为。

## 有依据的重复逻辑清理

- Swift 方块实体模板根坐标在 parse 入口已过滤，document 写入不再重复过滤；全项目只有 parse 创建该 template，原有坐标及嵌套标签回归通过。
- 两端 CLI 删除文件 tokenizer 后的重复根命令/子命令判断，路由前完成判定。
- Swift 实体创建的现代存储返回分支在无条件同值 return 前，删除该无效分支。
- iOS 玩家/对象地图中心及切片设置合并到一个位置准备方法，避免分支再次遗漏切片参数。

2230 个生产 Swift/C# private/fileprivate 函数声明按全项目源码/测试/脚本/XAML 的单词引用扫描，没有“仅声明”候选；另核对 95 个 XAML handler、Swift @objc selector、生命周期、条件编译与编译输入。本轮未发现足够证据支持删除其他生产函数。这个扫描是候选筛查，不证明没有间接引用或所有逻辑都能被执行覆盖；原始报告见 `logs/private-references.json`。

## 交付差异范围

生产修改位于双端 DimensionStore、C# BedrockNbtCodec/JavaStructureConverter、双端 CLI structure 文件路由、Swift WorldCommand/WorldCommandExecutor/PlayerNBTStore/BedrockWorldObjectNBTStore/WorldMapViewController，以及 Windows MainWindow。测试入口和行为回归随源码保留；没有改动版本/iOS 最低要求、六份 ReadMe 固定快照、目录对照快照及原存档样例。
