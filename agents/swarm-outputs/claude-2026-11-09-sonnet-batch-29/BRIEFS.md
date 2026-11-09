# sonnet/batch-29 — Idea Cards (written BEFORE any idea edit to WGSL)

Theme (already lives in the files): glass / iridescence / kaleidoscope / optical-wave shaders — a VCR reveal, a selective-colour mask, a smoke-advection wind tunnel, a prismatic glass tunnel, a mirror-wedge kaleidoscope, an Apollonian inversion gasket, a lens-tile glass wall, a crepuscular-ray thin film, a BZ excitable medium and a Kuwahara paint filter.
10 catalog ids, 10 WGSL files, one JSON each. Contract: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §9, §12). Batch date for headers: **2026-11-09**.

Infrastructure done first, in its own commit, before any idea work: 7 of the 10 files pasted the 13-binding header; they were migrated with `scripts/migrate_to_prelude.py --naga` (header-only, V1–V5 proofs passed). **No `Upgraded:` bump for that.**

Engine facts re-verified in this repo (not copied from a previous batch):
- `src/renderer/webgpu/audioDepth.ts::writeExtraBuffer` re-uploads the whole 256-float `extraBuffer` every frame (`[0..2]` audio, `[4]` historyHead, `[5..132]` FFT, **everything else zero**). So the `[133..138]` springs in `aero-chromatics`, `chroma-depth-tunnel-prismatic`, `gen-apollonian-gasket` never persist (their "initialised" flag reads 0 every frame → they behave as the raw cursor, with a same-dispatch write/read race on top). Persistent state for those three goes into **A texel (0,0)** (rescue **R1**: `A(0,0) = (x, y, 7, fract(time))`, every pixel reads the same C texel, only (0,0) stores it, every read of C that can touch (0,0) is masked) — the scheme already shipped in `cyber-magnifier.wgsl`.
- Audio is `plasmaBuffer[0].xyz`; `plasmaBuffer[1..]` is not audio (floor bug in `aero-chromatics`, rescue **R2**).
- A is `rgba16float` on most real tiers → a stored position resolves to ~0.0005 near 1.0; the glide is first-order so it is dead-zone tolerant.
- Never multiply `time` by an audio value (`time*(13+bass*5)`): the phase jumps by `time·Δaudio` every time audio moves → strobing. Audio goes into amplitude; `time` stays alone (rescue **R-phase**, only where HEAD does it).

Tactics (§12.1): T1 deepen the kernel · T2 physics one step further · T3 promote an intermediate · T5 name the device artifact · T6 use the history the shader already owns · T7 direction not magnitude. Idea numbers continue each file's own numbering so a coordinator can grep `// ── Idea n`.

Row ledger (§12.4 de-dup, each §12.2 row on ≤ 2 files): VCR dropout bursts (B) 1 · Halation-free grain Selwyn (A) 1 · Structure tensor (A) 1 · Cauchy (F) 1 · Henyey–Greenstein (F) 1 · Airy disc (F) 1 · Isotropic 9-pt Laplacian (D) 1 · Brown–Conrady none · Fresnel none (luminescent already owns its own) · Step-AO none. Nothing repeats.

---
## 1. static-reveal — artistic, 181 lines, Upgraded 2026-09-21 (Ideas: vertical-hold roll; multipath ghost)
```
SHADER: static-reveal
IDENTITY: a TV that lost signal — snow, chroma noise and tracking bands cover the picture; the brush re-acquires lock, and a brushed area decays back to static.
KEEP VERBATIM: 4 params (Regrowth Speed → decay, Brush Size → radius, Static Intensity (+treble) → snow, Noise Scale); depth-scaled mask decay stored in C.a/A.a; tracking band + hHold; snow / perlin chroma noise; acqFlash; vignette tint; vertical-hold roll + blanking bar; multipath ghost; R/B tracking shift; ACES; alpha.
INTERROGATION: T5 a technician names VCR artifacts: tracking (HEAD), vertical hold (HEAD), ghosting (HEAD), **head-switching noise** at the foot of the field, **tape dropouts**, chroma delay. Head-switch and dropouts are not present. T3 `mask` and `unlocked = 1 − smoothstep(mask)` already exist; both new artifacts can be gated by them so a fully brushed picture stays clean. T6 C.a (the lock) is already history; it needs no extra state.
ADD:
  1. Head-switching noise — in the bottom ~7 % of the field the horizontal sync is torn: horizontal shear growing toward the bottom edge (added to `dUV` so snow and video take it), a bright snowy head-switch line at the switching point; fades with the lock.
  2. Tape dropouts (§12.2B "Dropout bursts") — oxide shedding prints short white horizontal streaks with an exponential tail: per scanline cell, hash on (line, 6 Hz event window), start x per line, `exp(−x·λ)` tail, smooth envelope over each window so it never pops; amplitude rides Static Intensity; gated by `(1 − mask)`.
FORBID: springs, click shockwaves, IQ palette, any new param, any change to the mask packing or the roll/ghost maths.
A PACKING: display RGB + reveal mask in alpha (HEAD's, unchanged; C.a read back as the mask).
ROWS: Dropout bursts (B).
```

