# atmos_volumetric_fog — Swarm Notes (kimi, 2026-07-22-b12)

**Role:** Visualist (light transport: shafts, scattering color, aerial perspective)
**Shader:** `public/shaders/atmos_volumetric_fog.wgsl`
**Definition:** `shader_definitions/generative/atmos_volumetric_fog.json`

## Line delta

- Before: 166 lines → After: 233 lines (**+67**, within the brief's +50 to +90 budget; target 216–256 ✅)

## Key changes

1. **Mouse-anchored god rays (sharpened).** Added `godRayShaft()` — a 10-step screen-space radial march from each pixel toward the mouse light, accumulating fbm fog occlusion along the ray so light is carved into visible shafts instead of a flat radial glow. The old directional `pow(..., 4.0)` term was kept but sharpened into `godCone` whose exponent is driven by the Scattering slider (`shaftSharp = 2.0 + scattering * 6.0`). Final shaft term is masked by fog density, the God Rays slider, and light intensity, tinted warm (`mix(warm white, fogColor, 0.35)`).
2. **fbm density breakup.** Added a second 3-octave fbm layer (`breakup`, higher frequency, counter-drifting) multiplied into the density alongside the existing 4-octave `noiseVal`: `densityNoise = (0.5 + noiseVal*0.5) * (0.55 + 0.9*breakup)`. Fog now clumps and layers volumetrically.
3. **Treble sparkle motes.** Added `dustMotes()` — sparse (4% of cells, hash-gated) jittered dot motes with per-cell time-phased twinkle, scaled by treble. Motes are only revealed inside bright shafts (`moteGain = shaft*2 + godCone*lightGlow*godRays`) and by Light Intensity.
4. **Feedback clamp.** Temporal feedback now clamps `prev.rgb` to `[0, 1.2]` **pre-tint** (`prevSafe`) before the `* 0.95` decay — per the luma-echo-warp lesson, preventing blowout accumulation.
5. **Slider rewiring (same ids/defaults/mapping — saved-preset contract preserved):**
   - `param1 Fog Density` → fog extinction coefficient (unchanged role).
   - `param2 Light Intensity` → **rewired** from fog height to light brightness + glow radius (`glowRadius`, `lightGlow` gain). Height falloff is now fixed const `FOG_HEIGHT = 0.45`.
   - `param3 Scattering` → **rewired** from depth weight to in-scatter gain, shaft cone sharpness, and absorption coefficient scaling. Depth weight is now fixed const `DEPTH_WEIGHT = 0.55` (`calculateFogAlpha` signature simplified accordingly).
   - `param4 God Rays` → **rewired** from fog color shift to the god-ray shaft visibility mask. Fog color shift is now fixed at `0.5 + mids*0.1`.
6. Core algorithm/soul preserved: `physicalTransmittance`, `volumetricAlpha`, height fog, shockwave clear, video-luma emission, bass envelope, chromatic aberration, ACES, semantic alpha (now includes shaft contribution in `interaction`). Canonical 13-binding layout + `@workgroup_size(16,16,1)` unchanged; writes to `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame. No binding 13 added (not previously used).

## JSON

Added `updatedParams` (indices 0–3, exact brief block) and `"updated": true`. No other fields touched — params ids/names/defaults/min/max/step/mappings unchanged.

## QA flags

- ✅ `python3 scripts/wgsl_precommit_gate.py --files public/shaders/atmos_volumetric_fog.wgsl` → exit 0, 0 warnings (naga OK, bindgroup compatible).
- ✅ JSON parses cleanly.
- ⚠️ **No GPU in this VM** — visual QA deferred. Notably unverified visually: shaft march step count (10) vs. banding, mote density at `step(0.96, seed)`, shaft gain `* 6.0`, and feedback clamp interaction with the warm shaft tint. Recommend a quick on-GPU pass to tune `RAY_STEPS`, shaft gain, and mote sparsity if banding/over-bright shafts appear.
- ⚠️ `normalize(lightDir + epsilon)` — epsilon guard added against zero-length ray at the mouse pixel; fine for naga but the cone directly under the cursor is still intentionally pinned to the `(0,-1)` reference direction.
