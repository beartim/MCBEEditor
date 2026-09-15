# MCBEEditor CLI Stage 05b 报告：iOS 13 arm64 裸二进制发布

日期：2026-09-15。用户在批准 05a/05b 实现后明确补充：**iOS 可以只有裸二进制构建**。因此本阶段最终范围是不制作 deb，不再要求 rootful/rootless 两套安装布局。

## 已实现源码

1. 继续使用现有 `CLI/Scripts/build-apple.sh ios CLI/build/apple-ios` 作为唯一 iOS CLI 编译入口；目标保持 `arm64-apple-ios13.0`，直接链接现有 Apple LevelDB bridge、leveldb-mcpe 与 zlib。
2. iOS 编译后继续用 `xcrun lipo -archs` 要求只有 `arm64`；用 `xcrun vtool -show-build` 要求平台为 iOS、`minos` 为 13.0。
3. 对最终裸 Mach-O 执行 Apple ad-hoc 结构签名：`codesign --force --sign - --timestamp=none`，随后 `codesign --verify --strict`。同时在构建目录生成 `codesign.txt` 和 `mcbe-cli.sha256` 供 runner 日志/诊断使用。
4. `.github/workflows/cli-release.yml` 新增 `macos-15` job：
   - 先运行 `build-apple.sh host ... --test`，执行共享命令/存档/LevelDB 回归；
   - 再交叉编译 iOS 13 arm64；
   - GitHub artifact `MCBEEditor-CLI-iOS13-arm64` **只上传** `CLI/build/apple-ios/mcbe-cli` 裸二进制，不生成 deb。
5. README 和阶段说明已经把 deb/rootful/rootless 从 05b 退出条件删除。artifact 服务可能不保留 Unix executable bit，下载后部署到设备前需要时执行 `chmod +x mcbe-cli`。
6. 程序版本双端统一更新为 `MCBEEditor CLI 0.5.0-stage05b`；共享 smoke 预期同步更新。旧阶段源码审计允许这个更高阶段版本，避免发布版本升级导致历史功能门禁误报。

## TDD / 范围调整记录

`CLI/Tests/stage05b_source_audit.py` 先在 stage04e 基线上运行并按预期失败，失败点包括旧阶段文档仍要求 deb 以及不存在独立 release workflow；改为裸二进制发布后转绿。

05b 没有引入新的 Swift 命令执行算法，也没有复制一套 LevelDB/NBT 实现；编译输入仍来自同一 `CLI/iOS/sources.txt` 和 Apple native bridge。

## 当前环境实际验证

当前 Linux 环境实际通过：05b 源码门禁、全部累计源码审计、`build-apple.sh` 的 `bash -n`、61 个 Swift 生产输入和 `NativeIntegration.swift` 的 `swiftc -frontend -parse`。

当前环境不是 macOS/Xcode，因此实际执行 `build-apple.sh ios ...` 会在 `macOS with Xcode is required.` 环境门禁退出。这不是 iOS 构建失败，也不是构建通过；下列检查仍需 macOS runner：

- Objective-C++/LevelDB bridge 编译与链接；
- iOS arm64 Mach-O 真实生成；
- `lipo`/`vtool` 元数据检查；
- `codesign` ad-hoc 签名与验证；
- GitHub Actions macOS job；
- iOS 设备运行和 Minecraft 实际读档。

下一阶段只剩 05c 全量最终审计；如果 Actions 在此之前给出真实 Windows/macOS 编译日志，应优先修复明确的失败。
