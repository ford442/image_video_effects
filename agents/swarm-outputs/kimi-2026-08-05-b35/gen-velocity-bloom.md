# gen-velocity-bloom — Algorithmist b35 notes

**Lines:** 169 → 266 (+97, essentially at the envelope edge — the additions
are the flow field, advection/diffusion feedback and click-spring machinery).

## Contract repairs (was partially non-compliant)

- Added the mandatory resolution bounds guard (was absent — out-of-bounds
  texture stores possible).
- `dataTextureC` was sampled with `textureSampleLevel(…, u_sampler, …)` —
  rgba32float is non-filterable → all feedback reads now via non-filtering
  `textureLoad` (advected coords clamped to texture bounds).
- Depth was a **pass-through copy of readDepthTexture** → now generated
  relief depth: `baseLuma*0.25 + bloomLuma*0.75` (bloom mass rises toward
  the viewer, near-is-one).
- `velocityColor` if/else chain → branchless smoothstep gradient (same hues).

## Techniques integrated (algorithmic depth domain)

1. **Lucas-Kanade-style flow direction** — luminance gradient (gx, gy) from
   centered differences + temporal diff give a brightness-constancy motion
   cue; motion direction = perpendicular of the gradient. The original
   velocity *magnitude* formula (`lumaDiff + gradient*0.5`) is kept verbatim
   as the soul of the effect.
2. **Motion-aligned anamorphic bloom** — the old fixed-horizontal 16-tap
   streak now sweeps along the estimated flow direction, so fast motion
   smears along its own path (true motion bloom).
3. **Curl-noise advection** — divergence-free 2-octave curl field fused with
   the gradient cue; the feedback buffer is re-sampled at
   `uv − flow·radius·(0.5+velocity)·2`, producing organic incompressible
   swirl trails instead of pure exponential ghosting. Time only scrolls the
   noise potential → frame-to-frame coherent.
4. **Gray-Scott-hint diffusion feedback** — 4-tap Laplacian of the advected
   history, `diffused = prev + 0.6·∇²`, then decay, then thresholded
   bright-pass feed (`max(feed, decayed·0.9)` kept as the accumulation core).
   Bloom now propagates outward like a reaction front rather than only fading.
5. **Multi-scale detail** — 4-octave star bloom (macro, kept) + treble/FFT
   driven value-noise micro-shimmer sparkle on the bloom field.
6. **Click-pulse spring (mouse interaction, was absent)** — persistent state
   in extraBuffer[133] (energy) / [134] (prev mouseDown), single-writer at
   gid (0,0) with `arrayLength` guard; rising edge injects 1.0, decays ×0.93
   per frame; renders as a finite Gaussian burst at the cursor, spatially local.

## Audio (contract sources only)

- `plasmaBuffer[0].xyz`: bass pumps Bloom Intensity, mids widen Bloom Radius,
  treble drives the shimmer — all multiplicative on the live sliders.
- Guarded low FFT bins (`extraBuffer[6..8]`, i.e. engine bins 1–3 within the
  allowed 1–8 range, `arrayLength` guarded) boost the shimmer.

## Slider wiring (all 4 live, updatedParams byte-exact)

- p1 Velocity Threshold → velocity mask edge *and* bright-pass feed floor.
- p2 Bloom Intensity → feed gain (× bass pump).
- p3 Bloom Radius → octave radii, anamorphic length, advection distance
  (× mids widening).
- p4 Decay Rate → feedback decay (unchanged mapping).

## Perf estimate

Taps per pixel: velocity field 5 + star bloom 32 + anamorphic 16 +
feedback 5 + base 1 ≈ 59 texture taps (was ~53) plus ~24 hash evals for
curl/shimmer. Roughly +15–20% over the old shader; still a lightweight
post-effect class shader. All loops bounded, early guard exit only.

## Gate

`wgsl_precommit_gate.py --files …` → **passed** (naga OK, bindgroup
compatible, 0 extraBuffer violations — [133..134] single-writer spring is in
the sanctioned zone). JSON: features list populated + description extended
(additive, truthful); `updatedParams` verified byte-exact.
