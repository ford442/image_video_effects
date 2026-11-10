# BRIEFS — sonnet/batch-30 (written BEFORE any WGSL edit; HEAD = dac77dfc)

Theme: glitch, phosphor, warp and HDR distortion. Ten existing catalog shaders. Passes: first pass = 7 (no `Ideas:` line), second pass = rgb-shift-brush (2026-10-04), block-distort-em (2026-09-11, so this is its 3rd idea round), synthwave-grid-warp (2026-04 header, no ideas). Forks: A = CRT/HDR (retro-phosphor-hdr, retro-phosphor-stipple, alucinate-hdr); B = block/glitch/mosh (block-distort-em, glitch-slice-mirror, datamosh-brush-diffusion); C = brush/reveal (digital-reveal-guided, rgb-shift-brush); D = warp/grid (vortex-warp-coupled, synthwave-grid-warp).

HEAD defects found while reading (rescues, not ideas): listed per card as **R#**. Everything below is from reading the files; nothing was rendered before the cards were written.

---

## 1. retro-phosphor-hdr  (fork A)
```
SHADER: retro-phosphor-hdr
IDENTITY: a CRT screen — barrel glass, RGB triad stripes, scanlines, interlace dimming, phosphor persistence, grain, vignette — with HDR bloom + ACES.
KEEP VERBATIM: 4 params (Screen Curvature→barrel+CA, Phosphor Size→triad pitch, Scanline Intensity, HDR Bloom→bloom gain); barrelDistort/chromaticAberration/phosphorTriad/scanlines/interlaceFlicker chain order; max(color, prev*decay) persistence reading C as COLOUR; grain; vignette; click-ripple flash; ACES on display; A = raw HDR (r,g,b = pre-tonemap incl. bloom, a = overexposure) — unchanged packing.
MECHANISM (tactics 2,3,6,8): a CRT faceplate scatters bright phosphor light into a halo (energy moves from the core to the halo — tactic 8); the bloom loop already computes a `neighborMax`, `totalWeight` and a 16-tap ring it throws away (3); the file owns C as colour history, so one more piece of continuity is a slow rolling intensity band riding the same field cadence as interlaceFlicker (6).
ADD:
  1. Energy-conserving faceplate bloom (§12.2F): soft-knee bright extract of the 16-tap ring, hue-preserving, and the core loses what the halo gains (`src -= spread*k`). Native: it IS the "HDR bloom chain" the file advertises.
  2. Rolling hum bar: one slow vertical brightness band (power-supply hum beating against the field rate, ~0.1–0.2 Hz roll, ±4–6 % intensity, soft edges) multiplied into the scanline/interlace stage; amplitude fixed, not a new param. A CRT artefact a technician would name.
RESCUES:
  R1 bloom is DEAD on any LDR source: `neighborExposure = max(0, neighborMax - 1.0)`; a photo/video never exceeds 1.0 so `totalWeight≈0` and `bloom=0` → the "HDR Bloom" slider does nothing. Move the knee into display range (≈0.65–0.8, soft) so the slider is live on a photo AND still behaves on HDR chains.
  R2 `audioPulse = u.zoom_config.w` is the MOUSE-DOWN flag, not audio → use `plasmaBuffer[0].x` (bass). Idle look unchanged (0 either way).
  R3 `normalize(centered)` in chromaticAberration is NaN at the exact centre pixel → `normalize(centered + 1e-4)` as the stipple sibling does.
  R4 alpha is a bare 1.0 → semantic (e.g. screen coverage + glow), never below ~0.85 so compositing is not hollowed.
FORBID: springs, extra click systems (ripple flash stays as is), IQ palette, neon edge pop, aperture-grille redesign.
A PACKING: raw HDR (unchanged). C is read as colour history; do not ACES the stored value.
```

