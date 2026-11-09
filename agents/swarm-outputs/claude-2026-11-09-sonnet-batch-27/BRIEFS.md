# sonnet/batch-27 — Idea Cards (written BEFORE any WGSL edit)

Theme (already lives in the files): optical / lens shaders — a flare, a magnifier, two gravitational / droplet lenses, a prism, a zoom burst, a heat-haze mirage, an ASCII lens, a double exposure, a quantum cloud. 10 shaders, 3 forks + coordinator. Shared rules, engine facts and the R1 cursor-glide rescue: `COMMON.md`.
Tactics (SHADER_UPGRADE_BATCH §12.1): T1 deepen the kernel · T2 physics one step further · T3 promote an intermediate · T6 use the history the shader already owns. Each card answers the ones that apply, in the shader's own nouns.
"R" = rescue (a HEAD bug fixed; reported separately from ideas). "Rows" = §12.2 rows used (budget in COMMON.md).

---
## 1. ascii-lens (fork A) — interactive-mouse, 205 lines, Upgraded 2026-03-22 / 2026-08-02 (no `Ideas:`)
```
SHADER: ascii-lens
IDENTITY: a cursor lens that turns the photo under it into coloured ASCII glyph cells (5 brightness tiers  #  @  +  -  .); the photo is untouched outside; clicks scramble glyphs.
KEEP VERBATIM: 4 params (radius, density → 50–200 cells, line width, brightness bias) and roles; the 5 tiers + thresholds 0.8/0.6/0.4/0.25/0.1 and their glyph shapes; cell-centre colour × charVal; click scramble jitter + RGB split outside; luma-alpha/depth-mix alpha; depth passthrough; "mouse<0 → centre".
INTERROGATION: T1 the tier is decided from ONE tap at the cell centre → aliasing flicker on fine texture and hard contour bands; the better approximation of "brightness of this cell" is a cell mean + ordered dither (what aalib/libcaca do). T2 real ASCII converters also pick DIRECTIONAL glyphs (/ \ | _) where a cell holds an edge. T3 the extra cell taps give the cell gradient for free. T6 n/a (HEAD reads no history).
ADD:
  1. Cell-mean luma + Bayer-ordered tier dither — 5 taps over the cell (centre + 4 at ±0.3 cell), 4×4 Bayer value of the cell index shifts the tier thresholds by ±0.06 → tonal ramps, no contour banding, stable glyphs on texture.
  2. Edge-directed strokes (structure-tensor family, §12.2A, this file only) — gradient (gx,gy) of the cell from the taps; where |g| is high the mid/dark tiers (+ - .) are replaced by a stroke along the edge TANGENT (distance of localUV−0.5 to the line through the centre with direction (−n.y,n.x), width = the existing line-width slider). # and @ stay for bright blocks.
R1 glide (rate 8 = HEAD omega) · R2 dead audio: `bass=plasmaBuffer[1].x` → [0].x; per-cell flicker `plasmaBuffer[1..8]` → `extraBuffer[5+bin]` by cell hash. Idle look preserved (flicker=0 → keep HEAD's literal 0.8·charVal and −0.05 luma bias).
FORBID: IQ palette, CRT phosphor/scanlines/bloom, monochrome-terminal tint, new params, changing the 5 tiers.
A PACKING: display RGBA (unchanged); texel (0,0) = (glide.xy, 7, fract(time)).
ROWS: edge orientation (A1 family).
```

