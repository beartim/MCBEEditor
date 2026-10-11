# MCBE-SNBT 未指定类型的空 List 修复

版本保持 1.0.0，iOS 最低版本保持 13.0。本次修复基于已交付的完整 iOS、Windows、CLI 源码。

## 格式与行为

未指定元素类型的空 List 统一输出并接受：

```text
'List'''"Items"=""
```

NBT 二进制仍保存元素类型 0、元素数目 0。已指定元素类型的空 List 保留该类型，例如 `'List''Compound'"Items"=""`。空类型只能声明 List 的元素类型；普通标签或非空 List 不能使用空类型。

文件工具继续兼容旧的 `'List''End'` 空 List 输入，导出时规范化为新写法。命令解析不新增普通 End 标签类型。嵌套空 List、同型和异型子列表也使用新空类型标记，并可从查询输出再次输入。

匿名子列表须完整解析描述符、等号、载荷及闭合括号。已有紧凑 List<String> 中的单引号字符串和类型样式字符串保持原内容，包括首项 `"'List''Int'=[1]"` 和 `"'List''String'=[abc]"`。异型未知子类型、无类型非空 List 和数值列表的错误结构仍拒绝。

## 共享入口

| 入口 | 处理位置 |
| --- | --- |
| iOS GUI 与 Apple CLI 的 TXT、独立 NBT、连续根、结构及标签导入导出 | `Sources/NBT/MCBESNBTCodec.swift`，通过 StandaloneNBTFileCodec 共用 |
| Windows GUI 与 Windows CLI 的相应文件操作 | `Windows/MCBEEditor.Core/Nbt/McbeSnbtCodec.cs` |
| Swift summon、give、方块 states 等命令输入 | `Sources/Command/WorldCommand.swift` |
| Swift entity、getblock 及共用 NBT 命令输出 | `Sources/Command/WorldCommandExecutor.swift` |
| C# 共用命令 NBT 输入与输出 | `Windows/MCBEEditor.Core/Chunk/BlockCommand.cs` |

格式说明见 `Docs/MCBE-SNBT.md`；CLI 说明同步更新。

## 验证

- Swift 完整核心回归返回 0，最后的 98 项源代码审查门禁完成；实际 summon、entity、getblock 路径验证空 List、嵌套和字符串的字节往返。
- C# 完整 CoreSelfTest 与 CLI 编译成功。68 个共用文件样例、246 个共用命令解析样例以及 308 次 CLI 检查通过。
- 实际 C# CLI 的 TXT 转换验证 71 个场景、152 次调用；Swift 文件 probe 验证 71 个场景、138 次调用。另有 46 次原有二进制/JSON 转换回归。
- 两个方向的 Swift/C# TXT 互读各验证 34 个有效样例，结果与预期 NBT 二进制逐字节一致。
- 实际 Mojang LevelDB 的 CLI 集成验证通过：44 项主调用，并包含 summon 写入、导出重开、源存档完整性、查询读回及 10 项结构 TXT 专项。
- 固定 ReadMe 的真实文件写入回归通过；六份固定 ReadMe.txt 与示例 `custom_dimensions.mcworld` 均保持原字节。

测试执行于 Linux；未声称已在 iOS SDK/设备或 Windows GUI 上执行。两项 Windows FileShare 锁语义用例在 POSIX 上明确跳过。完整日志、失败复现及最终退出码见 `Docs/MCBESNBTEmptyList/README.md` 和其 `logs/`。
