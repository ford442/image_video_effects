# Stateful-simulation six — Idea Cards (written before any WGSL edit)

Batch: 2026-09-21, fifth batch of the day. Theme: effects whose picture comes from a *rule* running
on state (cellular field, reaction-diffusion, flock, fluid, wet media, condensation, caustic light).
Every idea extends that rule; none paints over it.

Sources: `artistic` (66/99 without named ideas) and `simulation` (15/46).

**Read in full and excluded (rescues, not upgrades):**
- `physarum`: agents live in `extraBuffer[0..]`, which the renderer re-uploads every frame (and
  which holds audio/FFT at [0..132]). It only writes pixels where agents land, so the sim never runs.
  It needs a rewrite onto texture state.
- `navier-stokes-dye`: it writes velocity to A, then overwrites A with display colour, so the next
  frame reads colour as velocity. Its palette comes from `plasmaBuffer[0..255]`, which is never written.
  It also has a dead `advect_velocity` entry point. Rescue.
- `physarum-gemini`, `physarum-grokcf1`: variants of the above; not read.
- `multi-turing`: **carded, then pulled after CPU simulation** (card kept at the bottom for the record).
  HEAD's Gray-Scott runs with an unnormalised 5-point laplacian at DA = DT = 1, which is outside the
  explicit stability limit. Ported to numpy, the field is a clamped per-pixel checkerboard at every
  step (mean neighbour jump 0.81 of full range) and never forms a pattern. What users see today is
  that noise. With a stable kernel (Sims 0.2/0.05/−1) the field relaxes to a uniform state at the
  default params, because HEAD seeds b ≈ 0.4 everywhere. Even with sparse seeding, the default
  sliders stay uniform (b1 std 0.002); patterns only appear at other slider settings. A working
  version needs new init plus remapped feed/kill ranges, which is param theft on an upgrade. It needs a
  rescue pass with a preset migration, so it's not in this batch.

- `lenia`: **carded, then pulled after CPU simulation** (`lenia.py`, `lenia2.py`). HEAD stores the
  *thresholded* value `smoothstep(thr/2, thr, c)` as state. A dead cell gains at most
  growthRate = 0.05 per step against a 0.225 cutoff, so it never wakes, and a live cell never falls
  below it. The field is frozen binary stamps sliding on the conveyor (mean 0.044, constant over
  1500 steps). The nutrient idea changed nothing, since nothing grows. Storing the continuous value
  (real Lenia) makes it live, but at HEAD's params it floods to 0.68 coverage and churns. It needs a
  retuned growth window, which is rescue work.

**The batch is therefore 6, not padded.** Three of the four artistic "simulations" I read (physarum,
navier-stokes-dye, lenia) plus multi-turing turned out non-functional at runtime. See the rescue list in NOTES.

**No GPU here, so the sims are checked on the CPU:** the update rules of the stateful files are ported
to numpy in the batch scratchpad and run for thousands of steps, before and after each change.
Findings from those runs are in NOTES.

Forbidden across the batch: springs, ripple loops, cosine palettes, audio-dependent ideas (plasmaBuffer
is still unwritten).

---



```
SHADER: boids
IDENTITY: 256 flocking boids (separation/alignment/cohesion) stored in row 0 of A/C, splatted as
          velocity-coloured motion-blurred soft particles over a dimmed photo.
KEEP VERBATIM: state row 0 packing, the three rules and weights, speed limits, wander, the splat and
               tone-map, and all 4 params.
ADD:
  1. Blind spot — boids ignore neighbours in a ~100° cone behind them, as real birds and fish do.
     This gives the flock leaders, lines and V-shaped fronts instead of isotropic blobs.
  2. Held pointer is a predator — while held, the cursor repels with a strong short-range flee, and
     the flock splits around it and rejoins behind (the "fountain" manoeuvre). Hover keeps HEAD's
     attraction.
FORBID: trails via new packing, palettes.
A PACKING: row 0 = boid state (pos, vel). Unchanged.
```