## 2. cyber-magnifier (fork B) — interactive-mouse, 204 lines, 3rd pass (Upgraded 2026-10-04; Ideas: texel grid; sweep-traced Sobel; depth rangefinder arc)
```
SHADER: cyber-magnifier
IDENTITY: a cyan HUD loupe at the cursor — magnified image with CA, digital texel grid at high zoom, scan grid / rings / radar sweep, sweep-traced outlines, depth rangefinder arc, click flares.
KEEP VERBATIM: all of HEAD (params magnification / lens_size / aberration / grid_opacity; A(0,0) glide state with marker 7; texel snap + grid; Sobel trace; rangefinder arc; border; click flares + magnification pulse; hue-preserving clamp; vignette; alpha; A = masks (inLens,border,sweep,alpha)).
INTERROGATION: T1 the magnification mapping `(uv−m)/mag + m` is a pure gnomonic zoom — the next-better approximation of a glass loupe is a 2-term radial (Brown–Conrady): magnification rolls off toward the rim. T2 a rangefinder-equipped optic also focuses: whatever is not at the measured distance goes soft. T3 `centreDepth` (rangefinder) is computed and only draws an arc; |depth − centreDepth| per pixel costs one subtraction. T6 n/a (C masked, A holds masks).
ADD:
  1. Loupe distortion (Brown–Conrady, §12.2B, this file only): r = |(uv−m)·aspect|/radius, s = 1 + k1 r² + k2 r⁴ with k1 ∝ −(mag−1) (barrel roll-off toward the rim; identity at mag=1; clamp s ≥ 0.4), applied to `uvZoomed`; gUV, Sobel taps, texel grid and CA all follow.
  2. Autofocus defocus keyed to the rangefinder — circle of confusion = clamp(|depth(gUV) − centreDepth|·k, 0, 1); lens colour blends to a 4-tap cross blur by CoC, faded out by `pixAmt` (a pixel-view loupe is not defocused). The depth under the lens centre stays sharp, so the arc now has a meaning.
FORBID: more HUD elements, springs, ACES on the photo outside the lens, IQ palette, changing the arc/sweep/grid motifs.
A PACKING: unchanged — masks + texel (0,0) glide state.
ROWS: Brown–Conrady.
```

## 3. multi-fractal-compositor-lens (fork B) — advanced-hybrid, 203 lines, no `Upgraded:`/`Ideas:` (first idea pass)
```
SHADER: multi-fractal-compositor-lens
IDENTITY: four zoom-tunnel layers of the photo (ping-pong sampled, depth-weighted) seen through a gravitational point lens at the cursor, with an Einstein-ring glow, core glow, ripple masses and chromatic aberration.
KEEP VERBATIM: 4 params (lens_mass, ring_glow, ripple_mass, chroma_boost) + their mixes; point-lens deflection form; ripple masses; 4-layer tunnel (layerZoom fract, held spin, flow noise, pingPong); depth-weighted composite; CA mix 0.7; ring/core colours; C persistence 0.08; ACES; alpha formula; `zoom_center` stays the raw cursor.
INTERROGATION: T2 a point-mass lens magnifies AREA, not surface brightness: images near the critical curve brighten (μ = 1/|1−(θE/θ)⁴|) and arcs stretch TANGENTIALLY (μt = 1/(1−(θE/θ)²)); and only sources BEHIND the lens are deflected. HEAD has neither. T3 HEAD's `mass·d/(d²+ε)·0.01` is exactly the point-lens equation with θE² = mass·0.01 — θE is never used; the painted ring sits at sqrt(mass·0.015) ≠ θE, and the deflection is not aspect-corrected (elliptical lens on 16:9, circular painted ring). T1 the 4 layers' `fract` zoom jumps 4×→1× at each wrap → the composite pops. T6 C persistence 0.08 stays.
ADD:
  1. Einstein arcs — μ and μt from the true θE = sqrt(lensMass·0.01): brightness × clamp(μ,1,3) near the critical curve and a 3-tap TANGENTIAL smear of the sampled layer (offset ∝ θE·μt, clamped) blended by an arc mask; the painted ring now sits on the real critical curve.
  2. Foreground bypass — deflection scaled by (1 − smoothstep(0.55,0.8,depth(uv))) (engine depth: near = 1): foreground objects are not lensed; inert when the depth map is flat/zero.
R1 glide for the LENS mouse only (rate ≈ 10; HEAD stiffness 42) · R2 aspect-correct the deflection (t=(uv−m)·aspectVec) and put the ring at θE (default look: ring radius 0.203 → 0.166 at default; document) · R3 zoom-phase pop: weight each layer by sin²(π·phase) (floor 0.02) so the wrap is invisible · mask C(0,0).
FORBID: black-hole accretion disc, new fractal formulae, IQ palette, springs on ripple masses.
A PACKING: ACES display RGBA (unchanged); texel (0,0) = glide state.
ROWS: none (point-lens μ is the file's own physics).
```

