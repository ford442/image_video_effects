# Notes — glitch twelve (2026-10-27)

Prelude migration on all twelve is infrastructure. `Upgraded:` dates are for the ideas below. Saved `params` were not edited.

## scanline-tear

Kept: field phase, comb, H/V roll zones, YIQ burst rotation, C field mix, spring, click punch. Params unchanged.
A packing: ACES display RGBA. C is colour.
In the diff: `serration` inside the H-sync roll (§12.2B sync-pulse); chroma sample left of luma inside the burst block (§12.2B chroma delay). Both scale with the sliders that already owned those errors (defaults are 0).

## vhs-jog

Kept: shuttle, tracking offset, cue bars, pause flutter, reverse chroma rotation, C max-hold streak.
A packing: pre-ACES linear RGB + alpha. ACES on the display write.
In the diff: `headSwitchBand` snow on the bottom rows; `vertical_tracking * (1.0 - uv_raw.y)` flag skew. No formula row.

## vhs-tracking-mouse

Kept: dash cells, detune, auto-track lock, AGC, click tears.
A packing: ACES display RGB + source alpha. C unread.
In the diff: `trackSlip` on `sampleUV.y`; `overscan` bar from `blankSide`. No formula row.

## strip-scan-glitch

Kept: hashed strip speed, blanking seam, held brake, C streak.
A packing: pre-ACES linear RGB + alpha. ACES on the display write.
In the diff: `slitAmt` 3-tap along scroll; `stripEdge` neighbour mix scaled by RGB Split. No formula row.

## sliding-tile-glitch

Kept: row/column choice, spring, click rings, chromatic tear, neon line, C feedback weight.
A packing: pre-ACES linear RGB in A. ACES on the display write. (The old header said ACES display RGBA; A was already the pre-ACES `hdr`.)
In the diff: `unshifted` mixed under `gridLine`; `restoreSpatial` replaces the uniform `(1.0 - restoration * 0.5)` damp. No formula row.

## data-stream-corruption

Kept: column rain, block displace, RGB split, green overlay, persistence. A is still `(corruption, 0, 0, alphaHistory)`.
C is now `textureLoad` (it was a filtering sample).
In the diff: `headGlow` / `tailFade` (§ none); held mix toward 1 inside the brush (§12.2C dwell). Display write is ACES. Bass speeds the rain; treble fills characters.

## rgb-split-glitch

Kept: Y/Cb/Cr temporal mix, herringbone, 8×8 ringing, mouse bleed, A delay packing, B diagnostic.
C is now `textureLoad`.
A packing: `(Y, block Cb, block Cr, delayed Cr)`. ACES on the display write only.
In the diff: `hanging` on odd lines; `crawl` added to the existing herringbone phase. Angle Offset is still the temporal mix. No formula row.

## digital-compression

Kept: block-corner DC, posterize, chroma floor, focus spring, click clear. A is still the diagnostic tuple. C stays unread.
In the diff: `acQuant` from Bit Crush (§12.2B DCT quantization); `mosquito` on the existing `edge`. Display is clamped before ACES.

## interactive-glitch-brush

Kept: spring, grenades, scan head, conveyor, oil-slick, C mix.
A packing: pre-ACES linear RGBA. ACES on the display write so the C mix is not tone-mapped twice.
In the diff: `strokeRadius = brushSize / (1 + speed)` (§12.2C speed-thinning); `snappedX` on the tear. Grenades still use the base brush size.

## interactive-glitch

Kept: block pulse, chromatic shift, click fronts, the four param roles.
A packing: pre-ACES RGB + Schmitt latch in A.a. Display alpha is still offset coverage. ACES on the display write.
In the diff: `lock` from C.a (§12.2B Schmitt); `rowV` quantizes the scan packet.

## interactive-glitch-cubes

Kept: face UV, grout slick, conveyor, click front, shadow branch. A is still `[linear rgb, settledHeight]`.
In the diff: `shade` from `posOnFace.y * height`; `wall` ring outside the face. Display write is ACES. No formula row.

## glitch-cathedral

Kept: 4-coefficient DCT, Floyd–Steinberg taps, 8px lead, rose shape, click fractures. A is still quant error + lead.
Cell Size at the default of 20 still drives full quant (`cellPx / 20`). Pattern Speed at 0.5 still runs the rose at the old rate (`* 2`).
In the diff: `came` every `cellPx`; `split` from RGB Split, stronger near the pointer; `sortPick` from Sort Strength. No formula row. The three previously dead sliders are read.
