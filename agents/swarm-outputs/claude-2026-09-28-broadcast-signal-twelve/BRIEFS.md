# Broadcast-Signal Twelve — Idea Cards (2026-09-28)

Written before any WGSL edit. Every idea was grepped against the 682 catalog `Ideas:` lines.
"Floor fixes" are hygiene (make it work) and are not counted as ideas.

## Idea Cards (written to BRIEFS.md before any WGSL edit)

Common FORBID (taken catalog-wide): head-switch skew/flagging, dropout-compensator line repeat, vertical-hold roll with blanking bar, tape-stretch shear, h-sync porch, dot crawl, luma-shouldered noise, quantisation staircase, macroblock I-frame tear, chroma ghost from C motion, motion-vector inheritance, keyframe recovery flash, row desync trail, rolling hum bar, faceplate glass, interlaced field parity, two-rate phosphor knee, triad-aligned grain, P7 tail, brightness-dependent beam width, bright-source blooming, Asendorf intervals, 3x5 segment font / white-hot leader, back-face mirror sample, IQ palettes, springs, generic ripple shockwaves on non-pointer effects.

### 1. vhs-chroma-bleed
- IDENTITY: warm, jittery VHS still with R/B smeared apart, grain, scanlines, vignette.
- KEEP VERBATIM: barrel k=-0.06, per-row jitter, tracking wobble, block brightness, noise bands, scanline/vignette/warmth helpers, slider roles (x bleed, y jitter, z drift speed, w rgb shift).
- ADD: (1) **colour-under bandwidth**: split into Y and Cb/Cr, low-pass chroma horizontally (7-tap box, width scaled by w) and delay the chroma plane a few px to the right of luma, so colour spills past edges like a real Y/C recording; (2) **cross-colour rainbow crawl**: fine horizontal luma detail (high |dY/dx|) leaks a slowly rotating false hue into chroma; (3) **chroma loss in dropout rows**: the tracking-dropout rows go luma-only (grey) with a ragged left edge.
- Floor fixes: Noise slider (y) also scales grain (default 0.2 ⇒ HEAD's 0.08); dropout hash gets time; alpha = source alpha (not luma); ACES; guard `pow` vignette base.
- A PACKING: display RGBA (no C read; unchanged).

### 2. vhs-jog
- IDENTITY: jog/shuttle scrub — mouse X sets shuttle speed/direction, rolling head band, row tears, R/B bleed, streaks from C.
- KEEP VERBATIM: wrapped roll, head band, click slip bands, tear noise, streak, bleed, static, C max-hold streak, sliders (noise, distFreq, bleed, scanlines).
- ADD: (1) **cue/review noise bars**: at high shuttle speed the picture shows N evenly spaced horizontal noise bars (N grows with |X−0.5|) that scroll opposite to play direction; (2) **pause-mode field flutter**: near X=0.5 (dead zone at HEAD since `sign()`=0) the picture becomes a freeze frame whose odd rows come from C and even rows from the source, jittering ±1 row — the still-frame shimmer; (3) **reverse-play colour phase error**: when shuttling backward, hue rotates per row band (colour-under phase reversal), settling as speed drops.
- Floor fixes: `pow` NaN at head band → `x*x`; cap `tapeSlip`; scanlines on screen `uv_raw.y`; ACES replaces the ad-hoc rolloff.
- A PACKING: pre-ACES linear display RGB + alpha; C read as colour.

### 3. vhs-tracking-mouse
- IDENTITY: full-width tracking-noise band at mouse Y with wobble, RGB split, dropouts, treble flash; click tears.
- KEEP VERBATIM: band mask, click tears, row wobble/jitter, 3-tap bleed, vignette, sliders (barHeight, distortion, noise, colorShift).
- ADD: (1) **dash-noise texture**: the band's noise becomes row-aligned bright/dark dashes of hashed length (tape dropout streaks along scan lines) instead of white noise; fixes HEAD's column-shaped "scanline dropouts"; (2) **tracking knob on mouse X**: |X−0.5| detunes tracking (band widens, dashes lengthen); **holding** auto-tracks: the band converges and locks over ~1 s and releases on mouse-up (X=0.5 unheld reproduces HEAD); (3) **AGC lift in the band**: blacks lift and chroma drains inside the band.
- Floor fixes: remove dead spring + `plasmaBuffer[rowBin]`; alpha = source alpha; soft band gate; ACES.
- A PACKING: display RGBA (no C read; unchanged).

### 4. signal-tuner
- IDENTITY: rows wobble with an R/B split inside a tuning radius around the cursor; click rings retune; ghosted history.
- KEEP VERBATIM: aspect falloff radius 0.5, row sine + `freqRadius`, beat pulse, click rings, jitter, R/B split, sliders (frequency, amplitude, speed, noise).
- ADD: (1) **off-station snow**: the Static Noise slider (w) now mixes real snow (per-pixel hash, treble-flickered) inside the detuned zone, strongest where the wobble is strongest; (2) **RF multipath ghost**: a faint second copy of the image offset to the right by a distance set by Frequency, fading with tuning influence — a delayed-path ghost, not history; (3) **detune beat bands**: where the row-wobble frequency nears the scanline count, slow horizontal moiré beat bands drift through the zone.
- Floor fixes: history mix min 0.15 → 0 away from the cursor (video stops lagging globally); `hash(uv*time)` → `hash(uv + time)`; dead spring/env and `plasmaBuffer[regionBin]` removed; ACES; alpha semantic.
- A PACKING: pre-ACES linear RGB + alpha; C read as colour.

### 5. crt-scanline-damage
- IDENTITY: barrel-warped CRT with RGB split, triad mask, flicker, dark-band fault, treble snow/scar rows, click degauss rings.
- KEEP VERBATIM: depth-scaled barrel, ring displacement, triad `gid.x % 3`, flicker, band fault, snow/scars, sliders (scanline, distortion, flicker, rgb sep).
- ADD: (1) **misconvergence swirl**: the degauss ring pulls R/G/B rasters apart radially with a rotating purity blotch (magenta/green) that settles after the ring passes; (2) **flyback retrace lines**: during the dark-band fault, faint bright diagonal retrace sweeps cross the picture; (3) **radial chromatic barrel** (promised in JSON): the RGB split becomes radial, growing toward the edges.
- Floor fixes: scanlines are dead at HEAD (`sin(kπ)`) → `sin(gid.y*π*0.5)`-style real raster tied to slider; black bezel outside the warp instead of clamped streaks; C via `textureLoad` (HEAD samples with a filtering sampler at texel corners); cap degauss sum; ACES. JSON drops `mouse-driven` (no pointer at HEAD; keep click-reactive).
- A PACKING: pre-ACES linear RGB + alpha; C read as colour.

### 6. scan-distort
- IDENTITY: colour-quantised, block-gridded video with fake motion-vector dots, garbled blocks, glitch pulses, cursor vertical ripple, soft scanlines.
- KEEP VERBATIM: quantisation, block grid darkening, MV dot grid, garble, glitch pulse, cursor ripple, scanline count from mouse Y, sliders (block size, quant, mv visibility, glitch freq).
- ADD: (1) **sync-tear band** (the header's promised "scanline tear"): rows inside the glitch pulse slide sideways along a sawtooth ramp and drag the same row from C, so the tear shows stale picture; (2) **DCT-basis garble**: garbled blocks show cosine basis patterns (u,v index hashed per block) rather than noise, and the garbled set re-rolls with time (HEAD's `blockHash` is static); (3) **MV arrows from temporal gradient**: MV dots become short arrows along `-∇L·(L−Lprev)` per block (cheap flow from C), zero-length on still content.
- Floor fixes: store pre-ACES in A (HEAD compounds ACES through C); A.a is display alpha (drop the per-pixel bass envelope in A.a — it never worked with extraBuffer anyway); remove spring; `plasmaBuffer[bandBin]` → `plasmaBuffer[0]`.
- A PACKING: pre-ACES linear RGB + semantic alpha; C read as colour.

### 7. waveform-glitch
- IDENTITY: quantised, sine-wobbled image with a horizontal R/B split, green Lissajous scope trace, alternating scanlines, blanking bar.
- KEEP VERBATIM: UV quantisation, wobble, R/B split, 64-step Lissajous SDF, scanlines, blanking, C trail mix, slider roles (x wave, y vhs, z alias rate + trail, w scope brightness).
- ADD: (1) **waveform-monitor trace**: a second trace plots the luma of the image row under the cursor Y as a video waveform (x = column, y = luma), glowing green like the Lissajous; (2) **beam-dwell brightness**: the Lissajous glow scales with 1/beam-speed so slow lobes burn brighter and fast crossings go faint, like a real scope phosphor; (3) **block glitch** (the z slider's promised name): treble spikes shift whole quantisation cells sideways by a per-cell hash.
- Floor fixes: aspect-correct the scope; `plasmaBuffer[1..8]` bars → three-band `plasmaBuffer[0]`; `time*(1+bass)` phase jump → accumulated phase via `time + bass*k`; remove spring; pre-ACES in A.
- A PACKING: pre-ACES linear RGB + alpha; C read as colour.

### 8. holographic-projection-failure
- IDENTITY: projected image breaking up: band tears, y wobble, R/B split, fine fringes, block bit-depth faults, static, flicker, cursor repair circle.
- KEEP VERBATIM: tear bands, wobble, repair mix, R/B split by depth, fringes, block fault, static/flash, flicker, sliders (instability, chromatic split, scanline drift, signal noise).
- ADD: (1) **emitter cone**: the picture is a cyan-carrier hologram cast from an emitter at bottom-centre — brightness and fringe pitch fall off with distance from the emitter and the image goes translucent (alpha = carrier transmission), which is the hologram look the name promises and HEAD lacks; (2) **stale-frame tear bands**: tear bands show the C frame (previous picture) shifted, not the current one; (3) **re-sync sweep in the repair circle**: a horizontal lock line sweeps down inside the cursor circle re-locking rows behind it; holding widens the circle (HEAD) and speeds the sweep.
- Floor fixes: `blockSize` goes ≤0 and `bitDepth` negative once instability > 1.5 (default reaches it with bass) → clamp; `time*(k+bass)` phase jumps; params/updatedParams default mismatch resolved in `updatedParams` only; pre-ACES in A.
- A PACKING: pre-ACES linear RGB + alpha; C read as colour.

### 9. holographic-glitch
- IDENTITY: row-sheared image with radial rainbow chroma, cosine interference overlay, cursor peel fold, click desync, RGB history trails.
- KEEP VERBATIM: value-noise row shear, peel fold, click push, radial chroma, 3-tap per-channel history, spectrum overlay, sliders (glitch, holographic, rgbShift, flicker→phaseInstability role kept).
- ADD: (1) **emitter flicker** (the w slider is named Flicker but has none): short random blackouts plus slow luminance sag scaled by w, default 0.4 mild; (2) **grating-order ghosts**: the interference overlay diffracts ±1-order faint copies of the image along the shear axis, hue-split, brightening with Holographic Intensity; (3) **peel shadow**: the folded crest casts a soft contact shadow onto the image beneath it.
- Floor fixes: half-texel offset; phase-jump `time*(k+audio)` terms; alpha clamp [0.08,0.98] → source alpha × transmission; pre-ACES in A.
- A PACKING: pre-ACES linear RGB + alpha; C read as colour (3 taps).

### 10. phosphor-decay
- IDENTITY: CRT phosphor trails with bloom, shadow mask, scanlines, cyan cursor glow, click blooms, warm blackbody grade.
- KEEP VERBATIM: per-channel decay, OkLab history mix, bloom, mask, scanlines, glow, click bloom, blackbody tint, vignette, dither, sliders (decay, bloom, mask, blanking).
- ADD: (1) **burn-in**: A.a accumulates a slow long-term luma average; burned regions lose phosphor efficiency, so a ghost of static content lingers as a dim negative after the picture moves; (2) **held static charge** (promised in JSON, absent): while held, electrostatic crackle sparks near the cursor and dust specks cling to the glass and fade after release; (3) **blanking-interval flicker**: the Scan Blanking slider also drives a faint per-frame vertical-blank dip on rows near the bottom.
- Floor fixes: HEAD renders near-black (`finalRGB*alpha` with alpha≈0 below luma 0.55) → alpha semantic, RGB not premultiplied; `pow` cube roots guarded with `max(0)` (NaN persists via C); vignette base guarded; remove spring; `plasmaBuffer[y%8+1]` dead → `plasmaBuffer[0]`.
- A PACKING: linear HDR phosphor RGB (pre-vignette, pre-ACES) + burn-in accumulator in A.a; C read as that.

### 11. cyber-terminal-ascii
- IDENTITY: scrolling grid of luma-picked SDF glyphs in phosphor green, binary decode lens at the cursor.
- KEEP VERBATIM: 9 SDF glyphs, luma index, lens with held widen, click burst, colour mix, scanline, vignette, sliders (density, color mode, glow, decoder radius).
- ADD: (1) **hex-dump decode**: inside the lens each cell shows the two hex nibbles of its luma byte from a 4×6 bitmap font (HEAD flashes random 0/1); (2) **typewriter row entry**: rows entering at the bottom type in left-to-right behind a block cursor, with a bass-driven type rate; (3) **bit-error flicker**: treble flips random glyphs to their neighbour index for one frame, leaving a brief green after-image via C.
- Floor fixes: scroll offset subtracts UV units instead of cell units (image and lens drift a whole screen) → cell units; decoder radius double-mapping (`mix(0.05,0.4,p)` on an already-ranged param) → single mapping that reproduces the default look; remove spring; pre-ACES in A.
- A PACKING: pre-ACES linear RGB + glyph coverage alpha; C read as colour.

### 12. strip-scan-glitch
- IDENTITY: vertical strips scrolling at hashed, brightness-weighted speeds with sideways tears, RGB split, bass scan bar.
- KEEP VERBATIM: strip count/speed mapping, per-strip hash speed, row sine warp, tear, RGB split, wrap sampling, scan bar, sliders (strips, speed, jitter, rgb).
- ADD: (1) **vertical-blanking seam**: each strip's wrap seam shows a short black blanking bar with sync-pulse ticks and a soft smear on the rows either side, so the wrap reads as a signal rollover instead of a hard cut; (2) **held brake**: holding the pointer drags the strips under the cursor to a halt (aspect-weighted by distance to mouse X) with treble flutter, releasing back to speed; (3) **speed-streak ghost**: fast strips leave a short vertical smear read from C along their scroll direction.
- Floor fixes: `pow` NaN in scan bar; speed mapping extrapolates past 300 strips → clamp; unbounded `yOffset` → `fract` per strip on a wrapped time; half-texel; ACES; add `updatedParams`.
- A PACKING: pre-ACES linear RGB + alpha; C read as colour.

