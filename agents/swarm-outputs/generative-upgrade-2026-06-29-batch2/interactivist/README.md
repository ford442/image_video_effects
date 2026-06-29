# Acid Lissajous — Interactivist Upgrade

**Shader:** `gen-acid-lissajous`  
**Agent:** Interactivist (batch 2)  
**Date:** 2026-06-29

## Changelog

- **Mouse gravity well** — strands are pulled toward the cursor with strength controlled by the *Glow / Mouse Gravity* slider and modulated by bass.
- **Click burst shockwave** — while the mouse is held, a localized radial burst adds energy and temporarily spawns two extra strands.
- **Audio reactivity**:
  - **Bass** → field scale pulse, extra strands, gravity boost, click-burst intensity.
  - **Mids** → morph / animation speed multiplier.
  - **Treble** → additive sparkle and brighter strand saturation.
- **Luma-keyed video spawn** — bright regions of the incoming video/image layer seed additional colored glow.
- **Depth-aware transparency** — depth read from `readDepthTexture` modulates alpha and chromatic-aberration bias.
- **Temporal feedback / motion advection** — previous frame is sampled along an organic-drift vector for self-advecting, ever-evolving trails.
- **Performance optimization** — inner Lissajous loop now tracks squared distance and takes `sqrt()` once per strand; sample count reduced from 180 to 96 and base strands from 7 to 5.
- **ACES tone mapping + chromatic aberration** applied before output.

## Techniques Used

| Toolkit Area | Technique |
|--------------|-----------|
| Mouse interaction | gravity well + click burst |
| Audio reactivity | bass pulse, mid morph, treble sparkle |
| Video/depth feedback | luma-keyed spawn, depth-aware alpha |
| Feedback loops | ping-pong temporal accumulation with drift advection |

## Performance Estimate

- ~5–9 strands × 96 Lissajous samples per pixel, with squared-distance optimization.
- One `textureSampleLevel` each for video and feedback, plus one `textureLoad` for depth.
- Estimated: **~1.2–1.6 ms/frame at 1080p on a mid-tier GPU**, well within 60 fps budget.
- No per-pixel heavy loops beyond the bounded strand/sample kernel; no `tan`, `textureSample`, or `dpdx`/`dpdy`.

## Dependencies

- Uses the canonical 13-binding generative header from `agents/WGSL_BUILTINS_GENERATIVE.md` §0.
- Reads audio from `plasmaBuffer[0].xyz` (bass/mids/treble).
- Expects `dataTextureC` to contain the previous frame for feedback.
