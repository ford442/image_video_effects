# gen_kimi_nebula — Kimi (Visualist) Notes, batch b13, 2026-07-22

## Line delta
- Before: 172 lines
- After: 227 lines
- Delta: **+55** (brief target: +50 to +90, final range 222–262 ✅)

## Key changes per technique

### 1. Boilerplate killed, sliders wired to real constants
`applyGenerativePrimaryControls()` (generic intensity/speedPulse/contrast/mouse
helper) is **removed entirely**. In its place a `NebulaControls` struct +
`nebulaControls()` builder maps the four existing slider params directly onto
nebula algorithm constants, with slider default 0.5 reproducing each legacy
hard-coded value (saved-preset contract preserved):
- **param1 Intensity** (`zoom_params.x`) → `gasGain = mix(0.4, 2.0, x)` — multiplies
  the raw fbm gas density before palette mapping (and the blue-layer mix).
- **param2 Speed** (`zoom_params.y`) → `timeScale = mix(0.0, 0.2, y)` — replaces the
  hard-coded `u.config.x * 0.1` time multiplier.
- **param3 Scale** (`zoom_params.z`) → `spatialScale = mix(0.5, 2.5, z)` — replaces the
  hard-coded `p * 1.5` noise spatial scale.
- **param4 Detail** (`zoom_params.w`) → `starCutoff = mix(0.99, 0.999, w)` — replaces
  the hard-coded `0.995` star hash threshold (also reused for the star halo).

### 2. Audio layer separation
- `mids = plasmaBuffer[0].y` drives a time-scaled drift offset on the mid-scale
  density layer (`density2`, fbm at 2× frequency).
- `treble = plasmaBuffer[0].z` drives a faster, differently-directed drift on the
  fine-scale layer (`density3`, fbm at 4× frequency).
- The strata therefore shear apart with the music while the base layer stays put.
- Bass still drives the chromatic-aberration offset exactly as before; added a
  subtle bass-reactive brightness shimmer (`color *= 1.0 + bass * 0.12 * ...`)
  gated on gas density so dark space stays dark.

### 3. Extra domain warp
One additional `fbm3` lookup (3 octaves, offset seed `vec3(31.4, -17.2, time*0.15)`)
produces a scalar warp that displaces `noisePos` via an asymmetric vector before
the density evaluation — more turbulent billowing without extra noise cost.

### 4. Preserved soul / contract
- ACES tonemap and the `0.85` input blend kept intact.
- Mouse stellar-wind swirl, wind core glow, twinkling stars, palette untouched
  (added only a palette-tinted star halo using the same cutoff).
- Canonical 13-binding layout unchanged; no bindings added/renumbered.
- `@workgroup_size(16, 16, 1)` unchanged.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- `textureSampleLevel(..., 0.0)` used for both sampler reads; no reserved
  identifiers; `extraBuffer` untouched.

### 5. JSON
`shader_definitions/generative/gen_kimi_nebula.json`: added `updatedParams`
(4 entries, index 0–3, mirroring existing params names/defaults/min/max/step)
and `"updated": true`. Nothing else changed. `json.load` passes.

## QA flags
- `wgsl_precommit_gate.py`: **exit 0, 0 warnings** (naga OK, bindgroup compatible).
- JSON parse: **OK**.
- No QA flags. Star-halo neighbor lookup reuses `hash3` on an offset cell — cheap
  and deterministic, no feedback dependency.

## No-GPU caveat
This VM has no GPU adapter (`navigator.gpu.requestAdapter()` → null), so the
shader was validated only via the naga/bindgroup precommit gate and JSON parse.
**Visual QA (slider feel, strata separation with audio, warp turbulence) is
deferred to real hardware.**
