# 第5轮：dimension purge 源码

命令格式为dimension purge 名称或ID。Swift/C#核心共用上一轮内容清理计划，追加维度根、原版canonical根、名称-ID登记删除，以及WorldClocks目标时钟删除。iOS/Windows GUI和Apple/Windows CLI均已接入；命令帮助、共享解析向量和写权限标记同步更新。Windows保留修改工作副本、导出.mcworld保存的流程。

玩家保留：扫描本机、LocalPlayer、player_、legacy_console_player_玩家记录，迁移指向目标维度的当前位置和重生维度。优先选择剩余主世界，否则按ID顺序取第一个剩余维度。迁移当前位置为(0.5,65.62,0.5)，重生点为(0,64,0)，重生强制标志改为0；不改变库存、生命和其它NBT字段。匹配整数/精确名称引用、顶层Spawn字段及respawn/spawn/spawnpoint/playerspawn/bedspawn/respawnpoint中的已识别Compound。迁移仅设置坐标，不检查地形，不宣称坐标在所有存档中安全。

若最后一个维度仍被玩家引用，删除前报错且不提交；没有目标玩家引用时可删除最后一个维度。格式错误、未知玩家维度、冲突引用或无法解析NBT也在提交前报错。内容删除、登记重写、玩家迁移和时钟更新使用同一次同步WriteBatch。purge后的同名同ID可重新add。

已加入Swift/C#核心回归用例：删除根与登记、query不再列出、单批提交、当前位置/重生点迁移和其它玩家属性保留、目标时钟过滤、无剩余维度时拒绝且字节不变、无玩家引用时允许删除最后一维度、重建同名ID。CLI解析向量新增4例，共216例。

实际通过：python CLI/Tests/source_audit.py（28命令/66个Swift输入/216解析向量）、python CLI/Tests/build_audit.py、python CLI/Tests/apple_build_lifecycle.py（构建脚本工具替身）、git diff --check。交付ZIP完整性与原示例mcworld字节保持一致已检查。

实际调用bash Scripts/test_dimension_query.sh、dotnet run --project Windows/MCBEEditor.Core.SelfTest -- --dimension均退出127：环境缺少swiftc/dotnet。原生RED/GREEN、编译、运行和真实存档重新打开测试未完成；写了用例不等同于验证行为通过。本轮未修改用户存档。

后续仍需：在对应工具链运行新增原生测试与真实数据库集成测试；完善特殊/历史玩家位置形态的回归，整体最终验收时再判断完整兼容性。第6–7轮解除旧命令固定维度限制，完善命令批处理的维度预检状态。
