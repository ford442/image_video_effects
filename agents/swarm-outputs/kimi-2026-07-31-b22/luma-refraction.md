# Batch 22 Notes: luma-refraction

**Agent:** Kimi (Algorithmist role)
**Date:** 2026-07-31
**Shader:** `public/shaders/luma-refraction.wgsl`
**JSON:** `shader_definitions/image/luma-refraction.json`

## Lines

- Before: 110 → After: **186** (+76, within +50..+90; inside the 160–200 target band)

## Priority-1 Fix: MASK-AS-COLOR feedback (4th sighting, spore-galaxy class)

The old "temporal wave memory" read `dataTextureC.rgb` — the wave **state** buffer
(`h` in [-10,10], `v`, 0) — and mixed it into the display color at ~5–7%
(`mix(finalColor, prevRefraction * 0.9, 0.05 + mids * 0.02)`), injecting simulation
garbage into the image. **Both lines (the read + the mix) were removed entirely.**
The wave state now never enters the display path; the chromatic refraction offsets
visualize the wave honestly. The A=(h, v, 0, 1) state write and all C state reads
remain untouched (engine-forced contract).

## Bugs Fixed

1. Mask-as-color feedback loop (state buffer leaked into display color) — removed.
2. Dead audio band: `mids` was only consumed by the removed feedback mix; it now
   drives the dispersion glint amplitude (derived from refracted image taps only).

## Slider Map (unchanged ids/defaults/ranges — saved-preset contract)

| zoom_params | id | name | default | range | drives |
|---|---|---|---|---|---|
| .x | waveSpeed | Wave Speed | 0.5 | 0–1 / 0.01 | `localSpeed` (luma-driven propagation, SACRED formula) |
| .y | mouseForce | Mouse Force | 0.5 | 0–1 / 0.01 | stir amplitude + stir radius (`0.05 + mouseForce * 0.05`) |
| .z | damping | Damping | 0.98 | **0.9–0.999 / 0.001 (EXACT)** | `v = v * damping` (SACRED) |
| .w | refraction | Refraction | 0.5 | 0–1 / 0.01 | chromatic refraction offset magnitude (r/g/b taps) |

## Techniques Added

1. **Click raindrops** — loop `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`;
   each live ripple (age 0–0.12 s) drops a one-shot gaussian wave impulse
   (`v += exp(-rd²/0.05²) * 0.8`, aspect-corrected), same form as the mouse stir.
2. **Audio rain** — branchless `step()` form: `hash21(uv * 91.0 + floor(time * 3.0))`
   gated by `0.998 - bass * 0.002` adds `v += 0.3` impulses on bass transients;
   beats make the whole surface drizzle.
3. **Ambient drizzle** — faint constant sprinkle (`step(0.9995, hash21(...)) * 0.05`)
   keeps the pond alive in silence.
4. **Widened mouse stir** — radius `0.05 + mouseForce * 0.05` (per brief).
5. **Dispersion glint** — honest display polish derived ONLY from refracted image
   taps: `chroma = |r - b|` of the tapped channels, shimmer amplitude driven by
   `mids`, warm spectral tint, clamped to [0,1]. No wave state involved.
6. `hash21` helper (fract/dot hash) for deterministic per-pixel rain selection.

## Kept VERBATIM (SACRED)

- `laplacian = (n + s + e + w_val) / 4.0 - h;`
- `localSpeed = waveSpeed * (0.2 + 1.0 * luma) * (1.0 + bass * 0.3);` (luma-driven propagation)
- `v = v + laplacian * localSpeed;` / `v = v * damping;`
- `h = h + v;` / `h = clamp(h, -10.0, 10.0);`
- `textureStore(dataTextureA, global_id.xy, vec4<f32>(h, v, 0.0, 1.0));`
- ALL `dataTextureC` state reads (state + n/s/e/w neighbors)
- `gradX = (e - w_val) * 0.5;` / `gradY = (s - n) * 0.5;` normal
- r/g/b refraction tap structure (offsets, clamped UVs, per-channel samples)

## Contract Checks

- 13-binding canonical layout unchanged; no renumbering; no binding 13 added.
- `@workgroup_size(16, 16, 1)` unchanged.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- All sampler reads use `textureSampleLevel(..., 0.0)`; no reserved-word identifiers.
- extraBuffer: declared but **never written** → no [133..255] concerns (0 violations).
- Ripple loop guarded with `min(u32(u.config.y), 50u)`.

## JSON Changes

Added ONLY (per brief):
- `"updatedParams"` — 4 entries, index 0–3, exact names/defaults/min/max/step
  (Damping 0.9–0.999 step 0.001 preserved).
- `"updated": true`

No changes to id/name/url/description/params/features/tags.

## Deviations

- Added the small ambient-drizzle impulse (constant, bass-independent) beyond the
  letter of the brief; it shares the audio-rain mechanism and keeps the sim alive
  in silence. All sacred formulas untouched.
- Mouse stir radius is now `0.05 + mouseForce * 0.05` (explicitly requested by brief);
  amplitude formula `(1.0 - dist / stirRadius) * mouseForce * 0.5` preserved.

## Gate Result

```
$ python3 scripts/wgsl_precommit_gate.py --files public/shaders/luma-refraction.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | Workgroup warnings: 0 | extraBuffer violations: 0
✅ public/shaders/luma-refraction.wgsl — naga OK, bindgroup compatible
```

**GREEN — 0 warnings, 0 extraBuffer violations, first pass.**
