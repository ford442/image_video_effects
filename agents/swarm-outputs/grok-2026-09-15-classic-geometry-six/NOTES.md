# Classic geometry leftover six — NOTES (2026-09-15)

Per shader: kept verbatim, packing, which ideas are in the diff.

## gen-3d-sierpinski-chaos

- KEEP: 4 tet vertices, warmup + pickVertex, density/speed/size/colorShift, extraBuffer[133] bassSmooth, mouse orbit.
- ADD 1: `repeatCorner` when `vi == lastVi`, boosts splat + glow.
- ADD 2: farthest-vertex `farIdx` drives face hue.
- A packing: ACES display RGBA; C already exact-loaded.
- Floor: ACES on write. No new springs.

## gen-aperiodic-monotile

- KEEP: Tile Scale / Rotation / Edge Width / Saturation; reliefDE sculpture; ACES mix with C.
- ADD 1: `chirality` flips local hex_q on odd (q,r) cells.
- ADD 2: `brim` sawtooth subtracted from hat distance.
- A packing: ACES display RGBA.
- Floor: unchanged bindings. No springs.

## gen-chromatic-zonohedron

- KEEP: Facet Scale / Spin / Edge Width / Color Cycle; 3 original axes; mouse pan.
- ADD 1: fourth generator `a3 = (0.809, 0.588)`.
- ADD 2: `win` generator index → hue.
- A packing: ACES display RGBA (was raw cell/hue while C is color).
- Floor: packing honesty. No springs.

## gen-zeta-function-landscape

- KEEP: Sigma / T Range / Height / Terms; eta continuation; click UV refraction; chromatic zeros.
- ADD 1: rails at 14.13 / 21.02 / 25.01 / 30.42, gated by |σ−1/2|.
- ADD 2: `isoContour` from `fract(log(1+|ζ|))`.
- A packing: ACES display RGBA; exact `textureLoad` C.
- Floor: FFT voice from extraBuffer[5..12] (read-only bins), not plasmaBuffer[1..]. No springs.

## gen-prismatic-mobius-helix

- KEEP: Coil Count / Ribbon Width / Helix Radius / Iridescence; sdMobius helix; mouse orbit.
- ADD 1: `seam = abs(sin(u))` glow on the half-twist join.
- ADD 2: `core = length(r−R, y)` spine before thickness.
- A packing: ACES display RGBA (was raw d/hue while C is color).
- Floor: packing honesty. No springs.

## gen-voronoi-crystal

- KEEP: Growth Speed / Count / Irregularity / Glow; f1/f2; extraBuffer[133..138] spring; rings; frost; click cracks.
- ADD 1: track f3; `triple` grain-corner spark.
- ADD 2: mix Euclidean with L∞ in the seed metric.
- A packing: ACES display RGBA.
- Floor: existing spring kept. No new springs.
