# sonnet/batch-28 — Idea Cards (written BEFORE any WGSL edit)

Theme (already lives in the files): organic / prismatic / voronoi-glass — two swirl presets on one file, a prism feedback loop, a prism compositor, a Möbius helix, a crystal, a faceted glass, a shattering Voronoi, a folded-paper fluid and a starling flock.
10 catalog ids, 9 WGSL families (`generative-psy-swirls` + `psy-swirls` are two JSONs on `generative-psy-swirls.wgsl`; `murmuration` is `murmuration-flock.wgsl` + `murmuration-render.wgsl`).
Contract: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §9, §12). Batch date for headers: **2026-11-09**.
Plumbing already done by the coordinator before any idea work: 8 files migrated to `#include "_prelude.wgsl"` with `scripts/migrate_to_prelude.py` (infrastructure; no `Upgraded:` bump for that).

Engine facts verified in `src/renderer/webgpu/audioDepth.ts` (`writeExtraBuffer`) and used below:
- `extraBuffer[0..255]` is re-uploaded every frame (`[0..2]` bass/mid/treble, `[4]` historyHead, `[5..132]` FFT, everything else **zero**). `[133..138]` springs/prev-pointer stashes in these files NEVER persist: `extraBuffer[137/138]` read 0 every frame. Persistent state must live in an A texel — **R1**: `A(0,0) = (x, y, GLIDE_MARK = 7, fract(time))`, every pixel reads the same C texel, only (0,0) stores it; every read of C at (0,0) as colour/field is masked (same scheme as `cyber-magnifier.wgsl`).
- A is `rgba16float` on most real tiers (0.0005 resolution near 1.0) → small gates/dead-zones on anything derived from a stored absolute position.
- Never multiply `time` by an audio/pointer-speed value (`time*(0.5+mids)`): the phase jumps by `time·Δaudio` radians (hundreds) every time the value changes → strobing. Audio goes into amplitude or into a spatially-varying term; time stays alone. **R-phase** below.

Tactics (§12.1): T1 deepen the kernel · T2 physics one step further · T3 promote an intermediate · T5 name the device artifact · T6 use the history the shader already owns. "R" = rescue (a HEAD bug fixed, reported separately from ideas). Rows = §12.2 rows used.

---
## 1. generative-psy-swirls + psy-swirls (one WGSL; two JSONs) — generative, 207 lines, Upgraded 2026-08-03
```
SHADER: generative-psy-swirls (+ psy-swirls: same file, url shaders/generative-psy-swirls.wgsl)
IDENTITY: stacked polar swirl arms (sin(3·swirl) × distance rings) in HSV rainbow, fbm-domain-warped, R/G/B layer stagger, pointer-offset layer centres, click swirl rings.
KEEP VERBATIM: 4 params and roles (twist, layers 2–7, frequency/warp scale, depth-reduction; zoom_params.xyzw — psy-swirls JSON labels them swirl_speed/layer_count/rainbow_speed/twist_intensity but maps the same four slots, so BOTH JSONs stay byte-exact); layeredSwirlLayer arm × ring product; fbm warp; per-layer mids hue fan; R/G/B layer stagger; click ring; 0.04 trail mix and 1.2 feedback clamp; ACES(color·1.1); alpha / relief depth.
INTERROGATION: T3 `swirl` (a + d·twist·freq − t/2) is computed per layer and only feeds sin(3·swirl); the polar angle never reaches the hue, so the psy-swirls description's "rainbow HSV cycles from polar angles" is concentric rings only. T2 a real vortex has a finite core (Rankine): HEAD's centre is a pure atan2 singularity where every arm pinches into a pinwheel point. T6 trail mix is 4% (prev·0.92·0.04) — kept, the history is not the idea here.
ADD:
  1. Arm-wound hue — hue += (a + d·twist·freq)/TAU: the spectrum winds with the arms. It is continuous across the atan2 seam (a jumps by TAU → hue by exactly 1), time drift of hue unchanged.
  2. Eye-wall cores — each layer's swirl centre gets a calm eye (val ∝ smoothstep of d) ringed by a bright eye-wall in the layer's own hue: Rankine core instead of a pinwheel singularity; core radius shrinks with twist so the Twist slider still reads as "tighter vortex".
R1 glide (HEAD "spring" omega 8 is dead: extraBuffer[137]=0 every frame → raw cursor) · mask C(0,0) in the trail read.
FORBID: image sampling, new params, IQ palette (hsv2rgb stays), ripple shockwave stamp, plasma/galaxy motifs, changing arm × ring product.
A PACKING: raw trail colour (clamp 1.2, pre-ACES — HEAD's, C read as colour); texel (0,0) = (glide.xy, 7, fract(time)).
ROWS: none (both ideas are the file's own vortex vocabulary).
```