## 2. selective-color — interactive-mouse, 181 lines, Upgraded 2026-10-16 (Ideas: hue window; mask contour)
```
SHADER: selective-color
IDENTITY: a photo desaturated everywhere except organic Voronoi / fbm / polar-sector / SDF-star-hex islands (+ click ripple reveals) that keep the colour under the pointer, outlined by a dark mask contour.
KEEP VERBATIM: 4 params (Radius, Edge Softness, Desat. Strength, Mask Feather); all six mask generators and their max-blend; `chromaticSplit` at the boundary; depth-Sobel edge tint; the hue window concept and the contour; ACES; alpha.
INTERROGATION: T1 HEAD's hue window is `length(color.rgb − key)` — an RGB distance, so a shadow and a highlight of the same hue are "different colours" and a single noisy texel decides the key. A real selective-colour tool targets a hue *and* saturation range in a chroma plane. T2/T5 a B&W print is a film stock: it has grain (density-weighted), and the colour islands are digital-clean; HEAD's desaturated field is perfectly smooth, so nothing separates "removed colour" from "photographed in mono". T3 `gray` is already computed.
ADD:
  3. Chroma-plane hue + saturation window — `cosSim(chroma(pixel), chroma(key))` with chroma = rgb − luma, gated by pixel chroma magnitude, key = 5-tap cross average around the pointer; luminance independent; a neutral key falls back to HEAD's RGB distance so grey pointers still behave.
  4. Mono-stock grain in the desaturated field (§12.2A "Density-weighted grain"): σ(L)=√(L(1−L)), 24 fps cadence (the native place for frame-rate grain), amplitude on the *removed-colour* weight `(1 − combinedMask)·desatStrength` so the islands stay clean.
FORBID: halation, spring, extra masks, a different mask library, IQ palette, any new param.
A PACKING: ACES display RGBA (HEAD's).
ROWS: Density-weighted grain (A).
```

## 3. aero-chromatics — simulation, 179 lines, header from 2026-05-31 (never carried an `Ideas:` line)
```
SHADER: aero-chromatics
IDENTITY: video smoke — bright pixels are light "smoke", advected away from a wind source (the pointer) with R/G/B back-traced at slightly different speeds, decaying history trail, click gust puffs, injected back from the live frame.
KEEP VERBATIM: 4 params (Wind Force, Smoke Decay, Chromatic Split, Source Intensity); luma-scaled velocity `(baseWind + mouseWind)·luma·2`; radial mouse repulsion + upward drift; click gusts over `u.ripples`; chromatic advection (`offsetR/G/B`); `mix(history·decay, frame, sourceMix·luma)`; luma/depth alpha; A = raw smoke trail RGBA (HEAD never tone-mapped the trail; no ACES added — would be a feedback loop on a tone curve).
INTERROGATION: T7 the wind is a magnitude field scaled by luma; the *orientation* of the picture's own structure never touches it — real smoke cannot cross a dark/heavy object, it slides along its outline. T2 a fan or blower does not push purely radially: it imparts swirl, so the outflow is a spiral, not a star. T6 history is read through a *filtering sampler* on a feedback texture; the contract and the (0,0) mask need exact loads.
ADD:
  1. Edge-tangent flow — ∇luma of the live frame (4 taps) gives the object-edge normal; the component of the velocity along it is removed in proportion to edge strength, so smoke streams along silhouettes instead of through them.
  2. Spiral outflow — the pointer wind gains a tangential component (`perp(mouseDir)`) in the same falloff and the same Wind Force scaling, so the repulsion curls into spiral arms.
RESCUES (reported separately, not ideas): R1 the sprung wind source's state (`extraBuffer[133..137]`) never persisted → eased raw cursor lives in A(0,0) (first-order glide, rate 8 ≈ HEAD's critically-damped ω), C(0,0) masked in the history read, manual exact-bilinear `textureLoad` replaces the filtering sampler on C. R2 `bass` was `plasmaBuffer[1].x` and the band flutter `plasmaBuffer[2..8].x` (not audio) → `plasmaBuffer[0].xyz` mapped across the 8 bands.
FORBID: ACES on the trail, IQ palette, ripple shockwave stamps (click gusts already exist), Gray-Scott, a new solver, any new param.
A PACKING: raw smoke colour + alpha; texel (0,0) = (glide.xy, 7, fract(time)) — one pixel of trail lost, masked on read.
ROWS: none (both ideas are the file's own wind vocabulary).
```

