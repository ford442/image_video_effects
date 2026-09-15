# Radial / BH blackbody leftover four — Idea Cards

Written **before** any WGSL edit, per `docs/SHADER_UPGRADE_BATCH.md` §2.

Family: remaining April 18, 2026 `spec-blackbody-thermal` hybrids after the
2026-09-15 Phase-C six. Two native ideas each. Identities kept. Planck + the
shared circular mouse-heat / engine-glow loop is the floor look, not the
upgrade. No spring+ripple+IQ stamp. No extra ember-glow ring.

Skipped (already carded this morning): `thermal-vision-blackbody`,
`chroma-kinetic-blackbody`, `energy-shield-blackbody`,
`stellar-plasma-blackbody`, `sim-heat-haze-blackbody`,
`encaustic-wax-blackbody`.

Skipped (already carded earlier): `bioluminescent-blackbody` (09-12),
`gen-astro-orrery-blackbody` (Batch 42), `thermal-touch-blackbody` (Batch 43),
`spec-blackbody-thermal` (Batch 50), Codex `honey-melt-blackbody` /
`melting-oil-blackbody`.

Skipped (idea-rich gravity/warp siblings — do not pad): `warp_drive` (Batch 56),
`hyper-space-jump` (alpha-physics), `gamma-ray-burst` (Batch 30), `black-hole` /
`gravity-well` (May), `gen-stardust-nebula` (06-06).

Skipped globally: tropism-rich `mycelium-network`, physarum `extraBuffer[0..]`
agents, `crt-clear-zone`, liquid-small.

---

SHADER: warp-drive-blackbody
IDENTITY: Alcubierre-style radial blur toward the mouse; warp speed maps to Planck temperature
KEEP VERBATIM: Intensity / Aberration / Brightness / Samples; radial R/G/B sample loop;
  luma→temp; dual-use of zoom_params.z/.w as brightness/samples AND temp ranges;
  existing engine-heat disk and mouse hotspot (floor look)
ADD (2 native ideas):
  1. warp-bubble wall — thin annular boost at a characteristic radius from the
     mouse; this is an Alcubierre bubble, not another center glow
  2. bow/wake Doppler — blue-shift samples toward the mouse, red-shift samples
     away, fused to the existing aberration axis
FORBID: extra circular ember ring; extraBuffer springs; IQ palette; stealing
  brightness/samples into new meanings
A PACKING: raw HDR RGB + avgTemp/15000 in .a; ACES on writeTexture only; do not
  start reading C

---

SHADER: hyper-space-jump-blackbody
IDENTITY: thermally colored jump tunnel of luma-weighted radial streaks
KEEP VERBATIM: Jump Strength / Low Temperature / High Temperature / Chromatic Spread;
  24-tap radial streaks; luma-weighted accumulation; vignette tunnel
ADD (2 native ideas):
  1. length-contracted streaks — Lorentz-like stretch so offset grows toward
     the rim (cinematic jump tunnel, not a uniform radial blur)
  2. relativistic beaming — inward (approaching) samples hotter/brighter, wake
     cooler; put chromatic_spread on dir_norm instead of the uniform
     `0.001 * f * dist` hack
FORBID: another engine-heat disk; extraBuffer springs; IQ palette
A PACKING: pre-ACES RGB + vignette alpha in A; ACES on writeTexture only.
  Depth: pass through readDepthTexture (HEAD wrote 0.0)

---

SHADER: gamma-ray-burst-blackbody
IDENTITY: mouse-centered GRB with thermal radial blur — a bipolar explosion, not a sunflower
KEEP VERBATIM: Intensity / Decay / Ray Density / Exposure; 20-tap radial blur to
  mouse; dual-use of zoom_params.x/.y as intensity/decay AND temp ranges
ADD (2 native ideas):
  1. bipolar jet lobes — two collimated opposite lobes on the existing atan2
     axis (GRBs are jets, not isotropic sin(angle * density) spokes)
  2. afterglow from exact C — previous burst energy cools in .a; write raw HDR
     before ACES so C is energy, not display
FORBID: extra center ember; extraBuffer springs; cloning warp-drive's bubble;
  hardcoded alpha 1.0
A PACKING: change HEAD's ACES+dist lie → raw burst RGB + energy in .a; ACES on
  writeTexture only. Semantic alpha from glare/jets.

---

SHADER: gen-singularity-forge-blackbody
IDENTITY: raymarched black hole + Keplerian torus disk + polar jets, Planck-colored
KEEP VERBATIM: Disk Density / Jet Intensity / Gravity Warp / Time Dilation;
  torus SDF; 100-step march; mouse gravity on rd. u.config.y as
  spaghettification (rippleCount) stays — do not steal it.
ADD (2 native ideas):
  1. Keplerian Doppler beaming on the disk — approaching azimuth hotter/brighter,
     receding cooler
  2. photon-ring caustic — thin ring near r = 1.5 * horizon, distinct from the
     existing volumetric 1/|dBlackHole| haze
FORBID: extraBuffer springs; IQ palette; replacing the march with a 2D glow
  overlay; using u.config.y as audio (that is rippleCount)
A PACKING: ACES display RGBA (HEAD never reads C; do not invent sim fields).
  Depth pass-through.
AUDIO LIE TO FIX: audioOverall = u.config.y is rippleCount. Drive
  audioReactivity from plasmaBuffer[0].xyz.
