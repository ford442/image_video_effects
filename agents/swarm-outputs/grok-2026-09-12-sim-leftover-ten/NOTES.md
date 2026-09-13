# Simulation leftover ten — notes

Per shader: kept verbatim, packing, which ideas are in the diff.

## sim-decay-system
KEEP: decay/material/corrosion/protection packing; Decay Rate / Edge Vulnerability / Color Shift / Recovery Rate; held protection; click rust rings.
A packing: raw (decay, material, corrosion, protection). ACES display only.
Ideas in diff: filiform veins (`veinPhase` along edge tangent); oxide bloom from stored + neighbor corrosion (`oxideBloom`).

## sim-decay-system-rgba
KEEP: paint/metal/organic/structure; Base Decay / Edge Vulnerability / Moisture / Recovery Rate; held restore; click damage.
A packing: raw four-layer.
Ideas in diff: paint-flake holes (`flakeMask`); rust bleed solver (`rustBleedIn`) + visual seep.

## alpha-erosion-terrain
KEEP: height/water/sediment/erosion; Rain / Erosion / Deposition / Sediment Capacity; mouse rain; click storms.
A packing: raw hydraulic fields.
Ideas in diff: alluvial fans (`fanDeposit` / `fanVis`); stream incision (`incision` / `channelVis`).

## alpha-crystal-growth-phase
KEEP: phase/temp/orientation/impurity; Supercooling / Anisotropy / Growth Rate / Impurity Level; mouse seed; click nucleation.
A packing: raw phase-field.
Ideas in diff: secondary dendrite arms (`sideArm` perpendicular to orientation); grain-boundary darkening (`grainBound` from neighbor orientation jump).

## alpha-fire-temperature
KEEP: fuel/temp/smoke/age; Burn Rate / Convection / Smoke Density / Ember Glow; mouse fuel; click sparks; up-advection.
A packing: raw fire fields.
Ideas in diff: side-vorticity (`vortAmt` lateral mix from dTdx); age-gated ember sparks (`spark` from Ember Glow + leftover fuel).

## alpha-em-field-simulation
KEEP: Ex, Ey, B, charge; Field Damping / Charge Intensity / B-Field Visibility / Wave Speed; click-parity charges.
A packing: raw signed EM.
Ideas in diff: LIC streaks along E (`lic` loop); recombination flash (`opp` opposite-sign product).

## alpha-multi-state-ecosystem
KEEP: s1/s2/resource/toxin; Species 1/2 Growth / Diffusion / Toxin Strength; keystone mouse; spore ripples; audio seasons.
A packing: raw ecosystem fields.
Ideas in diff: ecotone ridge (`ecotone` where s1≈s2); toxin stain (`stain` mottled mix from A).

## cellular-automata-rgba
KEEP: plants/herbivores/predators/nutrients; Plant Growth / Herbivore / Predator / Decay Rate; mouse seeds; click nutrient rings.
A packing: raw CA densities.
Ideas in diff: herbivore taxis (`taxis` along plantGrad); nutrient patches (`deathBloom` + `soilPatch`).

## lenia-on-video
KEEP: kernel radius / video coupling / glow / mix; A packing (density, neighborhood, growth, vidLuma); mouse spawn/clear; bass inject.
A packing: raw Lenia state.
Ideas in diff: anisotropic kernel (`pStretch` from luma gradient); membrane from |∇A| (`membrane`).
FLOOR: deleted extraBuffer[0..4] audio lie; plasmaBuffer stays.

## digital-moss
KEEP: grown/moisture/spores/age; Intensity / Speed / Scale / Detail; held clean; click spore rings; existing scanline.
A packing: raw moss fields.
Ideas in diff: shade taxis (`fromShade` darker neighbor); rhizoid threads (`thread` along luma tangent).
FLOOR: `filteringSampler` / `comparisonSampler` → canonical names. No new spring.
