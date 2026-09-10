# Classic generative geometry / fractal ten — Idea Cards (written before WGSL)

Family: leftover catalog generative with a math/botanical/fabric identity (not another optical/holographic overlay). Two native ideas each. Identities kept. Existing pointer + click ripples kept; no new extraBuffer springs.

Claimed IDs: `gen-julia-set-classic`, `gen-fractal-flame-classic`, `gen-flame-fractal-attractor`, `gen-fractal-tree-growth`, `gen-fibonacci-spiral-garden`, `gen-islamic-geometric-tiling`, `gen-ice-crystal-lattice`, `gen-interference-moire-field`, `gen-iris-bloom-fractal`, `gen-flowing-silk-ribbons`.

---

SHADER: gen-julia-set-classic
IDENTITY: escape-time Julia set with orbit traps and pointer-controlled complex C
KEEP VERBATIM: cReal / cImaginary / zoom / iterations roles; z²+c loop; axis+circle traps; held-pointer C mix; click warp of z0
ADD (2 native ideas):
  1. Exterior distance estimate from |z|/|z'| — sharp set boundary on THIS escape-time field
  2. Stripe / binary-decomposition coloring from log|z| along the escaped orbit — classic Julia, not a new motif
FORBID on this file: springs, Mandelbrot rewrite, IQ palette as the whole look
A PACKING: raw HDR display RGBA in A (ACES on writeTexture only); C is previous Julia color

---

SHADER: gen-fractal-flame-classic
IDENTITY: IFS-style flame density from swirl / horseshoe / polar affine variations
KEEP VERBATIM: iterations / variationMix / flameZoom / paletteCycle; swirl vs horseshoe mix; polar mix; warm vs spectral palette
ADD (2 native ideas):
  1. Logarithmic density compression (Draves flame histogram) — log(1+ρ) instead of linear glow
  2. Spherical variation z/r² as a third IFS pick fused into the existing mix — native flame, not a new solver
FORBID on this file: cloning the fold-attractor shader, springs, replacing variations
A PACKING: raw HDR display RGBA in A

---

SHADER: gen-flame-fractal-attractor
IDENTITY: curling orbit-density fire from rotate-abs fold + curl, not classic flame variations
KEEP VERBATIM: attractorStrength / orbitSpeed / curl / emberBloom; abs-fold; filament |xy| trap
ADD (2 native ideas):
  1. Fold-crease specular along the abs() fold axes — this solver already folds
  2. Even/odd iteration ember bands so inner vs outer curls separate without a new attractor
FORBID on this file: spherical/horseshoe stamp from Classic Fractal Flame, springs
A PACKING: raw HDR display RGBA in A

---

SHADER: gen-fractal-tree-growth
IDENTITY: recursive binary-branch distance-field tree with growth phase and leaves
KEEP VERBATIM: branchDepth / branchSpread / growthPhase / leafGlow; sdSegment branches; binary bit paths; pointer wind
ADD (2 native ideas):
  1. Bark rings from segment parameter h — wood, not film grain
  2. Apical meristem glow on incomplete growth tips — this shader already has levelGrowth < 1
FORBID on this file: L-system rewrite, fireworks overlay, IQ garden palette takeover
A PACKING: raw HDR display RGBA in A

---

SHADER: gen-fibonacci-spiral-garden
IDENTITY: Vogel / golden-angle phyllotaxis blossom field
KEEP VERBATIM: spiralScale / growthCycle / petalSize / bloom; GOLDEN_ANGLE; 96-node unfurl; 5-lobe petals
ADD (2 native ideas):
  1. Disk packing — petal size falls with √n so florets kiss instead of random overlap
  2. Visible 8- and 13-family parastichy ridges on those same nodes
FORBID on this file: replacing golden angle, fireworks, a second unrelated flower species
A PACKING: raw HDR display RGBA in A

---

SHADER: gen-islamic-geometric-tiling
IDENTITY: interlaced star polygons and recursive rosettes on a brick-offset grid
KEEP VERBATIM: starPoints / tileScale / lineWidth / ornamentDepth; star+interlace; rosette rings; existing crossingMask seed
ADD (2 native ideas):
  1. Over-under strap shadow at star/interlace crossings — girih weave, not a new tile
  2. Half-angle girih dart star rotated in the same cell
FORBID on this file: kaleidoscope rewrite, holographic oil-slick, springs
A PACKING: raw HDR display RGBA in A

---

SHADER: gen-ice-crystal-lattice
IDENTITY: hexagonal frost lattice with 6-fold needles, growth front, nucleation
KEEP VERBATIM: latticeDensity / branching / growthSpeed / frostGlow; three 60° lattice lines; 6-fold needles; fracture clicks
ADD (2 native ideas):
  1. Secondary dendrite teeth along the hex arms (Nakaya side-branching)
  2. Plate vs needle habit — slow growth fills hex interiors as thin plates
FORBID on this file: generic snow overlay, replacing the hex lattice
A PACKING: raw HDR display RGBA in A

---

SHADER: gen-interference-moire-field
IDENTITY: crossed analytic line waves whose product is the moiré
KEEP VERBATIM: lineDensity / crossingAngle / warpStrength / colorPhase; two rotated sin fields; product ridges
ADD (2 native ideas):
  1. Density detune (~6.8%) on a second pair — classic beat envelope
  2. Two-source path-difference fringes (Young) from origin vs pointer/offset focus
FORBID on this file: holographic rainbow rewrite, springs, replacing lines with a raymarcher
A PACKING: raw HDR display RGBA in A

---

SHADER: gen-iris-bloom-fractal
IDENTITY: recursive polar iris with aperture, pupil, radial veins, limbal ring
KEEP VERBATIM: petalCount / bloomDepth / aperture / colorCycle; polar lobes; pupil hole; vein phase; limbal
ADD (2 native ideas):
  1. Collarette zigzag between pupil and mid-stroma — real iris anatomy on THIS polar field
  2. Fuchs crypts — dark pits near the pupil along petal lobes
FORBID on this file: turning it into a generic flower mandala, springs
A PACKING: raw HDR display RGBA in A

---

SHADER: gen-flowing-silk-ribbons
IDENTITY: layered anisotropic silk ribbons with slope sheen and iridescence
KEEP VERBATIM: ribbonCount / flowSpeed / silkWidth / iridescence; per-lane sine paths; slope sheen; pointer comb
ADD (2 native ideas):
  1. Warp threads along ribbon length (periodic along the weave)
  2. Selvage — bright thin edges vs the ribbon body
FORBID on this file: liquid solver, holographic oil-slick as the whole look (iridescence param stays a mix)
A PACKING: raw HDR display RGBA in A
