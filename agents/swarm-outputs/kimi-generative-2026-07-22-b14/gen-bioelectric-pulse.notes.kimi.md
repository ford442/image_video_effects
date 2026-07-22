# gen-bioelectric-pulse — Interactivist Notes (Batch 14, Kimi)

**Date:** 2026-07-22
**Shader:** `public/shaders/gen-bioelectric-pulse.wgsl`
**JSON:** `shader_definitions/generative/gen-bioelectric-pulse.json`

## Line delta

- Before: 180 lines → After: **245 lines** (**+65**, within the +50–90 target; 245 ∈ [230, 270] ✓)

## Key changes per technique

### 1. Mouse bug fix (priority 1)
- `u.zoom_config.xy` was reading **Time** as mouse X (engine convention verified in
  `src/renderer/UniformBuffer.ts`: `zoom_config = [time, mouseX, mouseY, mouseDown]`).
- Fixed to `u.zoom_config.yz` for position, `.w` for down. Updated the struct field
  comment to `// x=Time, y=MouseX, z=MouseY, w=MouseDown`.
- The mouse pulse now actually follows the cursor instead of being glued to a
  drifting time coordinate.

### 2. Honest reaction trails (dataTextureC feedback)
- Added `prevFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb`.
- Trail accumulator: `trail = prevFrame * 0.9 + col * inject` (decay 0.9, inject ~0.07–0.14
  driven by Pulse Width), clamped **pre-tint** at `vec3(1.2)` (luma-echo-warp lesson).
- Trail persisted to `dataTextureA` pre-tint/clamped; `writeTexture` gets
  `clamp(trail * trailTint, 0, 1)`. Final 0–1 output clamp preserved.
- Pattern mirrors gen-neural-dust (batch 13) which already validated in this engine.

### 3. Kick mega-pulse (extraBuffer persistent state)
- `extraBuffer[133]` = smoothed bass envelope (fast attack 0.35 / slow release 0.04 follower).
- `extraBuffer[134]` = last kick trigger time.
- Only invocation `(0,0)` integrates state (avoids per-thread write races; established pattern
  from acoustic-string-theory). All other invocations just read.
- Kick condition: `bass > env * 1.25 + 0.12` with a **0.3 s retrigger gap**.
- New `megaPulse()` helper: expanding shockwave ring from screen center + hot core
  afterglow, age-faded over ~2.5 s; Speed drives expansion rate, Pulse Width drives
  ring sharpness/glow. State confined to **[133..255]** — no FFT bins touched.

### 4. Slider params rewired to real constants
- Existing mapping already used the correct ids; each slider now verifiably drives
  shader-specific constants (documented in a comment block in main):
  - **Pulse Count** (zoom_params.x) → number of wandering reaction centers (1–5).
  - **Pulse Speed** (zoom_params.y) → wave phase speed **and** kick shockwave expansion.
  - **Pulse Width** (zoom_params.z) → pulse glow radius **and** trail injection strength.
  - **Hue Shift** (zoom_params.w) → palette phase **and** phosphor trail tint.

## Binding contract / structural compliance

- Canonical 13-binding layout unchanged (0–12, no additions/renumbering, no binding 13).
- `@workgroup_size(16, 16, 1)` preserved.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- Sampler reads use `textureSampleLevel(..., 0.0)`; no reserved WGSL identifiers.
- Core algorithm (fbm substrate, 5 wandering pulse centers, vein mask, sparkle,
  vignette, wandering-center motion) fully preserved — upgrade, not rewrite.

## JSON status

- Added `updatedParams` (exactly 4 entries, index 0–3, mirroring existing params:
  same names/defaults/min/max/step). `"updated": true` was already present.
- Nothing else in the JSON touched. `json.load` passes.

## QA flags

- Gate: `python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-bioelectric-pulse.wgsl`
  → **exit 0, 1 passed, 0 warnings** (naga OK, bindgroup compatible).
- Cross-invocation read of extraBuffer[133/134] written by invocation (0,0) in the same
  dispatch is technically racy, but this is the established engine pattern (same as
  acoustic-string-theory) and worst case is a 1-frame envelope lag.
- **No-GPU caveat:** this Cloud VM has no WebGPU adapter, so visual QA (trail decay feel,
  kick threshold sensitivity, mega-pulse brightness balance) is **deferred to real
  hardware**. Constants were chosen conservatively from the batch-13 reference shader.
