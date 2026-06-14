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
// ═══ gen-quasicrystal ═══════════════════════════════════════════════
//  Category: generative
//  Features: quasicrystal, n-fold symmetry, projection-method,
//            audio-reactive, temporal-feedback, anti-moire, neon-glow,
//            chromatic-aberration, aces-tone-map, semantic-alpha,
//            slot-chain
//  Upgraded: 2026-06-14 by The Optimizer
// ═══════════════════════════════════════════════════════════════════
//  Penrose tiling-inspired aperiodic patterns. Upgrades: canonical
//  13-binding header, bounds guard, resolution-aware LOD anti-moiré,
//  temporal feedback via dataTextureC, neon glow, generative CA, and
//  ACES tone mapping with semantic alpha for slot-chain compositing.
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Core helpers ──────────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn neonGlow(color: vec3<f32>, intensity: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.0));
    let lum = luma(safeColor);
    let glowMask = smoothstep(0.22, 1.0, lum);
    let chroma = normalize(safeColor + vec3<f32>(0.001)) * max(lum, 0.18);
    let bloom = (safeColor * safeColor + chroma) * glowMask * max(intensity, 0.0);
    return safeColor + bloom;
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

// ── Quasicrystal ──────────────────────────────────────────────────
fn quasicrystal(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> f32 {
    var value = 0.0;
    let invN = 1.0 / f32(n);
    for (var i: i32 = 0; i < n; i = i + 1) {
        let theta = angle + TAU * f32(i) * invN;
        value += cos(dot(uv, vec2<f32>(cos(theta), sin(theta))) * 10.0 + t);
    }
    return value * invN;
}

// Branchless tri-color metallic cycle
fn metallicColor(pattern: f32, t: f32) -> vec3<f32> {
    let gold   = vec3<f32>(1.0, 0.84, 0.0);
    let silver = vec3<f32>(0.75, 0.75, 0.75);
    let bronze = vec3<f32>(0.8, 0.5, 0.2);
    let m = fract(pattern + t * 0.05) * 3.0;
    let s1 = step(1.0, m);
    let s2 = step(2.0, m);
    let c0 = mix(gold, silver, m);
    let c1 = mix(silver, bronze, m - 1.0);
    let c2 = mix(bronze, gold, m - 2.0);
    return mix(mix(c0, c1, s1), c2, s2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01  = vec2<f32>(pixel) / res;
    let uv    = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time  = u.config.x;
    let bass  = plasmaBuffer[0].x;
    let mids  = plasmaBuffer[0].y;
    let depthIn = textureLoad(readDepthTexture, pixel, 0).r;
    let prev  = textureLoad(dataTextureC, pixel, 0);

    let symmetry   = i32(mix(5.0, 13.0, u.zoom_params.x));
    let density    = mix(3.0, 15.0, u.zoom_params.y);
    let colorCycle = u.zoom_params.z;
    let projAngle  = mix(0.0, TAU, u.zoom_params.w);

    // Anti-moiré: scale pattern coordinate at extreme densities
    let densityScale = mix(1.0, 0.65, smoothstep(8.0, 14.0, density));
    let shimmerFreq  = mix(10.0, 6.0, smoothstep(8.0, 14.0, density));

    var p = uv * density * densityScale;
    p = rot2(time * 0.05 + projAngle) * p;

    // Primary + secondary quasicrystal layers
    let qc = quasicrystal(p, symmetry, time * 0.2, projAngle);
    let pattern = smoothstep(-0.2, 0.2, qc);

    let qc2 = quasicrystal(p * 1.5 + 0.5, symmetry, time * 0.15, projAngle + 0.1);
    let pattern2 = smoothstep(-0.1, 0.1, qc2);

    // Metallic base with audio reactivity
    var col = metallicColor(qc + qc2, time * colorCycle) * (1.0 + bass * 0.3);

    // Gem accents — compact branchless palette
    let gemLocations = fract(qc * 5.0 + qc2 * 3.0);
    let gemMask = smoothstep(0.48, 0.5, gemLocations) * smoothstep(0.52, 0.5, gemLocations);
    let gemIdx = i32(fract(qc * 10.0) * 5.0);
    let gemPal = array<vec3<f32>, 5>(
        vec3<f32>(0.9, 0.1, 0.2), vec3<f32>(0.1, 0.6, 0.9),
        vec3<f32>(0.1, 0.8, 0.3), vec3<f32>(0.9, 0.5, 0.1),
        vec3<f32>(0.7, 0.2, 0.8)
    );
    col = mix(col, gemPal[gemIdx], gemMask * 0.6);

    // Edge highlights
    let edgeMask = smoothstep(0.05, 0.0, abs(qc));
    col += vec3<f32>(1.0, 0.95, 0.8) * edgeMask * 0.4;

    // Subtle shimmer
    let shimmer = sin(p.x * shimmerFreq * 2.0 + time) * sin(p.y * shimmerFreq * 2.0 + time * 1.3);
    col += vec3<f32>(0.02) * shimmer;

    // Vignette
    col *= 1.0 - length(uv01 - 0.5) * 0.5;

    // Post-process: neon glow, generative chromatic aberration, ACES
    col = neonGlow(col, 0.35 + mids * 0.25);
    let caStr = 0.003 * (1.0 + bass) + depthIn * 0.001;
    col = genChromaticShift(col, uv01, caStr);
    col = acesToneMap(col * (0.9 + mids * 0.2));

    // Temporal feedback via dataTextureC
    let decay = 0.96;
    let trail = mix(prev.rgb * decay, col, 0.25 + bass * 0.1);

    // Depth-aware semantic alpha
    let depth = pattern * 0.5 + pattern2 * 0.3;
    let bloom = smoothstep(0.5, 1.2, luma(col));
    let alpha = clamp(luma(trail) * 1.2 + depth * 0.2, 0.25, 0.95);

    textureStore(writeTexture, pixel, vec4<f32>(trail, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, alpha));
    textureStore(dataTextureB, pixel, vec4<f32>(col, bloom));
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
    "upgraded-rgba",
    "aces-tone-map",
    "chromatic-aberration",
    "neon-glow",
    "anti-moire"
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
