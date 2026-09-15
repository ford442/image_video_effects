# BRIEFS — Classic math / CA / reaction leftover six

Batch: `cursor/classic-math-leftover-six-eb4c` · 2026-09-15 · Muse Spark (Flash class: 6 shaders)
Live contract: `docs/SHADER_UPGRADE_BATCH.md` (Idea Cards first; plumbing is floor, not upgrade).

## Selection rule (objective backlog, one family)

Next clean leftover after the 09-13/09-14 unions. The 09-13 note listed the remaining
classic math/CA as: rgb-diffraction / Langton / Klein / Verlet cloth / Koch /
phyllotaxis / Sierpinski tet / Newton. Since then Langton, Klein, Koch, phyllotaxis,
Newton (+ percolation, mandelbox, field-warp) all landed dated `Ideas:` headers on
main (09-13/09-14 batches). Untouched from that list: **rgb-diffraction,
verlet-cloth-wind, sierpinski-tetrahedron** — none carries an `Ideas:` line.
Family completion (+3): **cellular-automata-tapestry** (Gray-Scott CA, 05-31, no
Ideas), **audio-spirograph-julia** (spirograph/Julia math, no `Upgraded:` date at
all, no Ideas), **belousov-zhabotinsky** (excitable-media RD, 06-07 hygiene, no
Ideas). All six verified `grep -c '^//  Ideas:' == 0` on main at branch time.

Skipped deliberately (unchanged): `gen-percolation-threshold` (writes
extraBuffer[0..] spanning labels — engine FFT zone; needs its own redesign, not a
batch slot), tropism-rich `mycelium-network`, physarum extraBuffer[0..] agents,
`crt-clear-zone` (different family — visual-effects), blackbody Phase-C (own batch).

Claimed IDs (no other agent should touch these in this batch):
gen-rgb-diffraction, gen-verlet-cloth-wind, gen-sierpinski-tetrahedron,
gen-cellular-automata-tapestry, gen-audio-spirograph-julia, gen-belousov-zhabotinsky.

---

```
SHADER: gen-rgb-diffraction
IDENTITY (one sentence): a 6-slit diffraction-grating star-burst — sinusoidal
  interference fringes with per-channel spectral splitting under 6-fold
  kaleidoscopic symmetry.
KEEP VERBATIM: slitIntensity() sinc envelope + 6-slit loop, applySymmetry()
  6-fold mirror, zoom_params roles (speed / fringe freq / chromatic spread /
  brightness), per-band audio chromatic offsets, vignette.
ADD (2 native ideas):
  1. Single-slit diffraction envelope — a real grating's multi-slit fringes sit
     inside a broad Airy/sinc envelope centered on the optical axis; multiply
     the fringe sum by it so the burst has a physical center-to-edge falloff.
     Belongs: this IS a grating simulation.
  2. Blaze-angle steering — a per-slit phase ramp that steers the principal
     maxima off-axis (blazed gratings do exactly this), driven by mouse.x/y.
     Belongs: gives the file its first pointer response through grating physics.
FORBID on this file: extraBuffer springs/ripples, IQ palette wash, replacing the
  slit sum with fbm plasma.
A PACKING: ACES display RGBA (C read as color history).
FLOOR NOTES: add ACES (currently clamps to 3.0 with no tonemap); replace the
  filtering textureSampleLevel(dataTextureC) with exact textureLoad; JSON params
  stay byte-exact (empty params + aligned updatedParams kept as-is).
```

```
SHADER: gen-verlet-cloth-wind
IDENTITY (one sentence): a 64x64 Verlet cloth lattice blown by gust noise with
  pinned top row, mouse poke, and fabric/spec/SSS shading.
KEEP VERBATIM: h/v lattice sim in A.rg on the 64x64 region, pinned top row,
  three-octave noise wind + gravity + Laplacian*stiffness, mouse poke force,
  bilinear height sample, fabric/spec/backlight/SSS shade chain, ACES.
ADD (2 native ideas):
  1. Gust-front propagation — wind arrives as a traveling front swept across the
     cloth (phase-delayed by lattice x, speed on p1) instead of uniform noise,
     so gusts visibly cross the fabric. Belongs: this is a wind shader.
  2. Thread-tension sheen — stretch magnitude (|grad h|) brightens anisotropic
     warp/weft thread highlights along the lattice axes. Belongs: this is cloth.
FORBID on this file: extraBuffer springs (poke is already direct), IQ palette,
  replacing the lattice with display-history sparkles.
A PACKING: raw sim (h, v, 0, 0) on the 64x64 lattice (C read as fields there);
  every other pixel writes ACES display RGBA (never read back — C reads clamp
  into the lattice). Documented explicitly, not in silence.
FLOOR NOTES: HEAD only writes dataTextureA inside the lattice — all other pixels
  now write A every frame (same display RGBA, unread region). Ideas header added.
```