## 2. retro-phosphor-stipple  (fork A)
```
SHADER: retro-phosphor-stipple
IDENTITY: a CRT where each channel's phosphor is a blue-noise-jittered dot instead of a stripe: barrel glass, CA, scanlines, interlace dimming, persistence, grain, vignette.
KEEP VERBATIM: 4 params (Curvature, Phosphor Scale→dots/cell, Scanline Intensity, Flicker); per-channel jittered dot masks (blueNoiseOffset + channel offsets); barrel/CA; scanlines()/interlaceFlicker() functions; max-persistence on C colour; grain; vignette; the `color/(1+0.5·color)` curve unless a render shows it is the dullness (then ACES, say so).
MECHANISM (tactics 2,5): a real triad's three phosphors decay at different rates (P22: red rare-earth lingers longest, blue shortest — the red smear a dark CRT scene shows); the persistence line currently uses ONE constant for all channels. A scan beam's spot widens with drive current, so bright scanlines swell and fill the gap while dim lines stay thin — the scanline profile here is brightness-independent.
ADD:
  1. Per-channel phosphor persistence (native CRT): decay vec3 ≈ (0.89, 0.85, 0.78)+pulse so G keeps the HEAD constant 0.85; ghosts trail warm.
  2. Beam-width scanlines: the sine profile's darkness is scaled by (1 − luma·swell) so bright lines fill the gap and dim lines keep full gaps; `Scanline Intensity` keeps its role (max gap depth).
RESCUES:
  R1 `audioPulse = u.zoom_config.w` is MOUSE-DOWN → `plasmaBuffer[0].x`. JSON tags `mouse-driven` is then false unless something real uses the pointer — fix the tag, add `audio-reactive`.
  R2 `fract(rUV/gUV/bUV)` wraps the opposite screen edge into the corners under barrel distortion (visible seam) → clamp + a rounded black glass edge (soft mask), alpha follows the mask.
  R3 depth store is `vec4(0,0,0,1)` (kills downstream depth) → pass the source depth through.
  R4 alpha bare 1.0 → semantic coverage.
FORBID: bloom chain (that is retro-phosphor-hdr), hum bar (also hdr), springs, ripples, IQ palette.
A PACKING: display RGB (post-curve) + alpha, read back by C as colour history via max(); unchanged. State whether the curve was kept or ACES.
```

## 3. alucinate-hdr  (fork A)
```
SHADER: alucinate-hdr
IDENTITY: AI-VJ "conductor's baton": six music-reactive gold→cyan spectrum bars + a beat line (mouse is the conducting hand) over a psychedelic sine-warp + RGB split + HDR bloom atmosphere, premultiplied.
KEEP VERBATIM: 4 params (Atmosphere Bloom→radius, Bloom Intensity, Tone Map Exposure, Glyph Prominence); the warp formula family and mouse boost; 3-tap RGB shift; 16-tap bloom ring; mouse glow; ripple flash; vibeGlyphs layout (6 bars, x=0.18+0.13i, height from bass/mids/treble, beat line, conductor widening); gold→cyan gradient; premultiplied output; depth-modulated alpha; A = raw HDR (unread by anything — document).
MECHANISM (tactics 3,5): the bars are a spectrum analyser; a real analyser meter is segmented (LED ladder) with a red clip zone — the file draws smooth gradient bars. The atmosphere warp is mouse-driven only although the file is a music visualiser: the audio the bars show does not touch the layer beneath.
ADD:
  1. Segmented LED-ladder bars with a red clip segment (native to "spectrum meter"): stateless — quantise bar height into N segments with thin gaps, top segment(s) tint toward red when the band exceeds ~0.85. Bar layout, gradient and widths unchanged.
  2. Beat-locked warp: bass breathes `warp_amp` (≈ ×(1+0.6·bass)), treble opens the RGB-shift (`shift_amount` ×(1+0.5·treble)); mouse behaviour unchanged. The atmosphere now plays with the music the glyphs show.
RESCUES:
  R1 bloom is DEAD on LDR (`neighborMax - 1.0`, same bug as retro-phosphor-hdr) → knee into display range; slider live.
  R2 "Glyph Prominence" (`zoom_params.w`) is NOT READ anywhere (dead slider; the glyph gain is the constant 0.85) → wire it as the glyph gain with 0.7 (its default) reproducing 0.85 exactly: `gain = 0.85·(p/0.7)`.
  R3 `mouse_active = zoom_config.w > 0.0` etc. are fine; the spring is absent — do not add one.
FORBID: springs, IQ palette, history/peak-hold state (A is unread; do not start a state scheme here), new glyph shapes, FFT-band reads (plasmaBuffer[1..] does not exist).
A PACKING: raw HDR in A (unread at HEAD) — keep; final display premultiplied.
```

