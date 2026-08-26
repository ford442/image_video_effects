# Batch 53 briefs — 2026-08-21 (tracker #455–462) — FAST MOTION ENCORE

Batch 53 upgrades the next eight clean single-pass effects with two
shader-specific continuous-motion structures, held-pointer deformation, and
click fronts capped by the live ripple count and a 50-event maximum.

| # | Shader | Upgrade focus |
|---|--------|---------------|
| 455 | `pixel-sand` | Avalanche sheets, rising jets, held gravity, click shelves |
| 456 | `crt-magnet` | Degauss rings, rolling beam sweeps, held field gain, click shocks |
| 457 | `scan-distort-gpt52` | Smooth scan tears, diagonal conveyor, held band pull, click shocks |
| 458 | `digital-lens` | Caustic zoom streaks, spectral runners, held lens, iris waves |
| 459 | `chromatic-mosaic-projector` | Mosaic conveyors, tile runners, held gravity, chromatic blasts |
| 460 | `chrono-slit-scan` | Traveling slit heads, cross-runners, held slit bend, scan fronts |
| 461 | `mosaic-reveal` | Tile conveyors, flood runners, held expansion, reveal fronts |
| 462 | `quad-mirror` | Mirrored ribbons, seam runners, held twist, fold shells |

## Shared contract

- Preserve source `params` byte-for-byte and add aligned `updatedParams`.
- Preserve canonical 13 bindings, 16x16x1 workgroups, depth ownership,
  `plasmaBuffer[0].xyz` audio, and each established A/B/C role.
- Replace time-quantized/hash animation with smooth analytic motion.
- No renderer, graph, toolchain, dependency, or public TypeScript API changes.
- Structural validation is local; visual acceptance requires a real GPU.
