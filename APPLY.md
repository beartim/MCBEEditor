# 应用 Blocktopograph iOS 13 v1.1.2 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修改了以下核心文件：

- `Sources/World/TickingAreaStore.swift`：改用 Minecraft 原生的逐键 `tickingarea_<UUID>` 存储，并迁移旧版单键连续 NBT；
- `Sources/UI/TickingAreaViewControllers.swift`：增加按地图/区块选区筛选的常加载区域管理；
- `Sources/UI/WorldMapViewController.swift`：地图框选菜单增加常加载区域编辑；
- `Sources/UI/ChunkListViewController.swift`：单区块和批量区块菜单增加常加载区域编辑。

重新生成 Xcode 工程后，版本号为 1.1.2，构建号为 112。
