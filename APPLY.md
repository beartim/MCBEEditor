# 应用 Blocktopograph iOS 13 v1.1.14 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版新增与修复：

- 成功命令结果改为绿色，错误结果保持红色；
- 修复 `kill @e 1` 连续实体记录的部分删除与数据格式错误，改为原子批量删除；
- 未加载区块/SubChunk 按世界实际版本、地形元数据和调色板格式创建并执行写后读回校验；
- `give` 空槽和非玩家 `WasPickedUp` 规则修正；
- `summon` 支持 `default`；
- 实体通用 NBT 默认值和标签集合按 v1.1.14 要求更新。

重新生成 Xcode 工程后，版本号为 1.1.14，构建号为 124。
