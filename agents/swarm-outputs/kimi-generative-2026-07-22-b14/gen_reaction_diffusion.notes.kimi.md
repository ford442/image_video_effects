# gen_reaction_diffusion — Kimi Notes (2026-07-22, batch b14)

## Line delta
- Before: 179 lines → After: 234 lines (**+55**, within the +50–90 / 229–269 target)

## Gate / validation
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen_reaction_diffusion.wgsl` → **exit 0, 0 warnings** (naga OK, bindgroup compatible, workgroup convention OK)
- JSON parses cleanly; `updated: true`, `updatedParams` has exactly 4 entries mirroring params 0–3 (same names/defaults/min/max/step; ids unchanged in `params`).

## Key changes per brief technique

### 1. Treble micro-stimulus
- New `trebleSpeckle()` helper: 96×96 hash cell field, re-jittered at 12 Hz (`floor(time*12)` in the hash seed), hard-gated by `step(0.985, h)` so only ~1.5% of cells fire, and scaled by `smoothstep(0.08, 0.55, treble)` (plasmaBuffer[0].z).
- Signed via a second per-cell hash (`speckleSign`) so speckle can nudge the FHN activator either way; injected into FHN `du` (×0.9) and into Gray-Scott `grayB` via `abs()` (×0.5). Hats/cymbals now seed tiny wavelets across the whole substrate.
- Display-only sparkle added to `fitzColor` (cool white glint on fired cells) — sim state untouched.

### 2. Click spiral seeds (u.config.y)
- New `spiralSeed()` helper: rotating **dipole** (paired +/− Gaussian lobes, separation 0.022, σ≈0.014) centered on the cursor. Arm angle = per-click hash base + chirality × time × 2.4, so the paired stimuli rotate and wind the medium into spirals.
- Chirality flips per click via `hash21(floor(clickCount)+0.5, 7.7)`; each new click re-orients/re-hands the seed.
- Gated by `u.zoom_config.w` (injects while pointer down) and scaled by pulse strength. Injected signed into FHN `du` (×1.35) and as `abs()` into GS `grayB` (×0.7); also contributes to `waveFront` and a magenta seed glow in the display path.

### 3. Stimulus slider disentangled
- `pulseStrength` moved from `zoom_params.z` → `zoom_params.x` (Excitability).
- `zoom_params.z` (Stimulus) now drives **only** `diffA`/`diffB` (diffusion) — pure transport control.
- FHN timestep `fitzDt` moved from z → `zoom_params.y` (Recovery), which is semantically a timescale knob.
- Named aliases `exciteAmt/recovAmt/stimAmt` + comment block document the new semantics. JSON ids/names/defaults/min/max/step untouched (saved-preset contract).

### 4. Sliders drive real algorithm constants
- x Excitability: GS `feed`, `mouseRadius`, `pulseStrength`, FHN threshold `aParam` (0.55→0.85).
- y Recovery: GS `kill`, FHN `epsilon` (0.05→0.12), FHN `fitzDt` (0.055→0.095).
- z Stimulus: `diffA` (0.15→0.28), `diffB` (0.07→0.14) only.
- w Model Blend: unchanged `fitzMode` smoothstep crossfade.

## Preserved (per cautions)
- `dataTextureA` write stores raw `vec4(newState, waveFront, fitzMode)` — **no clamp/saturate/tonemap**; negative FHN values survive in rgba32float. Comment added at the write site.
- `dataTextureB` write intact (slot chaining).
- hue-preserve-clamp + ACES + IGN dither chunk verbatim; reseed-on-dead-black init detection (`abs(prev.r)+abs(prev.g) < 0.0001`) verbatim.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to writeTexture/writeDepthTexture/dataTextureA every frame, `textureSampleLevel(..., 0.0)` sampler reads, `textureLoad` for storage reads. No new/renumbered bindings, no reserved identifiers.

## QA flags
- **No-GPU caveat:** this VM has no WebGPU adapter; visual QA (spiral winding behavior, speckle density, slider feel) is deferred to real hardware. Validation here is static (naga + bindgroup + convention gate) only.
- Behavioral watch-items for hardware QA: spiral dipole only injects while mouse is down (per "click drops a seed at cursor"); if clicks should persist after release, a click-edge latch in extraBuffer[133..255] would be needed — not implemented to keep changes minimal and stateless.
- GS mode gets `abs(spiralStim)`/`abs(trebleStim)` (unsigned) since GS concentrations must stay non-negative; FHN gets signed injection for proper dipole winding.
