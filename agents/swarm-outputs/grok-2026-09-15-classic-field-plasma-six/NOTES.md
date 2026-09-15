# Classic field / plasma / crystal leftover six — NOTES (2026-09-15)

Cards written first in BRIEFS.md. Two native ideas each. No new springs.

## gen-strange-field-flow
KEEP: Drift/Chaos/Density/Persistence; de Jong + Clifford mix; 8 iters; hist rotate.
IDEAS IN DIFF:
  1. `lyap_acc += log(|Δstep|)` → stretch tint toward blue
  2. `pickover = min(|x|,|y|)` → stalk glow
A PACKING: ACES display RGBA (exact `textureLoad` C, including rotated hist UV)
FLOOR: ACES; swizzle assignment reconstructed; audio clamp

## gen-solar-wind-ribbons
KEEP: Ribbon Count / Twist / Speed / Glow; 64 samples; held-mouse steer; streaks
IDEAS IN DIFF:
  1. Parker lag `0.55 * |s|` inside `ribbonCentre`
  2. KH: perpendicular offset `sin(s*18)` along ribbon tangent
A PACKING: ACES display RGBA
FLOOR: single ACES (removed duplicate `aces` + `acesToneMap`)

## gen-prismatic-ion-cascade
KEEP: four sliders; mouse as origin; RGB phase split; video haze
IDEAS IN DIFF:
  1. `theta += 0.14 * sin(r*8 - ωt)` cyclotron
  2. recombination shell `exp(-|r - recombR|)`
A PACKING: ACES display RGBA
FLOOR: exact C load; continuous sparkle (no `floor(time)`)

## gen-crystal-lattice-growth
KEEP: Symmetry / Growth / Hue / Thickness; golden child; click fronts; HDR A
IDEAS IN DIFF:
  1. odd arms `qp = p - 2 n (p·n)` twin
  2. hopper `sdSeg` offset along segment normal
A PACKING: raw HDR in A; ACES on writeTexture

## gen-topological-acoustic-knots
KEEP: Density / Speed / Iridescence / Flow; ±1/2 orbits; mouse pin; director stripes
IDEAS IN DIFF:
  1. `live = smoothstep(pairDist)` annihilates opposite-charge pairs
  2. Schlieren `sin(2θ) * |∇θ|` dark brushes
A PACKING: ACES display RGBA
FLOOR: exact C load

## gen-quasicrystal-iridescence
KEEP: JSON slider roles; n-fold cosine sum; thin-film loop; held-mouse thickness
IDEAS IN DIFF:
  1. phason offset along k-perp in `quasicrystal()`
  2. Ammann stripes `fract(dot(p,k))`
A PACKING: ACES display RGBA (A now matches writeTexture)
FLOOR: ACES; plasmaBuffer; semantic alpha

Skipped from this family: belousov / protocell / hyperbolic-tree (idea-rich),
stardust-nebula / tessellation (already multi-technique), chronos-crystal-labyrinth
(C as fake audio), extraBuffer[0..] files.
