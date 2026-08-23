# Batch 57 briefs — 2026-08-23 (tracker #483–490) — KINETIC IMAGE TRANSFORMATIONS

Batch 57 upgrades eight clean single-pass effects with recognizable geometry,
continuous motion, psychedelic spectral color, held-pointer deformation, and
click events capped by the live ripple count and 50.

| # | Shader | Upgrade focus |
|---|--------|---------------|
| 483 | `pixel-sort-radial` | Luma-gated radial runners, held stretch, spectral click fronts |
| 484 | `mirror-drag` | Exact history, traveling shard facets, held drag, shatter fronts |
| 485 | `psychedelic-noise-flow` | RGB current filaments, held vortices, spectral flow fronts |
| 486 | `neon-flashlight` | Depth-edge cone ribs, radial sweeps, held squeeze, click flashes |
| 487 | `ascii-flow` | Live four-control glyph current, held vortices, phosphor fronts |
| 488 | `temporal-distortion-field` | Exact history, depth-weighted freeze, clock rings, click fronts |
| 489 | `pixel-drag-smear` | Exact wet-paint history, live comb modes, pigment fronts |
| 490 | `fractal-kaleidoscope` | Live intensity/speed/scale/detail, facet zoom, held twist |

## Shared contract

- Preserve source `params` exactly and add aligned `updatedParams`.
- Preserve the canonical 13 bindings, 16x16x1 workgroups, input depth
  ownership, and `plasmaBuffer[0].xyz` audio.
- Keep B unused and introduce no `extraBuffer` access.
- A remains display RGBA for Pixel Sort, Mirror Drag, Noise Flow, Temporal
  Distortion, and Pixel Drag. Neon retains display RGBA A. ASCII Flow and
  Fractal Kaleidoscope continue without A writes.
- No renderer, graph, TypeScript API, dependency, or bind-group changes.
