# 应用 Blocktopograph iOS 13 v1.1.10 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修复与变更：

- 命令完成后仅在主线程关闭数据库缓存并通知界面，修复执行后闪退；
- clone 使用重叠安全复制，不再产生方块连锁扩散；
- clone/fill 的维度改为命令参数，名称为 overworld、nether、the_end；
- clone 支持源维度与目标维度不同；
- 命令栏移除维度选择框，增加实时输入显示和持续闪烁光标；
- `CHANGES_v1.1.10.md`：完整格式、示例与兼容性说明。

重新生成 Xcode 工程后，版本号为 1.1.10，构建号为 120。
