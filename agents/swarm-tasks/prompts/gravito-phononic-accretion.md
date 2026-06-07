# Shader Upgrade Task: `gravito-phononic-accretion`

## Metadata
- **Shader ID**: gravito-phononic-accretion
- **Agent Role**: Optimizer
- **Current Size**: 1847 bytes
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
//  Gravito-Phononic Accretion v2
//  Category: generative
//  Features: SPH-density, orbital-velocity, shock-detection, blackbody,
//            audio-driven, mouse-rogue-body, ripple-perturbation
//  Complexity: Very High
//  Chunks From: inverse-square field + cubic-spline kernel + ACES tm
//  Created: 2026-05-31
//  By: 4-Agent Upgrade Swarm
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn cubicKernel(q: f32) -> f32 {
  let s = clamp(q, 0.0, 2.0);
  return select(0.25 * pow(2.0 - s, 3.0), 0.25 * s * s * (3.0 * s - 6.0) + 1.0, s < 1.0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn blackbody(t: f32) -> vec3<f32> {
  let kt = clamp(t, 0.0, 1.0);
  let g = mix(0.2, 1.0, smoothstep(0.15, 0.6, kt));
  let b = mix(0.0, 1.0, smoothstep(0.3, 0.9, kt));
  return vec3<f32>(kt, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x * 0.4;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  let precess = mids * 0.8;
  let g1 = vec2<f32>(0.35 + sin(time * 0.3 + precess) * 0.12, 0.42 + cos(time * 0.25) * 0.09);
  let g2 = vec2<f32>(0.68 + cos(time * 0.35 - precess) * 0.1, 0.58 + sin(time * 0.3 + precess) * 0.08);
  let mass1 = 0.9 + bass * 1.4 + p1 * 0.8;
  let mass2 = 0.8 + mids * 1.0 + p1 * 0.6;
  let mass3 = (0.7 + treble * 0.6) * mouseDown * (1.0 + p4 * 2.0);

  let d1 = length(uv - g1) + 0.06;
  let d2 = length(uv - g2) + 0.06;
  let d3 = length(uv - mouse) + 0.04;

  let v1 = vec2<f32>(-(uv.y - g1.y), uv.x - g1.x) * (mass1 / (d1 * d1)) * 0.025;
  let v2 = vec2<f32>(-(uv.y - g2.y), uv.x - g2.x) * (mass2 / (d2 * d2)) * 0.02;
  let v3 = select(vec2<f32>(0.0), vec2<f32>(-(uv.y - mouse.y), uv.x - mouse.x) * (mass3 / (d3 * d3)) * 0.04, mouseDown > 0.5);
  let vel = v1 + v2 + v3;

  let h = 0.045 + p3 * 0.04;
  var density = 0.0;
  for (var i = 0; i < 4; i = i + 1) {
    for (var j = 0; j < 4; j = j + 1) {
      let off = (vec2<f32>(f32(i), f32(j)) - 1.5) * h;
      let sp = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
      density += textureSampleLevel(dataTextureC, u_sampler, sp, 0.0).r * cubicKernel(length(off) / h);
    }
  }
  density = density * 0.25 + 0.001;

  let flowUV = clamp(uv - vel * 8.0 * (0.6 + p1), vec2<f32>(0.0), vec2<f32>(1.0));
  let flowed = textureSampleLevel(dataTextureC, u_sampler, flowUV, 0.0).r;
  let standing = sin(uv.x * 20.0 + time * 3.0) * cos(uv.y * 16.0 - time * 2.5) * treble * 0.12;

  var ripplePert = 0.0;
  let rCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rd = length(uv - rp.xy);
    let rt = time - rp.z;
    ripplePert += exp(-rd * 8.0) * sin(rt * 10.0) * 0.03 * smoothstep(3.0, 0.0, rt);
  }

  density = mix(flowed * 0.95 + density * 0.05, density, 0.3) + standing + ripplePert;

  let ps = 1.0 / res;
  let drx = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let drxm = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let dry = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let drym = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gradD = length(vec2<f32>(drx - drxm, dry - drym)) * res.x * 0.5;
  let shock = smoothstep(0.3, 1.2, gradD + length(vel) * 3.0);

  var temp = shock * 0.7 + (mass1 / (d1 * d1 * 20.0 + 1.0)) * 0.4 + (mass2 / (d2 * d2 * 20.0 + 1.0)) * 0.3;
  temp = clamp(temp, 0.0, 1.0);

  textureStore(dataTextureA, gid.xy, vec4<f32>(density, temp, shock, 0.0));

  let bb = blackbody(temp) * (1.0 + shock * 2.0);
  let scatter = smoothstep(0.02, 0.25, density) * temp * 0.6;
  let col = bb * (0.5 + density * 1.2) + vec3<f32>(0.3, 0.5, 1.0) * scatter;
  let bloom = shock * vec3<f32>(1.0, 0.9, 0.7) * 1.5;
  let tone = acesToneMap((col + bloom) * (0.8 + p2));

  let bgEmpty = smoothstep(0.15, 0.0, density);
  let alpha = clamp(density * 1.1 * temp * (1.0 - bgEmpty * 0.8) + shock * 0.5, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * temp * 0.7, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "gravito-phononic-accretion",
  "name": "Gravito-Phononic Accretion",
  "url": "shaders/gravito-phononic-accretion.wgsl",
  "category": "generative",
  "description": "SPH density estimation around orbiting accretors with cubic-spline kernel, shock-wave detection, and temperature-based blackbody coloring. Bass adds mass to primaries, mids drive orbital precession, treble creates acoustic standing waves. Mouse introduces a rogue body with tidal forces. Ripples seed density perturbations.",
  "features": [
    "SPH-density",
    "orbital-velocity",
    "shock-detection",
    "blackbody",
    "audio-driven",
    "mouse-rogue-body",
    "ripple-perturbation",
    "temporal"
  ],
  "tags": [
    "gravitational",
    "accretion",
    "cosmic",
    "organic",
    "audio-reactive",
    "lensing",
    "blackbody",
    "HDR"
  ],
  "params": [
    {
      "id": "accretionSpeed",
      "name": "Accretion Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "How fast material collects around gravitational centers"
    },
    {
      "id": "lensing",
      "name": "Lensing Strength",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Amount of gravitational light distortion"
    },
    {
      "id": "diffusion",
      "name": "Material Diffusion",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "How much material spreads out"
    },
    {
      "id": "mouseMass",
      "name": "Mouse Gravity Power",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Temporary mass added when mouse is held"
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