## 4. chroma-depth-tunnel-prismatic — advanced-hybrid, 179 lines, no `Ideas:` line (JSON already claimed `upgraded-rgba` — tag-without-ideas)
```
SHADER: chroma-depth-tunnel-prismatic
IDENTITY: the photo wrapped on a polar tunnel (angle, 1/radius) viewed through dispersive glass — four Cauchy-IOR wavelength taps with per-band absorption, spectral helix, axial packets, click fronts, centre fog, bass throat.
KEEP VERBATIM: 4 params (Tunnel Speed, Ring Density, Chromatic Spread, Center Fade) incl. their multi-uses (glassCurvature, cauchyB, glassThickness, spectralSat); polar mapping; `cauchyIOR` + `refractUV` + `wavelengthToRGB` four-band sum; absorption; packets, helix, click fronts, fog, throat; 0.08 C persistence; ACES; alpha.
INTERROGATION: T2 the glass is a pipe of stacked rings (`Ring Density`): the joints between rings are bevels, and a bevel disperses. HEAD wraps with `fract()` and the joint is invisible. T7 the tunnel flies along v; dispersion is only spatial (refractUV); a flying prism also smears its colours *along the flight direction* (each band sees a different depth) — HEAD's bands all sample the same v. T3 `wrappedUV` per band already exists inside the loop; the ring phase `fract(v)` is free there.
ADD:
  1. Ring-joint dispersive rim — inside the existing 4-band loop, a thin bevel highlight at each ring boundary computed from that band's own `fract(refractedUV.y)`, so the rim splits into a rainbow for free (Cauchy offsets already differ per band). Weighted by the band's spectral colour and `spectralSat`.
  2. Chromatic flight lag — each band samples the tunnel at its own depth, `v − (i − 1.5)·lag·|speed|`: at rest there is none, at speed the spectrum smears along the tunnel axis (a prismatic wake).
  3. Depth-integrated Beer–Lambert — the absorption path grows toward the vanishing point (light from far down the pipe crossed more glass), so distant rings warm instead of only fading to black.
RESCUES: R1 the "critically damped spring cursor" (`extraBuffer[133..138]`) never persisted → cursor glide in A(0,0), C(0,0) masked in the persistence read. R-phase `speed` carried `(1 + bass·0.45)` and the packets `time·(13+bass·5)` / `time·(9+mids·6)` → phase jumps of `time·Δaudio` every beat (strobe). Audio moves into amplitude (packet gain, throat, alpha); `time` stays alone.
FORBID: new params, springs beyond R1, a second tunnel, IQ palette, changing the four-wavelength sum.
A PACKING: ACES display RGBA (HEAD's); texel (0,0) = (glide.xy, 7, fract(time)).
ROWS: Beer–Lambert (F) — also existing on luminescent-glass-tiles (HEAD idea there), Cauchy stays as HEAD's.
```

