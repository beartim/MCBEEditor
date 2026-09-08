# Textures PNG / colors.txt / ReadMe changes

- PNG texture override filenames now use the iOS-safe `namespace_block.png` form.
- Only the first underscore is converted to the Bedrock namespace colon, e.g. `minecraft_bedrock.png` -> `minecraft:bedrock` and `minecraft_polished_blackstone.png` -> `minecraft:polished_blackstone`.
- Literal-colon PNG filenames such as `minecraft:bedrock.png` are no longer accepted.
- Added `Documents/Textures/colors.txt` parsing. Each valid line is `namespace:block #RRGGBB`.
- Invalid lines are ignored; later duplicate entries override earlier ones.
- Priority is `colors.txt` > PNG > built-in map colour.
- `Documents/Textures/ReadMe.txt` is rewritten with the canonical format/priority instructions whenever the shared texture directory is prepared, including app launch/activation.
