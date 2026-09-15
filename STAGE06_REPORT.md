# MCBEEditor CLI stage06 报告：NBT/mcstructure 独立格式转换

日期：2026-09-15

## 范围

本阶段从 stage05c 快照继续，只增加独立文件格式转换，不增加 NBT 编辑器功能、不增加世界命令、不修改 LevelDB/Chunk/World 持久化算法。

## 新 CLI

```text
mcbe-cli --convert "input.nbt" --to big-endian --output "output.nbt"
mcbe-cli --convert "input.nbt" --to little-endian --output "output.nbt"
mcbe-cli --convert "input.nbt" --to little-varint --output "output.nbt"
mcbe-cli --convert "input.mcstructure" --to json --output "output.json"
mcbe-cli --convert "java-structure.nbt" --to mcstructure --output "output.mcstructure"
```

已有文件默认不覆盖，使用 `--overwrite` 才覆盖。`mcbe-cli --help convert` 输出专用帮助。

## 格式语义

输入继续使用现有 Standalone NBT 解码器自动识别 Big Endian、Little Endian、Little Endian VarInt、JSON NBT、连续多根 NBT 与 GZip/Zlib 包装。输出 binary NBT 不重新压缩。JSON 使用现有 typed JSON；mcstructure 使用 Bedrock Little Endian，并在需要时复用 JavaStructureConverter。

连续多根 NBT 可以转换为 Big/Little/VarInt/JSON 并保持根标签数量；不能整体转换成 mcstructure。没有加入标签编辑、增删、搜索、合并等编辑器操作。

## 双端实现

- Windows：`CLI/Windows/CliFormatConverter.cs`
- Swift/iOS：`CLI/iOS/CliFormatConverter.swift`
- 程序版本：`MCBEEditor CLI 0.6.0-stage06`
- iOS sources 清单已加入新文件；Windows SDK-style project 自动包含新 `.cs`。
- 两端构建累计门禁加入 `CLI/Tests/stage06_conversion_audit.py`。

## 测试

双端原生集成测试源码新增：专用 help、Little Endian、Little Endian VarInt、JSON、mcstructure、默认拒绝覆盖、显式覆盖、连续多根保持、连续多根禁止转换 mcstructure。

当前 Linux 环境不具备 Windows .NET/MSVC 或 macOS/Xcode，因此平台原生测试仍需相应 runner 实际执行；本报告不会把静态/前端检查写成原生运行通过。

## 本地额外运行验证

在 Linux/Swift 6.2.1 环境中，除前端解析外还使用**测试专用的 Apple bridge / 文件发布 stub**编译了真实的 `StandaloneNBTFileCodec`、`JavaStructureConverter` 与 `CLI/iOS/CliFormatConverter.swift`，并实际执行 JSON → Little Endian → Little VarInt → Big Endian → JSON、覆盖保护、连续多根 NBT 保持，以及 **Java structure NBT → Bedrock mcstructure**；同时验证了转换输出的 `format_version` 与 Java → Bedrock 诊断信息。该运行测试通过。stub 只替代 Linux 不具备的 Apple 压缩 bridge 与 Darwin 文件发布函数，因此这不等价于 iOS Mach-O 真构建，也没有覆盖 GZip/Zlib 输入路径。
