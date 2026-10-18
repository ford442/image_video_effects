# Gemini Argon4 (`argon4/batch-04`) — Idea Cards

Date: 2026-10-18
Agent: Gemini (Argon4)
Batch: `argon4/batch-04` (10 shaders)

---

## 1. `gen-prismatic-singularity-engine`

```
SHADER: gen-prismatic-singularity-engine
IDENTITY (one sentence): A spinning black-hole singularity core surrounded by a 3-octave compressed gyroid manifold that raymarches R, G, and B along chromatically offset spacetime trajectories.
KEEP VERBATIM: 3 saved params (`singularity_mass` -> `zoom_params.x`, `twist_factor` -> `zoom_params.y`, `spectral_bleed` -> `zoom_params.z`), `sdGyroid` / 3-layer `map_gyroid` smooth-merged with `sdSphere`, inverse-distance whirlpool twist `invDist * twist`, held-mouse pull (`u.zoom_config.w > 0.5`), per-channel raymarch (`dR`, `dG`, `dB`), `plasmaBuffer[0].xz` bass/treble reactivity, `1.0 / minDepth` depth output.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `raymarch()` steps each channel to the surface without measuring the ray's impact parameter against the central photon sphere, and `get_normal()` shades the gyroid with flat Lambertian diffuse without crevice occlusion.
  tactic 2 (physics one step further): A rotating singularity exhibits a photon sphere at r_ph = 1.5 * r_horizon with relativistic Doppler beaming (prograde approaching side blue-shifted and boosted, retrograde receding side dimmed and red-shifted), while deep 3-octave gyroid pores trap ambient light.
  tactic 3 (promote an intermediate): Impact parameter b = length(cross(ro, rd)) relative to r_horizon and hit position/normal (p, n) are already available in `main()`; promote b into the photon-sphere ring and (p, n) into 5-tap step-count AO.
  tactic 6 (use the history the shader already owns): `dataTextureA` already stores `finalColor`; reading `dataTextureC` with exact `textureLoad` provides frame-dragged relativistic afterglow persistence.
ADD (2 native ideas):
  1. Photon-sphere relativistic Doppler beaming & Einstein ring (`photonRing`, `dopplerBoost`, §12.2F Soft inverse-square) — Rays grazing the photon sphere radius r_ph = 1.5 * r_horizon (impact parameter b = length(cross(ro, rd))) ignite a soft inverse-square Einstein ring with relativistic Doppler beaming (approaching whirlpool limb boosted and blue-shifted, receding limb reddened).
  2. Gyroid labyrinth step-count ambient occlusion & frame-dragged C history (`gyroidAO`, `frameDragHistory`, §12.2E Step-count AO) — 5-tap SDF ambient occlusion along the surface normal darkens deep 3-octave gyroid pores while Fresnel-Schlick rim dispersion and exact `textureLoad(dataTextureC, coord, 0)` history preserve relativistic trails before ACES tone-mapping.
FORMULA ADMISSION: §12.2F Soft inverse-square and §12.2E Step-count AO both belong to generative/SDF & optical families, consume existing ray `ro`/`rd`, `r_horizon`, `map()`, and `dataTextureC`, and pass the deletion test in both directions.
FORBID on this file: extraBuffer springs, click ripple loops, replacing the 3-channel raymarcher, changing any saved param.
A PACKING: ACES display RGBA in `dataTextureA`; read back via `textureLoad(dataTextureC, coord, 0)` as frame-dragged afterglow history.
```

---

## 2. `gen-kimi-crystal` (`public/shaders/gen_kimi_crystal.wgsl`)

