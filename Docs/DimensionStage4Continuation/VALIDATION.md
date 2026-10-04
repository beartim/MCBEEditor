# 第4轮续作检查点

本次按10分钟轮次继续empty，未进入purge。

Swift/C#同步补充：旧版mVillages单根、已识别列表及具有明确维度的Compound映射；清理混合维度映射时保留其它维度记录。移除部分连续NBT记录时直接保留其它根的原始编码。递归维度归属出现冲突时报错，避免任取第一个维度。

修复全局schedulerWT、dimension0、portals键被长度型区块清理误删的风险。当前只接受这些特殊全局项为空；非空或解析失败在单次数据库WriteBatch之前报错，数据库不变。这是未完成的数据格式适配，不能宣称empty已经覆盖所有存档形态。

新增Swift空维度测试入口，C#追加旧村庄、其它维度保留、错误无部分写入测试；Windows CLI追加empty解析和写权限测试。这些为待执行原生测试，不等同于行为已验证。

已实际运行并通过：python CLI/Tests/source_audit.py（28命令、66个Swift输入、212解析向量）、python CLI/Tests/build_audit.py、python CLI/Tests/apple_build_lifecycle.py（使用工具替身验证实际构建脚本生命周期）、git diff --check。

实际尝试bash Scripts/test_dimension_query.sh和dotnet run --project Windows/MCBEEditor.Core.SelfTest -- --dimension均退出127，原因是swiftc/dotnet缺失。没有声明编译、原生测试、真实存档修改或重新打开验证成功。原示例存档仅做字节完整性检查，不修改。

下一轮继续第4轮：根据可靠样本或原生实现确定非空portals、dimension0、schedulerWT的格式和维度归属，补充清理与异常回归；执行原生编译和复制存档验证需要对应工具链。然后实现purge，再解除全部旧命令维度限制。
