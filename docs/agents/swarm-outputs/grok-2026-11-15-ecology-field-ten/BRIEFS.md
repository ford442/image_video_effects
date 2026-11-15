# Idea Cards — Grok (ecology-field ten, 2026-11-15)

Written before the WGSL edits. Ten shaders (line counts in the request, multipass where noted). Each card adds **two or three** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is newly applied on at most two files here, and only where that file already is that mechanism.

- Blackbody chromaticity (§12.2F) is new on `gen-astro-orrery-blackbody` and `sim-smoke-trails-thermal` only — the two emitters that already claim a temperature.
- MacCormack advection (§12.2D) is new on `sim-smoke-trails-thermal` only.
- Isotropic 9-point Laplacian (§12.2D) is new on `wave-tank` only.
- Fold-count material (§12.2E) is new on `gen-string-theory-structure` only.
- Cauchy split and Beer–Lambert (§12.2F) are new on `photonic-caustics-graph` only.
- No grain, halation, thin-film, cos⁴, step-count AO, or a new spring.

Prelude migration on the pasted headers is infrastructure (`migrate_to_prelude.py`). It is not an idea and does not by itself bump `Upgraded:`.

`gen-astro-orrery-blackbody` and `gen-string-theory-structure` have an empty `params` array, so the UI shows four generic sliders that the shader currently multiplies by zero. Named params are added whose **defaults reproduce the previous constants**. Existing ids on the other eight shaders are not renamed or re-defaulted.

```
SHADER: predator-prey-ecology
IDENTITY (one sentence): packed Lotka–Volterra pixels — green prey flora against orange predator fauna, nutrient drawn from the photo, hold to seed, clicks bloom prey.
KEEP VERBATIM: eat / death / mutation / breed roles; packing .r prey, .g predator, .b nutrient, .a age; 5-point diffusion; held disk and click bloom; flora/fauna composite; render copies the raw state back to A
MECHANISM INTERROGATION:
  tactic 2: a real predator saturates (Holling), and grazing leaves a nutrient scar the photo slowly refills
  tactic 3: age is incremented and never read; death is a flat rate
  tactic 6: C is the raw field. Nutrient is pulled toward photo luma every frame and never spent
ADD:
  1. Holling type II intake — the existing prey×predator term saturates, matched to the old mass-action at moderate prey so blooms are not rewritten
  2. Nutrient grazing scar — prey spends .b, then the photo refills it at the existing 0.04 mix
  3. Age cohorts — .a yellows old flora and darkens old fauna, and slightly raises death. Death Rate still owns the base
FORBID on this file: a new palette, a spring, replacing the CA with agents
A PACKING: raw sim (prey, predator, nutrient, age). ACES on the render display only
```

```
SHADER: gen-astro-orrery-blackbody
IDENTITY (one sentence): a parallax starfield and one glowing spiral annulus, mixed with the photo and a same-pixel trail.
KEEP VERBATIM: three parallax star layers; the annulus mask smoothstep(0.4, 0.3, r) * smoothstep(0.1, 0.15, r); spiral sin(r·freq − time·2 + a·3); photo mix 0.6; bass on the disk, mids on frequency, treble on stars
MECHANISM INTERROGATION:
  tactic 2: an orrery has more than one ring, and each ring's heat is a blackbody, not one orange
  tactic 3: the star hash never becomes a temperature; the trail samples the same pixel
  tactic 6: C is display colour. A step against the spiral's rotation is the orbital wake
ADD:
  1. Flanking rings — the same spiral on an inner and an outer annulus. Ring Spread shows them; at the default they are on, and at 0 only the original annulus remains
  2. Blackbody chromaticity (§12.2F) — Tanner Helland. The main ring's default temperature (~2000 K) stays the old orange; inner runs hotter, outer cooler; stars take a temperature from their hash
  3. Orbital wake — exact C, a short step against the spiral's rotation. Trail amount stays the old 0.8 at the default
FORBID on this file: a spring, a new creature, replacing the starfield with a raymarched system
A PACKING: ACES display RGBA. The pointer offsets the ring centre (the file already claims mouse-driven); no spring
```