## 2. prismatic-feedback-loop — interactive-mouse, 196 lines, Upgraded 2026-07-30 / batch 68
```
SHADER: prismatic-feedback-loop
IDENTITY: the photo split into rotated R/B prism taps (G undeviated), blended into a raw-accumulated temporal history (A, ACES only on display), with glow on bright trails, held-pointer warp and click prism bursts.
KEEP VERBATIM: 4 params (Feedback mix, Blur Radius → prism spread, Glow Intensity, Chromatic Spread → fan angle); `accumulativeAlpha` raw accumulation (ACCUM_RATE .5) in A; rot2 drift 0.1; depth attenuation; held warp; click bursts (RIPPLE_LIFE); glow = trailLum²; ACES on display; alpha formula; depth passthrough.
INTERROGATION: T6/T2 a feedback loop feeds the *output back through the optics*; HEAD samples the history at the same pixel (pure temporal lowpass) — the prism is only ever applied to the live image, so the "loop" never compounds. T2 a real prism disperses blue harder than red (Cauchy n(λ)=A+B/λ²); HEAD's ±chromaFan is symmetric. T3 `feedbackMix` is already the loop gain.
ADD:
  1. Prism echo — the history is read back through the same prism: R from C(uv + k·rOffset), B from C(uv − k·bOffset), G at uv (exact textureLoad, manual bilinear), k = 0.3·feedbackMix so the Feedback slider keeps its role and at Feedback 0 the frozen frame is exactly HEAD's freeze. Fringes compound frame by frame into rainbow tunnels; blended = convex mix so values stay in [0,1].
  2. Cauchy weights on the three taps (§12.2F "Cauchy dispersion"): R×0.887, G 0, B×1.197 for B=0.2 (`cauchyScale`) on the live taps AND the echo — blue refracts harder than red.
R1 glide with velocity proxy = raw − glide for the held-warp `springVel` term (HEAD spring omega 10 dead) · mask C(0,0).
FORBID: neon edge pop, IQ palette, new params, ACES on the stored state, blur kernel.
A PACKING: raw accumulated RGBA (HEAD's, C read as colour+alpha); texel (0,0) = (glide.xy, 7, fract(time)).
ROWS: Cauchy dispersion (F) — also used by voronoi-faceted-glass; the two files differ on the other idea.
```

