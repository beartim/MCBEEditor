# LegacyTerrain / SubChunk compatibility update

This update adds persistent read/write support for Minecraft PE 0.10-era terrain and verifies every known persistent SubChunk encoding currently handled by MCBEEditor.

## Uploaded 0.10.0 world

The supplied world does not store `SubChunkPrefix (0x2f)` records. Its terrain is stored as `LegacyTerrain (0x30)`: 791 live terrain records were found, and every value is exactly 83,200 bytes.

MCBEEditor now decodes each 0x30 value as:

- 32,768 bytes BlockIDs (16 x 16 x 128, X-Z-Y ordering)
- 16,384 bytes block-data nibbles
- 16,384 bytes sky-light nibbles
- 16,384 bytes block-light nibbles
- 256 bytes height map
- 1,024 bytes biome/color samples

The 128-block-tall chunk is exposed internally as eight virtual numeric-ID v0 SubChunks at Y=0...7. Direct legacy block edits merge back into the original 0x30 value. Only BlockIDs and block-data nibbles are rewritten; light, height-map, biome/color, and any unknown trailing bytes are preserved.

## Persistent SubChunk versions

The read/write matrix is now:

- v0: numeric ID + data + sky light + block light
- v1: one persistent paletted storage
- v2-v7: numeric ID + data + sky light + block light
- v8: storage count + persistent paletted storages
- v9: storage count + absolute Y + persistent paletted storages

New v0/v2-v7 records include the full 4,096-byte legacy light tail and retain the exact requested version. In particular, v0 is no longer silently converted to v7 when a missing legacy SubChunk is created.

## Editor integration

LegacyTerrain is used by map rendering, block columns/details, block search, block NBT saving, and command block access (`setblock`, `fill`, `clone`). A LegacyTerrain-only dimension creates 0x30 air terrain for newly generated chunks rather than mixing in SubChunkPrefix records that Minecraft PE 0.10.x would not understand.

If an edit requires a modern block state, the existing whole-chunk upgrade path converts LegacyTerrain/numeric SubChunks to Version + Data3D + v9 SubChunks, including conversion of legacy height/biome data.

## Validation performed

- Synthetic byte-for-byte decode/encode round trips for v0, v1, v2, v3, v4, v5, v6, v7, v8, and v9.
- Numeric legacy block mutation followed by re-decode for every v0/v2-v7 version, with light tails unchanged.
- Synthetic 83,200-byte LegacyTerrain round trip and multi-field preservation checks.
- Swift decode/encode of an actual 83,200-byte LegacyTerrain value extracted from the supplied 0.10.0 world, including all eight virtual Y slices.
- Unified LegacyTerrain database read/write test verifies a block edit does not create a 0x2f record.
- Existing block-NBT/legacy-upgrade regression tests pass.
- Existing WorldCommandExecutor regression tests pass.

## Final integration fixes

The first integration placed the compatibility helpers in the correct source directory, but several production call sites still bypassed them and addressed only `SubChunkPrefix (0x2f)` keys. The final integration routes the following paths through `BedrockChunkSubChunkAccess` where appropriate:

- map surface rendering
- block-column inspection
- world block search
- chunk-level replace/search operations
- block edits and block-NBT persistence
- `setblock`, `fill`, and `clone` command caching/writeback
- map-region copy/replace operations
- empty/generated chunk creation

Region operations now merge edited legacy slices back into one 83,200-byte `LegacyTerrain (0x30)` value instead of creating mixed-format 0x2f records. Empty chunks in dimensions detected as LegacyTerrain worlds also use 0x30 storage.

Persistent paletted storage encoding was also corrected for `bitsPerBlock == 0`: the single block-state NBT follows the storage header directly, without a normal Int32 palette-count field.

Final regression coverage includes the complete core test suite in segments (to avoid runner wall-clock limits), the dedicated LegacyTerrain/SubChunk v0-v9 persistence test, the large WorldCommandExecutor semantic/runtime test, and the viewed/unsaved-state regression test. All completed successfully.
