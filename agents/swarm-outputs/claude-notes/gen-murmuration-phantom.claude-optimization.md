# gen-murmuration-phantom — Claude Optimization (2026-06-07)

## Bottlenecks Identified
- Line ~154: `textureStore(dataTextureA, coord, vec4<f32>(col, a))` — stored color not density; temporal feedback was lossy and color-space incorrect
- dataTextureB never written — wasted bind slot, no trail persistence channel
- No huePreserveClamp → violet highlights desaturated under high-bass pulse
- Temporal trail decay (line ~146) mixed against `prev.rgb * 0.92` but `prev` read from `dataTextureC` which carried color, not density — inconsistent

## Optimizations Applied
- Added persistent trail accumulation: `trailDensity = max(density, prevTrail.a * trailDecay)` where decay responds to bass → trails linger longer in quiet passages, flush fast on beats
- Write density+edge+scatter to `dataTextureB` for downstream multi-slot use
- Write `outCol + trailDensity` to `dataTextureA` — correct state for next-frame feedback
- Added `huePreserveClamp(col * 1.2, 2.5)` + IGN dither after ACES
- Updated features list and `Upgraded:` date

## Visual / Transcendence Notes
- Trail accumulation makes the flock feel genuinely volumetric — ghost paths persist across beats
- trailDecay `0.93 - bass * 0.04` means hard bass hits sweep the sky clean, giving punctuation to the murmuration rhythm

## Remaining Risks
- `textureSampleLevel` on `dataTextureC` for trail uses a computed UV from coord/res — this works for pixel-exact reads but may have 0.5-pixel offset at non-power-of-two resolutions
- True extraBuffer boid sim (per-boid x,y,vx,vy) not implemented — would require a separate pass and was considered a full rewrite; curl-noise density approach preserved

## JSON Changes
- Added `trail-accumulation`, `hue-preserve-clamp`, `ign-dither` to features array