```
SHADER: gen-sierpinski-tetrahedron
IDENTITY (one sentence): a chaos-game Sierpinski tetrahedron projection with
  vertex/edge/shell orbit traps and a domain-warped jewel background.
KEEP VERBATIM: V/E tetra tables, branchless-argmin chaos loop, minTrap/trapIdx/
  density shade chain (jewelColor + edge spec + Schlick fresnel), warp/curl/
  worley background, ACES, raw trap-state A packing (C.r blended as minTrap).
ADD (2 native ideas):
  1. Iteration-depth shelving — band the color by how many chaos-game steps it
     took to settle (escape-iteration gradient over the trap field), giving the
     solid faces depth strata native to the fractal.
  2. Edge-current flow — audio-paced brightness pulses traveling along the 6
     tetra edges, parameterized by the existing edgeTrapSq (current position =
     fract(time*speed + edge phase)). Belongs: the edges are already trapped.
FORBID on this file: palette replacement, new springs, touching the argmin loop
  structure.
A PACKING: raw trap state (minTrap, trapIdx, density, alpha) — unchanged.
FLOOR NOTES: move smoothed-audio + mouse-smooth + click state from
  extraBuffer[0..5] (engine-reserved + FFT zone — stomped by the engine) to
  extraBuffer[133..138] with single-writer (0,0) guards; reads updated to match.
  Ideas header added.
```

```
SHADER: gen-cellular-automata-tapestry
IDENTITY (one sentence): Gray-Scott reaction-diffusion (A/B fields) with
  video-luminance-modulated feed/kill, seasonal plasma coloring, and mouse
  nutrient injection.
KEEP VERBATIM: GS update + 3x3 convolution, luminance feed/kill modulation,
  seasonal plasma map over B, mouse B-inject intent, raw sim A packing
  (nextA, nextB, 0, 1). Saved params byte-exact.
ADD (2 native ideas):
  1. Kill-rate contour banding — isochrone bands of B concentration over the
     growth front (native RD visualization: band spacing reads local wave speed).
  2. Diffusion-anisotropy warp — a slow-rotating directional bias on the
     Laplacian taps that grows oriented Turing stripes (native to RD: anisotropic
     diffusion orients the pattern).
FORBID on this file: extraBuffer springs, replacing Gray-Scott with BZ kinetics,
  touching param roles.
A PACKING: raw sim (nextA, nextB, 0, 1) — unchanged.
FLOOR NOTES: exact textureLoad(dataTextureC) for the center + 4 Laplacian taps
  (HEAD filters rgba32float history — invalid); add ACES on the display write
  (HEAD has none); gate the mouse inject on pressed (zoom_config.w) instead of
  mouseY (zoom_config.z) — preserves the injector intent, stops always-on flood.
  Ideas header added.
```

```
SHADER: gen-audio-spirograph-julia
IDENTITY (one sentence): five epitrochoid spirograph rings with embedded Julia
  coloring under a fullscreen Julia overlay, composited over trail feedback.
KEEP VERBATIM: epitrochoid() rings + ratio/harmonic tables, julia() smooth
  iteration, mouse→juliaC mapping with auto drift, trailLength feedback blend,
  five-ring nearest-curve glow+core composite. Saved params byte-exact
  (freq / julia / trail / thickness).
ADD (2 native ideas):
  1. Hypotrochoid inner-loop family — even rings draw the inner-rolling
     (hypotrochoid) curve form while odd rings keep the outer epitrochoid, so
     the five harmonics split into two visible curve families. Belongs: curve
     math, no param theft (parity-selected, immediate).
  2. Julia orbit-trap filaments — trap the Julia orbit's minimum radius along
     each curve sample and darken/thin the glow into neon filaments where the
     orbit stays bounded. Belongs: Julia math already computed per sample.
FORBID on this file: extraBuffer springs, particle replacement, IQ wash over the
  HSL ring hues.
A PACKING: ACES display RGBA (C read as color history) — unchanged.
FLOOR NOTES: replace the u.zoom_config.x time-proxy "audio" with real
  bass/mids/treble from plasmaBuffer (anti-pattern fix); ACES on the display
  write (HEAD has none); semantic alpha from glow/core energy instead of
  hardcoded 1.0; truthful depth (curve energy) instead of 0.0. Ideas header added.
```

```
SHADER: gen-belousov-zhabotinsky
IDENTITY (one sentence): Belousov-Zhabotinsky activator/inhibitor spiral waves
  with oxidized color ramp, wavefront glow, and mouse seeding.
KEEP VERBATIM: (a,b) epsilon/Da/Db/feed update, spiral+hash seed, blue→orange
  oxidized ramp, waveFront glow, mouseDown seed, raw A packing
  (newA, newB, waveFront, alpha) + B detail channel (lapA, lapB, oxidized,
  waveFront^2). Saved params byte-exact.
ADD (2 native ideas):
  1. Refractory-tail shading — a trailing-edge dark band behind the wavefront
     (excitable media have a refractory period; the tail width reads recovery).
     Belongs: BZ kinetics.
  2. Pacemaker excitability gradient — a slow spatial gradient on epsilon that
     forms target-wave pacemaker zones where waves originate. Belongs: real BZ
     dishes are paced by heterogeneities.
FORBID on this file: replacing BZ with Gray-Scott, extraBuffer springs, touching
  param roles or the B detail packing.
A PACKING: raw sim (newA, newB, waveFront, alpha) + B detail — unchanged.
FLOOR NOTES: exact textureLoad(dataTextureC) for center + 4 neighbor taps
  (HEAD filters rgba32float history — invalid); branchless seed/select cleanup
  kept minimal (seed if kept as-is). Ideas header added.
```
