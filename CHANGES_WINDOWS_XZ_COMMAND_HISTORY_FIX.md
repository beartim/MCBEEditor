# Windows X/Z projection and command terminal refinement

- Fixed X/Z surface/height/mineral projection when `未生成子区块` is disabled: a missing SubChunk on the selected plane no longer stops the ray. The renderer continues through the complete negative-direction projection range and can select generated blocks behind missing front sections.
- Kept the enabled `未生成子区块` behavior unchanged: only the current 16-block chunk projection is rendered and missing sections use the aligned ungenerated texture.
- Added a Core self-test covering a missing front X plane with generated terrain farther behind it.
- Reduced vertical space used by the Windows header and map controls. World name/path now share one row and map control padding/status spacing is smaller.
- Command input now handles Up/Down on `PreviewKeyDown`, reliably recalling command history into the input line while leaving Left/Right and normal TextBox editing behavior intact.
- Every completed manual command now scrolls the terminal to the newest output and restores input focus.
- Generic parser usage errors are rewritten using the exact per-command help entry. `clear`, `give`, `kill`, etc. therefore show only their own iOS-matched usage/examples rather than their parser group's combined usage.
- Unknown commands now match iOS: `不存在的命令：<name>。输入 help 查看全部命令。`.
- Leading `/` now matches iOS: `命令不需要斜杠，请直接输入命令名称`.
- Command output wheel scrolling was reduced to 30 px per wheel notch for finer navigation.
- iOS sources were not changed in this update.
