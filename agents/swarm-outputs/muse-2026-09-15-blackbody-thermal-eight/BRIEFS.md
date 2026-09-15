# BRIEFS — Blackbody / Thermal Eight (2026-09-15)

Batch: 8 shaders, one family that already lives in the files — physically-based
blackbody thermal coloring (`blackbodyColor` + Stefan-Boltzmann radiance) fused
onto eight different base effects. No springs. No IQ palettes. No shockwaves.
Plumbing is the floor, not the upgrade.

IDs (all `shader_definitions/advanced-hybrid/*.json` present):
spec-blackbody-thermal, chroma-kinetic-blackbody, thermal-vision-blackbody,
thermal-touch-blackbody, stellar-plasma-blackbody,
gen-singularity-forge-blackbody, sim-heat-haze-blackbody,
gamma-ray-burst-blackbody.

Remaining blackbody cluster for a follow-up six: encaustic-wax-blackbody,
energy-shield-blackbody, honey-melt-blackbody, hyper-space-jump-blackbody,
melting-oil-blackbody, warp-drive-blackbody.

---

```
SHADER: spec-blackbody-thermal
IDENTITY (one sentence): luma-driven blackbody grade with isotherm contour
  rings, ember filament runners, held-pointer heat bloom, ember persistence,
  and click heat fronts.
KEEP VERBATIM: tempRangeLow/High + intensity/glow params; blackbodyColor +
  radiance; isothermRing + emberFilament; mouseHeat (held); u.ripples click
  fronts; prev-ember persistence read of C (rgb*a*15000); 16-ring glow;
  ACES display; A = raw thermal HDR + tempNorm alpha.
ADD (2 native ideas):
  1. depth-conductive ambient — near-depth pixels conduct mouse/click heat
     more strongly, far pixels stay cooler (readDepthTexture already bound;
     depth-aware tag already claimed). Belongs: thermal conduction through
     scene depth, not a new motif.
  2. Wien-fringe edges — luma-neighborhood temperature-gradient magnitude
     fringes hot edges blue and cool edges red (thermal-camera native).
FORBID on this file: springs, IQ palettes, new geometry/motifs.
A PACKING: raw thermal HDR rgb + tempNorm alpha (HEAD packing kept; alpha
  clamped to [0,1]).
```

```
SHADER: chroma-kinetic-blackbody
IDENTITY (one sentence): mouse-centered kinetic RGB split blended 60/40 with
  a blackbody thermal grade.
KEEP VERBATIM: strength/radius/luma_inf/rotation params; radial+rotated split
  offsets; luma-modulated falloff; blackbody grade; 16-ring glow; 0.6 blend.
ADD (2 native ideas):
  1. heat-driven split width — local normalized temperature scales the
     R/B split offset (hot pixels separate wider; thermal chromatic physics).
  2. gradient-axis split — split axis blends from radial toward the local
     luma-gradient direction (true lateral-chromatic behavior).
FORBID on this file: springs, click shockwaves, IQ palettes.
A PACKING: ACES display RGBA (HEAD never wrote dataTextureA — floor fix adds
  the write; C is unread history).
FLOOR: add dataTextureA write; clamp alpha to [0,1]; honest mouse-driven tag.
```

```
SHADER: thermal-vision-blackbody
IDENTITY (one sentence): thermal-camera view — contrast-shaped luma to
  temperature, mouse heat source, ember glow, microbolometer grain.
KEEP VERBATIM: temp_low/high + contrast + shift params; contrast pow; mouse
  heat (aspect-corrected); 12-tap ember glow; hash grain; ACES.
ADD (2 native ideas):
  1. isotherm contour bands — quantized temperature bands with bright edge
     lines (classic thermal-camera isotherm display).
  2. NETD temperature-dependent grain — grain amplitude higher in cold
     regions, cleaner in hot (real microbolometer behavior; replaces flat
     grain).
FORBID on this file: springs, click shockwaves, palettes.
A PACKING: ACES display RGBA (HEAD write kept; C unread).
FLOOR: meaningful tempNorm alpha (HEAD hardcoded 1.0).
```

