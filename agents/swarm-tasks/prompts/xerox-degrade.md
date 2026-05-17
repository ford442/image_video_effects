# Shader Upgrade Task: `xerox-degrade`

## Metadata
- **Shader ID**: xerox-degrade
- **Agent Role**: Optimizer
- **Current Size**: 3425 bytes
- **Target Line Count**: ~136 lines
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
//  Xerox Degrade
//  Category: retro-glitch
//  Features: glitch, branchless, sigmoid-contrast, ordered-dither, audio-reactive
//  Complexity: Medium
//  Phase B / Optimizer
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Contrast, y=GrainAmt, z=SmearAmt, w=Threshold
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// One hash → unpack into multiple uncorrelated values via xy/yx/sum permutes.
// Cheaper than three independent hash12 calls.
fn hash3_packed(p: vec2<f32>) -> vec3<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// 4×4 Bayer matrix as a closed-form expression (branchless). Avoids LUT overhead.
fn bayer4x4(p: vec2<i32>) -> f32 {
    let x = u32(p.x) & 3u;
    let y = u32(p.y) & 3u;
    // Pre-tabulated as bit pattern: returns 0..15 / 16
    let M = array<u32, 16>(
        0u,  8u,  2u, 10u,
       12u,  4u, 14u,  6u,
        3u, 11u,  1u,  9u,
       15u,  7u, 13u,  5u
    );
    return f32(M[y * 4u + x]) / 16.0;
}

// Sigmoid contrast curve — perceptually nicer than linear stretch
fn sigmoidContrast(x: f32, k: f32) -> f32 {
    // Steepness k; midpoint 0.5
    return 1.0 / (1.0 + exp(-k * (x - 0.5)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let contrast  = u.zoom_params.x * 8.0 + 2.0;          // sigmoid steepness 2..10
    let grain_amt = clamp(u.zoom_params.y + bass * 0.15, 0.0, 1.0);
    let smear_amt = u.zoom_params.z * (1.0 + bass * 0.5);
    let threshold = clamp(u.zoom_params.w, 0.0, 1.0);

    // Pack three uncorrelated noise values from one hash call (single ALU pass)
    let h = hash3_packed(uv * resolution * 0.01 + time * 0.1);
    let smear_n = (h.x - 0.5) * smear_amt * 0.1;

    // Branchless smear with mirrored-edge fallback (avoids hard if-branch)
    let smear_uv_raw = vec2<f32>(uv.x + smear_n, uv.y);
    let oob = step(1.0, smear_uv_raw.x) + step(smear_uv_raw.x, 0.0);
    let smear_uv = clamp(smear_uv_raw, vec2<f32>(0.0), vec2<f32>(1.0));
    let sample = textureSampleLevel(readTexture, u_sampler, smear_uv, 0.0).rgb;
    // Paper white when out-of-bounds (no branch, lerp mask)
    let paper = vec3<f32>(0.96, 0.96, 0.92);
    let color = mix(sample, paper, clamp(oob, 0.0, 1.0));

    // Grayscale → sigmoid contrast (smoother than linear stretch + clamp)
    let luma_raw = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let luma_thresh = clamp(luma_raw - threshold + 0.5, 0.0, 1.0);
    let contrasted = sigmoidContrast(luma_thresh, contrast);

    // Ordered-dither toner halftone — gives crisper xerox feel than uniform noise
    let dither = bayer4x4(coord) - 0.5;
    let toned = clamp(contrasted + dither * 0.06, 0.0, 1.0);

    // Toner scatter / paper fleck via packed hash channels (no branches)
    let scatter = step(h.y, grain_amt * 0.18) * (-0.4) +    // dark spots in light
                  step(1.0 - grain_amt * 0.18, h.z) * 0.3;  // light spots in dark
    let final_luma = clamp(toned + scatter * grain_amt, 0.0, 1.0);

    // Tinted toner / yellowed paper
    let toner_black = vec3<f32>(0.05, 0.05, 0.12);
    let final_color = mix(toner_black, paper, final_luma);

    // Alpha: dark toner = opaque, paper = translucent, grain damage reduces opacity
    let damage = grain_amt * abs(h.y - 0.5) * 0.5;
    let alpha = mix(0.88, 1.0, clamp(1.0 - final_luma + damage, 0.0, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coord, vec4<f32>(final_color, alpha));
}

```

## Current JSON Definition
```json
{
  "id": "xerox-degrade",
  "name": "Xerox Degrade",
  "url": "shaders/xerox-degrade.wgsl",
  "category": "retro-glitch",
  "description": "Simulates the degradation of repeated photocopying with grain, high contrast, and smear.",
  "params": [
    {
      "id": "contrast",
      "name": "Contrast",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "grain",
      "name": "Grain",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "smear",
      "name": "Smear",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "threshold",
      "name": "Threshold",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    }
  ],
  "features": [
    "glitch",
    "texture",
    "audio-reactive"
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
4. Ensure the upgraded shader is roughly 136 lines (±20%).
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
