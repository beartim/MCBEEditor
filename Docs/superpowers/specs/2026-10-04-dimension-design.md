# MCBEEditor 任意维度与 dimension 命令设计

## 目标与范围

按用户要求同步 iOS GUI、Windows GUI、Apple CLI 和 Windows CLI：增加 dimension query/empty/purge/add；解除所有世界命令仅支持 0/1/2 的限制。每轮工作不超过 10 分钟，每轮交付独立完整源码压缩包。保留版本号 1.0.0 和已有 iOS 13 最低兼容要求；Windows 保留导出 .mcworld 的保存方式。

本文件是第一轮的技术设计；第一轮不改变运行时代码。后续阶段直接依据用户的上述需求继续实施，无需另行选择执行方式。

## 示例存档的权威依据

数据库键 DimensionNameIdTable 的值为普通小端 NBT：根 Compound / entries Compound / 名称为键、Int 为 ID。

```text
entries: { bear:wzn: Int(1002), wzn:bear: Int(1000), wzn:cat: Int(1001) }
```

另有数据库键 Overworld、bear:wzn、wzn:bear、wzn:cat。各值均为根 Compound / data Compound / LimboEntities List(Compound)，此样例的列表为空。名称必须完整保留，不能统一替换成固定 namespace。

样例的实际维度为 overworld(0)、wzn:bear(1000)、wzn:cat(1001)、bear:wzn(1002)。只有 0 和 1001 有区块记录；没有 Nether/TheEnd 维度记录或对应区块，query 不应凭常量枚举宣称它们存在。level.dat 没有自定义名称-ID表。

## 命令语义

| 命令 | 行为 |
|---|---|
| dimension query | 按 ID 排序列出存在的维度名称与 ID，包含已登记但零区块的维度，以及仅有数据的未登记 ID；可附区块数量。只读。 |
| dimension add wzn:bear 1000 | 新建名称与 ID 的登记及维度根数据，零区块亦可在 query 和重开后发现。 |
| dimension add bear 1000 | 无 namespace 的名称原样登记，不自动添加 minecraft:。 |
| dimension add overworld 0 | 原版维度缺失时恢复；nether 1、the_end 2 同理。原版名称和 canonical ID 的对应关系固定。 |
| dimension empty 名称或ID | 删除目标维度内容，保留名称-ID登记与维度根；目标仍出现在 query。 |
| dimension purge 名称或ID | 删除目标维度内容、维度根和名称-ID登记；目标不再出现在 query；之后可重新 add。 |

名称输入按存档登记解析；原版名称的历史大小写兼容保留，也支持对应 minecraft: 别名。ID 为有符号 Int32，不保留 0/1/2 白名单。未知名称应报告名称无法解析，禁止任意猜测 ID。ID 操作须准确匹配数值，不用名称字符串包含匹配。

add 拒绝已占用的名称、ID，以及会覆盖无关全局数据库键的名称。参数校验在写入前全部完成，错误无部分写入。纯数字名称与数值 ID 存在语法歧义，add 应拒绝纯数字名称并提示使用非纯数字名称；普通无 namespace 名称仍支持。同名大小写冲突按存档真实名称检查，不能把所有自定义名称 lowercased 后存储。

## 数据边界

发现维度合并三个来源：DimensionNameIdTable、独立维度根记录、区块/digp 实际数据。未登记 ID 的名称显示为其数值，不凭玩家历史引用制造一个被 purge 的维度。

empty/purge 处理全部区块记录（含子区块、旧实体、方块实体、计划刻、hardcoded spawners 等）、digp 与所引用 actorprefix、维度 LimboEntities、属于此维度的常加载区块和村庄，以及能够明确归属此维度的其它内容。全局保存数据、计分板、其它维度和玩家存档不应随目标维度被删除。共享 actor 引用必须先检查其它维度是否引用，不能删除仍被引用的 actor。

在实现清空/删除阶段审计玩家当前位置、重生维度、跨维度门户、WorldClocks 和旧数据引用。保留玩家数据；purge 对指向被删除维度的玩家当前位置/重生位置执行明确、可报告的迁移到仍存在的维度。若不存在可用维度，拒绝 purge，保证不留下无处安放的玩家；无玩家引用时支持删除最后一个维度。细化这一策略的依据与实际行为须写入对应阶段说明。

empty 与 purge 的写入由同一个删除计划构建器产生，以数据库批处理执行；先构造所有删除/更新，再 ApplyBatch。未知或无法解析的维度内容必须报告，不能在误删其它维度的情况下宣称彻底删除。不得向 level.dat 发明无来源的维度登记字段。

## 技术结构

Swift 新增 Sources/World/DimensionStore.swift；C# 新增 Windows/MCBEEditor.Core/World/DimensionStore.cs。两端提供一致的 DimensionRecord、snapshot、resolve、add、empty、purge 语义，在 CLI 中复用相应 GUI 核心。

维度解析依赖当前世界的 snapshot。Swift WorldCommandParser.parse 增加可选 resolver；C# 各命令 parser 增加可选 Func<string,int> resolver。默认行为保留旧调用方兼容。禁止用进程全局可变映射，以免多世界相互污染。

CLI 批处理在预检中维护纯内存维度登记状态，使同一文件内 add 后的其它命令能解析新名称；全部语法预检成功后再执行。执行前仍验证最新存档状态，purge/add 不能使用过期缓存。validate 无世界上下文时只验证名称 token 语法，实际世界绑定在执行阶段完成。

区块键按完整长度区分主世界短格式与带维度的长格式，再判断类型。不能先把 data[8] 当 recordType；43、44、47、118 等 ID 会与类型低字节碰撞。全维度删除匹配涵盖未知合法标签，不能只使用 ChunkRecordType 枚举名单。

## 验证与交付

Swift、C# 使用内存数据库测试发现、解析、注册、清空和删除；样例 mcworld 验证实际字段及重开持久化。新增包含 actor、方块实体、旧实体、常加载区块、村庄、玩家引用的测试向量，因为用户样例这些内容为空。

每轮将完整源码、当轮变更与验证记录打包。第一轮提供原始源码基线、原始测试存档、只读分析脚本、JSON 报告与分轮计划。当前环境缺少 Swift/dotnet，不能宣称三端编译通过；后续有可用构建环境时执行本机构建，否则提供准确的静态与数据验证结果及待运行命令。
