SHADER: gen-abyssal-silicate-geode-weaver

IDENTITY (one sentence): a rotating Voronoi geode cavity hung with fast iridescent gyroid silicate threads, lit by audio shard pulses and click refraction waves, with a rotating-advected HDR trail.

KEEP VERBATIM: `voronoi` (F1/F2 squared), `gyroid`, `smin` union (k=0.2), the geode SDF (`max(sphere, -crystalDist)`), thread domain warp (mouse gravity well, rot2D(time*1.35), translation), 88-step march, `getPalette` iridescence (zoom_params.z), audio pulse / shardPulse (zoom_params.w), click waves (age-based, no ripple.w), camera flight, fog, tangential history advection, `max(col, prev*0.9)` HDR history. 4 saved params and their roles (x thread density, y geode facet scale, z iridescence, w acoustic glow) are byte-exact.

ADD (native ideas):
  1. Agate / chalcedony banding inside the geode facets. Rings are contours of the Voronoi nearest-seed distance F1 (the surface value of F2-F1 is pinned to ~0.2 by the SDF, so it cannot band; F1 varies across each facet). Ring phase is offset by the cell hash so each facet has its own band count, and the bands are colour-zoned blue at the seed to rose at the rim, using the existing geode blue / sss magenta constants. Scales with Geode Facet Scale. Belongs here because the facets are already Voronoi cells and a geode's classic look is banded agate.
  2. Dew-bead knots on the silicate threads. Pearls are placed on a jittered lattice in the thread's own warped/rotating domain (a shared `threadDomain()` helper, identical to what `map` uses) so they ride the threads instead of sliding through them. Each bead perturbs the normal into a dome (rotated back to world), with a specular pearl and slight refractive darkening. Belongs here because it makes the gyroid sheets read as strung, woven silk.
  3. Thin-film phase from thread thickness. Physical sheet thickness 0.1/|grad gyroid| plus a bead swell feeds the `getPalette` phase argument, so thick beads/knots and thin stretches shift hue. Still driven by Iridescence Intensity.

FORBID on this file: new IQ palette overlay, springs / extraBuffer state (never persists), extra ripple layers, new creature/fractal, tone-mapping the stored history.

A PACKING: existing documented packing kept: HDR history RGB (`max(col, prev*0.9)`, bounded to 5) with semantic alpha (coverage + click emission) in A. writeTexture gets ACES applied to the display copy only.

PLUMBING FIXED (changes the look slightly, disclosed):
  - `textureSampleLevel(dataTextureC, u_sampler, ...)` (filtering sampler on rgba32float) replaced with manual bilinear `textureLoad` (4 taps, clamped), tangential advection kept.
  - Hardcoded alpha 1.0 replaced with semantic alpha (surface coverage, thread beads, click emission, small void haze floor).
  - ACES on display RGB only; stored A history stays un-tone-mapped HDR.
  - No zero-C early return exists; no ripple.w use; pow bases are non-negative (checked). Audio already read from `plasmaBuffer[0].xyz`.
  - Header now `Ideas:` / `A packing:` / `Upgraded: 2026-09-27`.
