# Agent Notes: chronos-brush (Batch 17, Algorithmist)

## Line count
- Before: 94 lines → After: 144 lines (+50, within the +50..+90 / 144–184 target)

## Gate result
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/chronos-brush.wgsl`
- ✅ PASS — naga OK, bindgroup compatible (exit 0). Naga was available in this VM and validated the shader.

## Slider rewiring (priority 1 — labels were lies)
The old code read y as hue-shift speed, z as fade amount, w as opacity. Now:

- **x — Brush Size (default 0.3):** unchanged semantic — brush radius via `0.02 + brushSize * 0.15`, still audio-boosted by `bass_env(bass, mids)`.
- **y — Freeze Decay (default 0.9):** now drives history persistence directly:
  `decay = 1.0 - (1.0 - freezeDecay) * 0.25 * (1.0 - bass * 0.03)`.
  At default 0.9 (and silence) this yields `decay = 0.975` — **bit-identical to the legacy fade** (`1.0 - 0.5 * 0.05 * ...`). y=1.0 freezes forever (decay 1.0), y=0 decays fast (0.75).
- **z — Time Edge Distort (default 0.5):** now drives a real temporal distortion — the *history* sample UV (not the live feed) is wobbled by a two-octave time-varying sinusoid:
  `wobbleAmp = z² * 0.012`, `historyUV = clamp(uv + wobble, 0, 1)`.
  Quadratic falloff keeps z=0 at exactly 0 and the 0.5 default subtle (~0.003 UV ≈ a few px), so the painted look is preserved at defaults.
- **w — Mode (Paint/Erase) (default 0):** now an honest mode switch. `w > 0.5` → **erase**: brush strokes mix history toward the untinted live frame (thaw/unfreeze). `w ≤ 0.5` → **paint**: legacy chromatic tint pipeline. Both branches write history every frame — no early returns.

## Hue cycling note
The hue phase term `time * colorShiftSpeed * 0.5` (which secretly consumed slider y at 0.9 → rate 0.45) is now a fixed `time * 0.45`, preserving the exact legacy chromatic cycle rate at defaults.

## Techniques implemented
1. **Honest slider rewiring** (above) — ids/names/defaults untouched; defaults reproduce the legacy painted look.
2. **Stale comment fix (comment-only):** `config.y` = RippleCount (was "MouseClickCount"), `zoom_config.w` = MouseDown (was "Generic2"); `zoom_params` components annotated with real semantics; ripple layout documented (`xy`=click UV, `z`=click time).
3. **Click-stamp blooms:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (0 ≤ age ≤ 3.0s) stamps a soft round bloom (`1.0 - smoothstep(r*0.5, r, dist)`) at its click point with radius `radius * 1.5`, strength `exp(-age * 2.0)`. Blooms merge with the drag stroke via `brushMask = max(brush, stamp)` and flow through the same tint/erase pipeline, so single clicks paint without dragging.

## Sacred contract preserved
- dataTextureC read → dataTextureA write feedback intact; history stays RAW (no tonemap/clamp added beyond the legacy alpha clamp).
- `bass_env` and the inline HSV→RGB block are VERBATIM.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes `writeTexture`/`dataTextureA`/`writeDepthTexture` every frame, `textureSampleLevel(..., 0.0)` for all sampler reads.
- No reserved-keyword identifiers; no binding additions/renumbering; extraBuffer untouched.

## JSON
- Added ONLY `updatedParams` (indices 0–3) and `"updated": true` exactly per the brief. Existing params (ids, names, defaults, min/max, labels, order) untouched.

## Deviations
- Old `w` behaved as opacity (default 0 → invisible strokes). Since the saved-preset contract forbids changing defaults and the label contract demands a paint/erase switch, paint mode now uses `depthOpacity` (the old fully-on opacity) as its strength. At default w=0 this makes the brush visible where the old default was a no-op; the *painted* aesthetic (what users saw with w turned up) is reproduced exactly. This is the intended honest-semantics trade-off flagged by the brief.
- Brief suggested `decay = mix(0.90, 0.999, y)` as an example; I used `1.0 - (1.0 - y) * 0.25 * (1.0 - bass * 0.03)` instead because it reproduces the legacy decay constant (0.975) *exactly* at the 0.9 default while keeping the legacy bass modulation term.
- mouseDown is decoded in a comment but not wired into the brush strength (the legacy stroke painted regardless of button state; gating it would alter the current look).
