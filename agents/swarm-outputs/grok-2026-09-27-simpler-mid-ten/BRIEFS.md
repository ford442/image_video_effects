# Grok batch — simpler / mid generative ten — Idea Cards

Written **before** WGSL. Eight files already had dated cards; those mechanisms stay. Two new ideas each. Art Deco Sky and Alien Flora had no `Ideas:` line. Do not touch `gen-art-deco-sky-prismatic` or `gen-alien-flora-ecosystem`.

---

SHADER: gen-acid-lissajous
IDENTITY: sampled sin(ax+φ), sin(by) neon strands
KEEP VERBATIM: speed / complexity / glow+gravity / feedback; STRANDS×SAMPLES; origin-crossing beads; 1:1 glow waist; existing spring
ADD:
  1. Cusp dwell — nearest sample brightens where parametric speed is near zero (Lissajous cusps)
  2. 2:1 lobe split — when |freqX−freqY| is near 1, tint by the sign of that sample’s y (figure-eight lobes, not the 1:1 waist)
FORBID: replacing curves with a particle field; new springs
A PACKING: ACES display RGBA

---

SHADER: gen-audio-spirograph
IDENTITY: epitrochoid + hypotrochoid trails at musical ratios
KEEP VERBATIM: freq / audio / trail / thickness; epi + hypo loops; additive gears; rolling-center hubs; existing spring
ADD:
  1. Stator ghost — faint circle of radius R so the fixed gear is visible
  2. Cusp flash — brighten where consecutive segment tangents reverse (roulette cusp)
FORBID: Fourier-epicycle clone overlay; new springs
A PACKING: history RGB + coverage

---

SHADER: gen-barnsley-fern
IDENTITY: inverse Barnsley IFS fern (stem + three leaflet affines)
KEEP VERBATIM: scale / CA / brightness / feedback; pickIFS probabilities; barnsleyInv; last-affine tint; idx-0 stem rib; existing spring
ADD:
  1. Pinna rachis — thinner rib when the last map is idx 2 or 3, separate from the stem
  2. Crozier — extra curl density at the high-y tip
FORBID: replacing the fern with Voronoi-as-the-picture; new springs
A PACKING: ACES display RGBA

---

SHADER: gen-apollonian-gasket
IDENTITY: iterative circle inversion on a Descartes-style packing
KEEP VERBATIM: recursion / inversion / size / rainbow; five seed circles; circle_inv; packing rims; last-k tint; existing spring
ADD:
  1. Generation stipple — ring frequency scales with invCount so deeper copies read finer
  2. Tangent kisses — bright contact sparks where two seed circles nearly touch
FORBID: springs as the upgrade; a different fractal
A PACKING: linear RGB + alpha (ACES on display)

---

SHADER: gen-aperiodic-monotile
IDENTITY: hat-field relief. Not a claimed exact mathematical monotile.
KEEP VERBATIM: scale / spin / edge / sat; hatTileField reflection and chevron brim; relief raymarch
ADD:
  1. Kite notch — a second concavity opposite the brim so cells interlock
  2. Metatile outline — a faint 4-cell super-hex so the field reads as clustered hats
FORBID: replacing the hat field with a different tiling; new springs
A PACKING: ACES display RGBA

---

SHADER: gen-bifurcation-diagram
IDENTITY: logistic-map r vs x density + Lyapunov
KEEP VERBATIM: r position / zoom / iterations / color scheme; logistic loop; continuous palette mix; lyap≈0 ridges; existing spring
ADD:
  1. Transient ghost — early pre-skip iterates drawn dimmer than the settled attractor
  2. Cobweb ticks — a few (x, rx(1−x)) marks in the column under the pointer
FORBID: more click-wave overlays as the upgrade
A PACKING: HDR density RGB + alpha

---

SHADER: gen-chaos-game-ifs
IDENTITY: chaos-game toward 3 rotating vertices + existing orbit sculpture
KEEP VERBATIM: iterations / glow / rings / sat; ifsPoint; last-vertex tint; Sierpinski hole; existing SDF hero and spring
ADD:
  1. Iterate age — late steps weigh more than early steps inside ifsPoint, so settled orbits read brighter
  2. Median scaffold — faint edges between the three vertices so the triangle is readable around the hole
FORBID: a second raymarcher as the upgrade
A PACKING: ACES display RGBA

---

SHADER: gen-conway-game-of-life
IDENTITY: coarse-grid Life with Classic / Day&Night / HighLife morph
KEEP VERBATIM: seed / morph / grid / decay; B3/S23 family; neighbor heat; still-life amber; packing r=alive g=generation b=activity; existing spring
ADD:
  1. Split deaths — neighbors < 2 cold, neighbors > 3 hot
  2. Glider lean — neighbor centroid tints the live cell toward the crowded side
FORBID: SmoothLife rewrite; extra springs as the look
A PACKING: raw CA (alive, generation, activity, alpha)

---

SHADER: gen-art-deco-sky
IDENTITY: infinite Art Deco ascent, black marble / gold / glass
KEEP VERBATIM: city density / ascent / gold glow / fog; fluting; gold bands; drag searchlight; click halos; plasmaBuffer bass and mids
ADD:
  1. Ziggurat setbacks — wall width steps in with the repeating tier so the shaft is stacked terraces
  2. Casement mullions — dark cross bars on glass so lit windows are a grid
FORBID: a new city motif; new springs (searchlight and halos already exist and are not the upgrade)
A PACKING: pre-ACES history RGB (ACES on display). Display alpha from emission and metal coverage.

---

SHADER: gen-alien-flora
IDENTITY: repeated swaying mushroom on rolling ground, with subsurface scatter
KEEP VERBATIM: density / sway / glow / color shift; stem+cap SDF; SSS; organic alpha
ADD:
  1. Gill ridges — grooves on the cap underside
  2. Spore motes — small spheres lifting off the cap rim, nudged by bass; treble glints them
FORBID: a different creature; new springs
A PACKING: linear history RGB + organic alpha (ACES on display only)