## 4. double-exposure (fork C) — interactive-mouse, 200 lines, Upgraded 2026-09-06 (no `Ideas:`; banner lists `fast-motion`)
```
SHADER: double-exposure
IDENTITY: the photo composited with a second rotated / zoomed / warped copy of itself pivoted on the cursor — photographic screen/overlay exposure blend with CA on exposure 2, ghost trails and rotational click shockwaves.
KEEP VERBATIM: 4 params (zoom, rotation, opacity, warp) + mixes; pivot-relative transform; fbm domain warp; CA split on exposure 2; screen/overlay mix 0.35; ripple rotation + flash tint; C ghost trails; ACES; semantic alpha; depth blend; the `voroPattern` interference mask.
INTERROGATION: T2 the second exposure is a LENS projection pivoted on the cursor — an image circle with cos⁴ roll-off; HEAD's layer 2 is full strength to the frame edge so there is no "porthole" and little sense of a second exposure. T6 C is read as ghost trails (weight 0.05–0.25); a real camera held open is a LONG exposure — trails should integrate while the button is held.
ADD:
  1. Image-circle vignette of exposure 2 (cos⁴, §12.2A, this file only) — θ = atan(r_pivot / f) with f ∝ zoomLevel (aspect-corrected r), exposure-2 strength × mix(0.35,1,cos⁴θ): strongest at the pivot, rolling off to the frame edge.
  2. Shutter-open dwell — while the pointer is held the C feedback weight rises toward long-exposure integration (≈0.82), so the rotating exposure-2 smears into trails; release returns to HEAD's weight. No new state (uses the exact C the file already reads).
R1 glide (rate 13 = HEAD omega) for the pivot · R2 dead `binA=plasmaBuffer[3].z`, `binB=plasmaBuffer[7].y` → `extraBuffer[5+bin]` · R3 `time·(0.15+mids·0.2)`: audio scales a growing phase → rotation jumps; use `time·0.15 + mids·0.2·sin(time·0.7)` (identical at mids=0) · R4 mask C(0,0) in `hist` · drop `fast-motion` from banner/JSON.
FORBID: new params, IQ palette swap of the flash, extra ripple stamps, halation/grain/H&D (kept for a photo batch).
A PACKING: ACES display RGBA (unchanged); texel (0,0) = glide state.
ROWS: cos⁴.
```

## 5. anamorphic-flare (coordinator) — interactive-mouse, 199 lines, Upgraded 2026-09-11 (Ideas: threshold-gated highlight streak; blue-line ghost)
```
SHADER: anamorphic-flare
IDENTITY: a light at the cursor produces a cinematic anamorphic flare — horizontal blue streak + blue line, hex ghosts along the optical axis, central glow, rays, starburst and a rainbow halo — gated by the brightness of the source under the cursor.
KEEP VERBATIM: 4 params (width → streak length, intensity, color → dispersion, threshold); threshold-gated streak; blue-line ghost; hex ghost chain geometry + count; centralGlow, rays, starburst, halo; ACES; flare alpha; raw cursor as the light position.
INTERROGATION: T2 anamorphic lenses squeeze the image 2:1, so their ghosts / bokeh are horizontally stretched OVALS — HEAD's ghosts are round hexagons (spherical iris). Real glare also has a power-law tail (I ∝ 1/(r²+r0²)); HEAD's glow is two exponentials that end abruptly. T3 `dispersion`/`edgeFactor` are only multiplied into a tint; the streak's per-channel extent is the quantity the physics varies (red/amber tails longer than the blue-white core). T6 n/a. HEAD is not aspect-corrected: glow/rays/starburst/halo are ellipses on 16:9.
ADD:
  1. Oval anamorphic ghosts — ghost aperture coordinates squeezed ×2 in x before `hexagonAperture`, so ghosts become horizontally stretched hexes.
  2. Power-law glare tail (soft inverse-square, §12.2F, this file only) — `r0²/(d²+r0²)` × a long exp fade added to `centralGlow` in aspect-corrected distance: a faint veiling halo instead of a cut-off.
  3. Per-channel streak extent — hStreak evaluated per channel with length scales (1+0.5·disp, 1, 1−0.25·disp): blue-white core, amber tail, fringe grows along the streak; `spectralDispersion` stays for the ghosts.
R1 aspect-correct the radial terms (glow, rays, starburst, halo, ghost distance); identical at aspect 1.
FORBID: springs / ripples / mouse-down stamps, IQ palette, a second streak system, new params.
A PACKING: ACES display RGBA (unchanged).
ROWS: Soft inverse-square (F). (Lens-flare ghosts row NOT used — ghost geometry stays HEAD's.)
```

