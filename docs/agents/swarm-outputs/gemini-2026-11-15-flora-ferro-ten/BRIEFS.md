# Idea Cards — gemini/flora-ferro-ten (2026-11-15)

Written **before** any WGSL edits. Ten catalog shaders (109–114 lines) spanning simulation, advanced-hybrid, and generative families (`alpha-reaction-diffusion-rgba`, `gen-fibonacci-spiral-garden`, `sim-ink-diffusion-rgba`, `gen-cymatic-bloom-fronds`, `gen-flowing-silk-ribbons`, `gen-audio-reactive-mycelium-pulse`, `gen-bioluminescent-neural-coral-matrix`, `liquid-magnetic-ferro-em`, `gen-neon-geode-crystallization`, `gen-stellar-cyber-lotus-forge`). Every card adds 2 native ideas inside the existing main path. Saved `params` stay byte-exact across all ten JSON definitions. No new spring is introduced anywhere (`liquid-magnetic-ferro-em` keeps the magnet spring it already owns in `extraBuffer[133..138]`). No shared ripple stamp or generic overlay.

Three files still paste the canonical 13-binding header (`alpha-reaction-diffusion-rgba`, `sim-ink-diffusion-rgba`, `liquid-magnetic-ferro-em`). Those are migrated first via `python3 scripts/migrate_to_prelude.py --files ...`; that header swap is plumbing and is not counted toward any Idea Card.

**Batch formula de-duplication (§12.4 / §12.7):** every §12.2 formula row used appears **at most once** across all ten files:
- Isotropic 9-point Laplacian (§12.2D) → `alpha-reaction-diffusion-rgba` only
- Shallow-water / capillary continuity flux (§12.2D) → `sim-ink-diffusion-rgba` only
- Beer–Lambert spectral transmission (§12.2F) → `gen-flowing-silk-ribbons` only
- Step-count AO (§12.2E) → `gen-bioluminescent-neural-coral-matrix` only
- SDF curvature (§12.2E) → `gen-bioluminescent-neural-coral-matrix` only
- Surface tension (§12.2D) → `liquid-magnetic-ferro-em` only
- Orbit trap (§12.2E) → `gen-neon-geode-crystallization` only
- Thin-film phase (§12.2F) → `gen-neon-geode-crystallization` only
- Fresnel–Schlick (§12.2F) → `gen-stellar-cyber-lotus-forge` only
- Soft inverse-square (§12.2F) → `gen-stellar-cyber-lotus-forge` only

---

## 1. alpha-reaction-diffusion-rgba

```
SHADER: alpha-reaction-diffusion-rgba
IDENTITY: four-species ecological Gray–Scott reaction-diffusion (`warm U/V` and `cool U/V`) persisted in raw A/C state over the source photo, with photo-luma nutrient chemotaxis, inter-species interface membrane, held inoculation, and click fronts.
KEEP VERBATIM: Feed Rate, Kill Rate, Cross Inhibition, Source Mix; raw A/C `(warm U, warm V, cool U, cool V)` packing; `seed` initialization; `reactAB`, `reactCD`, and cross-inhibited `ds` reaction rates; photo-luma nutrient chemotaxis (`Idea 1` from 2026-09-12); `|s.g - s.a|` interface membrane (`Idea 2` from 2026-09-12); hover/held inoculation; click fronts; ACES display RGBA on `writeTexture` only.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `lap = l + r + t + btm - 4.0 * s` is an axis-pinned 5-point stencil, biasing Turing mitosis spots and labyrinthine coral stripes toward horizontal/vertical grid axes; adding the four diagonal `stateAt` taps forms the rotationally isotropic 9-point Laplacian scaled to the exact same continuum diffusivity.
  tactic 2 & 3 (physics one step further / promote an intermediate): `r.g - l.g`, `btm.g - t.g`, `r.a - l.a`, and `btm.a - t.a` are already evaluated for `membrane` and flattened with `abs()`, discarding their signs; preserving the signed inhibitor slope `∇(s.g + s.a)` yields a 3D wet-agar colony meniscus normal (for grazing specular glints and subtle photo refraction), while `src.r - src.b` partitions warm vs. cool Gray–Scott substrates into matching chromatic habitats of the underlying photo.
ADD (2 native ideas):
  1. Continuum-matched isotropic 9-point Laplacian (§12.2D) — adds the four diagonal `stateAt` taps (`(10/3) * (0.20 * cardinal + 0.05 * diagonal - s)`) so Gray–Scott spots and labyrinthine stripes bifurcate smoothly without X/Y pixel-axis pinning while preserving exact `feed`/`kill` Turing wavelengths.
  2. Chromatic habitat partitioning & 3D agar-meniscus sheen — biases warm substrate `s.r` vs. cool substrate `s.b` by photo warmth `(src.r - src.b) * Source Mix` so the two ecosystems colonize matching chromatic zones, while the signed inhibitor gradient `∇(s.g + s.a)` forms a wet-gel colony rim normal for grazing specular highlights and subtle substrate refraction.
FORBID: ACES on `dataTextureA` (corrupts raw Gray–Scott chemistry), a spring cursor, changing channel assignments.
A PACKING: raw `(warm U, warm V, cool U, cool V)` in A/C (unchanged; ACES on `writeTexture` only).
```

