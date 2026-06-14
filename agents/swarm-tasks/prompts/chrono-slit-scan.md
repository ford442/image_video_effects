# Shader Upgrade Task: `chrono-slit-scan`

## Metadata
- **Shader ID**: chrono-slit-scan
- **Agent Role**: Optimizer
- **Current Size**: 3242 bytes
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
//  Chrono Slit Scan — Batch D Upgrade
//  Category: artistic
//  Features: temporal-persistence, audio-reactive, fbm-warp, sdf-composition,
//            upgraded-rgba, multi-slit
//  Complexity: Medium
//  Created: 2026-05-10
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

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters (bass → slit width pulse, treble → edge feather shimmer)
  let slitCountRaw = u.zoom_params.x;
  let slitCount = mix(2.0, 3.0, slitCountRaw);
  let baseWidth = (u.zoom_params.y * 0.08 + 0.002) * (1.0 + bass * 0.5);
  let slitSpeed = u.zoom_params.z * 0.6 + 0.05;
  let feather = (u.zoom_params.w * 0.5 + 0.01) * (1.0 + treble * 0.6);

  // Mids → slit speed modulation
  let audioPulse = mids * 0.3 + 1.0;
  let speed = slitSpeed * audioPulse;

  // Multi-slit using sin waves
  var dist = 1.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    if (f32(i) >= slitCount) { break; }
    let phase = f32(i) * 2.094395102;
    let slitPos = fract(time * speed * (1.0 + f32(i) * 0.3) + f32(i) * 0.618034);
    let warp = fbm2(vec2<f32>(uv.y * 3.0 + f32(i), time * 0.5), time) * 0.05;
    let sp = fract(slitPos + warp);
    let d = abs(uv.x - sp);
    dist = smin(dist, d, 0.15);
  }

  // Fractal width modulation
  let widthMod = 1.0 + fbm2(vec2<f32>(time, uv.y * 2.0), time * 0.2) * 0.5;
  let slitW = baseWidth * widthMod;

  // Feather slit edges with smoothstep
  let mask = 1.0 - smoothstep(slitW * feather, slitW, dist);

  // Sample frames
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Spatially-varying temporal decay via noise
  let decayNoise = fbm2(uv * 4.0 + time * 0.1, time * 0.05);
  let decay = mix(1.0, 0.92 + decayNoise * 0.04, 0.5);

  // Alpha: slit-age based — freshly scanned regions more opaque
  let alpha = mix(history.a * decay, current.a, mask);
  let outColor = mix(history.rgb * decay, current.rgb, mask);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(outColor, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "chrono-slit-scan",
  "name": "Chrono Slit Scan",
  "url": "shaders/chrono-slit-scan.wgsl",
  "description": "Multi-slit temporal scan with 2-3 simultaneous animated slits, feathered edges, and audio-reactive speed modulation.",
  "params": [
    {
      "id": "slitCount",
      "name": "Slit Count",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "slitWidth",
      "name": "Slit Width",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "slitSpeed",
      "name": "Slit Speed",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "feather",
      "name": "Feather",
      "default": 0.3,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "temporal-persistence",
    "audio-reactive",
    "fbm-warp",
    "sdf-composition",
    "upgraded-rgba",
    "multi-slit"
  ],
  "tags": [
    "filter",
    "image-processing",
    "noise",
    "fractal",
    "temporal",
    "artistic"
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