```
SHADER: sim-smoke-trails-thermal
IDENTITY (one sentence): a smoke puff advected by its own velocity, rising with temperature, curled by density, coloured as heat, with the photo seen through Beer transmittance.
KEEP VERBATIM: packing density, temperature, velocity; semi-Lagrangian step; 4-neighbour blend; density curl; rise with temp; held source; click rings; transmittance exp(−density·scale); four param roles
MECHANISM INTERROGATION:
  tactic 1: one forward sample smears the puff; a backward correction is the next term of the same advection
  tactic 2: the colour is a gray-to-orange lerp. The shader's name is the Planck curve of that temperature
  tactic 6: C is the raw state. Do not store display colour in A
ADD:
  1. MacCormack correction (§12.2D) on density and temperature only, clamped to the 5-neighbour range. Velocity integration is unchanged
  2. Blackbody chromaticity (§12.2F) of the stored temperature — ember at the cool end, blue-white at the hot end. Thermal Intensity still scales radiance. ACES on the display only
FORBID on this file: a second fluid solver, an IQ palette, packing colour into A
A PACKING: raw sim (density, temperature, velocity). Unchanged
```

```
SHADER: gen-string-theory-structure
IDENTITY (one sentence): a four-fold abs-rotated projection whose zero-crossings glow as vibrating strings, mixed with the photo and a trail.
KEEP VERBATIM: four iterations; rotate then abs(z)−gap then ×1.5; vibe = sin(dist·freq − time·5)·cos(z.x·15 + time·3); photo mix 0.7; bass on the fold angle, mids on the gap offset, treble on the glow
MECHANISM INTERROGATION:
  tactic 2: a string has a bright core and a dim sheath, not one 1/|vibe| spike
  tactic 3: each abs() throws away the sign. That count is how many times the point was folded
  tactic 6: C is display colour, currently re-read at the same pixel. A step against the fold's rotation is the wake
ADD:
  1. Core and sheath — the existing 1/|vibe| splits into a tight peak and a wider dim shoulder. Glow still sets the amplitude; the default peak matches the old 0.05/0.01
  2. Fold-count material (§12.2E) — signs counted before each abs tint the string. The fold loop is otherwise the same
  3. Rotational wake — exact C, a small unwind of the domain rotation. Trail default 0.85 matches the old mix
FORBID on this file: a spring, a Calabi–Yau raymarch, an IQ palette as the look
A PACKING: ACES display RGBA
```

```
SHADER: jfa-aurora-voronoi
IDENTITY (one sentence): jump-flood Voronoi from the pointer, clicks, and random seeds, coloured as an aurora by seed id and distance.
KEEP VERBATIM: packing seed.xy, dist², id; 3×3 flood; mouse disk; click seeds; random spawn from Glow; aurora() palette; hue and glow param roles; render copies the field back to A
MECHANISM INTERROGATION:
  tactic 1: the flood repeats eight times at one jump. A jump flood halves the step
  tactic 3: dist² is only a radial darkening. Its gradient is the cell wall, which the render throws away
  tactic 6: C is the flooded field. The seed pass must reset the step counter or the next frame keeps shifting
ADD:
  1. Halving jump schedule — Jump Scale still sets the first step (default 0.5 starts at 128, and 128+64+…+1 matches the old 32×8 reach). extraBuffer[133] counts the repeat, single writer at (0,0), reset by the seed pass
  2. Cell-wall curtains — a finite difference of distance draws the Voronoi edge, and a slow sheet along that edge is the aurora hanging on the boundary
FORBID on this file: a new palette, a spring, replacing JFA with a noise Voronoi
A PACKING: raw flood field (seed xy, dist², id). ACES on the render display only
```

```
SHADER: photonic-caustics-graph
IDENTITY (one sentence): a rippled pool, photons refracted by its normal with a per-channel IOR, presented as chromatic caustics over the photo.
KEEP VERBATIM: emit normal from depth + fbm; packing normal.rgb + light height; 16 photons, Fresnel–Schlick, Snell with TIR; IOR / light size / dispersion / intensity roles; click rings in the accumulate pass; specular and the existing rim
MECHANISM INTERROGATION:
  tactic 1: dispersion is a linear ±δ. Cauchy is the curve of that same split
  tactic 2: a photon through water loses red first. The path length is already computed and only used as 1/(1+dist)
  tactic 6: the trace repeats twice and the second pass reads the caustic as if it were a normal. The height channel tells them apart (normals are ≤0.63 or ≥1.7, the caustic stores 1)
ADD:
  1. Cauchy IOR split (§12.2F) — n(λ)=A+B/λ² on the existing R/G/B photons. Dispersion still sets B
  2. Beer–Lambert in the pool (§12.2F) — the existing distance eats red before blue
  3. Second batch adds — when the incoming field is a caustic, rebuild the normal from depth and add the new photons onto it, so the ×2 trace accumulates instead of refracting the caustic
FORBID on this file: a thin-film look, a spring, a new photon solver
A PACKING: emit stores the normal; trace and accumulate store the caustic rgb. ACES on the present pass only
```