## 5. fractal-kaleidoscope — distortion, 179 lines, Upgraded 2026-10-05 (Ideas: nested chambers; reflection loss; integer wedge crossfade)
```
SHADER: fractal-kaleidoscope
IDENTITY: a mirror-wedge kaleidoscope of the photo — animated segment count crossfaded between integer folds, nested sub-chambers, per-bounce reflection loss, facet seams, HSV slick, held-drag pivot, click rings.
KEEP VERBATIM: 4 params (Intensity, Speed, Scale, Detail); `wedgeFold` + `chamberChain` + integer crossfade; reflectionLoss; `sampleSplit`; seam / conveyor / click / slick terms; folded-uv feedback with 0.26 mix; ACES; alpha = mirror-path transmission; depth write.
INTERROGATION: T3 `ch.seam` and `ch.bounces` are computed per chamber and used for brightness only. T2 in a real kaleidoscope the mirror edge is a glass edge — it disperses; and every extra bounce lengthens the optical path of the reflected copy, which is *further from the object cell and out of focus*, so reflections soften with bounce count. HEAD dims them (loss) but keeps them razor-sharp.
ADD:
  4. Seam-weighted dispersion — `sampleSplit` offset scales with the facet seam strength of that branch, so prismatic fringing gathers on the mirror seams.
  5. Per-bounce defocus — a 4-tap diamond softening whose radius grows with the branch's bounce count (clamped at 6), blended in by the same count; the first wedge stays crisp, deep reflections go soft.
FORBID: lens-flare ghosts, springs, new IQ/HSV overlay, any new param, touching the fold / crossfade maths.
A PACKING: ACES display RGBA, alpha = mirror-path transmission (HEAD's).
ROWS: none (both consume `seam` / `bounces` that already exist).
```

## 6. gen-apollonian-gasket — generative, 179 lines, Upgraded 2026-10-11 (Ideas: six — rims, curvature tint, stipple, kisses, interior wash, soddy spark)
```
SHADER: gen-apollonian-gasket
IDENTITY: a five-circle seed inverted through itself (up to 10 generations), spinning, with the pointer as an extra inversion circle — gasket glow, rims, curvature hue, stipple, tangent kisses.
KEEP VERBATIM: 4 params (Recursion Depth, Inversion Intensity, Circle Size, Rainbow Aberration); the five seed circles; the inversion loop + pointer inversion; every existing colour term; temporal feedback 0.05; aberration; A written before ACES; single ACES; alpha; depth.
INTERROGATION: T1 `minDist` is measured in the *inverted* plane, so its glow width changes with the local inversion scale; the proper distance estimate for an inversion group divides by the accumulated derivative (|d q/d p| = r²/|p−c|² per inversion). That gives a constant-screen-width line at *every* generation — the filigree the file is named after. T3 `invCount` is thrown into hue and ring frequency but never into *time*: generations are simultaneous. T2 a gasket is built generation by generation; light can arrive generation by generation.
ADD:
  7. Conformal hairlines — accumulate the inversion derivative (`scale *= r²/l2`, clamped, plus the spin matrix's own complex scale) and draw `1 − smoothstep(0, 1.6 px, minDist/scale)` as a constant-width gold line over every nested copy of every seed circle.
  8. Generation-delayed pulse — brightness wave `0.5+0.5·sin(t − invCount·δ)^p`: each deeper generation lights a beat after the previous one, so a pulse cascades inward through the nesting; bass raises the amplitude, never the phase.
RESCUE R1: HEAD's spring (`extraBuffer[133..138]`) never persisted → raw cursor; replaced by a first-order glide in A(0,0) (A holds pre-ACES colour; the texel is masked on the history read).
FORBID: changing the seed circle set, a different fractal, new palette, any new param, a second spring.
A PACKING: linear RGB + alpha, pre-ACES (HEAD's: C read as colour); texel (0,0) = (glide.xy, 7, fract(time)).
ROWS: none from §12.2 (E "orbit trap" deliberately not used: `invCount` / `lastK` already feed colour).
```

