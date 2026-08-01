# Agent Notes: digital-reveal (Batch 19)

**Agent role:** Algorithmist
**Date:** 2026-07-31
**Brief:** `swarm-tasks/kimi-briefs-2026-07-31-b19/digital-reveal.md`

## Line counts

- **Before:** 102 lines
- **After:** 166 lines (+64, inside the +50..+90 window; target 152–192 ✓)

## Per-slider mapping (saved-preset contract preserved — no renames/re-defaults)

| Slider | JSON id | Uniform | Shader role (unchanged) |
|---|---|---|---|
| Rain Density | `density` | `u.zoom_params.x` | `density = x * bass_env(bass, mids)` → rain grid column count (`gridSize`) + white-drop odds threshold |
| Reveal Size | `size` | `u.zoom_params.y` | `revealSize` → spring-brush radius (`brushRadius = revealSize * 0.3 + 0.05`) |
| Trail Fade | `fade` | `u.zoom_params.z` | `trailFade` → mask persistence (`fadeFactor = 0.8 + trailFade * 0.19`) |
| Rain Speed | `speed` | `u.zoom_params.w` | `rainSpeed = w * (1.0 + treble * 0.5)` → glyph fall rate (`colSpeed`) |

All four were already honestly wired; roles kept EXACTLY per the CAUTION list.

## Techniques implemented

1. **Spring-damper reveal brush (priority 1):** critically-damped spring (`stiffness=60.0`, `damping=2*sqrt(60)`, `dt=0.016`) chases the raw mouse; state in `extraBuffer[133..136]` (pos.xy, vel.xy). First-touch snap teleports to the cursor so the brush never glides in from (0,0); parked behaviour (invalid mouse) aims the spring at its own position. Pattern mirrors `interactive-glitch-brush.wgsl` (established repo convention). The brush distance is now measured against the spring position, so the feedback trail records inertial, swooping strokes.
2. **Click splash reveals:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (`age = time - rp.z`, ~2s lifetime) stamps an aspect-corrected blob of radius ~0.15 with linear ~2s decay; `newVal = max(newVal, rippleBlob)` applied **before** the `dataTextureA` write, so splashes then fade with `trailFade` via the feedback loop.
3. **Honest depth-gated rain:** after the chromatic white-drop branch, `rainColor *= mix(1.0, mix(0.6, 1.2, depth), 0.4)` (exact brief formula) — near content glows through glyphs in unrevealed regions, earning the depth-aware tag. `depthReveal` mask scaling untouched.
4. **Stale-comment fixes (comment-only):** `config.y = RippleCount` (was `MouseClickCount`), `zoom_config.w = MouseDown` (was `Generic2`).

## VERBATIM-preserved structures

- `hash22` and `bass_env` helpers — byte-identical.
- Mask feedback contract: `dataTextureA` stores `(newVal, 0, 0, 1)`; `dataTextureC.r` read as prev mask via `textureSampleLevel(..., 0.0)`; never tonemapped / never treated as display color.
- Rain column/charID/dropVal math (`gridSize`, `colSpeed`, `verticalPos`, `charID`, `dropVal`, `charBright`, `flicker`) — unchanged.
- Chromatic white-drop branch (`rainColor` init, bass green add, `hash22(...).y > 0.98 - density * 0.1` white-drop override) — unchanged.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, final `writeTexture` / `writeDepthTexture` stores, `alpha` formula, brush radius formula — unchanged.

## JSON changes

`shader_definitions/interactive-mouse/digital-reveal.json`: added ONLY the `updatedParams` array (indices 0–3, names/defaults/min/max/step exactly as in the brief) and `"updated": true`. Validated with `json.load`. No other fields touched.

## Deviations from the brief

- **Brush gated by `validF`** (`brush = validF * smoothstep(...)`): when the engine reports an invalid mouse (offscreen/negative), the spring parks and the brush now contributes 0 instead of a stale blob at the last parked position. Follows the established `interactive-glitch-brush.wgsl` pattern; slider roles and brush radius math unchanged. Considered a bug-fix consistent with "the brush snaps to the cursor" complaint.
- No other deviations. extraBuffer writes confined to [133..136]; no reserved-word identifiers; ripple loop guard present.

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/digital-reveal.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/digital-reveal.wgsl — naga OK, bindgroup compatible
```

GREEN on first run — 0 warnings, 0 extraBuffer violations.
