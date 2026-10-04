# 第 6 轮：GUI 任意维度命令（源码阶段成品）

包含前五轮全部代码。Apple 和 Windows GUI 单条命令按当前存档解析登记名称（含 namespace / 无 namespace）和 Int32 ID。解析回调属于当前世界，不使用全局映射。8 个 Windows 解析器保持可选回调及旧调用兼容性。Swift 的各命令共用同一回调。

移除常加载区块的原版维度校验；spread 纳入所有有地形的维度；GUI 无参数 chunk query 列出存档中的全部维度。同步两端帮助及命令清单。

已增加 Windows 解析回调测试并接入 --dimension；Swift 回调用例源码已提供，待最终原生验证阶段接入完整解析器测试构建（独立维度存储测试脚本保持原来的依赖）。

本轮检查：source_audit、build_audit、apple_build_lifecycle、git diff --check 通过。生命周期检查使用工具替身，不代表原生运行。Swift / .NET 命令均因未安装编译器而退出 127，原生编译和运行未验证。

下一轮：CLI 绑定当前存档映射；Command.txt 批处理预检维护 add/purge 后的名称映射。目前 GUI 批处理能识别原先登记的名称，同一批中先 add 再按新名称操作尚待同步。

继续保持版本 1.0.0、iOS 13、Windows 工作副本和导出 mcworld 行为。示例存档未修改。
