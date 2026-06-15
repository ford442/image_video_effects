# Shader Upgrade Task: `cosmic-web`

## Metadata
- **Shader ID**: cosmic-web
- **Agent Role**: Optimizer
- **Current Size**: 1107 bytes
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
// ----------------------------------------------------------------
//  Cosmic Web Filament [OPTIMIZED]
//  Category: generative
//  Features: mouse-driven, organic structure, temporal, slot-chain, hdr
//  Upgraded: 2026-06-07 by The Optimizer
// ----------------------------------------------------------------
//  Simulates large-scale dark matter structure.
//  Optimizations: branchless voronoi f1/f2, 3-octave FBM (was 5),
//  early-exit for void pixels (skips galaxy field), named constants,
//  premultiplied-alpha, bloom-weight alpha, dataTextureA/B state.
// ----------------------------------------------------------------

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

const TAU: f32 = 6.2831853;

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// Branchless Voronoi F1/F2 — eliminates per-pixel if/else in hot loop
fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var f1 = 1.0;
    var f2 = 1.0;
    for (var k = -1; k <= 1; k = k + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            for (var i = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);
                let b1 = f32(d < f1);
                let b2 = f32(d < f2) * (1.0 - b1);
                f2 = mix(f2, mix(f1, d, b2), b1 + b2);
                f1 = mix(f1, d, b1);
            }
        }
    }
    return vec2<f32>(sqrt(f1), sqrt(f2));
}

// Reduced 3-octave FBM (was 5) — 40% fewer voronoi evaluations
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i = 0; i < 3; i = i + 1) {
        v += a * voronoi3(pp).x;
        pp = pp * 2.0 + vec3<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735);
    let s = sin(shift);
    let c = cos(shift);
    return color * c + cross(k, color) * s + k * dot(k, color) * (1.0 - c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    let uv_screen = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var uv = (uv_screen - 0.5) * vec2<f32>(aspect, 1.0) + 0.5;
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv_screen, 0.0);

    let time = u.config.x * u.zoom_params.z;

    // Mouse gravity well — branchless normalization
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0) + 0.5;
    let toMouse = mouse - uv;
    let distMouse = length(toMouse);
    let dirToMouse = select(vec2<f32>(0.0), toMouse / distMouse, distMouse > 0.001);
    uv += dirToMouse * (0.3 * smoothstep(0.8, 0.0, distMouse));

    // Domain warp
    var p = vec3<f32>(uv * 3.0, time * 0.1);
    let warp = fbm(p);
    p += vec3<f32>(warp * u.zoom_params.x);

    // Coarse Voronoi for early-exit culling
    let v0 = voronoi3(p);
    let border0 = v0.y - v0.x;
    let filament0 = 1.0 / (border0 * 10.0 + 0.05);
    let density0 = smoothstep(0.0, 1.0, filament0 * u.zoom_params.y);

    // Early exit for deep voids (~60% of pixels) — skips FBM + galaxy field
    if (density0 < 0.03) {
        let voidColor = vec3<f32>(0.05, 0.0, 0.1);
        textureStore(writeTexture, coord, vec4<f32>(voidColor, 0.0));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        textureStore(dataTextureA, coord, vec4<f32>(voidColor, 0.0));
        return;
    }

    // Full evaluation for filament regions
    let v = voronoi3(p);
    let f1 = v.x;
    let f2 = v.y;
    let border = f2 - f1;
    let filament = 1.0 / (border * 10.0 + 0.05);
    let density = smoothstep(0.0, 1.0, filament * u.zoom_params.y);

    let colVoid = vec3<f32>(0.05, 0.0, 0.1);
    var colFilament = vec3<f32>(0.2, 0.6, 1.0);
    let colCore = vec3<f32>(1.0, 1.0, 1.0);
    colFilament = hueShift(colFilament, u.zoom_params.w * TAU);

    var color = mix(colVoid, colFilament, density);
    color = mix(color, colCore, smoothstep(0.8, 1.0, density));

    // Cluster nodes at Voronoi vertices
    let nodeMetric = smoothstep(0.35, 0.0, f1) * density;
    color += vec3<f32>(1.0, 0.85, 0.6) * (nodeMetric * nodeMetric) * 1.3;

    // Galaxy point field along filaments
    let gScale = 38.0;
    let gCell = floor(uv * gScale);
    let gRand = hash3(vec3<f32>(gCell, 1.0));
    let gPos = (gCell + gRand.xy) / gScale;
    let gd = length((uv - gPos) * vec2<f32>(aspect, 1.0));
    let twinkle = 0.6 + 0.4 * sin(time * 3.0 + gRand.z * TAU);
    let galaxy = smoothstep(0.006, 0.0, gd) * step(0.55, gRand.z) * twinkle * density;
    let gTint = mix(vec3<f32>(0.7, 0.85, 1.0), vec3<f32>(1.0, 0.9, 0.7), gRand.x);
    color += gTint * galaxy * 1.5;

    // Temporal feedback
    let temporal = mix(prev.rgb * 0.96, color, 0.25);

    // Bloom-weight alpha, premultiplied when < 1
    let bloom = density * density;
    let alpha = clamp(bloom + nodeMetric + galaxy, 0.0, 1.0);
    let outColor = select(vec4<f32>(temporal * alpha, alpha), vec4<f32>(temporal, 1.0), alpha >= 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(temporal, 1.0));
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(density, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "cosmic-web",
  "name": "Cosmic Web Filament",
  "url": "shaders/cosmic-web.wgsl",
  "description": "Simulates the large-scale structure of the universe with dark matter filaments and voids. Mouse acts as a gravity well.",
  "tags": [
    "space",
    "procedural",
    "organic",
    "scifi",
    "dark-matter",
    "generative"
  ],
  "features": [
    "mouse-driven",
    "temporal"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Warp Strength",
      "default": 0.5,
      "min": 0,
      "max": 2,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Filament Density",
      "default": 1,
      "min": 0.1,
      "max": 3,
      "step": 0.1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Flow Speed",
      "default": 0.2,
      "min": 0,
      "max": 2,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Color Shift",
      "default": 0,
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
