# NBTTreeCell indentationWidth build fix

## Failure

Xcode 15.4 failed while emitting the MCBEEditor Swift module with:

- `overriding property must be as accessible as its enclosing type`
- `cannot override with a stored property 'indentationWidth'`

The failure was at `Sources/UI/NBTTreeCell.swift` where the custom tree cell declared:

`private var indentationWidth: CGFloat = 18`

`UITableViewCell` already exposes an `indentationWidth` property, so Swift treated the stored property as an invalid override.

## Fix

- Renamed the cell's private stored indentation state to `treeIndentationStep`.
- Kept the existing `configure(... indentationWidth:)` parameter label so callers and compact NBT layouts do not need an API change.
- Updated all internal icon and hierarchy-guide calculations to use `treeIndentationStep`.
- Added a regression assertion that forbids reintroducing `private var indentationWidth:` in `NBTTreeCell` and requires the non-conflicting state name.

The behavior requested for NBT hierarchy indentation, horizontal reveal before delete, and L-shaped hierarchy guides is unchanged.
