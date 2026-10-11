# iOS 地图菜单修复

本次修复实体、方块实体及玩家图标在不同缩放比例下点选无菜单、菜单偏移及尖头未指向图标的问题。版本仍为 1.0.0，最低 iOS 版本仍为 13.0。

## 修复内容

- Y 俯视地图原来按方块距离判断实体命中，而图标按固定屏幕大小绘制。现在 Y/X/Z 地图共同使用连续屏幕坐标命中，避免低缩放漏点和高缩放误选。
- 单击手势由地图图像改为地图滚动视口接收。图标超出缩放后图像边缘但仍显示在视口时，也能点选；点选图像外的空白不会误选边缘方块。
- 实体、方块实体和玩家菜单保留所选图标的投影坐标，使用固定图标覆盖层作为菜单锚点。尖头对准该图标中心；部分被视口裁切的图标使用最近的可见边缘。
- 玩家重叠选择菜单也使用视口坐标，选定玩家后的菜单按该玩家图标定位。打开玩家菜单会清除此前的实体闪烁选择。

修改的生产文件只有 `Sources/UI/WorldMapViewController.swift`。原有维度命令、fill/setblock 方块实体参数及 MCBE-SNBT 空 List 处理保持原实现，固定 Commands/Textures `ReadMe.txt` 未改写。

## 已执行的验证

| 检查 | 结果 | 验证范围 |
| --- | --- | --- |
| 新增地图回归 | 1,740 项通过 | 8 种缩放、Y/X/Z、3 种画布密度、实体/方块实体/本地及在线玩家、隐藏图标、平移和视口边缘 |
| 同一回归对旧版本 | 425 项失败，符合预期 | 复现旧命中及菜单中心锚点错误，详见 `logs/geometry-red.log` |
| Swift 全量核心回归 | 退出码 0 | 包含命令、NBT、维度、fill/setblock 方块实体、地图投影及 98 项源代码审计 |
| 玩家图层/重命名回归 | 退出码 0 | 保留玩家图层、编辑入口、改名和临时渲染模式检查 |
| 地图控制器 Swift 语法解析 | 退出码 0 | `swiftc -frontend -parse Sources/UI/WorldMapViewController.swift` |
| CLI/构建/GUI NBT/地图源审计 | 退出码 0 | 源码及构建入口契约；Apple 生命周期用工具替身验证 |
| 独立代码审查 | 未发现重要问题 | 命中坐标、手势调用链、菜单锚点及旧功能保留 |

几何回归从生产 Swift 文件提取并执行实际命中与锚点方法，只替换 UIKit 视图转换和弹出菜单对象为仿射坐标测试夹具。手势注册及菜单调用链另外进行源码检查。日志包含在本目录的 `logs/` 下。

当前环境为 Linux，没有执行 Xcode 原生构建或 iOS 真机 UI 测试。上述回归没有执行真实 UIKit 手势仲裁、popover 排版和侧栏收缩动画。

## 复测命令

在项目根目录、安装 Swift 和 Python 3 的环境执行：

```bash
python3 Scripts/test_ios_map_object_interaction.py
bash Scripts/run_core_tests.sh
bash Scripts/test_mcbeeditor_map_player_rename.sh
swiftc -frontend -parse Sources/UI/WorldMapViewController.swift
```

真机复测可在 Y/X/Z 地图上切换低、中、高缩放和平移，分别点选实体、方块实体、本地及在线玩家；检查菜单出现、所选图标和尖头位置，再检查靠近视口边缘和玩家重叠时的菜单。
