# 第 4 次小更新：ID、颜色与版本范围

核对日期：2026-10-28。来源为用户指定的中文 Minecraft Wiki 更新页、Mojang 官方预览 metadata、协议枚举与 26.70.21 公告。在上一轮 kill 范围版本上增量更新；应用版本保持 1.0.0，最低 iOS 13。

## ID 对照与实际消费者

| 类别 | 数字 ID | identifier | 中文名称 |
| --- | ---: | --- | --- |
| 实体 Short ID | 155 | `minecraft:frostbite` | 冻尸 |
| 实体 Short ID | 156 | `minecraft:ice_ball` | 冰球 |
| 生物群系 | 196 | `minecraft:ice_caves` | 冰封洞穴 |
| 状态效果 | 38 | `freezing` | 冰冻 |
| 新版方块类型 | 1502 | `minecraft:icicle` | 冰锥 |
| 新版方块类型 | 1503 | `minecraft:ice_crystal` | 冰晶 |
| 新版方块类型 | 1504 | `minecraft:brittle_ice` | 脆冰 |

实体短 ID 同时接入原数字 NBT 实体识别桥，实体搜索和创建列表可找到新增类型。协议中的 Frostbite 完整枚举为 199579、IceBall 为 4194460；对照表沿用 Short ID 155／156，没有把协议完整枚举混作短 ID。

冰封洞穴已接入双端群系列表、搜索、fillbiome 名称解析与颜色。冰冻已接入目录、effect give／clear 和 ALL；命令语法继续使用字符串 ID，写回的 ActiveEffects.Id 为 38。C# 的 effect 名称及 ALL 枚举均改为复用主目录，避免重复维护漏项。

新增可搜索的“冰系方块 ID（预览）”入口，列出固定官方样本已确认的三个新方块类型 ID。这些数值独立于旧版 0–255 转换表；现代区块仍按世界自身 palette 的字符串名称与 states 读写，不拿此表替换运行时 palette。

## 新物品事实表

下表来自同一固定 Mojang mojang-items.json，用于资料核对。现有 give 命令继续使用字符串 identifier。

| 原始物品数值 ID | identifier | 名称 |
| ---: | --- | --- |
| -1249 | `minecraft:brittle_ice` | 脆冰 |
| 791 | `minecraft:frostbite_spawn_egg` | 冻尸刷怪蛋 |
| 853 | `minecraft:ice_ball` | 冰球 |
| 854 | `minecraft:ice_crystal` | 冰晶 |
| 855 | `minecraft:icicle` | 冰锥 |

物品原始数值与方块类型 ID 分属不同目录。例如冰晶方块为 1503，而该官方样本物品数据为 854；不将二者混用。冰冻药水和冰冻之箭沿用药水／箭的现有物品体系，不虚构独立物品数字 ID。

## 地图颜色

内置配色继续采用编辑器的材质近似色；双端的俯视图、剖面和图片导出复用同一颜色查询。

| 材质 | RGB | 范围 |
| --- | --- | --- |
| 冰晶 | `#B0DAD3` | `minecraft:ice_crystal` |
| 冰锥 | `#B9D9EC` | `minecraft:icicle` |
| 脆冰 | `#A7C7EA` | `minecraft:brittle_ice` |
| 浮冰与装饰系列 | `#8DB4EA` | 浮冰砖、楼梯、台阶、墙及雕纹浮冰沿用既有浮冰色 |
| 雪砖系列 | `#F1F6F7` | 雪砖、楼梯、台阶和墙的字符串兼容识别 |
| 冰封洞穴 | `#9ABBDD` | 群系 ID 196 |

Colors.txt > PNG > 内置颜色的优先级保留；未改动用户自定义文件。

## 来源和未确认项目

- [用户指定更新页](https://zh.minecraft.wiki/w/2026年第4次小更新)：范围和中文名称。
- [Mojang 固定预览样本](https://github.com/Mojang/bedrock-samples/tree/4d30ae63750467771b6eccda105f732c6cb77ff7)：v1.26.60.30-preview；确认实体标识、群系 ID、效果名称、三个新方块数值／属性名及物品数据。官方 main 当前仍停留 v1.26.50.4，不能以它判断预览内容不存在。
- [Mojang 协议 ActorType](https://mojang.github.io/bedrock-protocol-docs/1.26.70-preview.21/types/actor-type/)：新增实体完整枚举及短 ID。
- [冰冻数据页](https://minecraft.wiki/w/Freezing)：Bedrock 数字效果 ID 38；Mojang 预览 metadata 独立确认 freezing 名称，但该文件不提供数字 ID。数字的社区来源在证据中明确保留。
- [官方 Bedrock 26.60 公告](https://www.minecraft.net/en-us/article/minecraft--bedrock-edition-26-60-changelog)：已有部分实验内容。
- [官方 Preview 26.70.21 公告](https://www.minecraft.net/en-us/article/minecraft-preview-26-70-21)：确认浮冰装饰系列。

固定的官方 metadata 未包含浮冰砖系列后续数值；这些方块的颜色按已确认的材质与字符串系列兼容处理，未补入猜测数字。雪砖系列也只增加材质识别，其 Bedrock 数字值尚未从固定官方数据确认。以上待确认项均记录在 sources.json，不将 Java 数据冒充 Bedrock 数值。

证据文件、取得日期、来源、固定提交及 SHA-256 见 sources.json 与 Upstream/。保留原正式内容快照；catalog-reference.json 为当前双端 572 行的预期，增量来源单独保存。旧版方块 256 项 ID、名称及转换规则保持不变。

验证结果与边界见 [VALIDATION.md](VALIDATION.md)。
