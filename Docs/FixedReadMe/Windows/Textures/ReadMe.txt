MCBEEditor Textures 文件夹说明

此目录用于覆盖地图中方块的默认显示颜色。

1. PNG 覆盖
文件名必须使用：命名空间_方块名.png。
程序只把文件名中的第一个下划线转换为冒号。
例如：
minecraft_bedrock.png -> minecraft:bedrock
minecraft_polished_blackstone.png -> minecraft:polished_blackstone
文件名中直接使用冒号的格式（如 minecraft:bedrock.png）不受支持。
PNG 的可见像素会被计算为一个代表颜色，用于覆盖该方块显示颜色。

2. Colors.txt 覆盖
Colors.txt 每行格式必须为：
minecraft:bedrock #808080
即：完整冒号格式方块 ID + 空格 + #RRGGBB 六位十六进制颜色。
一行只能包含一个条目。空行会忽略，格式错误的行会忽略。
同一方块出现多次时，以最后一个有效条目为准。

3. 优先级
Colors.txt 有效条目 > 对应 PNG > MCBEEditor 内置方块颜色。
如果 Colors.txt 中存在某方块的有效条目，则忽略该方块对应 PNG 的颜色。

修改 PNG 或 Colors.txt 后，在 MCBEEditor 中点击“重新加载纹理”或重新渲染地图即可刷新。

注意：本 ReadMe.txt 是 MCBEEditor 内置的固定说明，并会在程序启动时恢复为默认内容。