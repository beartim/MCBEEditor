# 应用 Blocktopograph iOS 13 v1.1.11 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修复与变更：

- 地图栏目默认以本地玩家所在维度和实际坐标为中心；
- 命令输入行并入终端大屏，保留连续／末尾空格并显示持续闪烁光标；
- `clone` 在不同 Y 偏移、同维度重叠及跨维度情况下均从冻结的源 SubChunk 快照读取；
- 新增 `@s`、`@a`、`@e`、UniqueID 和实体 identifier 目标选择器；
- `clear` 可清除玩家及实体物品并保留村民交易；`clearspawnpoint` 必须指定目标；
- 新增 `give`、`kill`、`kick` 命令，并严格检查全部参数数量；
- `CHANGES_v1.1.11.md`：完整命令格式、选择器语义和修改说明。

重新生成 Xcode 工程后，版本号为 1.1.11，构建号为 121。
