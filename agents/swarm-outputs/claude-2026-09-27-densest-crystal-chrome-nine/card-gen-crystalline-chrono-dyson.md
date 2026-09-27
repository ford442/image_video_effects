```
SHADER: gen-crystalline-chrono-dyson
IDENTITY: a raymarched Dyson sphere seen from a mouse-orbit camera — crystal panels on a radius-2 shell (Worley-modulated
  fract panels), a domain-warped FBM quasar core, KIFS box fractal, torus conduit, an octahedron satellite and radial
  capsule spokes, with Fresnel/Beer-Lambert shading, fog, chromatic feedback and click rings.
KEEP VERBATIM: shell + panel construction (L133-138), quasar FBM core (L140-141), KIFS box (L124-131), torus conduit
  (L143), smooth-union chain (L152-158), shading family (L192-209), feedback with dispersion (textureLoad C), click
  rings (HEAD — keep, not an idea), ACES on display, depth, 4 slider roles (x panel_density, y quasar_glow, z flux_speed,
  w swarm_count), saved params.
FIX/WIRE:
  - uv not flipped (L172) though L175 claims screen-top = +Y -> flip.
  - Pole NaN: mouse y = 0 or 1 -> my = +-pi/2, ro parallel to up, cross()=0 -> normalize(0) NaN (L179). Clamp pitch.
  - Spokes (L149-151): sector angle folded but q never rotated into the sector; both capsule endpoints take q.y ->
    unbounded in y, sheets not spokes, non-Lipschitz seams. Rotate into sector, bounded capsule quasar->shell.
  - t = time*flux (L119) phase jump on slider move -> document or use accumulation-free alternative.
  - Full t += d (L189) through non-Lipschitz map (fract panels, noise added to distances) -> relaxation factor.
  - Dead kifsFold (L89) — may use in an idea or delete; volumetricFog ignores p/ro (L110) — fix or note.
  - Miss background hash3(rd).x static noise (L210) -> sparse stars (hash thresholded) is fine as floor.
ADD (native ideas):
  1. Statite swarm — Swarm Count (w) today only makes depth stripes sin(t_hit*swarm) (L209). Replicate the single
     octahedron satellite (L145-147) into w-count statites riding the conduit orbit by polar repetition (one SDF
     evaluation per sample, not a loop of 100), with a golden-ratio (PHI already at L146) phase spread and inclination.
     The slider now counts a swarm. Keep the stripes if they still read, or retire them into the statites (explain).
  2. Power-grid pulses — once spokes are real capsules, return the capsule parameter h (sdCapsule L94) and send
     emissive packets outward quasar -> spoke -> torus conduit (and along the conduit), fusing three existing
     subsystems into one energy-harvest circuit; packet speed from flux_speed.
  3. (optional) Louvered panels — each Worley panel cell (w.y seam) opens/closes on its own phase, leaking quasar light
     through open louvres.
FORBID: Keplerian gearing, Doppler beaming, photon ring, ripple rings as idea, thin-film, spring cursor, IQ palette,
  Cauchy facet fire, time-fault seams.
A PACKING: clamped HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: image upright; spokes become 8 real spokes; statites around the conduit. Not GPU-verified.
```

STATUS: draft (coordinator)

## Final (implementer, 2026-09-27)

Audit claims verified against HEAD:
- uv not flipped: TRUE. At mouse (0.5,0.5) cu = (-1,0,0), cv = (0,1,0), and +uv.y is the lower screen half, so world-up was
  drawn at the bottom (a 180-degree roll, not a mirror). Flipped.
- Pole NaN: TRUE but narrower than stated. The pitch rotates about world X after the yaw, so ro is parallel to up only when
  sin(mx) = 0 AND cos(my) = 0 (e.g. mouse (0.5, 0) or (0.5, 1)). Pitch clamped to +-1.45 rad.
- Spokes: TRUE. The folded angle was never applied to q, and q.y fed both capsule ends, giving unbounded, non-Lipschitz sheets.
- t = time*flux phase jump: TRUE. Kept and documented (L115-117). extraBuffer[133..] is zeroed each frame, so an
  accumulator can't persist.
- Non-Lipschitz march: TRUE, and there is a concrete unit bug. The plate SDF was in fract-cell units, so it
  over-reported distance by x density (4x at default). Divided by density (zero set unchanged) + 0.9 step relaxation.
- kifsFold dead: TRUE, deleted. volumetricFog ignores p/ro: TRUE, left verbatim (noted only).
- Miss background per-pixel hash static: TRUE, replaced with sparse fixed stars.
- No double tone-map. A = clamped HDR, C is read exactly and blended pre-ACES, so the history is consistent. Audio comes from
  plasmaBuffer[0]. Ripples use age only, never .w. Depth is near 1 / miss 0. All of this is fine at HEAD.

Ideas as implemented:
  1. Statite swarm: statiteSd L132-158 (polar repetition, nearest + same-side neighbour cell only; cell 0 is the HEAD satellite
     exactly, the rest are golden-phased in height/radius, sized to arc spacing), in map L220-221, sail shading L287-292
     (HEAD cyan, core-facing faces lit by the quasar x Quasar Glow). Swarm Count now counts statites (10..100). The HEAD
     depth stripes sin(t*swarm) were fake drones and are retired into them.
  2. Power-grid packets: gridGeom L160-179 (8 real spokes quasar(0.5) to conduit ring, capsule h kept as the path coordinate,
     conduit arc continues s from each junction), gridPacket L181-188 (comet packets, sharp leading edge, per-spoke golden
     phase, drain round the ring, speed via Flux Speed clock), halo line-integral in the march L261-263 + L306-307,
     surface emission L293-296. Fuses quasar + spokes + conduit into one circuit.
  3. Louvred panels: louvreOpen L125-130, plate tilt in map L206-207 (open = 0 is the HEAD plate), core-light throw on
     open plates L297-300.
Audio (not an idea): HEAD roles unchanged (bass conduit radius/fog/pulse, mids spoke radius/KIFS, treble KIFS/statite size).
A PACKING: clamped HDR linear RGB (pre-ACES) + semantic alpha (HEAD; alpha adds min(gridGlow,1)*0.2).
JSON: params/updatedParams byte-exact. Added features mouse-driven and upgraded-rgba. Kept the true pre-existing tags. No idea tags added.
Gates: naga OK; precommit gate pass; dead-slider audit scanned 1305 defs, file not flagged, x/y/z/w all read (L118,137,192,271,299,307).
Numpy port (scratchpad gen-crystalline-chrono-dyson/port.py, 128x72, audio 0, swarm 10/50, 3 mouse incl. pole, 2 clocks):
  map(ro) 1.6..2.9 (camera outside geometry), 0 NaN, hit 12-17%, <=6 stalled rays of 9216. Statite hits 0.9-3%, grid
  surface 0.6-2.4% (0.2-0.7% packet-lit), shell 6-11%, of which open louvres 1.5-3.9%. Halo peak ~0.1-0.19 x 5 = ~0.5-0.95 HDR.
Refused/skipped: none of the card; no fog rewrite (would be a new idea); no ripple/spring changes (HEAD click rings kept).
DEFAULT-LOOK SHIFT: image is now upright. The 8 spokes are real radial tubes carrying amber packets. 50 small statites ring the
  shell instead of one satellite plus cyan depth stripes. Some shell plates tilt open. The background is sparse stars instead of
  static. Not GPU-verified.

STATUS: final
