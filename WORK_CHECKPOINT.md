# MCBEEditor CLI 最新检查点：stage06（NBT/mcstructure 格式转换）

日期：2026-09-15。当前功能快照从 stage05c 最终审计基线继续，新增独立文件格式转换；不要用 stage05c 或更早快照覆盖当前工程。

## stage06 新增范围

- 双端新增 `mcbe-cli --convert 输入 --to 格式 --output 输出 [--overwrite]`；
- 目标格式：`big-endian`、`little-endian`、`little-varint`、`json`、`mcstructure`；
- 输入自动识别现有 Standalone NBT codec 已支持的 Big/Little/VarInt、JSON、连续 NBT、GZip/Zlib；
- `.mcstructure` 继续复用既有 Java → Bedrock structure 转换；
- 多根 NBT 可在三种 NBT 编码和 JSON 之间转换，不能整体转 mcstructure；
- 无 NBT 树编辑、搜索、增删标签或批量编辑功能；不依赖 `--world`；
- 版本更新为 `MCBEEditor CLI 0.6.0-stage06`。

## 发布形态不变

- Windows：x64 绿色单 `mcbe-cli.exe`；
- iOS：最低 iOS 13、arm64 裸 `mcbe-cli` Mach-O；
- 不制作 deb。

## 验证边界

当前 Linux 环境可运行 Python/source audit、bash 语法和 Swift 前端解析；没有 .NET/PowerShell，也不是 macOS/Xcode，因此 Windows/.NET 原生转换测试、macOS host 原生链接、iOS arm64 真构建/签名、GitHub Actions、设备执行仍需对应平台确认。双端原生集成测试源码已加入转换场景，平台 `-Test` 构建会实际执行。

stage05c 继续作为此前全量需求/发布链审计基线，stage06 只叠加文件转换工具。后续修复应重新执行累计 stage05c + stage06 门禁。

当前 Linux 环境额外使用测试专用 Apple bridge/文件发布 stub，编译并执行了真实 Swift `CliFormatConverter` + Standalone NBT codec + `JavaStructureConverter`，实际验证 JSON/三种 NBT 编码、多根 NBT、覆盖保护和 Java structure → Bedrock mcstructure；这不等价于 iOS/macOS 原生构建。