---

## 2. gen-fibonacci-spiral-garden

```
SHADER: gen-fibonacci-spiral-garden
IDENTITY: ninety-six golden-angle phyllotaxis florets unfurling from a central meristem with 5-lobed petals, 8/13 parastichy glow ridges, ochre outer-floret aging, green involucre bracts, held radial push, and click growth rings.
KEEP VERBATIM: Spiral Scale, Growth Cycle, Petal Size, Bloom; `GOLDEN_ANGLE` 96-floret loop (`unfurl`, `radius`, `angle`, 5-lobe `petalDistance`, `petal`, `halo`); 8/13 `paraRidge`; `ageMass` ochre outer shift; 13-fold green `bract` ring; `clickBloom`; exact `dataTextureC` raw HDR trail; `acesToneMap` on `writeTexture`.
MECHANISM INTERROGATION:
  tactic 2 & 3 (physics/botany one step further / promote an intermediate): inside the 96-floret loop, `q = p - node` and `size * lobes` are already computed per floret, yet every floret renders as a flat 2D spot on a flat disk; promoting `q / max(size * lobes, 1e-4)` coupled with a convex receptacle dome `(1 - r²)` gives each floret a 3D cupped corolla normal, central tubular anther pollen ring during mid-head anthesis, and subtle imbricated shadow onto older outer florets.
  tactic 1 (deepen the botanical motif): a real composite capitulum (sunflower/aster) crowns the perimeter between its central disk florets and its outer green involucre bracts with a golden-number ring of **21 elongated ligulate ray petals**; currently there is an empty dark gap right inside `bract`.
ADD (2 native ideas):
  1. Convex capitulum dome, 3D cupped-corolla normals & anthesis anther rings — promotes per-floret local coordinates `q / size` and radial head curvature into 3D sunlit corolla cups with golden-ochre pollen anther rings on mid-age florets (`normalizedIndex ∈ [0.22, 0.68]`) that are actively in bloom.
  2. 21-fold Fibonacci ray-floret corolla crown — unfurls a ring of 21 ribbed, radially tapered ligulate ray petals nestled inside the 13 green involucre bracts (scaled by `Spiral Scale`, `Petal Size`, and `Growth Cycle`, swaying gently with `audio.y` and held pointer wind).
FORBID: a spring cursor, raymarching a different scene, changing A/C raw HDR trail packing.
A PACKING: raw HDR display RGBA history in A/C (unchanged; `acesToneMap` on `writeTexture`).
```

---

## 3. sim-ink-diffusion-rgba

