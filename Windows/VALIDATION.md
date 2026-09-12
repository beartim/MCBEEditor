# Windows 验证清单

1. 运行 `Windows\build.cmd`，确认原生桥、Core SelfTest、Desktop publish 与便携启动器均成功，并确认 `Windows\dist` 最终只有 `MCBEEditor.exe`。
2. 打开真实 Bedrock 世界，确认地图 Y/X/Z、缩放/移动续载和对象图层正常。
3. 在三个维度执行 `chunk query`，确认每行包含 `IsSlimeChunk=True/False` 与 `Ticking=True/False`；指定未生成区块查询也应显示这两个字段。
4. 测试 `chunk empty/regenerate`、方块/区域命令、实体写入、tickingarea 与 structure 操作，确认修改只发生在 EXE 同级 `Cache` 工作副本，源世界文件时间戳/内容保持不变。
5. 检查 EXE 同级自动建立 `Textures`、`Commands` 和固定 `ReadMe.txt`；验证 `Commands\Command.txt` 批处理，不应访问用户 Documents 下的 MCBEEditor 目录。
6. 从主页导出 `.mcworld` 并检查压缩包，确认编辑结果存在且不包含 MCBEEditor 私有设置/元数据；确认不能覆盖原始 `.mcworld`、不能导出到源世界文件夹内部或 `Cache`。
7. 关闭程序后确认同级 `Cache` 被自动清空；`Textures` 与 `Commands` 保留。重启/重新打开世界时地图显示状态不会跨会话持久化。
8. 用含 LegacyTerrain、旧式 Entity、现代 actor/digp 和不同 SubChunk 版本的世界验证 Minecraft 世界格式兼容读取。
