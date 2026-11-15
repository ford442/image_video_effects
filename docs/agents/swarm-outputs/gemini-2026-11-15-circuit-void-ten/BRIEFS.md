# Idea Cards — gemini/circuit-void-ten (2026-11-15)

Written **before** any WGSL edits. Ten catalog shaders (132–137 lines) spanning interactive-mouse, image, artistic, advanced-hybrid, and generative families. Every card adds 2 native ideas inside the existing main path. Saved `params` stay byte-exact. No new spring is introduced anywhere (`voxel-depth-sort` keeps the spring it already owns in `extraBuffer[133..138]`). No shared ripple stamp or cosine palette.

Six files still paste the canonical binding header (`circuit-breaker`, `double-exposure-hdr`, `double-exposure-zoom`, `magma-fissure`, `gen-prismatic-serpent-river`, `aurora-rift-2`). Those are migrated first with `python3 scripts/migrate_to_prelude.py --files ...`; that header swap is plumbing and is not counted toward any Idea Card.

**Batch formula de-duplication (§12.4 / §12.7):** every §12.2 formula row used appears **at most once** across all ten files:
- Schmitt-trigger lock (§12.2B) → `circuit-breaker` only
- Vorticity confinement (§12.2D) → `aerogel-smoke` only
- Beer–Lambert spectral extinction (§12.2F) → `aerogel-smoke` only
- Halation (§12.2A) → `double-exposure-hdr` only
- Cauchy dispersion (§12.2F) → `double-exposure-zoom` only
- Isotropic 9-point Laplacian (§12.2D) → `magma-fissure` only
- Drying (§12.2C) → `cross-conv-mouse-bilateral` only
- Fresnel–Schlick (§12.2F) → `gen-prismatic-serpent-river` only
- Orbit trap (§12.2E) → `gen-synaptic-void-weaver` only
- Step-count AO (§12.2E) → `gen-synaptic-void-weaver` only

---

## 1. circuit-breaker

```
SHADER: circuit-breaker
IDENTITY: transforms the source image into an etched PCB circuit board whose copper traces and solder nodes overload and arc near the cursor.
KEEP VERBATIM: Grid Scale, Overload, Jitter, Edge Threshold; aspect-corrected mouse influence + bass boost; gridUV / gridID / gridLine; 10% node hash; influence-proportional UV jitter; 4-tap luma edge detection + edgeThreshold gate; green circuitColor (0.0, 0.8, 0.2) to cyan overloadColor (0.5, 0.8, 1.0) mix; treble-modulated node flash; scanline modulation.
MECHANISM INTERROGATION:
  tactic 5 (artifact of the real device): a real PCB has annular copper via rings with drilled centers and 45°-routed bus tracks, whereas `node` currently lights the entire square cell flat.
  tactic 7 (direction, not just magnitude): `edgeX` and `edgeY` are already computed and collapsed to scalar `edge`; quantizing their angle to 45° PCB octants aligns copper traces and signal pulses along real photo contours.
  tactic 6 (use the history the shader already owns): `dataTextureA` is written and `dataTextureC` is never read; a real circuit breaker latches open when overloaded and resets only once load drops below a lower threshold.
ADD (2 native ideas):
  1. Annular via pads & 45°-routed edge traces — `fract(gridUV) - 0.5` shapes `node` cells into copper solder rings with dark drill holes and routes `edgeX/edgeY` along quantized 45° PCB trace lanes carrying travelling current pulses.
  2. Breaker trip latch (§12.2B Schmitt-trigger lock) — overload drive per `gridID` latches a trip bit in `A.a` (`C.a` hysteresis: trips above `hi`, resets below `lo`); tripped cells open-circuit their green trace into charred copper while flashing an arc burst on trip onset and cooling via `C.rgb`.
FORBID: a spring cursor, click ripple rings, IQ rainbow palette, raymarching.
A PACKING: ACES display RGB in A.rgb + Schmitt-trigger breaker latch in A.a (read back from exact `dataTextureC`). `writeTexture` carries ACES RGB + semantic circuit/edge/overload alpha.
```

---