```
SHADER: ion-stream
IDENTITY: vertical lanes of helical ion packets over a curl-advected photo, bent by a magnet at the
          cursor, with a C wake.
KEEP VERBATIM: lanes, helix, packets, curl flow, magnetic bend, C wake, click fronts, params.
ADD:
  1. Charge split — alternate lanes carry opposite charge, so the magnet bends them in opposite
     directions and the stream splits around the cursor like a mass spectrometer. Charge also biases
     the existing blue/violet ion colour.
  2. Cyclotron tightening — inside the magnet's field the helix winds faster and tighter (cyclotron
     frequency ∝ B, Larmor radius ∝ 1/B), so lanes coil into tight springs near the cursor.
FORBID: palettes, new overlays.
A PACKING: display RGBA (HEAD). Unchanged.
```

```
SHADER: sim-ink-diffusion-rgba
IDENTITY: wet-paper pigment simulation — CMY-ish pigment in rgb, water in a, diffusion gated by
          water, subtractive absorption on a paper/photo mix.
KEEP VERBATIM: 5-point stencil, water/pigment diffusion rates, mixing, brush, click rings,
               evaporation, the absorb display, params.
ADD:
  1. Edge darkening (coffee ring) — pigment is carried toward the drying edge (down the water
     gradient), so washes dry with dark rims. This is the signature of real watercolour (Curtis et al.).
  2. Granulation — as the paper dries, pigment settles into the paper's grain valleys (grain from the
     photo's fine luminance plus a fixed fibre hash), so dried washes get texture where wet washes
     stay smooth.
FLOOR: depth was never written; now a truthful pass-through.
A PACKING: raw state (pigment rgb, water a). Unchanged.
```

```
SHADER: steamy-glass
IDENTITY: fogged window — steam density, droplets, runoff and wipe memory in state; blurred refracted
          photo behind fog; held pointer wipes.
KEEP VERBATIM: 4-channel packing, steam relaxation, wipe/click clearing, blur and refraction, params.
ADD:
  1. Runoff rivulets — `runoff` (B channel) is computed every frame and never shown. Heavy droplets now
     feed it, it runs downward (HEAD already reads `top.b`), sweeps steam and droplets off its track,
     and it's drawn as a clear, refracting drip line.
  2. Beaded wipe edge — a wipe pushes condensate to its border, so droplets pile up along the rim of
     each wiped patch.
FORBID: palettes; changing the wipe feel.
A PACKING: raw state (steam, droplets, runoff, wipe memory). Unchanged.
```

```
SHADER: sim-fluid-feedback-coupled
IDENTITY: single-pass velocity/pressure/density feedback fluid with vorticity confinement, pointer
          stir, click fronts, spectral tint over the displaced photo.
KEEP VERBATIM: advection, viscosity, one Jacobi pressure step, confinement, stir, fronts, packing,
               spectral(), params.
ADD:
  1. Buoyant dye — density adds a downward (Boussinesq) force, so injected dye sinks in plumes and
     curls over (Rayleigh-Taylor fingers) instead of only swirling where it was stirred.
  2. Schlieren from pressure — the pressure field (A.z) is stored and never displayed. Its gradient
     now refracts the photo and shades it like a shadowgraph, so pressure waves from stirs and
     clicks become visible.
FORBID: palettes beyond spectral(); new forcing overlays.
A PACKING: raw state (velocity.xy, pressure, density). Unchanged.
```

```
SHADER: photonic-caustics
IDENTITY: photo seen through a refractive height field (from depth plus ripples) lit from the cursor,
          with chromatic band ribbons and persistent irradiance.
KEEP VERBATIM: height-from-depth normal, bend, aperture, dispersion bands, click light, persistence
               formula, ACES, params.
ADD:
  1. True Jacobian caustics — irradiance also gets 1/|det J| of the refraction map (det J ≈ 1 + k∇²h),
     per channel with the IOR spread, so light gathers into real bright caustic lines where the surface
     focuses and thins where it spreads. The header claims "height-field convergence"; HEAD only has
     analytic bands.
  2. Specular glint — Blinn-Phong highlight of the cursor light on the height-field normal, so the
     surface itself reads as wet glass.
FLOOR (stated): C held ACES display, including the source photo, but was mixed back as *irradiance*.
  The photo therefore fed itself into the light every frame (packing lie, washed-out highlights). A now
  stores raw irradiance, and C is read as irradiance.
A PACKING: raw irradiance rgb + caustic alpha (changed from display; see floor).
```

