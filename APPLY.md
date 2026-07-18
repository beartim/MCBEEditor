# 应用 Blocktopograph iOS 13 固定版 1.0.0 完整源码

本压缩包为完整工程源码。覆盖现有工程后执行：

```bash
chmod +x Scripts/*.sh
bash Scripts/bootstrap.sh
```

本版修改：

- `tickingarea add circle` 只需维度、一组区块坐标、名称和预加载布尔值；
- 新增 `teleport`，支持目标选择器/UniqueID、跨维度传送及 Y=`Auto`；
- 新增 `weather clear/rain/thunder`；
- 天气命令与信息页天气栏目统一读写 `rainLevel`、`rainTime`、`lightningLevel`、`lightningTime` 和 `doWeatherCycle`；
- 天气栏目新增“天气自动变化”开关；
- 软件版本固定为 1.0.0，构建号固定为 100。

重新生成 Xcode 工程后，版本号为 1.0.0，构建号为 100。