```
SHADER: gen-kimi-crystal
IDENTITY (one sentence): Hexagonal ice crystals undergoing Nakaya plate-to-stellar-dendrite habit growth with physical ice-IOR Fresnel/Beer transmission and 22°/46° atmospheric halos, parhelia, and light pillars around the pointer sun.
KEEP VERBATIM: 4 saved params (`density` -> `zoom_params.x`, `purity` -> `zoom_params.y`, `growth` -> `zoom_params.z`, `thickness` -> `zoom_params.w`), odd-row hex grid, `sdHexagon` + `sdDendrite` Nakaya habit transition, `IOR_ICE = 1.31` (`1.31/1.32/1.33`), Fresnel-Schlick + Beer-Lambert transmission, 22° and 46° halos (`prismMinDeviation`, `prismMinDeviation90`), parhelia sun dogs, light pillars, click nucleation fronts.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): Each hex cell already computes `plateD` and `dendD` in `hexLocal`, but treats the crystal thickness as a smooth radial ramp (`1.0 - distFromCenter * 0.3`) without the stepped hexagonal basal hopper terraces and dendritic midrib air-inclusion veils of real snow crystals.
  tactic 2 (physics one step further): Horizontal hexagonal ice plates that create parhelia and light pillars also refract light through their 90° basal-to-prism edges to form an inverted circumzenithal / upper tangent arc crowning the 46° halo with vivid spectral separation.
  tactic 3 (promote an intermediate): `plateD` and `hexLocal` are already computed per pixel; promoting `plateD` into stepped hopper terrace contours modulates `pathLength` and specular glints, while `sunVec` and `r46R/G/B` directly position the circumzenithal tangent arc above the sun.
  tactic 6 (use the history the shader already owns): `dataTextureA` already stores `finalColor` (ACES display RGBA); reading `textureLoad(dataTextureC, px, 0)` adds subtle diamond-dust scintillation memory on crystal facets.
ADD (2 native ideas):
  1. Hexagonal basal hopper terraces & dendrite midrib air-inclusion veil (`hopperTerrace`, `midribVeil`, §12.2E SDF curvature / step contour) — Stepped hexagonal growth risers inside `plateD` modulate local ice `pathLength` and facet specular glints, while six-fold dendritic midrib ribs trap microscopic air-bubble veils that scatter crisp white light along the crystal arms.
  2. Circumzenithal / upper tangent ice-prism arc & exact C frost-glint persistence (`circumzenithalArc`, `prevFrost`, §12.2F Cauchy dispersion) — Plate-habit crystals (`1.0 - habit`) project an upward-curving spectral circumzenithal arc crowning the 46° halo (`sunVec.y < 0`) dispersed by `IOR_ICE_R/G/B`, paired with exact `textureLoad(dataTextureC, px, 0)` facet-glint persistence.
FORMULA ADMISSION: §12.2E SDF step contour and §12.2F Cauchy dispersion operate directly on existing `plateD`, `hexLocal`, `sunVec`, `r46R/G/B`, and `dataTextureC`; deleting either leaves the existing Kimi Crystal intact.
FORBID on this file: extraBuffer springs, changing saved params, removing 22°/46° halos or Nakaya dendrite transition.
A PACKING: ACES display RGBA in `dataTextureA`; read back via `textureLoad(dataTextureC, px, 0)` for diamond-dust scintillation persistence.
```

---

## 3. `gen-liquid-crystal-hive-mind`