```
SHADER: sim-ink-diffusion-rgba
IDENTITY: stateful wet-paper ink wash simulating pigment RGB and water saturation A over the photo-textured paper, with Bousseau drying-edge darkening, fibre/photo-valley granulation, held rotating-hue ink brush, and click ink rings.
KEEP VERBATIM: Wetness, Pigment Diffusion, Color Mixing, Evaporation Rate; raw `(pigment.rgb, water)` state in A/C; 4-neighbour diffusion + `chromaMean` mixing; held ink brush + click rings; exponential evaporation; Bousseau edge darkening (`edgeDark`); two-scale fibre + photo-tone granulation (`granulate`); subtractive `paper * absorb`; ACES on `writeTexture` only.
MECHANISM INTERROGATION:
  tactic 1 & 2 (deepen the solver / watercolour physics): real watercolour coffee-rings and "cauliflower" backruns happen because water-height gradients (`∇water`) drive capillary flow carrying suspended pigment outward toward fast-drying margins, and pigments separate chromatographically because fine phthalo/cyan grains ride capillary flow further than heavy mineral grains; `n.a, s.a, e.a, w.a` are already loaded every pixel, so `∇water` costs zero extra texture reads!
  tactic 2 & 3 (optical physics / promote `∇water` and `nextWater`): wet cellulose fibres lose air-gap scattering and turn more translucent to the underlying `source.rgb` photo where `nextWater` is high, while beaded wet puddle rims (`∇water`) catch a raking studio specular water-meniscus highlight before drying matte; also replace the quantized `floor(u.config.x * 12.0)` frame-hash jitter in stored state with spatially coherent micro-fibre capillary wicking.
ADD (2 native ideas):
  1. Capillary water-flux advection & chromatographic backruns (§12.2D Shallow-water / capillary continuity) — uses the already-loaded neighbour water gradient `(e.a - w.a, n.a - s.a)` to advect mobile pigment toward drying margins with per-channel grain mobility `(1.18, 0.96, 0.76)`, so fresh wet drops push damp washes into ruffled cauliflower backruns with subtle chromatic haloing.
  2. Wet-puddle meniscus specular & wet-cellulose translucency — constructs a 3D liquid-film normal from `∇water` and paper fibre grain to cast grazing specular glints on wet ink beads (`nextWater`), while wet paper becomes more optically translucent to `source.rgb` until evaporation restores matte cotton opacity.
FORBID: ACES on `dataTextureA` (corrupts raw pigment/water sim), a spring cursor, changing A/C channel meanings.
A PACKING: raw `(pigment.r, pigment.g, pigment.b, water)` in A/C (unchanged; ACES on `writeTexture` only).
```

---

## 4. gen-cymatic-bloom-fronds

