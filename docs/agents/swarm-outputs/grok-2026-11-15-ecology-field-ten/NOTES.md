# Notes — ecology-field ten (2026-11-15)

Idea Cards were written in `BRIEFS.md` before the WGSL edits. Saved `params` on the eight shaders that already had them are unchanged (ids, names, defaults, min/max/step, mapping). `gen-astro-orrery-blackbody` and `gen-string-theory-structure` had an empty `params` array and four generic sliders multiplied by zero; named params were added whose defaults reproduce the old constants.

Prelude migration (`migrate_to_prelude.py`) on the pasted headers is infrastructure. It is not an idea.

Real-GPU visual QA was not run. This VM has no hardware GPU.

## Per shader

### predator-prey-ecology
- Kept: eat / death / mutation / breed, 5-point diffusion, held disk, click bloom, flora/fauna composite, raw state copied back from the render pass.
- A packing: raw `(prey, predator, nutrient, age)`. ACES on the render display only.
- In the diff: Holling intake in the step (`response` matched to mass-action near prey 0.3); nutrient spent then refilled at the old 0.04 mix; age raises death and tints cohorts in the render.

### gen-astro-orrery-blackbody
- Kept: three parallax layers, the original annulus mask, the spiral `sin(r·freq − time·2 + a·3)`, photo mix 0.6, bass / mids / treble roles.
- A packing: ACES display RGBA.
- In the diff: inner and outer annuli on the same spiral (Ring Spread; off at 0); Tanner Helland chromaticity (§12.2F), main ring ~2000 K at the default; exact-C sample against the spiral tangent.
- Pointer offsets the ring centre. No spring.

### sim-smoke-trails-thermal
- Kept: density / temperature / velocity packing, rise, density curl, 4-neighbour blend, held source, click rings, transmittance.
- A packing: raw sim. Unchanged. ACES on the display only.
- In the diff: MacCormack on density and temperature only, clamped to the 5-neighbour range (§12.2D); blackbody chromaticity of temperature (§12.2F), Thermal Intensity still scales radiance. The click ring no longer uses `pow` on a signed distance.

### gen-string-theory-structure
- Kept: four rotate / abs / ×1.5 iterations, the vibe product, photo mix 0.7, bass on the fold angle, mids on the gap, treble on the glow.
- A packing: ACES display RGBA.
- In the diff: core plus sheath (default peak matches the old `0.05/0.01`); fold signs counted before each abs (§12.2E); exact-C sample one unwind of the domain rotation. Trail default 0.85.

### jfa-aurora-voronoi
- Kept: seed packing, 3×3 flood, mouse disk, click seeds, random spawn, `aurora()`, render copies the field back.
- A packing: raw flood field. ACES on the render display only.
- In the diff: Jump Scale is the first step and `extraBuffer[133]` halves it across the eight repeats (seed pass resets the counter, single writer at `(0,0)`). Default 0.5 starts at 128 so the reach matches the old fixed `32×8`. Render draws the distance gradient as a curtain.

### photonic-caustics-graph
- Kept: emit normal (depth + fbm), 16 photons, Fresnel–Schlick, Snell with TIR, the four param roles, click rings, specular, rim.
- A packing: emit stores the normal; trace and accumulate store caustic rgb. ACES on the present pass only.
- In the diff: Cauchy scales on the three IORs (§12.2F); Beer–Lambert along the existing path (§12.2F); the repeat detects a caustic by the height channel (normals are ≤0.63 or ≥1.7) and averages a second stratum instead of refracting the caustic. `extraBuffer[133]` is the stratum, reset by emit.

### luma-flow-field
- Kept: the four params, iso-luminance flow, curl, pointer vortex, click fronts, one-sided LIC, stagnation hold.
- A packing: HDR display-history RGBA. Unchanged.
- In the diff: the upstream history sample is averaged with the existing downstream one; the Laplacian of the luma taps already fetched holds the trail in dark pockets.

### physarum-agents
- Kept: `FOOD_W`, `WANDER`, `DEP0`, `TRAIL_CAP`, the 3-sensor steer, torus, deposit rule, click bloom, lure, the nutrient / vein / living-front render. The step pass was not given a new force.
- A packing: raw trail (`.r` amount, `.g` last deposit time). The render pass still does not write A.
- In the diff: old dense trail shifts ochre before the living-front flare; brightness travels along the trail tangent the render already computes. Alpha is coverage of the vein, not `1`.

### sim-sand-dunes-rgba
- Kept: four populations, the four params, size segregation, dust-devil swirl, held deposition, click fronts.
- A packing: raw `(fine, coarse, moist, airborne)`. Unchanged.
- In the diff: excess slope above a moisture-raised repose avalanches from the upper pixel to the lower one (both sides use the previous bed); dust falls out on the upwind-sheltered side and returns to fine.

### wave-tank
- Kept: height / velocity / previous-height / phase, the explicit velocity step, Wave Speed / Damping / Source Strength / Boundary Reflect, edge absorb, pointer oscillator, click injection, phase hue, Laplacian sparkle.
- A packing: raw wave. The render copies that state back. ACES on the display only.
- In the diff: isotropic 9-point Laplacian (§12.2D), gain matched to the old 5-point on an x-only wave; the step latches the pre-update height into `.b` (previously copied unchanged) and the render whitens a crest that is still rising. History reads are `textureLoad`.

## Formula roster

| Row | Files |
|---|---|
| Blackbody chromaticity (§12.2F) | `gen-astro-orrery-blackbody`, `sim-smoke-trails-thermal` |
| MacCormack (§12.2D) | `sim-smoke-trails-thermal` |
| Isotropic 9-point (§12.2D) | `wave-tank` |
| Fold-count material (§12.2E) | `gen-string-theory-structure` |
| Cauchy, Beer–Lambert (§12.2F) | `photonic-caustics-graph` |

No row is on a third file. No shared spring, ripple stamp, or IQ palette.
