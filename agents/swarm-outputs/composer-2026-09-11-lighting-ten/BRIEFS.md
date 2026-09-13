# Lighting-effects ten — Idea Cards (written before WGSL)

Family: leftover `lighting-effects` cohort from foundation note (hybrid done 09-10). Two native ideas each. Identities kept. Existing springs/ripples kept where HEAD owns them; no new springs. Skip `neon-light` (hybrid batch) and aurora-rift variants (overlap prior optical packs).

Claimed IDs: `divine-light`, `divine-light-gpt52`, `alpha-aurora-bands`, `aurora_borealis`, `underwater_caustics`, `cinematic-flare`, `dynamic-lens-flares`, `lens-flare-brush`, `neon-pulse-edge`, `sim-volumetric-fake-em`.

---

SHADER: divine-light
IDENTITY: Radial god-ray march with threshold gating, golden halo, and dust motes
KEEP VERBATIM: rayIntensity/decay/density/threshold; 16-step march; ripple offset; golden tint; exact C history
ADD (2 native ideas):
  1. Henyey-Greenstein forward-scatter phase along each march step — tightens shafts toward the light
  2. Depth-occluded shaft extinction — sample readDepth along the march and attenuate when geometry blocks the beam
FORBID: springs, stained-glass rewrite (that is gpt52), IQ palette
A PACKING: ACES display RGBA in A

---

SHADER: divine-light-gpt52
IDENTITY: Cathedral crepuscular rays with Cauchy dispersion, rose-window tint, and Airy halo
KEEP VERBATIM: spring center [133..138]; Cauchy RGB march; stained-glass mask; Airy rings; four params
ADD (0 new — document existing 3 ideas in header):
  Header only: Ideas line names Cauchy dispersion; rose-window stained glass; Airy diffraction halo
FORBID: fourth generic overlay; new springs
A PACKING: ACES display RGBA in A

---

SHADER: alpha-aurora-bands
IDENTITY: Multi-layer geomagnetic curtains with discrete O/N2 spectral emission bands
KEEP VERBATIM: intensity/curtainFrequency/turbulence/speed; auroraEmission altitude lines; 5 layers; wind from mouse
ADD (2 native ideas):
  1. Field-aligned curtain folds — warp layer UV along windDir before fbm (magnetic draping)
  2. Green-line treble shimmer — modulate only the 557.7 nm band with treble, not the whole palette
FORBID: replacing spectral lines with IQ palette, springs
A PACKING: ACES display RGBA in A

---

SHADER: aurora_borealis
IDENTITY: Flowing aurora ribbons with starfield and geomagnetic ripple substorms
KEEP VERBATIM: numRibbons/flowSpeed/ribbonWidth/glowIntensity; ribbon loop; curl noise; stars
ADD (2 native ideas):
  1. Corona discharge crown at each ribbon crest (local max of ribbonShape)
  2. Magnetic reconnection sparks along ribbon longitude when bass exceeds smoothed history from C
FORBID: kaleidoscope overlay, springs
A PACKING: ACES display RGBA in A

---

SHADER: underwater_caustics
IDENTITY: Gerstner-surface Jacobian caustics with volumetric god rays and absorption
KEEP VERBATIM: waveScale/causticIntensity/depth/clarity; 5-wave surface; Jacobian focus; godRay()
ADD (2 native ideas):
  1. Dual-frequency caustic beat — second surface sample at 0.55× wavelength, multiply focus ridges
  2. Suspended particulate glitter in cells where focus > threshold (native underwater sparkle)
FORBID: replacing Gerstner with noise caustics, springs
A PACKING: ACES display RGBA in A

---

SHADER: cinematic-flare
IDENTITY: Cooke triplet ghosts, anamorphic streak, 6-blade starburst, and Mie halo
KEEP VERBATIM: flareIntensity/streakLength/chromaticShift/bloomThreshold; triplet coeffs; diffractionSpike
ADD (2 native ideas):
  1. Lens dirt speckle occlusion along the flare axis (hash mask attenuates ghosts/streak)
  2. Veiling glare bloom between light source and image center (axis fog)
FORBID: ferrofluid, springs
A PACKING: ACES display RGBA in A

---

SHADER: dynamic-lens-flares
IDENTITY: Mouse-tracked optical-axis ghosts with halo ring and starburst blades
KEEP VERBATIM: intensity/threshold/spread/ghostCount; ghost loop; halo dispersion; ray blades
ADD (2 native ideas):
  1. Veiling glare along axis (center to mouse) weighted by lumaHot
  2. Ghost aperture breathing — ghost size modulated by bass-smoothed envelope from exact C.a
FORBID: brush falloff (that is lens-flare-brush), new springs
A PACKING: ACES display RGBA in A

---

SHADER: lens-flare-brush
IDENTITY: Brush-localized anamorphic streak, orbital ghosts, and starburst at cursor
KEEP VERBATIM: threshold/intensity/stretch/colorShift; brush falloff; ghost orbit; streak rainbow
ADD (2 native ideas):
  1. Wet smear persistence — blend flareTotal with exact C along mouse-drag offset vector
  2. Caustic sparkle at orbital ghost centers (small hash glints on ghostAccum)
FORBID: replacing brush with full-screen overlay, springs
A PACKING: ACES display RGBA in A

---

SHADER: neon-pulse-edge
IDENTITY: Sobel edge neon with multi-layer bloom and direction-driven hue cycle
KEEP VERBATIM: edge_threshold/glow_radius/pulse_speed/color_cycle_rate; Sobel; softEdgeDist from C.r
ADD (2 native ideas):
  1. Gradient-oriented neon rim — offset emission samples along (gx, gy) normal direction
  2. Treble sub-harmonic strobe on pulse (second faster sin layer keyed to treble)
FORBID: springs, replacing Sobel with generic edge detect
A PACKING: edge magnitude in C.r for halo reads; display RGBA in A (fix packing lie)

---

SHADER: sim-volumetric-fake-em
IDENTITY: God rays bent by mouse EM field with magnetic chromatic split and ripple charges
KEEP VERBATIM: lightIntensity/emDistortion/chromaticSplit/rippleCharge; E/B fields; radial march
ADD (2 native ideas):
  1. Faraday rotation hue twist proportional to totalB along bent ray
  2. Lichtenberg branch filaments where fieldMag exceeds threshold (native EM look)
FORBID: springs, replacing EM with generic blur
A PACKING: ACES display RGBA in A (+ floor: dataA write, ACES on output)
