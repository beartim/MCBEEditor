# give 命令修复

- 修复便携核心测试无法识别换行函数签名导致的 `command execution behavior is missing: give(target:`。
- `give` 对非玩家实体始终要求已有可写入的 `Mainhand` 标签。
- 缺少 `Mainhand` 的实体直接跳过，即使存在 `ChestItems` 也不会写入。
- 删除所有主动创建 `Mainhand` 的代码路径。
- `ChestItems` 超范围写入只会同步到已有 `Mainhand`。
