# pixel-stretch-cross — Kimi Visualist Upgrade Notes (2026-07-21)

**Line count:** 223 → 283 (**+60**, target 273–313 ✅)
**Gate:** `wgsl_precommit_gate.py` exit 0 (naga OK, bindgroup compatible, workgroup OK)
**JSON:** parses clean; brief version used verbatim (4 `updatedParams`, index 0–3)

## Changes by domain

### Slider wiring (4 params via u.zoom_params.x/y/z/w)
- **x → Stretch Amplitude** (default 0.5): maps to `ampScale = 0.06 + x*0.42`; default ≈ old per-axis feel (old fixed 0.15/axis at defaults).
- **y → Axis Blend** (default 0.5): manual H↔V bias; 0 = full V-stretch, 1 = full H-stretch.
- **z → Bloom Intensity** (default 0.3): scales the new HDR crossing bloom.
- **w → Bass Response** (default 0.5): `stretchScale = 1.0 + smoothBass * (0.15 + w*1.1)`; default ≈ old 0.6 bass gain.
- Legacy depth/turbulence sliders demoted to constants (`DEPTH_INFLUENCE = 0.5`, `TURBULENCE = 0.5`) at their old defaults — core character preserved.

### Motion / interactivity
- **Mouse-velocity axis steering:** mouse state tracked in `extraBuffer[0..3]` (prev mouse uv + smoothed velocity, house pattern). Horizontal flicks favor H-stretch, vertical flicks favor V-stretch (`velAxis` from |vx|−|vy|, confidence-gated by speed so the slider rules at rest).
- **Flick twist:** fast pointer motion adds a transient rotation (`flickTwist`) to the global drift angle.

### Audio
- **Bass-pulse amplitude:** stretch magnitude now breathes with the attack/release-smoothed bass envelope, scaled by the Bass Response slider (was a fixed 0.6 gain).
- Bloom gain gets a subtle bass heartbeat (`1.0 + smoothBass*0.4`).

### Color / cinematic polish
- **HDR bloom on stretch crossings:** new `crossingBloom()` helper (quadratic hot + linear term), masked by `crossEnergy` (ray-overlap accumulation) × mouse gravity well. Added to the trail **before** ACES tonemapping — never after.
- Bloom slightly thickens alpha (`bloomAlpha`) so crossings read as luminous paint.

### Structure / contract (unchanged)
- Canonical 13-binding layout verbatim, no binding 13 (shader doesn't use history ring).
- `@workgroup_size(16, 16, 1)`; writes `writeTexture` + `writeDepthTexture` + `dataTextureA` every frame.
- All sampler reads via `textureSampleLevel(..., 0.0)`; feedback via `textureLoad(dataTextureC, ...)`.
- Core algorithm untouched: Fibonacci disk 16-ray sampling, mouse gravity well, depth attenuation, click shockwave rings, temporal trail, layered alpha compositing.
- `dataTextureA.g` now also carries `crossMask` (was 0.0) — free debug/chain channel.

## QA flags
- **Eyeballed constants:** ampScale range (0.06–0.48), velocity confidence gain (×40), velAxis gain (×20), velocity steer weight (0.8), flickTwist clamp (0.6), bloom gain (×1.8), crossMask smoothstep (0.10–0.85) — all tuned by feel, not visually verified.
- **No-GPU caveat:** Cloud VM has no WebGPU adapter; validated via naga + bindgroup gate only. Visual behavior (bloom threshold, velocity steering feel) unverified on real hardware.
- **extraBuffer race:** mouse state in extraBuffer[0..3] is written by all threads non-atomically — benign here (all threads compute the same uniform values; matches existing house pattern in e.g. gen-cybernetic-mycelium-neural-web.wgsl).
- **Slider re-scope:** updatedParams remap zoom_params.z/w away from legacy depth_influence/turbulence (now constants). This follows the brief exactly; legacy `params` array kept in JSON for compatibility.
