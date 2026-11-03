# 第 4 次小更新验证记录

日期：2026-10-28。验证代码基于上一轮 kill 范围源码，保留版本 1.0.0 / iOS 13。

| 检查 | 结果 |
| --- | --- |
| 双端新增数据／NBT 回归 | 通过：实际数字实体扫描、中文搜索、群系、13 个冰雪材质用例、freezing.Id=38、give/clear/ALL、旧版目录隔离 |
| `python3 Scripts/test_catalog_sync.py` | Swift/C# 共 572 行目录通过；全部固定来源哈希、90 个群系、143 个实体、38 个效果、3 个新版方块与5个物品事实核对通过 |
| C# 完整 SelfTest | 通过，含新增 Drop4 与既有 kill 范围回归 |
| CLI 测试项目构建 | 通过，0 警告、0 错误 |
| WPF GUI 项目交叉构建 | 通过，0 警告、0 错误；EnableWindowsTargeting=true，串行且禁用 build server |
| Windows CLI smoke | 344 项进程检查、282 个解析用例、28 个命令通过 |
| CLI source audit | 命令帮助、清单、路由与构建输入通过 |
| 固定 ReadMe 实际读写 | 四端通过，用户 Command.txt 保持原字节 |
| 新 iOS 对照入口 | 两个生产文件 Swift 语法解析通过 |
| Swift 完整核心套件 | 通过：运行至 `DROP4_FULL_SWIFT_EXIT=0`，含新增 Drop4、既有 kill、282 个共享解析用例与98项源码检查 |

新增用例先复现旧目录缺少冻尸（双端 RED），再通过实际生产组件验证更新。保留原 effect 字符串 ID/ALL 语法；38 是目录及 NBT 数值，不新增数字命令输入。

独立只读复核确认全部565条基线记录语义不变、旧版转换器和版本信息不变、三个 UI 入口均有第六项；复核未发现可执行的代码问题。

Swift 运行环境为 Linux Swift6.0.3，使用工具链自带旧 driver 处理当前沙箱的 driver 调度限制。颜色目录核对用标量 UIColor 边界替身运行原生产群系分类和 RGB 表达式，替身不替代业务分支。未进行 iOS Xcode 链接或 Minecraft 实机读档；WPF 为交叉编译，未在 Windows 启动窗口。

完整验证日志位于 logs/。来源、数值与版本限制详见 [SYNC.md](SYNC.md)。

完整 Swift 首轮发现历史源码门禁仍假定首页5项 ID 入口，已按新增第六项同步门禁后重新执行。最终记录包含完整执行追踪与明确结束状态。
