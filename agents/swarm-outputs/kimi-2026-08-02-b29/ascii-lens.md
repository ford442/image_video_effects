# Swarm Completion: ascii-lens (b29)

**Agent:** kimi | **Date:** 2026-08-02 | **Status:** ✅ Complete

## Changes

1. **Frame contract FIXED (priority 1):** added `textureStore(dataTextureA, ...)` every frame with the same display color (`vec4(finalColor, finalAlpha)`) as `writeTexture`. Shader now writes `writeTexture` + `writeDepthTexture` + `dataTextureA` every frame.
2. **Spring lens (priority 1):** critically-damped spring on the lens position (omega = 8.0, `accel = ω²(target − pos) − 2ω·vel`, dt clamped to [0.0005, 0.05]). State in extraBuffer[133..138] ([133..134] pos, [135..136] vel, [137] init flag, [138] last time) — within the [133..255]-only rule; [0..4] reserved and [5..132] engine FFT untouched. Raw mouse with the existing negative-coord center fallback remains the spring target. Written by invocation (0,0) only, matching established repo convention (pixel-storm).
3. **Click glyph scrambles:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (age < 1.2s) contributes an aspect-corrected ~0.2-radius falloff × `exp(-age * 2.5)` weight. Inside the lens a decaying per-cell hash jitter is added to the luma tier selection; outside the lens a brief RGB split flicker marks the click.
4. **Dead audio wired:** per-cell FFT flicker via `plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * 0.4` — shimmers `charVal` (×(0.8 + flicker)) and nudges the luma tier; bass (`plasmaBuffer[1].x`) breathes the lens radius: `lensRadius * (1.0 + bass * 0.15)`.
5. **Stale header fixed:** comment-only — `Category: distortion` → `Category: interactive-mouse`, plus swarm-upgrade note.
6. **JSON:** applied the brief's full JSON verbatim (4 existing params with exact ids/names/defaults/min/max/step/mappings + additive `updatedParams` index 0–3 + `updated: true`). Nothing else changed.

## Contracts preserved (CAUTION block)

- Grid / cellUV / localUV construction and aspect-corrected cell sizing: VERBATIM.
- Luma-tier glyph selection kept in its branchy if/else form (pixel-crisp); thresholds unchanged.
- Width mapping `mix(0.02, 0.25, u.zoom_params.z)`: VERBATIM.
- Depth-weighted alpha (`mix(0.7,1.0,lumaFinal)` → `mix(alpha*0.8, alpha, depth)`): VERBATIM.
- Outside-lens passthrough: VERBATIM (RGB-split flicker layered on top only during click decay).
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, no binding 13.
- `textureSampleLevel(..., 0.0)` for sampler reads; no reserved-keyword identifiers.

## Lines

119 → **203** (+84, within target 169–209)

## Naga

`naga public/shaders/ascii-lens.wgsl` → **Validation successful** (clean, no warnings)

## Coordinator closeout

- Final lines: **119 → 205 (+86)**. RGB click taps are clamped at image boundaries; display RGBA is written to both primary output and A every frame.
- Truthful audio/click/depth metadata and `supportsDepth` were propagated without changing source params.
- Final focused gate, dead-slider/strict-buffer audit, JSON/list parity, Jest, and production build: pass.
