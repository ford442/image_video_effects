# plan-mouse.md

This document lists shaders that currently do not react to mouse input (no `u.ripples` or `mouse`/`zoom_config`-based interactions detected). For each shader, a short suggestion for adding a mouse/reactive behaviour is provided.

Criteria used for detection:
- Shader references `u.ripples` or uses `u.zoom_config` fields in a mouse-like way are considered mouse-reactive.
- All other shaders are treated as non‑reactive and included below.

Files identified (public/shaders):

- `ambient-liquid.wgsl` — Suggestion: Use `u.zoom_config.yz` as a soft attractor center for ambient flow or add `u.ripples` to spawn eddies.
- `ascii-glyph.wgsl` — Suggestion: Use `u.zoom_config.yz` to displace glyph positions or `u.ripples` to morph glyph SDF on click.
- `bitonic-sort.wgsl` — Suggestion: Use mouse to pick sort region: read `u.zoom_config.yz` for center and only run local bitonic sort there or add a ripple-triggered sort threshold.
- `boids.wgsl` — Suggestion: Add `u.ripples` as attractor seeds or modify boid `attraction` by `u.zoom_config` position to reveal textures near the pointer.
- `datamosh.wgsl` — Suggestion: Apply mouse-influenced search offsets (from `u.zoom_config`) on optical flow or trigger local smear accumulation on ripple events.
- `galaxy.wgsl` — Suggestion: Use `u.zoom_config.yz` to move galaxy center/background rotation or `u.ripples` to spawn local starbursts.
- `julia-warp.wgsl` — Suggestion: Map `u.zoom_config.yz` to Julia constant `c` or use `u.ripples` to spawn localized orbit-trap highlights.
- `lenia.wgsl` — Suggestion: Inject seeds at mouse position from `u.zoom_config.yz` or spawn/remap parameters with `u.ripples` for local growth.
- `melting-oil.wgsl` — Suggestion: Add `u.ripples` to stir the flow with local momentum or read `u.zoom_config` for drag center and intensity.
- `navier-stokes-dye.wgsl` — Suggestion: Use `u.ripples` to inject dye and energy at click locations or set `zoom_config` center as a continuous inflow source.
- `neon-edge-diffusion.wgsl` — Suggestion: Use `u.zoom_config` as local diffusion amplifier or `u.ripples` to create neon pulses at click positions.
- `physarum.wgsl` — Suggestion: Spawn agents (or bias their species/angle) using `u.ripples` and use `u.zoom_config` for attractor/repellent centers.
- `pixel-sand.wgsl` — Suggestion: Spawn grains at mouse position (via `u.ripples`) or add a `zoom_config` gravity well to pull grains.
- `prismatic-mosaic.wgsl` — Suggestion: Use `u.zoom_config` for mosaic center, scale, or to locally jitter cells; `u.ripples` can trigger rearrangements.
- `reaction-diffusion.wgsl` — Suggestion: Inject A/B chemicals at `u.zoom_config` or spawn seeds via `u.ripples` to locally perturb patterns.
- `spectrogram-displace.wgsl` — Suggestion: Use `u.zoom_config` to focus bands near the pointer or `u.ripples` to create local audio-reactive smears.
- `temporal-echo.wgsl` — Suggestion: Add mouse-controlled history offset parameter (via `u.zoom_config`) or allow `u.ripples` to pin frames into history.
- `texture.wgsl` — Suggestion: Use `u.zoom_config` to pan/zoom the image with pointer, or `u.ripples` to cause local displacement or reveal overlays.
- `voronoi.wgsl` — Suggestion: Use `u.zoom_config` to seed feature points or `u.ripples` to add dynamic feature centers and animate cells locally.

Notes & Next Steps:
- These suggestions are intentionally minimal; because the renderer’s bind group is immutable, additions should reuse the existing `u` Uniforms and `ripples` array rather than changing the pipeline layout.
- For maximal compatibility, prefer `u.ripples` (click-based) or `u.zoom_config.yz` (pointer position) for mouse interactions.
- If you want, I can implement the mouse additions for a subset of these shaders (one or two), or add a template snippet and small UI param to `Controls.tsx` to expose the new behaviors.

If you want me to implement the mouse reaction for specific shaders, tell me which ones to prioritize and how you want the pointer to influence them (e.g., ripple strength, spawn agents, reveal masks, etc.).

End of list
