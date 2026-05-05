# Shader Upgrade Task: `quad-mirror`

## Metadata
- **Shader ID**: quad-mirror
- **Agent Role**: Optimizer
- **Current Size**: 3256 bytes
- **Target Line Count**: ~110 lines
- **Status**: pending

## Immutable Rules
The following MUST NOT be changed:
1. The 13-binding contract header (copy exactly).
2. The `Uniforms` struct definition.
3. `@workgroup_size` unless the shader already uses shared memory or explicit local_invocation_id math.
4. Do NOT install new npm packages.
5. Do NOT modify Renderer.ts, types.ts, or bind groups.

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

---

## Current WGSL Source
```wgsl
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  var uv = vec2<f32>(global_id.xy) / resolution;
  var mouse = u.zoom_config.yz;

  // Quad Mirror Logic
  // The mouse position defines the center of the coordinate system.
  // We reflect everything around the X and Y axes defined by the mouse.

  // Relative coordinates
  let rel = uv - mouse;
  let rot = mix(0.0, 6.283, u.zoom_params.z);
  let c = cos(rot);
  let s = sin(rot);
  let rel_rot = vec2<f32>(rel.x * c - rel.y * s, rel.x * s + rel.y * c);

  // Reflect: absolute distance from center
  let abs_x = abs(rel_rot.x);
  let abs_y = abs(rel_rot.y);

  // Sample Coordinate
  // We want to sample from the "positive" quadrant (or whatever quadrant the source image is best in)
  // relative to the mouse?
  // Let's make it so that the image is mirrored around the mouse lines.

  // Simple Kaleidoscope:
  // sample_uv = mouse + vec2(abs_x, abs_y);
  // This mirrors the bottom-right quadrant to all others.

  // Params
  let mode = u.zoom_params.x; // 0 = Mirror, 1 = Repeat?
  let zoom = u.zoom_params.y; // Zoom into the center? 1.0 = Normal

  // Adjust zoom (avoid divide by zero)
  let z = max(0.1, zoom);

  // Scaled offsets
  let off_x = abs_x / z;
  let off_y = abs_y / z;

  // We need to map these back to valid UV space.
  // If we just use mouse + off, we might sample out of bounds.
  // u_sampler usually repeats or clamps. If repeat, we get tiling.

  // Let's try to make a "Quad Mirror" where the image looks symmetrical.
  // We sample at: mouse - offset (to look "inwards"?) or mouse + offset?

  // Let's try:
  let sample_uv = vec2<f32>(
      mouse.x - off_x,
      mouse.y - off_y
  );

  // If we want 4-way symmetry, we just use the calculated sample_uv.
  // The sign of (uv - mouse) determined which quadrant we are in, but we took abs(), so now we are always sampling from top-left relative to mouse.

  let color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);

  let edge_softness = mix(1.0, smoothstep(0.0, 0.1, min(abs_x, abs_y)), u.zoom_params.w);

  textureStore(writeTexture, vec2<i32>(global_id.xy), color * edge_softness);

  // Pass depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "quad-mirror",
  "name": "Quad Mirror",
  "url": "shaders/quad-mirror.wgsl",
  "category": "image",
  "description": "Kaleidoscope-like 4-way mirror reflection centered on the mouse.",
  "params": [
    {
      "id": "mode",
      "name": "Mode",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Mirror mode blend"
    },
    {
      "id": "zoom",
      "name": "Zoom",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Zoom level of the mirrored image"
    },
    {
      "id": "rotation",
      "name": "Rotation",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Rotation of the mirror pattern"
    },
    {
      "id": "edge_softness",
      "name": "Edge Softness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Softness of mirror sector edges"
    }
  ],
  "features": [
    "mouse-driven",
    "geometry"
  ],
  "tags": [
    "filter",
    "image-processing"
  ]
}

```

---

## Agent Specialization
# Agent Role: The Optimizer

## Identity
You are **The Optimizer**, a shader architect focused on performance, elegance, and pipeline integration.

## Upgrade Toolkit

### Performance Techniques
- Brute force → Early exit conditions
- Full resolution → Quarter-res blur + full-res combine
- Per-pixel noise → Blue noise sampling
- Redundant texture samples → Bilinear LOD
- Nested loops → Unrolled small kernels

### Code Elegance
- Magic numbers → Named constants
- Duplicated code → Helper functions
- Long functions → Logical sections with comments
- Hard-coded params → Uniform-based tuning
- GPU-unfriendly ops → Precomputed lookups

### Pipeline Integration
- Standalone → Designed for slot chaining
- No feedback → Uses dataTextureA/B for state
- LDR only → HDR output ready for tone map
- Single pass → Multi-pass decomposition hint
- Fixed quality → Level-of-detail scaling

### Post-Process Ready
- Expose bloom threshold metadata
- Tag as "expects pp-tone-map" if HDR
- Document slot recommendations
- Provide quality presets (low/medium/high)

## Quality Checklist
- [ ] No per-pixel branching on uniforms
- [ ] Texture samples minimized (caching used)
- [ ] Workgroup size optimized (16x16 for Pixelocity)
- [ ] Early exit for sky/background pixels
- [ ] LOD quality scaling based on frame time

## Output Rules
- Keep the original "soul" of the shader while making it production-ready.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- Preserve or enhance RGBA channel usage.
- Add JSON params if new tunable values are introduced (max 4 params mapped to zoom_params).

## Performance Constraint
This shader must remain efficient for 3-slot chained rendering. Avoid excessive nested loops, minimize texture samples, and prefer branchless math. If adding features, keep total line count within the target specified in the task metadata.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 110 lines (±20%).
5. Write a brief upgrade rationale (2-3 sentences).

## Output Format
Return exactly two code blocks:
1. ```wgsl
[upgraded shader source]
```
2. ```json
[updated shader definition]
```

If the JSON does not need changes, return the original JSON unchanged.
