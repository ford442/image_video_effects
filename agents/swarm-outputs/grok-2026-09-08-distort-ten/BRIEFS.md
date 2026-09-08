# Distortion / warp ten — Idea Cards (written before WGSL)

Family: quieter geometric warps after the 2026-09-08 convolution tens. Native ideas on the existing displacement. No spring+ripple+IQ stamp. Springs kept only where HEAD already owned them (`pixel-storm` eye).

---

SHADER: sine-wave
IDENTITY: multi-frequency sine interference that displaces the photo, with mouse as a wave source
KEEP VERBATIM: amplitude / speed / scale / chroma_detail; packet envelopes; click fronts; crest CA; A = offset.xy, crest, alpha
ADD:
  1. Standing-wave nodes — concentric node rings around the pointer (waves, not a new motif)
  2. Stokes second-order drift — mass-transport offset along the crest, not just first-harmonic displace
FORBID: springs, IQ palettes, replacing sine waves with a liquid solver
A PACKING: telemetry (offset.xy, crest, alpha) — HEAD packing kept

---

SHADER: parallax-shift
IDENTITY: depth-layered mouse parallax; focus plane is a slider
KEEP VERBATIM: strength / layer-count from p2 / depthWeight / focus; multi-layer accumulate; mouse as origin
ADD:
  1. Occlusion peel — nearer layers outweigh farther ones (parallax, not a flat average)
  2. Focus-plane CoC — off-plane layers smear along the parallax ray
FORBID: springs, IQ palettes, replacing parallax with a hologram
A PACKING: ACES display RGBA (HEAD already wrote display A)

---

SHADER: perspective-tilt
IDENTITY: mouse yaws/pitches a 3D image plane; distance and plane scale stay the camera
KEEP VERBATIM: tilt_sensitivity / distance / pitch_enable / plane_scale; ray–plane intersect; mouse yaw/pitch
ADD:
  1. Vanishing falloff — farther hits (large t) dim like perspective aerial fade
  2. Grazing Scheimpflug — near-parallel rays soften (incidence, not a DoF toy)
FORBID: springs, IQ palettes, replacing the plane with a fractal
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: interactive-rgb-split
IDENTITY: mouse-localized chromatic split, radial or directional by mode
KEEP VERBATIM: strength / falloff / mode (rad vs dir) / angle; single displacement field; ripple perturb
ADD:
  1. Wavelength-scaled split — R/G/B sample along the existing offset (the name)
  2. Lateral vs longitudinal mix — directional mode stays lateral; radial keeps longitudinal
FORBID: springs, IQ palettes, dropping the two modes
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: radial-rgb
IDENTITY: Brown barrel/pincushion lens with anamorphic stretch and dispersion
KEEP VERBATIM: k1 / k2 / anamorphic / dispersion; lensDistort; anamorphic Y
ADD:
  1. Radial chromatic — R/B at slightly different k1 (lens CA, not a costume)
  2. Mustache k3 — r^6 Brown term on the same polynomial
FORBID: springs, IQ palettes, replacing the lens with a prism scene
A PACKING: ACES display RGBA (HEAD already wrote display A; B diagnostics kept)

---

SHADER: elastic-surface
IDENTITY: spring-mass membrane; A stores displacement+velocity; mouse push/pull
KEEP VERBATIM: elasticity / tension / wave_speed / depth_influence; Hooke + Laplacian; A = disp.rg, vel.ba
ADD:
  1. Poisson contraction — stretch squeezes perpendicular to the displacement
  2. Exact-load membrane — neighbors from integer C (the sim is history, not a filtered sample)
FORBID: springs in extraBuffer, IQ palettes as the upgrade, ACES into A
A PACKING: raw sim (disp.xy, vel.xy) — HEAD packing kept; display ACES on writeTexture only

---

SHADER: vortex-distortion
IDENTITY: Lamb-Oseen swirl + Kelvin-Helmholtz at the core; mouse and click vortices
KEEP VERBATIM: circulation / viscosity / khAmplitude / aberration; lambOseen; KH m=6; A = vel.xy, vorticity, speed
ADD:
  1. Streamline smear — a few taps along velocity (fluid advection, not a new solver)
  2. Source-tied vorticity — overlay keeps photo luma so the picture is still the photo
FORBID: extraBuffer springs, IQ palettes, rewriting as Rankine-only (that's vortex-warp)
A PACKING: raw field (vel.xy, vorticity, speed) — HEAD packing kept; display ACES on writeTexture only

---

SHADER: chromatic-swirl
IDENTITY: mouse-centered swirl with R/G/B split; animate toggles motion
KEEP VERBATIM: swirl_strength / radius / aberration / animate; percent^2 angle; held doubles; A telemetry
ADD:
  1. Angular chromatic — R/G/B rotated by different angles (swirl CA, not radial split only)
  2. Animate as continuous spin — when animate is on, angle advances with time, not a sin pulse
FORBID: extraBuffer springs, IQ palettes, replacing swirl with a kaleidoscope
A PACKING: telemetry (dist/radius, angle, aberration, alpha) — HEAD packing kept

---

SHADER: infinite-zoom
IDENTITY: iterated Möbius / hyperbolic zoom that tiles the photo
KEEP VERBATIM: zoom_speed / distortion / rotation / max_iterations; mobius_transform; hyperbolic_mobius
ADD:
  1. Mouse as Möbius pole — pointer owns coefficient c (aim the zoom, still Möbius)
  2. Log-polar seam — wrap in log-radius instead of fract (seamless cycle)
FORBID: springs, IQ palettes, replacing Möbius with a Mandelbrot
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: pixel-storm
IDENTITY: mouse-eye wind blows pixels; trail smears history; held reverses to a suck
KEEP VERBATIM: strength / chaos / trail / radius; spring eye in extraBuffer[133..138]; held reverse; sector FFT
ADD:
  1. Luma debris — brighter pixels travel farther (storm debris, not uniform wind)
  2. Exact-C advection — history is integer C at the source cell, not a filtered sample
FORBID: new springs, IQ palettes, replacing wind with a fluid solver
A PACKING: ACES display RGBA (HEAD stored display history; keep display in A)
