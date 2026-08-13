# Batch 48 briefs — 2026-08-13 (tracker #415–422) — FAST MOTION CONTINUATION

Batch 48 takes the next smallest clean single-pass cohort and adds two distinct
continuous motion structures, held-pointer response, and capped click fronts
while preserving saved presets and feedback ownership.

| # | Shader | Lines | Upgrade focus |
|---|--------|-------|---------------|
| 415 | `ferrofluid` | 125→142 | Magnetic domains, droplet runners, live viscosity |
| 416 | `interactive-glitch` | 125→132 | Stable block pulses, scan tears, 16x16x1 |
| 417 | `chroma-lens` | 126→146 | Tangential edge blur, rim runners, glass fronts |
| 418 | `heat-haze` | 126→144 | Exact rising heat, convection packets, true decay |
| 419 | `predator-camouflage` | 126→143 | Pigment runners, hunt sweeps, held cloak |
| 420 | `scanline-cyberpunk` | 126→149 | Real audio, head rolls, phosphor runners |
| 421 | `spectral-slit-scan` | 126→152 | Live slit count, exact history, spectral packets |
| 422 | `watercolor-bloom` | 126→151 | Advected pigment, runners, truthful drying |

## Shared contract

- Canonical bindings, 16x16x1 workgroups, invocation guards, real audio, pointer position/down, and clicks capped at 50.
- Every source `params` entry is byte-exact and mirrored by an indexed `updatedParams` entry.
- A remains Ferrofluid diagnostics, display output for the other seven, and Heat Haze keeps scalar heat in depth. Scanline keeps its diagnostic B packing, Watercolor keeps mirrored display B, and the other six leave B unused.
- Spectral and Watercolor use exact bounded C display history; Heat Haze uses exact bounded depth-state loads.
- Motion uses continuous domains, runners, packets, sweeps, advection, or oscillation rather than frame-varying hashes.
- No shader accesses reserved `extraBuffer`; stylized ferrofluid, heat, and camouflage wording avoids physical or diagnostic claims.
- Cloud-VM proof is structural; visual and performance acceptance require a discrete GPU.
