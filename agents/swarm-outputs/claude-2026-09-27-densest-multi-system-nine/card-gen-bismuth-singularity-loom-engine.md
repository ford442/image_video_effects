```
SHADER: gen-bismuth-singularity-loom-engine
IDENTITY: a ring of six carved bismuth cubes around an invisible lensing point, cosine palette on n·v, blue proximity
  glow, trails.
KEEP VERBATIM: angular repeat, pointer twist/pitch, base box + subtraction loop form (0.5/scale fold, 0.6/scale cut,
  0.1 rad (1,1,1) turn, x1.3 scale), step-wise lensing pull, proximity glow, step-count AO, cosine palette on n.v,
  FFT flux veins, click rings, gravitational-memory feedback (persistence formula), hit depth, 4 slider roles
  (Mass x / Iterations y [i32 1..10] / Iridescence z / Extrusion w), saved params. Inert extraBuffer[133..138] spring
  left in place (engine zeroes it per frame, so sm == raw pointer) and noted in the header.
ADD (native ideas):
  1. Self-assembling sectors (WGSL L113, L134-163) — sector id from the angular repeat; each cube runs its own
     golden-angle-phased assembly clock and carves to a fractional stage = Iterations * [0.38..0.76]; the stage's
     last cut grows in continuously (sub_box + (1-carve)*0.6/scale). Six cubes are at different stages (seed block ->
     terraced shards -> dust). Makes the description's "continually self-assembling" true.
  2. Gravitational time dilation (L43, L85-101, L122-125, L235-237) — tau = sqrt(1 - rs/r); twist AND assembly clock
     run on proper time t - 25s*(1-tau): core-facing sides of each cube lag (bounded static shear; the carve front
     sweeps outward from the core). r floored at 2.5 rs to keep the SDF Lipschitz (measured |grad| >1.5 in 0.09% of
     samples vs 0.06% for HEAD). Fringe frequency redshifted by tau at the hit point (bands broaden near the core).
  3. Singularity shadow (L188-222, L333-347) — segment closest-approach test inside the lensing loop; rays that pass
     inside rs (same rs as idea 2, from Mass) are captured -> black, soft graze fade to 1.35 rs, trail memory also
     swallowed, horizon alpha = 1. No photon ring / sheen.
FIX/WIRE:
  - HEAD SILENT BUG (major): at audio 0 the lattice is carved away entirely — numpy port of map() over a 121^3 grid:
    min SDF = +0.095 at Iterations 5 (> 0 for every Iterations value at ext = 0). HEAD shows only the blue glow haze;
    the crystal appears only when bass*w > ~2.05. So "reproduce HEAD at w=1, audio 0" would mean an empty scene and
    make every geometric idea invisible at audio 0 -> refused. Extrusion now = bass*w*0.4 + min(0.2+0.5*stage, 2.1) *
    (0.75+0.25*w): rest extrusion rides the assembly stage, w scales it (w=0 sparse shards, 1 default, 3 dense).
  - Camera-inside-SDF: map(ro) at HEAD's z=-5 goes to -0.04 (pointer corners, bass*w=3) and -0.18 with solid stages.
    Camera moved to z=-6.2, focal 1 -> 1.24 (same framing at the origin): worst map(ro) over pointer corners,
    Iterations {1,3,5,10}, w {0,1,3}, audio {0,1}, mass {0,1}, t in [0,400] = +0.85.
  - ACES on display only (was col/(1+0.12col) re-applied to fed-back colour every frame).
  - A = HDR linear RGB + semantic alpha; C decoded as HDR (no double bound).
  - Semantic alpha: hit = mix(0.9,1,AO), veil off-surface, horizon opaque.
  - Header: dropped "treble sparkle", "spacetime-flexing shocks", "persistent spring" claims.
FORBID: hopper terraces, oxide thin-film, twin seams, terrace lips, flux lines, escapement flash, spring singularity lens,
  photon-ring oil sheen, beaming crescent, springs, ripples.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR trail memory; ACES only on writeTexture.
DEFAULT-LOOK SHIFT (GPU reviewer): HEAD default = dark blue haze with no crystal. Now: iridescent carved beams/shards
  filling much of the view (~60-75% coverage), the two near cubes split the screen at the centre seam (pre-existing
  sector seam, now more visible because neighbours sit at different stages), a black lensed hole at centre when not
  occluded. Bass densifies the lattice strongly. Slightly flatter perspective from the camera pull-back. Not GPU-verified.
```

STATUS: final
