# Viewed badge and NBT search correction

- Fixed the yellow `已查看` accessory on iOS 13 by giving the custom accessory view an explicit intrinsic size and frame.
- Enabled viewed badges only for:
  - entity/block-entity rows in the Entity tab after `编辑 NBT` is chosen;
  - entity/block-entity rows in map selection results after `编辑 NBT` is chosen;
  - block search results after the result row is tapped.
- All other list call sites fall back to ordinary disclosure indicators and do not display viewed badges.
- Replaced every shared NBT tree search with one deterministic priority:
  1. tag name;
  2. direct tag value;
  3. tag type.
- Removed NBT path matching completely and updated all NBT search placeholders accordingly.
- Added regression coverage for viewed-badge scope, Edit-NBT marking, no path matches, and name/value/type result ordering.
