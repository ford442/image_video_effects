# Completion: anamorphic-caustic-flare (kimi, b29)

## Lines
- Before: 119 → After: **182** (+63, within 169–209 target)

## Changes
- **Spring-dampered tilt + breathing flare anchor (priority 1):** critically-damped spring on the cursor, state in `extraBuffer[133..136]` (pos.xy, vel.xy) + `[137]` lastTime. Thread (0,0) integrates; all threads read. Snap guard on first frame/teleport (`time < 0.1 || lastTime <= 0.0 || dist > 1.5`). `mouseTilt` now rides the sprung x; flare anchor `flareY = mix(0.5, sprungMouse.y, 0.35)` drives both `centerDist` and the streak line so the lens breathes toward the cursor.
- **Click flare bursts:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple (age ≤ 1.2s) adds `exp(-age * 2.0) * smoothstep(0.02, 0.0, abs(uv.y - clickY)) * flareStrength` as a second streak term, plus a brief caustic energy spike `exp(-age * 3.0) * smoothstep(0.25, 0.0, dist)` near the click point.
- **Per-band FFT caustic shimmer:** 8 vertical bands (`min(u32(uv.x * 8.0), 7u)`), each modulating `causticMask` by `plasmaBuffer[(band % 8u) + 1u].x * 0.3`.
- **Sliders:** existing 4 params wired via `zoom_params.x/y/z/w`, each driving a real shader constant (flare strength, caustic intensity, refraction offset, caustic frequency/stretch). Mapping order preserved.

## Contracts preserved (verbatim)
- dataTextureA FIELD packing `(c, causticMask, flareStrength, semantic_alpha)` — not display color
- hash21 + caustic helpers, anamorphic smoothstep flare + streak construction, refraction offset formula, branchy filmic chromatic aberration block (`if (flareStrength > 0.4)`), contrast curve `pow(max(col,0), 0.88)`, semantic alpha formula, depth-energy write
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes writeTexture + writeDepthTexture + dataTextureA every frame
- extraBuffer usage confined to [133..137] (within [133..255]); no touch of [0..4] or FFT [5..132]
- Engine truth: config=[time,rippleCount,resW,resH], zoom_config=[time,mouseX,mouseY,mouseDown]
- JSON: ids/names/defaults/ranges EXACT (Flare 0–1.6, Caustic 0–1.8); full brief JSON applied verbatim with additive `updatedParams` (index 0–3) + `updated: true`

## Naga
- `naga public/shaders/anamorphic-caustic-flare.wgsl` → **Validation successful** (clean, no warnings)

## JSON
- Validated with `json.load` → OK

## Coordinator closeout

- Final lines: **119 → 189 (+70)**. All invocations now derive the same current-frame spring step, with an explicit `[138]` initialization flag and invocation `(0,0)` as sole writer.
- Click stacks use bounded maxima and aspect-correct distance; caustic/refraction weights, chromatic taps, and display HDR are bounded while raw field packing in A remains unchanged.
- Final focused gate, dead-slider/strict-buffer audit, JSON/list parity, Jest, and production build: pass.
