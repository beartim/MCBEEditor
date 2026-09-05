# iPhone 地图/NBT 布局与旧版数字 ID 方块绑定修复

## 1. iPhone 地图页布局

针对竖屏 iPhone 上文字被压成省略号、开关标题完全消失以及方块 NBT 侧栏过窄的问题进行了重新排版：

- 地图顶部的三个开关在 iPhone 上单独占一行，显示为“自动 / 网格 / 区块”，不再与 X/Z 渲染中心编辑器争抢同一行宽度。
- 渲染中心编辑器单独占一行；“渲染中心坐标”在 iPhone 上缩写为“中心”，X/Z 输入框和“渲染”按钮使用更小但仍可读的字号。
- 六项地图模式在 iPhone 上使用更紧凑字号，其中“常加载区块 / 史莱姆区块”显示为“常加载 / 史莱姆”，避免直接显示省略号。
- iPhone 的方块 NBT 展开侧栏由原来的约 42% / 最小 176 pt 调整到约 50% / 最小 200 pt、最大 250 pt，让 NBT 名称和值获得更多横向空间。
- 方块 NBT 的坐标输入和“查看”按钮合并为紧凑的一行；操作按钮缩写为“增加 / 保存 / 结果 / 导出 / 选择”。
- 坐标说明压缩成两行，NBT 行字体、缩进和状态提示字号同步缩小；典型的普通方块/旧数字 ID 方块可以在一屏内看到主要标签。大型 NBT 仍保留必要的滚动能力。

## 2. 旧版数字 ID 方块的 `name ↔ legacy_id` 绑定

旧版数字 SubChunk/LegacyTerrain 中的方块实际由数字 ID + metadata 保存。编辑器显示的字符串 `name` 现在明确作为数字 ID 的“对照字段”，不再被当成可独立修改的普通标签。

- 顶层 `name` 后显示 `🔗`，与受保护 UniqueID 的视觉提示一致。
- 修改 `name` 时：
  - 若字符串能映射到旧版数字 ID，则自动把 `legacy_id` 改成对应 ID；
  - 同时把 `name` 规范化为旧版目录中的 canonical identifier；
  - 若该方块没有旧版数字 ID 映射，保留输入供查看，但禁用保存并显示原因。
- 修改 `legacy_id` 时会反向同步 `name`。
- `name` 与 `legacy_id` 均不能重命名或删除，也不能通过根节点“增加/粘贴并覆盖”绕过保护。
- 批量选择/批量删除会排除这两个绑定字段。
- `legacy_data` 仍要求为 0…15。

## 3. 底层保存保护

保护不仅存在于 UI。`BedrockBlockNBTStore` 会再次检查：

- `name` 必须存在且能映射到旧版数字 ID；
- `legacy_id` 必须存在、范围为 0…255，且必须与 `name` 的映射完全一致；
- 旧数字方块不能携带非空现代 `states`；
- 不满足条件时直接拒绝保存。

因此，通过方块 NBT 编辑器把旧数字 ID 方块改成现代无数字 ID 方块时，不再像旧逻辑那样静默把整个旧区块升级成 v9；会明确禁止保存。命令系统等原本独立的区块现代化逻辑不受此限制。

## 4. 回归测试

新增 `Scripts/test_iphone_layout_legacy_block_link.sh`，并加入 `run_core_tests.sh`。同时更新实际 `BedrockBlockNBTStore` 运行测试，验证：

- 现代 states 写入旧数字 ID 方块会失败；
- `minecraft:netherite_block` 这类没有旧数字 ID 映射的名称会失败；
- `minecraft:diamond_block` 与错误的 `legacy_id=5` 会失败；
- `minecraft:diamond_block ↔ legacy_id=57` 可以正常保存；
- 保存后目标和相邻旧 SubChunk 仍保持 v7，LegacyVersion/Data2D 保持不变，不产生 Version/Data3D；
- 之前的 iPhone 地图稳定性、LegacyTerrain/SubChunk v0-v9、旧 zlib 兼容、框选地图导出以及现代 actor 二进制 TAG_String 回归均继续通过。
