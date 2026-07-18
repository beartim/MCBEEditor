# 应用 Blocktopograph iOS 13 v1.1.18 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版新增：

- `effect give 目标 状态效果ID或ALL 持续时间 效果等级`；
- `effect clear 目标 状态效果ID或ALL`；
- 状态效果字符串 ID 到当前数据值数字 ID 的严格校验；
- 完整 `ActiveEffects` Compound List 写入，不创建 `FactorCalculationData`；
- 清除最后一个效果时自动删除 `ActiveEffects` 根标签；
- 玩家和实体在同一 LevelDB WriteBatch 中原子更新。

重新生成 Xcode 工程后，版本号为 1.1.18，构建号为 128。
