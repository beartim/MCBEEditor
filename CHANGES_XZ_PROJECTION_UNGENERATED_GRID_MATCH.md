# X/Z 128-block projection, missing-section texture and grid matching

This revision extends the X/Z map renderer after the visual/hit/export-grid fix.

## X/Z 128-block negative-axis projection

- X mode now looks from the selected X plane toward **X-** for 128 blocks.
- Z mode now looks from the selected Z plane toward **Z-** for 128 blocks.
- Surface and height modes use the nearest non-air block along that orthographic ray.
- X-ray mode projects the nearest supported ore target found along the 128-block ray.
- Biome, ticking-area and slime modes deliberately continue to read the exact selected section plane, preserving the previously requested section-property semantics.
- All-loaded X/Z export expands its fixed-axis chunk slab to cover the same 128-block projection depth.

## Missing SubChunk display

- Bedrock commonly omits SubChunk records that are entirely air. Such omitted SubChunks inside an otherwise generated chunk are now treated as generated air rather than as missing terrain.
- The renderer receives the same generated-chunk state used by the Y map, preventing normal sky from being covered by the missing-section hatch.
- If an entire 128-block projection ray really has no generated/stored section data, the missing texture is still shown.
- The X/Z hatch now follows the same rendered-16-block sizing, light-gray base, soft-gray diagonal color, clipping alignment, spacing and line-width formula used by the Y-map placeholder.
- Live X/Z rasterization is raised to 4 pixels per block (subject to the existing 2048-side cap/downsampling) so the hatch no longer becomes visibly blocky when enlarged on iPad.

## SubChunk grid

- X/Z SubChunk grid uses the same `UIColor.label` 0.28 opacity as the live Y chunk grid.
- Grid lines use the same per-world-block line-width formula as Y mode.
- Grid drawing is non-antialiased, matching the crisp Y grid and keeping 16-block boundaries on rendered block edges.
- The existing power-of-two section sampling stride remains in place so downsampled 16-block boundaries stay stable.

## Regression coverage

`Scripts/test_nbt_tree_cross_section.sh` now checks the projection direction/depth, generated-air handling, Y-style missing texture, Y-style grid rendering and full-depth export slab.
