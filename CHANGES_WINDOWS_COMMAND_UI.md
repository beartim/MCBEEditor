# Windows 顶部布局与命令终端调整

本轮仅修改 Windows 版。

- 主窗口顶部与地图工具区改为更宽松、可换行的响应式布局。
- “重新读取源存档”真正重新复制/解压原始来源，替换当前 Cache 工作副本；不会重复触发 Command.txt。
- 命令页使用上方 RichTextBox 输出 + 下方 `>` TextBox 输入的 cmd 式结构。
- 输出文本可跨行选择、Ctrl+C、右键复制/全选；滚轮按小像素步长滚动。
- 输入支持 ↑/↓ 历史、←/→ 原生光标移动、标准选择/剪切/复制/粘贴。
- Command.txt 执行期间保留输出选择/复制能力，但禁止切换其它栏目或手动执行新命令。
- Windows help 逐命令与 iOS 当前 WorldCommandParser.usage 同步，并作为 Commands/ReadMe.txt 的同一帮助数据源。