---

## Card corrections made during implementation

- **sim-ink-diffusion-rgba, idea 1:** the card said pigment would be *carried* down the water
  gradient in the state (coffee ring). Built in numpy first (`ink.py`). At HEAD's rates water
  diffuses and dries faster than a rim can build: the conservative flux version only bled pigment
  outward past the wash (rim/centre ≤ 0.94 at every gate/k tried), and HEAD's pigment itself
  evaporates in seconds by design. Replaced before any WGSL with Bousseau et al. 2006 display-time
  edge darkening on the pigment-density gradient, scaled by dryness. That keeps the state rule
  untouched. Idea 2 (granulation) moved to display for the same reason and uses the same model.
- **steamy-glass, idea 1:** the first numpy version released droplets as a steady trickle and never
  formed a visible bead (runoff < 0.05 everywhere). Changed to a burst at sparse nucleation sites
  (whole droplet mass released above 0.28). The thresholds in the WGSL are the tested ones.

---

## Pulled cards (not implemented)

```
SHADER: multi-turing
IDENTITY: two coupled Gray-Scott reaction-diffusion systems at two spatial scales (McCabe-style
          multiscale), seeded from the photo's luminance, coloured cyan/orange over the source.
KEEP VERBATIM: two GS systems, feed/kill param ranges, the scale 1 and scale 2 laplacian spacing,
               cross-scale coupling, seeding from luminance, pointer/click seeding, HSV colouring.
ADD:
  1. Coarse DoG band steers the fine scale — the file declares SCALE3/SCALE4, gaussianBlur() and
     differenceOfGaussians() and never calls them. A sparse ring DoG of the scale-2 field (scale 4 vs
     8 texels) nudges scale-1 feed, so the fine pattern organises inside large cells. That is the
     multiscale idea in the header.
  2. Photo-structured kill rate — source luminance shifts scale-1 kill, so the pattern changes
     morphology across the photo's tones (spots in shadows, labyrinths in highlights). HEAD only uses
     luminance at initialisation.
  3. Relief shading — the V field is lit as a height map (gradient · light), so the pattern reads
     as raised tissue rather than flat hue.
FLOOR (stated, not counted): the laplacian was the unnormalised 5-point stencil with DA=DT=1, which is
  outside the explicit stability limit. Checked on CPU: HEAD is a clamped per-pixel checkerboard and
  never forms a pattern. Replaced by Sims' 3×3 kernel (0.2 edges, 0.05 diagonals, −1 centre) at the
  same two spacings. Alpha was hardcoded 1.0 and is now pattern coverage.
A PACKING: raw state (scale1.ab, scale2.ab). Unchanged.
```

```
SHADER: lenia
IDENTITY: continuous cellular field (smooth growth function on a weighted neighbourhood mean), drifting
          on a conveyor, with growth packets and pointer inoculation.
KEEP VERBATIM: 1/(1+d²) neighbourhood, growthKernel(), conveyor, packets, click fronts, inoculation,
               species colouring, the accumulation/alpha blend, and all 4 params.
ADD:
  1. Photo as nutrient — source luminance shifts the growth balance, so life thrives on the photo's
     bright regions and starves in its shadows. The file never reads readTexture; the image app's
     image is invisible to the organism.
  2. Growth / decay tint — cells whose growth is positive glow warm and dying cells cool, which is
     Lenia's standard way of showing the living front. The `growth` value is computed and discarded.
FORBID: replacing the kernel family, new palettes.
A PACKING: HEAD (state in rgb, accumulated alpha in a). Unchanged.
```
