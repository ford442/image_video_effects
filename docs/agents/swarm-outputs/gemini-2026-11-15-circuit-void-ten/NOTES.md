# Notes — gemini/circuit-void-ten (2026-11-15)

Idea cards and §12.1 mechanism interrogations were written first in `BRIEFS.md`. Saved `params` are byte-exact across all ten definitions. Six pasted binding headers were migrated first via `python3 scripts/migrate_to_prelude.py --files ...` (`circuit-breaker`, `double-exposure-hdr`, `double-exposure-zoom`, `magma-fissure`, `gen-prismatic-serpent-river`, `aurora-rift-2`); that header swap is infrastructure and is not counted as an idea.

No new spring was added anywhere. `voxel-depth-sort` retains its existing spring in `extraBuffer[133..138]`.

**§12.2 formulae used (each appears once across the ten files):**
- `circuit-breaker`: Schmitt-trigger lock (§12.2B)
- `aerogel-smoke`: Vorticity confinement (§12.2D); Beer–Lambert spectral extinction (§12.2F)
- `double-exposure-hdr`: Halation (§12.2A)
- `double-exposure-zoom`: Cauchy dispersion (§12.2F)
- `magma-fissure`: Isotropic 9-point Laplacian (§12.2D)
- `cross-conv-mouse-bilateral`: Drying (§12.2C)
- `gen-prismatic-serpent-river`: Fresnel–Schlick (§12.2F)
- `gen-synaptic-void-weaver`: Orbit trap (§12.2E); Step-count AO (§12.2E)

---

## circuit-breaker

Kept: Grid Scale, Overload, Jitter, Edge Threshold; aspect-corrected mouse influence + bass boost; `gridUV / gridID / gridLine`; 10% node hash; UV jitter; 4-tap luma gradient & `edgeThreshold`; green-to-cyan circuit/overload colour mix; treble node flash; scanline.
In the diff: annular via pads & 45°-quantized edge-routed copper traces (`// ── Idea 1`) turn square node cells into copper rings with drill holes and route `(edgeX, edgeY)` into 45° bus tracks with travelling signal pulses. Schmitt-trigger breaker latch (`// ── Idea 2`, §12.2B) latches overloaded cells open in `A.a`/`C.a`, charring open traces to dark bronze while firing a cyan-white contact arc on trip onset. Added catalog ACES on guarded non-negative RGB.
A packing: ACES display RGB in `A.rgb` + Schmitt-trigger breaker trip bit in `A.a` (read from exact `dataTextureC`). `writeTexture` carries ACES RGB + semantic circuit/edge/overload alpha.

## aerogel-smoke

Kept: Density, Blue Scatter, Light Intensity, Background Visibility; raw `[density, energy, velocity.xy]` packing; `phaseHG`; ambient + micro value-noise seed; curl driver; hover light, held plume, click shell/core plumes; volumetric depth blend.
In the diff: sub-pixel bilinear exact-load advection & vorticity confinement (`// ── Idea 1`, §12.2D) replace `round(velocityPixels)` grid-sticking and restore fine curling silica wisps from neighbour velocity curls. Dichroic Rayleigh Beer–Lambert extinction (`// ── Idea 2`, §12.2F) makes optical transmittance wavelength-selective via `Blue Scatter`, warming backlit background silhouettes to amber while scattered aerogel stays sky-blue.
A packing: raw `[density, scattering energy, velocity.x, velocity.y]` in A/C (unchanged; ACES on `writeTexture` only).

## double-exposure-hdr

Kept: Zoom Level, Rotation, Opacity, Saturation; mouse-pivoted `rotate2d` + `zoom` second plate; screen blend baseline + saturation mix; `overlapKnee`; 12-tap dual-plate bloom loop; held mouse glow; click flashes; `toneMapACES`.
In the diff: latent shadow-silhouette emulsion keying (`// ── Idea 3`) boosts Plate 2 print-through inside Plate 1's unexposed shadow reserve (`1.0 - smoothstep(0.16, 0.82, luma1)`) while yielding near D-max highlights. Emulsion base halation & shoulder core bleach (`// ── Idea 4`, §12.2A) accumulates warm red-amber film-base bounce from the outer ring (`ringIdx >= 2`) of the existing 12-tap loop and bleaches clipped overlap cores toward warm ivory before ACES.
A packing: ACES display RGBA (unchanged). C is unread.