## 7. luminescent-glass-tiles — distortion, 179 lines, Upgraded 2026-10-04 + 2026-11-01 (Ideas: Fresnel bevel rim; internal luminescence; Beer–Lambert body tint)
```
SHADER: luminescent-glass-tiles
IDENTITY: a wall of glass tiles over the photo — each tile a lens whose magnification follows its own centre luma; the pointer twists and shrinks nearby tiles; Fresnel bevel, trapped-light edge glow, body tint.
KEEP VERBATIM: 4 params (Grid Density, Refraction, Mouse Radius, Mouse Chaos); cell grid, `scale = 1 − luma·refractStr·2`, mouse twist, ripple twist; border darkening; Fresnel/absorption/transmission alpha; the three existing ideas; C persistence 0.07 in display space; depth; ACES.
INTERROGATION: T2 a lens refracts blue harder than red — HEAD's tile images have no dispersion at all (one tap). The Cauchy ratio (§12.2F) is the one physical term the glass is missing, and a lens' fringe grows with lens power `(1 − scale)`. T5 an artefact of hand-made glass block is *hammered* tile: each lens axis is slightly decentred, so neighbouring tiles show different parts of the picture. HEAD's tiles are all perfectly centred.
ADD:
  4. Cauchy lens dispersion — the three channels use `scale_c = 1 − (1 − scale)·cauchyScale(B)` (R<1, G=1, B>1 relative magnification) with B proportional to the existing lens power, so fringes appear only where a tile actually magnifies; G stays HEAD's `finalUV` so dispersion 0 ≡ HEAD.
  5. Hammered decentring — per-tile hash offset of the lens axis, amplitude ∝ lens power `(1 − scale)` (flat tiles stay flat); applied to the sampling only, so the border darkening logic keeps its symmetric reference.
FORBID: a spring (HEAD removed it for a documented race), new IQ palette, replacing Fresnel/luminescence, new params.
A PACKING: ACES display RGBA (HEAD's, C read as colour in display space).
ROWS: Cauchy dispersion (F).
```

## 8. divine-light-iridescence — advanced-hybrid, 178 lines, no header, no `Ideas:`
```
SHADER: divine-light-iridescence
IDENTITY: crepuscular god rays marched toward a light (the pointer) from bright pixels, tinted by a thin-film interference spectrum, with a sun halo, angular beams, treble sparkle and click ripples.
KEEP VERBATIM: 4 params (Ray Intensity, Luma Threshold, Softness, Ray Count); 14-step march with 0.94 decay and luma gate; `beamPattern`; `thinFilmColor` (sampled 400–700 nm) and thickness from ray density + noise; golden/iridescent mix; halo; treble sparkle; click ripple offset; 0.065 history; ACES; alpha; depth passthrough.
INTERROGATION: T2 light scattering in a haze is forward-peaked (Henyey–Greenstein); HEAD's beams only have the per-step decay, so their brightness has no angular lobe around the sun. T2 a *sun* seen through thin cloud wears a corona — diffraction rings around the disc whose radius scales with wavelength (the real "divine light iridescence"); the halo is a single Gaussian and the "sparkle" rings are monochrome and treble-only. T1 the 14 taps start at the pixel with a fixed stride, so every ray shows stepped copies where the image has contrast (stratification is the textbook cure).
ADD:
  1. Sun corona (§12.2F "Airy disc") — per-channel Airy rings `(2·J1(x)/x)²` with `x ∝ d/λ` (R rings wider than B), ring part only (core left to the halo), faded with distance; amplitude on Ray Intensity and bass.
  2. Henyey–Greenstein forward lobe (§12.2F) — beam radiance × `hgN(cosθ)` with `tanθ ∝ distance to the light`, normalised so the far field keeps ~the old mean; rays brighten toward the sun.
  3. Stratified march — a per-pixel interleaved-gradient offset of the 14-tap start so stepping copies dissolve into fine grain (history 0.065 smooths it).
FORBID: new params, springs, a second ray pass, replacing thin-film with an IQ palette, volumetric raymarch.
A PACKING: ACES display RGBA (HEAD's; B unused; depth passthrough).
ROWS: Airy disc (F), Henyey–Greenstein (F).
```

