# Idea Cards — Grok (glitch twelve, 2026-10-27)

Written before WGSL edits. Twelve existing glitch shaders. Each card adds **two or three** new ideas on the current kernel. Earlier ideas stay. Saved `params` stay byte-exact (ids, names, defaults, min/max/step). No shared spring, ripple stamp, or IQ palette.

Formula rule: each §12.2 row is used on **one** file.

All twelve paste the binding header. Migrating them to `#include "_prelude.wgsl"` is infrastructure and is not one of the ideas.

`glitch-cathedral` reads only `zoom_params.x`, and that read clamps a 2..200 cell size into 0..1, so the default of 20 is stuck at full quant. The other three sliders are the triaged dead set (`rgbSplit`, `sortStrength`, `patternSpeed`). Wiring them is the upgrade, and the default of 20 still drives full quant.

---

## scanline-tear

IDENTITY: an NTSC picture with interlaced fields, H/V sync tears, and a colour-burst phase error.
KEEP VERBATIM: Interlace Strength / HSync Error / VSync Error / Color Burst Error; field phase and comb; the roll zones; YIQ burst rotation; exact C field mix; the existing spring and click sync punch.
MECHANISM:
- tactic 2: a lost H-sync resets at the left edge of the line. The tear here is a sine, so it has no sync edge.
- tactic 3: `colorBurstError` rotates chroma and then throws away the fact that composite chroma is a delayed line.
- tactic 6: C stays the previous display colour. Neither idea stores a new channel.
ADD:
  1. Sync-pulse serration — inside the existing H-sync roll, add a saw that resets at the left edge. HSync Error still sets the amount.
  2. Chroma delay line — luma stays on the current sample, chroma comes from a few texels to the left. Color Burst Error still sets the distance and still rotates phase.
FORBID: a second roll system, dropout dashes (the tracking shader owns those), a new spring.
A PACKING: ACES display RGBA, same as today. C is read as colour.
FORMULA: sync-pulse timing (§12.2B); chroma delay line (§12.2B). Only this file.

## vhs-jog

IDENTITY: a jog/shuttle deck. Mouse X is cue, review, and pause; mouse Y is tracking; clicks slip the tape.
KEEP VERBATIM: Static Noise / Dist. Freq / Color Bleed / Scanlines; shuttle from mouse X; tracking from mouse Y; cue bars; pause field flutter; reverse chroma rotation; max-hold streak from C.
MECHANISM:
- tactic 2: a real head switch dumps a noise bar at the bottom of the field. This shader rolls the head but never shows that bar.
- tactic 5: tracking error flags. The top lines skew more than the bottom. Mouse Y is a uniform vertical offset today.
- tactic 6: both ideas are display-only. A stays pre-ACES linear colour.
ADD:
  1. Head-switch noise band — a short snow bar on the bottom rows, present only while the shuttle is up. Cue bars stay evenly spaced and keep scrolling.
  2. Tracking flag skew — mouse Y shifts the top of the frame sideways and the shift falls off toward the bottom. The vertical tracking offset stays.
FORBID: chroma-delay (scanline-tear owns it), pause logic changes, a spring.
A PACKING: pre-ACES linear display RGB + alpha. ACES on the display write only.
FORMULA: none.

## vhs-tracking-mouse

IDENTITY: one horizontal tracking-noise band at the pointer, with dash dropouts, an X tracking knob, and AGC in the band.
KEEP VERBATIM: Bar Height / Distortion Strength / Static Noise / Color Split; dash cells; detune from mouse X; held auto-track lock; AGC lift; click tears.
MECHANISM:
- tactic 2: a mistracked head reads the adjacent track, so the picture in the band slips vertically, and the side it left shows blanking.
- tactic 3: `detuneLive` only widens the band and lengthens dashes. The sample Y never moves.
- tactic 6: no C read today, and neither idea needs one.
ADD:
  1. Adjacent-track slip — inside the band, the sample shifts vertically by the detune, in the direction of the knob.
  2. Overscan blanking — the side the head left goes black inside the band. Width follows detune. Centred X stays clear.
FORBID: dash-noise changes, chroma-delay, storing a latch, a spring.
A PACKING: ACES display RGB + source alpha. C stays unread.
FORMULA: none.

## strip-scan-glitch

IDENTITY: vertical strips that scroll at hashed, brightness-weighted speeds, with a blanking seam, a held brake, and a speed streak.
KEEP VERBATIM: Strip Count / Scroll Speed / Glitch Jitter / RGB Split; per-strip hash speed; blanking bar and ticks; held brake from C; speed-streak ghost from C.
MECHANISM:
- tactic 2: a slit-scan camera integrates a finite slit. These strips sample one row.
- tactic 5: neighbouring slits leak at the boundary. RGB split offsets channels inside one strip and never crosses the edge.
- tactic 6: C stays the brake and the streak. The new taps are source samples.
ADD:
  1. Slit integration — fast strips average a few source rows along the scroll. Slow strips stay sharp. The C streak stays a separate ghost.
  2. Inter-strip leak — the strip edge mixes the neighbour strip, scaled by RGB Split.
