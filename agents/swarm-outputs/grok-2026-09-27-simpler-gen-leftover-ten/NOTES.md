# NOTES — Grok simpler generative leftover (10) — 2026-09-27

Second-pass ideas on a list that already carried 09-09 / 09-14 / Batch-18 cards.
User asked for a second 2-idea pass on all 10. Existing ideas kept. Saved params
byte-exact (firefly gained a matching `params` array; updatedParams unchanged).
No new springs. Percolation extraBuffer still unused.

## Per shader

### gen-rainbow-firefly-dance
- Kept verbatim: Intensity / Speed / Scale / Color Shift; orbits; comet tails; click mini-swarms; swirl C history.
- A packing: linear HDR in A; ACES on write. Matches C reads.
- Ideas in the diff: `flash` / `duty` (Photinus codes); `answerDelay` even/odd antiphase, held shrinks delay and boosts attract.
- JSON: added `params` matching updatedParams; tagged `upgraded-rgba`.

### gen-rainbow-icosahedron-cascade
- Kept verbatim: 12-vert/30-edge SDF; golden-angle yaw; silhouette trap; four sliders; mouse orbit.
- A packing: linear HDR in A (header previously lied ACES-in-A). ACES on write.
- Ideas in the diff: `icosaFaces` dual centroids `dualGlow`; `clickPulse` / `shellReach` (renamed off reserved `target`).
- JSON: added `click-reactive`.

### gen-rainbow-smoke (`gen_rainbow_smoke.*`)
- Kept verbatim: CFL; spectral emitters; radial click burst; [133..136] spring; raw A; B vorticity write.
- A packing: raw (velocity.xy, density, temperature).
- Ideas in the diff: `ringBand` toroidal smoke rings; `khTangent` / `khVis` Kelvin–Helmholtz billows.

### gen-orb (`gen_orb.*`)
- Kept verbatim: RK4 Lorenz; σ/ρ/β/trail; lobe-switch sparks; C± eyes; held orbit; click kicks.
- A packing: ACES display RGBA in A.
- Ideas in the diff: `stretch` / `lyapGain` filament sheen; `poincare` z=ρ−1 plane flashes.

### gen-newton-fractal
- Kept verbatim: degree/zoom/precision/warp; damped-Newton; conv-order sheen; A.a RD pack.
- A packing: ACES RGB; RD in alpha fraction. Unchanged pack helpers.
- Ideas in the diff: `striations` from `atan2(lastDz)`; `wander` from high `orbitSecond`.

### gen-percolation-threshold
- Kept verbatim: 80×60 lattice pack; conduction pulses; opalescence; held/click doping. No extraBuffer.
- A packing: lattice in [0..79]x[0..59]; display elsewhere.
- Ideas in the diff: `redBond` when `occCount == 2` on spanning sites; `mass` fade on finite clusters.

### gen-neon-snowfall
- Kept verbatim: Nakaya SDF; terminal velocity; flutter glint; gust/eddy; [133] bass_env.
- A packing: ACES display RGBA in A.
- Ideas in the diff: `riming` / `graupel` mix; `bankY` / `bankPrev` snowbank with gust lean.

### gen-neon-lotus
- Kept verbatim: petal SDF; Vogel carpels; beads; pond ripples; four sliders.
- A packing: ACES display RGBA in A. No invented C feedback.
- Ideas in the diff: `openAmt` nyctinasty; `padBody` / `padVein` / `peltate` lily pad.

### gen-kimi-crystal (`gen_kimi_crystal.*`)
- Kept verbatim: hex grid; Nakaya; Fresnel/Beer; 22° halo + parhelia; click nucleation.
- A packing: ACES display RGBA in A.
- Ideas in the diff: `prismMinDeviation90` / `halo46`; `pillar` plate-habit light pillars. `tan()` replaced with `safeTan` (sin/cos).

### gen-kimi-nebula (`gen_kimi_nebula.*`)
- Kept verbatim: mouse O-star; Rs / [OIII]/Hα/[SII]; dust extinction; bright rims; Sedov shells.
- A packing: ACES display RGBA in A.
- Ideas in the diff: `pdr` PAH skin outside Rs; `eggTail` globules pointing away from the star.

## Gates

Naga 10/10. Precommit 10/10. extraBuffer 0 new violations. Dead sliders 0 (file-stem list including underscore aliases). Catalog 1386 unique definition IDs, unified 1373, generative 478. Jest 741 pass / 6 fail (pre-existing WASM `bridge/api.js`). SKIP_WASM_BUILD=1 build green. Real-GPU visual QA: external.
