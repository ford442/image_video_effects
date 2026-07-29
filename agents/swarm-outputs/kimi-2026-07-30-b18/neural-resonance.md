# Agent Notes: neural-resonance (Batch 18, Algorithmist)

**Date:** 2026-07-30
**Lines:** 100 → 162 (+62, within the +50 to +90 target)
**Gate:** `python3 scripts/wgsl_precommit_gate.py --files public/shaders/neural-resonance.wgsl` → ✅ GREEN (naga OK, bindgroup compatible, no workgroup errors/warnings, no extraBuffer violations)

## Priority 1 — MASK-AS-COLOR FEEDBACK BUG (fixed)

Before: `dataTextureA` stored the mask quad `(mouseMask, feedbackMix, |curl|*10, alpha)`, but the feedback path sampled `dataTextureC` (previous frame's A) **as color** and mixed it into the display — so masks (including the `|curl|*10` blue-channel garbage) bled into the image. Same bug class as Batch 14's spore-galaxy.

After:
- `dataTextureA` now stores the **DISPLAY color** `(finalColor, finalAlpha)` — raw, never tonemapped. `dataTextureC` next frame therefore reads back real color, which is what `mix(chroma, feedback.rgb, feedbackMix * ...)` expects.
- `dataTextureB` now stores the **mask quad** — same 4 values, same order: `(mouseMask, feedbackMix, length(curl) * 10.0, finalAlpha)`. Written every frame.
- Feedback blend verified: default slider 0.55 → `mix(0.25, 0.96, 0.55) ≈ 0.64` mix factor, now blending actual previous-frame color instead of masks.

## Techniques implemented

1. **Spring-dampered mouse mask** — critically damped spring (`omega = 9.0`, damping ratio 1 via `accel = ω²(target − pos) − 2ω·vel`) easing the warp-emphasis center. State in `extraBuffer[133..136]` (pos.xy, vel.xy), `extraBuffer[137]` = last time for a clamped `dt`. Thread (0,0) integrates; all threads read. Snaps to raw mouse on first frames (`time < 0.1`, `lastTime <= 0`), or after a >1.5 UV teleport. Raw mouse stays the spring target; `mouseMask`/`mouseDelta` now use `springPos`.
2. **Click resonance rings** — loop over `u.ripples[i]` guarded by `min(u32(u.config.y), 50u)`. Each live ripple (`0 < age < 1.5s`) adds an aspect-corrected expanding band at radius `age * 0.5` (band width grows with age, amplitude fades linearly over 1.5s). `ringEnergy` (capped at 1.5) injects a bright `synapseTint` band into the feedback color, slightly lifts alpha, and pulls depth slightly forward. Rings persist and smear via the temporal feedback loop.
3. **Slider rewiring/documentation** — the 4 existing params already mapped to real algorithm constants; kept the exact mappings and documented the contract in-source:
   - **Amplification** (zoom_params.x, idx 0): curl noise frequency `mix(0.15, 1.35, x)` × audio gain `(1 + bass*0.45)`.
   - **Curl Strength** (zoom_params.y, idx 1): warp displacement amplitude `mix(0.005, 0.08, y)`.
   - **Feedback Mix** (zoom_params.z, idx 2): temporal blend `mix(0.25, 0.96, z)`, also drives feedback alpha mix.
   - **Chromatic Drift** (zoom_params.w, idx 3): RGB split distance `mix(0.0, 0.03, w)` along the curl vector, modulated by treble.

## Preserved verbatim (per CAUTION)

- `hash12`, `noise`, `curlField` helpers — untouched.
- Aspect-corrected warp (`aspectUV`, `mouseDelta`, `warpedUV` math) — unchanged except `mouseDelta` now centers on `springPos`.
- `synapseTint` sin() palette line — byte-for-byte identical.
- extraBuffer usage strictly in `[133..137]` (inside the allowed `[133..255]` range); no reserved/FFT bins touched.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, `textureSampleLevel(..., 0.0)` for all sampler reads, writes to `writeTexture`/`writeDepthTexture`/`dataTextureA`/`dataTextureB` every frame.

## JSON changes

`shader_definitions/artistic/neural-resonance.json`: added **only** the `updatedParams` array (indices 0–3, names/defaults/min/max/step exactly as in the brief) and `"updated": true`. No existing param renamed, re-defaulted, or reordered. JSON validated with `json.load`.

## Deviations

- Used `extraBuffer[137]` (last integration time) in addition to `[133..136]` — still within the permitted `[133..255]` window; needed for a frame-rate-independent `dt` and stale-state detection.
- Added a `clamp(finalColor, 0, 1)` after ring injection so stacked ripples cannot blow past 1.0 before the (raw) display color is written to A; keeps the feedback loop stable.
- New bindings: none. No changes to Renderer.ts / types.ts / bindgroups or any other shader/JSON.
