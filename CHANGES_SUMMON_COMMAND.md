# summon UniqueID 与直接 NBT 输入

版本保持 **1.0.0**。本次修改覆盖 iOS 图形版、Windows 图形版、iOS CLI、Windows CLI，并保留上一版的 `entity` 命令及其全部回归用例。

## 输入格式

```text
summon 实体类型 维度 x y z NBT标签或default [UniqueID]
summon 实体NBT标签
```

普通格式的最后一个参数可填写 `Auto` 或非零的有符号 64 位整数。省略时仍自动生成，兼容原有命令文件。手动 ID 直接按 Long 解析，支持 -9223372036854775808 至 9223372036854775807，不经过浮点转换。`0` 延续现有实体存储的限制，不作为合法 UniqueID。

```text
summon minecraft:pig overworld 0 64 0 default Auto
summon minecraft:pig overworld 0 64 0 default 9007199254740993
summon 'String'"identifier"="minecraft:cow",'List''Float'"Pos"="0.0,64.0,0.0",'Long'"UniqueID"="12345678"
```

直接 NBT 格式使用现有的带类型标签语法，保留传入标签的名称、类型、值和顺序，不自动套用实体通用模板。`identifier`、数字 `id`、`definitions` 等身份标签原样保存。

- 必须提供 `Pos` 或 `Position`：由恰好三个有限数值组成的 List，数值不能超出 Float 范围；保留原 List 的数值类型。
- `UniqueID` 如果提供，必须是非零 Long；缺少时生成一个未占用 ID，并在末尾追加 Long 标签。
- `DimensionId` 或 `Dimension` 如果提供，必须是 Int32 范围内的整数 NBT 标签；缺少时使用主世界存储位置，不向 NBT 中补写维度标签。
- 上述保留字段支持大小写别名，重复字段或同时提供多个别名会在命令预检时拒绝。

CLI 中两种格式均按写入命令处理，需要 `--output` 或 `--in-place`。复杂 NBT 建议放入 UTF-8 命令文件，通过 `--script` 执行，以保留引号。

## 存储与冲突处理

复用现有的新式 actorprefix/digp 和旧式区块 Entity 存储选择。创建前检查 NBT UniqueID；新式实体还检查所需的 actor 存储引用，包括没有对应实体数据的残留 digp 引用。即使摘要末尾存在损坏字节，也会避开扫描器仍能读取的完整引用。

手动 ID 冲突时拒绝创建且不写入数据库。自动生成时跳过已占用候选值。旧式实体的显式 NBT ID 不会被无关的新式 actor 引用错误限制。

两端 help、自动生成的 Commands/ReadMe.txt、CLI 命令清单及共享解析用例已同步。

## 验证

本轮在 Linux x86_64 上使用 Swift 5.10.1 与 .NET SDK 10.0.100 验证：

- Swift 完整核心回归通过，包含 192 个共享解析用例、summon 写入与冲突用例，以及 entity 查询回归。
- C# Core 全量回归通过，覆盖 Long 边界值、Auto、NBT 字节保留、现代/旧式存储、残留引用和拒绝时零写入。
- C# CLI 真实 Mojang LevelDB 集成测试通过，包含新命令的导出后重新打开、源存档不变、NBT 类型与 ID 精度检查。
- CLI 冒烟测试通过：253 项进程检查、192 个解析用例、27 个命令。
- Windows WPF 图形版交叉编译通过：0 警告、0 错误。
- 命令清单、两端 help、命令路由和 Swift 构建输入的一致性检查通过。
- 修改过的 iOS CLI 路由及原生测试文件通过 Swift 语法检查。

验证记录见 `CLI/Docs/Validation/summon/`。Linux 无法运行 iOS 真机/Xcode 完整构建或 Windows 图形界面；原生测试中的两个 Windows FileShare 锁场景按原有规则在 POSIX 跳过。这些平台运行检查未被计为已通过。
