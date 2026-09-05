# Batch 60 briefs — 2026-08-23 (tracker #521–530)

HEAT / ECHO / ELASTIC / ELECTRIC / EMBER / ENERGY cohort.
`edge-glow-mouse` is a deliberate second polish pass after Batch 59.

Each keeps source `params` exact (ids/names/defaults/ranges), canonical 13
bindings, 16×16×1 workgroups, unused B, and no new illegal extraBuffer writes.
Click loops are `min(u32(u.config.y), 50u)`. Springs only in `[133..138]`
(or documented extension) written from pixel `(0,0)`.

| # | Shader | Upgrade focus |
|---|--------|---------------|
| 521 | `heat-haze` | Hotter convection columns, Schlieren CA, held nozzle, FFT band shimmer, ACES |
| 522 | `heat-haze-mirage` | Stronger inversion fold, caustic runners, held press, keep spring [133..] |
| 523 | `echo-ripple` | Cap ripples at 50, richer thin-film harmonics, held gravity bowl |
| 524 | `echo-trace` | **Move Kalman state off FFT slots → [133..141]**; exact C loads; held brush; ACES |
| 525 | `edge-glow-mouse` | Second polish: oil-slick neon, anisotropic bloom packets, click rings |
| 526 | `elastic-strip` | Sharper bevel ribs, traveling pluck packets, soap-film iridescence |
| 527 | `elastic-surface` | **textureLoad C** for RG/BA state; caustic lighting; audio; held punch |
| 528 | `electric-contours` | Held charge, capped click sparks, corona bloom, FFT band arcs |
| 529 | `ember-drift-dissolve` | **textureLoad C** advection; held furnace; click ember bursts; ACES |
| 530 | `energy-shield` | Cap ripples; exact C trail; held hex tighten; audio; ACES; oil-slick hex |

## Shared contract

- Preserve source `params` ids/names/defaults/ranges; add/align `updatedParams`.
- `plasmaBuffer[0].xyz` audio; optional bins 1–8 for local shimmer.
- Held-pointer via `u.zoom_config.w > 0.5`.
- Exact `textureLoad` for `dataTextureC` and depth (no filtered history/state).
- Semantic (unpremultiplied) alpha; ACES on display path only when A stores state.
- Document A packing in header comments.
- Structural validation local; visual QA needs a real GPU.
- Distinct look per shader — do not clone the same neon-cyan recipe onto everything.
