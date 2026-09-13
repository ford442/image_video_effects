# Simulation leftover ten — Idea Cards (written before WGSL)

Family: August-23 simulation / field / growth / decay that already has the plumbing floor and **no Idea Cards**. Two native solver ideas each. Identities kept. No spring+ripple+IQ stamp. Existing mouse/held/click on decay, EM, fire, moss, Lenia kept.

Skipped: lighting/geometric/hybrid leftovers (done 09-10/11); kaleido/voronoi eight and drag-glitch eight; sand/slime/physarum/wave-equation leftover; overlay-rich origami/crease/ascii-glyph/neon-quantum-lattice; graphs/pass-2.

---

SHADER: sim-decay-system
IDENTITY: photo corrodes from edges inward; different materials decay at different rates
KEEP VERBATIM: decay/material/corrosion/protection packing; Decay Rate / Edge Vulnerability / Color Shift / Recovery Rate; held-pointer protection; click rust rings
ADD:
  1. Filiform rust veins along the already-detected edge gradient (streaks follow the Sobel tangent)
  2. Oxide bloom from the stored corrosion channel (currently almost unused in the picture)
FORBID: new springs; IQ palettes; treating the existing hash rust as the upgrade
A PACKING: raw (decay, material, corrosion, protection) — ACES display only

---

SHADER: sim-decay-system-rgba
IDENTITY: four-layer paint / metal / organic / structure decay with advertised cross-coupling
KEEP VERBATIM: paint/metal/organic/structure packing; Base Decay / Edge Vulnerability / Moisture / Recovery Rate; held restore; click damage
ADD:
  1. Paint-flake holes when integrity drops (discrete chips, not a smooth fade)
  2. Rust bleed from metal (G) into failed paint (R) — the cross-coupling made visible
FORBID: new springs; cloning decay-system filiform veins
A PACKING: raw (paint, metal, organic, structure) — ACES display only

---

SHADER: alpha-erosion-terrain
IDENTITY: hydraulic erosion height field seeded from photo luma
KEEP VERBATIM: height/water/sediment/erosion packing; Rain / Erosion / Deposition / Sediment Capacity; mouse rain; click storms
ADD:
  1. Alluvial fans — extra deposit where slope flattens and sediment is high
  2. Stream incision — extra downcut where water concentrates
FORBID: new springs; replacing the hydraulic solver
A PACKING: raw (height, water, sediment, erosion) — ACES display only

---

SHADER: alpha-crystal-growth-phase
IDENTITY: anisotropic phase-field dendrite with impurity rejection
KEEP VERBATIM: phase/temp/orientation/impurity packing; Supercooling / Anisotropy / Growth Rate / Impurity Level; mouse seed; click nucleation
ADD:
  1. Secondary dendrite arms when impurity is high (growth perpendicular to the primary orientation)
  2. Grain-boundary darkening where neighbor orientation jumps
FORBID: new springs; IQ candy as the whole look
A PACKING: raw (phase, temp, orientation, impurity) — ACES display only

---

SHADER: alpha-fire-temperature
IDENTITY: fuel / temperature / smoke / age fire with blackbody color
KEEP VERBATIM: packing; Burn Rate / Convection / Smoke Density / Ember Glow; mouse fuel; click sparks; up-advection
ADD:
  1. Side-vorticity at the flame (curl from the existing up-advection, lateral smoke/heat)
  2. Age-gated ember sparks driven by the existing Ember Glow slider
FORBID: new springs; ferrofluid / IQ overlay
A PACKING: raw (fuel, temperature, smoke, age) — ACES display only

---

SHADER: alpha-em-field-simulation
IDENTITY: 2D EM field with signed Ex, Ey, B, charge; mouse/ripple inject charges
KEEP VERBATIM: packing; Field Damping / Charge Intensity / B-Field Visibility / Wave Speed; click-parity charges
ADD:
  1. LIC streaks along E (line-integral convolution of the existing field)
  2. Recombination flash where +/− charge meet
FORBID: new springs; dropping click-parity charges
A PACKING: raw (Ex, Ey, B, charge) — ACES display only

---

SHADER: alpha-multi-state-ecosystem
IDENTITY: two competing species sharing resource and producing toxin, with audio seasons
KEEP VERBATIM: s1/s2/resource/toxin packing; Species 1/2 Growth / Diffusion / Toxin Strength; keystone mouse; spore ripples
ADD:
  1. Ecotone ridge where s1≈s2 (the contact front, not just per-species gradient glow)
  2. Toxin stain in the display from A (toxin is simulated, barely shown)
FORBID: new springs; cloning CA-RGBA herbivore taxis
A PACKING: raw (s1, s2, resource, toxin) — ACES display only

---

SHADER: cellular-automata-rgba
IDENTITY: plants / herbivores / predators / nutrients Lotka–Volterra CA
KEEP VERBATIM: packing; Plant Growth / Herbivore Efficiency / Predator Efficiency / Decay Rate; mouse seeds; click nutrient rings
ADD:
  1. Herbivores bias toward the plant gradient (taxis, not isotropic spread)
  2. Nutrient patches from local death (A already stores nutrients — make the bloom local)
FORBID: new springs; rewriting as Gray-Scott
A PACKING: raw (plants, herbivores, predators, nutrients) — ACES display only

---

SHADER: lenia-on-video
IDENTITY: continuous Lenia over video; luma seeds, hue/sat drive μ/σ
KEEP VERBATIM: kernel radius / video coupling / glow / mix; A packing (density, neighborhood, growth, vidLuma); mouse spawn/clear; bass inject
ADD:
  1. Anisotropic kernel stretched by the video luma gradient
  2. Membrane from |∇A| so creatures read as organisms, not a glow puddle
FORBID: extraBuffer[0..132] audio (header lie — delete it; plasmaBuffer stays); new springs
A PACKING: raw (density, neighborhood, signed growth, video luma) — ACES display only

---

SHADER: digital-moss
IDENTITY: shade-driven moss colonizing dark photo regions via moisture and spores
KEEP VERBATIM: grown/moisture/spores/age packing; Intensity / Speed / Scale / Detail; held clean; click spore rings; existing scanline
ADD:
  1. Shade taxis — grow toward the darker neighbor
  2. Rhizoid threads along the luma gradient
FORBID: more CRT scanlines as the upgrade; new springs (JSON spring-cursor is a lie — do not invent one)
A PACKING: raw (grown, moisture, spores, age) — ACES display only
FLOOR: rename filteringSampler / comparisonSampler to canonical names
