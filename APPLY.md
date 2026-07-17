# 应用 Blocktopograph iOS 13 v1.1.9 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版新增：

- `Sources/Command/WorldCommand.swift`：严格命令和方块 states 解析；
- `Sources/Command/WorldCommandExecutor.swift`：玩家物品／出生点及三维 clone、fill 存档修改；
- `Sources/UI/WorldCommandViewController.swift`：世界命令行窗口和维度选择；
- `CHANGES_v1.1.9.md`：完整功能、格式和兼容性说明。

重新生成 Xcode 工程后，版本号为 1.1.9，构建号为 119。
