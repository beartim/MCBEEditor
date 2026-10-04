# 固定 ReadMe.txt

本目录提供软件实际写出的六份固定 UTF-8 文本。生产代码内置对应字符串常量，启动时直接恢复该文本，不在运行时调用 help 或拼接命令说明。

| 版本 / 文件夹 | 固定文本 | 生产来源 |
| --- | --- | --- |
| iOS / Commands | `iOS/Commands/ReadMe.txt` | `Sources/Support/SharedCommandFileStore.swift` |
| Windows / Commands | `Windows/Commands/ReadMe.txt` | `Windows/MCBEEditor.Desktop/SharedCommandFileStore.cs` |
| Apple CLI / Commands | `AppleCLI/Commands/ReadMe.txt` | `CLI/iOS/CliSharedCommandStore.swift` |
| Windows CLI / Commands | `WindowsCLI/Commands/ReadMe.txt` | `CLI/Windows/CliSharedCommandStore.cs` |
| iOS / Textures | `iOS/Textures/ReadMe.txt` | `Sources/Support/BlockTextureOverrideStore.swift` |
| Windows / Textures | `Windows/Textures/ReadMe.txt` | `Windows/MCBEEditor.Desktop/BlockTextureOverrideStore.cs` |

已修正原先 Windows GUI 与两套 CLI 中调用帮助函数的实现。Textures 的说明也明确写为“内置的固定说明”。所有 Commands ReadMe 包含当前 28 类游戏命令；两套 CLI 另外包含结构文件路径接口及 `mcbe-snbt` 导出别名。

启动恢复 ReadMe 的行为保留。用户自己的 `Command.txt` 不会被自动创建、修改或删除；iOS 的既有重新激活恢复行为保留。

`python Scripts/test_fixed_readme.py` 编译并运行四个 Commands 生产组件，使用实际临时文件验证：不创建 Command.txt、原样恢复 ReadMe、保留用户文件字节；更换运行时 help 内容不会改变 ReadMe。Linux 中只替换 iOS Documents 根路径及未调用的命令读取依赖，没有把这个组件测试计为 iOS 应用运行验证。

以后更改命令说明时，须在源码中维护固定文本并同步本目录快照。程序仍然只写固定常量。
