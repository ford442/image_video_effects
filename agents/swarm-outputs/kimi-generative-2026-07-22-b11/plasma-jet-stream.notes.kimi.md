# plasma-jet-stream — Upgrade Notes (Kimi)

**Role:** Algorithmist
**Batch:** kimi-generative-briefs-2026-07-22-b11
**Files touched:**
- `public/shaders/plasma-jet-stream.wgsl` (full-file overwrite)
- `shader_definitions/generative/plasma-jet-stream.json` (added `updatedParams` + `"updated": true` only)
- this notes file

## Key Changes

- **Divergence-free curl-noise perturbation:** added `curlNoise()` — curl of a value-noise
  potential via finite-difference gradient rotated 90° `(dPsi/dy, -dPsi/dx)`. Replaces the
  bulk of the raw warped-FBM offset so jets bend without artificial sources/sinks
  (warped FBM kept at reduced 0.08 weight for boundary character; soul preserved).
- **Bass surge wave:** `plasmaBuffer[0].x` (bass) drives a slow radial pressure pulse
  from the stream origin (`surgePhase = radius * 5.0 - time * surgeSpeed * ...`).
  The passing wavefront multiplies jet `width` via `surgeBoost`, so beats visibly pump
  jet spread outward. Also adds a faint cyan shimmer ring riding the front.
- **Chromatic shear fringe:** per-jet shear magnitude computed analytically as
  `|d(core)/d(dist)| = jcore * dist / variance` (peaks at jet boundaries / high
  velocity-gradient zones). Fringe color hue follows the local bend direction
  (sign of curl + warp), giving a prismatic red/blue edge that flips with the curl.
  Fringe feeds `presence`/alpha and slightly pulls `depth` forward.
- **Slider wiring (contract preserved, 4 params, indices 0–3):**
  - `zoom_params.x` Jet Count → number of radial jets (1–8)
  - `zoom_params.y` Velocity → pulse frequency **and** surge-wave propagation speed
  - `zoom_params.z` Spread → base jet width = shear-layer thickness
  - `zoom_params.w` Turbulence → curl-noise bend amplitude + Clifford drift strength
  - Ids/names/defaults/min/max/step/mapping order unchanged (saved-preset contract).
- Core algorithm (radial Gaussian jets, Clifford drift, gold-noise sparks, ACES,
  temporal feedback via `dataTextureC`) untouched in spirit — upgrade, not rewrite.
- Canonical 13-binding layout and `@workgroup_size(16, 16, 1)` preserved;
  writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame;
  `textureSampleLevel(..., 0.0)` for sampler reads; no reserved-keyword identifiers;
  no binding 13 (shader doesn't use history ring).

## Line Count Delta

- Before: 152 lines → After: 214 lines (**+62**, within the +50 to +90 target; 202–242 band ✅)

## Validation

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/plasma-jet-stream.wgsl`
  → **exit 0, naga OK, bindgroup compatible, 0 warnings** ✅

## QA Flags / Caveats

- **All constants eyeballed** (surge speed/falloff 0.55/5.0/1.2, fringe gain 1.6,
  dispersion 0.28, curl epsilon 0.15, curl weight 0.10). Not tuned on real hardware.
- **This VM has no GPU adapter** — WebGPU unavailable, so visual QA is deferred.
  Validation is static (naga gate + binding contract) only; run on a GPU machine to
  eyeball fringe subtlety and surge pump feel.
- Surge wave is analytic (time-based phase), not a frame-accumulated bass integrator —
  avoids `extraBuffer` cross-thread races; amplitude still scales with instantaneous bass.