```
SHADER: gen-liquid-crystal-hive-mind
IDENTITY (one sentence): A raymarched honeycomb of hexagonal bio-synthetic cells filled with turbulent nematic liquid crystal exhibiting crossed-polariser birefringence, 4-brush schlieren crosses, and cell-to-cell relay waves over a persistent raw sim state in `dataTextureA`.
KEEP VERBATIM: 4 slider mappings (`zoom_params.x` Cell Density, `zoom_params.y` Fluid Turbulence, `zoom_params.z` Sync Pulse, `zoom_params.w` Disruption Radius), `opRepHex`, `sdHexPrism`, `curlNoise` + `fbm`, crossed-polariser `extinction` & `retardance`, cell-to-cell `relay` wave, 4-brush `brush` cross, `refractory` dip, click chemotactic fronts, and raw sim state packing `vec4(bass, mids, treble, nextHivePulse)` in `dataTextureA`.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): In `map()`, the nematic director `res.director` follows `curlNoise` uniformly across the cell without accounting for homeotropic/planar boundary anchoring at the hexagonal prism wall (`innerHex`), where real confined liquid crystals twist into a boundary layer and form cholesteric Grandjean-Cano pitch lines.
  tactic 2 (physics one step further): Confined liquid-crystal cells wet the six interior corners of their hexagonal prism walls with a curved capillary meniscus, and the excitable hive pulse stored in `dataTextureC.a` diffuses spatially across neighbouring pixels rather than evolving only pointwise.
  tactic 3 (promote an intermediate): `innerHex` and `cellUV = grid.uv / hexSize` are already computed in `map()`; promoting wall proximity `abs(innerHex)` drives both boundary director anchoring and Grandjean-Cano cholesteric pitch fringes.
  tactic 6 (use the history the shader already owns): `dataTextureC.a` already stores `hivePulse`; evaluating an isotropic 9-point Laplacian stencil (§12.2D) on `dataTextureC.a` diffuses the chemotactic hive pulse spatially into `nextHivePulse` without changing the raw sim packing.
ADD (2 native ideas):
  1. Hex-wall homeotropic director anchoring & Grandjean-Cano cholesteric pitch stripes (`wallAnchoring`, `grandjeanPitch`, §12.2F Thin-film phase) — Proximity to the hexagonal cell wall (`innerHex`) anchors `res.director` toward the hex wall normal and imprints concentric Grandjean-Cano cholesteric pitch bands into the birefringent `retardance` phase.
  2. Spatial hive-pulse 9-point Laplacian diffusion in `dataTextureC` & hex-corner meniscus pooling (`pulseLaplacian`, `meniscusPool`, §12.2D Isotropic 9-point Laplacian) — An isotropic 9-point Laplacian stencil on `dataTextureC.a` (`hivePulse`) diffuses chemotactic fronts across neighbouring cells in `nextHivePulse`, while capillary meniscus fillets (`meniscusPool`) brighten the six interior hex-prism corners.
FORMULA ADMISSION: §12.2F Thin-film phase and §12.2D Isotropic 9-point Laplacian consume existing `innerHex`, `cellUV`, `retardance`, and `dataTextureC.a` raw state; both pass the deletion test.
FORBID on this file: extraBuffer springs, ACES tone-mapping `dataTextureA` (must remain raw sim state), changing slider mappings.
A PACKING: Raw sim state (`A.rgb` = smoothed bass/mids/treble envelopes, `A.a` = `nextHivePulse` with spatial Laplacian diffusion; not tone-mapped).
```

---

## 4. `gen-bismuth-crystal-citadel`

```
SHADER: gen-bismuth-crystal-citadel
IDENTITY (one sentence): An endless raymarched six-fold canyon of stepped hopper bismuth crystals, molten tier-gap bismuth pools, and an axial beacon column with metallic Fresnel and oxide thin-film interference.
KEEP VERBATIM: 4 saved params (`terrace_step_size` -> `zoom_params.x`, `ascension_speed` -> `zoom_params.y`, `metallic_shine` -> `zoom_params.z`, `iridescence_shift` -> `zoom_params.w`), `wallSd`, bounded 2×2×2 `terraceSd`, `poolSd` / `meltColor` / `poolSeen`, `beaconGlow`, `calcAO`, hopper growth striae, cathodoluminescent pinnacle arcs, and pre-ACES HDR history in `dataTextureA`/`dataTextureC`.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `calcNormal(p)` already samples `map(p ± e)` along all three axes; combining those axis samples with `map(p).x` yields the 3D SDF mean curvature κ (§12.2E), which physically governs oxide layer thickness on cooling bismuth hopper edges vs concave step recesses.
  tactic 2 (physics one step further): Bismuth crystals grown from the melt develop diagonal {110} polysynthetic twin lamellae across their terraces, while the molten bismuth tier-gap pools (`m > 1.5`) nucleate 6-fold solidifying skeletal crystal rafts at their outer cooling rim with blackbody ember menisci.
  tactic 3 (promote an intermediate): `p`, `n`, `radius`, and `m` are already available at the hit point; promoting SDF curvature κ into `iriPhase` and `radius`/`atan2(p.z, p.x)` on `m > 1.5` hits into solidifying hopper rafts enriches both materials natively.
  tactic 6 (use the history the shader already owns): `dataTextureC` already provides the pre-ACES HDR rising trail (`prev = textureLoad(dataTextureC, coord, 0)`).
ADD (2 native ideas):
  1. SDF-curvature oxide thickness shift & {110} polysynthetic twin lamellae (`sdfCurvature`, `twinLamellae`, §12.2E SDF curvature) — 6-tap finite-difference SDF curvature κ shifts the bismuth oxide thin-film phase (`iriPhase`) between hot gold-magenta on convex hopper edges and deep cyan-violet in concave step recesses, while 45° polysynthetic twin lamellae modulate micro-facet specular reflection.
  2. Solidifying 6-fold hopper crystal rafts & blackbody meniscus seams on the molten pools (`solidifyingRafts`, `meniscusEmber`, §12.2F Rayleigh / blackbody) — On the molten tier-gap pools (`m > 1.5`), six-fold skeletal bismuth hopper rafts freeze inward from `POOL_RADIUS`, bordered by incandescent blackbody meniscus seams (`meniscusEmber`) and mirror-bright solid bismuth terraces.
FORMULA ADMISSION: §12.2E SDF curvature and §12.2F blackbody/Fresnel operate on the existing `map()`, `p`, `n`, and `m > 1.5` pool branch; deleting either leaves the existing citadel intact.
FORBID on this file: extraBuffer springs, click ripples, tone-mapping `dataTextureA` before storing HDR history, changing saved params.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha in `dataTextureA`; read back from `dataTextureC` via exact `textureLoad`.
```

