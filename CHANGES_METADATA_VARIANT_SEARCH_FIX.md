# 末地元数据 `variant` 搜索修复

- 修复连续输入搜索词时旧前缀结果未清除的问题。
- `StandaloneNBTEditorViewController.rebuildRows()` 现在每次搜索文本变化都先清空 `rows`。
- 搜索结果使用本次查询生成的新数组整体替换，不再追加到上一轮结果。
- 在用户存档所示结构中搜索 `variant` 时，仅返回 `MarkVariant` 与 `Variant`，不再残留 `DragonFightVersion`、`version`、`Invulnerable`、`LimboVersion` 等早期 `v` 前缀命中项。
- 新增 `Scripts/test_metadata_variant_search.sh` 回归测试。
