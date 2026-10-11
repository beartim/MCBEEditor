# iOS GUI 构建修复

针对 `logs_103365066932.zip` 修正 iOS 构建流程的地图回归测试编译错误。项目版本仍为 1.0.0，最低 iOS 版本仍为 13.0。

## 原因及修正

原日志在 `Run portable core tests` 步骤停止，尚未执行后续模拟器或 IPA 构建。`Scripts/test_ios_map_object_interaction.py` 生成的 Swift 测试只导入 Foundation，在 macOS/Xcode 15.4 中缺少 CoreGraphics 的几何类型扩展，导致 CGRect 参数构造、CGPoint/CGRect.zero、CGFloat 运算等连续报错。

现在在测试生成的 Swift 文件中增加条件导入：

```swift
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
```

Apple 平台使用 CoreGraphics 的几何接口；Linux 继续使用 Foundation 的几何类型。地图命中、菜单锚点和回归断言保持原实现，构建流程仍执行完整地图及核心测试。

本次原有文件仅修改该测试脚本。上一版 iOS 地图菜单修复、全部 Windows/CLI 源码、维度命令、fill/setblock 方块实体参数及六份固定 ReadMe.txt 均保持原内容。

## 验证及复测

本地验证使用 Linux Swift 5.10.1，执行：

```bash
python3 Scripts/test_ios_map_object_interaction.py
bash Scripts/run_core_tests.sh
python3 CLI/Tests/source_audit.py
python3 CLI/Tests/build_audit.py
python3 -m py_compile Scripts/test_ios_map_object_interaction.py
git diff --check
```

上述检查均通过。地图回归的 1,740 项检查通过，全量 Swift 核心回归退出码为 0，包含 98 项源码审计检查。

本地结果见 `logs/geometry-green.log` 和 `logs/swift-core.log`；`logs/original-ci-logs.zip` 是上传的原始 CI 日志压缩包，保留原内容。

当前 Linux 环境没有 Xcode，未本地执行 macOS CoreGraphics 分支、iOS 模拟器构建或 IPA 构建。现有 `Build iOS 13` 工作流使用 Xcode 15.4，保留完整回归、模拟器与 IPA 构建步骤，用于 Apple 平台复测。
