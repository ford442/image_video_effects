# Blackbody Phase-C leftover six — Idea Cards

Written **before** any WGSL edit, per `docs/SHADER_UPGRADE_BATCH.md` §2.

Family: uncarded April 18, 2026 `spec-blackbody-thermal` hybrids. Two native
ideas each. Identities kept. Planck + the shared circular ember-glow loop is
the floor look, not the upgrade. No spring+ripple+IQ stamp.

Skipped (already carded): `bioluminescent-blackbody` (09-12),
`gen-astro-orrery-blackbody` (Batch 42), `thermal-touch-blackbody` (Batch 43),
`spec-blackbody-thermal` (Batch 50), Codex `honey-melt-blackbody` /
`melting-oil-blackbody`.

Skipped (later four, radial-warp / BH siblings): `warp-drive-blackbody`,
`hyper-space-jump-blackbody`, `gamma-ray-burst-blackbody`,
`gen-singularity-forge-blackbody`.

Skipped globally: tropism-rich `mycelium-network`, physarum `extraBuffer[0..]`
agents, `crt-clear-zone` (idea-rich May 2026), liquid-small (Batch 51/58B).

---

SHADER: thermal-vision-blackbody
IDENTITY: FLIR-style luma→Planck thermal camera with a mouse heat disk
KEEP VERBATIM: Temperature Low / Temperature High / Sensor Contrast / Color Shift;
  luma pow-contrast; mouse-down heat disk; existing 12-tap bright bloom
ADD (2 native ideas):
  1. NUC/scanline banding — row-correlated sensor noise plus thin periodic
     calibration bars; this is a thermal camera, not a nebula
  2. hot-object lag from exact C — A already stores Kelvin in `.a`; previous T
     decays slowly so hot spots persist like a FLIR
FORBID: extraBuffer springs; IQ palette; replacing the camera with CRT scanlines
A PACKING: raw thermal RGB + normalized T in `.a`; ACES on writeTexture only

---

SHADER: chroma-kinetic-blackbody
IDENTITY: mouse-radial RGB split whose luma also tints Planck
KEEP VERBATIM: Effect Strength / Effect Radius / Luma Influence / Rotation;
  rotated mouse-dir split; R/G/B channel samples
ADD (2 native ideas):
  1. λ-scaled R/G/B offsets — same split axis, wavelengths 1.0 / 0.82 / 0.68
     so the kinetic prism is spectral, not equal RGB
  2. split boost from previous-frame luma delta (exact C) so motion reads as
     kinetic; write A so C exists next frame
FORBID: springs; stealing rotation into glowAmount; another circular ember ring
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: energy-shield-blackbody
IDENTITY: hex-cell energy barrier, mouse/ripple heat, cyan trail
KEEP VERBATIM: Hex Scale / Ripple Speed / Impact Strength / Decay; hexDist grid;
  click ripples as heat; trail in A.r
ADD (2 native ideas):
  1. discrete hex-cell strikes — `hash(hexCenter)` whole-cell on/off radius,
     not a smooth disk painted across cell interiors
  2. edge current — glow on `hexDist` edges, cooler fill, so the mesh reads as
     a Faraday cage not a heatmap overlay
FORBID: extraBuffer springs; cloning hex-voronoi from the hybrid lattice ten;
  another circular ember ring; filtered C
A PACKING: raw trail scalar in A.r (do not ACES). Exact `textureLoad` on C.

---

SHADER: stellar-plasma-blackbody
IDENTITY: domain-warped FBM nebula with energy→Planck cores
KEEP VERBATIM: Temperature Shift / Evolution Speed / Zoom Scale / Thermal Intensity;
  q/r domain warp; held-mouse hotspot
ADD (2 native ideas):
  1. filaments along `|∇f|` — magnetic ridges on the existing FBM, not another
     glow ring
  2. warp-advected C heat — previous raw T/thermal follows the existing `r`
     warp vector so the nebula persists
FORBID: `u.config.yzw` as audio (those are click count / resolution);
  extraBuffer springs; cloning the 12-tap ember overlay
A PACKING: raw thermal RGB + normalized T; early `dist>3` return must write A

---

SHADER: sim-heat-haze-blackbody
IDENTITY: convection temperature field, ground/source/mouse heat, buoyancy
  refraction of the photo
KEEP VERBATIM: Temperature Intensity / Convection Speed / Distortion Strength /
  Heat Source Count; 3×3 diffuse + 0.98 cool; exact C temperature; ground heat
ADD (2 native ideas):
  1. Schlieren streaks along existing `∇T` — knife-edge density, haze not just
     a Planck overlay
  2. plume shear — horizontal lean from `dT/dy` so plumes tilt, not only
     `-newTemp` upward
FORBID: ACES on stored T; writing temperature into depth; extraBuffer springs;
  another circular ember ring
A PACKING: raw temperature in A.r (already honest exact C)

---

SHADER: encaustic-wax-blackbody
IDENTITY: FBM wax thickness, mouse melt, thick pools glow Planck, thin glaze
  shows the photo through amber
KEEP VERBATIM: Wax Thickness / Surface Texture / Melt Radius / Thermal Intensity;
  5×5 weighted blur; height-field specular; wax_alpha
ADD (2 native ideas):
  1. cooling skin — high-frequency `waxDetail` is cooler than valleys (real
     encaustic crust)
  2. iron/brush ridges along the existing height-field tangent (tool marks,
     not a circular glow)
FORBID: storing `melt_thickness` in writeDepthTexture; extraBuffer springs;
  the shared 8-tap photo-luma ember loop (not wax-native)
A PACKING: ACES display RGBA (HEAD did not write A); pass through scene depth
