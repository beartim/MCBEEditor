# CHANGES_IOS_PHOTO_TAB_KEYBOARD_FIX

本次修改包含三部分。

## 1. 地图图片保存到相册

- 地图图片生成后不再只把 PNG 文件 URL 交给系统分享面板。
- 新增明确的导出目的地菜单：
  - `保存到相册`
  - `分享／存储…`
  - `取消`
- “保存到相册”使用 `Photos` 框架直接写入照片库。
- iOS 14 及更新系统使用 `.addOnly` 权限申请；iOS 13 使用旧权限接口。
- `Info.plist` 新增：
  - `NSPhotoLibraryAddUsageDescription`
  - `NSPhotoLibraryUsageDescription`
- “分享／存储…”同时向 `UIActivityViewController` 提供 `UIImage` 和命名 PNG URL，既保留文件分享，也让新系统能够识别图片类活动。
- 这样可以避免 iOS 14 TrollStore 环境在缺少照片写入用途声明时异常退出，同时保证新系统即使分享面板不提供“保存图像”，应用内仍始终有明确的“保存到相册”入口。

## 2. 实体/区块底部 Tab 标题

- 进入世界后底部 TabBar 固定显示：
  - `实体`
  - `区块`
- 不再显示 `实体（数量）`、`区块（数量）`。
- 页面顶部导航标题继续保留计数：
  - `实体（100）`
  - `方块实体（N）`
  - `区块（N）`

## 3. 命令页键盘按钮

- 在“清屏”左侧新增纯图标键盘按钮。
- 使用 SF Symbol `keyboard`，没有文字标题。
- 点击按钮：
  - 键盘未显示时呼出命令输入键盘；
  - 键盘已显示时收起键盘。
- 增加 VoiceOver accessibility label / hint。

## 回归检查

- 新增 `Scripts/test_photo_export_tabs_keyboard.sh`。
- 已通过：
  - 照片权限/保存链路静态回归；
  - 实体/区块底部固定标题回归；
  - 命令键盘图标按钮回归；
  - iPhone 布局/旧数字 ID 回归；
  - 0.10.0 zlib / 框选导出回归；
  - modern actor binary TAG_String 回归；
  - metadata CRUD/batch 回归；
  - `Sources` + `Tests` 共 109 个 Swift 文件 `swiftc -parse`。
