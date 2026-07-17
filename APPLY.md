# 应用 Blocktopograph iOS 13 v1.1.4 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修改了以下核心文件：

- `Sources/Chunk/MapCoordinate.swift`：增加方块距离与区块半径的双向换算；
- `Sources/World/TickingAreaStore.swift`：圆形常加载区域按游戏原生方块边界读取，并以区块为单位计算半径、地图包含范围和选区相交；
- `Sources/UI/TickingAreaViewControllers.swift`：圆形中心继续按方块坐标编辑，半径改为区块数并按 16 倍写回；
- `Sources/UI/NBTEditingUI.swift`：复制的多个标签全部粘贴，同名冲突仅提供覆盖、保留和取消；
- `Sources/UI/NBTNode.swift`：支持在 Compound 中原位覆盖同名标签；
- 各 NBT 编辑器：统一接入批量粘贴与覆盖标志；
- `Scripts/run_core_tests.sh`：增加半径单位及批量粘贴回归检查。

重新生成 Xcode 工程后，版本号为 1.1.4，构建号为 114。
