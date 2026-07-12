# cyber-rain — retry upgrade notes

## Goal
Richer, expanded upgrade of the original Cyber Rain shader. Keeps the neon-rain-on-wet-glass look, the mouse wiper, and all parameter mappings while layering additional interactive physical effects.

## What was kept
- Original 13-binding canonical header and `Uniforms` layout.
- `@compute @workgroup_size(16, 16, 1)`.
- Vertical rain drops and streaks, wet-glass blur, chromatic aberration, and depth-aware fog.
- Audio envelope (`bass_env`) driving rain intensity.
- Temporal wetness accumulation via `dataTextureC` / `dataTextureA`.
- Parameter mapping: intensity (p1), blur (p2), bloom (p3), wiper (p4).
- Semantic alpha based on rain intensity and droplets.

## New interactivity upgrades
1. **Spring-damper wiper follow**
   - Stores a smoothed cursor in `extraBuffer` integrated with `dt`.
   - The rain wiper is now centred on the lagging mouse, making it feel like a heavy physical squeegee.

2. **Mouse gravity well**
   - Computes a horizontal `rainBend` vector pointing toward the cursor.
   - Both the rain-drop grid and the streak grid receive this bend, so falling rain curves toward the mouse.

3. **Click shockwave / splash**
   - Records click position/time on mouse-down and expands a radial Gaussian ring that brightens rain and momentarily behaves like a splash.

4. **Thunder flash on bass peaks**
   - Adds a brief white flash driven by the bass envelope (`env`) and a fast time fract, simulating lightning when the audio hits hard.

## Validation
- `naga public/shaders/cyber-rain.wgsl` → Validation successful.
- Line count: original HEAD 130 → retry 205 (+75 lines).

## Files touched
- `public/shaders/cyber-rain.wgsl` (overwrite)
- `shader_definitions/interactive-mouse/cyber-rain.json` (already satisfied requirements; not modified)
