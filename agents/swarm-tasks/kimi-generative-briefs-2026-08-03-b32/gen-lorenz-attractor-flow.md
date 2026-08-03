# Swarm Brief — gen-lorenz-attractor-flow (batch b32, role: interactivist)

- **ID**: gen-lorenz-attractor-flow
- **Name**: Lorenz Attractor Flow
- **Category**: generative
- **Description**: Real-time visualization of the Lorenz strange attractor using GPU-accelerated ODE integration. Features chaotic butterfly-wing patterns, mouse perturbation, temporal feedback, chromatic dispersion, and temporal color evolution.
- **Current lines**: 137  |  **Target**: 197–227 (+60 to +90)

## Existing updatedParams (preset contract — keep names/defaults EXACTLY, indices 0-3)
  - index 0: "Integration Speed" default=0.5 min=0.0 max=1.0 step=0.01
  - index 1: "Color Shift" default=0.5 min=0.0 max=1.0 step=0.01
  - index 2: "Glow Intensity" default=0.5 min=0.0 max=1.0 step=0.01
  - index 3: "Mouse Influence" default=0.5 min=0.0 max=1.0 step=0.01

## Role instructions
Geometry mandate (primary): make the geometry reactive — mouse orbit camera built from u.zoom_config.yz (already normalized 0-1, y=0 top: do NOT re-normalize or flip), click ripples that deform/displace the geometric forms, and REAL audio reactivity (plasmaBuffer[0].xyz bass/mids/treble; extraBuffer[5..132] FFT bins read-only) driving scale/twist/fold of the 3D and 2D geometry.

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
1. `gen-lorenz-attractor-flow.wgsl` — complete, self-contained upgraded shader (canonical header).
2. `gen-lorenz-attractor-flow.json` — complete upgraded metadata.
3. `gen-lorenz-attractor-flow.md` — changelog: what changed & why, loop budget/perf estimate, rating prediction.

Reference pattern: public/shaders/gen-audiovisual-mandelbulb-raymarcher.wgsl
