# 应用 Blocktopograph iOS 13 v1.1.12 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修复：

- 修复 Xcode 15.4 在 `xcodebuild -version` 输出管道被提前关闭时抛出 `NSFileHandleOperationException: Broken pipe`、构建流程以退出码 134 中止的问题；
- `Scripts/bootstrap.sh` 先完整捕获版本输出，再解析 Xcode 版本；
- GitHub Actions 的 Xcode 15.4 选择与校验步骤同步改为安全解析；
- 保留 v1.1.11 的地图中心、命令选择器、`clear/give/kill/kick` 和 clone 修复。

重新生成 Xcode 工程后，版本号为 1.1.12，构建号为 122。
