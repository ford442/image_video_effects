# Shader Upgrade Task: `digital-lens`

## Metadata
- **Shader ID**: digital-lens
- **Agent Role**: Optimizer
- **Current Size**: 3238 bytes
- **Target Line Count**: ~140 lines
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
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BlockSize, y=Radius, z=GridOpacity, w=ColorTint
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let block_size = max(2.0, u.zoom_params.x * 50.0 + 2.0); // 2 to 52 pixels
    let radius = u.zoom_params.y * 0.4 + 0.05;
    let grid_opacity = u.zoom_params.z;
    let tint_strength = u.zoom_params.w;

    // Mouse
    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Smooth circle mask
    let mask = 1.0 - smoothstep(radius, radius + 0.05, dist);

    var color: vec4<f32>;

    if (mask > 0.001) {
        // Inside digital lens: Pixelate
        let blocks = resolution / block_size;
        let uv_quantized = floor(uv * blocks) / blocks + (0.5 / blocks);

        let pixelated = textureSampleLevel(readTexture, non_filtering_sampler, uv_quantized, 0.0);
        let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

        // Grid lines
        let uv_pixel = uv * resolution;
        let grid_x = step(block_size - 1.0, uv_pixel.x % block_size);
        let grid_y = step(block_size - 1.0, uv_pixel.y % block_size);
        let grid_line = max(grid_x, grid_y);

        var lens_color = pixelated;

        // Green matrix tint
        let tint = vec4<f32>(0.0, 1.0, 0.2, 1.0);
        lens_color = mix(lens_color, lens_color * tint * 1.5, tint_strength);

        // Add grid
        lens_color = mix(lens_color, vec4<f32>(0.0, 0.0, 0.0, 1.0), grid_line * grid_opacity);

        // Mix based on mask edge (soft transition)
        color = mix(original, lens_color, mask);

    } else {
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}

```

## Current JSON Definition
```json
{
  "id": "digital-lens",
  "name": "Digital Lens",
  "url": "shaders/digital-lens.wgsl",
  "category": "image",
  "description": "A lens that pixelates the image and adds a digital grid under the cursor.",
  "params": [
    {
      "id": "block",
      "name": "Pixel Size",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "radius",
      "name": "Lens Radius",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "grid",
      "name": "Grid Opacity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "tint",
      "name": "Matrix Tint",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    }
  ],
  "features": [
    "mouse-driven"
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


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 140 lines (±20%).
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
