# 第 7 轮：CLI 和批处理维度同步

包含前六轮全部修改。新增世界范围的纯内存 DimensionCommandContext，GUI/CLI 的命令文件预检按顺序投影 add/empty/purge。新增名称能被同批后续命令使用；重复名称/ID、已删除名称及无效语法使整批拒绝。预检不会写数据库。执行时重新按当前工作副本解析原始命令，避免使用失败命令之后的过期映射。

Apple/Windows CLI 的无世界 --check/--check-file 验证名称语法；执行入口在打开工作副本后再进行世界绑定。交互输入、显式脚本、Commands/Command.txt 和两个 GUI 的批处理入口均已接入。

本轮实际验证：
- C# Core 全套自测、维度 query/add/empty/purge/resolver/context 专项通过。
- C# CLI 编译通过（零警告、零错误），真实 Mojang LevelDB 集成主套件 44 次调用通过；专项额外覆盖 add→setblock→getblock→empty→query、导出重开和整批拒绝不修改源存档。
- Windows GUI 跨平台编译通过（零警告、零错误）；未在 Windows 运行 GUI。
- Swift 6.2.3 Linux 上维度存储专项、真实 Swift 解析器与命令执行器测试、216 个共享解析用例、98 项源码审计通过。文件系统/数据库在 Swift 命令执行器测试中使用既有测试替身；Apple ObjC 桥与平台应用构建不在此结果内。
- 28 命令帮助、构建输入和 iOS 13 检查通过；Apple 构建生命周期检查使用工具替身。

已更新旧 entity 数值维度拒绝用例，以及当前 GUI 固定 ReadMe 帮助副本。原示例存档未改动。版本继续为 1.0.0。

下一轮：样例存档实际删除/清空/新增/导出重开验证、完整命令示例、独立代码审查与最终源码交付。
