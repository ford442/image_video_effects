# notes — vhs-chroma-bleed (Idea Card #1)

Files: `public/shaders/vhs-chroma-bleed.wgsl`, `shader_definitions/image/vhs-chroma-bleed.json`

## Kept verbatim
Barrel `crtK = -0.06`; per-row `microJitter`; `tapeTracking` wobble + bass dropout; `compressionArtifacts` block brightness;
`noiseBands`; `vhsScanlines` / `vignette` / `analogWarmth` / `saturationRolloff` helpers; `vhsChromatic` per-channel delay; the
R/G/B split sampling at `rOff/gOff/bOff`; mids flash; mouse jitter nudge; depth scatter. Slider roles unchanged: x = bleed
strength, y = jitter (now also grain), z = drift speed, w = rgb shift (now also colour-under width).

## A packing
`ACES display RGB + source alpha`. No C read (unchanged from HEAD, which also never read C). HEAD wrote premultiplied
`rgb*alpha`; now straight RGB with semantic alpha.

## Ideas (line ranges in the WGSL)
1. **Colour-under bandwidth** — lines 217–238. `rgbToYcc` / `yccToRgb` helpers (lines 121–133). The R/B-bled pixel is split
   into Y + CbCr; chroma is replaced by a 7-tap horizontal box of the source taken to the RIGHT of the luma position
   (`chromaDelay` = 2.5–4 px × Bleed Width, `tapStep` = 1.4–2.6 px × Bleed Width), mixed at 0.45+0.2·w (0.65 at default).
   Luma stays the sharp per-channel-shifted value.
2. **Cross-colour rainbow crawl** — lines 240–248. |dY/dx| from taps 2 and 4 of the box gates a false-colour leak whose hue
   angle rotates at 0.7 rad/s and varies with row (`uv.y*28`); amplitude 0.10+0.05·bleed, scaled by Bleed Width.
3. **Chroma loss in dropout rows** — lines 250–260. `chromaDropRow` = 2.5 % of rows at rest (+bass·0.15, same `lineHash` as the
   HEAD luma dropout) go grey (CbCr → 0) from a hashed per-row start column (0–35 % of width) with ±3 % per-frame rag.

## Floor fixes
- `vignette`: `pow(1-r*s, 2)` → `max(...,0)` squared (lines 91–96); NaN guard.
- Noise slider (y) now scales grain: `grain * jitterAmt * 0.4` (line 266) = HEAD's fixed 0.08 at default 0.2.
- Dropout row hash gets time: `hash21(floor(time*24), row)` (line 182) — HEAD's rows were static.
- Alpha = source alpha (`gSample.a`, lines 209–211, 291) instead of luma+bleed.
- ACES on display and on A (line 293–295). Header rewritten in CONTRACT format (Category `image` to match the JSON folder;
  HEAD said `retro-glitch`).
- No extraBuffer reads/writes (HEAD had none either). Audio only `plasmaBuffer[0].xyz`.

## Deviations from the card
- Card says "dropout rows" for idea 3, but at HEAD the only dropout rows are bass-driven (`step(1 - bass*0.15, ...)`), i.e. none
  at rest. I added a 2.5 % resting rate for the chroma-only drop so the idea is visible without audio; the luma/bleed dropout
  keeps its bass-only gate. This is a small deliberate base-look change (thin grey rows at rest).
- ACES changes the tone curve slightly vs HEAD's unmapped clamp (standard for the batch).

## JSON
- `params` byte-exact (python diff of the sorted array before/after: identical).
- Added `updatedParams` (4 entries, index/name/default/min/max/step copied from `params`) — HEAD had none.
- `description` rewritten to name the three ideas.
- `features`: added `mouse-driven` (pointer nudges jitter; true at HEAD too). `upgraded-rgba` / `audio-reactive` kept.

## Gate / audits
- `wgsl_precommit_gate.py --files public/shaders/vhs-chroma-bleed.wgsl`: PASS (naga OK, bindgroup compatible, 0 extraBuffer
  violations).
- `audit_extrabuffer.py --files ...`: PASS (0 violations).
- `audit_dead_sliders.py --files vhs-chroma-bleed`: PASS (0 new dead sliders).

## GPU risks (no WebGPU on this VM — nothing was viewed)
- 7 extra texture samples per pixel (colour-under box) — fine for a post filter.
- The colour-under mix (0.65 at default) visibly softens saturated edges; that is the idea, but strength may want tuning on a
  real GPU. `colourUnderMix` is clamped ≤ 0.9 at w = 3.
- Cross-colour leak is gated by a gradient estimate over ~3 px; on very high-res inputs the `*6.0` normalisation may need
  raising to make it visible.
