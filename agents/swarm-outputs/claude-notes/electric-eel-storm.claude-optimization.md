# electric-eel-storm — Claude 3E Polish (E3) (2026-06-07)

## Bottlenecks Identified
- `stormCloud` ran two fixed-octave `fbm2` calls (4 + 3 = 7 `noise2` evaluations) for every pixel, including the periphery where the cloud's contribution is visually secondary to the eel/lightning foreground.
- The eel loop computed `sdEel` (capsule SDF) and glow for every eel at every pixel, even when the pixel was nowhere near the eel's body — `1/(1+d²·2000)` glow falls below visibility well before the SDF needs evaluating.
- Audio-driven body pulse, glow weight, hue shift, and temporal-blend factor all read raw `bass` directly — strobe-prone on percussive transients (the shader had no `bass_env` despite the pattern being standard elsewhere in the codebase).

## Optimizations Applied
- **`bass_env` migration**: added the standard smoothing helper, stored the envelope in `extraBuffer[3]` (attack 0.08 / release 0.02), and routed `sdEel`'s body-size modulation, `eelGlow` weighting, `eelHue` shift, and the final temporal-blend factor through `smoothBass` instead of raw `bass`.
- **Early-exit for off-screen eels**: gated the entire `sdEel`/body/glow block behind `if (length(uv - eelPos) < 0.35)` — skips the capsule-distance computation and the `1/(1+d²·2000)` glow evaluation for eels whose body can't possibly reach this pixel (their glow at that range is already below the `2000`-scaled falloff's visibility floor).
- **Distance-based octave LOD on storm cloud**: `lod = smoothstep(0.3, 0.7, distFromCenter)`; primary FBM relaxes 4→2 octaves and the secondary turbulence FBM relaxes 3→2 toward the screen edges — trims up to 3 `noise2` calls per layer at the periphery where the cloud reads as background texture rather than focal detail.
- Synced header `Features:` (added `upgraded-rgba`, `distance-lod`) and JSON `features` (`distance-lod`).

## Visual / Transcendence Notes
- The smoothed bass envelope makes eel-body pulsing read as a heartbeat rather than a strobe — matches the "bioluminescent" creature-feel the shader is going for.
- Cloud LOD reduction is masked by the foreground eels/arcs/lightning, which dominate the visual focus; edge cloud detail loss is imperceptible against the storm's inherent turbulent noise.

## Remaining Risks
- The `0.35` early-exit radius assumes `bodyLength` stays near its base `0.18 + bass*0.03` — if a future param exposes much larger eels, the cutoff would need widening to avoid clipping glow at the gate boundary.

## JSON Changes
- Added `distance-lod` to `features`.
