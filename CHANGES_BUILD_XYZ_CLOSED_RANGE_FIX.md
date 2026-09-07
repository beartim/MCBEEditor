# X/Z 剖面导出 ClosedRange 编译修复

- 修复 `WorldMapViewController.swift` 中两个跨行 `...` 范围表达式。
- Swift 会把行尾的 `...` 解析为 `PartialRangeFrom<Int64>`，无法赋给 `ClosedRange<Int64>`。
- 改为 `lower...(upper)`，确保上下界组成完整闭区间。
- 同时修复当前剖面范围和“全部已加载区域”剖面范围，避免修完第一处后第二处继续触发同类 Xcode 编译错误。
- 在 `test_nbt_tree_cross_section.sh` 增加回归检查，禁止该问题再次出现。