## 4. block-distort-em  (fork B)
```
SHADER: block-distort-em
IDENTITY: a mosaic of blocks pushed away from the cursor by an electric-field model (cursor + orbiting click charges), tilted by a hinge shear, with RGB split, B-field hue rotation, cell-edge highlights and field streamlines.
KEEP VERBATIM: 4 params (Block Size, Push Strength, RGB Split, Field Strength); electricField/magneticField, the orbiting secondary click charges (3 s window), grid/cellID/cellCenter push, row phase stagger (idea 2 of 2026-09-11), hinge shear (idea 1), split RGB taps, hueShift by B, edge highlight, streamlines, core glow, held gain, ACES display; A = ACES display RGBA (+ the two state texels below).
MECHANISM (tactics 3,7,6): `totalB` (the magnetic term) is computed and ONLY used as a hue angle — promote it: a magnetic term rotates things (tactic 3). Hinge shear already tilts a block along the E tangent; the tilt has no light, so a displaced block does not read as a raised tile (tactic 2). Block geometry is rigid per cell for the push but the EM displacement is per-pixel.
ADD:
  1. Magnetic block rotation: each block rotates about its centre by an angle ∝ clamp(totalB at the cell centre) × pushMask (≤ ~0.35 rad), applied to the cell-local offset before the sample, so blocks twist as the cursor moves. Native: it makes B a geometric, not just chromatic, term.
  2. Hinge facet shading: the lit/dark halves of a tilted block — shade ∝ hinge tilt × cellUV.x (sign from the hinge shear) × pushMask, small (±8–12 %). Extends idea 1 of the last pass; no new motif.
RESCUES:
  R1 `prevMouse` lives in extraBuffer[133..134] which is zeroed every frame → prevMouse=(0,0) so `mouseVel = mousePos·60` is a phantom constant velocity: the magnetic term (and hue spin) is driven by cursor POSITION, not motion. Use the A-texel scheme (COMMON §7) for the previous cursor; clamp |mouseVel| (e.g. ≤ 6) and let it be 0 on the first frames (sentinel not yet valid).
  R2 `normalize(distVec)` is NaN when a cell centre sits exactly on the cursor → guard.
FORBID: springs/glide (the cursor is the field source, raw), IQ palette, a second tear system, ripple rings.
A PACKING: ACES display RGBA (unchanged) — texels (0,0),(1,0) carry the cursor-track state with sentinel 0.7371 (C is read ONLY for those two texels; two corner pixels of history are not used by this shader). Say it in the header.
```

## 5. glitch-slice-mirror  (fork B)
```
SHADER: glitch-slice-mirror
IDENTITY: the frame is mirrored across a vertical seam at the cursor x, with a glitch halo around the seam (block-offset tears + horizontal RGB split + scanline darkening), a racing fracture packet, and click bands that shove the seam.
KEEP VERBATIM: 4 params (Intensity, Speed, Scale→block size, Detail→split/scanline density); fp128 seam integration of mouse.x + clickShift; mirror at seamX; glitch halo width/held widening; fracture_packet; block_size/seed/noise>0.8 x-tears; RGB split; scanline darkening; click damage bands (1.4 s window); mix with C by packet (12 %); semantic alpha.
MECHANISM (tactics 1,2,6): the corrupted blocks are displaced but each pixel inside them stays a smooth continuous image — a real macroblock codec failure shows the *block* itself held/quantised (tactic 2). A broadcast tear originates in interlace field offsets — alternate scanlines displaced oppositely (tactic 5); the file already has a scanline term but no field structure.
ADD:
  1. Macroblock hold (§12.2B block quantization): inside `bigNoise` blocks, colour is quantised — sample the block centre (one tap) and posterise with Q from `Scale`, blended by the existing `intensity`. Blocks read as blocks.
  2. Interlace comb at the seam (§12.2B field interlace): inside the glitch halo, even/odd scanline rows are displaced ±δ in x (δ ∝ intensity·`Detail`) — static per row parity, NO per-frame flicker (that would be the avoided frame-hash strobe).
RESCUES:
  R1 DOES NOT COMPILE at HEAD: `finalColor.rgb = acesToneMap(...)` swizzle assignment (naga). It is on the knownFailures ratchet (7→6 when fixed; coordinator edits `src/contracts/wgsl_validation.json`). Fix by building the vec4 whole.
  R2 double ACES: the glitch halo is `ACES(ACES(rgb))` while the rest is `ACES(rgb)` → the halo is darker/contrastier than the picture (visible seam). Apply ACES once, at the end; clamp ≥0 first.
  R3 dead spring: extraBuffer[133..138] is zero every frame so the guard `extraBuffer[138] > 0.5` is always false and `mouse` is the raw cursor already — delete the dead block (raw cursor stays; no A-texel state needed).
  R4 `plasmaBuffer[blockBin].x` (blockBin 1..8) is out of range → 0/undefined; replace the audio read with bass/mids/treble from [0].
FORBID: springs, IQ palette, thin-film, particles, a second unrelated tear system.
A PACKING: ACES display RGBA (unchanged); C only read for the packet echo.
```

