# 第 14 轮：Apple / iOS 13 发布链

日期：2026-09-24。基线第十三轮完整源码包，SHA-256：`ab52e6614afec2568c631c0269506bfc72786a7e350f3a9d00f15820ce122ca5`。

状态：Apple 构建产物保护修订、脚本流程测试及静态核对已交付；未生成或验收 iOS 二进制/IPA。

## 问题与修改

旧 build-apple.sh 直接以正式 OUT/mcbe-cli 为编译输出，之后才执行 host 测试或 iOS 架构、平台、签名校验。编译器留下部分文件、签名失败等情况会覆盖上一份正式产物，脚本即使返回失败，正式文件仍可能被误用。

现在在输出目录内创建独立临时目录，将编译、host 进程测试、iOS arm64 / IOS / minos 13.0 检查和签名验证指向候选二进制。全部成功后以同文件系统 mv 替换正式二进制；正常退出或失败由 EXIT trap 清理临时目录。此前正常二进制在这些验证失败时保留。

平台、签名报告和 SHA-256 在临时目录生成；校验值改为相对文件名 mcbe-cli，便于在交付目录执行 shasum -a 256 -c mcbe-cli.sha256。报告移动后最后替换二进制；多个报告与二进制并非整体事务，磁盘故障或并发写相同输出目录仍需独立处理，不作这类保证。

## 实际测试

- 新增 apple_build_lifecycle.py：复制真实构建脚本至隔离目录，对 uname / CMake / xcrun / codesign / shasum 使用可控工具替身。初次执行基线在 compile 场景失败，明确复现覆盖旧产物。
- 修订后六场景通过：编译失败、错误架构、错误平台、签名失败、验签失败均保留旧二进制；成功流程发布新二进制。均检查临时目录清理，输出路径包含空格。
- 这是实际 shell 流程测试，**不是 Swift/C++、Mach-O、签名或原生数据库测试**。模拟产物与模拟校验值从未作为交付二进制。
- 流程测试接入 host --test，并由现有 Apple CI host 测试入口覆盖。build_audit 同时校验接线。
- source_audit、build_audit、gui_nbt_audit、map_projection_audit 通过；构建、依赖引导、IPA 脚本 bash -n 通过；新增 Python 语法检查通过。

## 源码检查结论与限制

- 62 项 CLI Swift 输入存在，命令入口无 UIKit 依赖；既有 FileHandle iOS 13 API 修订保留。类型检查与 SDK 可用性仍必须由真实目标编译确认。
- CLI iOS 目标 arm64-apple-ios13.0、CMake iphoneos SDK/arm64/13.0、静态 LevelDB/zlib/ObjC++ bridge 链接、ad-hoc 签名及严格验签仍保留。
- GUI project.yml 的 iOS 13.0、Swift 5 和静态原生库设置保留；IPA 脚本核对 MinimumOSVersion。未运行 XcodeGen、xcodebuild 或 IPA 安装。
- 本环境缺少 swiftc、clang、cmake、xcrun、codesign 和 Apple SDK。没有真实 host 构建、LevelDB 集成、iOS arm64 编译、Mach-O 检查、签名、UIKit/GUI、iOS 13 终端启动或游戏读档结果。
- 现有 workflow 固定的 Xcode 路径仅检查配置；远程 runner 是否仍提供该版本未验证，本轮未触发 CI，也未擅自更换工具链。
- host 与 ios 应使用不同输出目录；CMake 缓存跨平台复用、动态依赖审计、Ctrl-C/权限、真机缓存及文件访问列入平台补充验证。

## 接续

在 macOS/Xcode 执行：

```bash
bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test
bash CLI/Scripts/build-apple.sh ios CLI/build/apple-ios
bash Scripts/build_unsigned_ipa.sh
```

ad-hoc 验签只证明结构签名，不能证明目标 iOS 设备允许执行。第 15 轮做汇总复核，必须保留前轮与本轮全部未验证专项，不得自动宣称收尾验收通过。