## voxel-depth-sort

Kept: Block Size, Extrusion, BG Darken, Block Gap; existing mouse spring in `extraBuffer[133..138]` driving `isoRot` and `isoTilt`; click lift waves; guarded `fftVoice` + `bass`; depth-shifted block sample; `ao`, `rim`, `spectral`, `sss`, `aces_tonemap`; `depthOut`.
In the diff: extruded isometric X/Y voxel side walls (`// ── Idea 1`) sweep a 3D rectangular pillar shaft between base and shifted cap along `(isoRot, isoTilt) * column * extrusion`, shading East/West and North/South faces distinctly. Physical column settle (`// ── Idea 2 (part a)`) eases `column` against `C.x`, and upslope neighbour height comparison (`// ── Idea 2 (part b)`) casts proportional step-shadows onto shorter adjacent blocks. ACES now maps the composed HDR voxel output cleanly.
A packing: raw voxel fields `(settledColumn, topMask, depthConf, finalAlpha)` matching HEAD's layout; `C.x` is read as previous settled column height. ACES on `writeTexture` only.

## double-exposure-zoom

Kept: Rotation, Zoom Level, Edge Fade, Audio Reactivity; exponential `zoom`, depth parallax, registration `drift`, aspect-correct rotation around `mouse`; `highlightKey` + screen/soft-light `matte`; guarded `filmResponse` + `acesToneMap`; warm `lightLeak` + `vignette`; `dataTextureC` trail.
In the diff: radial zoom-rack streak & Cauchy focal dispersion (`// ── Idea 3`, §12.2F) replace the static diagonal CA nudge with a 3-tap radial shutter-zoom blur from `mouse` scaled by `cauchyScale` and zoom excursion. Sprocket-frame `edgeMask` gate & warm film-rebate border (`// ── Idea 4`) wire the already-computed `edgeMask` into Plate 2's exposure weight so clamped out-of-frame borders fade cleanly instead of smearing, accented by a subtle amber rebate line at `edgeDist ≈ 0.008`.
A packing: ACES display RGBA (unchanged), read back from exact `dataTextureC` for temporal trail.

## magma-fissure

Kept: Cooling Rate, Fissure Width, Heat Haze, Brush Size; raw `[heat, 0.0, 0.0, 1.0]` packing; `magmaPalette`; held branching brush; click fracture shells; noise `branching`; `crack` and `crust` masks; ACES on `writeTexture`.
In the diff: isotropic 9-point thermal stencil (`// ── Idea 1`, §12.2D) adds the four diagonal `heatAt` taps to eliminate axial crack bias and lifts heat haze buoyantly upward (`-y`) with subtle R/B refractive split. Stefan–Boltzmann $T^4$ cooling & fractured slag-crust plates (`// ── Idea 2`) accelerate cooling on exposed mid-heat crust and split the solidifying crust along `(flow, perpFlow)` into dark basalt plates veined with glowing ember seams.
A packing: raw `[heat, 0.0, 0.0, 1.0]` in A/C (unchanged; ACES on `writeTexture` only).

## cross-conv-mouse-bilateral

