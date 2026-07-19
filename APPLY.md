# 应用 MCBEEditor iOS 13 固定版 1.0.0 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修改：

- 实体目标选择器支持 identifier，并在缺少 `identifier` 标签时读取 `definitions[0]`；
- `tickingarea add circle` 使用维度、中心区块坐标、区块半径、名称和预加载布尔值；所有 `tickingarea add` 遇到同名区域时先删除旧区域再创建；
- `teleport` 支持目标选择器/UniqueID/identifier、跨维度传送及 Y=`Auto`，Auto 无地面时回退到 Y=63；
- 新增 `time query/add/set/ceil/floor`；
- 新增 `weather clear/rain/thunder`；
- 天气命令与信息页天气栏目统一读写 `rainLevel`、`rainTime`、`lightningLevel`、`lightningTime` 和 `doWeatherCycle`；
- 天气栏目新增“天气自动变化”开关；
- 新增 `daylock 0或1`，只修改 `dodaylightcycle`；
- 新增 `spread 目标`，按玩家优先顺序随机传送到已加载区块的非全空气坐标列，并区分本地/在线玩家输出颜色；
- 地图渲染范围不设固定区块数量上限；中心和缩放按维度在当前会话中保留，关闭存档后不保存；
- 地图六种渲染模式（地表、高度等）的选择只在当前打开存档期间保留，退出存档后恢复默认地表模式；
- 地图对象图层新增默认开启的“显示玩家”，位于“显示实体”上方；本地玩家使用黄色五角星，在线玩家使用蓝色五角星，点击后打开对应玩家菜单；
- “显示出生点”移动到“显示方块实体”下方；
- 实体栏目半径模式的四个蓝色按钮只与中心、半径两行对齐；
- 软件整体名称统一改为 MCBEEditor；工程名、Target、Scheme、Bundle ID、显示名称、构建脚本、IPA 名称、导入导出格式标识、剪贴板类型、临时导出文件名及错误类型均已同步；旧版 NBT JSON 与剪贴板标识只保留导入兼容；
- 软件版本固定为 1.0.0，构建号固定为 100。

重新生成 Xcode 工程后，版本号为 1.0.0，构建号为 100。
