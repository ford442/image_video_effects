# gen-chaos-game-ifs — Optimizer Notes

## Changes Made
- Expanded from 134 to 179 lines (+45 lines).
- Added named constants: `MIN_ITER`, `MAX_ITER`, `IFS_SCALE_BASE`, `HEX_TAPS`, `HEX_WEIGHTS`.
- Implemented LOD scaling: iteration count varies by distance from screen center (`centerDist`) and audio bass.
- Refactored IFS into `ifsPoint` helper with branchless cascaded `select` attractor picking.
- Added 7-tap hex bokeh glow kernel (`hexBokehGlow`) for softer attractor falloff.
- Extracted `attractorGlow` helper for the R/G/B channel glow curves.
- Added early-exit background fallback: deep void grain where attractor glow is negligible.
- Temporal ghosting uses branchless `mix` with audio-driven feedback.
- Minimized texture reads: single `textureLoad` for `readDepthTexture` and `dataTextureC`.
- Semantic alpha derived from glow sum, ring contribution, bass, and input depth.

## Pipeline Compliance
- Canonical 13-binding compute header preserved verbatim.
- `@workgroup_size(16, 16, 1)` unchanged.
- Writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Uses `textureLoad` for storage/depth reads.

## Validation
- `naga` validation passed.
- JSON `features` array updated to reflect new capabilities.
