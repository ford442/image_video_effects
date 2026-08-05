# Batch 35 coordinator review

The next eight smallest pending clean single-pass generative shaders were
upgraded as one 4-agent swarm (Algorithmist / Visualist / Interactivist /
Optimizer, two shaders each). Tracker #316–323.

| # | Shader | Agent | Lines |
|---|--------|-------|-------|
| 316 | gen-bioluminescent-cyber-aether-void-seahorse | Algorithmist | 153 → 320 |
| 317 | gen-velocity-bloom | Algorithmist | 169 → 266 |
| 318 | gen-dragon-curve | Visualist | 178 → 238 |
| 319 | gen-fractal-chrono-dendrite-forge | Visualist | 180 → 251 |
| 320 | gen-raptor-mini | Interactivist | 184 → 249 |
| 321 | gen-bismuth-singularity-loom-engine | Interactivist | 186 → 272 |
| 322 | gen-3d-sierpinski-chaos | Optimizer | 192 → 242 |
| 323 | gen-astro-kinetic-chrono-orrery | Optimizer | 199 → 285 |

## Coordinator verification (post-swarm)

- **Saved-preset contract:** 7/7 shaders with pre-existing `updatedParams`
  verified byte-exact vs git HEAD (programmatic JSON comparison).
- **Dendrite-forge schema repair (accepted deviation):** the stale legacy
  `controls` block (raw 0–5/0–2 ranges, a schema shared by only 3 defs and
  never consumed by the app, which reads `params`/`updatedParams`) was replaced
  with the standard 4-index normalized `updatedParams`; slider names/roles
  preserved, WGSL rescales normalized values to the legacy engine ranges, and
  the entropy/dispersion/gravity effective defaults match the legacy defaults
  exactly. `mix(2,5,complexity)` previously extrapolated to 17 iterations at
  the old slider maximum — now bounded at 5.
- **Historical bug-class scan (all 8, automated + manual):**
  - `@workgroup_size(16, 16, 1)` 8/8; bounds guards 8/8.
  - Every-frame writes to `writeTexture`/`writeDepthTexture`/`dataTextureA` 8/8.
  - Zero `textureSample(`, `dpdx`, `tan(` (orrery hits were comments + a
    `tanHalf` variable), zero `1.0 - zoom_config.z`/mouse flips.
  - All `dataTextureC` reads are non-filtering `textureLoad`.
  - All `extraBuffer` writes confined to [133..138] with single-writer
    (`global_id.x == 0u && global_id.y == 0u`) + arrayLength guards.
  - Ripple loops guarded with `min(u32(u.config.y), 50u)` where ripples are
    used (4 shaders); the other 4 do not reference `u.ripples`.
  - Audio only from `plasmaBuffer[0].xyz` + guarded FFT bins 1–8.
- **Notable agent-level repairs (confirmed in review):**
  - Seahorse: non-canonical extended Uniforms struct (resolution/frame/
    matrices) rebuilt to the canonical 4-field struct.
  - Bismuth Loom: `u.config.y` (rippleCount!) was being read as "audio" —
    honestly rewired to plasma bands.
  - Orrery: 3/4 sliders were dead; per-step Kepler solves hoisted to per-pixel
    caches (~5–10× cheaper); `tan()` removed; missing A write fixed.
  - Sierpinski: centered-UV filtering history read → clamped `textureLoad`;
    flat 0.0 depth → projected splat depth; dead `audioIntensity` rewired.
  - Raptor-mini: copied-depth passthrough → generated capsule relief depth;
    A write added.

## Structural proof

- Focused gate: `wgsl_precommit_gate.py` 8/8 (naga OK, bindgroup compatible).
- `audit_extrabuffer.py` PASS (0 out-of-range writes); `audit_dead_sliders.py`
  PASS (0 def errors; 197 known triaged baseline only).
- Generated lists: regenerated without `--base-url` so only
  `public/shader-lists/generative.json` carries real batch metadata (105
  insertions); all other category lists byte-identical to HEAD.
- Unified manifest (gitignored artifact): 1,309 entries / 1,309 unique IDs,
  carries new features + dendrite's 4 updatedParams.
- Unrelated generated report drift (dead_sliders/extrabuffer/wgsl_precommit
  reports) restored byte-for-byte to HEAD.
- Jest + production build: see closeout below (results recorded in
  memory/2026-08-05.md).
- This VM has no GPU adapter: real-GPU visual QA remains an external handoff.
