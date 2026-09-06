# Grok batch — simpler generative / kinetic (10) B — Idea Cards

Written **before** WGSL. Catalog IDs use hyphens; `gen-cyclic-automaton` and `gen-fluffy-raincloud` are underscore-backed. Identity is the **current kernel**.

---

SHADER: gen-barnsley-fern
IDENTITY: inverse Barnsley IFS fern (stem + three leaflet affines)
KEEP VERBATIM: scale / CA / brightness / feedback; pickIFS probabilities; barnsleyInv; existing spring
ADD:
  1. Transform-class tint — last affine (stem vs leaflets) colours the frond (this is an IFS fern)
  2. Stem rib — extra density when the last inverse was idx 0 (the stem map)
FORBID: replacing the fern with Voronoi-as-the-picture; extra IQ overlay
A PACKING: ACES display RGBA (HEAD)

---

SHADER: gen-apollonian-gasket
IDENTITY: iterative circle inversion on a Descartes-style packing
KEEP VERBATIM: recursion / inversion / size / rainbow; five seed circles; circle_inv
ADD:
  1. Packing rims — bright |d−r| on the five seed circles (gasket, not a nebula)
  2. Curvature tint — last inverted circle’s k=1/r shifts hue (Descartes)
FORBID: springs as the upgrade (pointer inversion already exists)
A PACKING: linear RGB in A then ACES display (HEAD)

---

SHADER: gen-conway-game-of-life
IDENTITY: coarse-grid Life with Classic / Day&Night / HighLife morph
KEEP VERBATIM: seed / morph / grid / decay; B3/S23 family; packing r=alive g=generation b=activity
ADD:
  1. Neighbor heat — live cells tint by neighbor count (isolation vs crowd)
  2. Still-life amber — low-activity survivors (not birth/death flash)
FORBID: SmoothLife rewrite; extra springs as the look
A PACKING: raw CA (alive, generation, activity, alpha)

---

SHADER: gen-cyclic-automaton (`gen_cyclic_automaton.wgsl`)
IDENTITY: Greenberg–Hastings excitable media (rest / fire / refractory). Not a classic k-cyclic CA.
KEEP VERBATIM: States / Spontaneity / Bloom / Cooldown; cardinal ignition; A = (state, fire, refract, bloom)
ADD:
  1. Wave chirality — firing colour from which cardinal neighbor is on (N/E/S/W)
  2. Just-fired halo — extra glow at nextState==2 (first refractory step)
FORBID: Conway overlay; new extraBuffer slots
A PACKING: raw GH state

---

SHADER: gen-chaos-game-ifs
IDENTITY: chaos-game toward 3 rotating vertices + existing orbit sculpture
KEEP VERBATIM: iterations / glow / rings / sat; ifsPoint; existing SDF hero
ADD:
  1. Vertex occupancy — last picked attractor (a1/a2/a3) tints RGB
  2. Sierpinski hole — darker where the last step is far from all three vertices
FORBID: a second raymarcher as the upgrade
A PACKING: ACES display RGBA (HEAD stores display in A)

---

SHADER: gen-bifurcation-diagram
IDENTITY: logistic-map r vs x density + Lyapunov
KEEP VERBATIM: r position / zoom / iterations / color scheme; logistic loop; lyap
ADD:
  1. Continuous scheme mix — Color Scheme slider blends neighboring palettes (not 4 hard bands)
  2. Period-window ridges — extra mark where lyap ≈ 0 (period-doubling edge)
FORBID: more click-wave overlays as the upgrade
A PACKING: HDR density color in A (HEAD)

---

SHADER: gen-acid-lissajous
IDENTITY: sampled sin(ax+φ), sin(by) neon strands
KEEP VERBATIM: speed / complexity / glow+gravity / feedback; STRANDS×SAMPLES
ADD:
  1. Origin crossings — extra bead where a strand passes near 0 (Lissajous nodes)
  2. Ratio waist — glow boosted when |freqX−freqY| is small (near 1:1 ellipse)
FORBID: replacing curves with a particle field
A PACKING: ACES display RGBA

---

SHADER: gen-audio-spirograph
IDENTITY: epitrochoid + hypotrochoid trails at musical ratios
KEEP VERBATIM: freq / audio / trail / thickness; epi + hypo loops
ADD:
  1. Additive gears — all curves contribute (not winner-take-all minDist)
  2. Rolling-center dots — small hubs at the generating circle centers
FORBID: Fourier-epicycle clone overlay
A PACKING: history RGB + coverage (HEAD)

---

SHADER: gen-cycloid-bloom
IDENTITY: nested hypotrochoids as a floral mandala
KEEP VERBATIM: spin / petals / glow / persistence; coarse+refine search
ADD:
  1. Parameter vein — brightness along bestT (petal midrib)
  2. Stamen core — extra tight hypotrochoid at the origin
FORBID: extraBuffer springs (HEAD is not spring-owned)
A PACKING: ACES display RGBA

---

SHADER: gen-fluffy-raincloud (`gen_fluffy_raincloud.wgsl`)
IDENTITY: curl-noise cloud + rain sheet + Mie lining. Packing is density/vel/moisture.
KEEP VERBATIM: coverage / turbulence / rain / wind; vorticity; A = (ρ, vx, vy, moisture)
ADD:
  1. Anvil deck — flatten / spread density at the cloud top
  2. Virga — rain streaks that fade before the ground
FORBID: replacing the solver with display sparkles; new extraBuffer
A PACKING: raw density, velocity.xy, moisture
