# Reaction / Flow / Sand / Optical-Fluid cohort briefs — 2026-08-23

The user selected ten simulation IDs and required the canonical bindings 0–12,
ACES display mapping, semantic alpha, exact `textureLoad` feedback from C,
A-only writeback, live bass/mids/treble, bounded interaction state, preserved
pointer/held/click response, byte-exact saved params, and Naga-clean WGSL.

| Shader | Upgrade identity | A/C packing |
|---|---|---|
| `alpha-reaction-diffusion-rgba` | Ecological four-species Gray-Scott colonies | warm U/V, cool U/V |
| `chromatic-reaction-diffusion-rgba` | Spectrally phase-coupled warm/cool Turing fields | warm U/V, cool U/V |
| `rd-on-video-pass1` | Video-luma-fed chemistry with interactive inoculation | U, V, luma memory, activity |
| `luma-flow-field` | Iso-luminance advection plus curl ribbons | HDR trail RGB, coverage |
| `optical-flow-dream` | Single-pass temporal-luma dream advection | HDR dream RGB, coverage |
| `sim-sand-dunes` | Height-field saltation, avalanching, erosion | height, loose grains, velocity, moisture |
| `sim-sand-dunes-rgba` | Four-population grain transport | fine, coarse, moist, dust |
| `pixel-sand` | Density/velocity granular automaton | density, velocity XY, kinetic energy |
| `cymatic-sand` | Damped Chladni plate grain transport | density, velocity, resonance, strike memory |
| `photonic-caustics` | Refractive convergence accumulator | HDR irradiance RGB, coverage |

`optical-flow-dream` deliberately moved off its four-pass binding-13 graph so
the named effect satisfies the requested core 13-binding contract. The saved
four controls and public ID remain stable. `rd-on-video-pass1` remains the
first stage of its existing three-pass chain, but its own state/display path now
obeys the cohort contract.
