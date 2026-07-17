# Blocktopograph iOS 13 v1.1.12 修改说明

## 修复 GitHub Actions 工程生成前崩溃

本次日志中的失败发生在 `bash Scripts/bootstrap.sh` 阶段，尚未执行 XcodeGen 或 Swift 编译。异常为：

```text
NSFileHandleOperationException
-[_NSStdIOFileHandle writeData:]: Broken pipe
Process completed with exit code 134
```

原因是脚本原来使用：

```bash
xcodebuild -version | awk '/^Xcode / {print $2; exit}'
```

`awk` 读取到第一行后立即退出并关闭管道，但 `xcodebuild -version` 仍要输出第二行 `Build version ...`。在当前 macOS 14 ARM64 runner 和 Xcode 15.4 组合下，Xcode 对已关闭的 stdout 写入时会抛出 Objective-C 异常，而不是普通地处理 SIGPIPE。

现已改为：

1. 完整执行并捕获 `xcodebuild -version` 的全部输出；
2. 在命令结束后，从捕获的文本中解析 `Xcode 15.4`；
3. 无法执行或无法解析版本时输出明确错误；
4. GitHub Actions 和 `Scripts/bootstrap.sh` 使用相同的安全逻辑。

因此不会再因为版本检测本身中断工程生成。

## 版本

- Marketing Version：1.1.12
- Build Number：122
- 最低系统：iOS 13.0
- 构建工具链：Xcode 15.4
