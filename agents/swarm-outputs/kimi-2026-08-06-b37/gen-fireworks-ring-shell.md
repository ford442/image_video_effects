# gen-fireworks-ring-shell — VISUALIST upgrade note (Batch 37, tracker #334)

## Weaknesses found
- **Known bug class confirmed**: `mouseUV = (u.zoom_config.yz - res*0.5) / min(res.x, res.y)` treated the already-normalized 0–1 mouse UV as pixel coordinates — mouse halo was hopelessly off-screen. Fixed to `(u.zoom_config.yz - 0.5) * res / min(res.x, res.y)` (fan-shell sibling convention).
- **Flat depth**: `writeDepthTexture` wrote literal `0.0` every pixel.
- **LDR-leaning bursts**: core flash topped out ~1.5× and palette colors clamp to [0,1]; no deliberate overbright (>1.0) cores for ACES to roll off.
- **No atmosphere**: empty sky stayed pure black-blue; bursts had no ambient halo or fog, so the image lacked depth cues.
- **`mids` channel unused** (only bass/treble were read).

## Techniques applied (Visualist domain)
1. **HDR overbright burst cores + two-layer glow**: core flash boosted to `hexBokeh(..., 2.2 + bass)` with a warm white-hot tint `(1.0, 0.97, 0.9)`, and every ring spark gets a quadratic hot-core term `onRing² * (1.1 + treble*0.5)` pushing bright sparks >1.0 before ACES.
2. **Audio-reactive color temperature**: `warmth = clamp(bass*0.5 - treble*0.35, -1, 1)` scales R/B channels pre-tonemap (bass warms, treble cools); `mids` now also drives haze intensity.
3. **Atmospheric burst haze + depth fog**: per-shell ambient halo `exp(-d*2.6)` tinted by that shell's hue, plus a cool blue haze `(0.010, 0.013, 0.030)` that settles wherever generated depth says "far" (no spark heat).
4. **Real generated depth**: accumulated `heat` from every glow contribution → `depth = clamp(1 - exp(-heat*1.5), 0, 1) * 0.85`.

## Slider wiring (all 4 live, shader-specific)
- p1 **Ring Radius** → ring expansion radius `ringR` (unchanged semantics).
- p2 **Thickness** → angular jitter of ring sparks AND now also the spark glow-kernel width `(0.75 + thick*3.0)`.
- p3 **Spark Count** → per-shell spark count `n` and energy boost (unchanged semantics).
- p4 **Color Cycle** → palette offset for ring/inner/halo sparks AND the per-shell haze hue.

## Contract compliance
- Canonical 13 bindings verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples`. ✅
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✅
- `writeTexture`, `writeDepthTexture` (real generated depth, not flat-0.0), `dataTextureA` written every frame (`dataTextureB` persistent buffer also kept). ✅
- Audio only from `plasmaBuffer[0].xyz` (bass/mids/treble); no hash-based fake spectrum. ✅
- Feedback reads via `textureLoad(dataTextureC, pixel, 0)` only. ✅
- Semantic alpha: `clamp(length(col)*1.2 + 0.1, 0.12, 0.96)` — intensity-based, never hardcoded 1.0. ✅
- No extraBuffer writes at all; no `textureSample`/`dpdx`/`tan`. ✅
- JSON: `updatedParams` byte-exact vs `git show HEAD:` (verified identical); only `description` appended and `features` populated (additive). ✅

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files ...` → **PASS** (naga OK, bindgroup compatible, exit 0).