---

## 5. `gen-prismatic-cyber-chrono-void-kitsune`

```
SHADER: gen-prismatic-cyber-chrono-void-kitsune
IDENTITY (one sentence): A nine-tailed cybernetic void-kitsune with cellular quantum-glass armour, Cauchy-dispersed refraction, kitsunebi fox-fire wisps, caudal tail caustics, and a helical volumetric rift tunnel.
KEEP VERBATIM: 4 saved params (`tailDispersion` -> `zoom_params.x`, `riftDensity` -> `zoom_params.y`, `runeIntensity` -> `zoom_params.z`, `glassRefraction` -> `zoom_params.w`), 4 material IDs (1=Body, 2=Tails, 3=Rift, 4=Dust), 9-tail loop in `map()` and `kitsunebi()`, Cauchy-dispersed refraction (`n_r`, `n_b`), caudal-band tail caustics, helical rift current sheets, click shockwave tail lash, ACES display RGBA in `dataTextureA`/`dataTextureC`.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): In `map()`, `d_body` is a single cellular-perturbed sphere at `(0, 0, 5)` without sculpted kitsune fox ears, tapered muzzle snout, or crevice ambient occlusion inside the cellular armour seams.
  tactic 2 (physics one step further): The cyber-glass body (`m == 1.0`) transmits light through varying armour thickness (Beer-Lambert absorption) and glows along angular cyber-visor eye slits, while the 9 tails (`m == 2.0`) exchange azimuthal magnetic-reconnection plasma filaments across the inter-tail gaps.
  tactic 3 (promote an intermediate): `body_pos = pt - vec3<f32>(0.0, 0.0, 5.0)` is already computed in `map()`; promoting bilateral ear cones and a forward snout into `d_body` gives a true fox head silhouette, while `p` and `n` on `m == 1.0` feed 5-tap step-count AO (`aoFive`).
  tactic 6 (use the history the shader already owns): `dataTextureC` is already read at `prev_coord` for temporal glass smear.
ADD (2 native ideas):
  1. Sculpted kitsune fox ears, tapered snout, cyber-visor eye slits & armour crevice AO (`d_ears`, `d_snout`, `visorEyeGlow`, `armorAO`, §12.2E Step-count AO) — Bilateral swept fox ears and a forward muzzle sculpt `d_body` in `map()`, while 5-tap SDF ambient occlusion darkens the cellular armour grooves and luminous cyber-visor eye slits blaze across the brow.
  2. Inter-tail 9-fold braided plasma filaments & Beer-Lambert armour thickness absorption (`interTailArc`, `armorAbsorption`, §12.2F Fresnel–Schlick / Beer–Lambert) — Azimuthal 9-fold plasma filaments bridge adjacent tails across the fan, and Beer-Lambert absorption `exp(-sigma * thickness)` tints the Cauchy-dispersed body armour by path length.
FORMULA ADMISSION: §12.2E Step-count AO and §12.2F Beer–Lambert consume existing `body_pos`, `map()`, `n`, `view`, and `bg_col`; both pass the deletion test.
FORBID on this file: extraBuffer springs, changing material IDs 1..4, changing saved params.
A PACKING: ACES display RGBA in `dataTextureA`; read back via `textureLoad(dataTextureC, prev_coord, 0)`.
```

---

## 6. `gen-chrono-kitsune-prism-weaver`

