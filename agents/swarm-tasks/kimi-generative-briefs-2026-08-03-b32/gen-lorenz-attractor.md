# Swarm Brief — gen-lorenz-attractor (batch b32, role: optimizer)

- **ID**: gen-lorenz-attractor
- **Name**: Lorenz Attractor
- **Category**: generative
- **Description**: Strange attractor density accumulation. Each pixel seeds a short Lorenz trajectory near an equilibrium lobe; Gaussian kernel splatting onto the x-z projection builds the iconic butterfly over many frames of temporal Monte Carlo integration. Bass widens the rho parameter for more chaotic spread; mouse pans the view.
- **Current lines**: 140  |  **Target**: 200–230 (+60 to +90)

## Existing updatedParams (preset contract — keep names/defaults EXACTLY, indices 0-3)
  - index 0: "Sigma" default=0.5 min=0 max=1 step=0.01
  - index 1: "Rho (Chaos)" default=0.35 min=0 max=1 step=0.01
  - index 2: "Glow Radius" default=0.25 min=0 max=1 step=0.01
  - index 3: "Trail Decay" default=0.5 min=0 max=1 step=0.01

## Role instructions
Geometry mandate (primary): integrate geometric complexity at budget — adaptive raymarch step counts, LOD on FBM/tessellation detail, early exits, named constants, select/mix over branches. Ensure every declared slider is LIVE in the WGSL and every declared feature is real (no dead sliders, no fake FFT, no mask-as-color).

Wire all 4 sliders to MEANINGFUL shader-specific constants (geometry scale/fold/twist, light, reactivity, palette...). Every slider must be live. Preserve the shader's soul — upgrade, don't rewrite.

JSON deliverable: keep id/name/url/category and the 4 updatedParams above EXACTLY; keep `"updated": true`; add `"supportsDepth": true` if you write real depth; you may extend tags with geometry tags and refresh the description.

## Non-negotiable contract

- Canonical 13-binding header verbatim (see agents/WGSL_BUILTINS_GENERATIVE.md §0); Uniforms struct EXACTLY:
  `config, zoom_config, zoom_params, ripples` — no extra/reordered fields.
- `@compute @workgroup_size(16, 16, 1)` (3 explicit dims) + resolution bounds guard on global_invocation_id.
- Write `writeTexture`, `writeDepthTexture`, and `dataTextureA` EVERY frame.
- Only `textureSampleLevel`/`textureLoad`/`textureStore`. NO `tan`, `textureSample`, `dpdx`, `dpdy`. No WGSL reserved words as identifiers.
- Uniform truth: config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY(top-down), mouseDown].
  Guard ripple loops with `min(u32(u.config.y), 50u)`.
- extraBuffer: [0..4] engine-reserved, [5..132] engine FFT bins (read-only); persistent state ONLY in [133..255],
  single-writer guard (gid.x==0u && gid.y==0u) + arrayLength check.
- Audio ONLY from plasmaBuffer[0].xyz (bass/mids/treble) and FFT bins — no hash-based fake spectrum.
- Semantic alpha — never hardcode 1.0 unless opaque by design. No flat-0.0 depth clobber: write real depth (or passthrough).
- Prefer select/mix over per-pixel branches. No inverted smoothstep falloffs.

## Deliverables (write to the batch output dir given in your task prompt)
1. `gen-lorenz-attractor.wgsl` — complete, self-contained upgraded shader (canonical header).
2. `gen-lorenz-attractor.json` — complete upgraded metadata.
3. `gen-lorenz-attractor.md` — changelog: what changed & why, loop budget/perf estimate, rating prediction.

Reference pattern: public/shaders/gen-audiovisual-mandelbulb-raymarcher.wgsl
