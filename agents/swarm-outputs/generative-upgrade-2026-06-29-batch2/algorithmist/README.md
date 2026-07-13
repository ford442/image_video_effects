# Algorithmist upgrade: `gen-newton-fractal`

## Changelog

- **Fractal core preserved:** still solves `z^n - 1` with Newton's method and colors by convergent root.
- **FBM domain warping** added to the initial complex coordinate, distorting basin boundaries organically.
- **Time-varying complex perturbation** in the Newton numerator keeps the basin geometry evolving without breaking the analytic derivative.
- **Smooth iteration count** replaces raw step count for band-free boundary shading.
- **Multi-shape orbit traps** (unit circle, axes, diagonal, logarithmic spiral) drive iridescent glow.
- **Multi-root color accumulation** blends root colors near basin boundaries instead of hard nearest-root selection.
- **SDF smooth-union halo** around roots adds a geometric glow layer via `smin`.
- **Reaction-diffusion accent** on boundaries using `dataTextureC` state and a 4-neighbor Laplacian.
- **Audio reactivity:** bass nudges degree, treble boosts trap shimmer, mids add warp.
- **ACES tone mapping + generative chromatic aberration** finish the image.

## Techniques used

| Toolkit area | Technique |
|--------------|-----------|
| Fractal upgrades | Orbit traps, smooth iteration count, perturbation/hybrid polynomial |
| Noise upgrades | FBM domain warping for organic boundary distortion |
| SDF upgrades | Smooth union (`smin`) root halo geometry |
| Simulation upgrades | Reaction-diffusion boundary accent via `dataTextureC` feedback |

## Performance estimate

- Loop budget: outer Newton loop up to **84 iterations**, plus two fixed-size root loops of **6 iterations** each and a small FBM (3 octaves). Total well under **200 iterations/pixel**.
- Expected **60 fps @ 1080p** on mid-tier GPUs; heavy work is per-pixel complex arithmetic and a handful of texture samples.
- Memory traffic: one `textureLoad` + four neighbor `textureLoad`s for reaction-diffusion, plus one `textureSampleLevel` feedback sample.

## Dependencies

- Canonical 13-binding generative header from `agents/WGSL_BUILTINS_GENERATIVE.md` §0.
- Compute-safe builtins only (`textureSampleLevel`, `textureLoad`, `textureStore`); no `tan`, `textureSample`, `dpdx`, or `dpdy`.