```
SHADER: gen-chrono-kitsune-prism-weaver
IDENTITY (one sentence): A prismatic kitsune spirit whose central body acts as a white-light prism dispersing into 3–9 fractional-unfurling spectral tails pulsed by a travelling lub-dub heartbeat and HDR radial echo feedback.
KEEP VERBATIM: 4 saved params (`prism_hue_shift` -> `zoom_params.x`, `tail_count` -> `zoom_params.y`, `weave_tightness` -> `zoom_params.z`, `chrono_echo` -> `zoom_params.w`), bounding-sphere early-out (`BOUND_C`, `BOUND_R`), tetrahedral `calcNormal`, `heartbeat()` lub-dub transfer, `spectralBand()`, fractional tail unfurl (`tail_full`, `tail_grow`), revolving spirit fireballs (`d_orbs`), prismatic temporal shockwaves, and HDR radial echo in `dataTextureA`/`dataTextureC`.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `mapKitsune` models the prism body as a rippled sphere without kitsune ear crests, and shades `m < 1.5` using only silhouette Fresnel (`mix(core, rim_col, fre)`) without tracing internal Snell-refracted Cauchy rays through the prism body.
  tactic 2 (physics one step further): A real prism body refracts incoming ray `rd` across surface normal `n` via Snell's law with Cauchy wavelength dispersion (`1.0 / n_rgb`), and fox tails (`m > 1.5`) have plumose chevron guard-hair barbules that bristle as the arterial `heartbeat` pulse wave passes down `s_along`.
  tactic 3 (promote an intermediate): `pulse` (`hit.w`), `band` (`hit.z`), `p`, and `n` are already available at the hit point; promoting `refract(rd, n, eta)` on `m < 1.5` gives internal 3-wavelength prism caustics, and promoting `p.z - TAIL_Z_START` on `m > 1.5` gives plumose chevron fur barbules.
  tactic 6 (use the history the shader already owns): `dataTextureC` is already sampled at `prev_px` along `center_dir`; offsetting R and B by `±1` pixel along `center_dir` turns the existing feedback tint into true radial prismatic echo dispersion.
ADD (2 native ideas):
  1. Internal 3-wavelength Snell-Cauchy prism body refraction & kitsune ear-crest facets (`prismInternalRefract`, `d_earCrest`, §12.2F Snell vector refraction + Cauchy dispersion) — Bilateral kitsune ear-crest facets crown `BODY_POS` in `mapKitsune`, and body hits (`m < 1.5`) trace 3 Cauchy-dispersed Snell refraction vectors (`refract(rd, n, etaRGB)`) through an internal caustic lattice before blending with the spectral silhouette rim.
  2. Plumose tail-fur chevron barbules & radial chromatic C-echo split (`furBarbules`, `echoChroma`, §12.2E Orbit trap) — Along each splayed tail (`m > 1.5`), chevron guard-hair barbule ridges (`furBarbules`) catch anisotropic specular light and flare with the travelling `heartbeat` pulse, while the `dataTextureC` radial echo splits R/G/B by `±1` texel along `center_dir`.
FORMULA ADMISSION: §12.2F Snell vector refraction + Cauchy dispersion and §12.2E Orbit trap consume existing `rd`, `n`, `p`, `pulse`, `band`, and `prev_px`; both pass the deletion test.
FORBID on this file: extraBuffer springs, breaking bounding-sphere early-out `BOUND_R`, tone-mapping `dataTextureA` (must stay pre-ACES HDR), changing saved params.
A PACKING: HDR linear RGB (pre-ACES, clamped to `HDR_CEIL = 8.0`) + semantic alpha in `dataTextureA`; read back via `textureLoad(dataTextureC, ...)` as dispersive radial echo.
```

---

## 7. `gen-chronomorphic-glass-tesseract`

