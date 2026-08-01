# Agent Notes — temporal-phosphor-burn-motion-adaptive (Batch 19, role: Optimizer)

## Line counts
- **Before:** 101 lines
- **After:** 155 lines (+54, inside target range 151–191)

## Per-slider mapping (existing ids/defaults preserved — saved-preset contract)

| Slider | zoom_params | JSON id/name | Default | Shader constant driven |
|---|---|---|---|---|
| 0 | x | param1 / Motion Sensitivity | 0.5 | `motionSens = (1.0 + x*9.0) * (1.0 + bass*0.5)` — motion→decay response gain |
| 1 | y | param2 / Max Decay (Fast) | 0.5 | `decayMax = clamp(0.90 + y*0.099 + bass*0.03, 0, 0.999)` — slow-decay trail end |
| 2 | z | param3 / Min Decay (Still) | 0.5 | `decayMin = 0.70 + z*0.20` — fast-clear decay end |
| 3 | w | param4 / Warm Tint | 0.6 | `warmStrength = w * (1.0 + mids*0.4)` — amber/green tint amount |

(No renames, no re-defaults. Mapping was already shader-specific, kept as-is.)

## Techniques implemented
1. **Mouse phosphor lens (priority 1):** aspect-corrected distance to cursor (`(uv.x-mouse.x)*aspect`), `smoothstep(0.3, 0.0, d)` falloff; `decay = mix(decay, decayMax, mouseMask * 0.5)` per the brief. mouseDown (`zoom_config.w`) intensifies the charge (0.6→1.0 multiplier). Cursor proximity also feeds the motion term (`motion += charge * 0.18`) so pointer movement itself leaves a faint trail; a small `charge * 0.1` term added to alpha.
2. **Click burn stamps:** ripple loop guarded by `min(u32(u.config.y), 50u)`; live ripple (`rp.z > 0`, age in `[0, 2s)`) adds a warm ghost: `burned = max(burned, stampColor * exp(-rpAge * 2.0) * stamp)` with aspect-corrected radial falloff (0.12 radius) and white-hot-core→amber-rim stamp color.
3. **Per-band decay drift:** `bin = min(u32(clamp(uv.y,0,0.999)*8.0), 7u)`, `drift = (plasmaBuffer[bin+1u].x - 0.5) * 0.01` (±0.005), `decay = clamp(decay + drift, decayMin, 0.999)` — subtle spectrum breathing; static areas still clear.

## VERBATIM-preserved structures (engine contracts)
- Binding 13 `historyTexture: texture_2d_array<f32>` declaration; full immutable 13(+1)-binding layout unchanged.
- Ring indexing `(historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH` (both the recent-frame sample and the accumulation loop).
- `let historyHead = u32(extraBuffer[4]);` read. extraBuffer is **read-only** — no writes anywhere.
- Max()-based burn accumulation loop (`burned = max(burned, decayed)` over ages 1..7).
- Warm tint math: `warmTint = vec3(1.0, 1.08, 0.65)`, `burned = mix(burned, burned * warmTint, glowAmt)`.
- `dataTextureA` stores the raw display color (`finalOut`), unchanged.
- `@workgroup_size(16, 16, 1)`; writes to writeTexture/writeDepthTexture/dataTextureA every frame; all sampler reads use `textureSampleLevel(..., 0.0)`; no reserved-word identifiers.

## JSON changes
`shader_definitions/post-processing/temporal-phosphor-burn-motion-adaptive.json`: added ONLY the `"updatedParams"` array (index 0–3, exactly as in the brief) and `"updated": true`. Validated with `json.load` — OK.

## Deviations from the brief
- None material. Minor: stamp radial falloff uses radius 0.12 (brief only specified "at its click point"); `charge` uses mouseDown to scale 0.6→1.0 (brief said clicks do nothing — fixed via stamps, hover still charges at 60%); alpha gained a small `charge * 0.1` term for visible lens feedback.

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/temporal-phosphor-burn-motion-adaptive.wgsl
Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ naga OK, bindgroup compatible
```