## 6. datamosh-brush-diffusion  (fork B)
```
SHADER: datamosh-brush-diffusion
IDENTITY: Perona–Malik anisotropic diffusion over a heavily temporal-blended frame; a held brush (and click heat) punches datamosh blocks (24×24 hashed uv offsets, or frozen ghost blocks) into it; oil-slick tint + ACES.
KEEP VERBATIM: 4 params (Brush Size, Kappa→edge stopping, Time Step, Alpha Ghost); P–M exp edge-stopping + 4-neighbour flux; 5 % temporal blend toward the input; 24×24 block ID, the 28 % hold vs glitch-sample branch; brush radius + held mouseFactor×6 heat; ripple heat; oil tint; semantic alpha.
MECHANISM (tactics 2,7,6): datamosh is a P-frame decoded with the WRONG motion: the reference frame is carried along a motion vector, and chroma bleeds along it while structure persists. HEAD's glitch sample is a constant per-block hash offset on the CURRENT frame — it never follows the stroke and never carries history (C is available as exact colour history).
ADD:
  1. Motion-carry smear (§12.2B macroblock motion carry): inside the brush, glitch blocks sample the previous-frame colour (exact C, nearest/bilerp of 4 loads) displaced against the brush velocity (from the glide state's velocity) + the old hash offset as dither — a P-frame with the wrong reference following the stroke.
  2. Luma/chroma split bleed (§12.2B chroma delay variant): in mosh blocks keep luma from the diffused/held frame and take chroma from the carried sample, so colour bleeds along the stroke over intact structure (the real datamosh look).
RESCUES:
  R1 the spring lives in extraBuffer[133..138] = zero every frame → `smoothMouse = (0,0)` for every pixel → the brush and heat are PINNED to the top-left corner; held anywhere else does nothing. Use the A-texel glide scheme (COMMON §7; ω≈9.5 as HEAD) so the brush follows the cursor; its velocity feeds idea 1.
  R2 ACES→C→ACES loop: A stores the ACES+oil-tinted colour and C is read as the next frame's `prevColor` (95 % weight), re-tinted/ACES'd every frame → contrast/saturation compound. Store the pre-tint, pre-ACES diffused state in A; apply oil tint + exposure + ACES on `writeTexture` only. (Default look changes — flag meanL/stdL.)
FORBID: IQ palette, fluid solver, a different diffusion operator, new params, ripple shockwave rings (ripple heat stays).
A PACKING: raw diffused colour state (pre-tint, pre-ACES) + alpha in A; texels (0,0),(1,0) carry glide state (sentinel 0.7371). C read as colour.
```