```
SHADER: thermal-touch-blackbody
IDENTITY (one sentence): cursor as heat source on an artistic temperature
  field with buoyant history streaks, click heat fronts, audio wobble, and
  continuous original-image blend.
KEEP VERBATIM: heat/radius/ambient/blend params; mouseHeat + clickHeatFront
  (u.ripples); buoyancy/sway history streaks from exact C; ambient blend;
  audio modulation; ACES.
ADD (2 native ideas):
  1. conduction halo — wide faint secondary gaussian around the cursor so
     heat visibly conducts outward through the material.
  2. cooling-ember streak tint — history streaks shift toward deep ember red
     scaled by (1-historyHeat) instead of persisting white-hot.
FORBID on this file: extraBuffer springs (pointer is already direct),
  IQ palettes.
A PACKING: ACES display RGBA + tempNorm alpha (HEAD display write kept).
FLOOR: meaningful heat-driven alpha (HEAD hardcoded 1.0).
```

```
SHADER: stellar-plasma-blackbody
IDENTITY (one sentence): domain-warped FBM nebula whose energy maps to
  blackbody temperature — ember voids, blue-white cores, mouse hotspot.
KEEP VERBATIM: temp_shift/speed/zoom/intensity params; q/r/f warp chain;
  energy→800..15000K mapping; 12-tap glow; hotspot; ACES.
ADD (2 native ideas):
  1. spectral-class banding — temperature anchored through O/B/A/F/G/K/M
     stellar-class tint peaks (still blackbody, with class identity).
  2. differential-rotation shear — warp coords twisted by 1/(dist+eps) so
     the core rotates faster than the rim (accretion-native).
FORBID on this file: springs, generic neon palettes.
A PACKING: ACES display RGBA + tempNorm alpha (HEAD A write kept).
FLOOR (correctness, not ideas): u.config.y/z/w audio lie (rippleCount /
  resX / resY) → plasmaBuffer[0].xyz (JSON already claims audio-reactive);
  early-return path must write dataTextureA + depth; meaningful alpha;
  branchless mouse heat.
```

```
SHADER: gen-singularity-forge-blackbody
IDENTITY (one sentence): raymarched black hole + torus accretion disk with
  diskTemperature→blackbody coloring, blue-white jets, photon-sphere glow.
KEEP VERBATIM: disk/jets/warp/dilation params; sdTorus marcher; fbm disk
  perturb; diskTemperature; jet/photon/ambient glow; ACES.
ADD (2 native ideas):
  1. gravitational redshift — disk thermal color reddened/cooled toward the
     horizon by a 1/sqrt-style gravity factor (GR-native).
  2. doppler beaming asymmetry — approaching side brightened/blued,
     receding side dimmed/reddened via orbital-velocity temperature shift
     (relativistic-native).
FORBID on this file: springs, new geometry, palettes.
A PACKING: ACES display + exposure alpha (HEAD packing kept).
FLOOR (correctness): audioOverall = u.config.y lie (rippleCount) →
  plasmaBuffer bass + honest audio-reactive tag; header names ideas.
```

```
SHADER: sim-heat-haze-blackbody
IDENTITY (one sentence): raw temperature-field sim (diffuse / cool / ground
  + source + mouse heat) driving gradient refraction and blackbody glow.
KEEP VERBATIM: temperature/convection/distortion/sources params; 9-tap
  diffuse + 0.98 cooling; ground/source/mouse heat; gradient refraction;
  A = raw temperature field (C .r reads kept exact).
ADD (2 native ideas):
  1. vorticity shimmer — curl of the temperature gradient adds
     perpendicular displacement (convection turbulence, sim-native).
  2. mirage inversion band — near-ground hot layer mirrors the image
     vertically with strength ∝ groundHeat (real inferior-mirage optics).
FORBID on this file: springs, palettes, storing display color in A.
A PACKING: raw temperature field vec4(newTemp,0,0,1) (HEAD packing kept).
FLOOR: alpha thermalBlend-driven (HEAD ~0.9..1.0); header names ideas.
```

```
SHADER: gamma-ray-burst-blackbody
IDENTITY (one sentence): mouse-epicenter radial-blur burst with per-sample
  thermal tint, rotating rays, core glare, vignette.
KEEP VERBATIM: intensity/decay/ray/exposure params; 20-tap radial thermal
  sampling; ray mask; core glare; vignette; ACES.
ADD (2 native ideas):
  1. afterglow persistence — C-feedback exponential decay blend (GRB
     afterglows fade; also gives the orphaned dataTextureA a read purpose).
  2. light-curve flicker — core temperature pulsed by spiky banded noise
     over time (GRB prompt-emission spikes).
FORBID on this file: springs, u.ripples shockwaves (belong to click-led
  shaders; this one is epicenter-led), palettes.
A PACKING: ACES display RGBA + glare-driven alpha (HEAD dist-alpha
  replaced; C previously unread so no packing lie).
FLOOR: meaningful alpha (HEAD hardcoded 1.0); honest mouse-driven tag.
```