```
SHADER: gen-cymatic-bloom-fronds
IDENTITY: Barnsley IFS fern fronds blooming across a resonant cymatic standing-wave plate, modulated by bass growth, mids cymatic frequency, mouse/fBM domain warp, depth softening, and trailing persistence.
KEEP VERBATIM: Growth Rate, Cymatic Frequency, Frond Scale, Trail Decay; `fbm` domain warp + mouse offset (`q`); 4-branch Barnsley fern affine IFS coefficients (`0.01 / 0.86 / 0.93 / 1.00`); emerald-to-orchid `leafCol`; cymatic standing-wave rim; depth attenuation; `hue_preserve_clamp` + `aces` + `ign` dither.
MECHANISM INTERROGATION:
  tactic 1 & bug audit (deepen cymatic + IFS coupling): three existing bugs currently suppress the shader's own design: (a) `q` is warped by `mouse` and `fbm` on lines 66–70 and then ignored on line 88 (`length(uv - fp)` instead of `q`), leaving mouse dead; (b) `growth` multiplies `(0.5 + p1)` by `bassEnv`, making `Growth Rate` dead when audio is silent; (c) `hash21(vec2(f32(i), time * 0.01))` scrambles the IFS branch sequence every frame (frame-hash strobing). Fixing those lets us fold `q` into a coherent, wind-swaying 3-frond cymatic phyllotaxis rosette over a true 2D Chladni nodal plate `cos(mθ)sin(kr) + cos(nθ)sin(lr)`!
  tactic 3 (promote an intermediate): the 4 IFS branches inside the loop already correspond to distinct fern organs (rachis stem, apex progression, left pinna, right pinna); tracking `branchKind` shades the central rachis as a structural cyan vein and dusts lateral pinna tips with golden-bioluminescent spore **sori**, while Chladni nodal lines (`|mode| ≈ 0`) gather luminous cymatic spore sand that scatters on click ripples.
ADD (2 native ideas):
  1. True 2D Chladni `(m, n)` nodal plate & coherent wind-swaying cymatic frond rosette — replaces the frame-strobing IFS seed and unwired `q` with a stable, gently swaying 3-frond Barnsley rosette coupled to `q`, `Growth Rate` (live even at zero audio), and a radial-angular Chladni standing-wave mode driven by `Cymatic Frequency` (`p2`) + `mids`, with nodal sand gathering along standing-wave zero-crossings.
  2. Botanical IFS organ differentiation (rachis veins & pinna sori) — promotes the active Barnsley affine branch index inside the existing loop to distinguish luminous cyan rachis stems, emerald-orchid leaflet blades, and warm golden spore sori under lateral pinnae, burst outward by click ripples.
FORBID: filtering `textureSampleLevel` on `dataTextureC` (replace with exact `textureLoad`), frame-hash strobing, a spring cursor.
A PACKING: linear HDR frond/cymatic trail RGB + semantic frond density alpha in A/C (read back via exact `textureLoad(dataTextureC, pixel, 0)`; `aces` on `writeTexture`).
```

---

## 5. gen-flowing-silk-ribbons

```
SHADER: gen-flowing-silk-ribbons
IDENTITY: up to twelve layered anisotropic silk ribbons flowing across lanes with half-twist width pinch, warp threads, selvage highlights, travelling satin glints, held pointer combing, and click wave rings.
KEEP VERBATIM: Ribbon Count, Flow Speed, Silk Width, Iridescence; 12-ribbon loop (`lane`, `primary`, `secondary`, held `comb`, `slope`, `twist` pinch, `ribbon`, `sheen`, `warp`, `glint`, `selvage`, cooler `backAcc`); `clickWave`; exact `dataTextureC` raw HDR trail; `acesToneMap` on `writeTexture`.
MECHANISM INTERROGATION:
  tactic 2 & 7 (textile physics / transverse orientation): real iridescent "shot silk" (*changeant* organza) achieves its colour-shift from **perpendicular warp and weft threads dyed in contrasting hues** — currently `warp` threads run only along `p.x`, while the signed cross-ribbon coordinate `(p.y - center) / width` is flattened to `d` without transverse weft micro-fibres or angle-dependent warp-vs-weft dominance!
  tactic 3 & 8 (promote ribbon Z-height / Beer–Lambert sheer layering): inside the loop, `twist` (`cos(...)`) implies an oscillating 3D ribbon Z-billow `sin(...)` on top of ribbon index `fi`, yet all ribbons sum flatly without Z-ordered aerial **drape shadows** from upper ribbons onto lower ones or **Beer–Lambert subtractive dye filtering (§12.2F)** where sheer translucent ribbons cross!
ADD (2 native ideas):
  1. Shot-silk transverse weft weave & grazing warp/weft Dichroism — pairs the existing longitudinal `warp` threads with fine transverse `weft` micro-threads across `(p.y - center) / width`, shifting colour smoothly between warm warp dye at face-on angles and cool complementary weft dye at grazing `twist`/`slope` angles scaled by `Iridescence`.
  2. Z-billow aerial drape shadows & Beer–Lambert sheer cross-dyeing (§12.2F) — tracks ribbon 3D elevation across the existing 12-ribbon loop so upper billowing ribbons cast soft drape occlusion onto ribbons passing underneath, while overlapping sheer organza zones attenuate and cross-tint underlying silk via Beer–Lambert dye transmission.
FORBID: a spring cursor, replacing `palette()` or ribbon waves, ACES inside `dataTextureA`.
A PACKING: raw HDR display RGBA history in A/C (unchanged; `acesToneMap` on `writeTexture`).
```

