# crystalline-fracture — Algorithmist notes (kimi, 2026-07-22 b13)

## Line delta
- Before: 175 lines → After: 238 lines (**+63**, within the +50–90 brief target; final count 238 ∈ [225, 265]).

## Key changes per technique

### 1. Click stress rings (u.config.y + ripples[])
- New block loops `clickCount = min(u32(u.config.y), 50u)` over `u.ripples[i]` (xy = click pos, z = spawn time — matches existing shader convention, e.g. ripple-blocks/predator-prey).
- Each click spawns an expanding ring wavefront: `waveFront = age * 0.35`, thin band via `exp(-abs(rd - waveFront) * 24.0)`, amplitude decaying `exp(-age * 1.2)`, active window `age ∈ (0, 4)`.
- Ring stress is scaled by `(1.0 + fractureAmt * 2.0)` so the Fracture Amount slider also controls click-ring loading; where K exceeds (grain-modulated) toughness, rings trigger cracks.

### 2. Weak grain boundaries (one fbm lookup)
- Added `vnoise()` (bilinear hash lattice) + `fbm()` (3 octaves).
- Single `grain = fbm(grainUV)` lookup drives spatially varying toughness: `toughness = (0.4 + mids*0.6) * (0.55 + grain*0.9)` and also modulates K (`* (0.7 + grain*0.6)`), so cracks preferentially propagate along weak paths — reads as real material grain. Grain scale tracks cellCount so it stays coherent with the Voronoi structure.

### 3. Crack memory healing
- Stress feedback raised from `prev.r * 0.5` → `prev.r * 0.98` — strictly < 1.0, so the geometric series still converges, but fracture patterns persist and evolve across frames.
- Safety: stored stress reservoir is clamped (`stressOut = min(stress, 6.0)`) so the slow 2%/frame decay cannot accumulate visually unbounded values through the feedback loop.

### 4. Slider wiring (existing JSON contract preserved)
- `cells` (zoom_params.x): Voronoi cell count (as before) + grain fbm scale coherence.
- `glow` (zoom_params.y): chromatic edge emission (as before) + now also drives crack-tip HDR bloom energy: `tip * (0.5 + edgeGlow * 5.0)`.
- `fracture` (zoom_params.z): crack growth rate `time * crackSpeed * (0.2 + fractureAmt*1.2)` + click-ring stress amplitude.
- `chromatic` (zoom_params.w): edge split width (as before) + now also drives the post chromatic aberration: `caStr = 0.001 + chromatic * (0.5 + bass) + depth * 0.001`.

## Contract compliance
- Canonical 13-binding layout unchanged; no bindings added/renumbered; binding 13 not declared.
- `@workgroup_size(16, 16, 1)` preserved.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- dataTextureA layout preserved: `.r` = stress, `.g` = crack connectivity, `.b` = 0.0, `.a` = alpha. Feedback coefficient 0.98 < 1.0.
- Sampler reads use `textureSampleLevel(..., 0.0)`; thin-film iridescence + SSS math untouched.
- No WGSL reserved identifiers used.

## QA
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/crystalline-fracture.wgsl` → **exit 0, 0 warnings** (naga OK, bindgroup compatible).
- `shader_definitions/generative/crystalline-fracture.json` parses clean; added `updatedParams` (4 entries mirroring params index 0–3, same names/defaults/min/max/step 0.01) and `"updated": true`. Nothing else changed.
- **No-GPU caveat:** this VM has no WebGPU adapter (`requestAdapter()` returns null; app falls back to Canvas2D), so visual QA of the new ring waves / grain-guided cracks / persistent memory is **deferred to real hardware**. Validated via naga + bindgroup gate only.
