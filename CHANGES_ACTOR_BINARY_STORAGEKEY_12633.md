# Minecraft 1.26.33 Actor / StorageKey compatibility

## Root cause

The uploaded 1.26.33.10 world stores modern entities through `digp -> actorprefix`; entities are not stored in SubChunk records, so this issue is unrelated to newer SubChunk versions.

The active LevelDB state contains 343 `actorprefix` records. The zombie-horse test area has 16 valid `minecraft:zombie_horse` actor records and all 16 are referenced by `digp`. MCBEEditor previously identified only 10 of them because newer actor NBT stores `internalComponents/EntityStorageKeyComponent/StorageKey` as an NBT String whose payload is actually an arbitrary 8-byte binary actor-storage key. Values containing bytes such as `0x91` are not valid UTF-8.

When ordinary little-endian NBT decoding reached such a StorageKey it failed UTF-8 validation. `ConsecutiveNBTCodec` then attempted the VarInt fallback; because the fallback did not require full input consumption, the same payload could be misaccepted as an empty compound. The entity therefore appeared as an unknown entity even though its later NBT still contained `identifier=minecraft:zombie_horse`.

## Fixes

- `BedrockNBTCodec` treats the named `StorageKey` string payload as a binary-safe one-byte string when UTF-8 decoding fails.
- Binary-safe StorageKey values are encoded with the same one-byte mapping, preserving every original byte during entity edits.
- Ordinary NBT strings remain strict UTF-8.
- `ConsecutiveNBTCodec` now accepts the little-endian VarInt fallback only when the fallback consumes the complete record (apart from zero padding), preventing malformed little-endian data from silently becoming an empty NBT root.
- Added `Scripts/test_actor_binary_storage_key.sh` and included it in the core regression suite.

## Validation on the uploaded 1.26.33.10 world

- 343 / 343 current actorprefix payloads decode successfully.
- 343 / 343 actorprefix payloads decode -> encode byte-for-byte identically.
- Unknown actor roots in the raw actor test: 154 before the fix, 0 after the fix.
- Zombie horses: 10 identified before the fix, 16 after the fix.
- All 16 zombie-horse storage references are present in active digp summaries.
- World-wide current leash knots: 11; the four knots around the reported player area remain correctly identified.
- Full core regression suite passed in two segments, including modern entity storage/editing and SubChunk/LegacyTerrain tests.
