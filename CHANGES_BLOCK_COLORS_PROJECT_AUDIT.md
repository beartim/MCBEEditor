# 地图方块颜色与全项目源码审计

本轮以 `MCBEEditor-iOS13-v1.0.0-fillbiome-info-xz-picker-ci-fix-source` 为基线，集中处理地图颜色准确性、旧版方块 data 颜色丢失、重复判断和可确认的死代码。目标是改善颜色语义和可维护性，同时不破坏 MCBEEditor 对旧 Bedrock 存档的兼容路径。

## 1. 地图方块颜色

### 1.1 独立颜色目录

新增：

- `Sources/Chunk/BedrockBlockMapColorCatalog.swift`
- `Sources/Support/BedrockBlockIdentifier.swift`

原先 `ChunkSurfaceRenderer` 内的大段 `contains(...)` 颜色判断已移出渲染器。Y 模式和 X/Z 剖面现在共用同一套颜色语义，避免两个渲染路径颜色逐渐不一致。

### 1.2 修复错误的模糊字符串匹配

旧逻辑中较宽泛的 `contains(...)` 会让名称中包含相同片段、但材质完全不同的方块误命中。例如：

- `minecraft:soul_sand` 会先命中普通 `sand`；
- `minecraft:waterlily` / `underwater_torch` 可能被 `water` 捕获；
- `mossy_cobblestone` 会被 `moss` 捕获；
- `stone_bricks`、`prismarine_bricks` 可能落入普通红砖分支；
- `red_sandstone` 与 `red_sand` 的规则顺序容易互相影响。

现在把空气、水、岩浆等精确语义集中到 `BedrockBlockIdentifier`，并把更具体的材质规则放在宽泛规则之前。

### 1.3 灵魂沙及主要材质颜色

灵魂沙现在使用独立深棕色：

- `soul_sand`：`#544034`
- `soul_soil`：`#4B3A30`
- 普通沙：`#DEC98A`
- 红沙：`#B65A27`

同时重新整理了：

- 普通/红砂岩；
- moss / mossy stone；
- stone brick / prismarine brick / nether brick / mud brick；
- 草、树叶、藤蔓、水草、农作物；
- 雪与不同冰块；
- granite / diorite / andesite / tuff / deepslate / blackstone / basalt；
- 各木种，包括 oak、spruce、birch、jungle、acacia、dark oak、mangrove、cherry、bamboo、crimson、warped、pale oak；
- 铜的普通、exposed、weathered、oxidized 阶段；
- Nether / End / 金属 / 宝石 / 功能方块等常见家族。

普通地图模式中的矿石颜色更接近宿主石材，避免地表偶然露出的矿石像 X-Ray 一样异常鲜艳；X-Ray 模式仍使用单独的高对比矿石色。

### 1.4 染色方块

羊毛、混凝土、玻璃、陶瓦不再全部共用同一套高饱和度颜色：

- wool / carpet / concrete 使用基础染料色；
- stained glass 适当向浅色透明材质混合；
- concrete powder 略作灰化；
- terracotta 使用更暗、更低饱和度的独立色表；
- glazed terracotta 保留更接近染料主色的辨识度。

### 1.5 旧版数字 ID + data

旧渲染流程只把 `BedrockBlockState.name` 传给颜色函数，导致旧世界中依赖 data 值区分的颜色丢失。本轮让可见列保留完整 `BedrockBlockState`，并把 `legacyID` / `legacyData` 一直传到颜色目录。

因此旧版世界现在能区分：

- stone data：granite / diorite / andesite；
- sand data：普通沙 / 红沙；
- planks/log/leaves 的木种；
- 16 色 wool；
- stained glass / stained glass pane；
- terracotta；
- concrete / concrete powder 等旧数字方块变种。

项目内 `BedrockLegacyBlockCatalog` 的 256 个 legacy 标识已由专项测试逐项扫描；254 个得到明确语义颜色，仅保留/未使用技术 ID `unused_166`、`reserved6` 使用稳定 fallback。

