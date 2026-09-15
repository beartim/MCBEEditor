# MCBEEditor CLI stage04a 报告

日期：2026-09-15。范围：structure 文件导入、三格式导出、路径参数、覆盖规则和相关回归源码。

## 接口

两端新增 CLI 专用文件接口，不弹 GUI 文件选择器：

```text
structure import 名称 --file "路径.mcstructure|nbt|json" [--overwrite]
structure export mcstructure|nbt|json 名称 --file "输出路径" [--overwrite]
```

内部 tokenizer 支持单/双引号，因此路径可包含空格。导入只接受 `.mcstructure`、`.nbt`、`.json`；导出扩展名必须与指定格式一致。`.nbt` 继续使用 Big Endian，mcstructure 使用 Bedrock Little Endian，JSON 继续使用现有类型化 NBT JSON 编解码。

导入同名结构与导出覆盖已有文件都必须显式 `--overwrite`。文件输出先写同目录临时文件再发布，避免在编码失败时直接截断目标文件。

## 复用而非重写

Windows 使用现有 `StandaloneNbtFileCodec`、`JavaStructureConverter`、`StructureNbtStore`；Swift 使用 `StandaloneNBTFileCodec`、`JavaStructureConverter`、`StructureNBTStore`。因此 Java 结构转 Bedrock、NBT 三种 endian 识别、JSON 类型和 LevelDB `structuretemplate_` 存储规则仍与 GUI 共用同一实现。

一次性 `--command/--script` 中，缺少结构名或 `--file` 会在整批执行前拒绝，防止前置修改已经执行后才发现文件参数不完整。交互会话可省略名称，由 04b 提示输入；export 会先列出现有结构名。

## 回归源码与实际检查

Windows/Swift 原生集成测试源码增加：带空格路径导出、再次导入并从 LevelDB 验证、缺名称整批预检。`stage04_source_audit.py` 检查两端均复用原 codec/store 且新 Swift 文件进入 `sources.txt`。

本环境执行的 stage04 源码审计和 Swift 前端语法解析通过。没有 .NET/Windows 原生工具链，也没有 macOS/Xcode，新增真实 LevelDB 场景尚未编译/运行。日志见 `CLI/Validation/Stage04a/`。
