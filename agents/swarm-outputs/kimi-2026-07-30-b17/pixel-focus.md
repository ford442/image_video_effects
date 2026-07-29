# Agent Notes — pixel-focus (Batch 17, role: Optimizer)

## Lines
- **Before:** 95
- **After:** 146 (+51, within the +50 to +90 / 145–185 target)

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/pixel-focus.wgsl`
→ **PASSED** — `✅ naga OK, bindgroup compatible` (1 checked, 1 passed, 0 failed, 0 extraBuffer violations). Naga was available in this VM and validated the shader.

## What each slider now drives
| index | param | WGSL source | Drives |
|---|---|---|---|
| 0 | Block Size (`mosaicSize`) | `u.zoom_params.x` | Mosaic density base: `50 + (1 - mosaicSize) * 450` blocks across the frame (unchanged core, still the main pixelation constant) |
| 1 | Focus Radius (`radius`) | `u.zoom_params.y` | Base lens radius `mix(0.01, 0.5, y)`, now modulated by scene depth at the mouse (`* mix(0.7, 1.3, depthAtMouse)`) and by mouse-down rack-focus (`* (1 + mouseDown * 0.15)`) |
| 2 | Edge Hardness (`hardness`) | `u.zoom_params.z` | Focus falloff width: `smoothstep(focusRadius, focusRadius + (1 - hardness) * 0.2, dist)` (unchanged core constant) |
| 3 | Aberration (`chromatic`) | `u.zoom_params.w` | Branchless chromatic split strength (`offset = chromatic * 0.01`, still treble-boosted by `+ treble * 0.1`) — VERBATIM block preserved |

## Techniques implemented
1. **DEPTH-AWARE FOCUS (priority 1):** the depth buffer was previously read only to be passed through. Now `readDepthTexture` is sampled (unconditionally) at the clamped mouse position and at the current pixel. The mouse-point depth modulates the focus radius (`focusRadius *= mix(0.7, 1.3, depthAtMouse)`) so the lens tunes its clear pool to the subject's depth. Additionally, per-pixel depth slightly coarsens the out-of-focus mosaic for far content (`density *= mix(1.0, 0.85, depth * (1.0 - focus))`). Pixel depth is still written through to `writeDepthTexture` every frame.
2. **Click focus pulses:** loops `u.ripples` guarded by `min(u32(u.config.y), 50u)`. Each ripple (`xy` = click point, `z` = click time, verified convention from liquid-jelly-fluid.wgsl) emits an expanding sharp ring (`ringRadius = t * 0.55`, width `0.035 + t * 0.02`) where focus snaps to 1 via `focus = max(focus, ringBand * ringDecay)`, decaying linearly over 1.5s. Distances are aspect-corrected like the main lens.
3. **Spectral mosaic shimmer:** per-bin energy from `plasmaBuffer[1..4].x` is summed (`bin1*0.04 + bin2*0.03 + bin3*0.02 + bin4*0.02`) and multiplies the density on top of the existing global bass/mids term, so the mosaic breathes with the music. `density = max(density, 1.0)` guard kept.
4. **Lens rim highlight (small extra to hit line target):** a faint treble-reactive bright ring hugs the focus boundary, added to `finalRGB` after the core mix.

## Contract compliance
- 13-binding canonical layout preserved, no renumbering; binding 13 not declared (not used before).
- `@workgroup_size(16, 16, 1)`; writes `writeTexture`, `dataTextureA` (DISPLAY color), and `writeDepthTexture` every frame.
- All sampler reads use `textureSampleLevel(..., 0.0)`; all texture samples unconditional (the two new depth samples sit at top level, outside any branch; the ripple loop contains no texture reads).
- CAUTION respected: branchless chromatic `useChromatic` step + `mix` block and the alpha-from-luma formula `clamp(baseColor.a * (focus * 0.6 + luma * 0.3 + 0.1), 0.0, 1.0)` are preserved VERBATIM.
- No reserved-keyword identifiers; `extraBuffer` untouched.
- JSON: added ONLY `updatedParams` (index 0–3, names/defaults/min/max/step exactly as in the brief) and `"updated": true`. Existing `params` ids/defaults/order untouched.

## Deviations
- None from the mandatory items. The brief's suggested `focusRadius *= mix(0.7, 1.3, depth)` was applied using depth **at the mouse point** (subject depth) rather than per-pixel depth, which reads more like a real lens; per-pixel depth instead drives the subtle far-field mosaic coarsening. A minor `mouseDown` rack-focus widening and lens rim highlight were added to reach the line target — both additive, neither alters preserved code.
