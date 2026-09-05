# 1.26.33.10 现代实体读取兼容修复

## 问题结论

用户提供的 `极限模式-1.26.33.10.mcworld` 中实体漏读并不是 SubChunk v9 导致。

真实世界数据库检查结果：

- `SubChunkPrefix`：27,687 条，全部为 v9。
- 27,687 / 27,687 条 v9 SubChunk 均可由当前 `BedrockSubChunk.decode` 完整解码；0 条失败，0 条 Y 索引不一致。
- `actorprefix`：343 条。
- `digp` 最终引用 322 个有效 actor；322 个引用全部能找到对应的 `actorprefix`。
- 数据库中实际存在 16 匹 `minecraft:zombie_horse`，16 匹全部被 `digp` 有效引用，并非孤立/残留 actor。
- 16 匹僵尸马确实按 4 匹一组连接到 4 个栓绳结，与游戏内观察一致。

修复前使用 MCBEEditor 自身的 Swift NBT 解码器读取同一批 343 条 actor：

- 154 条 actor 解码后丢失 `identifier`，界面表现为大量“未知实体”；
- 僵尸马仅识别 10 / 16。

修复后：

- 343 / 343 条 actor 均可正常得到 `identifier`；
- 未知实体：0；
- 僵尸马：16 / 16；
- 按真实 `digp` 扫描得到 322 个有效 actor，其中主世界 225 个。

## 根因

1.26.33.10 的部分现代实体在：

`internalComponents -> EntityStorageKeyComponent -> StorageKey`

中使用 NBT `TAG_String` 类型保存 8 字节二进制 actor storage key，而该 8 字节内容不一定是合法 UTF-8。

例如一匹此前漏读的僵尸马中：

`00 00 00 10 00 00 02 91`

末字节 `0x91` 使整个 TAG_String 无法按严格 UTF-8 解码。

旧代码 `BedrockNBTCodec.readString()` 对所有 TAG_String 强制要求合法 UTF-8，因此正常 little-endian NBT 解码失败。随后 `ConsecutiveNBTCodec` 对任意失败都直接尝试 little-endian VarInt NBT；普通 little-endian Compound 的开头 `0A 00 00` 又可能被错误解释为一个空 VarInt Compound。由于旧 fallback 没有检查尾随数据，它会把真正的 actor 静默变成一个空 Compound，从而产生“未知实体”，而不是显式报错。

## 修改内容

### `Sources/NBT/NBTTypes.swift`

新增 `NBTRawStringCodec`：

- 合法 UTF-8 TAG_String 仍使用普通 Swift String；
- 非法 UTF-8 TAG_String 使用内部私有标记 + 十六进制负载无损保存；
- 写回时恢复成原始字节；
- NBT 摘要中显示为 `RawString[n] ...`，避免把二进制内容误显示为乱码。

没有增加新的 NBT tag 类型；持久化时仍严格写成 TAG_String。

### `Sources/NBT/BedrockNBTCodec.swift`

- `readString()` 不再因无效 UTF-8 使整个 NBT 失败；
- `writeString()` 能识别内部 raw-string 表示并逐字节恢复原始 payload。

### `Sources/NBT/ConsecutiveNBTCodec.swift`

收紧 VarInt NBT fallback：

- little-endian 失败后仍允许尝试 VarInt，以保留原有兼容能力；
- 但 VarInt 结果必须重新编码后与输入 payload 完整匹配（仅容许尾部全零填充）才可接受；
- 防止普通 little-endian actor 被错误识别为空 VarInt Compound。

### `Sources/UI/NBTNode.swift`

二进制 TAG_String 在通用 scalar 编辑器中设为只读，避免用户把内部 StorageKey 当普通文字修改而损坏实体引用。

### `Sources/UI/NBTEditingUI.swift`

复制/显示二进制 TAG_String 时使用可读的 `RawString[n] xx xx ...` 描述。

### 回归测试

新增：

`Scripts/test_modern_actor_binary_string.sh`

覆盖：

- 含无效 UTF-8 `StorageKey` 的现代 zombie_horse actor；
- `BedrockWorldObjectScanner` 正常识别实体；
- NBT decode -> encode 原字节完全一致；
- 错误 VarInt 空 Compound fallback 被拒绝。

并加入 `Scripts/run_core_tests.sh`。

## 真实存档验证

对用户上传世界的全部 343 条 actor 做真实数据往返：

- 343 / 343 decode 成功；
- 343 / 343 encode 后与原始 actor NBT 逐字节一致；
- 154 个包含二进制 StorageKey 的 TAG_String 均被无损保留。

对真实 `digp + actorprefix` 快照运行完整 `BedrockWorldObjectScanner`：

- 有效 actor：322；
- 主世界 actor：225；
- 未知实体：0；
- zombie_horse：16。

对世界全部 SubChunk 做扫描：

- v9：27,687；
- 解码成功：27,687；
- 解码失败：0；
- v9 内部 Y 与 DB key Y 不一致：0。

因此本问题已确认属于现代 actor NBT 字符串兼容，而不是 SubChunk 格式问题。