## 3. interactive-origami-coupled — advanced-hybrid, 191 lines, Upgraded 2026-09-12 (Ideas: capillary pooling; Kármán street)
```
SHADER: interactive-origami-coupled
IDENTITY: three-direction abs(sin) paper creases around the pointer over a viscous velocity/density field the pointer drags; fluid tints the photo, creases bend it and are lit.
KEEP VERBATIM: 4 params (fold scale / depth, viscosity, vortex strength); crease height + finite-difference grad; semi-Lagrangian advection (2 px), viscosity decay; pointer drag + vortexDir; click outward push; edge damping; capillary pooling; Kármán street along crease 1; fluid tint; crease lighting; speckle specular; ACES; alpha; A = raw (vx, vy, vorticity, density).
INTERROGATION: T3 the stored vorticity z is `vel.x − vel.y` — not a curl (A packing lies). The real curl and its gradient are one 4-tap read of C away. T2 a grid solver numerically damps exactly the small swirls the "Vortex Strength" slider is named for; the textbook cure is vorticity confinement. T3 `grad` + `dens` are both in hand: dense fluid on a slope slides downhill.
RESCUE R1: `prevMouse` lives in extraBuffer[133..134]/[138], re-uploaded zero every frame → prevMouse = mousePos → mouseVel = 0 → pointer drag, vortexDir and the Kármán street (all ∝ mouseVel/mouseSpeed) have NEVER run. Prev pointer moves to A(0,0) (marker 7); fluid loads at (0,0) masked; a small dead-zone absorbs f16 quantisation. R-phase: Kármán phase was `time·(4 + mouseSpeed·10)` — becomes `time·4` with speed in amplitude (it would have strobed the moment the rescue made it live).
ADD:
  1. Vorticity confinement (§12.2D, this file only) — real curl ω from the four C neighbours, ∇|ω| from their stored z, f = ε·(N.y, −N.x)·ω, ε ∝ Vortex Strength; A.z becomes the true curl (packing now honest).
  2. Crease gutters — dense fluid drains down the crease slope: vel −= grad·dens·k inside the fold zone, so pooled fluid (existing capillary pooling) also *flows* into the valleys it collects in.
FORBID: new params, springs, Gray-Scott, changing the fold function, IQ palette.
A PACKING: raw (vx, vy, curl, density) — z now honest; texel (0,0) = (prevMouse.xy, 7, fract(time)), (0,0) is also an (edge-damped) fluid cell, masked as zero on read.
ROWS: Vorticity confinement (D).
```

## 4. voronoi-chaos — distortion, 188 lines, Upgraded 2026-09-11 (Ideas: bass-snap shard jitter; held-pointer trail smear)
```
SHADER: voronoi-chaos
IDENTITY: flat-colour Voronoi mosaic of the photo whose seed points swim, get pushed round the pointer and snap on bass; per-cell spectral ridges, centre dots, click ring, held-pointer trails.
KEEP VERBATIM: 4 params (cell scale, chaos, color mix, dot size); F1 search with swimming + mouse repulsion + bass snap; ridge / spectral colour; dots; mouse highlight; held-trail smear from C (display RGBA); alpha; ACES.
INTERROGATION: T1 the search keeps F1 only; the Voronoi quantity that draws shards is F2−F1 (distance to the border). Without it, adjacent tiles of similar colour merge — the "chaos" has no cracks. T2 chaos = shattering: a click is an impact, but HEAD only paints a ring on top of the colours; the cells themselves do not move.
ADD:
  1. Fracture seams (§12.2 Worley F2−F1, with voronoi-faceted-glass's HEAD bevel the only other user) — track the second-nearest distance in the existing loop; dark crack core + thin lit lip, width grows with Chaos.
  2. Impact shatter — each ripple is a front; seed points inside the front's band get a one-shot jolt along their own hash direction (in the loop, per neighbour point), so a click physically tumbles the shards instead of just tinting them.
R2 (HEAD comment promises it, code does not): the tile colour is sampled at the UNperturbed seed (`time*0.5`, no mouse, no snap) while the geometry uses the perturbed one → pushed shards show the picture from where they used to be. Sample at the actual `m_point`. R-phase: `time*(0.5+mids)` and `-time*(3+bass*5)` phase jumps → audio into amplitude / spatial frequency.
FORBID: new params, springs, IQ palette beyond the existing spectral, neon scanlines.
A PACKING: display RGBA history (HEAD's, ACES output, C read as colour).
```

