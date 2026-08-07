# Optimizer note — gen-quantum-fluorescent-aether-moth-swarm (tracker #339)

## Weaknesses found
- **Uniform-truth violations**: `audio = u.config.y` (rippleCount, not audio);
  `click = u.config.y > 0.5`; mouse divided by `res` even though
  `zoom_config.yz` is already 0–1 uv; scatter condition `u.zoom_config.y > 0.0`
  was effectively constant (−2.0 almost always) — dead interaction logic.
- **Extreme per-pixel noise cost**: `curlNoise` did 6 × `snoiseVec3` = **18
  simplex evaluations per pixel**, plus 1 for spawn — ~19 snoise/px.
- **LDR feedback chain**: tone map applied before writing dataTextureA, so the
  temporal trail buffer accumulated clipped LDR.
- **Flat depth** (0.0) and **hardcoded alpha 1.0**.
- **Unclamped advection fetch** — `advect_gid` could leave the texture.
- Dead code after refactor (`snoiseVec3`, 3D `curlNoise`); magic numbers
  (0.92 decay, 0.7/0.9 spawn band, 20.0 freq, 0.02 advect, …).

## Techniques applied (Optimizer domain)
1. **Analytic/pruned curl evaluation** — replaced the 18-tap 3D curlNoise with
   a **4-tap curl of a scalar noise potential** (`curl2`: perpendicular gradient
   of snoise ⇒ divergence-free flow), +1 tap for z-wobble. ~19 → ~6 snoise/px
   (**~3× cheaper**), visually equivalent swirl character.
2. **Coarse cull / branchless gating** — the audio-mandala path's `if` branch
   became a smoothstep gate multiplied in; hover-force uses one `inverseSqrt`.
3. **HDR-ready feedback chain** — linear HDR stored in dataTextureA (bounded by
   `min(hdr, HDR_CEIL=6)`); ACES only on writeTexture presentation; trails stay
   in HDR across frames for slot chaining.
4. **Named constants + dead-code elimination** — all magic numbers promoted
   (`TRAIL_DECAY`, `SPAWN_LO/HI`, `ADVECT_SCALE`, `MOUSE_FORCE`, …); removed
   unused `snoiseVec3`/3D `curlNoise`.

## Slider wiring (all 4 live, byte-exact JSON params)
- p1 Swarm Density → spawn-field frequency (`SPAWN_FREQ * p1`).
- p2 Curl Intensity → flow domain scale + flow amplitude (`0.6 + p2*0.8`).
- p3 Glow Strength → emission gain of spawned moths.
- p4 Audio Sensitivity → mandala assembly gate (`smoothstep(bass+mids) * p4`).

## Performance notes
- snoise evals/px: ~19 → ~6 (4 curl + 1 wobble + 1 spawn). No loops except the
  guarded, bounded FFT bin sum (1–8, `arrayLength` guard).
- Single `textureLoad` feedback fetch (advected, clamped to bounds) — removed
  the redundant un-advected `old_color` read.
- All iteration bounded; no branches in the hot path except the FFT guard.

## Contract compliance
- Canonical 13-binding header verbatim; Uniforms struct exactly
  `config, zoom_config, zoom_params, ripples`. ✔
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✔
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame. ✔
- Audio ONLY `plasmaBuffer[0].xyz` (bass+mids mandala gate, mids exposure,
  treble shimmer) + guarded FFT bins 1–8 (indices 5–12, read-only). ✔
- Feedback reads via non-filtering `textureLoad(dataTextureC, …)` only;
  dataTextureA = HDR swarm state, writeTexture = presentation. ✔
- Semantic alpha = swarm intensity (`spawn*0.7 + luma(hdr)*0.4`, 0.03–0.95). ✔
- Real generated depth: dense clusters sit closer
  (`1 − spawn*0.85 − luma*0.15`). ✔
- Mouse-down now drives scatter repulsion (`zoom_config.w > 0.5`); mouse uv
  top-down y flipped correctly. ✔
- No persistent extraBuffer state used. ✔

## JSON
`updatedParams` (4 indexed objects) byte-exact (verified vs `git show HEAD:`).
Additive only: description extended truthfully, features populated (was `[]`).

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK,
bindgroup compatible), exit 0.
