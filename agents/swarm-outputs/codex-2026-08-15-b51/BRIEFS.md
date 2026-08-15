# Batch 51 briefs — 2026-08-15 (tracker #439–446) — LIQUID DYNAMICS, GEOMETRY & VISCOUS FLOW

Batch 51 upgrades the compact Liquid Effects cohort with rich fluid kinematics,
divergence-free Hamiltonian streamfunctions, 2.5D surface height-field normal derivatives,
viscoelastic Kelvin-Voigt elasticity, Cauchy & thin-film chromatic dispersion,
Snell's law refraction, multi-scale vorticity confinement, and exact `textureLoad`
float32 temporal history accumulation.

| # | Shader | Lines | Upgrade focus |
|---|--------|-------|---------------|
| 439 | `liquid-fast` | 64→145 (+81) | Divergence-free Hamiltonian streamfunctions, drag vortex wake, 2.5D heightfield normals, exact C load |
| 440 | `liquid-rgb` | 66→143 (+77) | Complex potential vortex superposition, Cauchy chromatic dispersion, Beer-Lambert absorption, exact C load |
| 441 | `liquid-jelly` | 67→145 (+78) | Kelvin-Voigt viscoelastic model, spring-mass drag tether, volumetric scattering, exact C load |
| 442 | `liquid-rainbow` | 71→148 (+77) | Trochoidal Gerstner waves, thin-film optical interference, chromatic dispersion, exact C load |
| 443 | `liquid-perspective` | 76→144 (+68) | 3D perspective rays, Snell refraction, edge silhouette bioluminescence, exact C load |
| 444 | `liquid-glitch` | 76→142 (+66) | Voronoi cellular quantization, fluid stream advection, Bernoulli slip bands, exact C load |
| 445 | `liquid-viscous-grokcf1` | 84→143 (+59) | Multi-octave FBM domain warping, helical flow, nebula filaments, exact C load |
| 446 | `liquid-viscous-simple` | 106→148 (+42) | Laplace cohesion operator, vorticity confinement flow, Fresnel sheen, exact C load |

## Shared contract

- Canonical bindings layout, 16x16x1 compute workgroup size, invocation bounds guards, real three-band audio (`plasmaBuffer[0].xyz`), pointer position/down response, clicks capped at 50 ripples.
- Every source `params` entry remains byte-exact and is mirrored by indexed `updatedParams`.
- Exact float32 state accumulation via `textureLoad(dataTextureC, ...)`, bypassing WebGPU float32-filtering hardware limitations.
- Preserves writeTexture and dataTextureA presentation/history roles; dataTextureB remains unused; zero persistent `extraBuffer` writes.
- Real-GPU visual acceptance remains external.
