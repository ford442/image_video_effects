# Agent Notes: ascii-glyph (Batch 19, Interactivist)

## Line counts
- WGSL: **101 → 169** (+68, target range 151–191 ✓)
- JSON: 55 → 89 lines (only `updatedParams` + `updated: true` appended)

## Per-slider mapping (saved-preset contract preserved — no renames/re-defaults)

| Slider | JSON id | Binding | Role in WGSL |
|---|---|---|---|
| 0 | glyphSize | `u.zoom_params.x` | Base glyph cell edge in px: `mix(4.0, 32.0, x) * bass_env(bass, mids)` — unchanged role; now `var` so the mouse lens can locally divide it (`/ (1.0 + lensBoost * 1.5)`) |
| 1 | brightness | `u.zoom_params.y` | Final glyph intensity multiplier on `finalRGB` and alpha — unchanged |
| 2 | colorAmount | `u.zoom_params.z` | Mix between ice-white ink `(0.8, 0.9, 1.0)` and source-image color with treble lift — unchanged |
| 3 | densityBoost | `u.zoom_params.w` | Pushes faint cells over the character threshold in `charDensity` smoothstep — unchanged |

## Techniques implemented
1. **Spring-damper mouse lens (priority 1):** `zoom_config.yz` was previously unused. Added a persistent eased lens center + velocity in `extraBuffer[133..136]` (semi-implicit spring, k=0.14, damping=0.78; first-frames snap guard). Aspect-corrected distance (`* vec2(aspect, 1.0)`) with `smoothstep` falloff over ~0.3 radius drives `mouseMask`; lens locally shrinks `glyphSize` (denser, finer glyphs) and lifts `charDensity` (+0.3 clamped) so the image resolves into finer type under the pointer.
2. **MouseDown tighten:** `zoom_config.w` (mouseDown) narrows lens radius 0.30→0.22 and boosts lens strength ×1.5 while held.
3. **Click ripple scrambles:** loop over `u.ripples` guarded by `min(u32(u.config.y), 50u)`; each live ripple contributes `rippleAge * rippleBand * fade` (expanding ring at 0.45/s, 0.08 band width, ~1.2s fade) into `scrambleSeed`, which is added into the `glyphPattern` hash seed so cells in the band flip characters chaotically. A cool-cyan `scrambleFlash` tint makes the scatter visible. With zero ripples the seed addition is exactly 0.0 — output identical to pre-upgrade.
4. **Stale comment fixes (comment-only):** `config.y` = RippleCount (was "ClickCount"), `zoom_config.w` = MouseDown (was "Generic2"), header Category = geometric (was "stylize"), header Features now lists mouse-driven; added Batch 19 upgrade note.

## VERBATIM-preserved structures
- `hash12` helper — byte-identical
- `bass_env` helper — byte-identical
- Depth-luminance tiering: `let depthLuma = mix(luma, luma * (1.0 - depth), 0.3);` — verbatim
- Bass beat-swap: `let beatSwap = hash12(cell + vec2<f32>(floor(bass * 5.0), 0.0));` — verbatim
- Cross/dot SDF glyph select: `let glyphShape = select(1.0 - smoothstep(0.0, 0.15, crossDist), 1.0 - smoothstep(0.0, 0.2, dotDist), glyphPattern > 0.5);` — verbatim
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, `textureSampleLevel(..., 0.0)` reads, all three writes (`writeTexture`, `writeDepthTexture`, `dataTextureA`) every frame; `dataTextureA` stays DISPLAY color.

## JSON changes
- `shader_definitions/geometric/ascii-glyph.json`: added ONLY the `updatedParams` array (index 0–3, names/defaults/min/max/step exactly per brief) and `"updated": true`. Validated with `json.load`. No other changes.

## Deviations from the brief
- None. extraBuffer usage confined to [133..136] ⊂ [133..255]; [0..4]/[5..132] untouched.

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/ascii-glyph.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/ascii-glyph.wgsl — naga OK, bindgroup compatible
```
GREEN — 0 warnings, 0 extraBuffer violations.
