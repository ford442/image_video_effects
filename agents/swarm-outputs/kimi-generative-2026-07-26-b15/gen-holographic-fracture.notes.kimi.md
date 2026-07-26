# gen-holographic-fracture — Batch 15 upgrade notes (kimi)

## Line delta
- Before: 183 lines → After: 267 lines (+84, within brief target 233–273 / +50–90)

## Key changes per technique

### 1. Mouse bug fix (priority 1)
- Changed `u.zoom_config.xy` → `u.zoom_config.yz` for the mouse crack origin
  (x is TIME per `src/renderer/UniformBuffer.ts`; yz = mouse xy, w = mouse-down).
- Fixed the stale header comment: top banner + `Uniforms` struct comment now
  document `zoom_config.yz = mouse position, w = mouse-down, x = TIME`.

### 2. Honest depth (supportsDepth: true now earned)
- Replaced flat `0.0` write to `writeDepthTexture` with a real depth field:
  `substrate*0.3 + crackProximity*0.5 + rippleFrontRidge*0.2 + edgeGlow*0.1`,
  clamped to 0..1. Depth derives from crack distance (`minDist`), the Voronoi
  edge field, and the expanding click-front distance.

### 3. Click crack fronts (ripples)
- New loop over `u.ripples[]` guarded by `min(u32(u.config.y), 50u)`.
- Each click spawns an expanding ring front (`radius = age * (0.2 + pulseSpeed*0.3)`)
  plus 8 short radial spokes left behind the front (`abs(sin(ang*4))*dr`),
  fading with `exp(-age*1.4)`; ripples older than 4s are skipped.
- Front glow composes into color as a warm-to-iridescent mix.

### 4. Spring-damper mouse crack origin
- Persistent state in `extraBuffer[133..135]` ONLY:
  `[133..134]` = eased mouse position, `[135]` = init flag.
- Critically-damped exponential approach (`mix(prev, raw, 0.14)` per frame);
  first frame initializes directly to avoid a lurch from origin.

### 5. Per-bin plasma phase shifts on thin-film iridescence
- Inside the crack loop, the dominant crack at each pixel captures
  `plasmaBuffer[1 + (i % 8)].x` as `domPhase`; this phase-shifts the
  thin-film cosine palette (`iridShift += domPhase * 2π * iridescenceAmt`),
  so each crack index shimmers to its own FFT band.

### 6. Tone mapping upgrade
- Hard `clamp(col,0,1)` replaced with hue-preserving clamp (rescale by max
  channel) followed by filmic ACES (Narkowicz fit) at 1.05 exposure; final
  output re-clamped to 0..1.

## Slider wiring (4 params, unchanged ids/defaults/mappings)
- `fractureCount` → `zoom_params.x` → radial crack count (3..12) + shard cell scale.
- `iridescence` → `zoom_params.y` → thin-film amplitude + per-crack phase-shift range.
- `crackWidth` → `zoom_params.z` → crack core line width + all glow falloff radii (crack, edge, ring, spokes).
- `pulseSpeed` → `zoom_params.w` → crack pulse rate, wobble rate, AND ripple-front expansion speed.
- `updatedParams` written to JSON verbatim from the brief (indices 0–3).

## Binding contract compliance
- Canonical 13 bindings (0–12) preserved, none added/renumbered; no binding 13.
- `@workgroup_size(16, 16, 1)` preserved.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `hash22` / `valueNoise` / `fbm2` / `glow` chunk bodies preserved verbatim.
- extraBuffer persistent state confined to `[133..135]` ⊂ `[133..255]`; FFT bins [5..132] untouched.
- No WGSL reserved keywords used as identifiers.

## QA flags
- Gate: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-holographic-fracture.wgsl`
  → **GREEN**, Passed: 1, Failed: 0, Warnings: 0.
- ⚠️ naga binary unavailable in this VM (`/root/.cargo/bin/naga` missing), so
  naga validation was skipped by the gate itself; bindgroup + workgroup checks
  passed. Syntax hand-verified against WGSL conventions used by sibling shaders.
- extraBuffer[133..135] written by all invocations with identical values
  (standard pattern in this codebase, e.g. holographic-crystal.wgsl).
- GPU visual verification not possible in headless VM (no WebGPU adapter).
