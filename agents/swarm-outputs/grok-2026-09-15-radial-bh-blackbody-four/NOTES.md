# Radial / BH blackbody leftover four — NOTES

Per-shader closeout. Cards in BRIEFS.md were written first.

Planck + the shared circular mouse-heat / engine-glow loop is floor, not the
upgrade. No file received a new center ember ring, extraBuffer spring, or IQ
palette.

## warp-drive-blackbody

- Kept verbatim: Intensity / Aberration / Brightness / Samples; radial sample
  loop; luma→temp; dual-use of `.z`/`.w` as brightness/samples AND temp ranges;
  engine-heat disk; mouse hotspot.
- Ideas in the diff:
  1. Alcubierre warp-bubble wall — `exp(-pow((distAspect - bubbleR)*16, 2))`
     thin annulus at a characteristic radius.
  2. bow/wake Doppler — B sampled toward mouse, R away; temperature and
     RGB weights follow `bowWake`.
- A packing: raw HDR RGB + `avgTemp/15000` in `.a`. ACES on writeTexture only.
  C not read.
- Floor: plasmaBuffer bass/mids/treble; UV clamp on aberration samples.
- No new spring.

## hyper-space-jump-blackbody

- Kept verbatim: Jump Strength / Low T / High T / Chromatic Spread; 24-tap
  streaks; luma-weighted accumulation; vignette.
- Ideas in the diff:
  1. Lorentz `gammaStretch = 1/sqrt(1-β²)` so offset grows toward the rim.
  2. Relativistic beaming (`mix(0.72, 1.48, inward)`); chromatic_spread on
     `dir_norm` (the `0.001 * f * dist` hack is gone).
- A packing: pre-ACES RGB + vignette alpha. Depth now passes through
  `readDepthTexture` (HEAD wrote `0.0`).
- Floor: plasmaBuffer. No new spring.

## gamma-ray-burst-blackbody

- Kept verbatim: Intensity / Decay / Ray Density / Exposure; 20-tap radial
  blur to mouse; dual-use of `.x`/`.y` as intensity/decay AND temp ranges.
- Ideas in the diff:
  1. Bipolar jet lobes — `pow(|cos(angle - jetAxis)|, collimation)` two
     opposite beams; `sin(angle * rayDensity)` survives only inside the lobe.
  2. Afterglow — `textureLoad(dataTextureC)` cools previous raw RGB by `.a`.
- A packing: HEAD ACES+dist lie → raw burst RGB + energy in `.a`. Semantic
  alpha from energy/jets/glare (HEAD hardcodes `1.0`).
- Floor: plasmaBuffer. No new spring.

## gen-singularity-forge-blackbody

- Kept verbatim: Disk Density / Jet Intensity / Gravity Warp / Time Dilation;
  torus SDF; 100-step march; mouse gravity on `rd`. `u.config.y` remains
  `spaghettification` (rippleCount).
- Ideas in the diff:
  1. Keplerian Doppler — `v_phi = (-p.z, 0, p.x)` dotted with `-rd`; approaching
     side hotter and brighter.
  2. Photon-ring caustic — thin `exp(-photonDist² * 90)` at `1.5 * horizonR`,
     distinct from the existing volumetric `1/|dBlackHole|` haze.
- Audio lie fixed: `audioOverall = u.config.y` → `plasmaBuffer[0].xyz`.
- A packing: ACES display RGBA. Depth pass-through. C not read.
- No new spring.

## Gates

- Naga / precommit: 4/4
- extraBuffer new violations: 0
- dead sliders: 0
- catalog: 1,367 (no new IDs)
- Jest: 689 pass / 6 fail = pre-existing WASM `bridge/api.js`
- SKIP_WASM_BUILD=1 build: green
- Real-GPU visual QA: external
