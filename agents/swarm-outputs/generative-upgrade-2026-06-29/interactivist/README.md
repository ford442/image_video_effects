# Interactivist Upgrade — `gen-quantum-pollen`

## What Changed

Upgraded **Quantum Pollen** for maximum interactivity and reactive life while keeping its layered, drifting pollen-swarm character.

### New Techniques

| Technique | How It Works |
|-----------|----------------|
| **Mouse gravity well** | Pollen is pulled toward the cursor along a soft inverse-distance force; adds organic orbit-like motion. |
| **Click burst** | On mouse down, a radial outward velocity injects fresh energy and temporarily overrides decay trails. |
| **Audio reactivity** | Bass → brightness pulse + halo size; mids → morph/drift speed + color saturation; treble → sparkle frequency. |
| **Video luma-keyed spawn** | Bright regions from `readTexture` seed additional pollen particles, blending the shader with live input. |
| **Depth-aware transparency** | Alpha fades where depth is high so pollen sits naturally in 3D scenes; depth output is adjusted accordingly. |
| **Motion-vector advection** | Previous frame is sampled along the local drift vector for flowing, direction-aware trails. |
| **Temporal accumulation** | Decay-based feedback through `dataTextureA` ↔ `dataTextureC` creates emergent, self-reinforcing flow. |
| **Domain warp** | fBM-driven warping of UV space adds organic, ever-changing currents. |
| **Chromatic aberration + ACES** | Subtle radial CA scaled by bass and depth, finished with ACES tone mapping. |

### Preserved Soul

- Three layered particle fields with soft halos and core sparkles.
- Pastel/bioluminescent pollen palette (now driven by `psychedelicPalette`).
- Time-based drift and vortex motion.
- Same `id`, `name`, `category`, and `url`.

## Parameter Mapping

- **p0 — Swarm Density**: layer scale / grid density.
- **p1 — Morph Flow**: drift speed and domain-warp evolution.
- **p2 — Bloom Glow**: neon glow intensity.
- **p3 — Feedback Trails**: advection strength and temporal decay.

## Performance Estimate

- **Per-pixel cost**: ~3 hash lookups, 3 particle layers, 2 fBM calls (3 octaves each), 4 texture samples.
- **Target**: 60 fps at 1080p on mid-tier GPU.
- **No loops > 3 octaves**, no per-pixel branching in hot paths (uses `select`/`mix`).

## Dependencies on Canonical Patterns

- Uses the exact 13-binding header from `WGSL_BUILTINS_GENERATIVE.md` §0.
- Entry point: `@compute @workgroup_size(16, 16, 1)`.
- Bounds guard with `global_id`/`pixel` vs `res`.
- Only `textureSampleLevel`, `textureLoad`, `textureStore` used.
- `tan`, `textureSample`, `dpdx`, `dpdy` avoided.
- Semantic alpha: computed from presence and depth, not hardcoded.
