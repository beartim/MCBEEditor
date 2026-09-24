# 第 9 轮：structure 命令与文件冲突

日期：2026-09-23。输入 `MCBEEditor-CLI-v1.0.0-audit-part08.zip`，SHA-256：`bc38e91d6b5255076bad5a3be30a5a8906708f43ece04251142747f8c7a502d4`。

**状态：本轮源码修订、回归用例与审计记录已交付；静态检查通过，原生编译、行为回归和游戏读档待补。** 保留前 8 轮成果，软件版本 1.0.0、iOS 13.0 最低版本不变；按每轮 10 分钟上限收口。

## 本轮修订

1. Swift structure load 改为逐条处理目标 BlockEntity：只删除确实写入 layer0 或 layer1 的坐标记录，保留其余重复坐标记录、无坐标记录及顺序。两个索引都为 -1 的位置不删除实体。原按坐标字典重建整区块的路径已移除。
2. Swift 结构实体坐标改用可容纳数值的 Int/Long，避免 Byte/Short 限幅；缺少 x/y/z 时补齐，已有 DimensionId / dimension 字段更新为目标维度。双端结构加载均拒绝当前数据库读取器不能回读的多根 VarInt 拼接，在最终批次前报错。
3. 双端 structure save 遇到选区内重复坐标实体时拒绝；加载结构遇到重复 block_position_data 位置时也拒绝，避免覆盖或生成有歧义的位置记录。Swift 不再保留无调用者的旧实体编码和限幅辅助函数。
4. 双端增加结构文件预检，接入非交互整批命令、交互单命令与 Command.txt 整批入口。导出禁止写入源世界、会话缓存、世界输出路径或其内部，禁止覆盖命令文件与本批次结构输入；检查扩展名、目录目标、已有文件覆盖规则、重复输出及输出文件/父目录冲突。非交互预检在创建工作副本之前执行；交互已有工作副本时在本次命令写入前执行。
5. 双端明确拒绝 `--file --overwrite` 这类缺少路径的参数组合，避免将选项误当文件名。

路径检查复用既有规范化规则：Windows 拒绝符号链接/目录联接，Swift 解析符号链接。执行阶段原有同目录临时文件及原子发布检查仍保留。导出不是世界数据修改，但属于外部文件写入，现由独立路径预检保护。

## 源码核对与回归

| 范围 | 本轮结果 | 验证状态 |
| --- | --- | --- |
| query / 名称 / save / delete | 核对逐行输出、名称规范化、同名 save 的既有覆盖语义、缺失记录与 delete all 路径 | 源码核对，运行待补 |
| load 实体记录 | 外部重复/无坐标记录保留、旧目标实体替换、跨维度字段与 Byte 坐标迁移 | 双端新增核心用例，待运行 |
| 重复源实体 | save 拒绝，Swift 整库不变、Windows 无新批次 | 双端新增断言，待运行 |
| 文件冲突 | 源世界/缓存/已有目标/目录目标/父路径文件/重复输出/结构输入/世界输出/脚本自身 | 新增 10 组真实 CLI 进程断言，待运行 |
| 失败副作用 | 前置 time set 不执行、不创建工作副本，来源和已有文件保持字节不变 | 新增断言，待运行 |
| nbt 与 Java 转换 | 保留 nbt 默认大端及 Java→Bedrock 路由、单根限制和兼容降级提示 | 既有转换用例保留，原生待运行 |
| 交互省略名称及取消 | 文件预检先于补名，取消分支仍在执行前 continue | 源码核对，终端运行待补 |

新增 `Windows/MCBEEditor.Core.SelfTest/StructureAuditTests.cs` 并接入完整自测和 `--cli-regression`；Swift 在现有命令核心测试加入 `verifyStructureAudit()`。新增 `CLI/Tests/structure_file_smoke.py`，接入两端构建测试开关。该进程测试使用最小 level.dat 检查预检拒绝，不依赖真实 LevelDB，不能代替成功导入/导出、保存重开测试。

## 实际执行的验证

- 第 8 轮输入哈希、ZIP 完整性和安全解压检查通过。
- `CLI/Tests/source_audit.py` 通过：26 命令、142 解析 fixture、62 Swift 编译输入及接线。
- `CLI/Tests/build_audit.py`、`CLI/Tests/windows_gui_overlap_click_audit.py` 通过。
- `bash -n Scripts/run_core_tests.sh`、`bash -n CLI/Scripts/build-apple.sh` 通过。
- 新 Python 脚本语法编译及 --help 通过；尚未调用真实 CLI。
- 环境仍无 swiftc/dotnet，新增 Swift/C# 用例、Objective-C++ 和原生集成均未编译或运行。PowerShell 构建和平台文件系统行为未验收。
- 完整源码包与第 8 轮逐文件比较，保留旧文件，ZIP 完整性通过。

目标平台执行：`python3 CLI/Tests/structure_file_smoke.py -- /path/to/mcbe-cli`，以及已有 `bash Scripts/run_core_tests.sh`、Windows 核心 `--cli-regression`、两端构建测试入口。

## 后续事项

1. structure save/load 原有实现只处理 layer0/layer1；save 写空 entities，load 不实例化实体。不能把本轮 BlockEntity 修订理解为普通实体复制已实现，相关功能范围需在补充轮明确。
2. 全 -1 空结构、长度不足/过长索引的填充或截断、非法位置元数据被忽略等既有宽松处理仍需专项复核；Swift 全跳过结构可能仍生成元数据，与 Windows 的无变化处理需统一。
3. 文件预检保护当前可见路径和本批次请求，不提供整个世界与所有外部文件的统一事务；执行中外部修改、平台路径别名/竞态及后续失败时已导出的文件需要目标平台测试。先导出后导入同一路径的批处理现在拒绝，需分两次执行。
4. 前 2～8 轮待补项继续保留，包括第 8 轮输入编码歧义与压缩边界。新增用例未运行，不能宣称编译、保存重开或游戏兼容已通过。
5. 下一轮为第 10 轮 GUI 地图、选择与导出；未闭环的结构/转换专项需在平台验收前安排补充轮，每轮仍不超过 10 分钟。
