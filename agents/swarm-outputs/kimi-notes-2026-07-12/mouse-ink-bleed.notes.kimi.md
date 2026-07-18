# mouse-ink-bleed — retry upgrade notes

## Goal
Richer, expanded upgrade of the original Mouse Ink Bleed compute shader. The first retry pass was too compact, so this version adds more interactivity while preserving the original ink-diffusion, parameter mapping, and semantic-alpha behaviour.

## What was kept
- Original 13-binding canonical header and `Uniforms` layout.
- `@compute @workgroup_size(16, 16, 1)`.
- FBM/value-noise/domain-warp ink displacement.
- Audio reactivity via `plasmaBuffer` (bass/mids/treble).
- Temporal trail through `dataTextureC` / `dataTextureA`.
- Depth-aware fade and ACES tone-map + IGN dither.
- Parameter mapping: spread (p1), turbulence (p2), decay (p3), colorIntensity (p4).
- Semantic alpha derived from brush/edge-glow contribution, not forced opaque.

## New interactivity upgrades
1. **Spring-damper mouse follow**
   - Stores `smoothMouse` and `velocity` in `extraBuffer` and integrates each frame with `dt = u.config.y`.
   - The gravity well is centred on the lagging cursor, giving the ink a physical, inertial feel.

2. **Mouse gravity well + vortex**
   - Pixels near the smooth cursor are pulled inward.
   - A tangent vortex component spins faster while the mouse button is held.
   - Strength scales with bass envelope and `spread` parameter.

3. **Click shockwave / ink burst**
   - Detects a mouse-down transition using `extraBuffer[PREV_PRESS]`.
   - Records click position/time and expands a Gaussian ring that displaces UVs and adds a bright ink splash.

4. **Emergent feedback loop**
   - Uses the previous frame's colour energy (`length(prev.rgb)`) to gently amplify the current displacement, creating self-reinforcing turbulence in busy regions.

## Validation
- `naga public/shaders/mouse-ink-bleed.wgsl` → Validation successful.
- Line count: original HEAD 129 → retry 202 (+73 lines).

## Files touched
- `public/shaders/mouse-ink-bleed.wgsl` (overwrite)
- `shader_definitions/interactive-mouse/mouse-ink-bleed.json` (already satisfied requirements; not modified)
