# RD / predator-prey / nano leftover eight — Idea Cards (written before WGSL)

Family: leftover reaction-diffusion / Lotka–Volterra / nanobot-assembly shaders with plumbing floor and **no Idea Cards**. Two native solver ideas each. Identities kept. No spring+ripple+IQ stamp.

Already done this morning: simulation leftover ten, slime/flow eight, sand/wave five. Origami/crease/ascii-glyph already carry 2026-09-11 Idea Cards — skip.

Skipped: chromatic-reaction-diffusion (optical ten, Marangoni/chemiluminescent already shipped); gen-lichen / gen-bioluminescent (June/August upgrades); predator-prey-ecology graph; nano-repair; physarum extraBuffer[0..] agents.

---

SHADER: reaction-diffusion
IDENTITY: two-channel Gray-Scott with a rotating one-pixel conveyor and traveling feed packets
KEEP VERBATIM: Intensity→diffusion, Speed→feed, Scale→kill, Detail→accumulation; packet fronts; mouse seed; click rings
ADD:
  1. Anisotropic Laplacian along the already-computed flowDir — the conveyor should smear chemistry, not just translate it
  2. Mitosis pinch — extra V where the B Laplacian is strongly negative (spots split instead of just growing)
FORBID: new springs; cloning chromatic dual-Turing; treating prev.rgb as display color (packing lie)
A PACKING: raw (U, V, packet, accumulation) — ACES display only

---

SHADER: chromatic-reaction-diffusion-rgba
IDENTITY: two cross-coupled warm/cool Gray-Scott systems packed RGBA
KEEP VERBATIM: Feed / Kill / Chromatic Separation / Cross Coupling; warm RG + cool BA; hover spiral; click fronts
ADD:
  1. Competitive overlap quench — where warm V and cool V coexist, both decay (two chemistries cannot occupy the same cell)
  2. Photo chroma seed — red luma feeds warm V, blue luma feeds cool V
FORBID: cloning chromatic-reaction-diffusion Marangoni/chemiluminescent; new springs
A PACKING: raw (warm U, warm V, cool U, cool V)

---

SHADER: alpha-reaction-diffusion-rgba
IDENTITY: four-species ecological Gray-Scott with photo nutrient and cross-inhibition
KEEP VERBATIM: Feed / Kill / Cross Inhibition / Source Mix; RG warm + BA cool; held inoculation; click fronts
ADD:
  1. Nutrient chemotaxis — inhibitors step along the photo-luma gradient (colonies follow food)
  2. Interface membrane — extra kill / display ridge where |∇(g − a)| is high (species contact line)
FORBID: cloning chromatic-rd-rgba overlap quench as the whole look; new springs
A PACKING: raw (warm U, warm V, cool U, cool V)

---

SHADER: hybrid-reaction-diffusion-glass
IDENTITY: a chemistry field used as glass thickness — Turing pattern refracts the photo
KEEP VERBATIM: Feed Rate / Kill Rate / Glass Refraction / Depth Effect; mouse inject; existing palette + Fresnel
ADD:
  1. Thickness IOR — distortion scales with chemistry (thicker gel bends more)
  2. Caustic concentrate — extra brightness where ∇·grad is negative (focusing ridges)
FORBID: replacing the glass with a dual-species rewrite; extra IQ overlay; new springs
A PACKING: raw (chem, |grad|, caustic, coverage) — ACES display only

---

SHADER: predator-prey
IDENTITY: discrete CA food chain — empty / plant / herbivore / carnivore with energy, age, mutation
KEEP VERBATIM: Eat Probability / Death Rate / Mutation Rate / Breed Threshold; species encoding; mouse carnivores; ripple plants
ADD:
  1. Reciprocal hunt — prey cells lose energy when an adjacent predator can eat them (eating was one-sided)
  2. Carcass compost — animal death becomes a plant with leftover energy instead of empty
FORBID: new springs; rewriting as continuous Lotka–Volterra (that's predator-prey-rgba)
A PACKING: raw (species, energy, age, variant)

---

SHADER: predator-prey-rgba
IDENTITY: continuous-density plants / herbivores / carnivores / toxin
KEEP VERBATIM: Eat Probability / Death Rate / Plant Growth / Toxin Strength; luma photosynthesis; mouse carnivores; ripple plants
ADD:
  1. Carnivore pursuit — carnivores bias along the herbivore gradient (the missing trophic taxis)
  2. Herbivore flee — herbivores bias away from the carnivore gradient
FORBID: cloning this morning's cellular-automata-rgba plant-taxis; new springs
A PACKING: raw (plants, herbivores, carnivores, toxin) — wire Toxin Strength (was dead)

---

SHADER: nano-assembler
IDENTITY: photo rebuilt as a grid of nanobots that scatter from the mouse
KEEP VERBATIM: Assembly / Density / Disruption / Rebuild Speed; cell mosaic; cyan disassembled glow; mouse repel
ADD:
  1. Docking bonds — weld seams on shared cell edges as assembly rises
  2. Ballistic scatter — offset along the mouse-away radial (not only hash jitter)
FORBID: inventing a persistent agent sim; extraBuffer springs; cloning crystal phase-field
A PACKING: ACES display RGBA (HEAD had no C feedback)

---

SHADER: nano-assembler-crystal
IDENTITY: nanobot grid that phase-field freezes into an oriented crystal
KEEP VERBATIM: phase/temp/orientation/impurity packing; Assembly / Grid Density / Disruption / Rebuild Speed; mouse melt; ripple nucleate
ADD:
  1. Hex facet lock — snap orientation to 60° when phase is high (crystal, not a blob)
  2. Recalescence glow — latent-heat temperature spike lights the freeze front
FORBID: cloning this morning's dendrite side-arms / grain-boundary; new springs
A PACKING: raw (phase, temp, orientation, impurity)