## 2. aerogel-smoke

```
SHADER: aerogel-smoke
IDENTITY: buoyant silica aerogel ("frozen smoke") advecting density, scattering energy, and flow in raw A/C state over the source image with Rayleigh blue opalescence and Henyey–Greenstein forward scatter.
KEEP VERBATIM: Density, Blue Scatter, Light Intensity, Background Visibility; raw A/C `[density, energy, velocity.x, velocity.y]` packing; `phaseHG`; ambient + micro value-noise seeding; curlDriver + upward buoyancy; hover light, held plume injection, click shell/core plumes; volumetric depth blend.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `advectedCoord = coord - vec2<i32>(round(velocityPixels))` quantizes sub-pixel drift (`|v| < 0.5 px`) to zero so slow aerogel smoke stalls on pixel boundaries, while neighbour averaging damps fine swirls even though `north/south/east/west` velocities are already loaded.
  tactic 2 (physics one step further): real silica aerogel is famous for dichroic Rayleigh opalescence — scattered light is sky-blue, while transmitted background light loses blue 4× faster than red ("sunset through aerogel"), whereas `transmittance = exp(-opticalDepth)` is currently neutral grey.
  tactic 3 (promote an intermediate): `north.zw, south.zw, east.zw, west.zw` are already fetched for `neighborAverage`; their curl gives vorticity at near-zero extra cost.
ADD (2 native ideas):
  1. Sub-pixel exact-load advection & vorticity confinement (§12.2D) — bilinear interpolation across four exact `stateAt` integer loads replaces `round()` grid-sticking, and curl from the already-loaded neighbour velocities feeds a confinement force that preserves curling silica wisps.
  2. Dichroic Rayleigh Beer–Lambert extinction (§12.2F) — wavelength-selective optical depth scaled by `Blue Scatter` attenuates blue/green faster than red in transmitted `source.rgb`, warming backlit silhouettes to amber while scattered aerogel stays icy blue.
FORBID: ACES on `dataTextureA` (would corrupt raw sim state), a spring cursor, changing A/C channel roles.
A PACKING: raw transport state `[density, scattering energy, velocity.x, velocity.y]` (unchanged; ACES on `writeTexture` only).
```

---

## 3. double-exposure-hdr

```
SHADER: double-exposure-hdr
IDENTITY: in-camera photographic double exposure overlaying a mouse-pivoted zoomed/rotated second plate onto the base photo, with overlap-keyed HDR bloom and ACES tone mapping.
KEEP VERBATIM: Zoom Level, Rotation, Opacity, Saturation; mouse-pinned aspect-correct `rotate2d` + `zoom` second plate; screen blend baseline + saturation control; `overlapKnee` (`min(lum1, lum2)`); 12-tap dual-plate bloom loop; held-mouse warm exposure burn; click flash bursts; ACES display RGBA.
MECHANISM INTERROGATION:
  tactic 2 (physics one step further): on real double-exposed negative film, Plate 1's highlights already saturate silver halide near D-max while Plate 1's dark shadows remain unexposed emulsion where Plate 2 develops with rich contrast; a flat screen blend washes Plate 2 across bright skies instead of keying into dark silhouettes.
  tactic 8 (energy accounting): bright overlap regions in film bounce light off the film base back into the red-sensitive layer while bleaching clipped cores toward warm ivory rather than stacking pure additive RGB.
  tactic 3 (promote an intermediate): `lum1`, `lum2`, and the outer ring (`i % 4 >= 2`) of the existing 12-tap bloom loop are already evaluated every pixel.
ADD (2 native ideas):
  1. Latent shadow-silhouette emulsion keying — modulates Plate 2's print-through contrast using Plate 1's unexposed shadow reserve (`1.0 - smoothstep(0.18, 0.82, lum1)`), so the second exposure develops vividly inside dark silhouettes while preserving soft screen highlights.
  2. Emulsion base halation & shoulder core bleach (§12.2A) — accumulates red-amber bounce `(1.0, 0.36, 0.12)` from the outer taps of the existing 12-tap bloom loop and gently desaturates clipped overlap cores toward warm ivory before `toneMapACES`.
FORBID: a spring cursor, click ripple rings, IQ palettes, replacing the 12-tap bloom kernel.
A PACKING: ACES display RGBA (unchanged). C is unread.
```

