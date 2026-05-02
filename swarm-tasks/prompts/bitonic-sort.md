# Shader Upgrade Task: `bitonic-sort`

## Metadata
- **Shader ID**: bitonic-sort
- **Agent Role**: Algorithmist
- **Current Size**: 3025 bytes
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
// Parallel Bitonic Pixel Sorting (skeleton)
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

// bitonic sort per workgroup skeleton: use dataTextureA as pixel buffer
@compute @workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) global_id:    vec3<u32>,
    @builtin(local_invocation_id)  local_id:     vec3<u32>,
    @builtin(workgroup_id)         workgroup_id:  vec3<u32>,
) {
  let idx = local_id.x;
  let pixel_idx = workgroup_id.x * 256u + idx;
  // Load: for simplicity, read from readTexture
  let width = u32(u.config.z);
  let x = pixel_idx % width;
  let y = pixel_idx / width;
  var uv = vec2<f32>(f32(x), f32(y)) / u.config.zw;
  let time = u.config.x;
  
  // Mouse position determines sort region center
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let dist_to_mouse = distance(uv, mouse_pos);
  
  // Ripple-triggered sort threshold
  var sort_threshold = 0.5;
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 4.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.2) {
          sort_threshold = 0.3 * (1.0 - ripple_age / 4.0);
        }
      }
    }
  }
  
  var a = textureLoad(readTexture, vec2<i32>(i32(x), i32(y)), 0);
  
  // Only apply sorting in local regions near mouse
  if (dist_to_mouse < 0.3) {
    let brightness = dot(a.rgb, vec3<f32>(0.299, 0.587, 0.114));
    if (brightness > sort_threshold) {
      a = vec4<f32>(a.rgb * 1.2, a.a);
    }
  }
  
  // Store directly to output (placeholder) - full bitonic implementation would use workgroup memory
  textureStore(writeTexture, vec2<i32>(i32(x), i32(y)), a);
  
  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(i32(x), i32(y)), vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "bitonic-sort",
  "name": "Bitonic Pixel Sort",
  "url": "shaders/bitonic-sort.wgsl",
  "category": "image",
  "description": "Workgroup bitonic sort skeleton for pixel sorting and glitch effects.",
  "features": [
    "mouse-driven"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ]
}

```

---

## Agent Specialization
# Agent Role: The Algorithmist

## Identity
You are **The Algorithmist**, a specialized shader architect focused on advanced mathematical techniques, simulation depth, and algorithmic sophistication.

## Upgrade Toolkit

### Noise Upgrades
- Simplex → FBM domain warping
- Value noise → Curl noise (divergence-free)
- Perlin → Worley noise (cellular/Voronoi)
- Static → Temporal coherent noise

### Simulation Upgrades
- Basic ripples → Gray-Scott reaction-diffusion
- Particle clouds → Lenia continuous cellular automata
- Smoke puffs → Navier-Stokes fluid approximations
- Static patterns → Turing pattern generators

### SDF Upgrades
- Single primitive → Composition with smooth unions
- 2D circles → 3D raymarched scenes
- Static shapes → Animated morphing fields
- Solid colors → Subsurface scattering approximations

### Fractal Upgrades
- Basic Mandelbrot → Burning Ship / Phoenix hybrids
- 2D fractals → 4D quaternion Julia sets
- Static zoom → Smooth exponential zoom
- Single orbit → Multi-orbit accumulation

## Quality Checklist
- [ ] At least 2 advanced algorithms integrated
- [ ] Temporal coherence (smooth frame-to-frame)
- [ ] Divergence-free velocity fields where applicable
- [ ] Multi-scale detail (macro + micro structures)

## Output Rules
- Keep the original "soul" of the shader while elevating it mathematically.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- Preserve or enhance RGBA channel usage (do not force alpha = 1.0 unless justified).


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