```
SHADER: gen-chronomorphic-glass-tesseract
IDENTITY (one sentence): A 4D-rotating glass hypercube (`rotXY..rotZW`) with chronomorphic spatial ripples, W-slice crossing caustic sheets, W-phase chromatic dispersion, schlieren stress striae, and mouse gravity-well lensing.
KEEP VERBATIM: 4 saved params (`fold_speed` -> `zoom_params.x`, `dispersion` -> `zoom_params.y`, `refraction_ior` -> `zoom_params.z`, `gravity` -> `zoom_params.w`), 6-plane 4D rotation `rotateTesseractPoint`, `sdf_tesseract`, `tesseractSliceMetrics`, W-phase `temporal_delay` dispersion (`iorR/G/B`), schlieren stress lines, corner TIR flashes, mouse gravity well `rd_warp`.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `sdf_tesseract` computes `d = abs(p) - vec4<f32>(s)` for the outer 4D block, discarding the 2-face pane recesses, 32 wireframe edges, and inner W-projected cube of a true 4D tesseract Schlegel projection.
  tactic 2 (physics one step further): In a 4D glass tesseract, the 32 wireframe struts and 8 diagonal W-vertex connectors form a recessed hyper-frame around an inner W-cube core, and light grazing the 16 4D hypercube vertices (`abs(p4) ≈ vec4(1.0)`) produces Airy-disc diffraction rings `(2 J1(x)/x)^2`.
  tactic 3 (promote an intermediate): `p4 = rotateTesseractPoint(p3, time)` is already computed in `sdf_tesseract` and `tesseractSliceMetrics`; sorting the pairwise maxima of `abs(p4)` yields the 4D wireframe strut distance and 16-vertex proximity without extra 4D rotations.
  tactic 6 (use the history the shader already owns): `dataTextureA` already stores `display`, while `dataTextureC` was unread; reading `textureLoad(dataTextureC, coord, 0)` adds a W-slice chronomorphic temporal echo.
ADD (2 native ideas):
  1. Schlegel 4D wireframe struts, recessed glass panes & inner hypercube core (`strutDist4D`, `innerCubeCore`, §12.2E Fold count as material) — From the rotated 4D point `p4`, pairwise component maxima carve bevelled glass pane recesses between the 32 tesseract wireframe struts and reveal an inner W-projected hypercube core.
  2. 16-vertex Airy-disc diffraction flares & chronomorphic C-history echo (`vertexAiryGlint`, `chronoHistory`, §12.2F Airy disc) — At the 16 4D hypercube vertices where `length(abs(p4) - vec4(1.0))` vanishes, a polynomial Bessel Airy disc `(2 J1(x)/x)^2` blooms with spectral diffraction rings, paired with exact `textureLoad(dataTextureC, coord, 0)` W-phase temporal persistence.
FORMULA ADMISSION: §12.2E Fold/component metric and §12.2F Airy disc consume `p4` from `rotateTesseractPoint` and `dataTextureC`; both pass the deletion test.
FORBID on this file: extraBuffer springs, click ripples, changing the 4D rotation schedule or saved params.
A PACKING: ACES display RGBA in `dataTextureA`; read back via `textureLoad(dataTextureC, coord, 0)` for chronomorphic W-phase persistence.
```

---

## 8. `gen-holographic-bismuth-core-reactor`

