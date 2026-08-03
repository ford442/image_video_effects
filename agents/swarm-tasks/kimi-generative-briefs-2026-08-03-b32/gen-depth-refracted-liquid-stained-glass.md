# Swarm Brief — gen-depth-refracted-liquid-stained-glass (batch b32, role: visualist)

- **ID**: gen-depth-refracted-liquid-stained-glass
- **Name**: Depth-Refracted Liquid Stained Glass
- **Category**: generative
- **Description**: Polar facet refraction with chromatic edge dispersion per depth edge, temporal caustic flicker, audio-driven refraction strength, and depth-aware bevel normals. Fixed float-modulus bug.
- **Current lines**: 135  |  **Target**: 195–225 (+60 to +90)

## Existing updatedParams (preset contract — keep names/defaults EXACTLY, indices 0-3)
  - index 0: "Facet Count" default=0.5 min=0 max=1 step=0.01
  - index 1: "Bevel Width" default=0.3 min=0 max=1 step=0.01
  - index 2: "Temporal Drift" default=0.5 min=0 max=1 step=0.01
  - index 3: "Chromatic Amount" default=0.5 min=0 max=1 step=0.01

## Role instructions
Geometry mandate (primary): give the forms real 3D presence — surface normals from the SDF/heightfield, 3-point lighting + Fresnel rim, ACES tonemap, material-ID driven palettes, per-facet/per-cell color variation, thin-film iridescence on geometric shells. Add 2D geometric patterning (tessellated inlays, symmetry-folded ornament) where it serves the creature/theme.

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
1. `gen-depth-refracted-liquid-stained-glass.wgsl` — complete, self-contained upgraded shader (canonical header).
2. `gen-depth-refracted-liquid-stained-glass.json` — complete upgraded metadata.
3. `gen-depth-refracted-liquid-stained-glass.md` — changelog: what changed & why, loop budget/perf estimate, rating prediction.

Reference pattern: public/shaders/gen-audiovisual-mandelbulb-raymarcher.wgsl
