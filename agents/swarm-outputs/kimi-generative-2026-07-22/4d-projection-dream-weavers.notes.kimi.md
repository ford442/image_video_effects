# 4D Projection Dream Weavers — Upgrade Notes

**Role:** Algorithmist
**Date:** 2026-07-22
**Shader:** `public/shaders/4d-projection-dream-weavers.wgsl`
**JSON:** `shader_definitions/generative/4d-projection-dream-weavers.json`

## Key changes

- **Spring-damper 4D navigation:** smoothed z/w slice angles + per-axis velocity stored in `extraBuffer[5..8]` (indices 0–4 left untouched, bounds-guarded with `arrayLength(&extraBuffer) > 8u`). Thread (0,0) integrates one critically-damped spring step per frame (`stiffness` scales with mouse-sensitivity slider, `damping = 0.82`, `dt` clamped to [0.001, 0.05]); all threads read the smoothed state. Raw mouse jumps now ease through the 4D slice instead of teleporting.
- **Worley dream-dust layer:** added `worley3D` (F1, 27-cell, jitter via existing `hash13`). Sparse sparkle via `pow(1 - F1, 24)`, animated along time + smoothed z/w, treble-modulated brightness (`plasmaBuffer[0].z`), and depth-faded via the fractal depth field so dust hides in dense regions. Dust color comes from a phase-shifted cosine palette.
- **Cosine-palette dimension tint:** added `cosinePalette`; tint phase driven by smoothed `(z + w)` + red-channel field + slow time, mixed at exactly 0.25 so the original blue→cream palette stays dominant.
- **Slider rewiring (generic boilerplate removed):** deleted the shared `applyGenerativePrimaryControls` helper and wired each slider directly into the algorithm:
  - `zoom_params.x` (Base Scale) → base zoom `mix(1.0, 3.2, p)` + mids.
  - `zoom_params.y` (Temporal Speed) → evolution speed `mix(0.15, 1.4, p)` + bass.
  - `zoom_params.z` (Fractal Detail) → amplitude of the 2nd/3rd octaves (`n2`, `n3` — previously `detail` was computed but **unused**, a latent bug now fixed).
  - `zoom_params.w` (4D Mouse Sensitivity) → 4D travel range `mix(1.5, 6.0, p)` + spring stiffness.
- Kept the canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, chromatic per-channel 4D offsets, temporal persistence via `dataTextureC`, ACES tone map, and writes to `writeTexture` / `dataTextureA` / `writeDepthTexture` every frame. No binding 13 (not used by original).

## Line count delta

- **Before:** 132 lines
- **After:** 221 lines (+89, within the +50..+90 brief target of 182–222)

## Gate / validation

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/4d-projection-dream-weavers.wgsl` → **exit 0, Passed: 1, Warnings: 0** (naga OK, bindgroup compatible).
- JSON validated with `python3 -m json.tool`; only `updatedParams` + `"updated": true` added, all existing fields (param ids/defaults/ranges) untouched.

## QA flags

- **Eyeballed constants (verify on real GPU):** spring `stiffness = mix(6.0, 18.0, pMouse)` / `damping = 0.82` — settle time tuned by feel; may want stiffer/looser on real hardware. Dust `pow(..., 24.0)` sparsity and `depthFade` smoothstep edges (0.9 → 0.35) are guesses; tint mix locked at 0.25 per brief.
- **No GPU in this VM** — `navigator.gpu` unavailable, so visual QA (dust density, tint richness, spring feel, trail interaction with the new smoothed z/w) is **deferred to a real-GPU run**. Naga validation + bindgroup compatibility are the only automated checks here.
- **One-frame lag:** non-(0,0) threads read the previous frame's spring state (intentional, avoids cross-thread race within a dispatch); imperceptible at 60 fps but worth knowing.
- First frame before any spring integration reads `extraBuffer[5..8]` as engine-zeroed values, so the slice starts at the 4D origin until the mouse moves — acceptable, but verify the initial frame looks intentional on GPU.
