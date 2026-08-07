# gen-evolutionary-cellular-gardens (tracker #337) — INTERACTIVIST upgrade

## Weaknesses found (original 207-line shader)

1. **No feedback memory** — the "cellular automaton" was re-derived each frame
   from time-slot hashing; no `dataTextureC` read, no `dataTextureA` write, so no
   real persistence, colony age, or self-organization.
2. **1:1 mouse mapping** — invasive-species zone followed the raw cursor
   instantly; no attractor lag, no click behavior; ripples ignored.
3. **Flat depth** — `writeDepthTexture` written as constant `0.0`.
4. **Hardcoded alpha** — `vec4(color, 1.0)` regardless of colony density.
5. **No FFT bands** — only plasmaBuffer bands used; no guarded bin detail.

Strengths preserved: real plasmaBuffer audio driving CA rule thresholds
(bass→birth, mids→survival, treble→refinement), multi-scale layering, species
colors, invasive-species concept. Soul untouched — edits are surgical.

## Techniques applied (interactivity domain)

1. **Temporal feedback memory / colony age** — `dataTextureC` via non-filtering
   `textureLoad`; per-pixel `colonyAge` (alpha channel) slowly approaches
   occupation → long-lived colonies become "established" (richer body, golden
   patina, higher relief). Bounded trail buffer (`prev.rgb*0.93 + color*0.09`,
   clamped to 2.5) written to `dataTextureA`; history bioluminesces back into the
   live frame so growth follows its own channels.
2. **Mouse nutrient gravity well + click colony burst** — spring-damper smoothed
   cursor (extraBuffer[133..136]) replaces 1:1 mapping; click rising edge
   ([137/138]) spawns a bounded (`exp(-age*1.2)`) expanding growth-front ring that
   locally boosts birth rules and blooms. Guarded engine-ripple loop
   (`min(u32(u.config.y),50u)`) seeds spore nutrient bumps into the rule
   thresholds — input becomes emergent growth, not direct paint.
3. **FFT-band genetic pressure** — guarded bins 1–8 (`extraBuffer[6..13]`,
   `arrayLength` guard) split fft_lo/fft_hi: fft_lo accelerates local evolution
   speed, fft_hi drives the shimmer/sparkle rate.

## Slider wiring (all 4 stay live, unchanged semantics)

- **p1 Cell Scale** → CA lattice scale (as before).
- **p2 Evolution Speed** → base mutation frequency (now FFT/mouse-modulated locally).
- **p3 Invasive Force** → mouse-zone disturbance AND click-burst amplitude.
- **p4 Bioluminescence** → glow gain (as before).

## Contract compliance

- Canonical 13 bindings verbatim; Uniforms struct exact. ✅
- `@compute @workgroup_size(16, 16, 1)` + bounds guard. ✅
- Every frame writes: `writeTexture`, `writeDepthTexture` (generated structural
  relief: coarse 0.5 + mid 0.3 + fine 0.15 + age 0.2), `dataTextureA`
  (trail + colonyAge). ✅
- Audio ONLY `plasmaBuffer[0].xyz` + guarded FFT bins 1–8. ✅
- Feedback via non-filtering `textureLoad` only. ✅
- Semantic alpha: colony density + bioluminescence + burst ring, clamp [0, 1]. ✅
- Persistent state ONLY extraBuffer[133..138], single-writer guard
  `gid.x==0u && gid.y==0u` + `arrayLength` check; FFT bins read-only. ✅

## JSON

`updatedParams` **byte-exact vs `git show HEAD:`** (verified programmatically —
array text identical). Additive only: `features` populated (was `[]`) with
truthful entries (audio-reactive, mouse-driven, click-reactive,
temporal-feedback, depth-aware, depth-output, semantic-alpha, procedural) and the
description extended with a truthful upgrade sentence.

## Gate result

`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK,
bindgroup compatible, 0 extraBuffer violations). Dead-slider audit: PASS (0 dead).