---

## 4. voxel-depth-sort

```
SHADER: voxel-depth-sort
IDENTITY: converts the image and depth map into an isometric 3D grid of extruded voxel columns rotated by the mouse, with per-block height from luma and depth, AO, and audio/click lift.
KEEP VERBATIM: Block Size, Extrusion, BG Darken, Block Gap; existing mouse spring in `extraBuffer[133..138]` driving `isoRot` and `isoTilt`; click lift waves; `fftVoice` + `bass` modulation; depth-shifted block colour sample; `column` height from `max(luma, sourceDepth)`; `topMask`, `ao`, `rim`, `spectral`, `sss`, `aces_tonemap`; `depthOut` relief.
MECHANISM INTERROGATION:
  tactic 2 (physics/geometry one step further): each voxel currently draws only a flat 2D square `topMask` over flat `backgroundColor`, with no extruded 3D side skirts along the isometric tilt vector and no occlusion from taller adjacent columns.
  tactic 1 (deepen the kernel): sampling the adjacent upslope block along the tilt direction reveals whether a taller neighbour column overlaps this pixel's gap/cap or casts a step shadow across it.
  tactic 6 (use the history the shader already owns): `dataTextureA.x` already writes scalar block height/luma every frame while `dataTextureC` was unread; smoothing column height against `C.x` gives physical pinscreen settle after audio/click impulses.
ADD (2 native ideas):
  1. Extruded isometric X/Y voxel side walls — projects the column's 3D skirt along `(isoRot, isoTilt)` * `column * extrusion` inside the inter-block gap and background, shading East/West and North/South side faces with directional Lambertian falloff so blocks read as solid 3D pillars.
  2. Upslope neighbour depth-sort shadow & `C.x` column inertia — compares `column` against the adjacent upslope cell's height to cast proportional step shadows (and side-wall overlap) onto shorter neighbours, while `C.x` smooths column drop-off so lifted blocks settle with physical mass.
FORBID: a second spring, changing `extraBuffer[133..138]`, replacing blocks with raymarched spheres, ACES inside `dataTextureA`.
A PACKING: raw voxel fields `(settledColumn, topMask, depthConf, finalAlpha)` matching HEAD's field layout; `C.x` is read as previous settled column height. ACES on `writeTexture` only.
```

---

## 5. double-exposure-zoom

```
SHADER: double-exposure-zoom
IDENTITY: photographic double exposure pairing the source frame with a mouse-centered, depth-parallaxed, rotated and zoomed second exposure featuring highlight matte keying, film stock curve, light leaks, and C frame trail.
KEEP VERBATIM: Rotation, Zoom Level, Edge Fade, Audio Reactivity; exponential `zoom` (`pow(2.0, ...)`), depth parallax, continuous registration `drift`, aspect-correct rotation around `mouse`; `highlightKey` + screen/soft-light `matte`; `filmResponse` + `acesToneMap`; warm `lightLeak` + `vignette`; `dataTextureC` temporal trail.
MECHANISM INTERROGATION:
  tactic 5 (artifact of the real device): racking a zoom lens during a double-exposure shutter pulls radial zoom streaks outward from the optical pivot (`mouse`) with wavelength-dependent focal magnification (Cauchy dispersion), rather than a fixed diagonal `±0.008` UV nudge.
  tactic 3 & 4 (promote an intermediate / second-order `Edge Fade`): `edgeMask` (`smoothstep(0.0, 0.05 + edgeFade * 0.45, edgeDist)`) is computed from `Edge Fade` on line 91 and then *never applied* to Plate 2's blend weight — so when zoomed out (`zoom < 1`), clamped edge pixels smear across the frame regardless of `Edge Fade`.
ADD (2 native ideas):
  1. Radial zoom-rack streak & Cauchy focal dispersion (§12.2F) — replaces the static diagonal offset on Plate 2 with radial 3-tap shutter-zoom blur along `(uv2 - mouse)` scaled by zoom excursion `abs(zoomMod - 0.5)` and Cauchy R/G/B magnification `cauchyScale`.
  2. Sprocket-frame `edgeMask` gate & film-rebate border — wires the already-computed `edgeMask` into Plate 2's print-through weight so zoomed-out/rotated plates fade cleanly to Plate 1 instead of smearing clamped borders, accented by a subtle warm amber film-rebate line right inside `edgeDist = 0`.
FORBID: a spring cursor, click shockwave rings, sharing halation with `double-exposure-hdr`.
A PACKING: ACES display RGBA (unchanged), read back from exact `dataTextureC` for temporal trail.
```

