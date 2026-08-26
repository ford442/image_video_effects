# Shader Notes

| Shader | A/C state packing | Alpha meaning |
|---|---|---|
| wave-equation | height, velocity, foam, phase | wave/foam coverage |
| steamy-glass | steam, droplets, runoff, wipe memory | condensed optical coverage |
| steamy-glass-volumetric | steam, optical depth, droplets, flow | volumetric opacity |
| sim-ink-diffusion-rgba | C, M, Y pigment, water | pigment/water coverage |
| sim-smoke-trails-thermal | density, temperature, velocity xy | smoke extinction |
| fire-smoke-volumetric-fog | density, temperature, soot, momentum | volume extinction |
| aerogel-smoke-hdr | density, scatter energy, velocity xy | aerogel/rim coverage |
| heat-haze-volumetric | velocity xy, heat, column density | thermal-column coverage |
| atmos-fog-volumetric | density, drift xy, moisture | fog extinction |
| interactive-magnetic-ripple-em | electric xy, magnetic field, energy | field/filings coverage |

The magnetic shader no longer stores previous pointer data in one texture
pixel; every texel now advances the same local field equations. Click events
come from `u.ripples`, so no shader-owned `extraBuffer` state is required.