```
SHADER: gen-holographic-bismuth-core-reactor
IDENTITY (one sentence): A raymarched 4-iteration KIFS bismuth fractal reactor core with orbiting micro-crystals, 4 articulating boron/graphite control rods (`sdRods`), fold-seam fuel channels (`coreSeamTrap`), and spherical magnetic containment flux lines.
KEEP VERBATIM: 4 saved params (`intensity` -> `zoom_params.x`, `speed` -> `zoom_params.y`, `scale` -> `zoom_params.z`, `mouseInfluence` -> `zoom_params.w`), `applyGenerativePrimaryControls`, `reactorFrame`, `rodInsertion` / `sdRods` (material `3.0 + rodIdx`), `coreSeamTrap`, 4-step KIFS `map()` (core=1, micro-crystals=2), `bismuthOxidationColor`, hopper terrace edge glints, magnetic containment shell flux, click rings, and pre-controls HDR history in `dataTextureA`/`dataTextureC`.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `coreSeamTrap` already runs the 4-iteration KIFS loop on `isCoreHit` pixels to find `trap`, but discards the per-iteration mirror-fold count (`foldGen`) and has no ambient occlusion inside the deep KIFS reactor cavities.
  tactic 2 (physics one step further): When the 4 boron control rods withdraw (`criticality = mix(1.25, 0.7, meanIns)`), high-energy electrons in the reactor vessel emit deep blue-violet Cherenkov phase-cone radiation around the core and annular coolant wakes around the immersed rod tips.
  tactic 3 (promote an intermediate): Returning `vec2<f32>(trap, foldGen)` from `coreSeamTrap` quantizes the bismuth oxide thickness (`bismuthOxidationColor`) by KIFS terrace generation, while `criticality` and `rodTipY` directly drive Cherenkov cone emission and rod-tip coolant wakes.
  tactic 6 (use the history the shader already owns): `dataTextureC` is already read at `coord` for pre-controls HDR history.
ADD (2 native ideas):
  1. KIFS fold-generation oxide stepping & 5-tap reactor cavity ambient occlusion (`foldGen`, `cavityAO`, §12.2E Fold count as material) — `coreSeamTrap` accumulates the mirror-fold parity count across the 4 KIFS levels to step the bismuth oxide interference thickness per terrace generation, while a 5-tap normal AO (`aoFive`) darkens deep KIFS cavities so the amber fuel seams pop.
  2. Criticality-driven Cherenkov phase-cone radiation & control-rod coolant wake rings (`cherenkovCone`, `rodWakeRing`, §12.2F Fresnel–Schlick / Henyey–Greenstein / Beer–Lambert) — Scaled by reactor `criticality`, forward-peaked Cherenkov blue-violet radiation (`vec3(0.16, 0.52, 1.0)`) blooms along the Cherenkov phase angle around the core and forms glowing annular coolant wake rings around the 4 control-rod tips.
FORMULA ADMISSION: §12.2E Fold count as material and §12.2F Henyey-Greenstein / Cherenkov forward cone operate on `coreSeamTrap`, `map()`, `criticality`, and `rodTipY`; both pass the deletion test.
FORBID on this file: extraBuffer springs, tone-mapping `dataTextureA` before `applyGenerativePrimaryControls`, changing saved params.
A PACKING: HDR history RGBA (pre-controls) in `dataTextureA`; `writeTexture` receives `acesToneMap(applyGenerativePrimaryControls(A).rgb)`.
```

---

## 9. `glass-shatter-morph`

```
SHADER: glass-shatter-morph
IDENTITY (one sentence): Interactive shattered glass where Voronoi shards are displaced by a spring-smoothed cursor and sculpted by mathematical morphology (erosion/dilation gradient) with chromatic refraction, micro-fractures, TIR glints, and photoelastic stress fringes.
KEEP VERBATIM: 4 saved params (`shard_scale` -> `zoom_params.x`, `displacement` -> `zoom_params.y`, `morph_blend` -> `zoom_params.z`, `edge_width` -> `zoom_params.w`), `[133..138]` spring cursor, click shockwaves, `(2*kRadius+1)^2` morphological `erosion`/`dilation` loop (`morphGradient`, `morphRGB`), shard tilt Fresnel, R/G/B aberration, micro-fracture spiderweb cracks, grazing TIR glints, photoelastic stress fringes, and `dataTextureC` trail persistence.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `voronoi()` currently tracks only nearest-seed distance `F1` (`res.dist`), so `edgeProx` highlights a ring around the cell center instead of the true polygonal Voronoi fracture boundary `F2 - F1`! Tracking `F2` and the inter-seed bisector vector inside `voronoi()` gives exact polygonal shard seams and 3D chipped bevel normals.
  tactic 2 (physics one step further): Real shattered glass exhibits conchoidal Wallner stress-wave hackle ripples curving across each shard face from the fracture origin, while the morphological extrema `[erosion, dilation]` form both top-hat/black-hat chipped edge frosting and an anti-halo clamp envelope inside each shard.
  tactic 3 (promote an intermediate): The morphological box loop already computes `erosion` (`minVal`), `dilation` (`maxVal`), and `centerSample`; promoting `sample - erosion` (white top-hat) and `dilation - sample` (black-hat) frosts the true `F2 - F1` shard bevels while clamping interior shard refraction within `[erosion - r, dilation + r]`.
  tactic 6 (use the history the shader already owns): `dataTextureC` is already read via `textureLoad(dataTextureC, pixel, 0).rgb`.
ADD (2 native ideas):
  1. True `F2 - F1` polygonal Voronoi fracture bevels & conchoidal Wallner hackle ripples (`edgeDist`, `bevelNormal`, `wallnerHackle`, §12.2F Snell vector refraction) — `voronoi()` tracks both nearest (`F1`) and second-nearest (`F2`) seeds so `edgeDist = F2 - F1` defines crisp polygonal shard cracks with Snell-refracting 3D bevel normals and concentric Wallner stress-wave hackle arcs across each shard face.
  2. Morphological top-hat / black-hat crack frosting & anti-halo shard clamp (`topHatFrost`, `antiHaloClamp`, §12.2A Anti-halo envelope) — Promotes the existing morphological `erosion` and `dilation` extrema into white/black top-hat crystalline frosting along the `F2 - F1` bevels and clamps interior shard refraction within the `[erosion - r, dilation + r]` anti-halo envelope.
FORMULA ADMISSION: §12.2F Snell bevel refraction and §12.2A Anti-halo envelope operate directly on `voronoi()` and the existing `erosion`/`dilation` loop; both pass the deletion test.
FORBID on this file: adding a second spring, removing the morphological erosion/dilation loop, changing saved params.
A PACKING: ACES display RGBA in `dataTextureA`; read back via `textureLoad(dataTextureC, pixel, 0)`.
```

