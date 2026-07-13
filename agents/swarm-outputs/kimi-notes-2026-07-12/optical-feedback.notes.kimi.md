# optical-feedback — retry upgrade notes

## Goal
Richer, expanded upgrade of the original Optical Feedback Loop. Preserves the infinite recursive feedback, hue shifting, audio-pumped zoom/rotation, and depth fade while adding physical interactive layers.

## What was kept
- Original 13-binding canonical header and `Uniforms` layout.
- `@compute @workgroup_size(16, 16, 1)`.
- Feedback sample from `dataTextureC` with zoom, rotation, domain warp, and hue shift.
- Audio envelope (`bass_env`) modulating zoom and colour.
- Depth-aware fade and ACES tone-map.
- Parameter mapping: accumulation (p1), zoom (p2), rotation (p3), shift (p4).
- Semantic alpha via `totalAlpha`, never forced opaque.

## New interactivity upgrades
1. **Spring-damper feedback centre**
   - Persists `smoothMouse` / `velocity` in `extraBuffer` and integrates with `dt`.
   - The feedback centre blends the instantaneous mouse with the lagging smoothed mouse, producing a delayed, drifting focal point.

2. **Mouse gravity well on feedback UV**
   - The feedback sample coordinate is pulled toward the cursor with distance-falloff strength, causing the loop to lean into the mouse.

3. **Click shockwave injected into the loop**
   - Records click time/position on mouse-down.
   - Expands a ripple that displaces the feedback UV and paints a transient bright ring, feeding itself back on subsequent frames.

4. **Emergent hue phase**
   - Stores an accumulating `huePhase` in `extraBuffer`.
   - It evolves from audio energy and click events, so the feedback hue keeps drifting even when the user parameters are static.
   - Also modulates the feedback coordinate by previous-frame colour energy for self-sustaining warping.

## Validation
- `naga public/shaders/optical-feedback.wgsl` → Validation successful.
- Line count: original HEAD 148 → retry 228 (+80 lines).

## Files touched
- `public/shaders/optical-feedback.wgsl` (overwrite)
- `shader_definitions/interactive-mouse/optical-feedback.json` (already satisfied requirements; not modified)