## 5. spec-bicubic-crystal — distortion, 187 lines (Ideas: wedge facets; Fresnel seams; facet-normal dispersion)
```
SHADER: spec-bicubic-crystal
IDENTITY: square crystal cells, each a tilted glass wedge resampled with Catmull-Rom bicubic, R/B split along the facet tilt, Fresnel-bright seams, centre glow, pointer bulge, click ripples.
KEEP VERBATIM: 4 params; cell grid, wedge offset, facetEdge, mouse influence, ripple shocks; Catmull-Rom 16-tap sampler; chromaDir split; edgeGlow; seam / Fresnel; C persistence 0.07 in display space; alpha; ACES.
INTERROGATION: T2 a glass wedge is thickest on one side; HEAD's wedge is only a displacement — it never uses thickness, so a thick crystal and a thin one look alike. T2 a faceted crystal shows an internal reflection of the scene (a twin image) at oblique facets. T3 `wedge` (= cellLocal·tiltDir) IS the thickness coordinate; `seamF` is already the Fresnel factor.
ADD:
  1. Beer–Lambert wedge absorption (§12.2F) — transmittance exp(−σ·t) with thickness t from `wedge`: the thick side of every facet tints cool, the thin side stays clear; σ rides the existing Distortion slider's magnitude.
  2. Internal-reflection twin — one bilinear tap mirrored across the facet's tilt axis, mixed by the existing Schlick `seamF` plus tilt steepness: oblique facets show a faint mirrored second image (bicubic stays on the primary image).
Floor: clamp colour ≥ 0 before ACES (Catmull-Rom undershoot).
FORBID: new params, IQ palette, ripple restyle, a second noise warp.
A PACKING: ACES display RGBA (HEAD's; C read as display colour).
ROWS: Beer–Lambert (F).
```

## 6. murmuration — simulation, `murmuration-flock.wgsl` (186) + `murmuration-render.wgsl` (92), sim ring + hash, A/C = rgb emission + crowd
```
SHADER: murmuration (flock + render)
IDENTITY: 65k boids (separation / alignment / cohesion through a spatial hash, wind, predator pointer) stamped as heading-tinted crowd patches; render blurs/fades the field and draws a dark flock silhouette with iridescent rim against a dusk sky.
KEEP VERBATIM: 4 params + roles (cohesion, alignment, perception, trail length); hash window, MAX_VISITS, sep/ali/coh weights, wind, predator peel/stoop, vmin/vmax, stamp patch (crowd in .a, heading hue), field diffusion + keep, silhouette thresholds (0.30–0.75), chromatic wake taps, sunset sky; A/C packing .rgb emission .a energy; ACES; alpha 1.
INTERROGATION: T2 Reynolds' original boids see through a forward cone; real starlings have a rear blind zone. HEAD is omni-directional, so neighbours behind pull a bird back as hard as the ones ahead and flocks relax into round blobs instead of ribbons. T3 the render pass already computes `grad` of the crowd (rim only) but lights every edge equally — the sky has a sun glow low in the frame (uv.y→1 in `sunset`), so edges facing it should catch the light and the far edges stay dark.
ADD:
  1. Forward vision cone (flock pass) — alignment and cohesion neighbours are weighted by smoothstep(−0.35, 0.25, cos angle(d, vel)); separation stays all-round (collision avoidance does not need eyes), crowd statistic keeps the unweighted count.
  2. Sunward rim (render pass) — rim light weighted by the edge normal vs the horizon sun direction: 0.35 + 0.65·max(n·sun, 0); the far side of the flock goes dark against the sky.
FORBID: new params, extra sim state, changing MAX_VISITS / WINDOW, particle trails, new sky.
A PACKING: unchanged. No state, no springs.
```

## 7. gen-prismatic-mobius-helix — generative, 182 lines, Upgraded 2026-09-15 (Ideas: one-sided 4π traveler; orientation-seam spectral current)
```
SHADER: gen-prismatic-mobius-helix
IDENTITY: slice of a stack of rectangular-section Möbius rings (coil count, width, radius), cosine-spectrum thin-film glow on the SDF edge + surface falloff, pointer-orbited camera, 4π traveler and seam current, temporal blend.
KEEP VERBATIM: 4 params; sdMobius / mobiusHelixInfo; edge / surface glow; thinFilm() cosine palette and its hue; helix trail; traveler; seam current; C blend 0.05+mids·0.02; ACES; alpha; depth.
INTERROGATION: T2 the file is called thin-film iridescence but `thinFilm()` is a cosine palette with a fake "view"; a real film's colour comes from interference of thickness × angle. T3 `across` (position over the strip's width) and `normal` are computed in sdMobius and discarded. T3 the SDF gradient is one finite difference away: the glow is symmetric around the surface; a lit bevel needs a direction.
ADD:
  1. Film-thickness fringes (§12.2F thin-film phase — this IS the effect) — δ = 4π·n·d·cosθ/λ with d varying across the strip (`across`, now kept in MobiusInfo) and with the ring index; R(λ)=cos²(δ/2) per channel modulates the palette `film` so interference bands run along the ribbon.
  2. SDF-gradient bevel light (§12.2E curvature/normal lighting) — central difference of the distance field gives the surface direction; the edge glow is lit on the side facing a key light so the flat glow reads as a rounded glassy lip.
R-phase: traveler `time·(0.07+bass·0.015)` and seam wave `time·(3+mids)` jump with audio → time alone, audio into amplitude/width.
FORBID: new params, new creature/fractal, swapping the palette to IQ-only, scanlines.
A PACKING: ACES display RGBA (HEAD's).
ROWS: thin-film phase (F), SDF-gradient lighting (E).
```

