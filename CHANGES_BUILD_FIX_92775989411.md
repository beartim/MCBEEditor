# Build fix for logs_92775989411

The GitHub Actions failure was caused by an obsolete portable regression assertion in `Scripts/test_nbt_tree_cross_section.sh`.

The old assertion required the previous fixed negative-axis projection implementation:

- `let maximumProjectionCoordinate = axis == .x ? fixedX : fixedZ`
- legacy two-scope X/Z export UI strings
- legacy all-loaded/current-section exporter variables

Those implementation details were intentionally replaced by the new range + six-angle export design. The test now validates the current behavior instead:

- configurable `projectionCoordinateRange`
- both positive-to-negative and negative-to-positive projection directions
- X/Z export range cell with ±infinity controls
- six export directions: x+, x-, y+, y-, z+, z-
- X mode defaults to x+, Z mode defaults to z+
- all-infinity range resolves to the loaded dimension extent
- showing missing X/Z SubChunks restricts block projection to the 16-block chunk containing the section plane
- missing SubChunk overlay still checks only the actual selected section plane

No user-facing feature was reverted for this build fix.
