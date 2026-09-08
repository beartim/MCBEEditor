# Block color third audit

This pass continues the map-color audit for both the Y surface renderer and the X/Z cross-section renderer.

## Corrected colors and rule ordering

- `minecraft:sunflower` and legacy alias `minecraft:sun_flower` now use sunflower yellow (`#E2B93B`) instead of the old generic red-flower color.
- Common flowers now keep distinct semantic colors: blue orchid, allium, azure bluet, tulips, oxeye daisy, cornflower, lily of the valley, wither rose, lilac, peony, dandelion/golden dandelion, and rose bush.
- Legacy `red_flower` (ID 38) and `double_plant` (ID 175) now use their data value when deciding map color, so old worlds no longer collapse every flower into red.
- `deadbush` is brown rather than being captured by the generic bush-green rule.
- `dried_kelp_block` is darker than live kelp; `wet_sponge` differs from dry sponge.
- Poplar foliage is now split into red, orange and yellow variants instead of inheriting the poplar timber color.
- Spruce, birch, jungle, acacia, dark-oak and oak leaves retain distinct greens; legacy `darkoak_*` aliases are handled before broad oak matching.
- `small_dripleaf_block` is recognized as vegetation, and `red_shrub` gets its own reddish foliage color.
- `straw_bed` uses a straw/tan color instead of falling back to an undyed white bed.

## Copper and metal families

- Raw copper storage blocks are handled before the generic copper family.
- Copper oxidation is detected by the oxidation stage anywhere in the identifier, covering cut copper, doors, grates, bulbs, lanterns, chests, chains and other current variants.
- Exposed/weathered/oxidized lightning rods follow their actual patina stage even though their identifiers do not contain the word `copper`.
- `iron_chain` uses the same neutral iron color as `chain`.

## Special and technical blocks

- Chain command blocks and repeating command blocks now have distinct green and purple colors rather than sharing the normal command-block orange.
- `lit_smoker` is explicitly classified instead of falling through to a hash fallback.
- `minecraft:unknown` now has a stable, recognizable purple technical-block color.
- Normal, chain and repeating command blocks now use separate orange/green/purple map colors.
- `lit_smoker` and legacy `lit_pumpkin` are explicitly classified instead of relying on broad fallbacks.
- Skeleton and wither-skeleton skulls now differ (bone vs dark charcoal), matching their visible material.
- Infested blocks now visually follow their host material where possible (deepslate, mossy stone, cobblestone, stone bricks) rather than always using one generic gray.

## Current Bedrock families covered

The semantic catalog was cross-checked against the current Bedrock stable block listing and expanded for current families such as cinnabar, sulfur, poplar, golden dandelion, dried ghast, copper utility blocks, light blocks, chemistry element blocks, pale-garden vegetation and related variants.

## Regression coverage

`Scripts/test_block_colors_full_audit.sh` now checks:

- all 256 legacy numeric IDs (only the intentionally unused/reserved IDs may use fallback colors),
- legacy metadata-driven flower and dye variants,
- representative modern block families,
- rule-order regressions such as sunflower/red-flower, ender-chest/chest, soul-sand/sand, command-block variants, poplar leaves/timber, straw-bed/white-bed and host-specific infested blocks.
