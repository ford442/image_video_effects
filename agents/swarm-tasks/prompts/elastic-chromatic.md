# Shader Upgrade Task: `elastic-chromatic`

## Metadata
- **Shader ID**: elastic-chromatic
- **Agent Role**: Optimizer
- **Current Size**: 3089 bytes
- **Target Line Count**: ~130 lines
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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=LagRed, y=LagBlue, z=MouseInfluence, w=Unused
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    // High lag value = slow update = more ghosting
    let baseLagR = u.zoom_params.x; // 0..1
    let baseLagB = u.zoom_params.y; // 0..1
    let mouseInfluence = u.zoom_params.z;

    // Mouse influence
    var mouse = u.zoom_config.yz;
    let dist = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));

    // Increase lag near mouse? Or decrease?
    // Let's make mouse *slow down* time (increase lag).
    // range: 0 to 1
    let influence = smoothstep(0.5, 0.0, dist) * mouseInfluence;

    // Effective lag
    // If lag is 1.0, we never update (freeze). If 0.0, instant update.
    let lagR = clamp(baseLagR + influence, 0.0, 0.99);
    let lagB = clamp(baseLagB + influence * 0.5, 0.0, 0.99);

    // Read History (Previous Frame)
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    // history.r = Old Red
    // history.b = Old Blue
    // history.g = Old Green (but we usually don't lag green, to keep structure)

    // Read Current Input
    let curr = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Update Channels
    // New = History * Lag + Curr * (1 - Lag)
    // This is an exponential moving average (EMA)

    let newR = mix(curr.r, history.r, lagR);
    let newB = mix(curr.b, history.b, lagB);
    let newG = curr.g; // Green is instant (anchor)

    let finalColor = vec4<f32>(newR, newG, newB, 1.0);

    // Output for display
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

    // Output for history
    textureStore(dataTextureA, global_id.xy, finalColor);

    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}

```

## Current JSON Definition
```json
{
  "id": "elastic-chromatic",
  "name": "Elastic Chromatic",
  "url": "shaders/elastic-chromatic.wgsl",
  "category": "image",
  "description": "Simulates color channel lag (ghosting) that responds to mouse proximity.",
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "lagR",
      "name": "Red Lag",
      "default": 0.8,
      "min": 0.0,
      "max": 0.99
    },
    {
      "id": "lagB",
      "name": "Blue Lag",
      "default": 0.6,
      "min": 0.0,
      "max": 0.99
    },
    {
      "id": "influence",
      "name": "Mouse Drag",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "unused",
      "name": "Unused",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0
    }
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
4. Ensure the upgraded shader is roughly 130 lines (±20%).
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