## 7. digital-reveal-guided  (fork C)
```
SHADER: digital-reveal-guided
IDENTITY: Matrix code-rain over the photo; a cursor/click "reveal" brush wipes the rain away to show the photo through a depth-guided (He et al.) filter; trail mask kept in C.
KEEP VERBATIM: 4 params (Rain Density, Reveal Size, Trail Fade, Depth Influence); glyphShape (bars+dots), grid/cell/colSpeed/dropVal/charBright/flicker, the 3 % white-hot cells, bass tint; guided-filter box regression with mouse-shrunk radius/epsilon; brush + held ×1.35 widen + capped click ripples (1.2 s); max(prev·fade, brush+ripple) mask in C.r; mix(rain, filtered, mask); ACES; alpha semantic; A = (mask, confidence, glyph, 1).
MECHANISM (tactics 2,3,6): the Matrix code rain is a column HEAD with a long fading tail of mutating glyphs — HEAD lights each cell independently with a short per-cell fade, so there is no head/tail structure. The reveal mask is a smooth per-pixel field, but the "digital" boundary between rain and photo should be made of the glyph CELLS (the file's own pixels), not a smooth wipe.
ADD:
  1. Rain head + decaying tail: per column the head glyph (white-hot) leads a tail of previous cells fading ≈ exp(−k·rowsBehindHead); `colSpeed`/`verticalPos` unchanged. Native Matrix vocabulary; replaces the isolated random 3 % flash cells' role without removing them.
  2. Glyph-cell reveal front: sample the mask at the glyph-cell centre (exact C load at the cell centre + brush/ripple analytic at the centre) so the reveal boundary steps in cell units; at the front (mask ≈0.2–0.8) the photo shows only through the glyph shape (glyph stencil) with a lit green rim. Interior of the revealed area stays the guided-filter image.
RESCUES:
  R1 pinned spring: `smoothMouse = extraBuffer[133..134]` = (0,0) every frame → the reveal brush is pinned to the top-left corner (the effect is mostly dead). Use the A-texel glide (COMMON §7, ω=10 as HEAD) — note A here is the mask-state packing, so texels (0,0),(1,0) are repurposed and the trail read is zeroed there.
  R2 `plasmaBuffer[band+1u].x` is out of range (single-vec4 buffer) → remove (use bass/mids/treble from [0] only).
FORBID: new params, IQ palette, ripple shock rings other than the existing reveal ripples, replacing the guided filter.
A PACKING: existing documented mask packing (r=mask, g=confidence, b=glyph, a=1) + state texels (0,0),(1,0) with sentinel 0.7371.
```

## 8. rgb-shift-brush  (fork C; 3rd idea round)
```
SHADER: rgb-shift-brush
IDENTITY: a brush paints a decaying mask; where painted, R and B are displaced in opposite directions (rotating with time) with spectral per-channel absorption alpha; click fronts add rings.
KEEP VERBATIM: 4 params (Shift Amount, Brush Size, Decay, Hue Shift); prevState-from-historyCoord with feedbackFlow; brush, click fronts, ribbon/spectral runners; fast mask (A.r) + slow mask (A.g, idea 1 of 2026-10-04); 7-tap prism fan weighted by bandResponse (idea 2); hue shift; wavelength alpha (Beer-Lambert-ish) and final tint terms; A = raw masks (r fast, g slow, b 0, a 1).
MECHANISM (tactics 7,4,2): the displacement direction is a global time rotation — it ignores the stroke; a prism/lens disperses ALONG the surface gradient and most at its EDGE, hardly at all in the flat interior. The mask already has that gradient (4 exact loads of C.r). The fan's taps are spaced linearly in wavelength; real dispersion n(λ)=A+B/λ² spreads the blue end much more than the red.
ADD:
  1. Edge-oriented dispersion (§12.2A direction-not-magnitude): direction blends from the time-rotating dir toward ±∇(mask) by gradient confidence, and shift magnitude gains an edge term (stroke rim disperses more than its interior). Same params; idle (no mask) picture unchanged.
  2. Cauchy-spaced prism fan (§12.2F): fan tap positions use 1/λ² spacing (n(λ)=A+B/λ² from the file's WAVELENGTH_* constants) instead of linear, blue end spread widest.
RESCUES:
  R1 `bandResponse` uses `pow((lambda-W)/55.0, 2.0)` with a NEGATIVE base for 6 of 7 taps → NaN-risk (pow(neg,2.0)); rewrite as `d*d` / `exp(-d*d)`.
FORBID: springs, extra click rings, IQ palette, changing hue-shift or alpha model, new params.
A PACKING: raw masks (unchanged): r=fast, g=slow, b=0, a=1 — do not put display colour or gradient in A.
```

