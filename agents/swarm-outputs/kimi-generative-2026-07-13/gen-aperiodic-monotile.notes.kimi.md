# gen-aperiodic-monotile — Optimizer Notes

## Changes Made
- Expanded from 138 to 183 lines (+45 lines).
- Added named constants: `HEX_Q`, `HEX_R`, `HEX_TAPS`, `HEX_WEIGHTS`.
- Implemented a 7-tap hex bokeh edge kernel (`hexBokehEdge`) for anti-aliased, chromatic tile outlines.
- Added LOD scaling: `lodScale` halves for very high tile densities (`scale > 28.0`) using branchless `select`.
- Extracted `tileColor` and `vignette` helpers for cleaner color composition.
- Added early-exit/background fallback: wandering-noise background outside tile regions.
- Temporal feedback is now branchless via `mix(prev * decay, ..., feedback)`.
- Minimized texture reads: single `textureLoad` for `readDepthTexture` and `dataTextureC`.
- Semantic alpha combines edge intensity, value, and input depth.

## Pipeline Compliance
- Canonical 13-binding compute header preserved verbatim.
- `@workgroup_size(16, 16, 1)` unchanged.
- Writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Uses `textureLoad` for storage/depth reads.

## Validation
- `naga` validation passed.
- JSON `features` array updated to reflect new capabilities.
