# MCBE-SNBT (.txt)

MCBE-SNBT 是 MCBEEditor 使用的带类型 NBT 文本格式，例如 `'Int'"Age"="0"`。文件使用严格 UTF-8（读取时允许开头 UTF-8 BOM），扩展名为 `.txt`。版本号仍为 1.0.0。

## 文档与根标签

- 简写输入：逗号分隔的命名标签，或 `{命名标签}`，作为一个名称为空的 Compound 根。例如 `'Int'"Age"="0",'String'"identifier"="minecraft:pig"`。
- 完整文件/规范导出：外层 `[ ... ]` 包含一个或多个命名根标签，根之间用逗号分隔；允许换行缩进。例如：

```text
[
'Compound'""="{'Int'"Age"="0",'String'"identifier"="minecraft:pig"}",
'Long'"named-root"="9007199254740993"
]
```

外层中括号是根标签序列，不是 NBT List；每个根可以有不同类型。该形式保留根名称、根类型及连续多根顺序。空文件、空根序列 `[]`、残缺括号/引号、末尾逗号或未消费的尾部内容均报错。`{}` 表示一个空的 Compound 根。End 仅可作为空 List 的元素类型，不能独立充当根或命名标签。

## 标签与值

基本写法为 `'类型'"名称"="值"`，允许类型、名称、等号之间有排版空白。类型名称采用现有名称（大小写敏感）：Byte、Short、Int、Long、Float、Double、ByteArray、String、List、Compound、IntArray、LongArray。名称可以为空，Compound 内可以有同名标签，全部保持原顺序，不去重。

- 整数按原类型严格检查范围；Byte 和 ByteArray 使用 -128 至 127 的有符号文本。Long 与 LongArray 不经过 Double。
- ByteArray、IntArray、LongArray 的值使用 `[1,2,3]`，空数组为 `[]`。
- Compound 的值使用 `{标签,标签}`，其中嵌套标签的结构引号不额外转义，沿用现有命令语法。
- Float/Double 的有限值使用足够往返的十进制精度，保留负零。允许读取 `NaN`、`Infinity`、`-Infinity`。为保留特殊浮点值位模式，另支持 `bits:XXXXXXXX`（Float，8 个十六进制字符）与 `bits:XXXXXXXXXXXXXXXX`（Double，16 个）；NaN 规范导出使用此形式。拒绝溢出为无穷的普通数值文字。
- String 及标签名称支持 `\\`、`\"`、`\'`、`\n`、`\r`、`\t`、`\b`、`\f`、`\uXXXX`（包括正确配对的 UTF-16 代理项），以及旧命令文本中的 `\,`、`\[`、`\]`、`\{`、`\}`。未知/残缺转义及非法代理项报错。普通 Unicode 可以直接写入。规范输出转义控制字符，不把实体二进制 String 转为显示摘要；使用模型保存的原始字符串表示，以便二进制写回保留原字节。

## List

List 写作 `'List''元素类型'"名称"="元素,元素"`；空值表示空 List，保留声明的元素类型。数字元素直接列出；Compound 元素使用 `{标签}`；数组元素使用 `[数字]`。

为消除空字符串、嵌套 List 元素类型和分隔符歧义，每个元素也可写成带类型的匿名值：`['类型'="值"]`。匿名值的类型必须与外层声明一致。规范导出时 String 元素及 List 元素使用这种形式：

```text
'List''String'"names"="['String'=""],['String'=" a,b "]"
'List''List'"nested"="['List''Int'="1,2"],['List''String'="['String'="x"]"]"
'List''End'"empty"=""
```

同时接受现有命令的紧凑写法，例如 `'List''Float'"Pos"="0.0,64.0,0.0"`、`'List''String'"names"="first,second"`、`'List''List''Int'"nested"="[1],[2]"`。还接受当前 entity/getblock 为不同子 List 类型生成的写法：`'List''List'"mixed"="['List''Int'=[1]],['List''String'=[two]]"`。紧凑字符串 List 的空值表示空 List；如需一个空字符串，请使用带类型的匿名值，逗号之间不能留空元素。紧凑元素中经转义得到的首尾空格、换行或制表符属于真实字符串内容，不会被裁剪。

List 不允许混合直接元素类型；List<List> 的各个子 List 可以声明不同类型。End List 必须为空。解析和导出均限制嵌套深度为 256，根数量限制与已有 NBT 文件工具一致（2,000,000）。

## 文件工具与入口

所有提供 NBT/JSON 导入导出的入口都增加 MCBE-SNBT (.txt)：独立 NBT/mcstructure 工具、根/选中/批量标签、世界/玩家/实体/方块实体/结构/村庄等相关入口、连续 NBT 导出，以及结构文件命令。

CLI 转换器增加 `--to txt`，同时接受 `--to mcbe-snbt` 别名，目标扩展名必须为 `.txt`。`structure export txt 名称`（也接受 `mcbe-snbt` 别名，格式名大小写不敏感）与结构文件导入 `.txt` 均使用同一 codec。结构转换仍沿用原有单根与 Java→Bedrock 规则。保留原有覆盖保护、源文件/世界保护和预检行为。

命令中的旧 NBT 输入格式保持兼容；本次文件格式的完整根包装不作为 summon 的额外命令参数。
