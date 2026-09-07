# NBT tree hierarchy + X/Y/Z map cross-section update

## NBT editor

- Replaced text-only UITableView indentation with a shared `NBTTreeCell` used by the tree-style NBT editors.
- The NBT type icon and both text lines now move right together for every hierarchy depth.
- Long/deep rows use an internal horizontal scroll surface. A left swipe first reveals hidden row content; after the content has reached its end, a new left swipe is handed back to the table so the delete action can appear.
- Expanded parents draw hierarchy guides. The guide continues through descendants and terminates with an L-shaped segment pointing at the icon of the last direct child.
- The behavior is shared by world/player/entity/structure/village/standalone/read-only NBT trees and the map block-NBT panel.

## Map X / Y / Z rendering

- Added an `X | Y | Z` render-axis selector; default remains `Y`.
- X/Z modes render a vertical cross-section centered on the map render center. The slice center Y defaults to 63.
- In a vertical section, higher Y is displayed at the top and lower Y at the bottom.
- Tapping a section point opens `选择X轴方块` or `选择Z轴方块`. Axis entries are ordered from the larger/positive coordinate toward the smaller/negative coordinate.
- X/Z keep the three display switches visible, disable chunk selection, and relabel the chunk grid as a 16×16 subchunk grid.
- Auto-render follows panning/zooming on the section horizontal axis and Y axis.
- The map object-layer menu gains `显示建筑高度限制` in X/Z mode, enabled by default. Limits are drawn as red dashed horizontal lines.

## Regression protection

- Added `Scripts/test_nbt_tree_cross_section.sh` and wired it into `run_core_tests.sh`.
