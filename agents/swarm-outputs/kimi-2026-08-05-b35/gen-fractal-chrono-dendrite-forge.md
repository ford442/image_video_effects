# gen-fractal-chrono-dendrite-forge — Visualist upgrade (batch 35, #319, cohort fixer-upper)

## Fixes (contract)
- `@workgroup_size(8, 8, 1)` → **`@workgroup_size(16, 16, 1)`**.
- Now writes **`writeDepthTexture` and `dataTextureA` every frame**
  (previously only writeTexture). Depth is real raymarch relief
  (`1 − clamp(d0/12)`, near-is-one, 0 on miss).
- JSON gains **4 indexed `updatedParams`** (index 0–3, name/default/min/max/
  step, normalized 0–1), all read via `u.zoom_params.x/y/z/w` and rescaled in
  WGSL to their original engine ranges:
  - 0 Dendrite Complexity (0.6) → `map()` iteration count 2–5
  - 1 Entropy Pulse Rate (0.25) → ×2.0 → pulse rate 0–2 (0.5 = legacy default)
  - 2 Spectral Dispersion (0.38) → 0.1 + ×2.9 → 0.1–3 (≈1.2 legacy default)
  - 3 Gravity Well Strength (0.4) → ×2.0 → 0–2 (0.8 legacy default)

## Visualist upgrades
- **3-point lighting rig, three temperatures**: warm forge key (2,4,−3), cool
  chrono-blue half-wrapped fill (−3,−1.5,−2), hot magenta Fresnel **rim**
  backlight (`pow(1−ndotv,3)`, treble-reactive).
- **HDR highlights**: specular ×2.2 and synapse emissive exceed 1.0 pre-tonemap
  (bloom-ready), then **ACES tone map** with mids-breathing exposure.
- **Volumetric glow approximation**: bounded near-miss accumulation
  (`exp(−4d)·0.02` per march step, total ≤ 2.4) rendered as a teal aura,
  visible even on miss rays; also tints the **depth fog** (deep-violet → teal
  chrono haze).
- **FFT-shimmered thin-film**: guarded engine bins 1–8 animate the bismuth
  oxide-film phase (no hash-based fake spectrum); bass/mids/treble from
  `plasmaBuffer[0].xyz`.
- **Click interaction**: `zoom_config.w > 0.5` deepens the mouse gravity well
  (×1.8), still exp-falloff bounded, finite and spatially local.
- **Semantic alpha**: 1.0-class on hits, void breathes with its aura
  (0.82 + hit + glow term, clamped) — no hardcoded alpha.

## JSON
Added `updatedParams`, `workgroup_size`, `supportsDepth`, `updated`, extended
description. **Deviation**: removed the stale legacy `controls` block
(0–5/0–2 raw ranges) because it contradicted the new normalized param contract
— same 4 slider names/roles preserved.

## Perf estimate
Raymarch unchanged at ≤120 steps; +1 exp per step (glow accum), +2 extra
lighting dots, +1 Fresnel pow on hit only. ≈ +6–9% vs. baseline. 180 → 251
lines.

## Gate
`wgsl_precommit_gate.py` — ✅ naga OK, bindgroup compatible, 0 extraBuffer
violations.
