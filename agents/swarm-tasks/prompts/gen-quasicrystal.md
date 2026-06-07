# Shader Upgrade Task: `gen-quasicrystal`

## Metadata
- **Shader ID**: gen-quasicrystal
- **Agent Role**: Optimizer
- **Current Size**: 1199 bytes
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
//  Quasicrystal - Penrose tiling-inspired patterns with 5-fold symmetry
//  Category: generative
//  Features: procedural, aperiodic tiling, projection method, audio-reactive, mouse-driven, temporal, upgraded-rgba
//  Created: 2026-03-22
//  By: Agent 4A
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Quasicrystal pattern using the projection method
// A 5D lattice is projected onto 2D to create the pattern
fn quasicrystal(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> f32 {
    var value = 0.0;
    let pi = 3.14159265359;
    
    // Sum of waves at angles determined by symmetry
    for (var i: i32 = 0; i < n; i++) {
        let theta = angle + pi * 2.0 * f32(i) / f32(n);
        let k = vec2<f32>(cos(theta), sin(theta));
        value += cos(dot(uv, k) * 10.0 + t);
    }
    
    return value / f32(n);
}

// Rhombus tiling based on quasicrystal
fn rhombusPattern(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> vec2<f32> {
    let qc = quasicrystal(uv, n, t, angle);
    let qc2 = quasicrystal(uv + vec2<f32>(0.1), n, t, angle + 0.1);
    
    // Create tiling pattern
    let phase1 = fract(qc * 2.0);
    let phase2 = fract(qc2 * 2.0);
    
    return vec2<f32>(phase1, phase2);
}

// Metallic gradient
fn metallicColor(uv: vec2<f32>, pattern: f32, t: f32) -> vec3<f32> {
    // Gold and silver base
    let gold = vec3<f32>(1.0, 0.84, 0.0);
    let silver = vec3<f32>(0.75, 0.75, 0.75);
    let bronze = vec3<f32>(0.8, 0.5, 0.2);
    
    // Gradient based on pattern
    let m = fract(pattern + t * 0.05);
    
    var col = vec3<f32>(0.0);
    if (m < 0.33) {
        col = mix(gold, silver, m * 3.0);
    } else if (m < 0.66) {
        col = mix(silver, bronze, (m - 0.33) * 3.0);
    } else {
        col = mix(bronze, gold, (m - 0.66) * 3.0);
    }
    
    return col;
}

// Gem accent color
fn gemColor(idx: i32, t: f32) -> vec3<f32> {
    let gems = array<vec3<f32>, 5>(
        vec3<f32>(0.9, 0.1, 0.2), // Ruby
        vec3<f32>(0.1, 0.6, 0.9), // Sapphire
        vec3<f32>(0.1, 0.8, 0.3), // Emerald
        vec3<f32>(0.9, 0.5, 0.1), // Amber
        vec3<f32>(0.7, 0.2, 0.8)  // Amethyst
    );
    return gems[idx % 5];
}

// 2D rotation
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    let bass = plasmaBuffer[0].x;
    
    // Parameters - safe randomization
    let symmetry = i32(mix(5.0, 13.0, u.zoom_params.x)); // 5, 7, 9, 11, 13
    let patternDensity = mix(3.0, 15.0, u.zoom_params.y);
    let colorCycle = u.zoom_params.z;
    let projAngle = mix(0.0, 6.28318, u.zoom_params.w);
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * patternDensity;
    
    // Slow rotation to reveal symmetries
    let rotSpeed = 0.05;
    p = rot2(t * rotSpeed + projAngle) * p;
    
    // Generate quasicrystal pattern
    let qc = quasicrystal(p, symmetry, t * 0.2, projAngle);
    
    // Create rhombus tiling pattern
    let threshold = 0.2;
    let pattern = smoothstep(-threshold, threshold, qc);
    
    // Second layer for detail
    let qc2 = quasicrystal(p * 1.5 + 0.5, symmetry, t * 0.15, projAngle + 0.1);
    let pattern2 = smoothstep(-threshold * 0.5, threshold * 0.5, qc2);
    
    // Metallic base color
    var col = metallicColor(p, qc + qc2, t * colorCycle);
    
    // Add gem accents at specific pattern locations
    let gemLocations = fract(qc * 5.0 + qc2 * 3.0);
    let gemMask = smoothstep(0.48, 0.5, gemLocations) * smoothstep(0.52, 0.5, gemLocations);
    
    let gemIdx = i32(fract(qc * 10.0) * 5.0);
    let gemAccent = gemColor(gemIdx, t) * gemMask;
    col = mix(col, gemAccent, gemMask * 0.6);
    
    // Highlight rhombus edges
    let edge = abs(qc);
    let edgeMask = smoothstep(0.05, 0.0, edge);
    col = col + vec3<f32>(1.0, 0.95, 0.8) * edgeMask * 0.4;
    
    // Add subtle shimmer
    let shimmer = sin(p.x * 20.0 + t) * sin(p.y * 20.0 + t * 1.3);
    col = col + vec3<f32>(0.1) * shimmer * 0.05;
    
    // Depth variation based on pattern
    let depth = pattern * 0.5 + pattern2 * 0.3;
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;
    
    let _luma_q = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let _alpha_q = clamp(_luma_q * 0.7 + 0.2, 0.0, 1.0);
    let outColor = vec4<f32>(col, _alpha_q);
    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);
}

```

## Current JSON Definition
```json
{
  "id": "gen-quasicrystal",
  "name": "Quasicrystal",
  "url": "shaders/gen-quasicrystal.wgsl",
  "description": "Penrose tiling-inspired quasicrystal patterns with n-fold symmetry using the projection method from higher-dimensional lattices",
  "tags": [
    "generative",
    "quasicrystal",
    "symmetry",
    "mathematical",
    "procedural",
    "audio",
    "music",
    "reactive"
  ],
  "features": [
    "generative",
    "animated",
    "audio-reactive",
    "temporal",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "symmetry",
      "name": "Symmetry Order",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "density",
      "name": "Pattern Density",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "colorCycle",
      "name": "Color Cycling",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "projAngle",
      "name": "Projection Angle",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
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