---

## 6. magma-fissure

```
SHADER: magma-fissure
IDENTITY: branching thermal cracks and cooling basaltic crust simulated in raw `A.r`/`C.r` heat over the heat-haze-refracted source image, ignited by held pointer and click fractures.
KEEP VERBATIM: Cooling Rate, Fissure Width, Heat Haze, Brush Size; raw `A/C = [heat, 0, 0, 1]` packing; `magmaPalette`; held-pointer radial branching brush; expanding angular click-fracture shells; noise-driven `branching` + `diffusion` + `cooling`; refractive `distortedUV`; `crack` and `crust` masks; ACES on `writeTexture`.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): `neighborMean` uses a 4-neighbour axial cross (`L, R, T, B`), biasing crack diffusion along pixel X/Y axes; adding the 4 diagonal loads yields the isotropic 9-point stencil.
  tactic 2 (physics one step further): real lava cools by $T^4$ radiative loss fastest on exposed mid-heat surfaces, fracturing the solidifying `crust` band into dark polygonal basalt plates separated by glowing tensile micro-seams, while hot air above fissures rises convectively (`-y`) rather than shimmering symmetrically.
  tactic 3 (promote an intermediate): `heatGradient` is already computed for `flow`; its magnitude and tangent orient crust plate cracks and buoyant haze lift.
ADD (2 native ideas):
  1. Isotropic 9-point thermal stencil (§12.2D) & buoyant upward heat haze — upgrades the 4-tap neighbour average to the 9-point isotropic Laplacian so fissures propagate without axial grid bias, and adds upward convective plume drift + subtle refractive R/B split to `distortedUV`.
  2. Radiative $T^4$ cooling & fractured slag-crust plates — accelerates cooling slightly in exposed crust zones while cellular cooling joints along the `heatGradient` tangent break the `crust` band into dark basaltic slag plates veined with ember seams.
FORBID: ACES or extra channels in `dataTextureA` (`[newHeat, 0, 0, 1]` is contractual), a spring cursor.
A PACKING: raw `[heat, 0.0, 0.0, 1.0]` in A/C (unchanged; ACES on `writeTexture` only).
```

---

## 7. cross-conv-mouse-bilateral

```
SHADER: cross-conv-mouse-bilateral
IDENTITY: aspect-correct pointer brush (and click fronts) that paints edge-preserving 7×7 bilateral smoothness onto the photo, leaving edges crisp while smoothing interior surface noise.
KEEP VERBATIM: Brush Size, Edge Preservation, Effect Strength (3 saved params, byte-exact); `brushFalloff`, `clickBoost`, `brushRunner`, `clickFront`; untouched fast-path; 7×7 (`-3..3`) `gaussSpatial * gaussRange` bilateral loop; range coring (`core`); bass sheen; wet-edge brush ring; coverage alpha.
MECHANISM INTERROGATION:
  tactic 6 (use the history the shader already owns): `dataTextureA` already stores painted colour + coverage alpha every frame while `dataTextureC` is never read — so painted smoothness vanishes the instant the cursor moves instead of behaving like paint!
  tactic 1 (deepen the kernel): `gaussRange` currently inspects scalar `luma` (`sLuma - centerLuma`) only, so isoluminant colour edges (e.g. red vs green at equal luma) and foreground depth silhouettes blur across boundaries.
ADD (2 native ideas):
  1. Persistent drying paint canvas in C (§12.2C Drying) — reads exact `dataTextureC` (linear painted RGB + coverage alpha) with exponential drying decay scaled by `Effect Strength`, so bilateral brush strokes remain painted on the image and slowly dry back; completely dry untouched pixels still take the fast early-out.
  2. Joint chroma-opponent & depth-silhouette range weight — augments `cored` luma range difference inside the existing 7×7 loop with opponent-chroma distance and `readDepthTexture` step delta so isoluminant colour edges and depth boundaries stay sharp.
FORBID: adding a 4th JSON slider, adding a spring cursor, double-tonemapping `dataTextureC` through ACES every frame.
A PACKING: linear painted RGB + brush coverage alpha in `A` (read back via exact `dataTextureC` for drying strokes); `aces()` applied once on `writeTexture`.
```