---

## 6. gen-audio-reactive-mycelium-pulse

```
SHADER: gen-audio-reactive-mycelium-pulse
IDENTITY: bioluminescent Voronoi mycelial hyphal network pulsing across a dark substrate with chlorophyll-to-violet hyphae, glowing nodes, treble spores, mouse/fBM domain warp, depth fade, and temporal persistence.
KEEP VERBATIM: Network Scale, Hyphae Glow, Node Brightness, Trail Persistence; `voronoiEdges` network; `fbm` + `mouse` warp; chlorophyll-to-violet `hyphae` hue mix; depth attenuation; `hue_preserve_clamp` + `aces` + `ign` dither.
MECHANISM INTERROGATION:
  tactic 1 & 3 (deepen Voronoi kernel / promote `md3`): inside `voronoiEdges`'s existing 3×3 cell loop, tracking the 3rd-nearest squared distance `md3` alongside `md` and `md2` costs zero extra iterations or hashes and yields `sqrt(md3) - sqrt(md)` — which isolates **3-way Voronoi vertices (hyphal anastomosis knots / fruiting primordia)**! Meanwhile Slider 3 (`Node Brightness`, `p3`) was wired only to the trail mix and didn't brighten nodes at all, and adding a secondary fine foraging sub-hyphae octave bridges empty cell interiors with delicate exploratory filaments.
  tactic 2 & bug audit (biological transport / replace frame-strobe static): real bioluminescent mycelium conducts travelling cytoplasmic / action-potential waves along cords outward from junctions and click inoculations, whereas line 96 used `hash21(pixel + fract(time * 18.0))` (frame-hash TV static) instead of coherent drifting bioluminescent **spores** lifting off fruiting knots on `treble`.
ADD (2 native ideas):
  1. Anastomosis triple-junction primordia (`md3 - md`) & coherent drifting spores — extends `voronoiEdges` to return 3-way vertex proximity so luminous fruiting knots bloom at hyphal intersections (wired directly to `Node Brightness` `p3` + `bass`), releasing smooth buoyant bioluminescent spore motes on `treble` in place of pixel-static hash strobing.
  2. Secondary foraging sub-hyphae & cytoplasmic translocation waves — layers fine exploratory sub-hyphae inside primary Voronoi cells (tapered toward main rhizomorph cords) and sends travelling bioluminescent nutrient pulses racing along hyphal filaments from mouse/click inoculation sites.
FORBID: filtering `textureSampleLevel` on `dataTextureC` (replace with exact `textureLoad`), frame-hash pixel strobing, a spring cursor.
A PACKING: linear HDR mycelium trail RGB + semantic network alpha in A/C (read back via exact `textureLoad(dataTextureC, pixel, 0)`; `aces` on `writeTexture`).
```

---

## 7. gen-bioluminescent-neural-coral-matrix