## 8. prismatic-3d-compositor — interactive-mouse, 182 lines, Pass 2 of 2 (Batch 22)
```
SHADER: prismatic-3d-compositor
IDENTITY: pass-2 composite of the cloud pass: depth-weighted parallax ghost driven by the pointer, depth-gated volumetric glow with a depth-hued halo, depth-scaled chromatic aberration, click prism flares, 50% mix with the source.
KEEP VERBATIM: 4 params (glow radius, glow intensity, parallax, aberration); parallax + in-bounds mask; 5×5 depth-weighted glow gather + prismTint; aberration direction law + flares; 0.5 videoBlend; feedback blend 0.85−mids·0.25 in A; alpha; depth passthrough.
INTERROGATION: T6 HEAD computes a temporal trail (`feedback`) and writes it to A, but the displayed colour is `finalColor`: the history is write-only — the trail is invisible. A is read back through a filtering-style `textureSampleLevel` (floor violation: must be exact textureLoad). T2 "volumetric" glow with no light direction has no shafts; the pointer is already the scene's active point.
ADD:
  1. Afterglow — the invisible trail becomes visible: out += max(prev − finalColor, 0)·k, depth-weighted (far haze lingers longer). Static scenes: prev ≈ finalColor → no change; motion leaves a prismatic wake. Exact C load.
  2. Cursor light shafts — 4 decaying taps from the pixel toward the pointer through the same bright-threshold/depth weight as the glow gather, tinted by prismTint, so the glow has a direction instead of a square footprint.
Floor: exact C load; over-range soft clip (highlight only, input is already display colour — no ACES double tone-map; say so).
FORBID: new params, a second composite pass, springs (pointer is a plain parallax driver here), IQ palette beyond prismTint.
A PACKING: trail colour (smoothed display RGB, A = composite luminance alpha) — HEAD's, C read as colour.
```

## 9. voronoi-faceted-glass — distortion, 181 lines (Ideas: tilted facets; chamfer bevel; facet glints)
```
SHADER: voronoi-faceted-glass
IDENTITY: stained-glass Voronoi panes that refract the photo (per-pane tilt), chamfered rims with a lit lip, orbiting-light glints, pointer-pushed seeds, ripple distortion.
KEEP VERBATIM: 4 params (Density, Refraction, Shimmer, EdgeSoftness → zoom_params.xyzw); seed swim + pointer push + ripple shocks; tilt, bevel, glint ideas; spectral tint; C persistence 0.08; alpha; ACES.
INTERROGATION: T2 the title says "Prismatic" but the panes only refract — the image is sampled once per pixel, so there is no dispersion at the bevel, where real glass splits colour most. T1 the single tap per pixel means every pane is optically perfect; real panes differ (some clear, some frosted). T3 `bevel`, `tilt`, `outDir` are already computed.
ADD:
  1. Bevel dispersion (§12.2F Cauchy, second user in the batch) — R and B sampled at the pane's sampleUV displaced along outDir/tilt, ∝ bevel (strongest at the rim) with Cauchy weights; G stays.
  2. Frosted panes — hash(cellId) picks ~⅓ of the panes to be frosted: a 4-tap rotated blur whose radius is the pane's frost × the refraction magnitude; clear panes keep HEAD's single tap.
FORBID: new params, thin-film palette, kaleidoscope, changing tilt/bevel/glint maths.
A PACKING: ACES display RGBA (HEAD's).
```
