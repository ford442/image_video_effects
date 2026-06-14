# Shader Upgrade Task: `quad-mirror`

## Metadata
- **Shader ID**: quad-mirror
- **Agent Role**: Optimizer
- **Current Size**: 3256 bytes
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
//  Quad Mirror — Batch D Upgrade
//  Category: geometric
//  Features: mouse-driven, geometry, upgraded-rgba, fbm-domain-warp,
//            audio-reactive, seam-warp
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

const TAU: f32 = 6.28318530718;
const MIN_ZOOM: f32 = 0.1;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * vec2<f32>(0.1031, 0.1030);
  let a = dot(pp, vec2<f32>(127.1, 311.7));
  let b = dot(pp + 1.0, vec2<f32>(269.5, 183.3));
  let c = sin(vec2<f32>(a, b));
  return fract(c * 43758.5453 + pp);
}

fn fbm2(p: vec2<f32>, t: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let h = hash22(pp + t * 0.1 * f32(i + 1));
    v += a * (h.x - 0.5);
    pp = pp * 2.3 + h.yx;
    a *= 0.5;
  }
  return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  let px = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let hOffset = (u.zoom_params.x - 0.5) * 0.4;
  let vOffset = (u.zoom_params.y - 0.5) * 0.4;
  let seamWarpAmt = u.zoom_params.z * 0.05;
  // Bass boosts rotation speed for beat-locked spin
  let rotation = u.zoom_params.w * TAU + time * 0.1 * (1.0 + bass * 0.3);

  // Treble → seam warp shimmer
  let warpShimmer = seamWarpAmt * (1.0 + treble * 0.5);

  // Mirror transform with animated rotation
  let rel = uv - mouse;
  let c = cos(rotation);
  let s = sin(rotation);
  let rx = rel.x * c - rel.y * s;
  let ry = rel.x * s + rel.y * c;

  let zoom = max(MIN_ZOOM, 0.5);
  var sampleUV = mouse - vec2<f32>(abs(rx + hOffset), abs(ry + vOffset)) / zoom;

  // FBM domain warp at seam boundaries (±5% around mirror lines)
  let seamH = abs(rx);
  let seamV = abs(ry);
  let nearSeamH = smoothstep(0.0, 0.05 * zoom, seamH);
  let nearSeamV = smoothstep(0.0, 0.05 * zoom, seamV);
  let nearSeam = max(1.0 - nearSeamH, 1.0 - nearSeamV);

  let warpX = fbm2(sampleUV * 20.0 + time, time * 0.5) * warpShimmer * nearSeam;
  let warpY = fbm2(sampleUV * 20.0 + vec2<f32>(5.2, 1.3), time * 0.5) * warpShimmer * nearSeam;
  sampleUV = sampleUV + vec2<f32>(warpX, warpY);

  var color = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Alpha: preserves src.a, reduces at seams proportional to warp amount
  let seamAlphaReduction = warpShimmer * nearSeam * 2.0;
  color.a = max(0.3, color.a - seamAlphaReduction);

  // Mids → saturation boost for audio-reactive colour pop
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let satBoost = 1.0 + mids * 0.4;
  color = vec4<f32>(mix(vec3<f32>(luma), color.rgb, satBoost), color.a);

  textureStore(writeTexture, px, color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, px, color);
}

```

## Current JSON Definition
```json
{
  "id": "quad-mirror",
  "name": "Quad Mirror",
  "url": "shaders/quad-mirror.wgsl",
  "description": "4-way kaleidoscope mirror with FBM domain warp at seam boundaries, animated rotation, and audio-reactive seam shimmer.",
  "params": [
    {
      "id": "hOffset",
      "name": "H Mirror Offset",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "vOffset",
      "name": "V Mirror Offset",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "seamWarp",
      "name": "Seam Warp",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "rotation",
      "name": "Rotation",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "geometry",
    "upgraded-rgba",
    "fbm-domain-warp",
    "audio-reactive"
  ],
  "tags": [
    "filter",
    "image-processing",
    "kaleidoscope",
    "mirror",
    "geometric",
    "audio-reactive"
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