## 9. vortex-warp-coupled  (fork D)
```
SHADER: vortex-warp-coupled
IDENTITY: a cursor-centred twirl of the photo whose strength/twist are coupled to a viscous velocity+dye field stirred by the cursor: fluid speed adds to the twirl, dye thickness adds twist, tints amber, smears, and sparkles.
KEEP VERBATIM: 4 params (Strength centred at 0.5, Radius, Twist, Viscosity); semi-Lagrangian advect with ×viscosity, cursor force + vortex force, capped click ripples (2 s, outward + dye), edge damping, velocity clamp; coupled twirl (weight=percent², spiralAngle); fluid blur smear; amber absorption tint; noise specular; pressure alpha; depth modulation; A = raw sim state (vel.xy, curl-ish z, dens w).
MECHANISM (tactics 2,3): the solver damps small swirls (semi-Lagrangian + viscosity) — the first-order missing physics is vorticity confinement; the .z channel is labelled vorticity but stores `vel.x - vel.y` (not curl) — an intermediate to promote honestly. Dye thickness `dens` already modulates tint and blur; a layer of liquid with a thickness gradient is a lens at its meniscus.
ADD:
  1. Vorticity confinement (§12.2D, snippet D1): honest curl ω = ∂v_y/∂x − ∂v_x/∂y from exact C neighbours (clamped), N = ∇|ω|/|∇|ω||, force ε·(N×ω) added to vel; honest ω stored in A.z.
  2. Dye meniscus lens (§12.2F Snell/thickness): sample the photo displaced along −∇dens (exact-load gradient of C.a) so thick dye edges bend the picture; amplitude ∝ dens·small.
RESCUES:
  R1 phantom velocity: thread (0,0) writes the cursor to A(0,0) and then OVERWRITES the same texel with fluid state at the end of main → `prevMouse` = (vel.xy at 0,0) ≈ 0 → `mouseVel = mousePos·60` always, saturating the fluid with the cursor POSITION. Move cursor-track state to the A-texel scheme (COMMON §7; texels (0,0),(1,0), zero the fluid read there), clamp |mouseVel|.
  R2 filtering sampler on C (`textureSampleLevel(dataTextureC, u_sampler, …)` ×4): contract says exact loads; hand-roll the bilinear from four clamped `textureLoad`s.
  R3 (check) `vorticity = vel.x - vel.y` replaced as above.
FORBID: ACES (HEAD has none and the output is the photo — clamp ≥0 instead, no `upgraded-rgba`), IQ palette, a new solver, springs.
A PACKING: raw sim state (vel.x, vel.y, curl, dens) + cursor-track state texels (0,0),(1,0) with sentinel 0.7371 (fluid zeroed there). State it.
```

## 10. synthwave-grid-warp  (fork D)
```
SHADER: synthwave-grid-warp
IDENTITY: a stylised synthwave scene — neon cyan perspective grid on a ground plane with distance fog, a haloed sun, two silhouette mountain layers whose heights come from the photo's top row, a pink→purple sky gradient, Reinhard-curved; alpha = scene coverage × fog.
KEEP VERBATIM: 4 params (Camera Height, Fog Density, Fog Falloff, Mountain Scale); screenToWorld/sdGrid/heightFog/renderSun/mountainLayer; the sunset gradient; sun drift sin(time·0.05); composition order; alpha = coverage·fog (semantic).
MECHANISM (tactics 5,2): the grid is STATIC (world pos has no time term) — the signature of synthwave is the grid streaming toward the viewer; the sun is a plain disc — the iconic sun has horizontal slits widening toward the bottom; the file is called "grid warp" yet nothing warps; `audioDrive` only scales alpha so the audio never reaches colour.
ADD:
  1. Streaming grid: advance world z by `time·speed` (speed with a bass surge) so lines flow toward the camera; bass/treble also pulse line brightness (audio now reaches colour, as the Grok comment intended).
  2. Slatted retro sun: horizontal slits cut from the lower half of the sun, slit thickness increasing toward the bottom and drifting slowly downward; halo kept.
  3. (optional, only if it reads well) ground swell: a travelling sine along z displaces the grid lines (amplitude from bass, small) — the "warp" of the name.
RESCUES:
  R1 ORIENTATION: HEAD maths is y-up (sky pink toward uv.y=0, mountains rise where uv.y<h, sun at 0.3) but gid.y=0 is the TOP row, so the scene is upside-down in the app (mountains hang from the top, the horizon/sky gradient inverted). Render HEAD first; if confirmed, flip once (`let y = 1.0 − uv.y` used for sun/mountains/sky/screenToWorld), document it.
  R2 `dataTextureA` is never written → write display RGBA.
  R3 the tone curve `col/(col+1)` halves every colour (1.0→0.5) so neon is dull: if a render confirms, move to clamped ACES (and tag `upgraded-rgba`); if you keep Reinhard, say so and do not tag.
FORBID: springs, ripples, IQ palette, photo-driven warping, new params (the 4 sliders keep their roles; speeds are literals).
A PACKING: display RGBA (the file has no state) — A = the written RGBA.
```
