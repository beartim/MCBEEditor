# 应用 Blocktopograph iOS 13 v1.1.19 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版新增：

- `setblock` 单坐标双层方块修改；
- `setworldspawn` 世界重生点修改；
- `spawnpoint` 玩家目标选择器重生点修改；
- `structure save/load/delete`，支持覆盖保存、跨维度加载与 `ALL` 删除；
- `tickingarea add/delete/list`，支持矩形、圆形、预加载与逐行列表；
- 新增命令的严格参数校验与可执行回归。

重新生成 Xcode 工程后，版本号为 1.1.19，构建号为 129。
