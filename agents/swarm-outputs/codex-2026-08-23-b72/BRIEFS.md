# Batch 72 briefs — ethereal generative cohort

This batch upgrades ten existing generative effects without changing renderer
APIs, the canonical uniform shape, saved parameter ranges, or WASM behavior.

| Effect | A/C ownership | Upgrade focus |
|---|---|---|
| `gen-ethereal-cyber-chrono-nebula-phoenix` | trap / SDF / nebula / coverage | Raw temporal phoenix memory, guarded halo spring, spectral plasma |
| `gen-ethereal-cyber-chrono-void-whale` | ACES display RGBA | Volumetric leviathan persistence, finite time fronts, held camera |
| `gen-ethereal-cyber-plasma-void-dragon` | ACES display RGBA | Exact plasma persistence, three-band lighting, ACES output |
| `gen-ethereal-glass-flora-terrarium` | ACES display RGBA | Exact glass-flora history and semantic ray coverage |
| `gen-ethereal-quantum-hologram-bonsai` | ACES display RGBA | Correct raw-range controls and reserved bass envelope state |
| `gen-ethereal-quantum-holographic-fractal-coral` | ACES display RGBA | Spectral coral shading, click propagation, temporal depth |
| `gen-ethereal-quantum-medusa` | ACES display RGBA | Live swimming speed, held gravity, finite chromatic click fronts |
| `gen-ethereal-silk-veil` | ACES effect-layer RGBA | Exact veil memory and timestamped fabric plucks |
| `gen-evolutionary-cellular-gardens` | trail RGB / colony age | Reserved attractor state, plasma-driven evolution, ACES display |
| `gen-feedback-echo-chamber` | ACES display RGBA | Exact multi-tap echo reconstruction and semantic echo controls |

## Cohort contract

- Bindings 0–12 remain declared, workgroups remain 16×16×1, and every shader
  guards out-of-range invocations.
- Every C access is an exact `textureLoad`; the echo chamber reconstructs its
  subpixel taps manually from exact loads. Only `dataTextureA` is written.
- Bass, mids, and treble come from `plasmaBuffer[0].xyz` and have distinct
  geometry, motion, color, evolution, or lighting roles.
- Existing mouse behavior remains live; held input strengthens applicable
  fields and click loops are capped at 50 with finite timestamp windows.
- Raw phoenix and garden state remains un-tone-mapped. Display outputs use
  canonical ACES and effect-derived semantic alpha.
- Persistent scalar state is guarded and limited to `extraBuffer[133..138]`.
- Every definition exposes exactly four named `params`, aligned with x/y/z/w.
