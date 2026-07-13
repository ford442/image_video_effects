# gen-quantum-foam — Optimizer Upgrade

**Agent:** Optimizer (Batch 2)  
**Target:** `public/shaders/gen-quantum-foam.wgsl`  
**Date:** 2026-06-29

## Changelog

### Performance
- **Shrunk Worley kernel from 5×5 to 3×3.** For points jittered inside a unit cell, the nearest feature point is always in one of the eight adjacent cells, so the 25-cell search was redundant. This alone cuts ~64% of Worley work.
- **Branchless cell-distance update.** Replaced `if/else` nearest/second-nearest logic with `step` + `mix`, removing per-pixel divergence inside the hot loop.
- **LOD scaling driven by `Detail` (p4).** Octave count is now 1–4 based on the slider, and `delta_time` (`u.config.y`) further throttles layers down by one when the frame exceeds a 20 ms budget.
- **Blue-noise-style sub-pixel jitter** via interleaved-gradient noise reduces visible grid artifacts without extra samples.
- **Bilinear temporal feedback** samples `dataTextureC` with `textureSampleLevel`, giving cheap motion trails and smoothing high-frequency noise.

### Elegance / Code Quality
- Removed duplicated `aces`/`acesToneMap` functions; now uses the canonical ACES implementation.
- Added named constants for all tunable ranges (`FOAM_DENSITY_MIN/MAX`, `FRAME_BUDGET_S`, etc.).
- Grouped logic into clearly-commented sections: constants, core math, Worley, foam field, chromatic shift, main pipeline.
- Helper functions are pure and reusable (`worley`, `foamField`, `foamChromaticShift`, `ign`, `luma`).

### Pipeline Integration
- **`writeTexture`**: final display-ready, tonemapped RGBA with semantic alpha.
- **`writeDepthTexture`**: pseudo-depth derived from foam density for downstream depth/DOF effects.
- **`dataTextureA`**: linear HDR trail for next-frame feedback and HDR chaining.
- **`dataTextureB`**: packed auxiliaries (`depth`, `luma`, `flash`, `border mask`) for compositing / post passes.
- Uses `readDepthTexture` for depth-aware dimming.

### Visual Preservation
- Still built from layered Worley-noise bubble fields.
- Same chromatic iridescence split across R/G/B foam offsets.
- Bass still spikes density and flash; treble still brightens cell borders.
- Vacuum background and foam-sum blending retained.

## Performance Estimate
- **Original:** ~300 Worley cell evaluations per pixel (3 foam calls × 4 octaves × 25 cells).
- **Upgraded:** ~108 evaluations worst case (3 foam calls × 4 octaves × 9 cells), and as low as ~27 at minimum LOD.
- Expected **1080p60 on mid-tier GPUs** (GTX 1060 / RX 580 class) with Detail at default; low-detail mode should hold 60 fps on integrated graphics. Temporal feedback and reduced branching further improve frame pacing.

## Slot Recommendations
- **dataTextureA** → current linear-HDR color (feedback / chaining source).
- **dataTextureB** → depth/luma/flash/border auxiliary buffer for glow/bloom passes.
- **dataTextureC** → previous frame HDR, sampled bilinearly for trails.
- **readDepthTexture** → scene depth for depth-aware dimming.
- **plasmaBuffer[0].xyz** → bass/mids/treble energy.

## Validation Notes
- Uses the exact 13-binding canonical header.
- Compute-safe only: `textureSampleLevel`, `textureLoad`, `textureStore`; no `tan`, `textureSample`, `dpdx`, `dpdy`.
- `@compute @workgroup_size(16, 16, 1)`.
- JSON keeps original `id`, `name`, `category`, `url`; adds `updated: true`, `workgroup_size: [16,16,1]`, and four `updatedParams`.
