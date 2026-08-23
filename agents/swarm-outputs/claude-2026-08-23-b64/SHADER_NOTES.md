# Batch 64 shader notes — 2026-08-23 (tracker #511–520)

## Feedback ownership (which slot carries what)

Display RGBA in `dataTextureA` unless the shader runs a genuine simulation, in
which case A carries state and display goes to `writeTexture`:

| Shader | `dataTextureA` | `dataTextureB` |
|---|---|---|
| `optical-feedback` | display RGBA | (unused) |
| `glass_refraction_alpha` | display RGBA | surface normal + interior path |
| `crystal-facets` | display RGBA | facet normal + TIR |
| `ambient-liquid` | **state** `[U, V, ink, luma]` | display RGBA + V |
| `frosted-glass-lens` | display RGBA | (unused) |
| `cyber-lens` | display RGBA | HUD masks |
| `bubble-lens` | display RGBA | bubble masks |
| `liquid-metal` | **state** `[height, supercritical, F, alpha]` | display RGBA + spec |
| `magnetic-interference` | display RGBA | (unused) |
| `digital-mold` | **state** `[U, V, hyphae, density]` | (unused) |

Three shaders (`ambient-liquid`, `liquid-metal`, `digital-mold`) run real
simulations whose state must survive in A; overwriting it with colour would
destroy the sim. This is the Batch 58B convention.

## extraBuffer occupancy (all inside [133..138])

| Shader | Slots |
|---|---|
| `optical-feedback` | 133–134 smoothed pointer, 135 hue phase |
| `magnetic-interference` | 133–134 previous pointer, 135 audio envelope |
| `bubble-lens` | 133–136 spring pos/vel, 137 last time, 138 init flag |

No other shader in the cohort writes `extraBuffer` at all.

## Retired baseline violations

`reports/extrabuffer_write_audit_baseline.json` drops from 46 to 44 entries;
repo-wide known violations fall 128 → 117. The retired entries are
`optical-feedback` (9 slots, `[0..8]`) and `magnetic-interference` (2 slots,
`[0..1]`).

## Per-shader structures

- **`optical-feedback`** — multi-front ripple shockwaves (every live ripple is
  its own expanding front, so overlapping clicks build interference); per-band
  spectral hue rotation (each FFT bin rotates its own radial zone).
- **`glass_refraction_alpha`** — Cauchy dispersion `n(λ)=A+B/λ²`; per-band
  caustic focusing from the convergence of the refracted direction field.
- **`crystal-facets`** — facet-normal Fresnel with total internal reflection
  past `asin(1/n)`; uniaxial birefringence along a per-facet optic axis.
- **`ambient-liquid`** — real Gray-Scott with a five-tap Laplacian and per-band
  feed/kill; V concentration raises surface tension and pulls the metaball
  isosurface inward.
- **`frosted-glass-lens`** — Beckmann microfacet scattering lobe (5 taps from
  the slope distribution); depth-dependent frost thickness.
- **`cyber-lens`** — rolling-shutter scan skew (per-row exposure time);
  per-band telemetry rings around the reticle.
- **`bubble-lens`** — Marangoni convection from surface-tension gradients;
  per-band membrane resonance (drum) modes.
- **`liquid-metal`** — Rosensweig hexagonal spike instability above the
  critical field; anisotropic Ward BRDF stretched perpendicular to flow.
- **`magnetic-interference`** — per-band domain-wall spectrum with defect
  pinning; hysteresis memory with a coercivity switching gate.
- **`digital-mold`** — nutrient-gradient chemotaxis up image luminance;
  per-band sporulation regimes across the Gray-Scott parameter plane.

## Validation

Structural only in this container. Real-GPU visual QA remains external.