```
SHADER: luma-flow-field
IDENTITY (one sentence): the photo advected along its own iso-luminance, plus a curl ribbon, a pointer vortex, and click fronts, with a trail in C.
KEEP VERBATIM: Flow Scale / Trail Decay / Curl Strength / Audio Sensitivity; isoFlow from the luma gradient; curl noise; pointer vortex; click fronts; the existing one-sided LIC mix and the stagnation hold
MECHANISM INTERROGATION:
  tactic 1: the LIC sample steps only downstream. Line integral convolution integrates both ways
  tactic 3: the four luma taps already imply a Laplacian. Concave pockets are where a flow pools
  tactic 6: C is display history. The second sample is the same history, upstream
ADD:
  1. Bidirectional LIC — the existing downstream history sample averaged with the upstream one, same Trail Decay weight
  2. Pooling in luma hollows — the Laplacian of the taps already fetched holds the trail where the photo is a dark pocket
FORBID on this file: a new palette, a spring, a second flow field
A PACKING: HDR display-history RGBA (unchanged). ACES on the display
```

```
SHADER: physarum-agents
IDENTITY (one sentence): Jones 2010 agents on a torus sense a pheromone trail, turn, deposit, and render as bioluminescent veins over the photo.
KEEP VERBATIM: FOOD_W, WANDER, DEP0, TRAIL_CAP (the CPU spec test); sense angle / distance / speed / persistence; 3-sensor steer; torus wrap; deposit race rule; click bloom; lure while held; nutrient / vein / living-front render
MECHANISM INTERROGATION:
  tactic 2: a real plasmodium pulses along a vein, and an old vein dries darker than the tip that just deposited
  tactic 3: deposit time is already in .g and only drives the living-front flare. The complement is the dried tube
  tactic 6: the solver packing stays .r trail, .g last deposit time. Do not change the steer
ADD:
  1. Dried-tube crust — dense trail whose deposit time is old shifts from the vein tint toward ochre. The living front still flares on top
  2. Peristaltic pulse — brightness travels along the trail tangent the render already derives from the gradient
FORBID on this file: changing the steer or the deposit constants, a spring, a second organism
A PACKING: raw trail (.r amount, .g last deposit time). The render pass does not write A. ACES on the display
```

```
SHADER: sim-sand-dunes-rgba
IDENTITY (one sentence): four grain populations — fine, coarse, moist clumps, airborne dust — blown, settled, and avalanched, with the photo showing through.
KEEP VERBATIM: packing; Gravity / Wind / Moisture / Dustiness; size segregation (coarse into troughs, fine saltating); dust-devil swirl; held deposition; click dust fronts
MECHANISM INTERROGATION:
  tactic 2: sand holds a slope until the angle of repose, then the face slips. Wet sand holds a steeper face
  tactic 3: the bed slope is already the vertical neighbour difference, and it is only a gentle gravity term
  tactic 6: C is the four populations. Dust falls out on the lee side of a ridge and becomes fine grains
ADD:
  1. Angle of repose — excess downhill slope avalanches, and Moisture raises the threshold. Gravity still scales the flux. Mass moves from the upper pixel to the lower one
  2. Lee-side saltation fallout — airborne dust settles where the upwind neighbour's bed is higher, and returns to the fine population. Wind still sets the direction
FORBID on this file: a new population channel, a spring, a blackbody grade
A PACKING: raw (fine, coarse, moist clumps, airborne dust). Unchanged. ACES on the display
```

```
SHADER: wave-tank
IDENTITY (one sentence): a 2D wave tank — height and velocity integrated from a Laplacian, stirred by the pointer and clicks, drawn with refraction, phase hue, and caustic sparkle.
KEEP VERBATIM: packing height, velocity, previous height, phase; Wave Speed, Damping, Source Strength, Boundary Reflect; the explicit velocity step; edge absorb; pointer oscillator; click injection; phase hue and the Laplacian sparkle
MECHANISM INTERROGATION:
  tactic 1: the stencil is a 5-point cross, so rings prefer the axes. The 9-point stencil is the same operator
  tactic 3: .b is documented as previous height and is copied unchanged, so a crest never knows it is rising
  tactic 6: C is the raw wave. Latching .b to the height before the update gives the render one substep of rise
ADD:
  1. Isotropic 9-point Laplacian (§12.2D) — corners included, gain matched to the old 5-point on a purely horizontal wave so Wave Speed still means the same thing
  2. Rising-crest foam — the step stores the pre-update height in .b, and the render whitens where that crest is high and still rising
FORBID on this file: a second wave equation, an IQ palette, packing display colour into A
A PACKING: raw wave (height, velocity, previous height, phase). ACES on the render display only
```