## 6. cross-mouse-spec-dispersion-lens (fork A) — interactive-mouse, 194 lines, Upgraded 2026-08-02 (no `Ideas:`)
```
SHADER: cross-mouse-spec-dispersion-lens
IDENTITY: a cursor prism lens — parabolic thickness profile, Cauchy-IOR radial displacement of R and B around a fixed G, rotating normal, click dispersion bursts and a bass rim flare.
KEEP VERBATIM: 4 params (lens radius, dispersion scale, lens strength, rotation speed); Cauchy constants (n0 1.4, B 3000, λ 650/530/460); thickness profile; `angle = t·rot·0.2 + profile·π`; held ×2 dispersion; glow; rim; click ring; alpha; depth passthrough.
INTERROGATION: T1 three wavelengths → at strong dispersion the image splits into three offset RGB copies; a real prism integrates over wavelength (continuous rainbow). T2 a thin lens refracts ∝ the thickness GRADIENT — zero on the optic axis; HEAD applies full strength at r→0 where the normal is `normalize(rotDir+1e-4)` (a centre pinch where every direction is displaced). T3 `iorR−iorG`, `iorB−iorG` are already Cauchy outputs; more λ costs nothing.
ADD:
  1. Continuous spectral integration (Cauchy, §12.2F, row 1/2) — 6 wavelengths (650 … 460, G at 530 undisplaced) each with its own Cauchy IOR displacement, accumulated with an RGB response basis that sums to 1 per channel (white stays white); R and B extremes keep HEAD's maximum fringe extent, the in-between taps fill the gap.
  2. Axis-regularised refraction — displacement amplitude × smoothstep(0, 0.3·R, r): nothing on the optic axis, maximum in the lens annulus; removes the centre pinch, rotation of the normal unchanged.
R1 glide (rate 8 = HEAD omega) · R2 dead treble `plasmaBuffer[6].x/[8].x` → `extraBuffer[5+bin]`.
FORBID: ripple stamps beyond the existing click ring, IQ palette, kaleido folds, new params.
A PACKING: display RGBA (no ACES: the photo passes through; additive glow/rim only); texel (0,0) = glide state.
ROWS: Cauchy dispersion.
```

