# Grok Upgrade — alpha-reaction-diffusion-rgba

**Date**: 2026-05-31  
**Upgraded by**: Grok (creative direction + direct implementation)

---

## Original Creative Diagnosis

This was already one of the more sophisticated reaction-diffusion shaders in the library — a proper 4-species (two loosely coupled Gray-Scott pairs) system running in full f32 precision. The core math was good.

However, it still felt like "a simulation you watch" rather than "a living ecosystem you can play god with." 
- Zero audio reactivity despite having `plasmaBuffer` available.
- Mouse was just a blunt "add chemicals" tool.
- Visualization was additive colored chemicals — pretty but not emotionally alive.
- No sense of predation pressure, extinction, recovery, or stratification.

The latent potential was enormous: this could become the canonical "digital life" shader in the collection.

---

## Upgrade Direction Chosen

**"Two Competing Ecosystems with Audio Climate and a Keystone Species"**

- **Bass** = makes predators hungrier and more aggressive (higher kill rate + slower predator diffusion).
- **Mids** = increases competition between the two separate ecosystems (they suppress each other more).
- **Treble** = triggers "spore bursts" — sudden erratic diffusion in the second ecosystem.
- **Mouse** = now a true keystone species. Holding the mouse creates localized extinction events. Recovery dynamics become visible and beautiful.
- **Depth** = creates vertical stratification. Deeper areas evolve more slowly and stably (like real ecological layers in water or soil).
- Visualization evolved to feel like competing biomes with dominance fade and biomass-driven alpha.

---

## The Moment It Sings

1. Let the simulation run until rich, complex Turing patterns emerge.
2. Hold the mouse down in one area for a few seconds while bass is strong — watch one ecosystem get hammered and the other start to invade the cleared space.
3. Play music with clear dynamics. The "weather" of the digital world changes with the music in a way that feels intentional.
4. Use in a slot chain with a slow-moving video underneath — the depth layering + biomass alpha creates gorgeous organic compositing.

---

## Technical Notes for Claude

- The reaction now has audio-driven asymmetry in both rates and diffusion. This is richer but slightly more expensive.
- State is still stored in `dataTextureC` (read) → `dataTextureA` (write). This is correct for the current ping-pong.
- Good candidate for future workgroup tiling on the Laplacian stencil if performance becomes an issue at 2048².
- The visualization now produces more interesting alpha (instability + biomass). This should composite extremely well.

---

## JSON

Completely rewritten with semantic names that match the new mental model:
- "Nutrient Availability"
- "Predation Pressure" (bass amplifies this)
- "Ecosystem Competition" (mids amplify this)
- "Source Nutrients"

Added strong `features` and `tags` for AI VJ matching.

---

## Files Changed

- `public/shaders/alpha-reaction-diffusion-rgba.wgsl`
- `shader_definitions/simulation/alpha-reaction-diffusion-rgba.json`

---

**Second shader in the 2026-05-31 Grok creative batch complete. This one now feels like a genuine digital ecology rather than a math visualization.**