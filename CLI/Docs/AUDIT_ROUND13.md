# 第 13 轮：Windows 发布链

日期：2026-09-24。基线为第十二轮完整源码包，SHA-256：`6cd24ea8c184f28d1927e48e76a16737486d9df570b47ede1154378a0c2a7674`。

状态：发布脚本修订、测试接线与静态检查已完成；没有生成或验收 Windows EXE。

## 修改与依据

- 发布脚本此前使用 `Set-Content -Encoding utf8NoBOM`，不兼容文档所列 Windows PowerShell 5.1 入口。改用明确的 .NET UTF8Encoding(false) 写入，并为包含中文的脚本增加 UTF-8 BOM，避免 5.1 按系统代码页读取中文断言。
- 新增 portable_release_smoke.py，接到 build-windows-release.ps1 -Test。实际复制最终外层 EXE 到中文/空格路径，验证返回码 2/3、标准输入预检和交互退出、中文相对脚本路径、用户 Command.txt 字节保留、同级 ReadMe 与运行时目录清理。
- 新探针使用构建产生的真实 LevelDB fixture 工具，新建临时数据库，移动至中文世界路径后通过最终 EXE 执行 chunk query；核对源世界文件未改。这补上原先仅验证托管入口、没有验证单文件包内原生 DLL 加载的缺口。
- fixture 工具 Windows narrow argv 限制通过 ASCII 相对创建路径规避；实际查询仍覆盖中文世界路径。没有修改生产数据库或添加伪原生后端。
- 发布目录仍只能包含一个 mcbe-cli.exe。原生静态链接、x64、控制台句柄、命令行引用、工作目录保留、缓存清理源码已检查，未在缺少平台条件下推测修改。

## 验证证据与边界

- build_audit 新增 PowerShell 编码门禁在基线上失败，修订后通过。该结果仅为源码/配置契约，不是 PowerShell 执行结果。
- source_audit、build_audit、gui_nbt_audit、map_projection_audit 通过；新增 Python 脚本语法编译通过。
- 当前环境无 dotnet、swift、pwsh、cmake、Windows SDK/MSVC；没有运行 C# / C++ 编译、PowerShell 5.1/7、原生进程探针、WPF、无 .NET 环境或 Minecraft。
- 新测试由 Windows CI 的已有 -Test 发布入口调用，测试失败会阻止后续产物上传；本轮没有触发远程 CI。
- 第十二轮文件逐项保留；仅变更本轮列明的脚本、静态门禁与进度文档，新 ZIP 校验通过后交付。

## 待平台验证

在 Windows 执行 `powershell -NoProfile -ExecutionPolicy Bypass -File CLI/Scripts/build-windows-release.ps1 -Test`，另执行 `Windows/build.cmd` 验证 GUI 发布。分别留存 PowerShell 5.1/7、无已安装 .NET 机器运行和 GUI 结果。Ctrl+C、并发启动、只读目录、杀进程后的残留清理仍需补充实测。

下一轮为第 14 轮 Apple 发布链；前轮所有未完成专项仍保留。遵循用户每轮限时约定，平台构建不以静态结果替代。