## 7. heat-haze-mirage (fork C) — image, 191 lines (already prelude), "Batch 60" (no `Upgraded:`/`Ideas:`)
```
SHADER: heat-haze-mirage
IDENTITY: an inferior mirage — rising fbm refraction stronger toward the bottom, dn/dy ray bending, a false-water fold (mirrored sample) past a critical gradient, caustic runners, warm amber grade, a heat source at the cursor.
KEEP VERBATIM: 4 params (heat_intensity, rise_speed, wavy_scale, chroma_shift); fbm displacement; gradient bend; TIR fold + mirrorUV; caustic runners; horizontal chroma shift; warm tint + glow; held widening; click heat bursts; ACES; semantic alpha; depth relief; A = pre-ACES haze accumulation RGBA; B diagnostics.
INTERROGATION: T2 atmospheric refraction is DISPERSIVE and acts along the density gradient, i.e. VERTICALLY (blue image above, red below, green-flash rim at the fold) — HEAD's split is horizontal only; heat shimmer also makes bright points twinkle (scintillation = the intensity counterpart of image dancing). T3 `bend` (vertical ray curvature) is computed and drives the fold; the per-channel vertical offset is ∝ bend. T6 HEAD writes `hazeAcc` (0.85 EMA of pre-ACES colour) to A and NEVER shows it: the documented "temporal haze accumulation" is dead; an exposure integrates shimmer.
ADD:
  1. Vertical atmospheric dispersion at the fold (Cauchy scale, §12.2F, row 2/2) — R/B sampled at ± (cauchyScale−1)·|bend|·k vertically (also on the mirrored sample): coloured fringes where the false water meets the horizon.
  2. Scintillation — highlight texels (luma > ~0.65) twinkle with value noise tied to the displacement-field coordinates (so it correlates with the shimmer), amplitude ∝ heatFactor.
  3. Exposure-integrated shimmer — out = mix(col, hazeAcc.rgb, 0.3·hazeDensity): the dead C history now shows, only in dense-haze regions (clean regions and video input are not ghosted).
R1 glide (rate 3 = HEAD omega; HEAD integrated one 1/60 step from a zeroed state, so the "spring" was the raw cursor) · R2 dead `bandBoost` (`plasmaBuffer[1..8]`) → `extraBuffer[5+bin]` by vertical band · R3 mask C(0,0) in `prev`.
FORBID: neon, IQ palette, new params, touching the fold geometry or the amber grade.
A PACKING: pre-ACES haze accumulation RGBA (unchanged semantics); texel (0,0) = glide state. B diagnostics unchanged.
ROWS: Cauchy dispersion.
```

## 8. interactive-zoom-blur (fork C) — distortion, 189 lines, Upgraded 2026-08-02 / 2026-09-21 (Ideas: depth-occluded streak taps; radial trail advection)
```
SHADER: interactive-zoom-blur
IDENTITY: a radial zoom blur streaming from the cursor — per-channel chromatic streaks, dithered taps, depth attenuation, click pulses, an outward-advected temporal trail.
KEEP VERBATIM: 4 params (strength, chromatic, sampleCount, depthAttenuation); Bayer-dithered tap loop `center + dir·(1+t·strength)`; per-channel spreads; depth-occluded taps; radial trail advection; click strength pulses; effectBlend; alpha; depth passthrough.
INTERROGATION: T2 a zoom burst photographed while panning (a whip-zoom) curves its streaks; HEAD's header promises "spring LAG feeds a motion bonus: fast flicks smear harder" but the spring is dead so the streaks are always perfectly radial. Zoom-burst photographs also show specular points as bright radial streaks, because exposure integrates LIGHT: averaging in display space dims them. T3 the cursor lag vector (raw − glide) is the velocity proxy; luma per tap is already in the accumulator. T6 the trail is read with exact C (keep).
ADD:
  1. Whip-pan zoom burst — each tap's ray centre slides along the cursor lag: `centre_t = center + lag·(0.8·t)`; streaks curve into spirals only while the pointer moves; zero at rest.
  2. Linear-light accumulation — accumulate tap colours as c² (gamma-2 ≈ linear light) and sqrt the sum, so highlights streak rather than average away. Deliberate look change on bright sources, documented with before/after.
R1 glide (rate 10 = HEAD omega) → epicentre `center` and the lag-driven strength bonus (HEAD's `springSpeed`) · R2 dead `fftVoice` (`plasmaBuffer[1..8]`) → `extraBuffer[5+bin]` by ray radius · R3 mask C(0,0) in `prev` (advected coords can land on it).
FORBID: new params, rotation / twirl motifs, IQ palette, ACES on a photo-through filter.
A PACKING: display RGBA (unchanged); texel (0,0) = glide state.
ROWS: none.
```

