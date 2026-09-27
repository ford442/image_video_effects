```
SHADER: gen-crystalline-nebula-weaver-void-spider
IDENTITY: a raymarched crystalline spider (ellipsoid body + abdomen, legs) hanging on web threads and a lattice of
  web nodes, in front of a 2D fbm nebula, with march glow, click rings and A/C feedback.
KEEP VERBATIM: hash3/vnoise/fbm (L31-65), palette (L68) as HEAD's nebula colouring (not a new stamp), body/abdomen
  ellipsoids (L84-90), smin, displace concept (L110), calcNormal, hueClamp, aces on display, A=pre-ACES HDR with exact
  C read, ripple rings (HEAD, not an idea), 4 slider roles (x web_complexity, y gravity_distortion, z plasma_intensity,
  w void_depth), saved params/updatedParams.
FIX/WIRE:
  - Step exhaustion shaded as hit (L191, L239) -> require d < eps.
  - thread2 dot grid computed at p*2*wc but divided only by wc (L107) -> distance 2x too large; fix the scale.
    The grid fills all space and grazing rays exhaust steps — idea 1 gates it, also bound it.
  - displace() adds scalar vec3(fbm) (L112) -> only a (1,1,1) diagonal shift; make it a real 3D warp (vector fbm or
    gradient) or document; keep gravity_distortion as its amount.
  - uv not flipped (L155); light at +y lights from screen bottom -> flip uv, keep mouse consistent.
  - zoom_config.w unused while JSON claims a hold-lunge: optional (only if cheap: hold pulls camera in via void_depth).
ADD (native ideas):
  1. Nebula-condensed web nodes — gate the thread2 node grid by the SAME fbm density that paints the nebula (sampled
     at the node cell centre), so web nodes only exist where the gas is dense: the web crystallises out of the nebula,
     and the march glow accumulator (L179) makes the condensing nodes glow. Fuses the web and nebula subsystems.
  2. Metachronal eight-leg gait — replace the one mirrored box leg pair (L91-93) with four leg pairs placed by polar
     (angular) repetition around the body, each leg a two-segment capsule bent at a knee, lifted in alternating
     tetrapod phase (legs L1,R2,L3,R4 vs R1,L2,R3,L4) on a time phase; bass may scale stride amplitude, never phase.
     Makes the JSON's gait claim true.
  3. (optional) Spinneret dragline — thread1 is an infinite axial cylinder (L105): anchor it at the abdomen tip and
     let it sag under gravity_distortion (catenary-ish bend), so the spider hangs from its own silk.
FORBID: plucked standing-wave strings, dew beads, silk afterglow via C, agate banding, thread-tension sheen,
  over-under interlacing, thin-film, photon ring, lensed halo, spring cursor, IQ palette as a new stamp.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: image upright; exhaustion no longer painted as surface; web nodes clustered in nebula; 8 legs.
  Not GPU-verified.
```

STATUS: final (see Final section)

## Final (implementer, 2026-09-27)

Audit claims vs HEAD (numpy port in scratchpad gen-crystalline-nebula-weaver-void-spider/port.py, sweep.py):
- Step exhaustion shaded as hit: TRUE but slider-dependent. At defaults only 0.13% of rays exhaust; at web_complexity 5
  91% and at void_depth 4 99% of HEAD rays exhaust and were painted as surface. New: 0% at defaults, 23% at wc=5 (now nebula).
- thread2 distance 2x too large (scaled p*2*wc, divided by wc): TRUE — fixed (divide by 2*wc).
- displace() scalar vec3(fbm): TRUE (diagonal shift only) — now a per-axis 3D warp (3 x two-octave fbmLite rescaled to the
  4-octave mean, so the average offset matches HEAD); gravity_distortion stays its amount.
- uv not flipped: TRUE — flipped; mouse.y flipped with it so the dragged weaver still follows the pointer.
- Extra finding: HEAD's `+ fbm(p)*0.1` web bias (~0.047) exceeds both thread radii, so the web was never a surface, only march
  glow. Kept (it is the ethereal look). HEAD's axial thread1 ran down the view axis and read only as a centre dot.

FIX done: converged-hit flag (d < 0.001) drives shading, hitMask and depth (near 1 / miss 0); thread2 scale; 3D warp; uv flip;
  hold-lunge wired (zoom_config.w > 0.5 pulls the camera 30% closer — the JSON already claimed it).

Ideas as implemented:
  1. Nebula-condensed web nodes — sdNodes L171-196; node glow accumulator L290/L298-299; tinted by the pixel's nebula L340-342;
     alpha L366. Each lattice cell's node centre is projected through the camera and gated by the SAME fbm as the nebula
     (smoothstep 0.50..0.62); absent cells return the safe neighbour bound (1 - max|q| - rmax) and the lattice is bounded to a
     r=5 ball. Port: corr(nodeGlow, nebDens) = 0.53; mean node glow 40x higher in dense gas (>0.62) than in thin gas (<0.45).
  2. Metachronal eight-leg tetrapod gait — legAt/sdLegs L101-135, used in sdSpider L143-144. Angular repetition + x-mirror; own +
     nearest neighbour leg evaluated (other side's leg past the end sectors). Port vs brute-force 8 legs: overestimate >0.05 in
     0.01-0.05% of points (1-sector version was 11%). Bass scales stride only.
  3. Spinneret dragline — sdDragline L153-169 (replaces thread1): 4-capsule parabola from the abdomen rear to an off-frame
     upper-left anchor, sag = gravity_distortion * 1.6.
Audio (not ideas): bass = abdomen pulse + stride amplitude + glow (HEAD), mids = nebula (HEAD), treble = web glint (HEAD) + node glow.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD); C read exactly, re-blended as HDR, ACES only on writeTexture.
Refused/skipped: none. Kept HEAD ripples as-is (not an idea). extraBuffer untouched.
JSON: params/updatedParams byte-identical (asserted); features + upgraded-rgba, mouse-driven; description rewritten honestly
  (HEAD claimed a spring cursor that never existed).
Gates: naga OK; wgsl_precommit_gate pass; audit_dead_sliders PASS (1305 defs scanned, 0 new dead); all 4 zoom_params read.
DEFAULT-LOOK SHIFT: image upright; spider has 8 thin jointed stepping legs instead of two vertical bars (hit area 8.7% -> 5.2%
  of frame in the port); march haze now clumps into glowing nodes over dense nebula; a sagging silk strand to the upper left.
  Cost: ~1.75x vnoise per map step vs HEAD. Not GPU-verified.

STATUS: final
