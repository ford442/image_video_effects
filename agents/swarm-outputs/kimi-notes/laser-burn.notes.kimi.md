# laser-burn — Kimi Upgrade Notes

## Changes
- Ember persistence channel: embers fade slower than heat for lingering glow
- Audio spark showers: treble creates flying particles near beam
- Depth mod: background chars less intensely
- 3-state temporal system: charLevel, heatLevel, emberLevel
- Spark particles are bright white-yellow for visibility

## Wow Factor
- Embers continue to glow after mouse moves away
- Spark showers on treble hits look like welding arcs

## Risks
- 3-channel state may exceed `dataTextureA` precision at low bit depth
- Sparks can be too sparse at low treble levels
