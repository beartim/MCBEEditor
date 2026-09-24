# 第 12 轮：冗余代码与说明清理

日期：2026-09-24。基线 `MCBEEditor-CLI-v1.0.0-audit-part11.zip`，SHA-256：`55cc62eaebe18d5135c54cf5fd430a6471b5b88e701f0be9658a64556a0154e6`。

**状态：清理、文档校正及静态验证已交付；未运行原生编译和 GUI。** 环境恢复后重新开始本轮，按 10 分钟上限交付。前 11 轮代码与报告保留，软件版本 1.0.0 / iOS 13.0 不变。

## 清理清单与引用依据

| 对象 | 引用证据 | 处理 |
| --- | --- | --- |
| Windows BedrockWorldObjectNbtStore.SaveInPlace | 全仓仅定义和 Core.SelfTest 一处调用；实现只有 `=> Save(item, edited)` | 删除旧包装方法，自测直接调用 Save；保存逻辑未变 |
| iOS WorldMapViewController 导出范围 | minimumProjectionChunk / maximumProjectionChunk 的 X/Z 分支分别调用完全相同的表达式；轴差异已由 projectionRange 处理 | 两处三元表达式改为直接计算 |
| CLI 原生测试阶段注释 | Windows.Tests 和 iOS.Tests 共 4 条 Stage04c/Stage04d 注释；不承担构建或测试行为 | 去掉阶段前缀，保留具体测试用途与全部断言 |
| 第一轮历史记录 | FINAL_REVIEW 同时承载当前进度与旧三轮计划，CLI README 尾部仍停在第 9 轮 | 原始第一轮正文完整归档到 AUDIT_ROUND01；总览改为当前状态、报告索引、待补项 |

没有删除整份源码、测试脚本或历史报告。跨 Swift/C#/XAML/脚本/文本引用检查未给出其他安全的私有函数删除候选；XAML 事件、命令 ReadMe 生成器、编码兼容路径以及独立有价值的回归入口均保留。这里不是“全项目已无冗余”的承诺。

## 说明与检查修订

- README 与 CLI README 的当前进度统一指向 FINAL_REVIEW，避免头尾轮次漂移；旧三轮描述只保留在明确标注的历史记录中。
- COMMAND_PARITY 区分读取 v0～v9 与可写 states/storage 的实际边界；现代 255 storage、旧数字 layer0/layer1、LegacyTerrain Y 限制分别说明。
- 双端 give 均检查恰好 5 个参数：物品标签参数仍必填，无标签用 NULL。现有帮助一致，无需修改语法或无意义重写帮助。
- 说明结构 save/load 仍只有 layer0/layer1，普通实体复制未实现；修正“所有格式转换均不改变标签内容”的宽泛表述，指出 Java→Bedrock 的映射和兼容降级。
- 结构输出的受保护路径与文件/父目录冲突不被 --overwrite 绕过；同一路径重复导出允许后一次显式覆盖。多个外部文件与世界保存没有统一事务。一次只读复核发现过重复输出措辞过宽，已按双端 ValidateFiles 修正。
- 双端 CliSharedCommandStore 的固定 ReadMe 补充结构路径预检。启动重写 ReadMe、用户 Command.txt 不被创建/覆盖/删除、Textures 的 Colors.txt 优先规则与启动准备入口均保留。
- source_audit 之前只比较 Windows 帮助的命令名，无法发现正文漂移；现在三方逐条比对 inventory、Swift、Windows 的 26 条完整帮助文本。

## 实际验证

- 最新基线版本、输入哈希、ZIP 完整性和安全解压通过（479 文件）。
- `source_audit.py` 通过：26 条完整帮助、26 命令路由、142 解析 fixture、62 Swift 编译输入。
- 帮助漂移复现：在内存中仅替换 Windows help 正文，原检查仍接受，改进后触发拒绝。没有改动生产帮助文本来制造通过。
- `build_audit.py`、`gui_nbt_audit.py`、`map_projection_audit.py` 通过。
- `test_nbt_tree_cross_section.sh`、`test_windows_parity_icon_cleanup.sh` 通过；`bash -n Scripts/run_core_tests.sh` 通过。这些不是 GUI 或原生行为结果。
- 文档相对链接、JSON/项目 XML 可解析性、第一轮正文归档不丢失、全部基线文件保留及新 ZIP 完整性在交付前核对。
- 一次独立只读复核未发现代码级重要问题；文档重复输出规则已校正。
- 当前仍无 swiftc / dotnet，因此未编译 Swift/C#，未运行自测二进制、原生数据库、WPF/UIKit、签名/单 EXE 或 Minecraft 读档。低风险等价清理复用既有自测与源码门禁，没有另写镜像实现测试。

## 下一步

下一轮为第 13 轮 Windows 发布链。第 14 轮 Apple 发布链及第 15 轮最终复核继续按分轮计划执行；前 2～11 轮列明的结构、转换、地图、对象和平台待补项没有因本轮文档清理而关闭。每轮不超过 10 分钟，缺少平台时交付实际静态结果和阻塞点，不宣称发布或游戏验收通过。
