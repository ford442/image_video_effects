# Slime / flow leftover eight — Idea Cards (written before WGSL)

Family: leftover Physarum-trail / luma-flow / coupled-wave / RK4 / heat-haze / Lichtenberg shaders with plumbing floor and **no Idea Cards**. Two native solver ideas each. Identities kept. No spring+ripple+IQ stamp.

Already shipped this morning (do not re-edit): wave-equation, pixel-sand, sim-sand-dunes, sim-sand-dunes-rgba, cymatic-sand (`agents/swarm-outputs/grok-2026-09-12-sand-slime-nine/`).

Skipped: physarum / physarum-gemini / physarum-grokcf1 (extraBuffer[0..] agent packing — do not expand); optical-flow-tracer (binding 13 + extraBuffer[0] audio lie); sand-dunes generative (already technique-rich); origami/crease.

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

---

SHADER: wave-equation-rgba-fluid
IDENTITY: coupled wave height/velocity + Jacobi pressure + advected dye packed RGBA
KEEP VERBATIM: height/vel/pressure/dye packing; Wave Speed / Wave Damping / Fluid Viscosity / Source Strength; mouse oscillator + held dye; click injects
ADD:
  1. Breaking-wave foam where slope is steep and fluidVel points downhill
  2. Dye stretch along fluidVel (anisotropic filament, not just isotropic viscosity)
FORBID: cloning wave-equation caustic ridges as the whole look; new springs
A PACKING: raw (height, velocity, pressure, dye) — ACES display only

---

SHADER: spec-runge-kutta-advection
IDENTITY: RK4 dye advection through a noise velocity field with mouse vortex pairs
KEEP VERBATIM: RK4 backtrace; Time Step / Diffusion / Vortex Strength / Temporal Feedback; counter-rotating vortex pair; curl vis
ADD:
  1. Strain-rate filaments — extra dye contrast where |∇u| is high (RK4 is what preserves them)
  2. History LIC along a second RK4 step (another tap on the same integrator)
FORBID: replacing RK4 with Euler; new springs
A PACKING: HDR dye RGB + |vel| in A

---

SHADER: sim-heat-haze-field
IDENTITY: temperature field with ground/source heat, convection refraction of the photo
KEEP VERBATIM: Temperature Intensity / Convection Speed / Distortion Strength / Heat Source Count; packing temp/grad/disp; mouse heat; click rings
ADD:
  1. Thermal plumes — extra upward advection of stored heat (currently only the display displacement rises)
  2. Schlieren streaks along ∇T (refractive filaments native to heat haze)
FORBID: new springs; cloning fire-temperature embers
A PACKING: raw (temp, grad.x, grad.y, displacement mag)

---

SHADER: lichtenberg-fractal
IDENTITY: dielectric-breakdown charge that spreads from mouse/click with curl-biased branching
KEEP VERBATIM: Branch Complexity / Decay Speed / Glow Intensity / Depth Attraction; charge/age packing; mouse ignition; click origins; curl alignment
ADD:
  1. Streamer tips — extra glow where charge is high and neighbors are empty (the growing ends)
  2. Residual scorch along cooled channels (A was unused; age already tracks fade)
FORBID: new springs; replacing DBM with a different fractal
A PACKING: raw (charge, age, curl bias, scorch) — ACES display only
