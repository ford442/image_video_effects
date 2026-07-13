# gen-fireworks-roman-candle — Optimizer Notes

## Changes Made
- Expanded from 111 to 175 lines (+64 lines).
- Added named constants: `NUM_TUBES`, `NUM_SHOTS`, `NUM_TRAILS`, `NUM_BURST_SPARKS`, `HEX_TAPS`, `HEX_WEIGHTS`.
- Implemented a reusable 7-tap hex bokeh kernel (`hexBokehGlow`) for all star/glow rendering.
- Refactored tube-star evaluation into `evalTubeStars` helper; mouse candle into `mouseCandle` helper.
- Replaced per-shot `if (age < 0.0 || age > 3.5)` with branchless `step` culling.
- Added early-exit/background fallback: sky color fades near horizon and pixels with no fireworks keep a cheap background.
- Minimized texture reads: single `textureLoad` each for `dataTextureC` and `readDepthTexture`.
- Switched from `hash1` UV hash to `hash2` for background dust to avoid name collision and improve distribution.
- Introduced semantic alpha based on intensity and depth rather than hardcoded 1.0.

## Pipeline Compliance
- Canonical 13-binding compute header preserved verbatim.
- `@workgroup_size(16, 16, 1)` unchanged.
- Writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Uses `textureLoad` for storage/depth reads; no `textureSample` calls on storage textures.

## Validation
- `naga` validation passed.
- JSON `features` array updated to reflect new capabilities.