```
SHADER: gen-bioluminescent-neural-coral-matrix
IDENTITY: raymarched 3D gyroidal neural-coral matrix (`dot(sin(p * scale), cos(p.zxy * scale))`) with forward camera flight, gentle roll, subsurface scattering, abyssal water fog, cyan bioluminescent glow, and held-mouse gravity well.
KEEP VERBATIM: Structure Scale, Distortion Intensity, Travel Speed, Bioluminescence (exact non-unit slider ranges `[1..5]`, `[0..3]`, `[0..5]`, `[0..3]`); held-mouse 3D gravity well (guarded & branchless); bass-pulsing gyroid SDF; 100-step raymarcher (`t <= 20.0`) with volumetric `glow`; directional `diff` + `sss` + abyssal `exp(-0.05 * t)` fog.
MECHANISM INTERROGATION:
  tactic 1 & 2 (deepen coral/neural anatomy): `map(p)` is currently a smooth single-octave gyroid shaded flat slate-blue with uniform cyan glow; real brain/neural coral has fine **calcareous corallite polyp pores/ridges** etched into its gyroid walls and conducts **travelling synaptic action-potential waves** along minimal-surface channels (modulated by `mids`, `Bioluminescence`, and click pulses).
  tactic 3 (promote `getNormal` taps → curvature + crevice AO): the 6 axial SDF taps `map(p ± e)` evaluated for `getNormal(p)` also yield **local SDF mean curvature (§12.2E)** (`(Σ map(p±e) - 6·map(p))`), isolating convex coral meandroid ridges for warm anthozoan chromoprotein fluorescence (coral-magenta/cyan rims vs. deep indigo polyps), paired with **5-tap SDF ambient occlusion (§12.2E)** inside deep gyroid caverns and catalog ACES + refractory C afterglow!
ADD (2 native ideas):
  1. Corallite polyp micro-relief & synaptic action-potential waves — sculpts fine high-frequency corallite ridges onto the gyroid walls (scaled by `Structure Scale` and `Distortion Intensity`) and propagates electric cyan-to-magenta neural firing waves along the coral matrix channels (boosted by `Bioluminescence`, `mids`, and click impulses).
  2. 5-tap gyroid cavern AO (§12.2E) & SDF curvature chromoprotein rims (§12.2E) — darkens deep gyroidal chambers with 5-tap SDF ambient occlusion while curvature derived from the 6-tap surface normal lights convex polyp ridges with fluorescent coral-pink/cyan chromoprotein rims, finished with ACES tone mapping, semantic alpha, and exact-C bioluminescent afterglow (replacing unused raw normal dump in `A`).
FORBID: changing JSON slider ranges, unguarded `normalize(p - mouse_pos)`, hardcoded `1.0` alpha, a spring cursor.
A PACKING: ACES display RGBA in A/C (replaces unread raw normal write; read back via exact `textureLoad(dataTextureC, pixel, 0)` for subtle bioluminescent water afterglow).
```

---

## 8. liquid-magnetic-ferro-em

```
SHADER: liquid-magnetic-ferro-em
IDENTITY: persistent magnetohydrodynamic ferrofluid solver storing `(height, velocity, EM potential, surface charge)` in raw A/C over the refracted source image, driven by an `extraBuffer[133..138]` cursor magnet spring, orbiting dipoles, click charge rings, Rosensweig hex spikes, and 3-band iridescence.
KEEP VERBATIM: Field Strength, Spike Sharpness, EM Coupling, Dipole Count; raw `(height, velocity, potential, charge)` A/C packing; existing `extraBuffer[133..138]` magnet spring; held polarity flip; 2..6 orbiting dipoles; alternating-polarity click charge rings; hexagonal Rosensweig `spikeTarget`; `fresnel`, `emTint`, `specular`, `acesToneMap`, and height-coupled `writeDepthTexture`.
MECHANISM INTERROGATION:
  tactic 1 & 2 (deepen MHD solver): `latticeP` currently evaluates an isotropic world-axis hex grid regardless of magnetic field orientation, and `lapH` is a linear 5-point stencil; in real ferrofluids, tangential magnetic flux `B` chains Rosensweig peaks into **anisotropic ridges aligned along dipole field lines** bridging North and South poles, while nonlinear **capillary surface tension (§12.2D)** `κ = ∇·(∇h / sqrt(1 + |∇h|²))` (using all 8 neighbours) rounds saddle valleys and pinches spike tips into taut liquid-metal cones.
  tactic 3 & 8 (promote `potential` gradient & `charge`): `(r.b - l.b, t.b - d.b)` (`∇potential`) and `charge` are already computed every pixel; where high electric field `|∇potential|` meets `charge` across equipotential contours, real MHD fluids exhibit **Lorentz eddy-current induction filaments**, while steep oily magnetite menisci absorb transmitted `source.rgb` in thick peaks and catch a secondary grazing rim highlight.
ADD (2 native ideas):
  1. Flux-tube-aligned Rosensweig chaining & nonlinear capillary surface tension (§12.2D) — warps the Rosensweig wave-vector anisotropically along local magnetic flux direction `normalize(field)` so ferrofluid ridges bridge visibly between dipole poles, while 8-neighbour nonlinear mean-curvature surface tension `κ` tautens liquid-metal cones and rounds inter-spike valleys.
  2. Lorentz equipotential induction filaments & magnetite carrier-fluid optics — illuminates fine electromagnetic induction arcs along equipotential lines gated by `|∇potential|`, `charge`, and `EM Coupling`, while thick ferrofluid peaks deepen magnetite absorption and add a grazing anisotropic metallic counter-rim.
FORBID: ACES on `dataTextureA` (corrupts raw 4-field MHD state), modifying or duplicating `extraBuffer[133..138]` spring layout.
A PACKING: raw `(height, velocity, EM potential, surface charge)` in A/C (unchanged; `acesToneMap` on `writeTexture` only).
```

