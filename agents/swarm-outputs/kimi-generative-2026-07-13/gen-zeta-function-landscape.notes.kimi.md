# gen-zeta-function-landscape — Optimizer Notes

## Changes Made
- Expanded from 127 to 170 lines (+43 lines).
- Added named constants: `MIN_TERMS`, `MAX_TERMS`, `HEX_TAPS`, `HEX_WEIGHTS`.
- Implemented LOD scaling: term count is reduced in regions with large `y_offset` via `lodFactor`.
- Added a 7-tap hex bokeh kernel (`hexBokehSample`) for temporal smoothing of the previous frame.
- Extracted `landscapeColor` helper to centralize zero-proximity chromatic coloring.
- Added early-exit background fallback with subtle grain for low-height pixels.
- Replaced `2.0 * 3.14159265` literals with `TAU` constant.
- Minimized texture reads: single `textureLoad` for `readDepthTexture` and `dataTextureC`.
- Semantic alpha now blends intensity, foreground mask, and input depth.

## Pipeline Compliance
- Canonical 13-binding compute header preserved verbatim.
- `@workgroup_size(16, 16, 1)` unchanged.
- Writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Uses `textureLoad` for storage/depth reads; `textureSampleLevel(..., 0.0)` only for hex-bokeh sampling of `dataTextureC`.

## Validation
- `naga` validation passed.
- JSON `features` array updated to reflect new capabilities.
