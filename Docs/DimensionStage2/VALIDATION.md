# 第2轮：dimension query

本轮增加 iOS GUI、Windows GUI、Apple CLI 和 Windows CLI 的 dimension query；读取 DimensionNameIdTable.entries，保留登记但无区块的维度；合并 Overworld/Nether/TheEnd 根、已识别区块键与 digp。每行输出 名称=ID，区块=数量，按 ID 排序。区块数量为具有区块记录或 digp 的去重 X/Z 坐标数。

修复 Swift/C# 区块键解码：先通过完整长度区分短前缀和包含维度的长前缀，避免 ID 43、44、47、118 等低字节与记录类型碰撞。

命令示例：dimension query；help dimension。

此包目前只支持 query；add/empty/purge 和其它命令任意维度解析仍按后续轮次实施。

## 验证结果

- CLI/Tests/source_audit.py：通过；28 个命令、两端帮助、路由、64 个 Swift CLI 源文件及 202 个解析测试向量一致。
- CLI/Tests/build_audit.py：通过构建输入和原有测试接线审计。
- CLI/Tests/apple_build_lifecycle.py：通过。它验证实际构建脚本的发布与失败保留行为，使用工具替身，不等于本机 Swift 编译。
- git diff --check：通过。
- 原始示例存档内容按字节保留；只读样例 CRC32C/MANIFEST/NBT 分析仍通过。
- 新增 Swift 核心服务/键解码测试、C# 核心只读查询/键解码测试和 Windows CLI 解析测试。运行测试入口时 swiftc/dotnet 均不存在（退出127）；原生编译与执行测试尚未完成，不能宣称构建通过或完成原生 RED→GREEN。

## 待运行命令

```bash
bash Scripts/test_dimension_query.sh
bash Scripts/run_core_tests.sh
dotnet run --project Windows/MCBEEditor.Core.SelfTest -- --dimension
dotnet run --project CLI/Windows.Tests -- --dimension
```

## 当前边界

query 合并的实际数据来源是已识别区块记录与 digp；旧村庄、仅常加载区块或未识别标签等其它数据证据的扩展发现，留给清理阶段统一审计。维度表结构异常或 ID 有相冲突名称时查询明确报错，避免默默使用错误映射。empty/purge 尚未启用。