---

## 9. gen-neon-geode-crystallization

```
SHADER: gen-neon-geode-crystallization
IDENTITY: raymarched procedural bismuth-crystal geode cavern (`twist`, octahedral `abs`+sort `fold`, `4.0`-repeated cubic crystals with plasma displacement) erupting with luminescent neon plasma.
KEEP VERBATIM: Plasma Intensity, Crystal Fold, Bloom Radius, Geometry Twist (exact slider ranges `[0..1]`, `[0..5]`, `[0.1..2.0]`, `[-3.14..3.14]`); `p.xz` twist by `p.y`; octahedral `abs(p) - fold` + 3-axis sort; `4.0` domain repetition + box crystal core; 100-step raymarcher + step-count neon bloom.
MECHANISM INTERROGATION:
  tactic 1 & 5 (artifact of real bismuth crystals / §12.2E Orbit trap): real bismuth forms **stair-stepped rectangular hopper crystals** (outer rims grow faster than hollow terraced centers), and inside `map()`'s octahedral `abs`+sort block, proximity to the sorting mirror planes (`min(abs(p.x - p.y), abs(p.y - p.z))`) acts as a natural **cleavage-seam orbit trap (§12.2E)** where neon plasma erupts! Also fixes three bugs: `mids` was unread despite JSON `"audio": "mid"` on `crystal_fold`, `Bloom Radius` multiplied raw `treble` (dead when silent), and held-mouse subtracted unbounded `ro.z` (flipping camera backward after 10 s).
  tactic 2 (optical physics of bismuth — §12.2F Thin-film phase): bismuth's iconic rainbow sheen is textbook **bismuth-oxide ($\text{Bi}_2\text{O}_3$, $n \approx 2.5$) thin-film interference** whose nanometer thickness steps across crystal hopper terraces, shifting facet reflections continuously through gold, magenta, cyan, and violet with viewing angle `dot(-rd, out_n)`!
ADD (2 native ideas):
  1. Stepped bismuth hopper terraces & octahedral cleavage-seam orbit trap (§12.2E) — carves concentric stair-stepped hopper recesses into the repeated crystal faces and captures octahedral fold-plane proximity inside `map()` so glowing neon plasma veins erupt along crystal cleavage seams (driven by `Plasma Intensity`, `bass`, `mids` on `Crystal Fold`, and click plasma surges, with volumetric cavern glow on miss rays too).
  2. Bismuth-oxide $\text{Bi}_2\text{O}_3$ thin-film interference (§12.2F) — evaluates physical thin-film reflectance (`n = 2.5`, terrace-stepped oxide thickness in nm, viewing cosine `max(dot(-rd, out_n), 0.05)`) across crystal facets + specular highlights, finished with ACES tone mapping, normalized `[0..1]` depth, semantic alpha, and exact-C plasma shimmer persistence.
FORBID: changing JSON slider ranges (`[-3.14..3.14]` etc.), camera-breaking `mouse - ro` bug, hardcoded `1.0` alpha, a spring cursor.
A PACKING: ACES display RGBA in A/C (replaces unread raw normal write; read back via exact `textureLoad(dataTextureC, pixel, 0)` for subtle geode plasma shimmer).
```

