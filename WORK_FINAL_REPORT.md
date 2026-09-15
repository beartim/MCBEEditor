# MCBEEditor CLI 当前最终报告（stage06）

日期：2026-09-15

stage05c 已完成此前全部世界命令、保存、交互、发布链和冗余代码的全量审计；stage06 在该稳定基线上仅叠加独立 NBT/mcstructure 文件格式转换工具。

当前运行时版本为 `MCBEEditor CLI 0.6.0-stage06`。Windows 仍以 x64 绿色单 `mcbe-cli.exe` 发布，iOS 仍以最低 iOS 13 的 arm64 裸 `mcbe-cli` Mach-O 发布，不制作 deb。

stage06 支持 `--convert 输入 --to big-endian|little-endian|little-varint|json|mcstructure --output 输出 [--overwrite]`。输入自动识别现有 codec 支持的 Big/Little/VarInt、JSON、连续 NBT 和 GZip/Zlib；输出 binary NBT 为未压缩。mcstructure 只允许单根结构，并继续复用 Java → Bedrock structure 转换。没有引入 NBT 编辑器功能。

26 个世界根命令及 stage05c 已审计的 Bedrock 持久化语义保持不变。stage06 新增双端原生集成回归源码与独立 source audit，并接入累计 Windows/Apple 测试脚本。

当前执行环境为 Linux x86_64、Swift 6.2.1；能完成源码审计、Swift 前端 parse、Python/bash/元数据检查，但没有 Windows .NET/MSVC，也不是 macOS/Xcode。因此 Windows 最终 EXE、Windows 原生转换集成、macOS host 原生链接、iOS arm64/lipo/vtool/codesign、GitHub Actions、iOS 设备与 Minecraft 实际读档仍必须保持为未验证，等待对应平台执行。

当前 Linux 环境额外使用测试专用 Apple bridge/文件发布 stub，编译并执行了真实 Swift `CliFormatConverter` + Standalone NBT codec + `JavaStructureConverter`，实际验证 JSON/三种 NBT 编码、多根 NBT、覆盖保护和 Java structure → Bedrock mcstructure；这不等价于 iOS/macOS 原生构建。
