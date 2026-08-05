# gen-lichtenberg-storm — Interactivist upgrade notes (Batch 36, #328)

203 → 287 lines (+84). Gate: **PASS** (naga OK, bindgroup compatible, workgroup OK, 0 extraBuffer violations).

## What changed

**Bug fix (contract compliance)**
- Feedback read was `textureSampleLevel(dataTextureC, u_sampler, …)` — rgba32float is
  unfilterable, so that path was invalid. Now `textureLoad(dataTextureC, px, 0)` (non-filtering).
- Ripple loop guard brought to contract form `min(u32(u.config.y), 50u)` with
  `rt >= 0.0` and decay early-out (bounded, finite ages).

**Mouse (toolkit: spring-smoothed follow + click shockwave + velocity-aware)**
- Spring-smoothed cursor state in extraBuffer[133..136] (pos/vel, k=80, d=12, fixed
  h=0.016, clamped), prev-down edge in [137], shock timestamp in [138]. Single writer
  (gid 0,0) + `arrayLength` guard; readers fall back to raw mouse when state unavailable.
- The cursor is now a **live discharge electrode**: an extra `licht()` seed anchored at
  the smoothed mouse, brightened by click-hold and mouse speed.
- Mouse velocity agitates the storm: it widens branch count and jitter (`dynJitter`),
  so fast strokes produce wilder discharges (mouse affects ≥2 parameters).
- Click rising-edge fires an **ionization shockwave ring** from the electrode:
  finite age (2 s gate), spatially local Gaussian ring, non-negative, cold-buffer-safe
  (shockT initialized to −10, ring suppressed when shockT==0).

**Audio (toolkit: FFT multi-band color splitting)**
- Guarded engine FFT bins 1–8 (extraBuffer[6..13], read-only): low bins drive warm
  sparks, high bins drive cool sparks; treble still gates sparkle density.
  Existing bass seed-count / bass-pulse / mids thickness wiring preserved.

**Feedback / emergent (toolkit: temporal accumulation + etched-channel memory)**
- dataTextureA now stores `r=energy (afterglow), g=charge, b=ring`. The charge channel
  **accumulates where strikes occur** (`prevCharge*decay + energy*0.12`) and feeds back
  as an `etch` bias inside `licht()` that lowers the dendrite threshold along old
  channels → strikes preferentially regrow along previous paths. This is the emergent,
  history-dependent behavior: self-organizing Lichtenberg figures that deepen over time.
- Depth is now real relief: `0.15 + energy*0.55 + charge*0.2 + ring*0.15 + storm*0.1`
  (clamped, near=1 at hot cores/etched channels).

## Sliders (all LIVE, unchanged contract)
- p1 Branch Jitter → branch count + dendrite wander (now summed with mouse-velocity jitter)
- p2 Glow Intensity → HDR tip glow, exposure, shock ring flash
- p3 Storm Frequency → storm pulse rate + seed turnover
- p4 Afterglow Persistence → afterglow decay **and** charge-etch decay (deeper memory)

## Perf estimate
~Same order as before: 6–9 `licht()` evaluations/pixel worst case (each = 2× 5-octave
fBM); the 50-ripple cap only adds cost for fresh clicks (decay early-out). Spring/FFT
blocks are O(1). Estimate ≈1.2× previous cost — comfortably 60 fps at 1080p on discrete
GPU, fine on modern integrated.

## JSON
Additive only: tags `+ interactive, feedback, temporal`. `updatedParams` byte-exact.