---

## 10. gen-stellar-cyber-lotus-forge

```
SHADER: gen-stellar-cyber-lotus-forge
IDENTITY: raymarched 3D cybernetic lotus flower with central forge sphere and curved `smin`-blended radial petals rotating in cosmic bloom, with golden vein glow and held-mouse gravity well.
KEEP VERBATIM: Bloom Intensity, Rotation Speed, Petal Complexity, Vein Glow (exact slider ids `p1..p4` and ranges `[0..1]`, `[0..5]`, `[1..6]`, `[0..2]`); camera `ro = (0, 2, -5)` framing; held-mouse 3D gravity pull; rotation `time * 0.2`; `core` sphere + `smin`-fused curved petals; cosmic blue ambient bloom + golden `veinGlow`.
MECHANISM INTERROGATION:
  tactic 4 & bug audit (wire dead `Petal Complexity` + deepen lotus SDF): `let num_petals = u.zoom_params.z;` on line 44 was **100% dead** (never referenced!), and `Vein Glow` (`u.zoom_params.w`) multiplied uniform raymarch `glow` with no actual veins on the petals! Replacing the fixed 6-step loop with an exact O(1) polar sector fold driven by `num_petals` (at default `3.0` → 6 outer petals, matching HEAD's silhouette, while `1..6` scales petal count AND unfurls an interleaved inner golden-offset corolla whorl + stamen ring) frees raymarch budget for real 3D normals and carves glowing **branching cyber-circuit veins** along each petal blade!
  tactic 2 & 8 (optical physics — forged metal normals, §12.2F Fresnel–Schlick & soft inverse-square core light): HEAD never computed a surface normal on hit (`t < 15.0` was flat unlit colour) and omitted both `writeDepthTexture` and `dataTextureA`! Computing 3D normals lets the central stellar `core` illuminate inner petal faces via **soft inverse-square point lighting (§12.2F)** while outer titanium-indigo petals catch **Fresnel–Schlick cyber-magenta grazing rims (§12.2F)** and click forge-strike flares.
ADD (2 native ideas):
  1. Live multi-whorl `Petal Complexity` corolla & etched cyber-vein conduits — wires `Petal Complexity` (`u.zoom_params.z`) to control outer + inner interleaved lotus petal whorls (`2 * round(num_petals)` petals per whorl, matching 6 at default `3.0`) and etches branching circuit-vein channels along local petal coordinates `pp` carrying golden stellar pulses scaled by `Vein Glow` (`u.zoom_params.w`).
  2. Stellar core inverse-square forge lighting (§12.2F) & Fresnel–Schlick metallic petal rims (§12.2F) — shades 3D lotus normals with warm inverse-square radiance emitted from the central forge `core` (plus click forge-pulse flares) and grazing Fresnel–Schlick cyber-violet/cyan sheen, adding ACES tone mapping, semantic alpha, normalized `writeDepthTexture`, and exact-C stellar ember trail in `dataTextureA`.
FORBID: changing JSON slider ids/ranges, shifting camera framing away from the lotus, omitting `writeDepthTexture` or `dataTextureA`, a spring cursor.
A PACKING: ACES display RGBA in A/C (read back via exact `textureLoad(dataTextureC, pixel, 0)` for subtle stellar forge ember trail).
```
