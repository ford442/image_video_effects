# Idea Cards — batch 2 of 2 (shaders 6-10 of "organic/optical mid-high" ten)

## 6. gen-cosmic-velvet-hypnosis (SECOND PASS)

```
SHADER: gen-cosmic-velvet-hypnosis
IDENTITY: soft log-polar spiral kaleidoscope well with crushed-velvet sheen, chromatic runner comets, and click halos
KEEP VERBATIM: spiral/octave-well math, drag-torque mouse mechanic, palette, 4 params and their roles, ripple click halos
EXISTING (kept): crushed-velvet pile patches under a turning light; nested log-octave wells sinking inward
ADD (new this pass):
  1. counter-runner comet — a second comet travels the counter-spiral's opposite winding (mirrors the existing single "runner" mechanic, doesn't invent a new motif); where the two cross, a bright collision flash marks the encounter
  2. seam glint — either runner sparking a brief glint wherever it crosses a nested-octave seam, tying the two existing ideas (velvet sheen's runners + the octave wells) together instead of leaving them independent
FORBID on this file: springs, unrelated fractals, replacing the drag-torque mechanic
A PACKING: ACES display RGBA (unchanged — read back as colour history)
```

## 7. gen-cymatic-plasma-mandalas

```
SHADER: gen-cymatic-plasma-mandalas
IDENTITY: discrete N-fold kaleidoscope over a hex/circle SDF blend, perturbed by a wave field meant to read as Chladni-plate cymatics, chromatic aberration, spring-damped mouse vortex, click nodal rings
KEEP VERBATIM: fold/kaleidoscope math, hex+circle SDF blend, spring-mouse vortex + extraBuffer[133..138] state (untouched), click nodal-ring perturbation, 4 params and roles, temporal symmetry memory, depth edge glow
ADD:
  1. three-band wave interference — the prior "cymatic" wave was a single sine; real Chladni plates ring at multiple modes at once. Sum three audio-band-keyed radial waves (bass/mids/treble frequencies) so their crossings form genuine nodal interference lines instead of one fake sine
  2. standing-wave sand speckle — fine speckle brightens only where all three wave sources sit near zero together (a true shared node), mimicking how real Chladni sand gathers exactly at nodal lines, not just at one wave's zero-crossing
FORBID on this file: removing the spring/vortex, replacing the kaleidoscope fold, changing symmetryOrder's integer-sector behavior
A PACKING: A/C = final ACES display RGBA; exact temporal symmetry memory (unchanged, now stated in header — was previously only in JSON feedbackPacking)
```
Plumbing fix: file had no `Ideas:` header line (only a prose hygiene note) — added one naming the two ideas above.

## 8. gen-depth-refracted-liquid-stained-glass

```
SHADER: gen-depth-refracted-liquid-stained-glass
IDENTITY: depth-buffer-as-heightfield refraction through a polar kaleidoscope of stained-glass facets, three-point lighting, Fresnel, ornament inlay, temporal tint rotation, click-wave glass flex
KEEP VERBATIM: facet fold, heightfield normal from depth gradient, three-point lighting, ornamentSample, thinFilmTint, click-flex, 4 params and roles
ADD:
  1. leaded-came highlight — a sharp specular line right on the facet seam (edgeFactor), brighter where the key light grazes it, literalizing the "stained glass" identity's missing lead-came structure (currently the seam only got a soft tint, no metal highlight)
  2. depth-driven caustic focus glow — steep-bevel facets (large refraction offset magnitude) concentrate light like a lens; brightens in proportion to how hard this texel is already refracting, using data the shader already computes but never turned into a visible caustic
FORBID on this file: replacing the depth-heightfield refraction mechanic, adding a solver, generic bloom unrelated to the glass metaphor
A PACKING: A/C = final ACES display RGBA; exact stained-glass tint history (unchanged, now stated in header)
```
Plumbing fix: file had no `Ideas:` header line — added one.

## 9. gen-cybernetic-ferro-coral

```
SHADER: gen-cybernetic-ferro-coral
IDENTITY: raymarched ferrofluid coral reef — magnetic domain-warped spikes repelled/attracted around the mouse, Gray-Scott Turing-band shell stripes, iridescent Fresnel shell over an emissive core
KEEP VERBATIM: warpedFbm spike mechanic, turingBand shell carving, mouse-repulsion field, core/shell material split, 4 params and roles, ripple spike-boost
ADD:
  1. circuit-trace glow — a thin emissive trace lit exactly on the Turing-band balance line (where turingBand peaks), literalizing "cybernetic" which the name promised but nothing in the render actually delivered
  2. signal pulse — a ring travels outward from the coral's centre across the shell, amplitude keyed to treble, reading as a "data pulse" racing through the coral's wiring; distinct from the existing uniform bass-driven spike intensity
FORBID on this file: replacing the ferrofluid spike SDF, adding unrelated palettes, touching extraBuffer (file explicitly documents "no engine-reserved extraBuffer slots")
A PACKING: A/C = raw HDR display RGBA history (unchanged)
```
Plumbing fix: header carried a "Batch 36 — Algorithmist" attribution stamp instead of a proper `Ideas:` line — normalized to the standard 7-line banner with a real `Ideas:` line.

## 10. gen-chrono-voronoi-mycelium (SECOND PASS)

```
SHADER: gen-chrono-voronoi-mycelium
IDENTITY: multi-generation animated Voronoi mycelium growth with mouse nutrient gradient, click nutrient-front waves, velocity-advected HDR light-trail history
KEEP VERBATIM: multi-generation Voronoi growth, voronoiLayer/glowingTips, nutrient/clickSurge mechanics, the pre-ACES-in-A / ACES-on-writeTexture packing (do not normalize to match other shaders), 4 params and roles
EXISTING (kept): clamp connections across generation borders; apothecia cups on high-generation seeds
ADD (new this pass):
  1. cyclic birth-death regeneration — the old per-cell birthTime only ever aged toward zero and stayed dead forever after one cycle, so "chrono" did nothing after the first ~15s. Wrapped the age clock per cell (cyclePeriod) so colonies genuinely die and regrow in a loop — this is the "chrono" half of the identity the file's math never actually implemented
  2. rebirth burst — a green spark distinct from the warm clamp/apothecia hues, marking the instant a cell re-enters its growth cycle; makes the new cyclic regeneration visible rather than just structurally present
FORBID on this file: touching the velocity-advected history/flow field, changing the A/C packing convention, restating idea 1/2 from the prior pass as if new
A PACKING: HDR display RGBA (pre-ACES in A; ACES on writeTexture) — unchanged, this file's documented packing differs intentionally from the rest of the batch
```
