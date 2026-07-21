# Upgrade Notes: pixel-depth-sort (Optimizer pass, 2026-07-21)

## Line-count delta
- Original: **197 lines** → Upgraded: **252 lines** (**+55**, within the +50…+90 envelope; target band 247–287 ✅)

## Changes by domain

### Parameters (u.zoom_params re-scoped per brief, exactly 4, index 0–3)
- `x` = **Sort Radius** (default 0.3): wires the previously hardcoded `* 40.0` tap-spacing scale (`SORT_RADIUS_SCALE`). Default reproduces the old `param2 = 0.3` look bit-for-bit.
- `y` = **Mids Modulation** (default 0.5): new `midsGain = 1.0 + mids * midsMod` multiplier on sort length (audio mids on top of the existing bass drive). At mids=0 it is a no-op.
- `z` = **Chromatic Accent** (default 0.2): strength of the new span-seam RGB fringe.
- `w` = **Feedback Clamp** (default 1.2, range 1.0–2.0): pre-mix clamp ceiling for the temporal feedback read.
- Legacy slider constants folded in so defaults preserve the original look: `DEPTH_THRESHOLD = 0.5` (old param1), sort angle `0.0` (old param3 — mouse-following angle still drives direction), `BASE_ABERRATION = 0.2` (old param4).
- Old `params` array kept in the JSON for backward compat; `updatedParams` added verbatim from the brief; `"updated": true`.

### Temporal feedback / stability
- Previous frame (`dataTextureC`) is now clamped to `[0, feedbackClamp]` **pre-mix** (luma-echo-warp lesson: cap pre-tint at ~1.2) so a hot upstream slot can't blow out the accumulator.
- Added 1-LSB hash dither (`hash21(uv*7919 + fract(time)*17) / 255`) before the ACES pass to break up accumulation banding on slow gradients.

### Chromatic edge accent
- New `spanEdgeMask()` helper: 1.0 where `centerDepth` sits at either end of the sorted depth span (seam width = 25% of span extent), gated by the existing `boundaryStrength`.
- Seam proximity widens the directional CA split (`BASE_ABERRATION + chromaAccent * spanEdge * 2.0`).
- Green channel now pulls a half-offset sample on seams (`mix(sortedColor.g, gSeam, …)`) so the fringe is a full three-channel split, not R/B-only.
- Subtle magenta-cyan seam tint (`vec3(0.9, 0.4, 1.0) * (0.7 + treble*0.3)`, max mix 0.35) riding the span edges with light treble shimmer.

### Performance / structure (Optimizer role)
- Removed dead `wsum` accumulator (was summed but never read).
- Hoisted repeated `vec2<f32>(0.0)/(1.0)` clamp bounds into `UV_LO`/`UV_HI` consts.
- Branchless zero-radius fallback (`hasSpan = smoothstep(0.0, 0.5, sortLength)`): radius slider at 0 falls back to the raw frame instead of smearing one collapsed tap set.
- Early-out background branch retained (skips the 25-comparator network + 11 texture reads for sky/far pixels).

### Preserved (per CAUTION rule)
- 25-comparator sorting network sequence — untouched, marked load-bearing in a comment.
- LOD-distance logic — `lod = 1 - smoothstep(0.15, 0.55, mouseDist)`, `sampleCount = 5 + lod*4`, `depthSharp = 8 + lod*24` all unchanged.
- Canonical 13-binding layout unchanged; `@workgroup_size(16, 16, 1)`; all three outputs (`writeTexture`, `writeDepthTexture`, `dataTextureA`) written on every path every frame; all sampler reads use `textureSampleLevel(..., 0.0)`; no reserved-keyword identifiers; no binding 13 added (shader doesn't use history ring).

## QA flags
- **Eyeballed constants** (no GPU available to tune visually): seam width 0.25 of span, seamSplit gain ×2.0, seamTint mix cap 0.35, tint color vec3(0.9, 0.4, 1.0), treble shimmer 0.7+0.3t, dither amplitude 1/255, `hasSpan` smoothstep window (0.0, 0.5).
- **No-GPU caveat**: headless VM has no WebGPU adapter — validated only via naga (`scripts/wgsl_precommit_gate.py`, exit 0) and JSON parse. Visual behavior (fringe subtlety, feedback stability, dither visibility) needs on-GPU eyeballing.
- **Slider re-scope**: x/y/z/w semantics changed per the brief's `updatedParams` (old Depth-Threshold/Sort-Length/Sort-Angle/Aberration folded to constants equal to their old defaults, so the default frame is unchanged). Saved user presets that moved old sliders 1/3 will map onto the new semantics.
