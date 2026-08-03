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

## Follow-up correction

- The block-search result controller now shares its viewed-state object with the world session while the user temporarily switches to the map. Returning through “返回方块列表” therefore restores the same yellow badges instead of creating a blank tracker. A new search still starts with an empty state, and nothing is persisted after the world editor closes.
- NBT searching now uses fallback priority rather than combining all categories: if any tag-name matches exist, only those are shown; otherwise direct tag values are searched; tag types are searched only if both earlier categories are empty.
- Compound/List child counts and parent summaries are no longer treated as tag values, eliminating unrelated container rows.
