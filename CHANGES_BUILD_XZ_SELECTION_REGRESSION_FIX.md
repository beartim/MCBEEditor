# X/Z selection regression test fix

## Problem
GitHub Actions stopped in `Scripts/run_core_tests.sh` at `test_fillbiome_info_xz_selection.sh` with:

`X/Z auto-selection must choose the largest non-air coordinate not exceeding the rendered plane`

The application implementation had intentionally gained two X/Z automatic-selection modes:

- Normal X/Z view: choose the largest non-air coordinate inside the automatic projection range.
- Ore/X-ray X/Z view: choose the largest highlighted ore coordinate inside the automatic projection range.

The old regression check still searched for the pre-X-ray single-condition source text and therefore failed even though normal-mode fallback behavior remained intact.

## Fix
Updated `Scripts/test_fillbiome_info_xz_selection.sh` so it separately verifies:

1. the requested lower/upper automatic projection bounds are enforced;
2. ore-priority mode exists;
3. ore-priority mode uses `BedrockBlockIdentifier.isHighlightedOre(...)`;
4. normal mode still falls back to `!block.primaryState.isAir`.

No runtime X/Z selection behavior was reverted.
