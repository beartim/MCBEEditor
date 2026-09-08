# 方块地图颜色第二轮完整审计

本轮以 `MCBEEditor-iOS13-v1.0.0-block-colors-project-audit-source` 为基线，对 `BedrockBlockMapColorCatalog` 做第二轮完整复核。重点不是单独修 `ender_chest`，而是检查“特殊方块被宽泛材质词误判”、旧数字 ID/data 颜色分支与较新的 Bedrock 方块系列。

## 1. 已确认并修复的错误颜色

- `ender_chest`：不再落入普通 `chest` 的褐色，改为深青黑 `#234342`。
- `redstone_wire`：不再被最终的 `stone` 规则吞掉，改为红色 `#A32222`。
- `redstone_torch` / `unlit_redstone_torch`：不再使用普通火把黄色，改为亮/暗红色。
- `flower_pot`：不再因为包含 `flower` 而显示红花色，改为陶瓦褐红色。
- `chorus_flower`：不再按普通花朵显示，改为末地紫色。
- `end_bricks` / `end_stone_bricks`：不再被 `stone_brick` 规则提前显示为普通灰色，改为末地石砖的浅黄绿色。
- `seaLantern`（旧版驼峰 ID）：与现代 `sea_lantern` 使用同一浅青白色。
- `invisibleBedrock`：从错误的 legacy 染色玻璃 data 分支中移除，恢复为基岩深灰色。
- `silver_glazed_terracotta`：识别旧版 `silver` 颜色别名，按 light gray 显示。
- legacy `shulker_box`：ID 218 的 data 现在参与 16 色着色，不再一律显示同一种紫色。
- `pumpkin_stem` / `melon_stem`：不再继承南瓜/西瓜果实颜色，改为植株绿色。
- `red_nether_brick`：与普通下界砖区分，使用更明显的暗红色。
- `tinted_glass`：不再和普通玻璃同样浅青，改为深灰紫色。
- `soul_fire` / `soul_torch` / `soul_lantern` / `soul_campfire`：统一为灵魂火青色，不再落入普通火把/灯笼黄色。
- `crying_obsidian` / `respawn_anchor`：与普通黑曜石区分为更偏紫的深色。

## 2. 增加的明确语义颜色

补充了此前容易使用 fallback hash 色的系列：

- 工作站/功能块：lectern、loom、cartography table、fletching table、smithing table、composter、smoker；
- 蜂蜜/蜂巢：honey block、honeycomb block、bee nest、beehive；
- 特殊装置：bell、conduit、lodestone、chain、lightning rod、target、heavy core、vault、ominous vault、jigsaw、barrier；
- Nether：ancient debris、netherite block、gilded blackstone、weeping/twisting vines、nether sprouts；
- End：ender chest、chorus flower、end stone bricks；
- 珊瑚：tube/brain/bubble/fire/horn coral，以及 dead coral；
- 新植物：azalea、flowering azalea、dripleaf、hanging roots、glow lichen、leaf litter、mangrove propagule、mangrove roots、cactus flower、torchflower、pitcher plant、spore blossom；
- Pale Garden：pale moss、pale hanging moss、creaking heart、eyeblossom；
- Froglight：ochre / verdant / pearlescent 使用不同主色；
- 其他：decorated pot、frog spawn、sniffer egg、suspicious sand、scaffolding、light block。

Bamboo 建筑系列单独使用较温暖的黄木色，不再和活体竹子的绿色完全相同。

## 3. 规则顺序调整

新增 `specialSemanticRGB`，放在染色方块处理之后、宽泛的木材/石材/植物/功能块规则之前。

这一层专门处理名称容易“串词”的方块，例如：

- `ender_chest` vs `chest`
- `flower_pot` / `chorus_flower` vs `flower`
- `end_stone_bricks` vs `stone_brick`
- `soul_torch` / `redstone_torch` vs `torch`
- `tinted_glass` vs `glass`
- `mangrove_roots` vs `mangrove` wood family

因此后续新增宽泛材质规则时，不容易再次把这些特殊方块覆盖掉。

## 4. Legacy data 修正

`legacyVariantRGB` 的染色 family 从：

- 35, 95, 160, 171, 236, 237, 241, 254

修正为：

- 35, 160, 171, 218, 236, 237, 241, 254

其中：

- ID 95 在 MCBEEditor 的 Bedrock legacy 表中是 `invisibleBedrock`，不是 stained glass，因此旧写法是明确错误；
- ID 218 是 `shulker_box`，data 是颜色信息，应纳入 16 色处理。

## 5. 回归测试

新增 `Scripts/test_block_colors_full_audit.sh` 并加入 `run_core_tests.sh`。

该测试会：

- 对所有已确认误判项做精确颜色/差异检查；
- 验证 ender chest 不会再次变成普通箱子褐色；
- 验证 soul/redstone torch 不会再次使用普通火把色；
- 验证 end stone bricks 不会再次变灰；
- 验证 legacy seaLantern、invisibleBedrock、silver glazed terracotta、shulker box data；
- 检查 100+ 个现代常见/特殊方块均有明确语义颜色，不依赖 fallback hash；
- 重新扫描 256 个 legacy block ID，仅允许 `unused_166` 与 `reserved6` 使用 fallback。

## 6. 验证结果

- 113 个 Swift 源文件 `swiftc -parse` 通过；
- 20 个 Shell 脚本 `bash -n` 通过；
- 16 个独立 `test_*.sh` 全部通过；
- 原方块颜色/项目审计专项继续通过；
- fillbiome/info/X-Z、NBT/X-Y-Z、LegacyTerrain、SubChunk v0-v9、Metadata、iPhone 布局、单 PNG 分享等专项全部通过；
- 完整 `run_core_tests.sh` 在容器 240 秒执行窗口内超时，但超时前连续通过到 chunk regeneration/clear 系列，没有出现失败。
