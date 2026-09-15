# NOTES — Blackbody / Thermal Eight (2026-09-15)

Batch: 8 shaders, one native family (blackbody thermal). Two native ideas
each. Identities kept. No new springs. No IQ palettes. No shockwaves.

## Per shader

### spec-blackbody-thermal (root canonical grade)
- Kept verbatim: temp ranges, intensity/glow params, blackbodyColor +
  radiance, isotherm rings + ember filaments, held mouse heat, u.ripples
  click fronts, ember persistence C read, 16-ring glow, ACES, raw-HDR A.
- Added: (1) depth-conductive pointer heat (near conducts 1.25×, far 0.45×;
  `sceneDepth` read once, reused for the depth write); (2) Wien-fringe edges
  (luma-gradient magnitude tints hot edges blue / cool edges red).
- A packing: raw thermal HDR rgb + tempNorm alpha (HEAD packing; alpha was
  already clamped).
- JSON already carried upgraded-rgba/audio-reactive; WGSL header now names
  Ideas + packing (was tag-without-ideas drift).

### chroma-kinetic-blackbody
- Kept verbatim: strength/radius/luma_inf/rotation params, radial+rotated
  split, luma-modulated falloff, blackbody grade, glow, 0.6 blend.
- Added: (1) heat-driven split width (tempNorm scales offset 0.6–1.5×);
  (2) gradient-axis split (axis blends 45% toward local luma-gradient dir).
- Floor: dataTextureA write added (HEAD never wrote A); alpha clamped;
  two trivial `if`s → select. JSON += mouse-driven, upgraded-rgba,
  updatedParams.

### thermal-vision-blackbody
- Kept verbatim: temp_low/high + contrast + shift params, contrast pow,
  aspect-corrected mouse heat, 12-tap ember glow, hash grain, ACES.
- Added: (1) isotherm contour bands (9 quantized bands + 9000K edge lines);
  (2) NETD grain (0.05 cold → 0.008 hot amplitude).
- Floor: tempNorm alpha (HEAD hardcoded 1.0). JSON += upgraded-rgba,
  updatedParams.

### thermal-touch-blackbody
- Kept verbatim: heat/radius/ambient/blend params, mouse + click fronts,
  buoyancy/sway history streaks from exact C, ambient blend, audio, ACES.
- Added: (1) conduction halo (wide 3×-radius gaussian at 0.35×);
  (2) cooling-ember streak tint (history cools toward deep ember red).
- Floor: heat alpha (HEAD hardcoded 1.0). JSON += upgraded-rgba (params
  already aligned).

### stellar-plasma-blackbody
- Kept verbatim: temp_shift/speed/zoom/intensity params, q/r/f warp chain,
  energy→K mapping, 12-tap glow, hotspot, ACES.
- Added: (1) spectral-class banding (O–M anchor tints at 0.35 mix);
  (2) differential-rotation shear (twist ∝ 1/(dist+0.35)).
- Correctness: u.config.y/z/w audio lie (rippleCount/resX/resY) →
  plasmaBuffer[0].xyz (JSON already claimed audio-reactive — now honest);
  early-return path writes dataTextureA + depth; tempNorm alpha;
  branchless held-gate. JSON += upgraded-rgba, updatedParams.

### gen-singularity-forge-blackbody
- Kept verbatim: disk/jets/warp/dilation params, sdTorus marcher, fbm disk
  perturb, diskTemperature, jet/photon/ambient glow, ACES, exposure alpha.
- Added: (1) gravitational redshift (temp × mix(0.55,1,gravRed));
  (2) doppler beaming asymmetry (±22% orbital-velocity temp shift).
- Correctness: audioOverall = u.config.y (rippleCount) → plasmaBuffer bass.
  spaghettification = u.config.y KEPT (click-count wobble, pre-existing
  behavior, not audio). JSON += audio-reactive, upgraded-rgba,
  updatedParams.

### sim-heat-haze-blackbody
- Kept verbatim: temperature/convection/distortion/sources params, 9-tap
  diffuse + 0.98 cooling, ground/source/mouse heat, gradient refraction,
  raw-temp A packing with exact C reads.
- Added: (1) vorticity shimmer (diagonal-tap curl → perpendicular
  displacement); (2) mirage inversion band (near-ground hot mirror).
- Floor: thermalBlend alpha (HEAD ~0.9–1.0). JSON += upgraded-rgba,
  updatedParams.

### gamma-ray-burst-blackbody
- Kept verbatim: intensity/decay/ray/exposure params, 20-tap radial thermal
  sampling, ray mask, core glare, vignette, ACES.
- Added: (1) afterglow persistence (C-feedback decay; HEAD wrote A but never
  read C — the read purpose is new, packing stays display RGBA);
  (2) light-curve flicker (spiky ^6 pulse on core temp).
- Floor: glare-driven alpha (HEAD hardcoded 1.0; HEAD dist-alpha replaced —
  safe, C was unread). JSON += upgraded-rgba, updatedParams.

## Gates
- Naga (naga-cli 22.0.0, cargo-installed): 8/8 (heat-haze needed one fix:
  vorticity line ordered before `var displacement`; caught by naga).
- Precommit gate: 8/8 (bindgroup + workgroup + extraBuffer).
- extraBuffer audit: PASS (no new writes; batch writes none).
- Dead sliders: 0 new.
- Catalog: 1,367 / lists 1,367 / defs 1,380 unique — verify:catalog-counts
  passed, README already current.
- Jest + SKIP_WASM_BUILD=1 build: see closeout.
- Real-GPU visual QA: external (Cloud VM has no adapter).

## Follow-up
Remaining blackbody cluster (6): encaustic-wax, energy-shield, honey-melt,
hyper-space-jump, melting-oil, warp-drive — clean follow-up six.
