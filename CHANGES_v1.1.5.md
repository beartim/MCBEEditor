# Blocktopograph iOS 13 v1.1.5

## NBT 多标签粘贴修复

- 修复复制多个 NBT 标签后仍只粘贴出第一个标签的问题。
- 根因是旧实现连续调用两次 `UIPasteboard.setData`：部分 iOS 环境会在写入旧版单标签兼容数据时覆盖先前的批量数据。
- 现在使用一次 `UIPasteboard.setItems`，把批量格式和旧版单标签兼容格式放入同一个剪贴板项目。
- 新增独立的 `NBTClipboardCodec`：
  - 按复制顺序保存全部 NBT 根标签；
  - 保留每个标签的名称、完整 NBT 类型和数值；
  - 校验标签数量、每项长度、截断数据及多余尾部数据；
  - 继续兼容只包含单标签格式的旧剪贴板数据。
- Compound 同名冲突行为保持为“覆盖、保留、取消”，不再要求修改标签名称。
- List 会一次粘贴所有复制项，并要求所有项目与列表元素类型一致。

## 从文件导入 NBT 标签

- 所有 Compound/List 的“增加 NBT 标签”菜单新增“导入 NBT／mcstructure／JSON…”。
- 支持：
  - Big Endian NBT；
  - Little Endian NBT；
  - Little Endian VarInt NBT；
  - GZip/Zlib 包装；
  - 连续多个根标签；
  - Bedrock `.mcstructure`；
  - Blocktopograph 类型化 JSON NBT；
  - 可推断为 NBT 的普通 JSON。
- 导入到 Compound 时：
  - 优先使用文件内的根标签名称；
  - 根名称为空时使用文件名；
  - 连续多个空名称根标签会使用“文件名 1、文件名 2……”；
  - 与现有标签重名时使用相同的覆盖/保留冲突弹窗。
- 导入到 List 时会忽略根名称并一次加入所有根值；类型不一致时拒绝写入。
- 独立 NBT 文件和元数据连续 NBT 的“新建根标签”菜单也支持一次导入一个或多个根标签。
- 文件选择器严格限制最终扩展名为 `.nbt`、`.mcstructure` 或 `.json`，并正确处理 iOS 文件提供程序的安全作用域访问。

## 验证

- 新增三标签批量剪贴板编码、解码与顺序保持可执行测试。
- 新增 Xcode XCTest 批量剪贴板往返测试。
- 全部 Swift 源码和测试文件通过语法解析。
- 核心回归测试通过。

## 版本

- MARKETING_VERSION：1.1.5
- CURRENT_PROJECT_VERSION：115
