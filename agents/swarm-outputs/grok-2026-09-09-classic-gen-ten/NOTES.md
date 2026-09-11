# Classic generative geometry / fractal ten — NOTES

Per shader: kept verbatim, packing, which ideas are visible in the diff. Floor (bindings / 16×16 / ACES / exact C / plasma audio) was already present; this batch is the Idea Cards.

---

## gen-julia-set-classic
- KEPT: cReal/cImaginary/zoom/iterations; z²+c; axis+circle traps; held C mix; click z0 warp
- A PACKING: raw HDR display RGBA in A; ACES on writeTexture
- IDEAS IN DIFF: `dz` derivative + `deEdge` (exterior DE); `stripeAcc` from `sin(log(r2))`

## gen-fractal-flame-classic
- KEPT: iterations/variationMix/flameZoom/paletteCycle; swirl/horseshoe/polar; warm vs spectral
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `spherical = z/(r*r)` IFS pick when `pick > 0.72`; `logDensity = log(1+(density+edgeTrap)*8)`

## gen-flame-fractal-attractor
- KEPT: attractorStrength/orbitSpeed/curl/emberBloom; abs-fold; |xy| filament
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `crease` on `min(|folded.x|,|folded.y|)`; `evenDen`/`oddDen` inner vs outer curls

## gen-fractal-tree-growth
- KEPT: branchDepth/spread/growthPhase/leafGlow; binary paths; pointer wind; leaf blobs
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `sdSegment2` returns `h` → bark `rings`; apical `bud` from `levelGrowth*(1-levelGrowth)`

## gen-fibonacci-spiral-garden
- KEPT: spiralScale/growthCycle/petalSize/bloom; GOLDEN_ANGLE; 96 nodes; 5-lobe petals
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `pack = mix(1.18, 0.48, sqrt(n))`; `para8`/`para13` ridges

## gen-islamic-geometric-tiling
- KEPT: starPoints/tileScale/lineWidth/ornamentDepth; brick offset; star+interlace; rosette rings
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `underShadow` at star/interlace overlap; `dart` half-angle girih star

## gen-ice-crystal-lattice
- KEPT: latticeDensity/branching/growthSpeed/frostGlow; 60° lattice; 6-fold needles; nucleation
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `dendrite` teeth on hex `arm`; `plateFill` from hex interior × slow-growth habit

## gen-interference-moire-field
- KEPT: lineDensity/crossingAngle/warpStrength/colorPhase; two rotated sin fields; product ridges
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `densB = density * 1.068` detune beat; `young` path-difference from origin vs `srcB`

## gen-iris-bloom-fractal
- KEPT: petalCount/bloomDepth/aperture/colorCycle; polar lobes; pupil; veins; limbal
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `collarette` zigzag at `aperture*1.38`; `crypts` darken near pupil

## gen-flowing-silk-ribbons
- KEPT: ribbonCount/flowSpeed/silkWidth/iridescence; sine lanes; slope sheen; pointer comb
- A PACKING: raw HDR display RGBA in A
- IDEAS IN DIFF: `warp` periodic along `p.x`; `selvage` at `d ≈ width*0.88`

---

Floor: no new extraBuffer springs. Existing click ripples kept. Saved `params` byte-exact; `upgraded-rgba` added to JSON features only.