Kept: Brush Size, Edge Preservation, Effect Strength (all 3 saved params byte-exact); `brushFalloff`, `clickBoost`, `brushRunner`, `clickFront`; untouched fast-path; 7×7 bilateral loop; range coring; sheen; wet-edge brush ring; coverage alpha.
In the diff: persistent drying paint canvas in C (`// ── Idea 3`, §12.2C Drying) retains linear painted bilateral RGB and exponentially decaying coverage alpha in `dataTextureA`/`dataTextureC` so brush strokes linger as painted strokes on the photo before gently drying away (pixels with zero live brush and dried canvas still take the O(1) fast path without running the 7×7 loop). Joint chroma-opponent & depth-silhouette range weight (`// ── Idea 4`) adds opponent-chroma distance and `readDepthTexture` step delta into `cored` so isoluminant colour edges and object silhouettes stay sharp.
A packing: linear painted RGB + brush coverage alpha in A/C (avoids multi-frame ACES re-compression); `aces()` applied once on `writeTexture`.

## gen-prismatic-serpent-river

Kept: Serpent Count, Flow Speed, Body Scale, Iridescence; mouse drag vortex; `lanes`, `speed`, `slither`, finite `bodyU / girth / presence`; per-channel R/G/B `dispersion`; `headEye` + `eyes`, `wake`, `prismFins`, `riverCurrent`, `clickShed`; `palette(hue)`; `historyLoadUV`; ACES display RGBA.
In the diff: over/under braided companion strand (`// ── Idea 3`) weaves a counter-phased serpent across each lane with sinusoidal `primaryOver` topological ordering, contact shadows on the under-passing strand, and braided depth relief. Cylindrical spine normal, chevron scales & Fresnel flank sheen (`// ── Idea 4`, §12.2F) preserve the sign of `laneY - slither` to bend scale rows into V-chevrons from spine to belly and light grazing flanks with Fresnel–Schlick iridescence.
A packing: ACES display RGBA (unchanged), read back via `historyLoadUV` as colour history.

## aurora-rift-2

Kept: Intensity, Speed, Depth Weight, Turbulence; 4-layer parallax loop with `fbm3` and `magneticFold`; cursor `pointerBend` + held boost; click `ionization` fronts; oxygen/nitrogen colours; volumetric `transmittance` + `opticalDepth`; `historyAt` C persistence; ACES display RGBA; `sourceDepth` write.
In the diff: asymmetric electron stopping-edge & vertical ray spectrum (`// ── Idea 1`) shapes each curtain with a sharp lower stopping border fringed by $\text{N}_2^+$ magenta-violet, a bright 557.7 nm green belly, and a tall upward-tapering 630.0 nm crimson ray tail (`uv.y < centerY`). Tangential fold-pleat brightening & foreground depth occlusion (`// ── Idea 2`) spikes optical density where `cos(foldPhase)` approaches a tangent sightline and uses `Depth Weight` + the previously unused `curtainCoordinate` to mask curtains behind foreground `sourceDepth` silhouettes with soft horizon bounce.
A packing: ACES display RGBA (unchanged), read back via exact `historyAt`.

## gen-synaptic-void-weaver

Kept: Glow Intensity, Fractal Iterations, Tendril Thickness, Rotation Speed (exact ranges and mappings); `rot3D`, `smin`, folded `abs(p) - 1.0` `length(p.xy)` tube IFS; mouse gravity well (guarded and branchless); 80-step raymarcher; obsidian `base_color` + `spec` + cyan/magenta `emissive * pulse`; volumetric `glow`; deep purple void background.
In the diff: synaptic soma junctions & orbit-trap veins (`// ── Idea 1`, §12.2E Orbit trap) replace `map()`'s unused `1.0` return with accumulated `smin` junction fusion and `p.xz` orbit-trap proximity inside the existing `iterations` loop, swelling intersections into soma bulbs where action-potential pulses and click depolarization waves flare. 5-tap fractal SDF ambient occlusion & synaptic refractory C afterglow (`// ── Idea 2`, §12.2E Step-count AO) sculpt deep dark-matter crevices on hit and replace the dead `vec4(0.0)` `dataTextureA` write + Reinhard/gamma with ACES display RGBA + semantic alpha and decayed `dataTextureC` trail.
A packing: ACES display RGBA (read back from exact `dataTextureC` as synaptic refractory trail).
