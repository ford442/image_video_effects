# gen-ethereal-quantum-medusa — Kimi Notes

## Changes
- Chromatic tentacle separation: core glows warm red, tentacle tips cool blue, mid-body green.
- Temporal bioluminescence pulse memory: `dataTextureC` stores previous glow for organic afterimages.
- Audio-reactive tentacle sway: `mids` modulate domain-repetition angle for rhythmic undulation.
- Bass-driven glow intensity pulses with heartbeat-like rhythm.
- Depth output from ray distance for volumetric compositing.

## Wow-Factor
- Medusa that literally dances to music — tentacles sway on beats, bioluminescence pulses like a deep-sea creature.
- Chromatic body gradient makes the jellyfish feel translucent and alive.

## Risks
- Ray march with `smin` and domain repetition is ~100 steps; already at performance limit for some mobile GPUs.
- Temporal blend may cause ghosting on fast mouse movement; blend factor is conservative.
