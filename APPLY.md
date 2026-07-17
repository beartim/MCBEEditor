# 应用 Blocktopograph iOS 13 v1.1.5 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修改了以下核心文件：

- `Sources/NBT/NBTClipboardCodec.swift`：新增批量 NBT 剪贴板二进制编解码，保证多个标签完整保留；
- `Sources/UI/NBTEditingUI.swift`：一次写入批量与兼容剪贴板格式；新增 nbt/mcstructure/json 文件导入、同名冲突处理和 List 类型校验；
- 各 NBT 编辑器：新增子标签导入入口并传递覆盖标志；
- `StandaloneNBTFileViewController.swift`、`MetadataNBTViewControllers.swift`：新建根标签时支持一次导入多个根标签；
- `Tests/BlocktopographTests.swift`、`Scripts/run_core_tests.sh`：增加三标签批量剪贴板往返测试和导入入口静态检查。

重新生成 Xcode 工程后，版本号为 1.1.5，构建号为 115。
