# fillbiome / info / X-Z selection limit

## X/Z axis picker

- X/Z cross-section projection only looks toward the negative axis.
- The axis picker now uses the current rendered X/Z plane as its maximum coordinate.
- The picker can therefore no longer select a higher X/Z coordinate that is outside the visible projection slab.
- The list remains descending, so its automatic selection still prefers the highest non-air coordinate available within the permitted range.

## fillbiome command

New command syntax:

    fillbiome <dimension> x1 y1 z1 x2 y2 z2 <numeric biome id | string biome id>

- Dimensions use the existing `overworld`, `nether`, and `the_end` names.
- String biome IDs are resolved through the shared Bedrock biome registry. A string with no known numeric ID is rejected.
- Numeric IDs do not need to exist in the built-in registry. They are treated as raw 32-bit biome values; signed negative values such as `-1` are preserved by their 32-bit bit pattern.
- Data3D edits only biome cells whose world Y is inside the inclusive command range.
- Data2D/Data2DLegacy intentionally ignore Y because those formats store only a horizontal biome plane. Their byte storage still requires IDs in 0...255.
- The implementation reuses `BedrockChunkStore.setBiomeID`, so command writes follow the same database mutation path as the map selection biome editor.

## World information

The Information tab now inserts these rows immediately after the world name and before player count:

- `种子`: `RandomSeed` from `level.dat`.
- `附魔种子`: `EnchantmentSeed` from the local-player NBT record (falling back to the first player record if no local-player record is present).

## info command

New command:

    info

- Takes no arguments.
- Calls `WorldInspector` directly, so the terminal output stays synchronized with the Information tab.
- Emits every world-information row as a separate command output line in `标题=值` form.

## Regression coverage

- Added `Scripts/test_fillbiome_info_xz_selection.sh`.
- Updated the older X/Z picker regression to require the current plane as the positive/high coordinate bound.
- The command parser portable test covers string biome IDs, arbitrary raw numeric IDs, unknown string IDs, and argument-free `info`.
- The command-executor portable compile includes `WorldInspector.swift` and passes with the new command cases.
