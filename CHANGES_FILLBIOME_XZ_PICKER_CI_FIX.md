# fillbiome / X-Z picker / CI regression fix

## CI regression

- Fixed `Run portable core tests` failure:
  `error: biome ID/name catalogue is unexpectedly small: 2`.
- `BedrockBiomeCatalog` is now only a presentation/color adapter. The actual
  numeric/string biome catalogue lives in `BedrockDataValueCatalog.biomes`.
- Updated the regression check to count the shared biome table instead of old
  `entry(...)` literals in `BedrockBiomeCatalog.swift`.
- The shared catalogue currently contains 89 entries and remains the single
  source used by the biome picker and `fillbiome` string-ID parser.

## X/Z axis picker

- Restored the manually selectable axis range to current X/Z ±128 blocks.
- Rows remain ordered from the largest coordinate to the smallest coordinate.
- Added a separate automatic-selection upper bound equal to the current
  rendered X/Z plane.
- When the picker opens, it automatically selects the largest non-air X/Z
  coordinate that is **not greater than the current rendered X/Z**.
- Blocks in the +axis half of the ±128 range remain visible and can still be
  selected manually; they are only excluded from automatic initial selection.
- If no qualifying non-air block exists, the picker falls back to the tapped /
  current rendered plane coordinate.

## Regression protection

- Updated both X/Z regression scripts to check the distinction between the
  full manual ±128 range and the capped automatic initial selection.
- All standalone `Scripts/test_*.sh` checks pass after the change.
