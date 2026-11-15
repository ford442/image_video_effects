# Notes — gemini/flora-ferro-ten (2026-11-15)

Idea cards and §12.1 mechanism interrogations were written first in `BRIEFS.md`. Saved `params` (ids, names, defaults, min/max/step, mappings) are byte-exact across all ten JSON definitions. Three legacy pasted binding headers were migrated first via `python3 scripts/migrate_to_prelude.py --files ...` (`alpha-reaction-diffusion-rgba`, `sim-ink-diffusion-rgba`, `liquid-magnetic-ferro-em`); that header swap is infrastructure and is not counted as an idea.

No new spring was added anywhere. `liquid-magnetic-ferro-em` retains its existing magnet spring in `extraBuffer[133..138]`.

**§12.2 formulae used (each appears at most once across the ten files):**
- `alpha-reaction-diffusion-rgba`: Isotropic 9-point Laplacian (§12.2D)
- `sim-ink-diffusion-rgba`: Shallow-water / capillary continuity flux (§12.2D)
- `gen-flowing-silk-ribbons`: Beer–Lambert spectral transmission (§12.2F)
- `gen-bioluminescent-neural-coral-matrix`: Step-count AO (§12.2E); SDF curvature (§12.2E)
- `liquid-magnetic-ferro-em`: Surface tension (§12.2D)
- `gen-neon-geode-crystallization`: Orbit trap (§12.2E); Thin-film phase (§12.2F)
- `gen-stellar-cyber-lotus-forge`: Soft inverse-square (§12.2F); Fresnel–Schlick (§12.2F)

---

## alpha-reaction-diffusion-rgba

Kept: Feed Rate, Kill Rate, Cross Inhibition, Source Mix; raw `(warm U, warm V, cool U, cool V)` state in A/C; `seed` initialization; `reactAB`, `reactCD`, and cross-inhibited `ds` reaction rates; photo-luma nutrient chemotaxis (`Idea 1`); `|s.g - s.a|` interface membrane (`Idea 2`); hover/held inoculation; click fronts; ACES on `writeTexture` only.
In the diff: continuum-matched isotropic 9-point Laplacian (`// ── Idea 3`, §12.2D) adds the four diagonal `stateAt` taps (`(10/3) * (0.20 * cardinal + 0.05 * diagonal - s)`) so Turing mitosis spots and coral stripes bifurcate without horizontal/vertical grid pinning. Chromatic habitat partitioning & 3D wet-agar meniscus sheen (`// ── Idea 4`) enrich warm `s.r` vs. cool `s.b` substrates using photo warmth `src.r - src.b` and promote the signed inhibitor slope `∇(s.g + s.a)` into a 3D agar-gel rim normal for grazing specular highlights and subtle substrate refraction.
A packing: raw `(warm U, warm V, cool U, cool V)` in A/C (unchanged; ACES on `writeTexture` only).

## gen-fibonacci-spiral-garden

Kept: Spiral Scale, Growth Cycle, Petal Size, Bloom; `GOLDEN_ANGLE` 96-floret loop (`unfurl`, `radius`, `angle`, 5-lobed `petalDistance`, `petal`, `halo`); 8/13 `paraRidge`; `ageMass` ochre outer aging; 13-fold green `bract` ring; held radial push; `clickBloom`; exact `dataTextureC` raw HDR trail; `acesToneMap` on `writeTexture`.
In the diff: 3D cupped-corolla dome normals & anthesis anther rings (`// ── Idea 1`) promote per-floret `q / lobeRadius` and convex capitulum curvature into sunlit 3D corolla cups and open golden pollen anther rings on mid-head florets in active bloom (`normalizedIndex ∈ [0.16, 0.78]`). 21-fold Fibonacci ligulate ray-floret corolla crown (`// ── Idea 2`) unfurls 21 ribbed, radially tapered golden ray petals nestled behind the disk head and inside the 13 green involucre bracts.
A packing: raw HDR display RGBA history in A/C (unchanged; `acesToneMap` on `writeTexture`).

## sim-ink-diffusion-rgba

Kept: Wetness, Pigment Diffusion, Color Mixing, Evaporation Rate; raw `(pigment.rgb, water)` state in A/C; 4-neighbour diffusion + `chromaMean` mixing; held rotating-hue ink brush + click ink rings; exponential evaporation; Bousseau drying-edge darkening (`edgeDark`); two-scale fibre + photo-tone granulation (`granulate`); subtractive `paper * absorb`; ACES on `writeTexture` only.
In the diff: capillary water-flux advection & chromatographic backruns (`// ── Idea 3`, §12.2D) reuse the already-loaded neighbour water gradient `(e.a - w.a, n.a - s.a)` for upwind pigment transport with per-channel grain mobility `(1.18, 0.96, 0.76)`, producing cauliflower backruns and chromatic haloing when wet drops hit damp washes (also replacing frame-quantized `floor(time * 12)` state jitter with coherent fibre capillary wicking). Wet-puddle meniscus specular & wet-cellulose translucency (`// ── Idea 4`) increase paper translucency to `source.rgb` where `nextWater` fills cotton fibre air gaps and cast raking specular glints off `∇water` puddle rims.
A packing: raw `(pigment.r, pigment.g, pigment.b, water)` in A/C (unchanged; ACES on `writeTexture` only).

