# MCBE-SNBT TXT 支持（1.0.0）

本次在已完成 entity 和 summon 增强的源码上继续修改，版本仍为 1.0.0。

## 使用方式

MCBE-SNBT 是带明确 NBT 类型的 UTF-8 文本，文件扩展名为 `.txt`。以下内容可直接保存为 TXT 并导入：

```text
'Int'"Age"="0"
```

实体示例：

```text
'String'"identifier"="minecraft:cow",'List''Float'"Pos"="0.0,64.0,0.0",'Long'"UniqueID"="12345678"
```

上述简写读取为一个匿名 Compound 根。导出使用外层根标签序列，保存根类型、根名称及连续多根顺序：

```text
[
'Compound'""="{'Int'"Age"="0"}"
]
```

完整文法、嵌套列表、字符串转义和数值规则见 [Docs/MCBE-SNBT.md](Docs/MCBE-SNBT.md)。本格式与 Java SNBT 的写法不同。

## 已接入的入口

| 入口 | iOS / Windows 行为 |
| --- | --- |
| 独立 NBT/mcstructure 工具 | 打开、编辑、原格式另存、转换 MCBE-SNBT TXT |
| NBT 编辑器 | 导入 TXT；导出根、选中及批量标签为 TXT |
| 世界、玩家、元数据、村庄 | 复用相同编解码器；支持连续多根 TXT |
| 实体与方块实体 | 导出全部标签；实体文件导入支持 TXT |
| 结构文件与 structure 命令 | TXT 导入导出；保留原有单根结构和 Java→Bedrock 转换规则 |
| 两端 CLI 转换工具 | `--to txt`，也接受 `--to mcbe-snbt` |

CLI 示例：

```text
mcbe-cli --convert input.nbt --to txt --output output.txt
mcbe-cli --convert input.txt --to little-endian --output output.nbt
structure export txt my:house --file house.txt
structure import my:house --file house.txt
```

GUI 的 structure 命令通过文件窗口选取路径。CLI 继续使用显式 `--file`；已有文件的覆盖规则不变。

## 数据保真与兼容

- 保留 NBT 类型、64 位整数精度、重复 Compound 标签和空列表的元素类型。
- 保留浮点负零、NaN 位模式、原始二进制 String 模型与根标签顺序。
- 严格检查 UTF-8、数值范围、转义、标签类型和嵌套深度；解析错误时不会先发布转换输出。
- 原有 JSON、三种二进制编码、压缩输入以及 entity/getblock/summon 命令语法继续使用原有规则。

构建与测试证据见 `CLI/Docs/Validation/mcbe-snbt/`；目标平台与真机验证范围在该目录说明中列出。
