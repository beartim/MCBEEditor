# 第 15 轮实际验证矩阵

日期：2026-09-24。P 为 Linux C# CLI 的 202 次 smoke / 142 条公共解析 fixture，N 为 44 项真实 Mojang LevelDB 集成。下表 26 个根命令均通过 P，均进入 N 的实际执行路径；列出的 N 场景不意味着每个命令都有独立持久化断言，更不代表所有分支或游戏验收。

| 命令 | 实际已过场景（N，除非另注） | 主要边界/后续 |
| --- | --- | --- |
| help | 单命令帮助；P 全部帮助 | 目标平台终端布局 |
| info | 世界信息查询 | 畸形字段 |
| clear | 清除玩家物品 | Swift 多对象提交 |
| clearspawnpoint | 根出生点清除；Swift 新核心用例保护嵌套标签 | 多玩家提交失败 |
| clone | 重叠复制并导出回读 | 全部格式组合与游戏 |
| chunk | query/empty/regenerate | 巨大范围与游戏再生成 |
| daylock | 写入和回读；环境矩阵 | 畸形 dodaylightcycle 差异 |
| effect | give/clear ALL、等级 255 | 游戏实际效果 |
| experience | level/percent/query 和回读 | 玩家辅助记录识别 |
| fill | 区域写入 | 游戏多层兼容 |
| fillbiome | 数字群系写入 | 游戏实际群系 |
| getblock | End 高层查询 | 全部畸形记录 |
| give | Auto 发物品 | Swift 多对象提交 |
| kill | summon 后删除 | 异常对象与游戏 |
| kick | @a 删除并回读 | 未知辅助键族 |
| setblock | 普通及 End 新区块高层写入回读 | 游戏重开 |
| setworldspawn | 世界出生点写入 | 游戏实际出生位置 |
| spawnpoint | 玩家出生点写入 | 游戏重生 |
| spread | 可用地形执行 | 随机样本/混合目标提交 |
| storage | set/query/delete/clear、v8 255 层回读 | 索引 255 拒绝与 clear 255 不同；游戏待验 |
| structure | 六子命令与回读；10 次文件预检 | 仅 layer0/layer1，无普通实体；空结构/异常索引 |
| summon | default 猪实体 | 游戏和其他实体族 |
| teleport | 玩家整数 Y 回读 | 坐标范围差异/混合目标提交 |
| tickingarea | circle/list | 游戏常加载效果 |
| time | set/query 和回读；环境矩阵 | 畸形字段与游戏 |
| weather | query/thunder/缺省循环与回读 | 游戏天气效果 |

## 其他接口与平台

| 接口 | 实际证据 | 未覆盖 |
| --- | --- | --- |
| Swift/C# 核心 | 两个完整入口通过，含前轮命令/旧格式/高层/多层/NBT/投影/实体等专项 | 测试使用内存数据库或部分读取器替身；不是 Apple CLI 原生入口 |
| --convert | C# 46 次真实进程、N 转换/多根；双端核心 | 输入歧义、压缩尾部/多成员、Apple 桥、JSON 特殊边界 |
| 批处理与会话 | 14 项会话、7 项环境、N 语法拒绝/运行错误继续/来源保护与恢复 | 单命令内部混合对象全事务未保证 |
| 保存 | N 导出重开、源字节/未知记录保护 | Windows 两项 FileShare SKIP；最终 EXE 未验 |
| GUI 地图 | Swift 投影坐标、C# 渲染核心、静态 GUI 检查 | 实际控件、异步、PNG 像素 |
| GUI 对象/NBT | 双端身份/迁移核心、C# 新方块实体连续保存、静态接线 | 新方法普通实体直接覆盖、并发/村庄/退出和实际 GUI |
| Windows 发布 | C# CLI/Core、WPF 交叉编译、Linux 原生桥 | Windows ABI、EXE、PowerShell 5.1/7、干净机器 |
| Apple 发布 | Swift 核心、六个发布脚本工具替身场景 | macOS CLI、ObjC++、iOS SDK、签名、IPA/真机 |
| Minecraft | 未运行 | 坐标与步骤见 AUDIT_ROUND15.md |

日志及命令见 [Validation/round15/README.md](Validation/round15/README.md)，行为规格见 [COMMAND_PARITY.md](COMMAND_PARITY.md)，缺口见 [FINAL_REVIEW.md](FINAL_REVIEW.md)。