## gen-cymatic-bloom-fronds

Kept: Growth Rate, Cymatic Frequency, Frond Scale, Trail Decay; `fbm` domain warp + mouse offset; 4-branch Barnsley fern affine IFS probabilities (`0.01 / 0.86 / 0.93 / 1.00`); emerald-to-orchid `bladeCol`; cymatic standing-wave rim; depth attenuation; `hue_preserve_clamp` + `aces` + `ign` dither.
In the diff: 2D Chladni `(m, n)` nodal plate & coherent 3-frond Barnsley rosette (`// ── Idea 1`) wire the previously unused warped coordinate `q`, keep `Growth Rate` live at zero audio, replace frame-strobing IFS random seeds with a smooth wind-swaying 3-frond rosette, add a radial-angular Chladni standing-wave plate with luminous nodal spore sand, and switch `dataTextureC` from filtering `textureSampleLevel` to exact `textureLoad`. Botanical IFS organ differentiation (`// ── Idea 2`) distinguishes cyan structural rachis stems from emerald-orchid leaflet blades and golden-bioluminescent pinna spore sori burst by click waves.
A packing: linear HDR frond/cymatic trail RGB + semantic alpha in A/C (read back via exact `textureLoad(dataTextureC, pixel, 0)`; `aces` on `writeTexture`).

## gen-flowing-silk-ribbons

Kept: Ribbon Count, Flow Speed, Silk Width, Iridescence; 12-ribbon loop (`lane`, `primary`, `secondary`, held `comb`, `slope`, `twist` pinch, `ribbon`, `sheen`, `warp`, `glint`, `selvage`, cooler `backAcc`); `clickWave`; exact `dataTextureC` raw HDR trail; `acesToneMap` on `writeTexture`.
In the diff: shot-silk transverse weft weave & grazing warp/weft dichroism (`// ── Idea 3`) pair longitudinal `warp` threads with perpendicular `weft` micro-threads across `signedD / width`, shifting fabric hue between warm warp dye face-on and complementary weft dye at grazing `twist`/`slope` angles. Z-billow aerial drape shadows & Beer–Lambert sheer cross-dyeing (`// ── Idea 4`, §12.2F) track 3D ribbon elevation across lanes so upper billowing ribbons cast soft drape shadows onto lower strands while overlapping sheer organza zones cross-filter dye transmission via Beer–Lambert extinction.
A packing: raw HDR display RGBA history in A/C (unchanged; `acesToneMap` on `writeTexture`).

## gen-audio-reactive-mycelium-pulse

Kept: Network Scale, Hyphae Glow, Node Brightness, Trail Persistence; Voronoi hyphal network; `fbm` + `mouse` warp; chlorophyll-to-violet `hyphae` hue mix; depth attenuation; `hue_preserve_clamp` + `aces` + `ign` dither.
In the diff: anastomosis triple-junction primordia (`md3 - md`) & buoyant drifting spores (`// ── Idea 1`) extend the 3×3 Voronoi scan to track 3rd-nearest cell distance `md3`, blooming luminous fruiting knots at 3-way hyphal vertices wired directly to `Node Brightness` (`p3`), and replace pixel-static `hash21(pixel + fract(time * 18))` with smooth drifting spore motes + exact `textureLoad(dataTextureC, ...)`. Secondary foraging sub-hyphae & cytoplasmic translocation waves (`// ── Idea 2`) branch fine exploratory filaments from primary cords into cell interiors and send bioluminescent nutrient pulses racing outward along hyphae.
A packing: linear HDR mycelium trail RGB + semantic network alpha in A/C (read back via exact `textureLoad(dataTextureC, pixel, 0)`; `aces` on `writeTexture`).

## gen-bioluminescent-neural-coral-matrix

Kept: Structure Scale, Distortion Intensity, Travel Speed, Bioluminescence (all 4 non-unit slider ranges byte-exact); held-mouse 3D gravity well (guarded and camera-relative); bass-pulsing gyroid SDF; 100-step raymarcher (`t <= 20.0`) with volumetric `glow`; directional `diff` + `sss` + abyssal `exp(-0.06 * t)` fog.
In the diff: calcareous corallite polyp micro-relief & synaptic action-potential waves (`// ── Idea 1`) sculpt fine secondary meandroid polyp pores onto the gyroid walls and propagate cyan-to-magenta neural firing waves along minimal-surface channels (modulated by `mids`, `Bioluminescence`, and click impulses). 5-tap gyroid cavern AO & SDF curvature chromoprotein rims (`// ── Idea 2`, §12.2E Step-count AO + §12.2E SDF curvature) darken deep chambers while 6-tap curvature lights convex coral ridges with fluorescent cyan/coral-pink chromoprotein rims, finished with `acesToneMap`, semantic alpha, scalar `[0..1]` depth, and exact-C bioluminescent afterglow.
A packing: ACES display RGBA in A/C (replaces unread raw normal write; read back via exact `textureLoad(dataTextureC, pixel, 0)` for refractory coral afterglow).