## 9. interactive-fisheye (fork B) — interactive-mouse, 184 lines, 3rd pass (Upgraded 2026-10-04; Ideas: refraction from the simulated surface; caustic focusing from the height Laplacian)
```
SHADER: interactive-fisheye ("Fluid Lens Dynamics")
IDENTITY: a fluid droplet lens at the cursor — per-pixel height/velocity sim refracting the photo, caustic focusing, meniscus ring, specular/Fresnel sheen, capillary runners and click splashes.
KEEP VERBATIM: 4 params (surface tension, viscosity, mass, splash threshold); droplet_shape + stretch; per-pixel spring to target_h + capillary; refraction from the sim gradient and Laplacian caustics (the two existing ideas); click splash displacement; 1.06/0.94 chroma split; spec / Fresnel / slick colouring; ACES on writeTexture only; A = RAW sim state [h, v, nx, ny]; depth relief.
INTERROGATION: T1 the sim has NO neighbour coupling — every pixel is an independent spring toward an analytic target, so "ripples" are painted functions, not waves; the Laplacian is computed only to brighten caustics. Promote it to a force (damped wave equation) with the isotropic 9-point stencil (the droplet is round; the 5-point stencil gives diamond rings). T2 the refraction `normal.xy·0.12·h` is the small-angle limit of Snell; water is η≈1.33 and the refracted ray bends non-linearly near the steep meniscus. T3 `lap`, the neighbour loads and `normal` already exist. T6 C is read as raw fields (h, v): the history affords wave propagation without changing the packing.
ADD:
  1. Neighbour-coupled capillary waves (damped wave equation + isotropic 9-point Laplacian, §12.2D, this file only) — `accel += κ·lap9(h)/dt²` with κ = c²dt² ≤ 0.25 (stability), clamp v; capillary rings now propagate and ring down; the 3 extra corner loads are exact C.
  2. Snell refraction (§12.2F, this file only) — refracted direction from the existing blended sim normal with η = 1/1.33 replaces the small-angle displacement; calibrated so a weak slope displaces about as HEAD did.
R1 (lag-only) HEAD's `pointer_vel` comes from the last two CLICKS (`ripples[rc−1]`, `ripples[rc−2]`), so droplet stretch tracks click history, not the drag: replace with the cursor lag vector (A texel (0,0) glide; droplet stays at the raw cursor); texel (0,0) is masked in every sim read (treated h=v=0).
FORBID: new sim variables in A (keep [h,v,nx,ny]), Gray-Scott / ferrofluid, IQ palette changes, ACES on stored fields.
A PACKING: RAW sim [h, v, nx, ny] (unchanged); texel (0,0) = glide tracker (documented). Test ≥300 frames at extreme sliders for stability.
ROWS: damped wave, isotropic 9-pt Laplacian, Snell.
```

## 10. quantum-flux (fork A) — interactive-mouse, 182 lines, Upgraded 2026-05-23 / 2026-08-02 (no `Ideas:`)
```
SHADER: quantum-flux
IDENTITY: a probability cloud around the cursor where the photo jitters per channel, splits chromatically, ripples with a radial wave, drifts in hue and gets interference scanlines.
KEEP VERBATIM: 4 params (flux jitter, wave freq, colour drift, flux radius) + audio rides; hash jitter `rand(seed)`; RGB split; radial `wave`; HSV hue drift + `driftMask`; scanlines; click decoherence bursts; alpha formula; depth passthrough.
INTERROGATION: T1 jitter amplitude is spatially flat inside the cloud (only the influence falloff) — a probability density has structure. T2 the radial `wave` already is a standing-wave phase φ = dist·freq·50 − t·5: its nodes are where the uncertainty should vanish (orbital shells); and a quantum system's colour is quantised, but hue drift is continuous. T3 φ is already computed → ψ² for free. T6 n/a.
ADD:
  1. Radial probability shells — jitter amplitude × (0.35 + 1.3·sin²φ) (mean ≈ 1, so default strength is kept): uncertainty piles into antinode shells that travel outward with the wave; the photo is crisp at the nodes.
  2. Quantum-jump hue — the drifted hue is quantised to 6 energy levels with a fast smoothstep snap (`(floor(h·L) + smoothstep(0.78,1,fract(h·L)))/L`): plateau-then-jump hue steps, concentric hue shells via the existing `dist·2` term. Colour-drift slider keeps its role (speed + mask).
R1 glide (rate 9 = HEAD omega) · R2 dead per-sector FFT `plasmaBuffer[1..8]` → `extraBuffer[5+bin]` by angular sector.
FORBID: drawn orbits / particles, IQ palette, new params, ripple stamps beyond the existing click bursts.
A PACKING: display RGBA (unchanged); texel (0,0) = glide state.
ROWS: none.
```
