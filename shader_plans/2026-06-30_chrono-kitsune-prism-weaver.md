# 2026-06-30 — Chrono-Kitsune Prism Weaver

**Status:** approved
**Category:** Hybrid (Advanced)
**Shader ID:** chrono-kitsune-prism-weaver
**WGSL file:** public/shaders/gen-chrono-kitsune-prism-weaver.wgsl
**JSON target:** public/shader-lists/hybrid.json (or artistic.json if preferred)

## Visual Concept
A living prismatic kitsune spirit weaving through a chrono-void lattice.
Multiple ethereal tails (5–9) trail behind the fox form, each carrying independent chromatic time-shifts and void-echoes. The lattice itself pulses and folds with temporal feedback — past frames bleed into the present as prismatic caustics and neon rift lines.

Mouse drag pulls the weave like silk through fingers, creating propagating temporal ripples.
AI depth map adds true parallax depth to the void layers and tail tips.
Optional audio reactivity drives the pulse rate of the chrono rifts and the brightness/intensity of the prismatic dispersion on the tails.

**Wow factor:** Hypnotic, organic-yet-digital, high motion, beautiful color, infinite zoom feel in the void lattice. Perfect showcase for multi-pass compute + temporal ping-pong + depth + mouse/audio.

## Technical Requirements
- Compute shader (ping-pong state + feedback pass + composite)
- 2–3 workgroup passes (state update, temporal feedback, final composite)
- Use standardized Uniforms struct from AGENTS.md
- Support mouse position + click strength
- Optional audio texture / spectrum uniform (if EventBus or audio node available)
- Integrate with existing depth map when AI model is loaded
- @workgroup_size(16, 16, 1) or (8, 8, 1) — 3-argument form preferred for clarity

## Uniforms (add to standard header)
- `mouse_pos`, `mouse_down`, `mouse_strength`
- `time`, `delta_time`
- `prism_hue_shift`, `tail_count`, `weave_tightness`, `chrono_echo_amount`
- `audio_pulse` (0–1 reactive intensity)
- `depth_enabled`, `depth_scale`
- Standard resolution, frame, etc.

## Passes
1. **State / Weaver Pass** — Update kitsune position, tail curves, lattice points
2. **Temporal Feedback Pass** — Blend previous frame with prismatic time-shifted echoes + void absorption
3. **Composite + Post** — Final color grading, chromatic aberration on rift edges, bloom on bright tail tips, depth parallax offset

## Performance Targets
- 60 fps on mid-range GPUs
- Keep memory low (two or three ping-pong textures max)
- Workgroup size that tiles cleanly over 512×512 or 1024×1024 dispatch

## Implementation Notes for Jules / Implementer
- Follow the universal bindgroup + uniform header exactly (see AGENTS.md)
- Make parameters tunable via the existing Controls UI where possible
- Add to the dropdown immediately via the JSON entry (hot-swap ready)
- Test with and without AI depth loaded
- Optional: add a simple “tail whip” on mouse click for extra playfulness

## Acceptance Criteria
- Visual is immediately striking and different from existing kitsune/void/chrono effects
- Smooth mouse interaction with clear temporal response
- Depth integration works when model is loaded
- No regressions in existing shaders or performance
- Clean WGSL, well-commented, follows project shader style

**Created:** 2026-06-30 (replaces [YYYY-MM-DD] per daily rule)
