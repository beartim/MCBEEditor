# iOS 与两个 CLI 构建流程修复（2026-11-03）

根据本轮提供的三份 CI 日志，在上一版
`MCBEEditor-entity-nbt-save-refresh-source.zip` 上修复。

## 失败原因及修正

1. iOS GUI 在执行 portable core tests 时，新加入的实体 NBT 保存重开测试
   生成的 `ui.swift` 使用 `CGRect.zero`，但没有显式导入 CoreGraphics。
   这在 macOS 上报错。为生成的 UI 和控制器文件添加条件导入，与项目已有
   地图几何测试的跨平台写法一致。
2. iOS CLI 的程序已经编译成功，随后原生集成测试仍假定无参数 `entity`
   不包含玩家，故把有两名玩家的世界误判为空结果。现在验证两名玩家的
   类型、维度、实际坐标及完整 NBT，并用未命中 identifier 的查询单独验证
   空结果。后续 pig/cow 测试也同步当前带 metadata 的输出，检查精确 Long
   和原始 NBT 字节。
3. Windows CLI 同样在编译后的原生集成测试失败。召唤测试仍按旧展示格式
   匹配空/嵌套 List 文本。现在从真实 CLI 查询结果中提取 MCBE-SNBT，使用
   文件 codec 解码并与独立构造的完整 NBT 字节比较，同时检查维度和坐标。

修改的已有文件仅为上述三个测试文件。没有关闭测试关卡，也没有更改
entity 的玩家查询、输出或存储行为。版本仍为 1.0.0，最低 iOS 13.0。

详细证据、复现与平台验证范围见
[验证记录](Docs/BuildFix20261103/VALIDATION.md)。
