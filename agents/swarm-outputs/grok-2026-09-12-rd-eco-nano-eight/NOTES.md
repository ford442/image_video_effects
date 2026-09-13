# RD / predator-prey / nano leftover eight — notes

Per shader: kept verbatim, packing, which ideas are in the diff.

## reaction-diffusion
KEEP: Intensity→diffusion / Speed→feed / Scale→kill / Detail→accumulation; rotating conveyor; packets; mouse seed; click rings.
A packing: raw (U, V, packet, accumulation). Stopped mixing prev.rgb as display color. ACES display only.
Ideas in diff: anisotropic Laplacian along `flowDir` (`anisoLap`); mitosis pinch (`mitosis` from −laplacian.g).

## chromatic-reaction-diffusion-rgba
KEEP: Feed / Kill / Chromatic Separation / Cross Coupling; warm RG + cool BA; hover spiral; click fronts.
A packing: raw (warm U, warm V, cool U, cool V).
Ideas in diff: overlap quench (`overlap` kills both V); photo chroma seed (`warmSeed` / `coolSeed`).

## alpha-reaction-diffusion-rgba
KEEP: Feed / Kill / Cross Inhibition / Source Mix; RG warm + BA cool; held inoculation; click fronts.
A packing: raw (warm U, warm V, cool U, cool V).
Ideas in diff: nutrient chemotaxis (`taxis` along photo luma gradient); interface membrane (`membrane` from |∇(g−a)|).

## hybrid-reaction-diffusion-glass
KEEP: Feed Rate / Kill Rate / Glass Refraction / Depth Effect; mouse inject; existing palette + Fresnel.
A packing: raw (chem, |grad|, caustic, coverage). Laplacian C loads now clamped.
Ideas in diff: thickness IOR (`thickness` scales distortion); caustic concentrate (`caustic` from −div).

## predator-prey
KEEP: Eat Probability / Death Rate / Mutation Rate / Breed Threshold; species encoding; mouse carnivores; ripple plants.
A packing: raw (species, energy, age, variant). C neighbor reads converted to textureLoad.
Ideas in diff: reciprocal hunt (`neighbors[2]`/`[3]` drain prey energy); carcass compost (animal death → PLANT).

## predator-prey-rgba
KEEP: Eat Probability / Death Rate / Plant Growth; luma photosynthesis; mouse carnivores; ripple plants.
A packing: raw (plants, herbivores, carnivores, toxin). Toxin Strength (`zoom_params.w`) now live.
Ideas in diff: carnivore pursuit (`pursuit` along herbivore gradient); herbivore flee (`flee` away from carnivore gradient). Did not clone this morning's plant-taxis.

## nano-assembler
KEEP: Assembly / Density / Disruption / Rebuild Speed; cell mosaic; cyan disassembled glow; mouse repel.
A packing: ACES display RGBA (HEAD had no C feedback). Sampler names canonicalized; time from `config.x`.
Ideas in diff: docking bonds (`dock` on shared cell edges); ballistic scatter (`radial` along mouse-away).

## nano-assembler-crystal
KEEP: phase/temp/orientation/impurity; Assembly / Grid Density / Disruption / Rebuild Speed; mouse melt; ripple nucleate.
A packing: raw (phase, temp, orientation, impurity). Neighbor C converted to textureLoad.
Ideas in diff: hex facet lock (`snapped` to 60°); recalescence glow (`recalescence` from latentHeat). Did not clone this morning's dendrite arms / grain boundary.
