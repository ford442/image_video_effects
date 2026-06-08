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
//  Cosmic Web Filament - Generative simulation of dark matter web
//  Category: generative
//  Features: mouse-driven, organic structure
// ----------------------------------------------------------------

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
  config: vec4<f32>,       // x: time, y: aspect, z: resX, w: resY
  zoom_config: vec4<f32>,  // xy: center, z: zoom, w: unused (Mouse: yz)
  zoom_params: vec4<f32>,  // x: warpStrength, y: density, z: speed, w: colorShift
  ripples: array<vec4<f32>, 50>,
};

// 3D Random Hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// 3D Voronoi Noise returning F1 and F2
fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var f1 = 1.0;
    var f2 = 1.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);

                if (d < f1) {
                    f2 = f1;
                    f1 = d;
                } else if (d < f2) {
                    f2 = d;
                }
            }
        }
    }
    // Return sqrt distances
    return vec2<f32>(sqrt(f1), sqrt(f2));
}

// FBM for Domain Warping
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p_loop = p;
    for (var i = 0; i < 5; i++) {
        let v_dist = voronoi3(p_loop).x; // Use F1 for cloudiness
        v += a * v_dist;
        p_loop = p_loop * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Hue rotation using Rodrigues' rotation formula
fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    var k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(shift);
    return vec3<f32>(color * cosAngle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cosAngle));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    let uv_screen = vec2<f32>(global_id.xy) / resolution;
    // Aspect ratio correction
    var uv = (uv_screen - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0) + 0.5;
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    let time = u.config.x * u.zoom_params.z; // Speed control

    // Mouse Interaction (Gravity Well)
    let mouseRaw = u.zoom_config.yz;
    var mouse = (mouseRaw - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0) + 0.5;

    let toMouse = mouse - uv;
    let distMouse = length(toMouse);
    
    // Safe normalization avoiding division by zero
    let dirToMouse = select(vec2<f32>(0.0), normalize(toMouse), distMouse > 0.001);
    let pullStrength = 0.3 * smoothstep(0.8, 0.0, distMouse);

    // Warp UV towards mouse
    uv += dirToMouse * pullStrength;

    // Domain Warping for Organic Look
    var p = vec3<f32>(uv * 3.0, time * 0.1);
    let warp = fbm(p);
    p += vec3<f32>(warp * u.zoom_params.x); // Warp strength

    // Voronoi Cell Calculation
    var v = voronoi3(p);
    var f1 = v.x;
    var f2 = v.y;

    // Filament metric: borders are where F2 - F1 is small
    let border = f2 - f1;
    let filament = 1.0 / (border * 10.0 + 0.05); // Sharpen

    // Density mapping
    let density = smoothstep(0.0, 1.0, filament * u.zoom_params.y);

    // Color Palette
    let colVoid = vec3<f32>(0.05, 0.0, 0.1);
    var colFilament = vec3<f32>(0.2, 0.6, 1.0);
    let colCore = vec3<f32>(1.0, 1.0, 1.0);

    // Apply color shift using proper hue rotation
    colFilament = hueShift(colFilament, u.zoom_params.w * 6.28);

    var color = mix(colVoid, colFilament, density);
    color = mix(color, colCore, smoothstep(0.8, 1.0, density));

    // ═══ UNIQUE VISUAL IDEA: galaxy clusters at filament nodes + galaxy field ═══
    // (1) Cluster nodes — where filaments intersect (the web is densest AND a Voronoi
    //     vertex, so F1 is small), gravity has pulled matter into a bright cluster.
    //     Real clusters glow warm (old red/yellow stars) vs the cool filament gas.
    let nodeMetric = smoothstep(0.35, 0.0, f1) * density;
    let clusterColor = vec3<f32>(1.0, 0.85, 0.6);
    color = color + clusterColor * pow(nodeMetric, 2.0) * 1.3;

    // (2) Galaxy point field — the filaments are strung with countless galaxies.
    //     Tile space, drop a jittered galaxy per cell, twinkle it over time, and gate
    //     its visibility by the local web density so galaxies trace the structure.
    let gScale = 38.0;
    let gCell = floor(uv * gScale);
    let gRand = hash3(vec3<f32>(gCell, 1.0));
    let gPos = (gCell + gRand.xy) / gScale;
    let gd = length((uv - gPos) * vec2<f32>(resolution.x / resolution.y, 1.0));
    let twinkle = 0.6 + 0.4 * sin(time * 3.0 + gRand.z * 6.28);
    let galaxy = smoothstep(0.006, 0.0, gd) * step(0.55, gRand.z) * twinkle * density;
    // Galaxy tint varies from cool blue (young) to warm gold (old) per-galaxy.
    let gTint = mix(vec3<f32>(0.7, 0.85, 1.0), vec3<f32>(1.0, 0.9, 0.7), gRand.x);
    color = color + gTint * galaxy * 1.5;

    // Temporal feedback
    let decay = 0.96;
    let temporal = mix(prev.rgb * decay, color, 0.25);
    textureStore(dataTextureA, coord, vec4<f32>(temporal, 1.0));

    // Output
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));

    // Simple depth based on density
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
