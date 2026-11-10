# BRIEFS — sonnet/batch-36 (written BEFORE any WGSL edit; HEAD = 75dbf877)

Theme: glitch, spectral, distortion and neon-warp. Ten existing catalog shaders (the user's list, numbers in parentheses were line counts). Passes: first pass = 5 (rgb-ripple-distortion, block-distort-interactive, hybrid-fractal-feedback, blueprint-reveal-guided, data-scanner-gabor — no `Ideas:` line; rgb-ripple/hybrid carry a 2026-05-23 hygiene header only), second/third pass = rgb-distance-split (2 ideas), circular-pixelate (2), glitch-reveal (3), spectral-vortex (3), neon-warp (3). Forks: A = block/reveal glitch (block-distort-interactive, glitch-reveal, circular-pixelate); B = spectral (rgb-ripple-distortion, rgb-distance-split, spectral-vortex); C = scanner/reveal (blueprint-reveal-guided, data-scanner-gabor); D = warp/fractal (neon-warp, hybrid-fractal-feedback).

HEAD defects found while reading are listed per card as **R#** (rescues, not ideas). Everything below is from reading the files; nothing was rendered before the cards were written, so every "visible" claim is a hypothesis the fork must measure (COMMON rule 11).

---

## 1. block-distort-interactive  (fork A)  — first pass
```
SHADER: block-distort-interactive
IDENTITY: the cursor shoves a grid of rigid mosaic tiles away from it (per-tile push, RGB split along the shove), lit by a warm key glow at the pointer, a cool fill glow at tile centres, rim light on tile edges, a bass pulse ring and treble sparkle at grid nodes; premultiplied output.
KEEP VERBATIM: 4 params (Block Size→blockScale 8..72, Push Strength, RGB Split, Radius); rigid per-cell shove (cell-centre influence, direction away from the pointer); treble wobble; per-channel split along the shove direction; gridLine + prism tint; the whole lighting stack (volumetricGlow key, fill glow, rimLight, pulse ring, sparkle, falloff); bloomAlpha; premultiplied output; depth blend.
MECHANISM (tactics 3, 5, 6): a real block codec (JPEG/MPEG macroblock) subsamples chroma per block — the colour comes from the block, the luma stays per pixel (tactic 5: artefact of the real device the "block distort" imitates). The file already writes `influence` to A.r but reads nothing back (tactic 6): one extra piece of continuity is that a pushed tile does not snap back the instant the cursor leaves.
ADD:
  1. Macroblock chroma subsampling (§12.2B "block quantization", 4:2:0 flavour): inside each shoved tile the chroma (colour minus its own luma) is taken from the tile-centre sample and quantised to a few levels, while luma stays per pixel; mix weight = influence. Pushed tiles read as "compressed" blocks.
  2. Elastic recoil (native pointer memory, uses the A.r the file already writes): read C exactly at the tile-centre texel; `latch = max(influence, prev·k)` with k ≈ 0.92–0.95 (relax ~0.4–0.8 s), exactly 0 below an epsilon (rgba16float A must not stall at a denormal). The shove/split/gain use the latched influence so tiles the cursor has left spring back with lag. Tile-constant (every pixel of a tile stores the same value) so C at the tile centre is authoritative.
RESCUES:
  R1 `uv = gid/dims` has no +0.5 (tile assignment shifts half a pixel) → pixel-centre uv.
  R2 no tone-map: key glow + fill + rim + pulse + sparkle are added to the colour then hard-clipped at the write → ACES on display RGB (clamp ≥ 0 first) before the premultiply; report the default-look change (meanL/stdL HEAD→new).
  R3 header (Upgraded/Ideas/A packing); JSON features only what is true (`upgraded-rgba` once ACES lands).
FORBID: springs, click ripples/shockwaves, a second lighting system, IQ palette, new params.
A PACKING: A = (latched influence, gridLine, volGlow, alpha) — a raw per-tile field, C-read at the tile centre (r only); do not ACES it. writeTexture = ACES display, premultiplied (unchanged).
```

## 2. glitch-reveal  (fork A)  — 3 ideas already shipped (2026-10-05)
```
SHADER: glitch-reveal
IDENTITY: a clean circular reveal window onto the photo; outside it blocks jitter/scatter with chroma split, inverted/shifted blocks, horizontal tear bands, datamosh holds from C, a green rim.
KEEP VERBATIM: 4 params (Block Size, Scatter Amount, Reveal Radius, Jitter Speed); all three HEAD ideas (datamosh block hold from exact C, tear bands, block-snapped window edge); mask semantics (0 clean inside, 1 glitched outside); inverted/shifted block recolour; green border/edge glow; ACES on display then C-colour blend; A = display RGB + `.a = 10 + alpha` validity sentinel (C read as colour); depth passthrough.
MECHANISM (tactics 2, 5): HEAD shares ONE `tick = floor(time·speed·(1+mids))` across every block, so every block re-rolls at the same instant — a whole-frame strobe, not a codec (real macroblocks re-key at different frames: intra-refresh staggering). And a real sync tear is not a rigid translation: the shift ramps across the head-switch lines (a sheared parallelogram with an exponential tail).
ADD:
  1. Staggered block re-key (block phase): each block's seed uses its own tick `floor(time·speed·(1+mids) + phase_b)` with `phase_b = hash(gridUV)`, so blocks re-roll one by one in a rolling pattern; Jitter Speed keeps its role (mean re-key rate). The tear-band hash stays on the global tick (rows are a different axis). Measure: fraction of blocks whose seed changes between consecutive frames at default speed (HEAD: all-or-none at tick boundaries).
  2. Sheared head-switch tear (§12.2B "sync-pulse timing"): inside a tear band the horizontal shift ramps with the row position (−½…+½ of `tearShift` across the band, plus a short exponential tail at the band's trailing edge) instead of a rigid shift; bands whose `tearOn` is 0 are unchanged.
RESCUES: R1 verify the C `10+alpha` sentinel survives `A16=1` (spacing at 10..16 is 2⁻⁷); if it does not, say so. No other defect found at HEAD.
FORBID: springs, new pointer systems, VHS dropout / roll costumes, a second datamosh system, IQ palette.
A PACKING: unchanged (display RGB + 10+alpha sentinel).
```

## 3. circular-pixelate  (fork A)  — 2 ideas already shipped (2026-10-16)
```
SHADER: circular-pixelate
IDENTITY: the photo re-imaged through a hex lenslet array: each hex cell is a hex-clipped round lens dome refracting one sample, with chroma, glint, prism rim, grout seam, pointer dilation, click rings, exact-C ghost, Bg Mix.
KEEP VERBATIM: 4 params (Density, Radius, Hardness, Bg Mix); getHex lattice; hex diaphragm (hexBlade) + grout seam (the two shipped ideas); lensNormal refraction; chromatic red/blue taps; glint; prism rim; exact-C history blend; held dilation + click wave; ACES display; A = result (display RGBA, C read as colour); depth passthrough.
MECHANISM (tactics 1, 2): each lenslet takes ONE point sample at (cell centre + refraction): a real lenslet integrates its whole footprint, so at high Density a textured photo shows per-cell speckle (aliasing) instead of the cell's mean colour — the next-better approximation of the same operator (tactic 1). And a real small aperture shows optical vignetting (cat's-eye / lemon bokeh) toward the frame edge where the barrel clips the pupil (tactic 2).
ADD:
  1. Footprint-integrated cell colour: replace the single base tap by a 7-tap rosette (centre + 6 hex neighbours at ≈0.5·apertureRadius, aperture-weighted) so each cell shows its area mean; HEAD's red/blue CA taps stay as a differential about that mean. Budget ≤ +10 loads.
  2. Cat's-eye optical vignetting: a second aperture disc, shifted toward the frame centre by `vig = clamp(r²·k, 0, 0.7)·apertureRadius` (r = distance of the cell from frame centre), intersected with the hex diaphragm (`aperture = min(aperture, aperture2)`), so cells near the corners/edges become lemon-shaped, oriented tangentially; centre cells are exactly HEAD. Measure the % of frame area affected at Density 0.5 and 576 px.
RESCUES: R1 `uv = gid/resolution` has no +0.5 → pixel-centre uv (hex lattice phase). Nothing else broken at HEAD (history and ACES are consistent).
FORBID: springs, extra ripple systems, new IQ palettes beyond the existing `spectrum`, a third grout/seam system, thin-film.
A PACKING: unchanged (display RGBA = result; C read as colour).
```

## 4. rgb-ripple-distortion  (fork B)  — first pass (2026-05-23 hygiene header only)
```
SHADER: rgb-ripple-distortion
IDENTITY: pointer swirl + click ripples drive a damped displacement field (A.rg, ×0.94 per frame) that splits R/G/B and is read as a stress field whose photoelastic (polariscope) fringes tint the picture.
KEEP VERBATIM: 4 params (Frequency→ring spatial frequency, Amplitude, Wave Speed, Color Separation→currently the photoelastic gain `stressOptic`); the displacement feedback; pointer push + swirl; the ripple ring loop (radial sin × exp envelope); stress tensor chain → principal stresses/angle → per-channel retardation → isoclinic × fringePalette; B packing (HEAD owns B: stress, angle, isoclinic); A = (displacement.rg, fringe, stressMag); depth proxy.
MECHANISM (tactics 2, 4, 6): the R/B split is a fixed symmetric ±0.4·chromaShift about green — real dispersion is non-linear (Cauchy: blue bends more than red). Each click is ONE sine ring; real water ripples disperse (long waves outrun short ones), so a click should spread into a train. "Color Separation" is labelled as the RGB split yet only gains the fringe optics.
ADD:
  1. Cauchy dispersion on the channel taps (§12.2F "Cauchy dispersion"): per-channel scale `n(λ)=1+B/λ²` at 650/550/450 nm normalised to green, applied to `chromaShift` so blue spreads more than red; green stays on `uv+displacement`. B large enough that the R/B asymmetry is visible (a ±10 % asymmetry will not be — measure).
  2. Deep-water ripple dispersion (§12.2D "deep-water dispersion"): the ripple term becomes two wave components k₁=freq, k₂≈1.8·freq whose phase speeds differ as c ∝ 1/√k (shorter waves slower), different decay envelopes; a single click spreads into a leading long wave and a trailing short train. Amplitude normalised so the first ring at default equals HEAD's.
RESCUES:
  R1 `fieldAt` samples C with the FILTERING `u_sampler` (rgba32float history) → exact `textureLoad` at the pixel (±1 for the four stress-derivative taps, clamped).
  R2 "Color Separation" does not move the channels → let it ALSO scale `chromaShift` with default 0.5 ⇒ HEAD magnitude (do not change its existing optic role).
  R3 verify the idle look: at zero stress the mix is `mix(base, base·0.35 + photoelastic, 0.35)` ⇒ a ×0.78 darkening at rest. If confirmed, make rest an exact pass-through (scale the mix by stress) and report the default-look change; otherwise leave.
  R4 ACES only if the photoelastic term is allowed to exceed 1; if it stays LDR, say "LDR, no ACES" in the notes.
FORBID: springs, extra pointer systems, IQ palette, holographic scanlines, new params, a third dispersion mechanism.
A PACKING: A = raw displacement field (rg), fringe/10, stressMag — read back as C as a FIELD; do not tone-map it. B unchanged (HEAD-owned).
```

## 5. rgb-distance-split  (fork B)  — 2 ideas already shipped
```
SHADER: rgb-distance-split
IDENTITY: chromatic separation that grows with distance from the cursor (a deadzone around it stays sharp), rotated by Angle Offset, with a directional Blur and Beer–Lambert transmission alpha.
KEEP VERBATIM: 4 params (Split Strength, Angle Offset, Blur Amount, Deadzone); dir/effectFactor/rotSeparation geometry; shipped Idea 1 (7 wavelength taps, k=(λ−550)/100, wavelengthRGB weights, per-channel normalisation); shipped Idea 2 (±1st-order grating ghosts); Beer–Lambert alpha + 15 % tint; ACES; A = display RGBA; depth passthrough.
MECHANISM (tactic 2): a lens with lateral colour also has (a) longitudinal/axial CA — red and blue focus off the green plane, so edges grow a magenta/green defocus halo, and (b) secondary spectrum — dispersion is non-linear in λ, so the per-wavelength offsets are a parabola, not a line (red and blue land on the SAME side of green: the classic purple fringe).
ADD:
  1. Longitudinal CA (native lens physics): per-wavelength isotropic defocus (a small 4-tap disc) with radius ∝ |k|·effectFactor·strength, green (k=0) stays sharp; the Blur slider keeps its directional role. Budget ≤ +16 loads (apply to the |k|≥1 taps, or fewer taps per wavelength); re-time.
  2. Secondary spectrum (non-linear dispersion; second file for the Cauchy-family row): offset = rotSep·(k + c₂·k²) along the same axis; keep the mean R/B spread at HEAD's magnitude at default (normalise), green exactly at 0.
RESCUES: R1 `uv = gid/resolution` has no +0.5 → pixel-centre. R2 `var c` inside the loop shadows the outer `c = cos(angleOffset)` → rename (legal but fragile). Nothing else broken.
FORBID: springs, ripples, prism-flare / holographic costume, a third ghost system, new params.
A PACKING: unchanged (display RGBA, write-only).
```

## 6. spectral-vortex  (fork B)  — 3 ideas already shipped (isophote advection, signed arms, depth shelves)
```
SHADER: spectral-vortex
IDENTITY: the picture's own luminance contours spin up a curl field that persists in A (phase, curl.xy, energy), twists the image, and rotates its hue along signed spectral arms around the pointer.
KEEP VERBATIM: 4 params (Twist Scale, Distortion Step, Color Shift, Curl Amplification); the three shipped ideas; C-state decode (phase, curl, energy) and exact bilerp helper; image-gradient curl; held/click swirl terms; ACES only on writeTexture; A = raw sim state (phase, curl.xy, energy); B unwritten; depth passthrough.
MECHANISM (tactics 1, 3): the pointer swirl is a unit tangent × exp(−6d): non-zero and direction-singular at d→0, i.e. a point sink of curl, where a real vortex has a calm eye (Lamb–Oseen: v ∝ (1−exp(−r²/rc²))/r — zero at the core, peak at ≈1.12·rc, 1/r far field). And the hue spin is HSV: rotating H at constant V changes luminance wildly between yellow and blue, so the "spectral" cycle flashes brightness.
ADD:
  1. Lamb–Oseen pointer vortex (kernel deepening; one-sentence family match: this shader IS a vortex field): replace the swirl magnitude `exp(−6d)` by a Lamb–Oseen profile with rc ≈ 0.06–0.08 uv, peak magnitude equal to HEAD's peak at default, far field decaying 1/d but still enveloped so it stays local. Held/idle weights (0.35/1.0, 0.4+mids) unchanged.
  2. Luma-preserving hue spin: rotate (I,Q) of YIQ about the luma axis by the same angle HEAD adds to H (`phase·colorShift·spin + …`), so the spectral cycle keeps luminance; saturation/energy gain terms stay. Clamp ≥ 0 before ACES. Measure the temporal std of mean luma over one hue turn, HEAD vs new.
RESCUES: R1 the `extraBuffer[133..138]` spring is DEAD (re-zeroed every frame ⇒ `initialized` false ⇒ springPos = rawMouse, springVel 0, dt 0). Delete the dead state path and use the raw pointer (output identical by construction — verify); do NOT introduce the A-texel scheme here (A is a per-pixel sim; do not spend two texels on it). Update the header's "Batch 58D" wording and any `temporal-state`-style JSON claim only if now false.
FORBID: re-adding a spring, dispersion/Cauchy taps (row budget), IQ palette on top, new params.
A PACKING: unchanged (raw sim state; ACES only on writeTexture).
```

## 7. blueprint-reveal-guided  (fork C)  — first pass (no Upgraded header)
```
SHADER: blueprint-reveal-guided
IDENTITY: a blueprint drawing of the photo (white edge lines on blue, faint grid) with a circular window around the cursor that reveals the guided-filtered real image; alpha = guided-filter confidence (line weight).
KEEP VERBATIM: 4 params (Edge Strength→line gain, Grid Opacity, Radius, Softness); the depth-guided filter (He-style a·guide+b, 7×7 window, ε=0.001) as the revealed image; Sobel edge detection; blue background (0.05,0.1,0.4) + white lines; the sin grid; the reveal mask; alpha = confidence-modulated; A = (filteredColor, confidence); depth passthrough.
MECHANISM (tactics 1, 5, 7): Sobel gives a 3-px-wide smear whose width varies with contrast; a draughtsman's pen draws a single constant-weight hairline, with heavier outlines at object boundaries (tactic 5) — the gradient direction is already computed and thrown away (tactic 3/7). A blueprint's interior is flat blue, so tone is lost; technical drawings hatch solids by tone.
ADD:
  1. Hairline thinning by gradient-oriented non-max suppression: return (magnitude, direction) from the Sobel, compare with the two neighbours along ±gradient, keep the ridge only; Edge Strength keeps its role as line gain; line weight is heavier where the depth map steps (object outline) — this also makes the header's "lines follow true object contours" true.
  2. Tone hatching: in the blueprint (unrevealed) side, 45° hatch lines whose density/weight follow source luma (dark = dense, ≥2 levels), pale-cyan, under Grid Opacity's grid (does not replace the grid).
RESCUES:
  R1 the Sobel runs on the RAW image although the comment/header say it uses the guided result (only the revealed picture is guided). Cheapest honest fix = idea 1's depth-step weight; otherwise correct the header.
  R2 flat/absent depth ⇒ `varGuide≈0` ⇒ a = 0 ⇒ the "guided" image is an 80 % blend to an 11-px box mean (heavy blur). Verify with `SRCFLAT`/a flat depth render; guard so a flat guide falls back to the original (blend by `varGuide/(varGuide+ε)`-style confidence) and report.
  R3 no ACES on display: blueprint = blue + white·edge·gain + grid exceeds 1 → ACES on display RGB (clamp ≥ 0), alpha stays semantic; report the default-look change (the deep blue shifts).
  R4 `uv = gid/resolution` has no +0.5 → pixel-centre.
FORBID: springs, click ripples, IQ palette, neon/glow on the lines, a second reveal system, raymarch.
A PACKING: unchanged (A = filtered colour + confidence, display-space; nothing reads C).
```

## 8. data-scanner-gabor  (fork C)  — first pass (Batch-67 header only)
```
SHADER: data-scanner-gabor
IDENTITY: a vertical scan bar that follows the cursor x (with an fp128 phase wobble); inside it a 4-orientation Gabor bank colour-codes local orientation over the photo; outside the bar the photo is dimmed; green grid, bright border, vertical packet, click bursts, held widens the bar.
KEEP VERBATIM: 4 params (Frequency, Sigma, Gabor Response, Scan Width); fp128 scan phase; the 4 orientations (0/45/90/135° + rot) with the per-orientation cosine palette and |r|-weighted blend; green grid; bar border; vertical packet; click bursts; held widening; outside dim; ACES + semantic alpha; A = display RGBA (C read as colour); depth passthrough.
MECHANISM (tactics 1, 3, 7): the bank uses only the EVEN (cosine) phase response — a signed value that oscillates with the stripe phase, so the "analysis" shows ripple fringes instead of a steady orientation response. The standard next step is the quadrature pair: the odd (sine) phase in the same loop, energy = √(even²+odd²) (phase-invariant), phase = atan2(odd, even). Tactic 3: with four energies the shader already has an orientation vector field and throws it away; tactic 7: an orientation is a direction.
ADD:
  1. Gabor energy via the quadrature pair: accumulate the sine-phase response in the SAME loop (one extra accumulator, no extra taps), use energy as the response magnitude and keep the orientation palette; brightness is steady across stripes. `Gabor Response` keeps its gain role.
  2. Orientation needles: from the four energies compute the dominant orientation θ* = ½·atan2(Σ E_k sin2θ_k, Σ E_k cos2θ_k) (+rot) and coherence; draw a short tick per existing 1/40 grid cell: pixels whose offset from the cell centre is parallel to the pixel's own θ* (|cross| < w) and within L·coherence of the centre. No extra taps.
RESCUES:
  R1 seam: outside the bar `color *= 0.4`, inside `mix(color, analyzed, in_scan·0.9)` starts from the UNDIMMED photo, so the bar's soft edge is a bright outline against the dimmed field → dim once with `mix(0.4, 1.0, in_scan)` before the mix. Verify on a render.
  R2 `plasmaBuffer[band + 1u]` reads out of range (buffer is a single vec4) → remove or drive the same faint tint from bass/mids/treble per band; never `[1..]`.
  R3 `uv = gid/resolution` has no +0.5 → pixel-centre.
  R4 cost: 4×169 taps in the bar already; report frameMs HEAD→new at 192 and 576; do not add taps.
FORBID: springs, new click systems, IQ palette beyond the existing orientation palettes, a second scanner, new params.
A PACKING: unchanged (display RGBA; C read as colour at in_scan·0.1).
```

## 9. neon-warp  (fork D)  — 3 ideas already shipped (convective plume, schlieren bands, inferior mirage)
```
SHADER: neon-warp
IDENTITY: a heat field (pointer ember/held source, click bursts, three bass-driven sources) refracts the photo (whip + gradient displacement) and glows through a blackbody ramp; plume, schlieren bands and inferior mirage on top.
KEEP VERBATIM: 4 params (Refraction Strength, Diffusion, Emission Gain, Cooling); ThermalField/addSource + plume stretch; shipped ideas 1–3; ripple sources; idle ember 0.15 / held 1.4; whip; blackbodyRGB glow + fog glow; 18 % advected exact-C history; saturation 1.18; ACES on display; A = linear pre-ACES RGB + heat alpha (read back as C colour); depth lifted by heat.
MECHANISM (tactics 2, 4, 8): refraction in hot air follows the density gradient (Gladstone–Dale: n−1 ∝ ρ ∝ 1/T), not the temperature gradient: the deflection is ∝ ∇T/T², so it is strongest on the cool shoulder of a plume and flattens at the incandescent core — HEAD displaces ∝ ∇heat everywhere. Cooling only sets the ripple-source decay, while the colour trail left behind is a fixed 18 % history; a real heated spot cools through the blackbody sequence (white→yellow→orange→red→dark), keyed to how fast it cools.
ADD:
  1. Gladstone–Dale density refraction: displacement factor `f(heat) = ((1+g)/(1+g·heat))²` (normalised so f(1)=1: default magnitude where heat≈1 is HEAD's) applied to the existing `grad·(−0.3)+whip` term, so the hottest core refracts less and the shoulder more; schlieren/mirage untouched.
  2. Planck-cooling afterglow: the history weight becomes Cooling-keyed (`mix(0.30, 0.08, cooling01)` ⇒ ≈HEAD's 0.18 at the default 0.45) and the history is tinted per frame toward red as it cools (×(1.0, 0.88, 0.70)-ish before the mix), so a moving ember leaves a trail that goes white→orange→red. Must stay bounded (history never feeds back above the source).
RESCUES: none found at HEAD (verify NaN-free at heat extremes and with `A16=1`).
FORBID: springs, an extraBuffer state, new click systems, shockwave rings, particles/sparks, IQ palette, re-doing shipped ideas 1–3.
A PACKING: unchanged (linear pre-ACES RGB + alpha; C read as colour).
```

## 10. hybrid-fractal-feedback  (fork D)  — first pass (2026-05-23 hygiene header only)
```
SHADER: hybrid-fractal-feedback
IDENTITY: a mouse-steered Julia set drawn with a bounded cosine palette, fed back through C with accumulative alpha and an RGB-delay split, composited over the live input.
KEEP VERBATIM: 4 params (Zoom Level, Feedback Strength, RGB Channel Delay, Color Cycling); Julia iteration (z²+c, 45 iterations, escape radius 2) and the c = mix(cBase, cMouse, 0.5) construction with click kicks; accumulativeAlpha; the RGB-delay split along `delayVec`; blend over the current input; depth lowering; A = accumulated RGBA (read back as C colour).
MECHANISM (tactics 3, 6): the loop computes `z` every step and throws away everything except an integer count — banded colour, no orbit structure (tactic 3, §12.2E). The file owns C as feedback but samples it at the SAME uv, so the loop never moves: a real video-feedback loop zooms/rotates the previous frame each iteration (tactic 6).
ADD:
  1. Smooth iteration + orbit-trap veins (§12.2E "orbit trap" + "smooth iteration count", E1): `fractalValue` becomes the smooth escape count (no banding) and a trap (distance to a line/circle, min over the existing loop) multiplies the palette as veins; `Color Cycling` keeps its role.
  2. Video-feedback transform: the history read for the blend is taken at `pivot + rot(θ)·(uv−pivot)·s` (s ≈ 0.995, θ ≈ ±0.004 rad/frame scaled by dt-free constants, pivot = the Julia pivot/pointer) so the accumulated image tunnels/spirals. Feedback Strength keeps its role; the history must stay bounded.
RESCUES:
  R1 the `extraBuffer[133..138]` spring is DEAD (re-zeroed every frame; `extraBuffer[138]>0.5` never true) so `mouse = rawMouse`. The identity says "smooth the Julia parameter": revive it with the A-texel scheme (rule 7, exemplar cyber-lens) — OR, if that costs identity/complexity, drop to the raw pointer and say so. Decide with evidence; either way delete the dead path.
  R2 C is sampled with the FILTERING `u_sampler` (`prev`, `prevR`, `prevB`) → exact loads / hand-rolled 4-load bilerp at the texel centre (rule 8).
  R3 `plasmaBuffer[regionBin]` (bins 1..8) is out of range → drive the per-region shimmer from bass/mids/treble (by region index mod 3); never `[1..]`.
  R4 no tone-map: the accumulated RGB goes straight to writeTexture → ACES on display only (A keeps the pre-ACES accumulation; clamp ≥ 0).
  R5 `z = (uv−0.5)·zoom·2` is not aspect-corrected (the Julia set is stretched on 16:9) → multiply z.x by aspect; report the default-look change.
FORBID: springs in extraBuffer, new click systems, IQ palette replacement, a different fractal, new params.
A PACKING: A = accumulated pre-ACES RGBA (read as C colour/alpha accumulation); ACES only on writeTexture.
```

---

## Formula budget (§12.4)
| Row | Files |
|---|---|
| Cauchy-family non-linear dispersion | rgb-ripple-distortion (Cauchy n(λ)), rgb-distance-split (secondary spectrum k²) |
| Deep-water dispersion | rgb-ripple-distortion |
| Block quantization (chroma-from-block) | block-distort-interactive |
| Sync-pulse timing / head-switch skew | glitch-reveal |
| Orbit trap + smooth iteration | hybrid-fractal-feedback |
| native (once each) | tone hatching, hairline NMS (blueprint); Gabor energy, orientation needles (scanner); Lamb–Oseen, luma-preserving hue spin (vortex); Gladstone–Dale, Planck cooling (neon-warp); footprint integration, cat's-eye (pixelate); staggered re-key (glitch-reveal); elastic recoil (block-distort); longitudinal CA (rgb-distance-split); video-feedback transform (hybrid) |
