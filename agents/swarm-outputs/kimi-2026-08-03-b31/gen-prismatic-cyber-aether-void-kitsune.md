# Changelog — gen-prismatic-cyber-aether-void-kitsune (b31, algorithmist)

## Critical bug fixes
- **Mouse y-flip removed**: map() used `-mouse.y * 3.0` / `-mouse.y * 2.0` (a y-flip). `u.zoom_config.yz`
  is 0–1 with y=0 top; the warp center is now mapped with `(0.5 - y)` into a y-up world — no flip, no
  re-normalization. The stale "[-1,1] normalized space" comment was corrected.
- Bounds guard now uses `u.config.zw` instead of `textureDimensions(writeTexture)`.
- Canonical header order restored (bindings 0–12, then the exact Uniforms struct); the old struct comment
  claiming config.y was "Audio/ClickCount" was fixed (it is rippleCount).

## Geometry added (role mandate)
- Full 3D SDF library: sdSphere / sdBox / sdTorus / sdOctahedron / sdCapsule + smin.
- New **matID 3**: **prismatic octahedral shard swarm** — 6 orbit cells (angular repetition), treble-scaled,
  counter-rotating around the kitsune.
- New **matID 4**: three stacked **auroral torus tail-rings** behind the body, bass-pulsed radii.
- Octahedral **shoulder crystals** smooth-unioned onto the armor.
- 2D geometric layer: **hex-tessellated rune grid** replaces the pure-noise rune mask (per-cell pulse phase
  from hex cell IDs, still gated by simplex noise + Rune Glow slider), and a **kaleidoscopic fold** on the
  volumetric storm backdrop (fold count from mids).
- Adaptive raymarch: 80–120 steps scaled by Storm Density.

## Contract compliance
- Writes `writeTexture`, `writeDepthTexture` (real `1 - t/maxDist` hit depth), `dataTextureA` every frame.
- Semantic luma-based alpha (was hardcoded 1.0). Audio only from plasmaBuffer[0].xyz.
- All 4 sliders live: Tail Dispersion, Current Warp (mouse warp), Storm Density (storm + adaptive steps),
  Rune Glow (hex runes).

## Perf estimate
- ~393 lines. 80–120 raymarch steps × map() (body ~8 prims + 9-tail loop + shards + 3 rings + simplex calls);
  calcNormal 6 map evals on hit; miss pixels run a 40-step fbm storm march. ~20% heavier than before;
  est. 60fps discrete / 25-35fps integrated at 1080p.

## Gate
- `wgsl_precommit_gate.py`: PASS (naga OK, bindgroup compatible). 309 → 393 lines (+84).

## Rating prediction
- 4.4/5 — the kitsune gains a full jewelry set (shards, rings, shoulder crystals) and the runes now read as
  deliberate circuitry instead of noise blobs; storm has real symmetry structure.
