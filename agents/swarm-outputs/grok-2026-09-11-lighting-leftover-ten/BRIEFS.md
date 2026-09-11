# Lighting leftover ten — Idea Cards (written before WGSL)

Family: leftover lighting / neon / volumetric shafts. Two native ideas each. Identities kept. No spring+ripple+IQ stamp. Click charges on `sim-volumetric-fake-em` kept.

Skipped: fireworks leftover six; `matrix_digital_rain`; aurora pass-2 graphs; optical/flare already idea-upgraded; `neon-pulse` / `neon-pulse-stream` (Batch 60/56); overlay-rich geometric leftovers; `fire_smoke_volumetric`; generative nebula/solar-flare.

Three Sobel files stay distinct: pulse-edge = direction-hue **tubes**; neon-edges = Mach + blackbody **isotherms** + inverse-square spotlight; edge-glow = **discharge sheath** + 60 Hz beat.

---

SHADER: neon-pulse-edge
IDENTITY: Sobel neon edges whose hue follows edge direction, with multi-layer bloom and a pulse
KEEP VERBATIM: edge_threshold / glow_radius / pulse_speed / color_cycle_rate; 3×3 Sobel; hsv from atan2(gy,gx); mouse proximity boost; plasma XYZ
ADD:
  1. Tangent tube glow — bloom samples along Sobel tangent, not an isotropic 8-tap ring
  2. Exact-C edge afterglow — textureLoad previous edgeMag so the halo is a trail, not a filtered sampler
FORBID: springs, click shockwaves, cloning neon-edges Mach/blackbody or edge-glow mercury spectrum
A PACKING: raw edgeMag / depth / gx / gy in A (not ACES). C is the previous edge field.

---

SHADER: sim-volumetric-fake-em
IDENTITY: mouse-charged fake god rays; E bends shafts; B splits RGB; click ripples spawn orbiting secondary charges
KEEP VERBATIM: light_intensity / em_distortion / chromatic_split / ripple_charge roles; electricField; magneticField; ripple orbit charges; radial blur toward light
ADD:
  1. Beer–Lambert dust along the already-bent sample path (exp(-opticalDepth))
  2. E×B lateral shaft bend — perpendicular kick from E and signed B, not only E-parallel
FORBID: new extraBuffer springs; dropping ripple charges; using config.y as audio
A PACKING: ACES display RGBA on every pixel. Mouse previous-pos in extraBuffer[133..134] only (single-writer at 0,0).

---

SHADER: sim-volumetric-fake
IDENTITY: fast radial-blur god rays from an animated light, with noise dust
KEEP VERBATIM: light_intensity / dust / scattering / noise_speed; animated lightPos; radial blur loop
ADD:
  1. Depth occlusion vs the light — a sample in front of the light (higher scene depth toward camera) kills the shaft
  2. Discrete dust motes on radial taps (hashed sparkle, not only smooth fbm dust)
FORBID: springs; cloning the EM sibling’s charges
A PACKING: ACES display RGBA (HEAD never wrote A or used C)

---

SHADER: volumetric-god-rays
IDENTITY: mouse-aimed radial shafts with density/decay/weight/exposure and Mie phase
KEEP VERBATIM: four params; 48-sample walk toward mouse; miePhase; bass dust; ACES display
ADD:
  1. Photo-luma occluder — dark samples along the march extinguish illuminationDecay
  2. Sun-disk core — bright disk at the mouse, gated by local highlight luma
FORBID: springs; replacing Mie with a different renderer
A PACKING: ACES display RGBA in A (HEAD stored raw accumulated RGB; C unused as color — switch and say so)

---

SHADER: neon-flashlight
IDENTITY: cursor cone that lights photo edges in neon
KEEP VERBATIM: held squeeze, click fronts, cone ribs, sweep; JSON params radius / intensity / threshold / ambient (remap WGSL to those roles)
ADD:
  1. Umbra vs penumbra — hard inner disk, soft outer ring
  2. Specular catch only on luma edges inside the cone
FORBID: new springs; treating existing click rings as the upgrade
A PACKING: ACES display RGBA (HEAD stored emission)

---

SHADER: neon-strings
IDENTITY: bank of plucked blackbody wires with traveling packets and click impulses
KEEP VERBATIM: stringCount / tension / intensity / coolRate; harmonics h1–h3; packet; clickImpulse; exact-C afterimage; blackbody
ADD:
  1. Standing-wave node darkening at 1/2, 1/3, 2/3 of string length
  2. Nut and bridge end-pins — cooler fixed ends with a small specular tick
FORBID: new springs; replacing the string bank with a particle field
A PACKING: ACES display RGBA (HEAD already stored display in A; C is color history)

---

SHADER: neon-edges
IDENTITY: multi-scale Sobel + Mach bands, blackbody tint, mouse spotlight
KEEP VERBATIM: edge_sensitivity / mach_strength / spotlight_radius / neon_gain; five scales; blackbodyRGB; existing tube-current wave
ADD:
  1. Inverse-square spotlight from the pointer (replace gaussian blob)
  2. Isotherm bands — quantize Kelvin so the tube shows discrete temperature steps
FORBID: cloning pulse-edge HSV tubes; new springs
A PACKING: HEAD packed edgeStrength/brightBand/temp/halo and never read C as color — switch to ACES display RGBA so C is honest history

---

SHADER: neon-edge-glow
IDENTITY: gas-discharge neon/mercury spectrum on photo edges, AC flicker, electrode sputter
KEEP VERBATIM: edgeStrength / glowRadius / neonTint / intensity; neonSpectrum + mercurySpectrum; mouse tube bend
ADD:
  1. Tube core + dark sheath — bright core line, darker glass envelope around it
  2. 60 Hz beat flicker as a squared-sine mains envelope (keep, make it the visible beat not extra random)
FORBID: cloning pulse-edge HSV; springs
A PACKING: HEAD packed edgeMask/flicker in A, C unused — switch to ACES display RGBA

---

SHADER: anamorphic-flare
IDENTITY: cinematic horizontal flare centered on the mouse
KEEP VERBATIM: JSON width / intensity / color / threshold mapped honestly; hex ghosts, central glow as supporting optics
ADD:
  1. Streak gated by photo highlight at the light (threshold slider is real)
  2. Blue-line ghost — a second horizontal streak offset on +Y, cyan-blue
FORBID: springs; IQ palette as the whole look
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: neon-echo
IDENTITY: CRT phosphor persistence with cursor drift and halation
KEEP VERBATIM: persistence_gain / cursor_drift / excitation_threshold / halation; per-channel tau; blackbody age; injection from luma+edge
ADD:
  1. Exact-C persistence — textureLoad C (no filtering sampler on history)
  2. Two-component P7 phosphor — fast blue decay + slower yellow-green tail on top of existing RGB taus
FORBID: springs; treating existing linear mix as enough (HEAD already has exp tau — deepen to P7, do not revert)
A PACKING: raw persistence RGB + alpha in A (not ACES). ACES on writeTexture only.
