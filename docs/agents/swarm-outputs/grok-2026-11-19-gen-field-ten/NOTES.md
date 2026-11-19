# Notes — generative field ten (2026-11-19)

Second idea pass. Each file already had an upgrade. Saved `params` were not edited. `gen-topology-flow` and `lorenz-attractor-flow` were migrated to `#include "_prelude.wgsl"` (infrastructure; the idea edits are what bump `Upgraded:`).

| Shader | Kept | A packing | Ideas in the diff | Formula |
|---|---|---|---|---|
| `gen-plasma-psychedelic-wormhole` | 1/r tunnel, photon subrings, point-mass deflection, frame-drag, KH billows, inverse-ACES trail | ACES display RGBA | chromatic Einstein ring; throat plunge curtain | Cauchy §12.2F |
| `gen-lichtenberg-storm` | `licht()`, return-stroke head, corona from C.g, etch, spring electrode, shock ring | raw sim (energy, charge, ring, 1) | stepped-leader gaps; bead lightning | — |
| `gen-galactic-aether-crystal-geode-core` | map materials, KIFS, agate, amethyst zoning, druse, gas swirl | ACES display RGBA | weathering rind; fluid inclusions; march-step occlusion | march step count (not 5-tap AO) |
| `gen-bifurcation-diagram` | one logistic loop, palettes, period-3, superstable, cobweb ticks, pointer lens | HDR density; ACES on write | Feigenbaum hairlines; invariant-density cusps; fixed-point tick | — |
| `gen-thermal-rainbow-topography` | terrainHeight, diffusion, contours, fault, caldera, channels, saddle eddies | A.rgb display history, A.a height | slope-aspect sun; fumarole vents | — |
| `gen-astral-plasma-accretion-forge` | Keplerian torus, dust lanes, redshift g, Rossby, reconnection, horizon | ACES display RGBA | orbital Doppler beaming; Schwarzschild photon ring | — |
| `lorenz-attractor-flow` | Euler Lorenz, FTLE twin, hop bands, upstream C, SDF tube | ACES display RGBA | Poincaré knots at z=27; equilibrium eyes | — |
| `gen-topology-flow` | height field, particle advection, Morse index, whiskers, relief | HDR history; ACES on write | persistence; source/sink tint; critical level set | — |
| `gen-metaball-soft-body` | Rayleigh modes, neck beading, meniscus, nephroid | ACES display RGBA | satellite droplet; Fresnel–Schlick; Young–Laplace darkening | Fresnel–Schlick §12.2F |
| `gen-sentient-liquid-neon-fractal-heart` | fractal heart, lub-dub, systolic wave, oxygenation, Purkinje, diastolic refill | bounded HDR history; ACES on write | pericardial sac; valve snap; refractory dip | — |

No §12.2 row is shared. Cauchy is the wormhole only. Fresnel–Schlick is the metaball only.

JSON: `upgraded-rgba` added on `gen-thermal-rainbow-topography` and `gen-topology-flow`. No param ids, names, defaults, or ranges changed.

Real-GPU visual QA: external. This VM has no hardware GPU.
