# MCBEEditor CLI stage03c 报告

日期：2026-09-15。范围：Swift 保存链路与 Apple 原生构建输入专项复核。此报告是本次 stage04b 综合快照中的 03c 子阶段记录。

## 完成内容

复核 `CliWorldWorkspace`、文件系统/路径、`MiniZipArchive`、`WorldSession`、Apple 原生 CMake/bridge 输入和 `build-apple.sh`。保存契约保持：另存为只导出世界根并沿用 GUI 编辑器私有元数据过滤；mcworld 原位提交从完整解压容器重建，保留世界外条目和容器层级并排除世界 `db/LOCK`。

修正持续会话会依赖的一处生命周期问题：`CliWorldWorkspace.sourceStamp` 改为可刷新，成功原位提交后重新计算源指纹。否则未来同一会话第二次 `:save` 会把本会话第一次提交误判为“外部修改”。Windows 对应 `CliWorldSession` 在 04b 接入时同步刷新，避免两端行为分叉。

没有改动 `MiniZipArchive` 编解码算法、LevelDB bridge、CMakeLists、bootstrap 依赖版本、末地高层/255 storage 算法。Apple 源清单后续在 04a/04b 增加两个 CLI Swift 文件，构建脚本仍从 `sources.txt` 统一读取。

## 实际验证

`stage03_source_audit.py` 通过；`build-apple.sh` 通过 `bash -n`。当前环境为 Linux，不是 macOS/Xcode；因此 Objective-C++ bridge、Mojang LevelDB 静态库、macOS host 可执行文件、iOS arm64 交叉编译和真实原生集成测试没有运行。后续 04a/04b 完成后，Linux Swift 6.2.1 对最终 59 个 Swift 构建输入和 `NativeIntegration.swift` 做了 `-frontend -parse`，语法解析通过，但这不等于 Apple 编译/链接通过。

实际日志位于 `CLI/Validation/Stage03c/`。Apple 真正门禁仍是：

```sh
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
bash CLI/Scripts/build-apple.sh ios CLI/build/apple-ios
```
