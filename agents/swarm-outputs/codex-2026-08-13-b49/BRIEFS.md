# Batch 49 briefs — 2026-08-13 (tracker #423–430) — FAST MOTION CONTINUATION

Batch 49 takes the next smallest clean single-pass cohort and adds two distinct
continuous motion structures, held-pointer response, real three-band audio,
and capped click fronts while preserving saved presets and buffer ownership.

| # | Shader | Lines | Upgrade focus |
|---|--------|-------|---------------|
| 423 | `black-hole` | 127→139 | Orbit runners, infall packets, held lensing |
| 424 | `chroma-depth-tunnel-prismatic` | 127→146 | Axial packets, spectral helix, pointer pull |
| 425 | `glass-shatter` | 127→145 | Shard runners, edge glints, held repel |
| 426 | `interactive-glitch-cubes` | 127→144 | Exact history, cube sweeps, stable sparkle |
| 427 | `kintsugi-repair` | 127→144 | Repair runners, gold traces, held energy |
| 428 | `luma-melt-interactive` | 127→144 | Exact downward history, melt and drip packets |
| 429 | `pp-ssao` | 127→148 | Rotating kernels, depth scans, pointer focus |
| 430 | `rgb-shift-brush` | 127→142 | Exact mask advection, spectral ribbons |

## Shared contract

- Canonical bindings, 16x16x1 workgroups, invocation guards, real audio, pointer position/down, and clicks capped at 50.
- Every source `params` entry remains byte-exact and is mirrored by an indexed `updatedParams` entry.
- A keeps each shader's established display, diagnostic, or state packing; B remains unused; established generated or pass-through depth roles remain unchanged.
- Interactive Glitch Cubes, Luma Melt, and RGB Shift Brush use exact bounded C history loads.
- Motion uses continuous runners, packets, conveyors, kernels, or advection rather than frame-varying hashes.
- No shader accesses reserved `extraBuffer`; prism, glass, kintsugi, and occlusion descriptions remain explicitly stylized.
- Cloud-VM proof is structural; visual and performance acceptance require a discrete GPU.
