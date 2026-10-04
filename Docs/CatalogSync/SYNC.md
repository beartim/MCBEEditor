# ID 对照与中文名称同步

核对日期：2026-10-04。正式版基线为 Bedrock 26.52；官方内容样本为 `Mojang/bedrock-samples` 的正式标签 `v1.26.50.4`，不是 preview 分支。26.52 是修复版本，内容目录与 26.50 正式内容对应。

| 类别 | 条目数 | 核对与处理 |
| --- | ---: | --- |
| 实体 | 141 | 官方实体文档中的 Short ID 全部一致；保留教育版、技术实体与旧版实体。NPC 增加“非玩家角色”中文说明。 |
| 状态效果 | 37 | 当前官方名称全集无遗漏；保留既有存档数字 ID。 |
| 生物群系 | 89 | 官方 metadata 的名称和数字 ID 逐项一致，包括硫磺洞穴与斑驳森林。 |
| 魔咒 | 42 | 与当前官方名称及协议枚举核对；27/28 改为基岩版 `binding` / `vanishing`；41 显示“戳刺（突进）”，包含当前基岩版简体中文名称与原有称呼。 |
| 旧版方块 | 256 | 255 个仅英文显示名称补齐中文；0–255 的数字 ID、旧字符串 ID、别名与存档转换规则保持不变。 |

实体 153=`minecraft:sulfur_cube`、154=`minecraft:cushion` 等新版实体已存在于上一版，本次核对确认正确，没有重复添加。所有 565 条对照现有中文显示文本。未命名的 `reserved6` 使用“未命名预留方块（reserved6）”描述，保留技术名称，不宣称存在官方中文名。

## 名称来源

优先参考中文 Minecraft Wiki 可检索到的社区术语，结合当前 Mojang `zh_CN.lang` 与对应 `en_US.lang` 核对。Wiki 的直接抓取受到限制，未把旧索引页面声称为最新完整 ID 表；新版数字值以 Mojang/Microsoft 数据复核。

`legacy-block-names.json` 保留原英文名称、中文名称及可用的语言键。旧表中一个 ID 可能涵盖多个颜色、木种或方块变种，因此“第二组”“双层”“旧版共用 ID”等是说明性标签；没有将某个变种的专有中文名误用为整组名称。

社区与游戏语言文件有不同叫法时，使用常见社区名称，例如“加热块”“霜冰”“发光的黑曜石”“数据更新方块”。NPC 展开为“非玩家角色（NPC）”。对无法确认专有中文名的技术占位符，明确标注未命名。

## 来源与复现

- [Minecraft 中文 Wiki：方块](https://zh.minecraft.wiki/w/方块?variant=zh-cn)
- [Minecraft 中文 Wiki：加载提示](https://zh.minecraft.wiki/w/加载提示?variant=zh-tw)
- [Minecraft 中文 Wiki：化合物](https://zh.minecraft.wiki/w/化合物)
- [Mojang 正式内容样本](https://github.com/Mojang/bedrock-samples/tree/v1.26.50.4)
- [Microsoft 官方实体数值文档](https://github.com/MicrosoftDocs/minecraft-creator/blob/ba7a3b48ae80393780766f361b83698361ee3f3e/creator/Reference/Content/VanillaListingsReference/Entities.md)
- [Mojang 协议 ActorType](https://mojang.github.io/bedrock-protocol-docs/1.26.51/types/actor-type/)
- [Mojang 协议魔咒枚举](https://mojang.github.io/bedrock-protocol-docs/1.26.51/types/enchant-type/)
- [Bedrock 26.52 修复公告](https://feedback.minecraft.net/hc/en-us/articles/49175370527501-Minecraft-Bedrock-Edition-26-52-Hotfix-Changelog)

固定提交、下载日期及 SHA-256 见 `sources.json`。`Upstream/` 保存核对所需的名称/数字事实；`catalog-reference.json` 是两端共同验收快照。Mojang `bow_infinity` 的 metadata 值是 `minecraft:infinity`，对照继续使用 `infinity`。

复核命令：`python Scripts/test_catalog_sync.py`。该脚本编译并运行生产 Swift/C# 目录，对比全部条目，核查实体扫描器的数字映射，实际执行中文搜索；不是仅比较源文件文本。

旧版方块表用于历史数字 SubChunk，不将新版本运行时调色板序号当作固定方块 ID，也不为新方块臆造 0–255 之外的旧数字 ID。
