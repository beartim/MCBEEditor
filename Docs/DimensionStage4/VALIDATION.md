# 第4轮检查点：dimension empty

三端新增 dimension empty 名称或ID。清理计划覆盖目标维度的全部长度合法区块记录（含未知标签）、digp及独占actor、明确Dimension的孤立actor、tickingarea、按维度分组的现代村庄；清空维度根data.LimboEntities，以及全局旧村庄/AutonomousEntities中的已识别列表。共享actor仍被其它维度引用时保留。保留玩家、其它维度数据、维度登记与维度根设置；若维度只有数据而未登记，创建dimension_ID名称来保留它。

先读取并完成清理计划及全部NBT编码，再一次sync WriteBatch提交；内容元数据冲突或解析失败时不提交。注册表已有目标时不重写其字节。Windows沿用修改工作副本和导出.mcworld保存流程。

本轮是检查点，尚未完成整轮验收。非列表形态的旧版mVillages、门户缓存及更多特殊全局数据仍须继续审计，不能宣称所有历史数据形态已完整清除；相关检查完成后再进入purge。

已检查：source_audit.py通过（28命令、66个Swift源文件、212解析向量）；build_audit.py通过；git diff --check通过；原测试存档保持原始字节。

新增C#核心回归测试覆盖未知区块标签、共享actor、维度登记保留、其它维度不变、常加载区块及村庄同组记录。测试入口已接入--dimension。当前dotnet实际调用退出127；Swift/.NET均缺失，原生编译及执行测试待完成，Swift专项清理测试亦须补齐。

下一轮继续第4轮：补齐特殊旧数据处理、Swift和C#错误无部分写入测试、测试存档复制品验证，然后再开始dimension purge。
