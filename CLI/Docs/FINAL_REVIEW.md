# 收尾检查与后续计划

2026-10-12 整体检查已完成，本轮修复 NBT 分配/结构尺寸/维度名称边界、CLI 单引号路由、Swift 出生点和全 -1 结构、iOS 方块实体地形迁移及双端地图状态，清理确认的重复逻辑。最新结果、完整日志与平台边界见 [整体检查](../../Docs/OverallAudit/VALIDATION.md) 和 [修复记录](../../Docs/OverallAudit/REVIEW.md)。下面第 15 轮表格描述当时状态；其中全 -1 Swift 无变化写入和本轮地图问题已在最新记录中闭环，其他未扩大范围的功能/平台事项仍按各自记录验收。

后续 setblock/fill 根坐标规则已更新：方块实体根 x/y/z 可省略，输入时忽略，写入按实际目标位置生成。最新行为及四端验证见 [方块实体自动坐标](../../Docs/BlockEntityAutoCoordinates/VALIDATION.md)；下文保留第 15 轮审计时的记录与范围。

2026-09-24 第 15 轮源码审计交付，保留第 1～14 轮成果。用户取消本轮时限；软件版本 1.0.0、iOS 最低 13.0 保持。完整范围见 [分轮计划](../../docs/superpowers/plans/2026-09-21-mcbeeditor-cli-audit-plan.md)。

本轮修复 Swift 出生点递归误删嵌套标签、Windows 方块实体连续保存旧引用，并修正实际运行揭示的测试入口问题。**全部历史专项、目标平台与 Minecraft 尚未完成验收。**

## 当前实际证据

| 验证 | 结果与边界 |
| --- | --- |
| 双端核心 | 完整 C# Core.SelfTest、Swift run_core_tests.sh 通过；Linux、内存数据库及部分读取器替身 |
| C# CLI 进程 | 202 次 smoke、14 项会话、7 场景环境、46 次转换、10 次结构文件预检通过 |
| 真实数据库 | Linux C# + Mojang LevelDB 44 项通过；2 个 Windows FileShare 场景 SKIP |
| WPF | 交叉编译 0 警告/0 错误；GUI 未运行 |
| 静态/脚本 | 五项源码/GUI/构建 audits、六场景 Apple 工具替身流程、shell/Python 语法通过 |
| 独立复核 | 本轮差异无确认 Critical/Important，保留两项 Minor 测试盲点 |

详情：[第 15 轮报告](AUDIT_ROUND15.md)、[26 命令矩阵](REGRESSION_MATRIX.md)、[日志与复跑命令](Validation/round15/README.md)。续接临时目录丢失后已恢复并重新回归，交付日志来自最终执行。

## 历史报告

第 1～14 轮报告保留各轮当时的环境和验证状态；其中“缺少编译器/待运行”不能理解为本轮仍未取得任何运行证据，也不能由本轮 Linux 结果升级为 Windows/iOS 实测。

- [第 1 轮](AUDIT_ROUND01.md)
- [第 2 轮](AUDIT_ROUND02.md)
- [第 3 轮](AUDIT_ROUND03.md)
- [第 4 轮](AUDIT_ROUND04.md)
- [第 5 轮](AUDIT_ROUND05.md)
- [第 6 轮](AUDIT_ROUND06.md)
- [第 7 轮](AUDIT_ROUND07.md)
- [第 8 轮](AUDIT_ROUND08.md)
- [第 9 轮](AUDIT_ROUND09.md)
- [第 10 轮](AUDIT_ROUND10.md)
- [第 11 轮](AUDIT_ROUND11.md)
- [第 12 轮](AUDIT_ROUND12.md)
- [第 13 轮](AUDIT_ROUND13.md)
- [第 14 轮](AUDIT_ROUND14.md)

## 尚未闭环与建议顺序

| 优先级 | 专项 | 继续入口/条件 |
| --- | --- | --- |
| 高 | 命令提交一致性 | Swift clear/give 逐对象保存、双端 teleport/spread 混合目标中途失败；WorldCommandExecutor 与 Targeting/EntityAction stores，失败注入明确事务契约 |
| 高 | NBT 转换 | 显式输入编码尚未实现；双端 Standalone codec、Apple 压缩桥；压缩尾部、多成员、解压上限 |
| 高 | 结构异常输入 | 全 -1、截断/过长索引、非法位置元数据和 Swift 无变化写入；双端结构存储 |
| 高 | 平台和游戏 | Windows 发布/FileShare/单 EXE；Apple 真实编译/签名/IPA/iOS 13；同版本游戏打开与退出重进，坐标见本轮报告 |
| 中 | 命令兼容差异 | 畸形 dodaylightcycle、player_ 辅助记录识别、两端坐标范围；出生点多玩家批提交失败 |
| 中 | 格式/功能边界 | 普通 JSON 重名键、深度、超 Int64；structure 普通实体未实现、save/load 仅 layer0/layer1 |
| 中 | 地图与对象 GUI | 异步旧画面、下采样点击、巨大范围、网格/六方向 PNG；玩家/村庄并发与路径重排、独立/连续根退出、重名 Compound |
| 中 | 新刷新方法与发布 | 普通实体 RefreshedObject 直接回归、刷新失败后 GUI 恢复；Apple 报告/二进制非整体事务、平台缓存/权限/并发/竞态 |

255 storage、末地高层已取得核心及部分 Linux C# 真实数据库回读证据，游戏仍待验。Windows 方块实体连续保存核心已修复，实际 GUI 仍待验。后续专项没有因本轮测试通过而自动勾选，本轮不自动开始下一轮。

目标平台继续执行：

```powershell
powershell -File CLI/Scripts/build-windows-release.ps1 -Test
```

Windows GUI 使用 Windows/build.cmd；还须测试无预装 .NET 的最终 EXE。

```bash
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
bash CLI/Scripts/build-apple.sh ios CLI/build/apple-ios
bash Scripts/build_unsigned_ipa.sh
```

Apple 命令需匹配的 macOS/Xcode 环境。host 编译不代表 iOS 13 真机通过，ad-hoc 验签不证明设备允许执行。第 15 轮不限时仅覆盖本轮，后续时限按用户指示与原计划执行。
