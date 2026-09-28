```
SHADER: gen-abyssal-plasma-void-medusa
IDENTITY: a raymarched hollow-dome jellyfish bell with 5 wavy tentacles swinging round it in a noise-warped void,
  fresnel/hue-shifted bioluminescence plus volumetric march glow.
KEEP VERBATIM: bell dome SDF (outer/inner shells L102-110), 5 tentacles and their sway (L113-132), domain warp
  (L86-91), mouse drag of the body (L94-99), volumetric `vol` accumulation in the march, fresnel/hue shading family,
  4 slider roles (x bioluminescence glow, y fluid distortion, z tentacle length, w plasma hue), saved params.
  Screen orientation (bell low, tentacles up — "inverted" comment L101) stays; flag for GPU QA, do not flip.
ADD (native ideas):
  1. Plasma node lanterns — the "plasma nodes" the JSON description promises: 5 glowing cores at the tentacle roots,
     reusing the tentacle angle `a` (L118), emitted into `vol` during the march (L199) so they glow volumetrically.
     Visible at audio 0 (slow stateless flicker); bass brightens.
  2. Bell shell-thickness translucency — thickness = outer-inner shell gap (L107-109) at the hit point: the thin
     crown lets lantern light through (warm transmission), the thick rim occludes. Couples idea 1 to the bell SDF.
  3. Void-current filaments — make the L86-91 domain-warp field visible: thin iso-line filaments of the warp noise
     accumulated in the march glow / background, swirled around the body by the mouse drag offset (L94-99).
FIX/WIRE (floor, all silent bugs at HEAD):
  - Canonical header (copy shape of public/shaders/analog-film-degrade.wgsl): Features, Upgraded 2026-09-27, Ideas, A packing.
  - Audio: L213 reads dataTextureC.r as "audio" -> plasmaBuffer[0].xyz. The JSON claims audio-reactive; make it true.
  - extraBuffer[133] breathing pulse (L80, L158) is zeroed each frame and races across threads -> stateless bell
    breath from time (+ bass). Remove the extraBuffer write.
  - Camera: L177 `.xzy` swizzle swaps y/z -> mouse press jumps camera overhead and at mouse≈(0.5,0.566) ro.xz=0 makes
    cross(cw, up) = 0 -> NaN frame. Fix the orbit so the default view reproduces HEAD's default framing where possible.
  - L247 miss fade exp(-dO*0.05) with dO>100 zeroes background and halo -> fade by hit distance only on hits; misses
    keep background + glow.
  - Tentacle taper at L129 uses a stale tP.y (~0) -> taper along the tentacle's own length coordinate.
  - C sampled with textureSampleLevel -> exact textureLoad(dataTextureC, coord, 0). Write dataTextureA (HDR linear +
    semantic alpha) and a real hit depth (near 1, miss 0). ACES on writeTexture only (replace Reinhard+gamma);
    no double tone map. Alpha: body/glow coverage, not 1.0.
  - Watch the step: domain warp is not Lipschitz; scale step (e.g. 0.7) if you raise any warp amplitude.
FORBID: jet-propulsion wave, radial canals, gonads, lappets, marine snow, nematocyst beads, Stokes-shift afterglow,
  bell contraction wave, spring cursor, screen-space ripple rings.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR for a light trail.
DEFAULT-LOOK SHIFT: background/halo no longer black; 5 lantern cores at the bell rim; audio now live.
```

STATUS: draft (coordinator) — superseded below

## Refinement (implementing agent, 2026-09-27)

Verified against HEAD — all FIX claims true except one detail in Idea 2:
- CORRECTION: the card had the shell thickness inverted. Outer r=1.5 @y=1, inner r=1.3 @y=0.5 → the gap is ~0.3 at the
  RIM and ~0.7 at the CROWN. So the thin rim transmits lantern light, the thick crown filters it (numpy: bell-hit
  thickness p5/p50/p95 = 0.28/0.40/0.60).
- Also found: HEAD treated step-exhausted rays as hits (`dO < MAX_DIST` only) → hit now requires dS < 0.01.

WHERE EACH IDEA LIVES (final WGSL):
  1. Plasma node lanterns — lanternPos/lanternPower L123-138 (stateless flicker, bass brightens), SDF bulbs fused at
     the tentacle roots L178-181, volumetric halo in the march L273-280 + L372-373, tentacle lighting + white-hot
     cores L343-346, lantern light on nearby currents L366-367. Lantern colour = complementary plasma hue.
  2. Bell shell-thickness translucency — L329-341: radial outer/inner gap at the hit, Beer-Lambert with absorption
     (1-hue)*3+1.2 so the rim glows lantern-hot and the crown deepens to the bell hue.
  3. Void-current filaments — voidCurrent L107-115 (the map() warp field, now shared), isoLine L212, L354-367:
     iso-lines of warp components x/y on the ray's closest approach to the body, same mouseDrag, knots where they
     cross; strength 0.15 + fluid*0.9 (slider y drives both warp and currents).

FIXES DONE: canonical header; audio → plasmaBuffer[0].xyz; extraBuffer[133] write/read removed → stateless
bellRadius(); camera orbit on a clamped sphere (default unpressed framing identical; no overhead jump; no NaN at
mouse (0.5,0.566)); miss fade removed (hits only); tentacle taper along own length (0.1 root → 0.03 tip); step 0.8,
MAX_STEPS 128; exact textureLoad C (short HDR light-wake 0.45); A = HDR linear + semantic alpha; depth near 1 / miss 0;
ACES(col*1.4) replaces Reinhard+gamma; fresnel pow base clamped.
SDF SANITY (numpy port, scratchpad medusa_check.py): map(camera) 2.6-3.8 > 0 at defaults, all slider extremes and
mouse orbit extremes; 13-29% of a 40² view hits body; 69/991 hits land on lantern cores.
REFUSED: none. Screen orientation kept (bell low, tentacles up).

STATUS: final
