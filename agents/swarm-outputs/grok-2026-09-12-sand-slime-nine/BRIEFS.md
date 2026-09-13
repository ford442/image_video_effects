# Sand / slime / wave leftover nine — Idea Cards (written before WGSL)

Family: leftover granular / Physarum-trail / wave-tank shaders with plumbing floor and **no Idea Cards**. Two native solver ideas each. Identities kept. No spring+ripple+IQ stamp.

Skipped: physarum / physarum-gemini / physarum-grokcf1 (extraBuffer[0..] agent packing — do not expand); simulation leftover ten (done this morning); overlay-rich origami/crease.

---

SHADER: wave-equation
IDENTITY: damped height/velocity ripple tank that refracts the photo
KEEP VERBATIM: height/velocity/foam/phase packing; Wave Speed / Damping / Source Strength / Boundary Reflect; held oscillator; click fronts
ADD:
  1. Caustic ridges from |∇h| (bright lines where slope is steep, native to a water tank)
  2. Standing-node darkening where height and velocity are out of phase
FORBID: new springs; IQ as the whole look
A PACKING: raw (height, velocity, foam, phase) — ACES display only

---

SHADER: pixel-sand
IDENTITY: granular density/velocity automaton with avalanche sheets
KEEP VERBATIM: density/vx/vy/energy packing; Gravity / Particle Density / Curl Force / Bounce; held swirl; click shelves
ADD:
  1. Diagonal rest — grains fill empty cells from the two down-diagonals (classic falling-sand)
  2. Kinetic sparkle from the stored energy channel
FORBID: new springs; replacing the automaton
A PACKING: raw (density, vx, vy, energy)

---

SHADER: sim-sand-dunes
IDENTITY: height-field saltation, avalanching, wind erosion
KEEP VERBATIM: height/loose/velocity/moisture; Gravity / Wind / Viscosity / Erosion; held mound; click impacts
ADD:
  1. Slipface vs stoss — extra avalanche on the lee (downwind steep) side
  2. Windward ripple wavelength from wind (short ridges on the stoss)
FORBID: cloning erosion-terrain alluvial fans
A PACKING: raw (height, loose, velocity, moisture)

---

SHADER: sim-sand-dunes-rgba
IDENTITY: four grain populations — fine, coarse, moist clumps, airborne dust
KEEP VERBATIM: packing; Gravity / Wind / Moisture / Dustiness
ADD:
  1. Size segregation — coarse settles in troughs, fine saltates with wind
  2. Dust-devil swirl when dry + windy (dust spins off the bed)
FORBID: cloning dunes height-field
A PACKING: raw (fine, coarse, moist, dust)

---

SHADER: cymatic-sand
IDENTITY: Chladni plate with persistent grain transport
KEEP VERBATIM: density/velocity/energy/strike memory; Frequency Mode / Harmonic Mix / Grain Density / Audio Sensitivity
ADD:
  1. Node piles — extra grain at |wave|≈0, empty antinodes
  2. Beat envelope between the two Chladni modes (w0 vs w1)
FORBID: new springs
A PACKING: raw (density, radial vel, energy, strike memory)

---

SHADER: sim-slime-mold-growth
IDENTITY: Physarum-style trail with left/center/right sensors
KEEP VERBATIM: trail packing (trail, diffused, activity, deposit); Sensor Angle / Trail Decay / Particle Count / Randomness; mouse food; click rings
ADD:
  1. Photo food — extra deposit on dark luma (colonize the picture)
  2. Vein anastomosis — thicken where neighbor trails already form a corridor
FORBID: new springs; rewriting as Gray-Scott
A PACKING: raw (trail, diffused, activity, deposit)

---

SHADER: sim-slime-mold-growth-em
IDENTITY: Physarum trails steered by mouse E/B; click opposite charges
KEEP VERBATIM: trail/E-mag/B/activity packing; Sensor Angle / Trail Decay / EM Influence / Ripple Charge dual-use; extraBuffer[133..138] pointer history
ADD:
  1. Field-line deposit — extra trail along E (agents follow the field, so the trail should too)
  2. Opposite-polarity wipe — trails thin where secondary (negative) charge is strong
FORBID: new extraBuffer slots; dropping click charges
A PACKING: raw (trail, E mag, signed B, activity)

---

SHADER: slime-mold-on-video
IDENTITY: video-luma food field with trail follow / decay
KEEP VERBATIM: trail/food/drift packing; Trail Follow / Trail Decay / Food Gain / Glow; mouse food; click fronts
ADD:
  1. Food anastomosis — bridges between luma peaks (connect bright food islands)
  2. Streamer veins along packed drift (thin bright threads, not a glow puddle)
FORBID: new springs; cloning slime-mold-growth agent loop
A PACKING: raw (trail, food, drift.x, drift.y)

---

SHADER: luma-flow-field
IDENTITY: iso-luminance advection with curl ribbons and C history
KEEP VERBATIM: HDR trail RGB + coverage A; Flow Scale / Trail Decay / Curl Strength / Audio Sensitivity; mouse vortex; click fronts
ADD:
  1. LIC sample along isoFlow (history tap along the already-computed flow)
  2. Stagnation hold where |∇luma| is tiny (trail parks in flats)
FORBID: new springs; replacing iso-luma with a different field
A PACKING: HDR display-history RGBA (C is read as color trail)
