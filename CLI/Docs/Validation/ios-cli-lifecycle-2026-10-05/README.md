# Bash 3.2 生命周期修复验证记录

日期：2026-10-05。验证环境：Linux，Python 3.12，GNU Bash 3.2.57(3) 与系统 GNU Bash 5.2.21。

## 输入与范围

| 输入 | SHA-256 |
| --- | --- |
| 上一版完整源码包（730 个文件） | `4875be0cd93ba3b427b7e4a7cec86a7ca65edcadfb4a717a06029fff23cc3f8a` |
| `logs_100792496542.zip`（39,393 字节） | `b237166774035c1dad4b1f5e380493eccc410e2570557511cb314d4791e661cc` |
| 保留的 `Tests/Fixtures/custom_dimensions.mcworld` | `b2b229bc4cc8c9937da461c08b5117501b12bb38791599eca5a6c7b6f63bdcd4` |

`uploaded-ios-build.log` 与 `uploaded-windows-build.log` 是本次上传 ZIP 中 build step 日志的原始字节副本。其他日志来自本次本地验证。旧验证目录与旧变更说明均保持原样，属于历史记录。

生产脚本、生产代码和真实源码清单均保持输入版本，仅修正 `CLI/Tests/apple_build_lifecycle.py` 的夹具。真实 Swift 清单包含 1 个入口和 66 个非入口输入；旧夹具只有入口，未反映真实构建条件。

## 结果

| 检查 | 日志 | 结果 |
| --- | --- | --- |
| 修复前，系统 Bash 5.2 | `bash52-baseline.log` | 通过；体现平台差异 |
| 修复前，Bash 3.2 直接运行 | `bash32-direct-red.log` | 预期失败：原 host 内容断言 |
| 修复前，Bash 3.2 跟踪各分支 | `bash32-red.log` | 预期失败；记录空数组错误、退出码 0 和旧二进制 |
| 修复后，Bash 3.2 全部 8 场景 | `bash32-green.log` | 通过 |
| 修复后，Bash 5.2 全部 8 场景 | `bash52-green.log` | 通过 |
| 工具替身也使用 Bash 3.2 | `bash32-all-shims.log` | 通过 |
| 28 类命令、231 个解析夹具、67 个 Swift 输入的源码审计 | `source-audit.log` | 通过 |
| Windows/Apple 发布与 iOS 13.0 构建配置审计 | `build-audit.log` | 通过 |
| 两项 UTF-8 和原生夹具诊断测试（CP1252 strict） | `support-tests.log` | 通过 |
| Bash 3.2 / 5.2 生产脚本语法 | `bash32-syntax.log` / `bash52-syntax.log` | 通过；空日志是正常结果 |

8 个生命周期场景为 iOS 编译失败、架构失败、平台失败、签名失败、签名验证失败、成功发布，以及 host 夹具构建失败和完整成功。失败场景继续检查旧二进制保留；成功场景检查新二进制和空 stderr。host 成功还检查原生夹具先于两项数据库 smoke 测试构建，各场景继续检查临时目录清理。

`results.json` 记录附加验证的退出码；`files.sha256` 记录本目录各证据文件的摘要。红日志是有意保留的复现证据，不是最终版本的失败结果。

本次上传的 Windows job 已通过原生集成与单 EXE 发布；这是上传的 CI 证据。当前 Linux 环境没有 Apple SDK，本次使用真实 shell 和工具替身，尚未验证真实 iOS 编译、签名或设备执行。发布前重新运行 `.github/workflows/cli-release.yml`。

## 复跑

在项目根目录、macOS 默认 Bash 3.2 环境下运行：

```bash
python3 CLI/Tests/apple_build_lifecycle.py
python3 CLI/Tests/source_audit.py
python3 CLI/Tests/build_audit.py
PYTHONIOENCODING=cp1252:strict python3 CLI/Tests/test_smoke_support.py
bash -n CLI/Scripts/build-apple.sh
```

Linux 上复现旧版 Bash 时，先将指向实际 GNU Bash 3.2.57 的 `bash` 可执行文件或符号链接放入 PATH 首位，再运行同一生命周期测试。该测试用 PATH 中的 `bash` 启动真实脚本，工具替身隔离 SDK 和原生编译工具。Bash 3.2 来自 GNU 官方 3.2 源码及 001–057 补丁，验证用私有工具链未收入源码包。

附加工具替身验证只在运行时更换临时工具脚本的 Bash 解释器，不修改仓库文件。Python 语法及工作区空白检查另执行：

```bash
python3 -m py_compile CLI/Tests/apple_build_lifecycle.py
git diff --check
```
