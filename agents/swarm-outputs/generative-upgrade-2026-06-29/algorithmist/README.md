# Algorithmist Upgrade — `gen-torus-knot-rainbow`

## Changelog

### Geometry: from brute-force point glow to analytic SDF
- Replaced the 300-sample point-accumulation loop with a **smooth-union of 3D→2D projected capsule segments** (128 segments).
- Each segment contributes a true tube SDF (`sdSegment - radius`) and the whole knot is fused with `smin`, giving a continuous, anti-aliased tube instead of a cloud of sparks.
- Tube radius is **harmonically modulated** along the knot (`sin(t*5 - time*0.4)`) and reacts to bass, preserving the original "breathing rainbow" feel.

### Fractal upgrade: multi-orbit Julia trap
- Added a **32-iteration complex Julia orbit trap** with three trap points in the halo field around the knot.
- The trap output warps the hue/saturation of the knot and tints the halo with a psychedelic palette, giving iridescent, ever-changing edges.

### Noise upgrade: FBM domain warping
- Integrated canonical `domainWarp` + `fbm` for organic modulation of the tube environment and the background nebula field.
- Background is a domain-warped FBM colored with `psychedelicPalette`, softly masked by the knot's SDF so the tube stays readable.

### Audio reactivity
- Bass still drives the `q` winding wind modulation (the shader's signature audio behavior).
- Mids push saturation and halo glow; treble tightens glow falloff and adds high-frequency shimmer.

### Image quality
- ACES tone mapping.
- Generative chromatic shift driven by angle + bass + input depth.
- Temporal feedback via `dataTextureC`/`dataTextureA` with decay controlled by `p4`.
- Semantic alpha: intensity/depth-based, never hardcoded 1.0.

## Performance Estimate

- **Loop budget per pixel**: 128 segment iterations + 32 Julia iterations + 4-octave background FBM with domain warp ≈ **~170 primary loop steps**, plus cheap closed-form math inside each loop.
- Expected **60 fps at 1080p on a mid-tier GPU** (GTX 1060 / RX 580 class). The capsule SDF is O(N) and branchless; the Julia trap is the next most expensive block and stays under 35 iterations.
- Peak cost is roughly **2× lower** than the original 300-step brute-force loop while producing a cleaner, higher-contrast image.

## Dependencies on Canonical Patterns

- Uses the exact **13-binding generative header** from `agents/WGSL_BUILTINS_GENERATIVE.md` §0.
- Reuses canonical `hashf`, `hash21`, `valueNoise`, `fbm`, `domainWarp`, `acesToneMap`, `hsv2rgb`, `psychedelicPalette`, `luma`, `rot2`, `rotX`, `rotY`, `smin`, `sdSegment`.
- Compute-safe only: `textureLoad`, `textureSampleLevel`, `textureStore`; no `tan`, `textureSample`, `dpdx`, `dpdy`.
- Entry point: `@compute @workgroup_size(16, 16, 1)`.
