# 第3轮：dimension add

新增三端 dimension add 名称 ID。支持 wzn:bear 1000 或无 namespace 的 bear 1003；原样保留自定义名称；ID 为有符号 Int32。已存在的名称或 ID 拒绝覆盖。

缺失原版维度可用 overworld 0、nether 1、the_end 2 重建，也支持对应 minecraft: 别名。原版名称与ID固定，自定义名称不能占用0/1/2。纯数字名称会与ID语法冲突，拒绝；空白、控制字符、超长NBT名称、保留数据库键或已有键冲突也拒绝。

自定义维度注册写入实际 DimensionNameIdTable.entries（名称→Int），同时创建同名小端 NBT：根 Compound/data Compound/LimboEntities List(Compound)。一次 sync WriteBatch 写入两条记录。原版维度使用 Overworld、Nether、TheEnd 根，不向自定义登记表增加原版名称。

现有登记表未知标签与根名称保留。参数/冲突检查与全部NBT编码在提交前完成，错误不会留下单独根或孤立登记。新维度尚无区块，query 仍可发现。Windows 沿用既有工作副本、写入锁准备和导出 .mcworld 保存流程；CLI add 需要写入/导出，query 保持只读。

## 本轮验证

- source_audit.py 通过：28命令、两端帮助、65个Apple CLI源文件、209个解析向量一致。
- build_audit.py、apple_build_lifecycle.py 通过；后者使用工具替身，不证明本机Swift构建。
- bash -n 两个相关Swift测试脚本、git diff --check 通过。
- 原附件和示例存档按字节保留；此轮没有写入用户原始世界。
- 增加 Swift/C# 无namespace名称、registry/root结构、重复ID/名称、保留键、失败无写入、原版恢复和Int32边界测试。
- 增加 Windows CLI native 测试：实际执行add，关闭写入句柄后重新以只读句柄打开，断言空维度仍存在。
- 测试源先于产品实现写入，但本环境 swiftc/dotnet 不存在（实际调用退出127），原生编译与行为测试尚未运行；不得宣称原生RED→GREEN或构建通过。

## 可执行验证命令

```bash
bash Scripts/test_dimension_query.sh
bash Scripts/run_core_tests.sh
dotnet run --project Windows/MCBEEditor.Core.SelfTest -- --dimension
dotnet run --project CLI/Windows.Tests -- --dimension
```

原生持久化测试位于 CLI/Windows.Tests/DimensionCommandTests.cs，接入CLI测试项目完整native测试流程；--dimension仅运行parser测试，需要现有native数据库fixture工具才能执行完整CLI集成套件。

## 后续工作

empty/purge 未启用。其它命令任意维度名称解析、同批add后使用新名称的预检仍按第6/7轮实现；当前add→query可以顺序执行。下一轮实现 dimension empty。
