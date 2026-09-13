# 区块显示、结构文件命令与 Windows 图标更新

基于上一版 `MCBEEditor-iOS-Windows-save-compatibility-audit` 修改，适用于 iOS 和 Windows。上一版未生成区块／子区块的保存兼容性修复保留。

## 本次修改

- 区块列表与 `chunk query` 读取实际 SubChunk 数据头的版本。例如 `SubChunk v8 · Y0-Y4`。同一区块存在多种版本时显示 `SubChunk v8/v9`；空数据头明确显示“未知版本”，不会冒充 v0。负高度显示如 `Y-4-Y4`。
- `weather query` 读取并打印 `rainLevel`、`rainTime`、`lightningLevel`、`lightningTime`、`doWeatherCycle`。时间单位为游戏刻，原始标签缺失时打印 `NULL`。查询不修改 level.dat 或数据库。
- `structure query` 每行输出一个已保存结构的名称、尺寸、原点、格式版本和数据大小（按实际存在的字段显示）。无法解析的结构也列出并标记。无结构时明确提示。
- 新增结构文件导入／导出命令，使用系统文件选择／保存窗口。同名导入确认替换；取消不修改存档。Command.txt 会等待文件窗口完成或取消，再继续下一条命令。
- 结构 NBT 列表及编辑器均可选择 mcstructure、NBT、JSON 导出格式；Windows 多选结构导出也可以统一选择格式。编辑器导出包含当前已应用到树中的未保存编辑。
- Windows 删除“重新读取源存档”按钮及其重新建立工作副本的实现，移除由此失去用途的调用参数；顶部“说明与许可证”移至右侧。
- Windows 更换透明 PNG 和 ICO。ICO 包含 16、20、24、32、40、48、64、96、128、256 像素尺寸，WPF 程序和单 EXE 启动器使用同一份图标资源。
- 共用结构文件交互代码，删除重复的导入／导出处理；同步更新两端 help 与 Commands/ReadMe。

## 命令示例

```text
weather query
structure query
structure import
structure import demo:house
structure export mcstructure
structure export nbt demo:house
structure export json demo:house
```

`import` 后的名称可以省略，选取文件后输入名称；`export` 的格式是必填参数，之后的名称可以省略，省略时选择已有结构。

| 导出参数 | 扩展名 | 编码和内容 |
| --- | --- | --- |
| `mcstructure` | `.mcstructure` | Bedrock 结构数据，Little Endian，小端 |
| `nbt` | `.nbt` | 标准 Big Endian，大端 NBT，保留结构标签 |
| `json` | `.json` | 带 NBT 类型信息的 JSON，可在两端重新导入 |

`.nbt` 指编码格式，不会把 Bedrock 结构标签自动变成 Java 版结构标签。导入 Java 结构时继续沿用原有转换器和转换损失提示。

## 结构 JSON 的附带修复

新增回归发现旧 iOS JSON 编码器省略嵌套 List 子元素的完整类型包装，结构的 `block_indices` 重新导入时会被误判为整数。

本版统一输出明确的子元素标签，并让两端读取器兼容旧 iOS 的嵌套 List 包装和显式标签数组。Windows 与 iOS 生成的结构 JSON 已互相读取、验证并转换为 Bedrock 结构。

## 验证

- Windows Core 全套 SelfTest 与新增命令／格式回归通过，包括查询无写入、混合 SubChunk 版本、三种结构格式导出与重新导入。
- Windows WPF Release 编译通过：0 警告、0 错误；XAML 事件处理函数审计通过。
- iOS 核心回归通过。主脚本前段与命令执行器及后续测试分段运行；新结构 JSON 兼容性另作最终回归。UI Swift 文件语法检查通过。
- 原有未生成子区块、旧数字格式、val/states 调色板、空 storage 与 255 storage 保存回归继续通过。
- 图标 ICO 的全部尺寸均有 alpha 通道，四角透明，WPF 构建包含新图标。

当前环境没有 Xcode、iOS/Windows 图形桌面或 Minecraft。本次没有执行完整 IPA 构建、系统文件窗口的实机交互或游戏内重载测试，也没有生成可运行的 Windows 发行 EXE。源码包中的 `Windows/build.cmd` 和 iOS 构建脚本仍用于各自平台的正式构建。

本次验证记录见 `Validation/command-format-update/`，上一版兼容性审计记录保留在原位置。
