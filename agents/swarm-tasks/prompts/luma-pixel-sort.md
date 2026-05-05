# Shader Upgrade Task: `luma-pixel-sort`

## Metadata
- **Shader ID**: luma-pixel-sort
- **Agent Role**: Optimizer
- **Current Size**: 3192 bytes
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
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Threshold, y=SortStrength, z=Direction, w=Glitchiness
  ripples: array<vec4<f32>, 50>,
};

// Pseudo random
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  var mousePos = u.zoom_config.yz;

  let threshold = u.zoom_params.x;
  let strength = u.zoom_params.y * 0.5; // Max displacement length
  let dirMix = u.zoom_params.z;
  let glitch = u.zoom_params.w;

  // Calculate luminance
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Mouse interaction: Modify threshold based on Y position of mouse
  // and maybe local influence
  var mouseInfluence = 0.0;
  if (abs(uv.y - mousePos.y) < 0.2) {
      mouseInfluence = 1.0 - abs(uv.y - mousePos.y) / 0.2;
  }

  // Dynamic threshold
  let localThreshold = threshold - (mouseInfluence * 0.2);

  var offset = vec2<f32>(0.0, 0.0);

  if (luma > localThreshold) {
      // "Sort" / Displace
      // The brighter the pixel, the further we look back/forward?
      // Or we shift this pixel to a new location?
      // Simple glitch sort: displace UV based on luma if above threshold

      let shift = (luma - localThreshold) * strength;

      // Add noise/glitch
      let noise = rand(vec2<f32>(uv.y, time)) * glitch;

      if (dirMix < 0.5) {
          // Vertical sort/smear
          offset.y = shift + noise * 0.1;
      } else {
          // Horizontal sort/smear
          offset.x = shift + noise * 0.1;
      }
  }

  // Sample at offset
  let srcUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let finalColor = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
}

```

## Current JSON Definition
```json
{
  "id": "luma-pixel-sort",
  "category": "artistic",
  "features": [
    "mouse-driven"
  ],
  "url": "shaders/luma-pixel-sort.wgsl",
  "description": "Glitchy pixel sorting based on luminance and mouse height.",
  "params": [
    {
      "id": "threshold",
      "name": "Threshold",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "strength",
      "name": "Sort Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "direction",
      "name": "Direction Mix",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "glitch",
      "name": "Glitchiness",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0
    }
  ],
  "tags": [
    "stylized",
    "artistic"
  ],
  "name": "Luma Pixel Sort"
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
