# Batch 37 coordinator review

The next eight smallest pending clean single-pass generative shaders were
upgraded as one 4-agent swarm (Algorithmist / Visualist / Interactivist /
Optimizer, two shaders each). Tracker #332–339.

| # | Shader | Agent | Lines |
|---|--------|-------|-------|
| 332 | gen-fireworks-fan-shell | Algorithmist | 169 → 222 |
| 333 | gen-fireworks-horse-tail | Algorithmist | 170 → 218 |
| 334 | gen-fireworks-ring-shell | Visualist | 170 → 201 |
| 335 | gen-fireworks-kamuro-gold | Visualist | 173 → 207 |
| 336 | gen-symbiotic-cyber-fungal-core-reactor | Interactivist | 184 → 314 |
| 337 | gen-evolutionary-cellular-gardens | Interactivist | 207 → 303 |
| 338 | gen-chrono-kitsune-prism-weaver | Optimizer | 208 → 269 |
| 339 | gen-quantum-fluorescent-aether-moth-swarm | Optimizer | 208 → 240 |

## Coordinator verification (post-swarm)

- **Saved-preset contract:** 7/7 pre-existing `updatedParams` verified
  byte-exact vs git HEAD (programmatic JSON comparison).
  `gen-symbiotic-cyber-fungal-core-reactor` had none — gained 4 indexed
  additive updatedParams whose names/defaults/min/max/step were verified to
  match its existing `controls` dict exactly (the `zoom_config.w` "Mutation
  Rate" control was correctly excluded as an engine-owned mouseDown channel;
  its 0.1 default behavior is preserved as the hold-to-mutate surge base rate).
- **Historical bug-class scan (all 8, automated + manual):**
  - `@workgroup_size(16, 16, 1)` 8/8; resolution bounds guards 8/8.
  - Every-frame writes to `writeTexture`/`writeDepthTexture`/`dataTextureA` 8/8.
  - Zero `textureSample(`, `dpdx/dpdy`, banned identifiers.
  - All `dataTextureC` reads are non-filtering `textureLoad`.
  - extraBuffer writes confined to [133..138], single-writer + arrayLength
    guards (fungal-reactor [133..136] spring attractor, gardens [133..138]
    attractor/click state — the only two shaders persisting state).
  - Audio only from `plasmaBuffer[0].xyz` + guarded FFT bins 1–8; zero
    config.y-as-audio (three shaders had exactly that bug: fungal-reactor,
    kitsune-weaver, moth-swarm).
  - All 13 canonical bindings present 8/8.
- **Fireworks-family normalized-pointer bug (flagged class):** present in all
  four fireworks shaders — `zoom_config.yz` (already 0–1 canvas uv) treated as
  pixel coordinates. Fixed in all four to centered aspect space
  `(yz - 0.5) * res / min(res)`, consistent with each shader's uv convention.
  Kitsune-weaver and moth-swarm had the same pixel-divide bug, also fixed.
- **Coordinator-level repair (moth-swarm):** the upgraded mouse mapping
  introduced a `1.0 - mouse01.y` flip that vertically mirrored the mouse
  against the shader's `uv.y = -1 at top` convention. Flip removed; mapping is
  now 1:1 top-down. Re-gated green after the fix.
- **Notable agent-level repairs (confirmed in review):**
  - Fungal-reactor: fake audio from `u.config.y` (rippleCount), broken
    Mutation Rate reading engine-owned `zoom_config.w`, teleporting 1:1 mouse,
    and missing A/depth writes all repaired; spring-smoothed gravity-well
    attractor + click spore-burst + feedback nutrient memory added.
  - Cellular-gardens: fake per-frame hash CA replaced with real colony-age
    feedback memory; click colony-burst growth front; relief depth and
    semantic alpha fixed.
  - Kitsune-weaver: config.y-as-audio + double-normalized mouse fixed;
    bounding-sphere early-out, tetrahedral normals, hoisted invariants.
  - Moth-swarm: config.y-as-audio + pixel-divide mouse + dead scatter
    condition (constant -2.0, now mouseDown repulsion) fixed; 18-tap vector
    curlNoise replaced by 4-tap scalar-potential curl (~3× cheaper,
    divergence-free by construction).
  - Fan-shell/horse-tail: closed-form ballistic + linear-drag integrator
    (terminal fall velocity), temporal-coherent wind/gusts, heat-derived
    generated depth.
  - Ring-shell/kamuro-gold: HDR overwhite/white-gold cores, audio-reactive
    color temperature, per-shell atmospheric haze + depth fog, split-tone
    grade, heat-derived generated depth.

## Structural proof

- Focused gate: `wgsl_precommit_gate.py` 8/8 (naga OK, bindgroup compatible,
  0 workgroup/extraBuffer violations) — re-run after the moth-flip repair.
- `audit_extrabuffer.py` PASS; `audit_dead_sliders.py` PASS (0 new).
- Generated lists: regenerated without `--base-url`; only
  `public/shader-lists/generative.json` carries batch metadata.
- Unified manifest (gitignored artifact): 1,310 entries / 1,310 unique IDs
  (+1 vs Batch 36 = fungal-core-reactor now qualifying with updatedParams).
- Unrelated generated report drift (timestamps/counts only) restored
  byte-for-byte to HEAD.
- Jest + production build: results recorded in memory/2026-08-06.md.
- This VM has no GPU adapter: real-GPU visual QA remains an external handoff.
