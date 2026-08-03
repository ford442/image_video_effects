# Changelog — gen-sentient-cyber-chrono-void-serpent (b31, algorithmist)

## Critical bug fixes
- Bounds guard now uses `u.config.zw` (canonical) instead of `textureDimensions(writeTexture)`.
- Mouse: `u.zoom_config.yz` treated as 0–1 with y=0 top; world mapping uses centered transforms
  (`(m - 0.5)` / `(0.5 - m.y)`) — no y-flip, no re-normalization. Camera orbit unchanged visually.
- Canonical header order restored (bindings 0–12, then the exact Uniforms struct).

## Geometry added (role mandate)
- Full 3D SDF library: sdSphere / sdBox / sdTorus / sdOctahedron / sdCapsule + smin.
- Scale segments upgraded from spheres to rotating **octahedral chrono-glass shards** whose size is
  driven by Fracture Depth displacement.
- New **matID 3**: **torus chrono-rings** z-repeated along the spine, twisted against the body, bass- and
  treble-reactive — the serpent now visibly wears time-bands.
- New **matID 4**: free-floating **chrono-glass shards** in hashed grid cells, treble/fracture scaled.
- 2D geometric layer: **hex-tessellated armor etching** (hexCell/hexEdge pulse per cell) and a
  **Julia ring orbit-trap** temporal rift backdrop (animated c, palette-mapped, gated by Void Density).
- Adaptive raymarch: 80–120 steps scaled by Fracture Depth.

## Contract compliance
- Writes `writeTexture`, `writeDepthTexture` (real `1 - dO/maxDist` hit depth), `dataTextureA` every frame.
- Semantic luma-based alpha (was hardcoded 1.0). Audio only from plasmaBuffer[0].xyz.
- All 4 sliders live: Time Scale (spine + palette time), Plasma Intensity (bass gain + glow), Void Density
  (void floor + rift glow + fog), Fracture Depth (displacement + shard size + adaptive steps).
- Existing `updatedParams` defaults and `defaultValue` keys are retained byte-for-byte for saved-preset compatibility.

## Perf estimate
- ~325 lines. 80–120 raymarch steps × map() (spine warp + octa shard + ring repetition + glass cell +
  3 noise3D calls); calcNormal 6 map evals on hit; miss pixels run an 8-iteration Julia trap (cheap).
  ~20% heavier than before; est. 60fps discrete / 30-40fps integrated at 1080p.

## Gate
- `wgsl_precommit_gate.py`: PASS (naga OK, bindgroup compatible). 233 → 325 lines (+92).

## Rating prediction
- 4.3/5 — the serpent gains signature chrono jewelry (rings + glass shards) and the Julia rift gives the
  background a fractal identity that matches the "chrono-void" theme instead of a plain fog gradient.
