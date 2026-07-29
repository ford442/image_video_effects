# Agent Notes — fireworks-portrait-burst (Batch 18, Algorithmist)

## Lines
- Before: 100 → After: 166 (+66, within the +50 to +90 target)

## Techniques implemented (all 3 from the brief)

1. **MOUSE COORD BUG FIX (priority 1):** `mUV = (u.zoom_config.yz - res*0.5)/min(res.x,res.y)` treated normalized [0,1] mouse coords as pixels, throwing bursts hundreds of pixels off-screen. Fixed via a new `normToCentered(p, res)` helper that computes `(p * res - res * 0.5) / min(res.x, res.y)` — the held-mouse burst now detonates at the cursor.
2. **Honest depth:** `writeDepthTexture` no longer stores flat 0.0. It now writes `clamp(dot(col, lumWeights) * 0.8 + sparkGlow * 0.2, 0.0, 1.0)`, where `sparkGlow` accumulates all burst/spark glow contributions (core flash 1.0×, sparks 0.25×) so bright bursts sit forward in chain depth.
3. **Click ripple bursts:** New ripple loop guarded by `min(u32(u.config.y), 50u)`. Each live ripple (`age = time - ripple.z`, alive 0–3s) fires a one-shot burst at its click point: a core flash (`exp(-rAge*7.0)`) plus 28 sparks using the same `sparkPos`/`softGlow` pipeline as the held-mouse burst (speed seeded by `hash1(f32(ri)*97.0 + f32(q)*3.7)`, gravity 0.85). The existing held-mouse auto-repeat is kept intact.

## Slider wiring (zoom_params.x/y/z/w → updatedParams index 0–3)
- **Brightness (thresh, x):** minimum image luminance that may seed a detonation core (`mix(0.1, 0.75, x)`), used by both the per-pixel dimming and the 7-probe culling (`pLum < thresh * 0.6`).
- **Burst Size (size, y):** per-burst energy (`mix(0.4, 1.5, y)`) — drives spark count, spark speed, radius and brightness for all three burst sources (probe, mouse, ripple).
- **Dissolve (dissolve, z):** how hard bright regions are dimmed when they detonate (`mix(0.1, 0.7, z)`), modulated by bass.
- **Warmth (warmth, w):** spark palette — 0 = inherit source color, 1 = hot ember gold (`ember = vec3(1.0, 0.7, 0.3)`); applied to probe sparks, mouse burst, and ripple sparks.

## Preserved verbatim (per CAUTION)
- `sparkPos` gravity, `softGlow` falloff, `hash1` seeds (probe loop untouched), the 7-probe loop including both `continue` guards, `acesToneMap`, temporal echo mix, and the raw dataTextureA/B roles (no re-tonemapping). `textureLoad` for dataTextureC kept. Canonical 13-binding layout and `@workgroup_size(16, 16, 1)` unchanged. `writeTexture`, `writeDepthTexture`, `dataTextureA` (and `dataTextureB`) written every frame.

## Deviations
- Mouse/ripple burst spark color now mixes in `warmth` (`mix(mCol, ember, warmth*0.35)` / `*0.4`) so the Warmth slider is visible on interactive bursts too — a minor extension, not a physics change (angles/speeds/radii/fade unchanged).
- Added `lumWeights` const and `normToCentered` helper (used by both the fixed mouse path and the new ripple path) to avoid duplicating the coordinate math.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/fireworks-portrait-burst.wgsl` → **GREEN** (Passed: 1, Failed: 0 — naga OK, bindgroup compatible, workgroup OK).

## JSON
`shader_definitions/image/fireworks-portrait-burst.json`: added only `updatedParams` (index 0–3, exact block from brief) and `"updated": true`. Existing `params` untouched (no renames/re-defaults/reorders). JSON parses clean.