## 9. gen-belousov-zhabotinsky — generative, 178 lines, Upgraded 2026-06-07 / 09-15 / 09-27 (Ideas: refractory tail; pacemaker gradient; phase hue; annihilation cusp)
```
SHADER: gen-belousov-zhabotinsky
IDENTITY: an excitable-medium reaction–diffusion dish (activator a, inhibitor b) seeded with a spiral, painted over the input, with spiral tip glow and ferroin-like blue → violet → red → orange ramp.
KEEP VERBATIM: 4 params (Reaction Rate, Activator Diffusion, Inhibitor Diffusion, Feed Rate); the kinetics `a(1−a²) − b + feed`, `(a − b)/2`; seeding; pacemaker gradient on ε; colour ramp, refractory shading, phase hue, annihilation cusp, spiral-tip glow; mouse seed; ACES + hue-preserve clamp + IGN dither; A = raw (a, b, waveFront, alpha); B = (lapA, lapB, oxidized, front²).
INTERROGATION: T1 the Laplacian is `avg(4 edge neighbours) − centre` — the 5-point stencil, which has an axis bias: BZ spirals on it grow diamond/square wave fronts and align to the grid (the D-table row exists for exactly this). T3 the four neighbours `n/s/e/w` are already loaded and only their Laplacian is used; their *difference* is the activator gradient. T2/T5 BZ waves in a real dish are not seen by their colour alone: they are photographed by refractive-index gradients (Schlieren), the front lights like a relief under side light.
ADD:
  5. Isotropic 9-point Laplacian (§12.2D) — 0.2 edge / 0.05 corner weights (4 extra loads), scaled ×5/6 so the effective diffusion at wave scale is HEAD's, so Da/Db sliders keep their strength; rounder, grid-free fronts. lapA/lapB stored in B remain Laplacians.
  6. Schlieren front relief — `∇a` from the existing n/s/e/w taps, lit from the upper left like the kuwahara impasto; the front is shaded as a refractive-index ridge, warm on the lit side, deep on the lee side.
FORBID: a new reaction (Gray-Scott), replacing the colour ramp, new params, changing A/B packing.
A PACKING: raw sim (newA, newB, waveFront, alpha) in A; (lapA, lapB, oxidized, front²) in B — HEAD's, unchanged; ACES on display only.
ROWS: Isotropic 9-point Laplacian (D).
```

## 10. interactive-kuwahara — interactive-mouse, 177 lines, Upgraded 2026-10-04 (Ideas: generalised variance-weighted blend; impasto ridges; canvas weave)
```
SHADER: interactive-kuwahara
IDENTITY: a four-sector Kuwahara painterly filter whose brush (radius) shrinks to detail under the pointer focus, with saturation boost, impasto lighting, canvas weave and a wet trail.
KEEP VERBATIM: 4 params (Brush Size, Saturation, Focus Radius, Hardness); four box sectors (−r…0 quadrants) with mean/σ; generalised weights `1/(1+σ^8)`; impasto from sector-luma slope; canvas weave; wet runner / packets / click clarity; ACES; C wet-trail mix 0.14; alpha.
INTERROGATION: T1 the four sectors are axis-aligned squares for every pixel — the classic Kuwahara blocky "mosaic" on diagonal edges; the better approximation of the same operator is the anisotropic Kuwahara, whose sectors follow the local edge orientation (A row "structure tensor … oil-paint"). T7 HEAD computes no orientation at all. T3 the sector weights `w_k` are computed and only summed: their *spread* is exactly "how decisively one sector won", i.e. the paint-patch boundary — the place oil/watercolour pools pigment.
ADD:
  4. Structure-tensor sector alignment (§12.2A) — the four sector squares rotate to the local edge orientation, weighted by coherence × gradient energy so flat / noisy areas keep HEAD's axis-aligned sectors; the impasto slope is rotated back into screen space. 9 extra luma taps.
  5. Stroke-edge pigment pooling — `(wmax − wmin)/wmax` from the existing sector weights darkens the pigment where one sector decisively won (paint-patch boundaries), scaled by stylisation so photo-real regions are untouched.
FORBID: a different painter (Gaussian Kuwahara rewrite, 8 sectors), new params, springs, wet-trail change.
A PACKING: ACES display RGBA (HEAD's; C read as colour for the wet trail).
ROWS: Structure tensor (A).
```
