# 应用 Blocktopograph iOS 13 v1.1.15 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版新增与修复：

- 旧版数字 ID SubChunk 遇到无数字 ID、非空 states 或非空气层 1 时，自动迁移为现代 `Version/Data3D/v9` 格式后再执行方块 NBT、`fill` 或 `clone`；
- 命令 NBT 参数支持全部 NBT 类型、数组、List、Compound、空容器和任意层级嵌套；
- `give` 增加第四个物品标签参数，支持 `NULL` 或完整嵌套 NBT；
- 修复中间 NBT 参数与后续命令参数的边界解析。

重新生成 Xcode 工程后，版本号为 1.1.15，构建号为 125。