---

## 10. `fractal-glass-distort`

```
SHADER: fractal-glass-distort
IDENTITY (one sentence): An 8-iteration 4-map affine IFS stained-glass distortion filter where base-4 map addresses define coloured cathedral glass panes, lead came lines, Beer-Lambert absorption, and wavelength-dispersed contraction gradients.
KEEP VERBATIM: 4 saved params (`contraction` -> `zoom_params.x`, `rotation` -> `zoom_params.y`, `refraction` -> `zoom_params.z`, `aberration` -> `zoom_params.w`), `[133..138]` spring cursor, 4-map `ifsAttractorDensity` returning `(density, address)`, 3-wavelength `conR`/`contraction`/`conB` gradients (`gradR`, `gradG`, `gradB`), `paneTint(address)`, `lead` came detection, Beer-Lambert `absorb`, Schlick `fresnel`, click rings, and post-ACES `dataTextureC` persistence.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): Inside `ifsAttractorDensity`, the 8-iteration loop already updates `q` at every step but discards the minimum axial orbit-trap distance (`min(abs(q.x), abs(q.y))`), which maps the internal fibrous glass ream swirls and seed bubbles of hand-rolled cathedral stained glass.
  tactic 2 (physics one step further): Real stained-glass windows join panes with rounded H-channel lead cames that have raised silvered solder bosses at multi-pane junctions and cast a subtle directional bevel drop-shadow onto the adjacent glass pane.
  tactic 3 (promote an intermediate): Promoting an orbit-trap accumulator inside `ifsAttractorDensity` yields antique glass ream striae and seed-bubble glints at zero extra IFS calls, while the neighbour address checks (`dGx.y`, `dGy.y`) already computed for `lead` identify multi-pane solder junctions and directional came relief.
  tactic 6 (use the history the shader already owns): `prevC = textureLoad(dataTextureC, coord, 0).rgb` is already mixed post-ACES; weighting its persistence by pane density `d0` gives thick stained-glass panes a warm cathedral afterglow while keeping lead lines sharp.
ADD (2 native ideas):
  1. IFS orbit-trap antique glass ream striae & trapped seed-bubble glints (`reamVein`, `seedBubble`, §12.2E Orbit trap) — An orbit trap inside the existing 8-iteration `ifsAttractorDensity` loop captures internal fractal vein distance, producing hand-rolled antique stained-glass ream swirls and tiny specular air-seed bubbles inside each coloured pane.
  2. 3D rounded lead-came profile, silvered solder-joint bosses & pane bevel shadow (`cameRelief`, `solderBoss`, `paneShadow`, §12.2A Local contrast / bevel relief) — Where neighbour base-4 addresses (`dGx.y`, `dGy.y`) diverge, directional address gradients sculpt a rounded metallic H-channel lead came with bright solder bosses at 3-way junctions and a bevel drop-shadow across the adjacent pane edge.
FORMULA ADMISSION: §12.2E Orbit trap and §12.2A bevel relief operate directly inside `ifsAttractorDensity` and on `dGx.y`/`dGy.y` address transitions; both pass the deletion test.
FORBID on this file: adding a new solver, removing `paneTint` or wavelength IFS gradients, changing saved params.
A PACKING: ACES display RGBA (alpha = glass coverage) in `dataTextureA`; read back via `textureLoad(dataTextureC, coord, 0)`.
```
