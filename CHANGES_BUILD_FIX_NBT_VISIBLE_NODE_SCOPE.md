# Windows build fix: NBT visible-node scope collision

This follow-up fixes the Windows desktop compile error reported after the full parity audit package:

- `MCBEEditor.Desktop/NbtEditorWindow.cs(520,22): CS0136`
- `VisibleBatchNodes(TreeViewItem, bool)` declared the pattern variable `node` in the method block and then reused `node` as the nested `foreach` iteration variable.
- The nested iteration variable is now `visibleNode`; behavior is unchanged.

A regression assertion was added to `Scripts/test_windows_full_parity_audit.sh` so this exact C# scope collision cannot be reintroduced silently.
