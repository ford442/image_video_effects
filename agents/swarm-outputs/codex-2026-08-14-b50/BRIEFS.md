# Batch 50 briefs — 2026-08-14 (tracker #431–438) — GEOMETRY & DETAIL ENRICHMENT

Batch 50 upgrades the geometry-forward cohort with enriched shapes, structural
detail, facet geometry, and fine-grained patterns while preserving saved presets,
buffer ownership, and the established interaction contract.

| # | Shader | Lines | Upgrade focus |
|---|--------|-------|---------------|
| 431 | `neon-contour-drag` | 126→~145 | Dual-scale contours, held warp, edge runners |
| 432 | `voronoi-glass` | 127→~150 | Second-closest grout, facet glints, shatter fronts |
| 433 | `spec-blue-noise-stipple` | 127→~155 | Golden tertiary dots, ink splatter, treble crawl |
| 434 | `fractal-glass-distort` | 128→~150 | Attractor runners, held pinch, shock rings |
| 435 | `navier-stokes-dye` | 127→~155 | Filament streaks, vortex ribbons, dye bursts |
| 436 | `chrono-luma-slit-scan` | 127→~145 | Slit bands, scan runners, held temporal halo |
| 437 | `spec-blackbody-thermal` | 127→~155 | Isotherm rings, ember filaments, heat fronts |
| 438 | `adaptive-mosaic` | 128→~150 | Exact C load, grout conveyors, tile fronts |

## Shared contract

- Canonical bindings (binding 13 only on chrono-luma-slit-scan), 16x16x1 workgroups, bounds guards, real three-band audio, pointer position/down, clicks capped at 50.
- Every source `params` entry remains byte-exact and is mirrored by indexed `updatedParams`.
- Preserve each shader's established A/B/C roles; chrono retains `extraBuffer[4]` history head.
- Motion uses continuous runners, packets, or conveyors — not frame-varying hashes.
- Cloud-VM proof is structural; visual acceptance requires a discrete GPU.
