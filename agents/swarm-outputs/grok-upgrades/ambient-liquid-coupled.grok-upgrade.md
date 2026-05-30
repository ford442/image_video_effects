# Grok Upgrade — ambient-liquid-coupled

**Date**: 2026-05-31  
**Upgraded by**: Grok (creative direction + direct implementation)

---

## Original Creative Diagnosis

The shader already had a nice fluid velocity field + ambient wave displacement + mouse + ripple interaction. It was pleasant and technically solid, but emotionally it felt like "two systems loosely glued together" rather than a single living surface. The coupling was mechanical, not visceral.

The latent potential was obvious: **what if the coupling itself was the main character?** A membrane you could actually press into with your finger (mouse), that would tear, show its subsurface, and slowly heal — with music literally controlling how tight or loose the skin feels.

---

## Upgrade Direction Chosen

**"Living Membrane"** — Mouse down = finger pressing into a viscous surface. High pressure creates visible layer separation (you are seeing through the tear into a slightly different subsurface). Bass = surface tension. High bass makes the membrane much more resistant to healing, so dramatic deformations persist and feel "set" into the material.

Key new behaviors introduced:
- Real-time membrane pressure field (stored in dataTextureB)
- Bass-modulated surface tension using a proper attack/release envelope (`bass_env`)
- Visible layer separation that scales with pressure + bass
- Mouse press strength directly modulates resistance and tear depth
- Much richer alpha that represents membrane thickness (high pressure = more translucent "wound")
- Premultiplied write for clean slot chaining

---

## The Moment It Sings

1. Load a detailed image or video.
2. Hold the mouse down and slowly drag — watch the surface stretch and tear like thick skin or a thin layer of oil on water.
3. Play music with strong bass. The tears you just made will suddenly "set" and heal much more slowly.
4. Tap the mouse in rhythm with the beat — you are literally drumming on the surface of a living material.
5. Watch in slot 2 or 3 — the alpha now plays beautifully with whatever is underneath.

---

## Technical Notes for Claude (future optimization pass)

This shader now has two interacting state fields (velocity in dataTextureA, pressure in dataTextureB). It is a good candidate for:
- Workgroup tiling on the pressure diffusion / advection step
- Early exit when both velocity magnitude and membranePressure are below a small threshold
- Possibly separating the pressure evolution into its own micro-pass in the future if we want even richer membrane topology

The current implementation prioritizes **readability and the new creative behavior** over maximum performance. It should still run well at 2048², but there is clear headroom.

---

## JSON

New definition created at:
`shader_definitions/advanced-hybrid/ambient-liquid-coupled.json`

Four expressive params with good semantic names that match the new mental model (Wave Strength, Viscosity, Vortex Strength, Layer Separation).

---

## Files Changed

- `public/shaders/ambient-liquid-coupled.wgsl` (major creative upgrade)
- `shader_definitions/advanced-hybrid/ambient-liquid-coupled.json` (new)

---

**This is the first shader in the 2026-05-31 Grok creative batch. It now feels like something you want to reach out and touch.**