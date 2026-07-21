# Upgrade Notes: luma-pixel-sort (Optimizer pass, 2026-07-21)

## Line-count delta
- Original: **207 lines** → Upgraded: **262 lines** (+55, within the +50…+90 brief window)

## Changes by domain

### Params / slider wiring (exactly 4, index 0–3)
- `zoom_params.x` — **Luma Threshold** (unchanged semantics, default 0.5)
- `zoom_params.y` — **Sort Length** (unchanged semantics, default 0.3)
- `zoom_params.z` — **Sort Angle** (NEW; 0–1 → 0–180°, rotates the Fibonacci disk sampling axis via a `rotateOffset` helper; angle 0 = identity rotation, so the default preset reproduces the classic look)
- `zoom_params.w` — **Palette Mix** (NEW; cosine-palette tint strength on sorted spans, 0 disables, default 0.3)
- Retired sliders became tuned constants: `DEPTH_BLEND = 0.5`, `NOISE_MIX = 0.3` (their old defaults, eyeballed as sensible midpoints). The legacy `params` array in the JSON is untouched; only `updatedParams` reflects the new roles, exactly as the brief specified.

### Audio reactivity
- Bass now smoothly lowers the luma threshold: `bassDrop = smoothstep(0.15, 1.2, bass) * 0.2`, added to the existing treble/mids terms (`threshold - treble*0.25 - mids*0.1 - bassDrop`). Beats extend sorted spans into darker material without twitchiness (smoothstep shaping instead of a raw linear term).
- Existing bass-driven sort-radius boost (`1.0 + bass * 0.3`) and mouse proximity boost left intact.

### Color / polish
- Added IQ-style `cosinePalette(t)` helper (`a + b*cos(TAU*(c*t+d))`, d = 0.00/0.33/0.67).
- Tint is keyed by sorted-span luma (`fract(luma(sortedRGB) + time*0.05)`) and brightness-preserving (`paletteRGB * max(luma, 0.05)`).
- Tint is gated by span width (`smoothstep(0.02, 0.35, lumas[8]-lumas[0])`) so flat regions stay clean, and scaled by `paletteMix * sortFactor`. Palette Mix = 0 fully disables it.

### Performance / structure
- Loop invariants (`sortAngle`, `noiseScale`) hoisted above the sampling loop; per-iteration cost is one extra `rotateOffset` (cos/sin hoisted by being called on constants per-frame — the rotation trig is computed per sample but on a uniform angle; cheap).
- All three early exits unchanged: background/depth mask, dark-pixel threshold exit, zero-radius exit.
- **25-comparator sorting network untouched** — compare-exchange sequence and layer structure byte-identical; only a "DO NOT MODIFY" comment added.
- Canonical 13-binding layout unchanged, `@workgroup_size(16, 16, 1)`, all paths write `writeTexture` + `writeDepthTexture` + `dataTextureA` via `writeOutputs`, all sampler reads use `textureSampleLevel(..., 0.0)`, depth via `textureLoad`.

## QA flags
- **Eyeballed constants** (no GPU available to tune visually): `BASS_THRESHOLD_DROP = 0.2`, bass smoothstep edges (0.15, 1.2), `SPAN_TINT_LO/HI = 0.02/0.35`, palette phase offsets (0.0/0.33/0.67), palette time drift `time * 0.05`. All are conservative mid-range values; defaults (angle 0, palette 0.3) keep the look close to the original.
- **No-GPU caveat**: validated via `wgsl_precommit_gate.py` (naga OK, bindgroup compatible) and JSON parse only. Visual behavior (span steering, palette grading, bass threshold drop) has NOT been eyeballed on a real adapter — recommend a quick visual pass on GPU hardware.
- **Slider semantics note**: params index 2/3 changed role (Depth Blend → Sort Angle, Noise Mix → Palette Mix) per the brief's `updatedParams`. Saved presets using old index 2/3 values will reinterpret them as angle/palette; defaults chosen so this is visually benign.
- **Gate result**: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/luma-pixel-sort.wgsl` → exit 0, 1 passed / 0 failed / 0 warnings.
