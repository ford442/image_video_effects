# Shader Upgrade Task: `pixel-depth-sort`

## Metadata
- **Shader ID**: pixel-depth-sort
- **Agent Role**: Optimizer
- **Current Size**: 3195 bytes
- **Target Line Count**: ~180 lines
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
// ═══════════════════════════════════════════════════════════════════
//  Pixel Depth Sort — Batch D Upgraded
//  Category: post-processing
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware
//  Complexity: Medium
//  Chunks From: pixel-depth-sort
//  Created: 2026-05-02
//  Upgraded: 2026-05-10
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  let mousePos = u.zoom_config.yz;
  let depthThreshold = u.zoom_params.x;
  let sortLengthBase = u.zoom_params.y * 40.0;
  let sortAngle = u.zoom_params.z * 6.283185307;
  let aberration = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let sortLength = sortLengthBase * (1.0 + bass * 2.0);

  let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Sort direction follows mouse position
  let angleFromMouse = atan2(mousePos.y - 0.5, mousePos.x - 0.5);
  let angle = angleFromMouse + sortAngle;
  let dir = vec2<f32>(cos(angle), sin(angle));

  // Sample 9 pixels forward along sort direction
  var colors: array<vec4<f32>, 9>;
  var depths: array<f32, 9>;

  for (var i: u32 = 0u; i < 9u; i = i + 1u) {
    let offset = dir * f32(i) * sortLength / resolution;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    colors[i] = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    depths[i] = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  }

  // Sort by depth (ascending: near to far)
  for (var i: u32 = 0u; i < 9u; i = i + 1u) {
    for (var j: u32 = 0u; j < 8u - i; j = j + 1u) {
      if (depths[j] > depths[j + 1u]) {
        let td = depths[j];
        depths[j] = depths[j + 1u];
        depths[j + 1u] = td;
        let tc = colors[j];
        colors[j] = colors[j + 1u];
        colors[j + 1u] = tc;
      }
    }
  }

  // Find where centerDepth fits in sorted depths
  var rank: u32 = 0u;
  for (var i: u32 = 0u; i < 9u; i = i + 1u) {
    if (centerDepth > depths[i]) {
      rank = rank + 1u;
    }
  }
  rank = clamp(rank, 0u, 8u);

  let sortedColor = colors[rank];

  // Chromatic aberration at sort boundaries
  let depthRange = abs(depths[8] - depths[0]);
  let boundaryStrength = smoothstep(0.05, 0.3, depthRange);
  let caOffset = dir * aberration * boundaryStrength * 4.0 / resolution;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = sortedColor.g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  let finalColor = vec3<f32>(r, g, b);

  // Alpha: near pixels more opaque
  let alpha = clamp(centerDepth, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "pixel-depth-sort",
  "name": "Pixel Depth Sort",
  "url": "shaders/pixel-depth-sort.wgsl",
  "description": "Directional pixel sorting by depth with mouse-following sort angle, chromatic aberration at boundaries, bass-driven sort length, and depth-layered alpha.",
  "features": [
    "upgraded-rgba",
    "mouse-driven",
    "audio-reactive",
    "depth-aware"
  ],
  "tags": [
    "filter",
    "depth-aware",
    "pixel-sort",
    "chromatic-aberration",
    "audio-reactive"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Depth Threshold",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Sort Length",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Sort Angle",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Aberration",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
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
- Per-pixel pseudo-random → **Blue noise or Halton sequence** (same cost, less banding)
- Redundant texture samples → Bilinear LOD
- Nested loops → Unrolled small kernels
- Expensive trig → Precomputed or polynomial approximations:
  ```wgsl
  // Fast atan2 approximation (max error ~0.0015 rad)
  fn fast_atan2(y: f32, x: f32) -> f32 {
      let a = min(abs(x), abs(y)) / (max(abs(x), abs(y)) + 1e-6);
      let s = a * a;
      var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
      if (abs(y) > abs(x)) { r = 1.5707963 - r; }
      if (x < 0.0) { r = 3.1415927 - r; }
      if (y < 0.0) { r = -r; }
      return r;
  }
  // Fast exp approximation
  fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }
  ```

#### 7-tap hex bokeh kernel (perceptually equals 19-tap circular at lower cost)
```wgsl
const HEX_TAPS = array<vec2<f32>, 7>(
    vec2<f32>( 0.0,  0.0),
    vec2<f32>( 1.0,  0.0), vec2<f32>( 0.5,  0.866),
    vec2<f32>(-0.5,  0.866), vec2<f32>(-1.0,  0.0),
    vec2<f32>(-0.5, -0.866), vec2<f32>( 0.5, -0.866),
);
```
Use for radial-blur, DOF, and glow shaders. Scale each tap by `radius / res` before sampling `readTexture`.

#### Anti-moiré LOD bias for procedural noise
```wgsl
let lod = clamp(log2(max(fwidth(uv).x, fwidth(uv).y) * cell_freq), 0.0, 4.0);
let p = uv * (cell_freq * exp2(-lod));
```
Kills the shimmer that plagues high-frequency procedural patterns (fractal / kaleidoscope shaders) when zoomed out. `cell_freq` is the base tile frequency.

### Workgroup Shared Memory (tiling pattern for blur/filter kernels)
```wgsl
var<workgroup> tile: array<array<vec4<f32>, 18>, 18>; // 16x16 + 1px border
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>,
        @builtin(local_invocation_id) lid: vec3<u32>) {
    // Load tile including borders, then sync
    tile[lid.y+1][lid.x+1] = textureSampleLevel(readTexture, u_sampler,
        vec2<f32>(gid.xy) / vec2<f32>(u.config.zw), 0.0);
    workgroupBarrier();
    // All accesses to tile[] now L1-cached — no global texture reads in hot loop
}
```

### Code Elegance
- Magic numbers → Named constants (see Algorithmist for PI/TAU/PHI/etc.)
- Duplicated code → Helper functions
- Long functions → Logical sections with comments
- Hard-coded params → Uniform-based tuning via `zoom_params`
- GPU-unfriendly ops → Precomputed lookups

### Pipeline Integration
- Standalone → Designed for slot chaining
- No feedback → Uses dataTextureA/B for state
- LDR only → HDR output ready for tone map
- Single pass → Multi-pass decomposition hint
- Fixed quality → Level-of-detail scaling

### Post-Process Ready
- Expose bloom threshold via alpha channel (`alpha = bloom_weight`)
- Tag as "expects pp-tone-map" if HDR
- Document slot recommendations
- Provide quality presets (low/medium/high)

## Quality Checklist
- [ ] No per-pixel branching on uniforms
- [ ] Texture samples minimized (caching used)
- [ ] Workgroup size optimized (16x16 for Pixelocity)
- [ ] Early exit for sky/background pixels
- [ ] LOD quality scaling based on frame time
- [ ] Anti-moiré LOD bias applied for high-frequency procedural patterns
- [ ] Hex bokeh kernel used in place of naive circular sampling where applicable

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
4. Ensure the upgraded shader is roughly 180 lines (±20%).
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
