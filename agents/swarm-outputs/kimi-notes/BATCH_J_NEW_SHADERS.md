# Batch J — 8 New Generative Shaders

**Agent:** Kimi
**Date:** 2026-05-31
**Scope:** Create 8 entirely new generative shaders with full upgrade suite (temporal, chromatic, audio-reactive, mouse-driven, depth-aware).

---

## Shader List

| # | ID | Name | Lines | Concept |
|---|----|------|------:|---------|
| 1 | `sacred-geometry-torus` | Sacred Geometry Torus | 118 | Golden ratio torus knots with phi-harmonic layers and rotating nodes |
| 2 | `plasma-jet-stream` | Plasma Jet Stream | 123 | High-energy radiating plasma jets with turbulence and shock sparks |
| 3 | `holographic-crystal` | Holographic Crystal | 114 | Crystal facet interference with rainbow holographic shifts and moiré |
| 4 | `spore-galaxy` | Spore Galaxy | 112 | Organic spore particles in galactic spiral arms with nebula dust |
| 5 | `neural-synapse-web` | Neural Synapse Web | 130 | Pulsing network nodes connected by traveling synaptic signal lines |
| 6 | `lava-lamp-blobs` | Lava Lamp Blobs | 118 | Classic metaball lava blobs with chromatic warm-cool shifts |
| 7 | `acoustic-string-theory` | Acoustic String Theory | 120 | Vibrating string harmonics in perspective with audio-driven pluck |
| 8 | `magnetic-flux-garden` | Magnetic Flux Garden | 128 | Ferrofluid-like field lines between cursor poles with organic warp |

**Average lines:** 120

---

## Design Patterns

### 13-Binding Contract
All 8 shaders declare the full immutable binding set:
- `u_sampler` (0), `readTexture` (1), `writeTexture` (2), `u: Uniforms` (3)
- `readDepthTexture` (4), `non_filtering_sampler` (5), `writeDepthTexture` (6)
- `dataTextureA` (7), `dataTextureB` (8), `dataTextureC` (9)
- `extraBuffer` (10), `comparison_sampler` (11), `plasmaBuffer` (12)

### Uniforms Usage
- `config.x` → time
- `zoom_config.yz` → mouse (normalized, remapped to ±1)
- `zoom_params.x/w` → 4 slider parameters
- `plasmaBuffer[0].xyz` → bass, mids, treble

### Audio Reactivity
- **Bass** drives primary motion intensity, core glow, pluck amplitude
- **Mids** drives secondary modulation, spread, resonance
- **Treble** drives sparkle, seeds, high-frequency detail

### Temporal Feedback
- All 8 shaders read `dataTextureC` via `textureSampleLevel(..., uv, 0.0)`
- Blend: `mix(current, prev * 0.9, 0.025–0.03 + bass * 0.01)`
- Contextually weighted (e.g., `lava-lamp-blobs` uses bass for persistent heat trails)

### Chromatic Dispersion
- Each shader assigns distinct R/G/B channels to visual elements
- Audio bands modulate individual channels (±0.1–0.25)
- Examples:
  - Sacred Geometry: golden R nodes, emerald G ring, sapphire B detail
  - Plasma Jet: red-orange core, yellow-green shock, blue sparks
  - Neural Web: blue nodes, cyan synapses, white signal pulses

### Depth & Alpha
- Semantic alpha derived from `presence = sat(primary * 0.85 + secondary * 0.6)`
- Depth: `0.9–0.95` minus weighted primary/secondary contributions
- All write `writeDepthTexture` with `vec4<f32>(depth, 0, 0, 1)`

---

## Algorithm Highlights

### Sacred Geometry Torus
- Golden ratio φ = 1.61803398875 hardcoded
- Nested loop: 5 phi-offset rotation layers + `phiLayers` count of radial nodes
- Node positions calculated from hash seeds, pulse to bass

### Plasma Jet Stream
- Outer loop over `jetCount` radial jets
- Each jet: direction from polar angle, perp offset for line width
- Turbulence warps perp offset with sinusoidal displacement
- Shock front via `smoothstep` on accumulated intensity

### Holographic Crystal
- 2D crystal lattice via `max(abs(x), abs(y))` facet distance
- Holographic interference: R/G/B phase offsets at 0.0, 2.094, 4.188 radians
- Mouse tilt via 2D rotation matrix on UV
- Moiré interior pattern from crossed sines

### Spore Galaxy
- Logarithmic spiral: `armAngle = a + r * swirl - time`
- Cell-based spore particles via `hash22` grid
- Nebula dust from hash noise with radial falloff

### Neural Synapse Web
- Double loop: nodes + pairwise connections
- Signal travel: `fract(proj/len - time * speed)`
- Early-exit connectivity cull via hash threshold
- Node glow + line glow + traveling signal pulses

### Lava Lamp Blobs
- Metaball function: `blobField` sums Gaussian blobs
- Blob positions animated with `fract` for vertical cycling
- Warm/cool color split: red-orange core vs blue-green halo

### Acoustic String Theory
- String count loop with vertical distribution
- Each string: damped sine wave + traveling pluck pulse
- Harmonics sub-loop with golden ratio offset spacing
- Node glow at interference points

### Magnetic Flux Garden
- 40-step Euler integration per field line from pole A to B
- Field direction: Coulomb-like `1/r²` between poles
- Organic warp via sinusoidal displacement on field vectors
- Curl glow at rotating positions around pole A

---

## JSON Parameters

All 8 JSONs use 4 parameters with sensible defaults (0.35–0.52) mapped to `zoom_params.x/w`.

---

## Validation Status
- Pending: `generate_shader_lists.js` + `check_duplicates.js`

---

## Claude Polish Notes
- `neural-synapse-web` double loop is expensive (O(n²) per pixel with 40 iterations per connection). Consider reducing `nodeCount` max from 16 to 10 if performance is poor.
- `magnetic-flux-garden` uses 40 Euler steps per field line × up to 24 lines = 960 iterations. May need workgroup-size tuning on low-end GPUs.
- `sacred-geometry-torus` nested loop (5 + phiLayers nodes) is bounded and safe.
- Consider adding `dataTextureB` usage for dual-pass effects in future iterations.