---

## 8. gen-prismatic-serpent-river

```
SHADER: gen-prismatic-serpent-river
IDENTITY: finite, head-to-tail tapered chromatic serpents with scales, glowing eyes, and prismatic fins slithering across lanes in a flowing river, steered by mouse drag and shedding chromatic rings on click.
KEEP VERBATIM: Serpent Count, Flow Speed, Body Scale, Iridescence; mouse drag vortex (`dragTangent * dragMask`); `lanes`, `speed`, `slither`, finite `bodyU / girth / presence`; per-channel R/G/B `dispersion` (`bodyRGB`); `headEye` + `eyes`, `scales`, `wake`, `prismFins`, `riverCurrent`, `clickShed`; `palette(hue)`; advected `historyLoadUV`; ACES display RGBA.
MECHANISM INTERROGATION:
  tactic 3 & 7 (promote an intermediate / signed orientation): `laneY - slither` is the signed cross-body coordinate, immediately flattened with `abs(laneY - slither)` — keeping its sign defines a 3D cylindrical cross-section normal from dorsal spine to flanks and bends flat scale bars into overlapping V-chevrons.
  tactic 1 (deepen the existing motif): the shader is titled *braided* creatures, yet each serpent is confined strictly to its own 1D horizontal `lane`; pairing adjacent strands with an alternating over/under `zOrder` crossing wave lets serpents weave across lanes with real over/under occlusion and contact shadow.
ADD (2 native ideas):
  1. Over/under braided strand crossings — evaluates a counter-phased companion strand weaving across the lane boundary with sinusoidal `zOrder` so strands pass over and cast soft contact shadows onto under-passing serpents (also reflected in `writeDepthTexture`).
  2. Cylindrical body normal, chevron scales & Fresnel flank sheen (§12.2F) — uses the signed transverse offset `(laneY - slither)` to curve `scalePhase` into imbricated V-chevrons along the spine and add grazing Fresnel–Schlick iridescence along the 3D serpent flanks.
FORBID: a spring cursor, replacing `palette()` or finite serpent anatomy, raymarching a different creature.
A PACKING: ACES display RGBA (unchanged), read back via `historyLoadUV` as advected river trail.
```

---

## 9. aurora-rift-2

