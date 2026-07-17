# 应用 Blocktopograph iOS 13 v1.1.3 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修改了以下核心文件：

- `Sources/Entity/BedrockWorldObjectNBTStore.swift`：增加实体/方块实体创建与删除，并在修改实体 UniqueID 时迁移 `actorprefix` 和 `digp`；
- `Sources/UI/WorldObjectCreationViewController.swift`：新增对象创建/复制表单；
- `Sources/UI/EntityBrowserViewController.swift`：增加新建、复制、删除入口；
- `Sources/UI/WorldObjectNBTEditorViewController.swift`：允许修改 UniqueID 值，但继续禁止删除或重命名；
- `Scripts/run_core_tests.sh`：增加创建、删除和 UniqueID 索引迁移回归测试。

重新生成 Xcode 工程后，版本号为 1.1.3，构建号为 113。