FORBID: a new brake, a seam rewrite, chroma-delay.
A PACKING: pre-ACES linear display RGB + alpha. ACES on the display write only.
FORMULA: none.

## sliding-tile-glitch

IDENTITY: grid tiles that slide on row or column conveyors near the cursor, with a chromatic tear and a restoring decay.
KEEP VERBATIM: Grid Size / Slide Amount / Chaos / Restoration; row-vs-column direction; spring cursor; click rings; chromatic tear; the neon grid line; C feedback weight.
MECHANISM:
- tactic 3: `cellEdge` draws neon and never shows what the tile slid away from.
- tactic 4: Restoration is one scalar on every tile. Tiles far from the pointer should settle first.
- tactic 6: C stays the feedback colour. No new channel.
ADD:
  1. Grout of the unshifted photo — the existing grid line reveals the sample at the unmoved UV, under the neon.
  2. Distance-weighted restoration — Restoration damps tiles by how far they are from the pointer. Near tiles keep the full slide.
FORBID: a second grid, an IQ palette change, Schmitt state, a new spring.
A PACKING: pre-ACES linear RGB in A, ACES on the display write. Same roles as today.
FORMULA: none.

## data-stream-corruption

IDENTITY: vertical character streams; the pointer paints a corruption field that persists and then eats the photo.
KEEP VERBATIM: Stream Speed / Brush Size / Glitch Intensity / Persistence; column hash rain; block displace; RGB split; green stream overlay; A is `(corruption, 0, 0, alphaHistory)`.
MECHANISM:
- tactic 2: a rain column has a bright head and a tail. `isChar` is flat along the column.
- tactic 3: the brush adds the same amount whether the pointer is passing or held.
- tactic 6: C is the corruption field. Dwell writes that same field. The filtered C sample becomes an exact load.
ADD:
  1. Rain head and tail — the head of each column is bright and the characters fade down the tail. Stream Speed still sets the fall.
  2. Dwell pressure — a held pointer inside the brush climbs corruption toward full. A passing pointer keeps the old add.
FORBID: a new solver, a spring, writing display colour into A.
A PACKING: raw `(corruption, 0, 0, alphaHistory)`. ACES on the display write only.
FORMULA: dwell pressure (§12.2C). Only this file.

## rgb-split-glitch

IDENTITY: a 4:2:0 composite split — full-res luma, half-res chroma, temporal chroma delay, herringbone alias, and block ringing.
KEEP VERBATIM: Split Dist / Angle Offset / Jitter Noise / Radius and their current roles (glitch amount, temporal chroma mix, alias severity, mouse bleed radius); the Y/Cb/Cr delay packing in A; the B diagnostic write.
MECHANISM:
- tactic 2: a composite edge grows hanging dots where a luma step meets a chroma cell. `freqMeasure` is computed and only tints the herringbone.
- tactic 5: the herringbone is a continuous field. Real chroma crawl flips phase every scanline and walks upward.
- tactic 6: A stays the delay state. Crawl and dots are display-only.
ADD:
  1. Hanging dots — on alternate lines, a luma step adds a one-pixel chroma error. Jitter Noise scales it.
  2. Chroma crawl — the existing herringbone gains a per-line phase flip and a slow upward drift from Jitter Noise.
FORBID: a spatial chroma-delay line (scanline-tear owns that row), rewiring Angle Offset off the temporal mix, ACES into A.
A PACKING: A is `(Y, block Cb, block Cr, delayed Cr)`. B stays the diagnostic. ACES on the display write only. C is an exact load.
FORMULA: none.

## digital-compression

IDENTITY: YUV macroblock crush with a focus window that stays clear near the pointer.
KEEP VERBATIM: Block Size / Bit Crush / Artifacts / Focus Radius; the block-corner sample; posterize; chroma floor; focus spring; click clear; A stays `(influence, artifact, blocks, alpha)` and C stays unread.
MECHANISM:
- tactic 1: the block is a single copied texel. JPEG keeps a quantized AC residual inside the block.
- tactic 5: mosquito noise lives on the block edge this file already measures.
- tactic 6: no history. Both ideas are display-only.
ADD:
  1. AC quantization — the pixel-minus-DC residual is rounded to a step from Bit Crush, then added back. Flat blocks remain when Bit Crush is off.
  2. Mosquito noise — a short-lived grain on the existing block edge, scaled by Artifacts.
