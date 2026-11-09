# BRIEFS — Fork D (sonnet/batch-24): data-stream-spectral, vaporwave-horizon-prismatic, audio-voronoi-gabor

Written BEFORE any WGSL edit. HEAD = origin/main c37e2fb0 + prelude commit 7d29bf79 (token-identical to the pre-migration shaders). HEAD renders: scratchpad/forkD/*_head_*.png.

## HEAD verification (what I actually saw / derived)

| shader | HEAD finding | evidence |
|---|---|---|
| data-stream-spectral | spring is dead: `extraBuffer[138]>0.5` false every frame ⇒ `mousePos == rawMouse` (HEAD already behaves as raw cursor, bit-identical to what I will ship). `fftStrip = plasmaBuffer[1..8].x` is always 0 ⇒ the "FFT band tinting" never ran. A.a = display alpha copy, C.a never read. | code + audio-0 render equals audio-0.4 render except bass/mids/treble terms |
| vaporwave-horizon-prismatic | `gridV += time*gridSpeed*heldBoost` ⇒ pressing the button shifts the scroll phase by `0.5·time·gridSpeed` (≈72 grid units at t=100, gridSpeed 1.45 ⇒ half a cell, and the speed is ×1.5 afterwards); sun also pops to 1.5× radius in one frame. Grid lines are aliased near the horizon (cyan speckle band, visible in HEAD 192/576 renders). Fog `mix(fog, floor, 1-fogDensity*0.85)` is *transmittance-shaped* (strong in the near floor, none at the horizon) — kept, identity of the look; noted as open item. The photo is mirrored but the **sun is not** (sun is synthesised in the sky branch only). | vap_head_{idle,held}_T{2,100}.png |
| audio-voronoi-gabor | (1) audio is not audio: `extraBuffer[idx*4]` (not an audio source) with an always-on `sin(time*8)` beat fallback ⇒ at audio 0 the image strobes and cells flash white (a0_T2 vs a0_T3 differ completely; meanL 0.425→0.354, stdL 0.279→0.18). (2) `textureStrength` is unnormalised (Gabor sums are O(1–10)): `mix(color, color*gaborColor, textureStrength*gaborInfluence*0.3)` extrapolates (t>1), and the per-pixel seed shift `gaborStrength*0.3` can exceed a whole cell ⇒ nearest-seed search leaves its 3×3 window ⇒ speckle around strong edges (visible dotted noise around the discs). (3) Gabor bank = 4 orientations × 81 taps = 324 filtered loads + 324 exp + 324 cos per pixel (HEAD 170–200 ms at 192 px quiet machine; 420–710 ms under today's load). (4) Final colour only clamped 0..2, no ACES; A never written. (5) `cellCenter` / `dist` of the second seed unused. | vor_head_a0_T2/T3, code |

## RESCUES (separate from ideas; default look changes are expected and stated in NOTES)

### data-stream-spectral
- **R1 dead spring → raw cursor, honestly.** Remove the extraBuffer spring block and its comments ("spring mouse [133..138]" claim). Bit-identical to HEAD's actual behaviour (HEAD already used the raw cursor every frame).
- **R2 dead per-strip FFT bins → live 3-band spectral tilt.** `fftStrip` was always 0. Replace with a tilt across strip position: bass on the left strips, mids centre, treble right (`u=(stripIdx+0.5)/numStrips`, triangular weights over plasmaBuffer[0].xyz). At audio 0 identical to HEAD (fftStrip was 0).

### vaporwave-horizon-prismatic
- **R1 held scroll-phase jump.** Scroll phase becomes an integrated state (A texels (0,0)/(1,0), sentinel scheme, `fract(phase)` stored, `fract(time)` stored) so rate = `gridSpeed·(1+0.5·heldSmooth)`; `heldSmooth` eases 0→1 in ~0.15 s. Default look (idle) identical in distribution to HEAD (a scrolling grid at `gridSpeed`); scrubbing the Grid Speed slider no longer teleports the grid either. History read masked on the two state texels. sunRadius uses `heldSmooth` too so the sun grows instead of popping.

### audio-voronoi-gabor
- **R1 audio source.** `plasmaBuffer[0].xyz` (clamped) replaces extraBuffer + sin beat. Silence = bands 0 ⇒ no strobing, no white cells, no treble sparkle. `audio_reactivity` stays the audio gain.
- **R2 idle life.** Cells must still live at zero audio: a slow per-cell breathing floor (`idle = (0.22, 0.14, 0)` × slow LFO, no treble) feeds cell wander/displacement only (never the colour/sparkle terms); real audio overrides via `max`. Documented: at silence the picture is a photo with breathing cells, lit membranes and Gabor tint — not a strobe.
- **R3 bounded Gabor strength.** `texStr = clamp(textureStrength/…,0,1)`-style normalisation for the `mix` factor and a ≤0.35-cell cap on the per-pixel seed shift so the 3×3 search stays valid. (Exact constants set from measured stats, in NOTES.)
- **R4 display.** ACES on display RGB (clamp ≥0 first), A = display RGBA written, depth pass-through kept.
- **R5 perf.** Shared tap grid: 81 luma loads once; Gaussian is rotation-invariant (σ equal on both axes) ⇒ separable table `ge[|d|]`; the four sinusoids reduce to three small tables (`cos(2πf·x)`, `cos(2πf·(x±y)/√2)`) ⇒ ~81 loads + 43 cos + 5 exp instead of 324/324/324. Bit-compatible with HEAD's response (same freq 0.15, σ 2.5, 2σ²+0.001, radius 4).

## Idea Cards

### data-stream-spectral
```
SHADER: data-stream-spectral
IDENTITY: the photo recast as vertical data-rain strips — every strip scrolls the image vertically at its own rate, strip%4 picks a spectral band (wide warm blur / mid green / tight cool / edge-difference), bright head packets race down the strips, clicks shear them.
KEEP VERBATIM: speed→flow rate, density→strip count, turbulence→cursor/click x-shear, glow→digital tint mix + bright-cell flashes + alpha; fp128 flow phase; strip hash/rand; the four band kernels + tints; head packet; bright-cell flash; click wake; band-3 negative values clamped before ACES; ACES; semantic alpha; A = display RGB.
MECHANISM INTERROGATION:
  tactic 1 (deepen kernel): strips already decode the image into bands; the next-better stream model is a stream that can *stall* — real data streams latch into a degraded state and recover with hysteresis, not per-frame flicker.
  tactic 2 (physics one step further): a lossy stream shows dropout: a burst that blanks data and recovers exponentially behind its leading edge, in the data's own coordinate (it scrolls with the content).
  tactic 3 (promote intermediate): `rand`/`stripIdx` already exist per strip: they key the lock drive and the burst epoch; `packet` already marks the head and is not reused.
  tactic 6 (history): A.a is a display-alpha copy that no one reads (C.a unused) ⇒ one free latch bit per pixel, constant down a strip, without new bindings or state texels.
ADD:
  1. Schmitt-trigger stall lock (§12.2B): per-strip drive = slow value noise (+bass) vs hi 0.72 / lo 0.50; latch read from exact C.a, written to A.a. Locked strips stutter-step their scroll at 6 steps/s and hold full digital tint — a stalled stream with hysteresis, not flicker. Native: it is the strip's own scroll + tint, gated.
  2. Dropout bursts (§12.2B): per strip/epoch hash fires a burst (probability rises with treble); in the strip's image-space coordinate the data is blanked with an exponential tail behind a white leading edge, so the burst scrolls with the content. Native: it blanks the stream the effect already draws.
FORMULA ADMISSION: both rows are in the distortion/glitch table (this shader *is* a stream glitch); both consume per-strip quantities/history the file already owns (stripIdx, rand, flow phase, C.a); deleting either leaves exactly this effect; neither alone is "rain strips" (additive).
FORBID: springs (R1 removes the dead one), ripple overlays beyond the existing click wake, IQ palettes, new params, a second tear system, per-bin FFT.
A PACKING: A.rgb = ACES display RGB (unchanged); A.a = strip lock latch (HEAD wrote display alpha there; C.a was never read — documented). writeTexture alpha unchanged.
```

### vaporwave-horizon-prismatic
```
SHADER: vaporwave-horizon-prismatic
IDENTITY: synthwave horizon — striped sunset sun on the horizon, neon perspective grid floor that mirrors the photo through a 4-band Cauchy reflection, near-floor fog, CRT scanlines and phosphor persistence; horizon follows cursor Y, floor bends with cursor X.
KEEP VERBATIM: sky gradient + striped sun + glow; perspective grid math (zDepth, gridU/gridV, curve, line width law); 4-band Cauchy reflection loop; neon cyan/magenta colours; near-floor fog law; ripple offset/glow; 0.06 history persistence; scanline; ACES; params (Grid Speed, Glow Intensity, Grid Scale, Warp Amount); alpha model.
MECHANISM INTERROGATION:
  tactic 1 (kernel): the grid is evaluated as an un-filtered `smoothstep` at one point ⇒ aliasing; the next-better operator is the same lines filtered by the pixel footprint in grid space.
  tactic 2 (physics): a mirror floor reflects *everything above it*, including the sun; HEAD reflects only the photo. Rough wet-floor reflections of a point source break into horizontal glitter rows.
  tactic 3 (promote intermediate): `reflY`/`dy`/`zDepth` are already computed for the Cauchy reflection ⇒ the mirrored sun disc and the footprint are one subtraction/derivative away.
  tactic 8 (energy): neon lines on a CRT bloom: light leaves the line core and lands in the halo — total conserved. HEAD adds glow by only multiplying the line colour.
ADD:
  1. Perspective-filtered grid: analytic pixel footprint `fw` in grid units (∂gridV/∂y = −K·zDepth², ∂gridU/∂x = K·zDepth …); line coverage widened by fw and amplitude ×min(1, 2·lw/fw) so far lines fade to their mean density (a faint horizon haze) instead of aliasing speckle.
  2. Sun reflection on the mirror floor: the striped half-disc re-evaluated at the mirrored point (`reflY`), with horizontal glitter-row shimmer (rows displaced by `sin(dy·k − t)`) and a narrow glitter path extending toward the viewer; follows `heldSmooth` sun radius.
  3. Energy-conserving phosphor bloom (§12.2F): grid colour mixed with its 8-tap blur (`out = src·(1−k) + blur·k`, k≈0.4) so the halo is paid for by the core — evaluated analytically (grid is a function of uv), no history needed.
FORMULA ADMISSION: rows F (Energy-conserving bloom; budget allows vaporwave) + tactic-derived 1, 2; all consume quantities already computed (dy, zDepth, reflY, sun params, grid mask); deletion test OK both ways; no new Cauchy (4-band already present), no spring/ripple overlay.
FORBID: new Cauchy, springs, IQ palettes, particle sparkles, changing the sky/sun look, changing the fog direction (identity), new params.
A PACKING: ACES display RGBA (unchanged) + state texels A(0,0)=(fract scrollPhase, heldSmooth, 0, 1), A(1,0)=(fract lastTime, 0, 0, 0.7371) — pixels there lose only their phosphor read (masked), not their output.
```

### audio-voronoi-gabor
```
SHADER: audio-voronoi-gabor
IDENTITY: the photo displaced through Voronoi cells whose centres and displacement directions are steered by a 4-orientation Gabor analysis of the photo itself and driven by audio; cursor gravity + click pulse; cell edges glow with the mids.
KEEP VERBATIM: 4 params + roles (cell_count, audio_reactivity = audio gain, displacement, gabor_influence); Gabor bank (freq 0.15, σ 2.5, radius 4, four orientations) and dominantAngle/textureStrength definitions; Voronoi F1/F2 over 3×3 with audio wander + Gabor seed rotation; displacement direction law (hash angle + dominantAngle·influence); cursor gravity/click pulse; Gabor colour map and per-cell frequency colours; depth modulation; alpha model.
MECHANISM INTERROGATION:
  tactic 1 (kernel): the bank's four sinusoids share one Gaussian ⇒ one tap grid + three tables (R5) — same operator, cheaper; the saving funds the ideas.
  tactic 3 (promote intermediate): the loop computes F2 and the second seed but only the F2−F1 distance is used; the second seed gives the membrane *tangent* (perp(p2−p1)) for free; and the nearest seed's base position is a stable per-cell anchor.
  tactic 7 (direction): the Gabor bank outputs an orientation; HEAD uses it only per pixel. The membrane has an orientation too — compare the two.
  tactic 2 (physics): a cell wall is a ridge; a ridge is lit differently depending on how its tangent faces the light/grain.
ADD:
  1. Grain-lit cell membranes: `rid = 1−smoothstep(0,w,F2−F1)`; ridge slope direction = normalize(p2−p1); shade = rid_slope · dot(slopeDir, (cos θ, sin θ)) with θ = dominantAngle ⇒ walls facing the texture grain brighten, walls opposite darken (embossed walls lit from the grain). Scales with the existing gabor_influence.
  2. Rigid cell translation: displacement direction uses the Gabor orientation sampled at the cell's own seed (second bank evaluation on the shared tap grid at the seed's uv) instead of the per-pixel `dominantAngle`, so each cell slides as one plate and tears only at its membrane (HEAD tears inside cells ⇒ the speckle).
FORMULA ADMISSION: tactic-derived (no §12.2 row needed); both consume F1/F2/seed/dominantAngle already in the file; deleting either leaves exactly this effect; the membrane lighting and rigid plates are unusable on any other family.
FORBID: replacing Voronoi/Gabor, springs, ripple fronts, IQ palettes (the gaborColor cosine map is HEAD's and stays), new params.
A PACKING: display RGBA (ACES) — HEAD never wrote A; C is not read.
```