## liquid-magnetic-ferro-em

Kept: Field Strength, Spike Sharpness, EM Coupling, Dipole Count; raw `(height, velocity, EM potential, surface charge)` A/C packing; existing `extraBuffer[133..138]` magnet spring; held polarity flip; 2..6 orbiting dipoles; alternating-polarity click charge rings; hexagonal Rosensweig `spikeTarget`; `fresnel`, `emTint`, `specular`, `acesToneMap`, and height-coupled `writeDepthTexture`.
In the diff: nonlinear capillary surface tension & flux-tube-aligned Rosensweig chaining (`// ── Idea 1`, §12.2D Surface tension) upgrade `lapH` to the 9-point isotropic stencil, add 8-neighbour nonlinear mean-curvature capillary restoration `κ = ∇·(∇h / sqrt(1 + |∇h|²))`, and warp the Rosensweig wave-vector along local magnetic flux `normalize(field)` so ferrofluid ridges bridge between dipole poles. Lorentz equipotential induction filaments & magnetite carrier-fluid optics (`// ── Idea 2`) illuminate eddy-current arcs along equipotential contours gated by `|∇potential|`, `charge`, and `EM Coupling`, while thick ferrofluid peaks deepen magnetite absorption and catch a counter-rim reflection.
A packing: raw `(height, velocity, EM potential, surface charge)` in A/C (unchanged; `acesToneMap` on `writeTexture` only).

## gen-neon-geode-crystallization

Kept: Plasma Intensity, Crystal Fold, Bloom Radius, Geometry Twist (exact slider ranges including `[-3.14..3.14]` byte-exact); `p.xz` twist by `p.y`; octahedral `abs(p) - fold` + 3-axis sort; `4.0` domain repetition + cubic crystal core; 100-step raymarcher + step-count neon bloom.
In the diff: stepped bismuth hopper terraces & octahedral cleavage-seam orbit trap (`// ── Idea 1`, §12.2E Orbit trap) carve concentric stair-stepped hopper recesses into crystal faces, wire `mids` into `Crystal Fold` (matching JSON `"audio": "mid"`), keep `Bloom Radius` live when audio is silent, fix the held-mouse camera-flip bug, and erupt neon plasma veins along octahedral sorting mirror seams. Bismuth-oxide $\text{Bi}_2\text{O}_3$ thin-film interference (`// ── Idea 2`, §12.2F Thin-film phase) shades crystal facets with physical $n = 2.5$ oxide-thickness interference colours, adding `acesToneMap`, normalized `[0..1]` depth, semantic alpha, and exact-C plasma shimmer.
A packing: ACES display RGBA in A/C (replaces unread raw normal write; read back via exact `textureLoad(dataTextureC, pixel, 0)` for geode plasma shimmer).

## gen-stellar-cyber-lotus-forge

Kept: Bloom Intensity, Rotation Speed, Petal Complexity, Vein Glow (exact slider ids `p1..p4` and ranges byte-exact); camera `ro = (0, 2, -5)` framing; held-mouse 3D gravity pull; rotation `time * 0.2`; central `core` sphere + curved `smin`-fused radial petals; cosmic blue ambient bloom + golden `veinGlow`.
In the diff: live multi-whorl `Petal Complexity` corolla & etched cyber-vein conduits (`// ── Idea 1`) wire the previously dead `Petal Complexity` (`u.zoom_params.z`) via polar sector folding (`2 * round(complexity)` petals per whorl, matching 6 outer petals at default `3.0`) to drive outer + uplifted interleaved inner petal whorls + forge stamen crown, etching branching circuit-vein conduits pulsing with `Vein Glow` (`u.zoom_params.w`). Stellar core inverse-square forge lighting & Fresnel–Schlick metallic petal rims (`// ── Idea 2`, §12.2F Soft inverse-square + §12.2F Fresnel–Schlick) compute 3D lotus normals lit from the incandescent central `core` and cyber-magenta/cyan grazing rims, adding `acesToneMap`, semantic alpha, normalized `writeDepthTexture`, and exact-C stellar ember trail in `dataTextureA`.
A packing: ACES display RGBA in A/C (read back via exact `textureLoad(dataTextureC, pixel, 0)` for stellar forge ember trail).
