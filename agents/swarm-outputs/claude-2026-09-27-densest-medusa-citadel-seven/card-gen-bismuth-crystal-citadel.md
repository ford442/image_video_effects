```
SHADER: gen-bismuth-crystal-citadel
IDENTITY: a camera rises through a twisting six-fold tower of hollow bismuth boxes repeating every 4 units vertically,
  with stepped terracing and iridescent metallic shading.
KEEP VERBATIM: twist (L61-64), vertical repeat (L66-67), six-fold angular fold (L69-77), hollow box d1/inner_hollow
  (L85-94), crystal slab d3 (L97-103), iridescence palette (L37-39, L221-229), rising camera, 4 slider roles
  (x terrace step size, y ascension speed, z metallic shine, w iridescence shift), saved params.
FIX/WIRE (major first):
  - HEAD BLANK: d2 = sdBox(p - pStep, 0.45s) - 0.05 over a grid repeating through ALL space. Worst in-cell distance is
    0.0866*s - 0.05 < 0 for every s < 0.577 (slider range s = 0.1..0.6, default 0.35) -> map < 0 everywhere, march
    stops at t=0, calcNormal(p)=normalize(0)=NaN. Fix: confine terraces to the tower — e.g. d2 = max(d2 - 0.05*?,
    d1 - shellMargin) or intersect with a band around d1's surface, so terraces step the tower walls only. Verify with
    a numpy port of map(): map(camera) > 0 and a surface exists in view, for s in {0.1, 0.35, 0.6}.
  - Camera: ro at z=-5 on the axis inside a six-fold ring of boxes at radius ~2 — check map(ro) > 0 after the fix.
  - Mouse dead: L149-150 divide 0..1 zoom_config by dims; L170 overwrites the rotated rd. Make mouse orbit/tilt the
    look-at camera; default mouse reproduces the HEAD camera path.
  - speed = y*(1+mids*0.5); time = config.x*speed (L139, L145) -> ~60-unit camera jumps with music. Phase from time*y;
    audio modulates something else.
  - AO constant 0.5 (L250) -> real few-tap AO along the normal. Alpha >1 at L263 -> clamp.
  - Depth inverted (L279) -> near 1, miss 0. ACES on writeTexture only (replace x/(1+x)+gamma). Write A (HDR + alpha);
    read C exactly (a thin rising-trail is optional, not an idea).
  - Canonical header (was 5-line banner); JSON: drop false "fractal" tag, add true features.
ADD (native ideas):
  1. Melt-pool bands between tiers — tiers are boxes ±1.5 in a period of 4, leaving 1-unit gaps: fill each gap level
     with a glowing molten-bismuth pool (emissive band/plane in the gap, rippling surface), since bismuth crystals grow
     out of a cooling melt. The pools light the underside of the tier above.
  2. Axial beacon reflections — revive the declared-but-unused metalFresnel and IOR_BISMUTH: reflect(rd, n) is traced
     cheaply (analytic) against a light column on the tower axis and the melt bands, so every metallic face mirrors the
     beacon and the pools with Schlick metal Fresnel (L213, L236, L241).
FORBID: hopper terraces (any form), oxide thin-film/tarnish/zoning, twin seams, terrace-lip glints/emissive, riser
  rainbow film, containment flux lines, escapement flash, photon-ring sheen, self-assembling sectors, time dilation,
  singularity shadow, spring cursor.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha.
DEFAULT-LOOK SHIFT: HEAD is a flat/NaN frame at every slider value; now an actual citadel. Not GPU-verified.
```

STATUS: draft (coordinator)

## Final (implementer, 2026-09-27)

Audit claims verified against HEAD — all TRUE:
- Blank frame: numpy port of HEAD map() gives map(camera) = -0.041 / -0.025 / -0.008 at x = 0 / 0.5 / 1 and every ray stops at t = 0
  (rounded terrace cubes, 0.45*s + 0.05, overlap their 0.5*s cells for every s in 0.1..0.6).
- Mouse dead (0..1 mouse / pixels; L170 overwrote the rotated rd). Camera jumps from time*(1+mids). AO const 0.5.
  Alpha > 1 for Metallic Shine > ~1. Depth inverted. No A write / C read. Also: HEAD uv.y was not flipped (image upside-down) — flipped now.

FIX (floor): terraceSd() keeps the pStep grid + 0.45*stepSize cubes but only grows cubes on cells whose centre is within
  stepSize*(0.1+0.25*hash31) of the wall (hash31 was unused at HEAD); 2x2x2 neighbour cells checked, 0.52*s fallback bound,
  far-field bound dw - 1.2*s. Camera: mouse x = orbit, mouse y = tilt; mouse (0.5,0.5) = HEAD path exactly. Phase = clock*y.
  Real 5-tap AO; alpha clamped; depth near 1 / miss 0; ACES on display only; mouse lamp now follows the pointer in camera space.
  JSON: dropped false "fractal" tag; features = upgraded-rgba, audio-reactive, mouse-driven. params byte-exact.
Numpy check (scratchpad bismuth_port.py): map(ro) in 1.12..1.88 for x in {0,0.5,1}, y in {0,0.5,2}, 3 clocks, 4 mouse
  positions; 47-74% of rays hit, 1-13% hit a melt pool, 0 stalled rays; SDF bound violations <= 0.05% of random steps (fold seams, HEAD).

Ideas as implemented:
  1. Melt-pool bands — poolSd/meltColor L105-119, in map L188-192, pool shading L306-311, underlight L348-356, pools in
     reflections poolSeen L137-149. Discs r < 2.9 at every gap plane (|ly| = 2), rippling; undersides of tiers lit from below.
  2. Axial beacon mirrored by metal Fresnel — axisApproach/beaconGlow L121-135; metalFresnel with IOR_BISMUTH dielectric floor
     L300-303 (both were declared-unused at HEAD); diffuse + mirrored beacon/pools L358-369; direct column through gaps L383-386.
Audio (not an idea): bass -> melt glow + metallic (HEAD), mids -> pool ripple amplitude, treble -> iridescence (HEAD).
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha; C read exactly and blended 15% (light rising trail).
Refused/skipped: none of the card; no ripples/spring added (HEAD had none).
DEFAULT-LOOK SHIFT: HEAD blank at all slider values; now the twisting hollow-box tower with studded walls, orange melt bands
  between tiers and a pale blue axial beam. Not GPU-verified.

STATUS: final
