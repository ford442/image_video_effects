# Generative-only cohort briefs — 2026-08-23

The selected ten shaders keep distinct procedural identities while sharing the
canonical bindings 0–12, exact C feedback, A-only writeback, ACES display
mapping, semantic alpha, three-band audio, and four named controls.

| Shader | Upgrade identity | Persistent A/C state |
|---|---|---|
| `gen-chronos-labyrinth` | Rotating chronometer sigils over chronal masonry and rifts | rift echo, depth, material, alpha |
| `gen-chronos-monolith-resonator` | Click-driven resonance harmonics around a dark-matter obelisk | display history RGBA |
| `gen-conway-game-of-life` | Morphing Life/Day-and-Night/HighLife neon automaton | alive, generation, activity, alpha |
| `gen-coral-reef-colony` | Click-seeded colony fronts with held nutrient attraction | display history RGBA |
| `gen-cosmic-clockwork-dyson-sphere` | Mechanical tick shocks and plasma megastructure history | display history RGBA |
| `gen-cosmic-slime-mold` | Correctly normalized feeding and persistent nutrient waves | HDR trail RGB, alpha |
| `gen-cosmic-velvet-hypnosis` | Fine velvet weave layered into counter-spiral moire | display history RGBA |
| `gen-cosmic-web-filament` | Pulsing quasar nodes at filament junctions | display history RGBA |
| `gen-cryogenic-frost-plasma-matrix` | Fracture shocks, thermal plasma, and bounded bass envelope | HDR history RGB, alpha |
| `gen-crystal-caverns` | Purity-controlled transmission, click refraction, held camera | display history RGBA |

The Conway compile failure was a declaration-order defect: `activity` was used
before it was defined. Cryogenic Frost Plasma Matrix now writes its feedback to
A and stores its only scalar envelope at `extraBuffer[133]`, never slot 0.
Dyson Sphere's four labels now match the live WGSL meanings: Mechanical
Complexity, Clock Speed, Plasma Intensity, and Gear Ratio.
