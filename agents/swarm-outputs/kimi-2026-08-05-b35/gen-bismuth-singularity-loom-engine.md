# gen-bismuth-singularity-loom-engine — Interactivist upgrade notes (batch 35, tracker #321)

**Files:** `public/shaders/gen-bismuth-singularity-loom-engine.wgsl` (186 → 272 lines, +86),
`shader_definitions/generative/gen-bismuth-singularity-loom-engine.json` (additive `features` only; `updatedParams` byte-exact).

## What changed

1. **AUDIO TRUTH FIX (bug).** The shader read `u.config.y` as "audio" — that field is
   the ripple count, so the extrusion force and vein brightness were silently driven
   by clicks. Now: bass/mids/treble from `plasmaBuffer[0].xyz`; bass→extrusion force
   (slider w, as named "Acoustic Extrusion Force") + gravity-well pull + vein energy;
   mids→lattice weave speed + spring stiffness; treble→iridescence band tightening.
2. **Sprung pointer (mouse ×3 params).** Critical-damped spring in
   `extraBuffer[133..138]` (single-writer + arrayLength guard, dt clamp, init flag).
   Smoothed pointer drives: (a) lattice twist angles in `map()` (threaded through as
   function args — `map`/`getNormal`/`raymarching` signatures extended), (b)
   gravity-well depth (`pull_str`), (c) subtle camera parallax sway on the ray origin.
   Mouse y kept top-down truth (no source flip; sway sign chosen for pitch feel).
3. **FFT multi-band color split.** Guarded bins 1/4/7 (`arrayLength>13u`) tint the
   emissive flux veins R/G/B respectively. No fake spectrum.
4. **Click spacetime shockwaves.** Guarded ripple loop (`min(u32(u.config.y),50u)`),
   age window 0–2 s, expanding ring flexes color and lifts depth veil locally,
   non-negative, and halves local feedback persistence.
5. **Emergent gravitational memory feedback.** `dataTextureA` written every frame
   (was missing); `textureLoad(dataTextureC)` reads last frame. Persistence =
   f(bass, accumulated glow, hit mask, shock reset) — the rotating lattice leaves
   history-dependent ghost wakes off-surface; fresh hits stay crisp; clicks erase.
   Soft HDR bound `col/(1+col*0.12)` keeps accumulated veins finite.
6. **Real depth + semantic alpha.** `writeDepthTexture` now written (was missing):
   raymarch hit depth `1 - dO/MAX_DIST` (near-is-one), 0 on miss, shock lift off-surface.
   Alpha: 1.0 only on crystal hit (opaque by design), translucent glow veil otherwise.

## Slider contract (all 4 stay live, index order via `u.zoom_params.xyzw`)

- x Singularity Mass → lensing pull strength (kept, now + bass/pointer terms)
- y Bismuth Iterations → hopper subtraction depth (kept)
- z Iridescence Frequency → palette frequency (kept, now treble-modulated)
- w Acoustic Extrusion Force → now honestly wired to **bass** (was ripple count!)

## Gate

`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK, bindgroup
compatible, no extraBuffer violations). JSON `json.load` OK.

## Perf estimate

Raymarch core unchanged (120 steps max, ≤10 hopper iters, 6-tap normal on hit).
Added per-pixel: spring O(1), 1 textureLoad + mix, ≤50-iteration ripple loop
(early-out). `MarchResult` struct return is free after inlining. ≈ +3–6% per-pixel.