### 1.6 未知/自定义方块

对当前颜色目录无法识别的自定义或未来方块，不再依赖 UIKit HSV 随机式分支，而是使用基于完整 identifier 的稳定 FNV-1a 哈希生成低饱和度、中等亮度 RGB。同一个 identifier 在 Y 地图和 X/Z 剖面中始终得到相同 fallback 色。

## 2. 渲染性能

`ChunkSurfaceRenderer` 新增有上限的 `NSCache<NSString, UIColor>`，最多缓存约 2048 个方块颜色结果。

这对 X/Z 128 方块深度投影尤其重要：同一种方块不再对每个像素重复执行完整字符串分类。

## 3. 源码统一与清理

### 3.1 方块 identifier 语义集中

新增 `BedrockBlockIdentifier`，统一：

- air / cave_air / void_air；
- water / flowing_water / bubble_column；
- lava / flowing_lava；
- X-Ray 高亮矿物判定。

`WorldCommand`、`BedrockSubChunk`、`ChunkSurfaceRenderer`、`BedrockCrossSection` 和 `WorldCommandExecutor` 已改为复用这些规则，避免各文件各写一份、后续修改不一致。

### 3.2 负坐标向下取整集中

`MapCoordinate` 新增 `floorDiv16`，作为方块 Y/X/Z 到 16 方块单元的统一 floor division。

已替换：

- `BedrockCrossSection`；
- `BedrockSubChunkEditor`；
- `WorldCommandExecutor` 中 SubChunk Y 与 local Y 计算。

这避免 `-1`、`-16`、`-17` 等负坐标在不同模块出现不同结果。

### 3.3 删除确认无调用的旧代码

删除 `BedrockSubChunkEditor` 中已经没有调用者的旧 `modernBlockState(from:paletteVersion:)` 私有实现，以及对应的局部 `floorDiv16`。

没有把文件名或逻辑中带 `legacy` 的代码一概删除：这些路径承担旧 Bedrock SubChunk、LegacyTerrain、数字 ID 和 zlib 存档兼容，属于产品功能而不是冗余代码。

### 3.4 项目静态审计

本轮额外检查：

- `TODO` / `FIXME` / `HACK`：Sources 中无遗留；
- 调试 `print(...)`：Sources 中无遗留；
- `try!`：Sources 中无遗留；
- 重复 `isHighlightedOre`：只保留一份；
- 重复 `floorDiv16` 声明：只保留 `MapCoordinate` 一份。

程序化创建的 UIKit 控制器仍保留 `required init?(coder:) { fatalError(...) }`。这些是明确不支持 Storyboard/Coder 初始化的标准防御路径，不按“死代码”删除。

## 4. 未进行的高风险重构

`WorldMapViewController.swift` 仍然承担较多地图状态、渲染、导出和对象图层逻辑，是当前最明显的“大文件”结构问题。由于它和近几轮新增的 X/Y/Z 剖面、图片导出、选择、对象点击等逻辑高度耦合，本轮没有为了代码形式好看而强制拆类，以避免引入大量 UI 生命周期和状态同步回归。

后续如果要继续结构重构，建议按“CrossSectionCoordinator / MapExportCoordinator / MapOverlayCoordinator”逐个拆分，并每拆一块先补行为测试，而不是一次性重写控制器。

## 5. 回归保护

新增 `Scripts/test_block_colors_project_audit.sh`，并加入 `Scripts/run_core_tests.sh`。它会检查：

- 灵魂沙和普通沙必须不同色；
- waterlily / underwater_torch 不能被当水；
- mossy cobblestone、stone bricks、prismarine bricks 等关键冲突项；
- terracotta 与 wool 色系必须区分；
- legacy 红沙、红羊毛、dark oak data 必须正确；
- 256 个 legacy identifier 的颜色覆盖；
- legacyID/data 必须保留到渲染层；
- 旧 renderer-local 大颜色分支不能重新出现；
- 矿物判断和 floorDiv16 不得再次复制；
- 已删除的 `modernBlockState` 死实现不能回归。
