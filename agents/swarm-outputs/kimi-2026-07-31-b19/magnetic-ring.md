# Agent Notes: magnetic-ring (Batch 19, Interactivist)

**Date:** 2026-07-31
**Shader:** `public/shaders/magnetic-ring.wgsl`
**JSON:** `shader_definitions/interactive-mouse/magnetic-ring.json`

## Line counts

- **Before:** 102 lines
- **After:** 166 lines (+64, inside the 152–192 target range)

## Per-slider mapping (unchanged ids/defaults — saved-preset contract)

| Slider | Param id | Mapping | Range | WGSL constant driven |
|---|---|---|---|---|
| 0 | `base_radius` | `u.zoom_params.x` | 0–1, def 0.5 | `baseRadius = mix(0.02, 0.45, x)` — base radius of all 3 concentric rings |
| 1 | `strength` | `u.zoom_params.y` | 0–1, def 0.5 | `strength = y * bass_env(bass, mids)` — displacement + chromatic split magnitude |
| 2 | `pulse_speed` | `u.zoom_params.z` | 0–1, def 0.5 | `pulseSpeed = mix(0.5, 8.0, z)` — global pulse speed (also scales each ring's own voice pulse) |
| 3 | `ring_thickness` | `u.zoom_params.w` | 0.01–0.3, def 0.3 | `ringThickness = mix(0.01, 0.18, w)` — ring band width (also widths the shockwave bands) |

All four mappings already drove shader-specific constants; kept verbatim, no renames/re-defaults.

## Techniques implemented

1. **Spring-damper ring center (priority 1).** Critically-damped spring (omega = 9.0, zeta = 1) integrated by thread (0,0) each frame with clamped dt; raw `u.zoom_config.yz` mouse stays the spring target. State in `extraBuffer[133..138]`: [133..134] sprung pos, [135..136] velocity, [137] init flag (snaps to cursor on first frame), [138] last integration time. All other threads read the sprung center `magnetPos` (≤1 frame slack = the magnetic drag). **Aspect correction is applied to the SPRUNG position** (`dVec = uv - magnetPos`). A `magnetLag` term energizes the ring glow while the magnet is dragging.
2. **Click flux shockwaves.** Ripple loop guarded by `min(u32(u.config.y), 50u)`. Each live ripple (age 0–1.5s) adds a decaying smoothstep band at radius `age * 0.4` directly into `ringMask` (`band * decay²`, band width tied to the Ring Thickness slider), plus a local `shockBoost = decay * exp(-rDist * 3)` pulse that feeds glow and alpha — clicks fire visible flux surges. Ripple layout verified against `src/renderer/UniformBuffer.ts`: `vec4(x, y, startTime, pad)` in UV space.
3. **Per-ring FFT voices.** Ring *i* (0..2) reads `plasmaBuffer[i + 1u].x` (bass/mids/treble neighbours) and runs its own pulse `sin(time * pulseSpeed * (0.7 + voice*0.8) - dist*20 + i*2.094)`, accumulating a per-ring `voiceGlow` (distinct hue per ring, amplitude scaled by its voice). The global `pulse`/`ringGlow` lines are kept for the displacement wobble; the z slider remains the global pulse speed.
4. **hash21 grain.** Previously-declared-but-unused `hash21` now drives a subtle animated grain on the field lines (`fieldGlow * (0.85 + grain*0.3)`).

## VERBATIM-preserved structures (CAUTION list)

- `hash21` and `bass_env` helper functions — byte-identical.
- 3-ring loop structure: radii `baseRadius * (1.0 + i * 0.6)`, `fieldAngle = atan2(...) + i * 1.047`, spokes `fract(fieldAngle * 8.0 / (i + 1.0))` — loop header and core lines untouched; per-ring voice code appended inside the loop only.
- `safeDir = dVecAspect / max(dist, 0.001)` normalize guard — identical.
- Chromatic `rUV`/`gUV`/`bUV` tap structure (incl. `let gUV = baseUV;` and the three `textureSampleLevel(..., 0.0)` taps) — identical.
- `dataTextureA` still receives the DISPLAY color (`finalPixel`).
- Canonical 13-binding layout unchanged; `@workgroup_size(16, 16, 1)`; `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- extraBuffer writes only in [133..138] ⊂ [133..255]; [0..4] reserved and [5..132] FFT bins untouched.

## JSON changes

Added ONLY `"updatedParams"` (4 entries, index 0–3, exactly as given in the brief's JSON block) and `"updated": true`. Existing `id`, `url`, `features`, `params` (with mapping/description fields), `tags`, `name` untouched. JSON validated with `python3 -m json` load.

## Deviations from the brief

None. (Minor implementation choice: the shockwave band width scales with `ringThickness * 1.5` so the Ring Thickness slider also shapes click waves; the brief left band width unspecified.)

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/magnetic-ring.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/magnetic-ring.wgsl — naga OK, bindgroup compatible
```

GREEN — 0 warnings, 0 extraBuffer violations, first pass.
