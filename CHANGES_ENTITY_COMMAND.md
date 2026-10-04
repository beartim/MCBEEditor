# entity 命令更新（1.0.0）

本次源码更新适用于 iOS 图形版、Windows 图形版、iOS CLI 和 Windows CLI。版本号保持 1.0.0。

## 用法

```text
entity
entity overworld
entity overworld -16 0 -16 16 128 16
```

完整语法：`entity [维度 [x1 y1 z1 x2 y2 z2]]`。

- 不传参数：列出所有维度的普通实体，包括自定义维度。
- 只传维度：列出该维度的全部普通实体。维度参数沿用已有命令的 `overworld`、`nether`、`the_end`。
- 传维度和两组坐标：按实体原始浮点坐标筛选闭合长方体范围，包含边界；支持小数、负数和反向角点。
- 不带范围时保留没有位置字段的实体；指定范围时跳过没有位置字段的实体。
- 命令只读，不包含玩家记录和方块实体。CLI 执行无需 `--output` 或 `--in-place`。

每个实体单独一行，使用与实体栏目相同的类型识别逻辑，保留原始 NBT 标签及顺序，例如：

```text
minecraft:pig=['String'"identifier"="minecraft:pig",'Long'"UniqueID"="12345678"]
```

类型识别复用实体扫描器，支持 identifier、旧式数字 ID 和 definitions 回退。仅有 definitions 的实体也能识别；查询不会为它补写 identifier 标签。NBT 采用 getblock 的带类型显示格式，递归包含 Compound、List 和各种数组，保留 Int64 整数精度。字符串中的换行等字符会转义，保持每个实体一行。

嵌套列表的子列表类型相同时，继续使用既有简写；类型不同时，逐个显示子列表的类型，例如 `['List''Int'=[1]],['List''String'=[2]]`。此混合类型表示是显示格式，不扩展已有命令的 NBT 输入语法。

## 实现与边界处理

- 两端共享实现均接入命令解析、执行和帮助；Windows GUI 增加只读执行入口，两端 CLI 增加只读分类。
- 兼容旧式区块实体记录与现代 actor/digp 记录，按解析后的实体维度过滤。
- 保留不同存储记录中重复 UniqueID 的实体，不受实体浏览器默认 200,000 条显示上限影响。
- 没有匹配结果时显示 `entity：没有匹配的实体。`；损坏记录等问题追加 `entity 扫描提示：…`。
- 修复混合嵌套 List 的类型丢失，以及 Swift 扫描超大或非有限位置值时的整数转换崩溃。查询范围仍使用原始坐标比较。

## 验证

本次最终源码已通过：

- Swift 全量核心回归，包含新增 entity 查询、精确 NBT、混合列表、极端位置及只读测试。
- C# 全量 Core.SelfTest，包含超过 200,000 条实体、不丢重复 UniqueID 和递归列表类型测试。
- C# CLI 真实 Mojang LevelDB 集成：新增 entity 查询测试及原有 44 个调用场景；验证世界数据完整性与只读行为。
- Windows CLI smoke：221 个进程检查、160 个解析用例、27 个命令。
- Windows WPF 交叉编译：0 警告、0 错误。
- 四端命令清单、帮助和执行路由静态核对。

测试环境为 Linux。未执行 iOS/macOS 原生构建、iOS 真机测试或 Windows GUI 运行测试；两个 Windows 专用 FileShare 锁测试按既有测试逻辑在 Linux 跳过。iOS 原生 CLI 集成用例已补充，需在 Apple 环境运行。

最终验证日志与复现说明见 `CLI/Docs/Validation/entity/`。
