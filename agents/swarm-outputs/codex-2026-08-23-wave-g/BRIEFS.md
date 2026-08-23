# Codex (g) Wave / Smoke / Volumetric Batch

Upgraded ten existing effects in place:

- `wave-equation`: damped height/velocity wave tank with reflective edges.
- `steamy-glass`: condensation, droplets, runoff, wiping, and refraction.
- `steamy-glass-volumetric`: layered steam extinction and droplet scattering.
- `sim-ink-diffusion-rgba`: subtractive CMY pigment diffusion driven by water.
- `sim-smoke-trails-thermal`: buoyant smoke with temperature and velocity.
- `fire-smoke-volumetric-fog`: coupled flame, smoke, soot, and fog volume.
- `aerogel-smoke-hdr`: Rayleigh/Mie-inspired aerogel scatter and HDR halo.
- `heat-haze-volumetric`: persistent heat-column refraction.
- `atmos-fog-volumetric`: height-weighted drifting atmospheric fog.
- `interactive-magnetic-ripple-em`: Maxwell-like electric/magnetic ripple field.

All shaders use the renderer's 13 bindings, 16×16×1 workgroups, exact bounded
`textureLoad` feedback from `dataTextureC`, feedback writes only to
`dataTextureA`, three-band audio, held-pointer interaction, uniform click
ripples, semantic alpha, and ACES output tone mapping.