```
SHADER: aurora-rift-2
IDENTITY: four parallax layers of magnetically folded oxygen (green/red) and nitrogen (blue/violet) auroral curtains composited with Beer–Lambert transmittance over the source image, bent by the pointer and ionized by clicks.
KEEP VERBATIM: Intensity, Speed, Depth Weight, Turbulence; 4-layer parallax loop with `fbm3` `lowField`/`highField` and `magneticFold`; cursor `pointerBend` + held boost; click `ionization` fronts; oxygen/nitrogen spectral colours; volumetric `transmittance` + `opticalDepth`; `historyAt` C persistence; ACES display RGBA; `sourceDepth` write.
MECHANISM INTERROGATION:
  tactic 2 (physics one step further): a real auroral curtain is strongly asymmetric vertically — precipitating electrons stop abruptly at the ~100 km lower border (`uv.y > centerY`), forming a sharp bright bottom edge fringed with fast $\text{N}_2^+$ violet-pink, then glow 557.7 nm green in the lower belly and taper slowly upward (`uv.y < centerY`) into diffuse 630.0 nm high-altitude red rays; currently `ribbon` is a symmetric Gaussian and `altitude` depends only on `centerY` rather than `uv.y - centerY`.
  tactic 3 (promote an intermediate): `curtainCoordinate` is accumulated across all 4 layers on lines 92 & 115 and *never used*, while `magneticFold`'s spatial derivative (`cos(...)`) identifies where the thin curtain folds tangentially along the line of sight (limb brightening), and `depthWeight` only scales alpha rather than occluding curtains behind foreground `sourceDepth` silhouettes.
ADD (2 native ideas):
  1. Asymmetric electron stopping-edge & vertical ray spectrum — shapes each curtain with a crisp lower stopping border and a tall upward ray tail (`uv.y < centerY`), mapping intra-curtain vertical offset to $\text{N}_2^+$ magenta-violet lower fringe → 557.7 nm oxygen green core → 630.0 nm high-altitude red ray tips.
  2. Tangential fold pleat brightening & foreground depth sky-mask — boosts optical path thickness where `magneticFold` turns tangent to the sightline, and uses `Depth Weight` + the previously unused `curtainCoordinate` to occlude curtains behind near `sourceDepth` silhouettes while casting soft auroral sky-glow onto foreground edges.
FORBID: a spring cursor, IQ rainbow palette, changing A/C packing.
A PACKING: ACES display RGBA (unchanged), read back via exact `historyAt` for curtain persistence.
```

---

## 10. gen-synaptic-void-weaver

```
SHADER: gen-synaptic-void-weaver
IDENTITY: 80-step raymarched 3D folded dark-matter tube network (`abs(p) - 1.0`, `rot3D`, `smin`) with specular obsidian skin, travelling cyan/magenta bioluminescent action-potential pulses, volumetric glow, and mouse gravity well.
KEEP VERBATIM: Glow Intensity, Fractal Iterations, Tendril Thickness, Rotation Speed (and their exact ranges/mappings); `rot3D`, `smin`, folded `length(p.xy) - thickness` IFS loop; mouse gravity well; 80-step marcher (`t <= 10.0`); dark obsidian `base_color` + specular + cyan/magenta `emissive * pulse`; volumetric `glow`; deep purple void background.
MECHANISM INTERROGATION:
  tactic 3 (promote an intermediate): `map()` computes `smin(d, tube, 0.5)` inside the `iterations` loop and returns hardcoded `vec2<f32>(d, 1.0)`, throwing away `.y`; the `smin` blend factor `h * (1.0 - h)` and minimum axis proximity inside that exact loop identify where tendrils fuse into synaptic soma junctions!
  tactic 1 (deepen the kernel): hit shading uses a single unoccluded directional light, leaving deep fractal folds flat; 5-tap SDF ambient occlusion along `n` carves out the abyssal depth of the neural web, while `dataTextureA` currently writes dead `vec4(0.0)` instead of retaining a refractory firing trail in `C`.
ADD (2 native ideas):
  1. Synaptic soma junctions & orbit-trap firing in `map().y` (§12.2E Orbit trap) — accumulates `smin` junction fusion and origin-axis orbit trap in `map().y` inside the existing `iterations` loop, swelling tendril intersections into organic soma bulbs where cyan/magenta/gold synaptic bursts fire (triggered further by click depolarization waves and `mids`).
  2. Fractal crevice SDF ambient occlusion (§12.2E Step-count AO) & refractory C afterglow — evaluates 5-tap `ao` along the surface normal on hit to darken deep dark-matter folds, replaces Reinhard+gamma with `acesToneMap` + semantic alpha, and stores ACES display RGBA in `A` so `dataTextureC` contributes a subtle neural refractory trail instead of unused `vec4(0.0)`.
FORBID: a spring cursor, replacing the folded tube IFS with a different fractal, writing `vec4(0.0)` to `dataTextureA` or `1.0` alpha.
A PACKING: ACES display RGBA (replaces dead `vec4(0.0)` write; read back from exact `dataTextureC` as synaptic refractory afterglow).
```