FORBID: macroblock motion carry, a datamosh smear, writing colour into A.
A PACKING: unchanged diagnostic tuple. ACES on the display write only.
FORMULA: block DCT quantization (§12.2B). Only this file.

## interactive-glitch-brush

IDENTITY: a sprung brush that tears blocks under the cursor, with click grenades and a scan-head line.
KEEP VERBATIM: Brush Size / Glitch Intensity / Block Scale / Color Split; the spring in `extraBuffer[133..136]`; grenades; scan head; conveyor; oil-slick phosphor; C persistence.
MECHANISM:
- tactic 2: a fast stroke is thinner. Brush Size ignores the spring velocity this file already integrates.
- tactic 7: the tear offset is sub-pixel. The block grid is already computed and not applied to the sample.
- tactic 6: C stays the previous linear colour.
ADD:
  1. Speed-thinning — radius divides by `1 + k·|spring velocity|`. Brush Size stays the base width.
  2. Block-snapped tear — the horizontal offset lands on the block grid. Block Scale still sets the cell.
FORBID: dwell (data-stream owns it), a new spring, more oil-slick.
A PACKING: pre-ACES linear display RGBA. ACES on the display write only, so C is not tone-mapped twice.
FORMULA: speed-thinning (§12.2C). Only this file.

## interactive-glitch

IDENTITY: pulsing blocks that slide and tear, stronger inside the pointer radius, with a traveling scan packet.
KEEP VERBATIM: Base Intensity / Influence Radius / Glitch Speed / Block Size; the block pulse; chromatic shift; the scan packet; click fronts.
MECHANISM:
- tactic 2: a block that crosses the glitch threshold should stick until the pulse falls, not flicker off the same frame.
- tactic 7: the scan packet is a smooth sine. The block size is already a row pitch and is not used on that sine.
- tactic 6: C is unread. The latch fits in A.a because display alpha is a separate coverage value.
ADD:
  1. Schmitt block latch — a block that crosses the high pulse stays torn until the pulse drops below the low threshold. The latch is A.a.
  2. Row-quantized scan — the scan packet is evaluated on the block row, so the tear is a strip of blocks.
FORBID: a spring, a second block grid, chroma-delay.
A PACKING: A is pre-ACES RGB + latch in A.a. Display alpha stays the offset coverage. ACES on the display write only.
FORMULA: Schmitt-trigger lock (§12.2B). Only this file.

## interactive-glitch-cubes

IDENTITY: image-mapped cubes that extrude toward the pointer, with grout, a shadow, and a settled height in C.
KEEP VERBATIM: Cube Size / Extrusion Height / Grid Gap / Shadow Strength; the face UV; grout slick; conveyor; click front; A is `[rgb, settledHeight]`.
MECHANISM:
- tactic 2: an extruded face is brighter on top. Height is computed and only added as a flat lift.
- tactic 3: the margin between the base footprint and the grown face is empty. That margin is the side wall.
- tactic 6: height stays in A.a. Neither idea repacks it.
ADD:
  1. Height bevel — the face shades by its own height, lighter toward the top edge.
  2. Extruded side wall — the ring just outside the face samples the tile, darkened, so the cube has thickness. Shadow Strength still darkens the cast shadow.
FORBID: a new solver, more oil-slick, writing height into the display alpha.
A PACKING: A stays `[linear rgb, settledHeight]`. ACES on the display write only.
FORMULA: none.

## glitch-cathedral

IDENTITY: an 8×8 DCT stained-glass quantizer with Floyd–Steinberg error through C, lead lines, and a rose-window pulse.
KEEP VERBATIM: the 4-coefficient DCT and its quant floor; Floyd–Steinberg taps; rose pulse; lead lines; click fractures. Cell Size still drives quant, and at the default of 20 the quant matches today's clamped-to-1 result. Pattern Speed scales the existing rose rate so the default 0.5 keeps today's speed.
MECHANISM:
- tactic 4: Cell Size is a 2..200 pixel pitch and is only a clamped quant knob. RGB Split, Sort Strength, and Pattern Speed are unread.
- tactic 5: the description's channel split and pixel sort are the artifacts of this glitch and they are absent.
- tactic 6: A stays the quant-error field. The new mixes are display-only.
ADD:
  1. Cell-pitch cames — a darker lead every Cell Size pixels, on top of the 8px DCT lead.
  2. Pointer RGB split — RGB Split offsets R and B, stronger near the pointer.
  3. Row pixel-sort — Sort Strength pulls a pixel toward the brighter neighbour along the row, stronger near the pointer.
FORBID: changing the DCT size, a spring, storing sort state in the error field.
A PACKING: A stays quant error in RGB and lead in A.a. ACES on the display write only.
FORMULA: none.
