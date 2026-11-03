# 命令语法与省略参数统一设计

目的：检查全部 28 条命令，让 Swift/C#、GUI/CLI 对同一写法给出相同结果，并兼容现有完整命令。

采用兼容扩展：只省略语义明确的参数，不重排旧语法；不引入依赖当前选中对象的隐式目标、维度或坐标。与仅改帮助相比，解析行为也得到统一；全面重写为新参数顺序会破坏现有脚本，故不采用。

统一约定：方括号表示可省略，嵌套方括号表示从右向左省略；坐标必须成组；0/1 开关保持严格；命令/子命令及 Auto、NULL、default、preserve、empty 不区分大小写；ID 和 NBT 内容保留原样。ALL 保持大写，避免把已有名称 all 解释为删除全部。

默认值（实现选择）：

| 命令 | 新省略规则 |
|---|---|
| dimension、chunk、structure | 裸命令等同 query；其余参数不借此省略 |
| time | 裸命令、time query 等同 time query daytime |
| weather | 裸命令等同 query；clear 自动变化默认 1；rain/thunder 依次默认 6000 游戏刻、1.0、1 |
| tickingarea | 裸命令、list、query 等同 list ALL；query 是 list 的别名；add 的 preload 默认 0，名称必填 |
| give | 槽位默认 Auto；物品之后数量默认 1、NBT 默认 NULL；槽位若出现仍在物品之前，靠 Auto/整数与完整物品 ID 区分 |
| kill | 目标或完整范围之后的创造模式开关默认 0；非创造玩家仍清零，非玩家仍删除 |
| effect give | 效果之后默认 600 游戏刻、原始等级 0；保留负持续时间与 Byte 原始等级；字符串 ID 可带 minecraft: |
| effect clear | 效果默认 ALL；目标必填 |
| summon | 坐标之后 NBT 默认 default；UniqueID 默认 Auto；指定 UniqueID 时仍须提供 NBT/default 占位 |
| fill、setblock | 每层 states 默认 NULL；最后方块实体默认 preserve；连续方块 ID 表示多层。方块后第一个 NBT 属于 states，要写方块实体模板须先给 states/NULL 占位 |
| storage set | states 默认 NULL；层号必填 |

其余 help、info、clear、clearspawnpoint、clone、entity、experience、fillbiome、getblock、kick、setworldspawn、spawnpoint、spread、teleport、storage 其他操作及 structure import/export/save/load/delete 保持既有参数规则，在完整审计表中明确必填与省略条件。结构导出格式继续显式填写；非交互 CLI 的结构名称与 --file 继续必填。

所有新默认值在两端解析阶段转换为已有类型，执行器继续使用原有写入逻辑；不更改版本、存档格式、旧方块转换、上一轮 ID/颜色与 kill 范围行为。

验证：默认写法与显式写法的类型/值等价；非法中间省略、额外参数、坐标缺项仍拒绝；空 states 与方块实体模板分界；255 层限制；用户命名 all 与数字维度；共享语法用例、两端核心、CLI 预检和固定帮助实际文件读写。构建不等同真机验证，限制如实记录。
