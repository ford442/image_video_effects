# Agent Notes: holographic-shatter (Batch 19, Algorithmist)

## Line counts
- **Before:** 103 lines
- **After:** 162 lines (+59, inside target range 153–193)

## Bugs fixed (all three recon-confirmed)
1. **OOB plasmaBuffer palette read** — `plasmaBuffer[palIdx % 256u]` indexed past the
   real FFT bin count (zeros → dead black palette). Now `plasmaBuffer[(palIdx % 8u) + 1u].rgb`
   (live bins 1–8). The `palIdx` computation and the holographic sin() phase math are unchanged.
2. **Dead 'Depth Weight' slider** — `depthLayeredAlpha()` was never called. Now wired:
   `finalAlpha = mix(baseColor.a, depthLayeredAlpha(finalColor, uv, depthWeight), clamp(effectIntensity, 0.0, 1.0))`
   exactly per the brief formula.
3. **Inverted mouse impact falloff** — was `(0.4 + mouseDown * 0.6) * smoothstep(0.0, 0.6, dM)`
   (grew with distance). Now near-focused:
   `nearImpact = mouseGain * smoothstep(0.6, 0.0, dM)` with
   `impact = max(nearImpact, 0.25 * mouseGain)` global baseline preserved.

Also normalized the odd depth write `vec4(depth, 0, 0, 1)` → `vec4(depth, 0.0, 0.0, 0.0)`.

## Per-slider mapping (saved-preset contract, unchanged ids/defaults)
| Slider | zoom_params | Drives |
|---|---|---|
| Shatter Amount (idx 0) | x | `shatterAmount` = shard flight distance, bass-boosted `(1.0 + bass * 0.4)` |
| Hologram Intensity (idx 1) | y | `holographicIntensity` = foil/edge interference mix strength |
| Depth Weight (idx 2) | z | `depthWeight` = depth- vs luma-tiered alpha blend (now actually called) |
| Shard Count (idx 3) | w | `shardCount` = fracture grid density (`w * 50 + 10`) |

## Techniques implemented
- Guarded palette read into live FFT bins 1–8.
- Wired depth/luma-tiered alpha into final alpha.
- Near-focused impact falloff with far-field baseline.
- **Click shatter detonations:** ripple loop guarded by `min(u32(u.config.y), 50u)`;
  each live ripple (age < 1.5s) is a decaying impact center with the same flightDir
  math from the ripple origin, weight `exp(-age * 2.5) * smoothstep(0.5, 0.0, rDist)`;
  accumulated `clickDir`/`clickImpact` add to the shard offset and effectIntensity.
- **Per-channel chromatic refraction:** R/B channels re-sampled along `flightDir`
  (±refr), mixed by `chromaMix` (edgeGlow + mids + clickImpact driven) — uses the
  previously-unused `mids` bin.
- Depth write normalized.

## VERBATIM-preserved structures
- `rand()` helper — untouched.
- `depthLayeredAlpha()` body — untouched.
- Shard grid construction (`gridUV`/`shardId`/`shardUv`) and `edgeGlow` construction — untouched.
- Holographic phase/palette sin() math (`phase`, `holographic`, `palIdx`, `foil`) — only the
  plasmaBuffer INDEX expression changed.
- Temporal settling: `mix(sample.rgb, prevShards * 0.92, 0.06 + bass * 0.02)` — untouched;
  `dataTextureA` still written with raw display color.
- 13-binding layout, `@workgroup_size(16, 16, 1)`, all sampler reads `textureSampleLevel(..., 0.0)`.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- extraBuffer: declared (layout) but **never written** → 0 violations.

## JSON changes (shader_definitions/image/holographic-shatter.json)
- Added ONLY `"updatedParams"` (4 entries, index 0–3, exactly as the brief's JSON block)
  and `"updated": true`. `params` ids/names/defaults/min/max/step untouched. JSON validates.

## Deviations from the brief
- `effectIntensity` gained a `+ clickImpact * 0.3` term (not in the VERBATIM caution list)
  so click detonations also lift the alpha-blend weight; original terms unchanged.
- `finalColor` declared `var` so the new chromatic refraction pass can rebuild it after the
  verbatim `mix(settled, foil, edgeGlow * holographicIntensity)` construction.

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/holographic-shatter.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/holographic-shatter.wgsl — naga OK, bindgroup compatible
```
