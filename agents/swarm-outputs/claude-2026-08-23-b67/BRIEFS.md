# Batch 67 briefs — 2026-08-23 (tracker #521–530)

**Status: CLAIMED.** Ten shaders. Tracker entries #521–530 are reserved by this
batch; parallel agents should take #531+.

## Creative brief (on top of the 13-binding contract)

1. **Fast motion** — at least two *distinct, analytic* fast-motion techniques
   per shader. Traveling packets, velocity-stretched streaks, conveyor/warp
   cameras, orbital whip, speed lines, time-warp easing. Velocities clamped and
   stable. **No frame-hash strobing** — motion must be closed-form in `config.x`.
2. **Psychedelic colour** — vivid, high-saturation, multi-hue. Smooth hue
   cycling, prismatic dispersion, iridescent shifts, reactive colour fields
   driven by audio + pointer. No muddy or desaturated results.
3. **Fun / high-energy personality** — playful and energetic while staying
   coherent with each shader's original identity: elastic snap-back, liquid
   rainbow trails, crystal light bursts, magnetic particle dances, holographic
   flicker that feels alive.

## Hard constraints

Exact 13-binding contract · ACES + semantic alpha · `dataTextureA` writeback ·
`plasmaBuffer` audio · bounded spring/click state strictly in
`extraBuffer[133..138]` · exact `textureLoad` from `dataTextureC` (no filtering)
· naga validation · no `extraBuffer` writes outside `[133..138]` · preserve
existing param IDs / defaults / ranges.

## Audit and per-shader focus

| # | Shader | Gaps found | Fast-motion pair |
|---|--------|-----------|------------------|
| 521 | `bubble-chamber` | **filtering sampler on rgba32float C**, no audio, no ripples, no ACES | Relativistic track streaks; helical momentum spirals |
| 522 | `crystal-freeze` | `@workgroup_size(8,8,1)`, no ripples, no exact C load | Dendrite growth fronts; facet light-burst whip |
| 523 | `ferrofluid-spikes` | no ripples, no C read, no ACES | Spike eruption packets; travelling field conveyor |
| 524 | `frost-reveal` | **no bounds guard**, no audio, no ripples, no ACES | Crystallisation wavefronts; radial shatter streaks |
| 525 | `glass-wipes` | **no bounds guard**, no ACES, no exact C load | Wiper blade sweep with elastic snap-back; bead conveyor |
| 526 | `heat-haze` | no C read, no ACES | Thermal updraft packets; shimmer shear streaks |
| 527 | `holographic-flicker` | **time-hashed strobing (3 sites)**, no ripples, no ACES | Scan-line conveyor; parallax ghost whip |
| 528 | `liquid-jelly` | no ripples fronts beyond basic, thin colour | Elastic wobble propagation; jiggle overshoot streaks |
| 529 | `magnetic-dipole` | no audio, no ACES, no exact C load | Field-line particle dance; pole-flip orbital whip |
| 530 | `radial-blur` | **no A writeback**, no ACES, no C read | Zoom-burst speed lines; rotational shear streaks |

Note: `holographic-flicker` currently drives its flicker from hashes seeded on
time, which is exactly the strobing the brief forbids. Its motion is being
rebuilt on analytic phases.

## Validation

Structural only in this container: `wgsl_precommit_gate.py` (naga + bindgroup +
workgroup + extraBuffer), `audit_extrabuffer.py`, `audit_dead_sliders.py`,
`audit_audio_mappings.py`, shader-list and uniform checks, Jest, production
build. Real-GPU visual QA remains external.
