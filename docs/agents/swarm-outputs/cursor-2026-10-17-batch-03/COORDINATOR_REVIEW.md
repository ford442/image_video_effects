# Coordinator review — cursor batch-03

2026-10-17. Cards in `BRIEFS.md` were written before the WGSL. Each numbered idea is named in the shader.

| Shader | Verdict | Why |
|---|---|---|
| rd-on-video-pass1 | pass | Contour stretch and spot fission sit on the Gray-Scott update. Feed/kill/diffusion/dt and raw A packing kept. |
| rd-on-video-pass2 | pass | Isochrone threads and substrate core sit on the existing palette. B stays pre-ACES color + pattern. No A write. |
| rd-on-video-pass3 | pass | Dye take-up and the gate meniscus sit on the luma composite. No A write. C load is exact. |
| liquid-optimized-pass1 | pass | Seiche and shore set-down sit on the wave solver. Height packing kept. Not the crest-lean from liquid-pass1. |
| liquid-optimized-pass2 | pass | Snell offset and velocity glint sit on the Fresnel/Beer shade. No A write. Not the fold caustics from liquid-pass2. |
| gen-tectonic-plasma-crucible | pass | Pillow rind and strike-slip striae sit on the crust shade. Crack ramp and isostatic bob kept. |
| gen-luminescent-chrono-fluid-astrolabe | pass | Unequal-hour arcs and the alidade shadow sit on the rete. Prior plate, gears, and rule kept. |
| gen-navier-stokes-ink | pass | Marangoni force and coffee-ring rim sit on the ink solver and its display. Raw velocity packing kept. |
| gen-magnetic-ferrofluid | pass | Peak bifurcation and magnetite chains sit on the existing lattice. Rosensweig, labyrinth, Rayleigh, softbox kept. |
| gen-auroral-ferrofluid-monolith | pass | Stable red arc and black-aurora lanes sit on the volume march. Sheath, cusp knots, and substorm curtains kept. |

Checklist: cards exist; ideas are pointable; kernels and slider roles kept; no shared spring/ripple/IQ stamp; A packing matches how C is read; saved params unchanged; Naga, precommit, extraBuffer, and dead sliders green on this batch.

Real-GPU visual QA: external.
