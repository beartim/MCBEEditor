# 第 8 轮：独立 NBT 转换审计

日期：2026-09-23。输入 `MCBEEditor-CLI-v1.0.0-audit-part07.zip`，SHA-256：`8239f68f70ee4ef5f725f61dbb5150cb82ee87538d8031e3d4713dfc9386a207`。

**状态：本轮源码修订、回归用例和转换矩阵已交付；静态检查通过，原生编译及行为测试未运行。** 保留前 7 轮成果，版本 1.0.0、iOS 13.0 最低版本不变。按 10 分钟上限收口，不把工具链缺失视为测试通过。

## 已修订源码

1. Swift typed JSON 的整数原先先转 Double，再转 Int64，导致超过 2^53 的精度损失；普通 JSON 推断还有把 Int64.max 舍入至 2^63 后直接转换的崩溃风险。现通过 NSNumber 的十进制文本获取精确 Int64，再选 Int/Long；用 CoreFoundation 区分布尔值，typed 整数不再把 true/false 当作 1/0。
2. Windows JSON 导出的 Long/LongArray 改为十进制字符串，与 Swift 保持一致，避免外部 JSON 实现通过 Double 中转损失低位。双端解码继续接受范围内的整数 token 和十进制字符串。NBT 标签类型仍由 type 字段保存。
3. 双端 JSON 导出遇到 Compound 内重名标签时抛出明确错误，避免对象键覆盖导致静默丢数据。二进制转换仍保留这些标签；当前 JSON 对象格式不声称支持重复名称。Swift 嵌套 List/Compound 导出路径同步传播错误。
4. 双端 typed Float 在 Double 转 Float 后再检查有限性，拒绝 1e39 等溢出；Swift typed Float/Double 也拒绝 NaN/Infinity 文本和布尔值，与 Windows 的有限数值契约对齐。
5. Swift 对普通 JSON 空数组 [] 原先误判为零个 NBT 根。现与 Windows 一致，得到一个空 End List；显式 documents:[] 仍拒绝。
6. Apple GZip/Zlib 解压增加与 Windows 相同的 512 MiB 输出上限，在追加缓冲区前检查。ZIP 的精确声明长度校验规则保留。512 MiB 边界和 Objective-C++ 编译仍待原生平台验证。

## 转换矩阵与测试入口

新增 `CLI/Tests/nbt_conversion_smoke.py`，由 Python 独立构造二进制输入，并调用真实 CLI；已接入 Windows `-Test` 与 Apple `--test`。没有 CLI 时不能把 Python 语法检查或样本生成当成产品测试。

| 场景 | 断言 | 本轮状态 |
| --- | --- | --- |
| Big Endian / Little Endian / Little VarInt × 原始/GZip/Zlib | 每组双根输入转 JSON，再转原编码并回读；类型和值一致 | 用例已编写，待原生执行 |
| 中文根/字符串、Byte/Short/Int/Long/Float/Double、三类数组 | 保留类型与值，含 Int64 两端及 2^53+1 | 用例已编写，待原生执行 |
| 空 Compound、空 List、嵌套 List | 结构和 List 元素类型保留 | 用例已编写，待原生执行 |
| 数字 token 的 Long JSON 输入 | 保留精确整数，输出仍能回读 | 用例已编写，待原生执行 |
| 同路径转换 | 未 overwrite 拒绝且字节不变；overwrite 后可回读 | 用例已编写，待原生执行 |
| 已有目标与目录目标 | 仅明确 overwrite 替换普通文件，目录拒绝 | 用例已编写，待原生执行 |
| 空文件、非法根、截断 NBT、损坏校验和/截断压缩流 | 失败不覆盖已有输出，不留下转换临时文件 | 用例已编写，待原生执行 |
| 重名 Compound、非法 JSON 标量/空 documents | 失败不覆盖已有目标 | 用例已编写，待原生执行 |
| 多根转 mcstructure | 拒绝并且不创建输出 | 用例已编写，待原生执行 |

Windows 新增 `NbtConversionAuditTests.cs`，接入完整核心自测和 `--cli-regression`；Swift 核心脚本增加大整数、空数组、非法标量和重名拒绝用例。产品 CLI 的解析和最终临时文件发布路径经源码核对，已有“先完成解码/编码，再写同目录临时文件并发布”的顺序，本轮未改这些入口。

## 本轮实际验证

- 第 7 轮输入哈希、ZIP 完整性与安全解压路径核验通过。
- `CLI/Tests/source_audit.py`：26 命令、142 解析 fixture、62 Swift 编译输入和接线检查通过。
- `CLI/Tests/build_audit.py`、`CLI/Tests/windows_gui_overlap_click_audit.py` 通过。
- `bash -n Scripts/run_core_tests.sh`、`bash -n CLI/Scripts/build-apple.sh` 通过。
- 新 Python 测试脚本编译和 --help 通过；独立样本的整数打包及 Python GZip/Zlib 包装回读通过。这些只验证测试工具，不证明产品转换成功。
- 再次确认 `swiftc` / `dotnet` 不存在；没有 Swift、C#、Objective-C++ 编译和原生行为通过记录，也没有发布二进制。

目标平台入口：

```text
python3 CLI/Tests/nbt_conversion_smoke.py -- /path/to/mcbe-cli
```

Windows 也可使用 `python CLI/Tests/nbt_conversion_smoke.py -- 路径/mcbe-cli.exe`。完整构建入口保持 `CLI/Scripts/build-windows.ps1 -Test` 和 `bash CLI/Scripts/build-apple.sh host CLI/build/apple-host --test`。

## 明确保留的补充项

1. **输入编码歧义仍未解决。** 比如匿名 Int 根 `03 00 00 01 00 00 00` 在大小端都能完整解析，但值分别为 16777216 和 1。现有 .nbt 优先 Big Endian，不可能只凭这些字节可靠推断作者意图。需要后续补充显式输入编码选项，并回归已有 CLI 参数；本轮矩阵使用含中文根名的可区分样本，不据此宣称任意 NBT 自动识别无歧义。
2. 压缩流尾部截断、尾随垃圾、多 GZip 成员的两端行为，以及解压输出上限边界，需要在原生平台追加专项验证；当前矩阵覆盖校验和损坏和压缩正文截断，没有全覆盖所有包装边界。
3. 未统一数据库专用 ConsecutiveNBTCodec 的单根 VarInt 回退与独立文件的多根读取规则。第 7 轮 Swift clone 的 VarInt 多根拒绝保留；独立文件已有逐根 VarInt 读取，二者不能混同。
4. JSON 对象本身重复键、过深嵌套及普通 JSON 超出 Int64 范围整数的策略仍需补充审计；不能把当前有限样本视为全格式验收。
5. 前 2～7 轮待验证项保留。下一轮为第 9 轮 structure 命令与文件冲突；上述第 8 轮补充项在平台验收前单独闭环，必要时增加补充轮，不自动勾选完成。
