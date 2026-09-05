# Batch 71 briefs — generative-only cohort

This batch upgrades ten existing generative effects without changing renderer
APIs, the canonical uniform shape, saved parameter values, or WASM behavior.

| Effect | A/C ownership | Upgrade focus |
|---|---|---|
| `gen-cybernetic-mycelium-neural-web` | ACES display RGBA | Exact four-neighbor connectivity, spring cursor, mutation bursts |
| `gen-cyclic-automaton` | state / firing / refractory / bloom | Excitable state machine, directional painting, finite click ignition |
| `gen-cycloid-bloom` | ACES display RGBA | Exact arc persistence, held lens, spectral petal voices |
| `gen-cymatic-plasma-mandalas` | ACES display RGBA | Bounds-safe spring state, held vortex, nodal click rings |
| `gen-cymatic-quantum-silk-loom` | ACES display RGBA | Live weave speed, raymarched plucks, semantic silk coverage |
| `gen-de-jong-attractor` | density / hue / tube depth / alpha | Raw attractor accumulation, 3D hero orbit, click deformation |
| `gen-depth-refracted-liquid-stained-glass` | ACES display RGBA | Depth refraction, held lens, finite glass-flex fronts |
| `gen-dla-copper-deposition` | deposit / depletion / oxidation / activity | Persistent eight-neighbor DLA, electrodes, tip sparks |
| `gen-dmt-fractal-zoom` | ACES display RGBA | Correct normalized mouse warp, portal fronts, escape depth |
| `gen-dragon-curve` | ACES display RGBA | Fold shocks, spring navigation, spectral filament lighting |

## Cohort contract

- Bindings 0–12 remain declared, workgroups remain 16×16×1, and every shader
  guards out-of-range invocations.
- Every C access is an exact `textureLoad`; no simulation history uses sampler
  filtering. Only `dataTextureA` is written; B remains layout-only.
- Bass, mids, and treble come from `plasmaBuffer[0].xyz` and have distinct
  geometry, motion, deposition, color, or lighting roles.
- Mouse hover/position behavior is preserved, held input strengthens it, and
  click loops are capped at 50 with finite timestamp windows.
- Raw cyclic, De Jong, and DLA state remains un-tone-mapped. Display outputs
  use canonical ACES and effect-derived semantic alpha.
- The only persistent scalar state uses guarded `extraBuffer[133..138]` spring
  windows; shaders without spring state do not write the buffer.
- Every definition exposes exactly four named `params`, aligned with x/y/z/w.
