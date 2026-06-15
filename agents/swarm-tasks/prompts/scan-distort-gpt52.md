# Shader Upgrade Task: `scan-distort-gpt52`

## Metadata
- **Shader ID**: scan-distort-gpt52
- **Agent Role**: Optimizer
- **Current Size**: 3236 bytes
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
//  Scan Distort Matrix gpt52 (Batch D Upgrade)
//  Category: distortion
//  Features: glitch, animated, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgrades: 3-band frequency distortion, FBM scan lines,
//            effect-mask alpha, mids-driven band distortion
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

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(41.7, 289.3))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var pp = p * 0.1031;
  let d = fract(pp.x * pp.y * 23.4517 + pp.y * 37.2314);
  let s = vec2<f32>(d + 0.113, d + 0.257);
  return fract(s * s * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    v = v + a * noise2(pp);
    pp = pp * 2.03;
    a = a * 0.5;
  }
  return v;
}

fn to_linear(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(2.2));
}

fn to_srgb(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(1.0 / 2.2));
}

fn aces_tm(c: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let cc = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((c * (a * c + b)) / (c * (cc * c + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Params
  let scanIntensity = u.zoom_params.x;
  let bandSplit = u.zoom_params.y;
  let fbmScale = u.zoom_params.z;
  let chromaticMix = u.zoom_params.w;

  let lines = mix(200.0, 1400.0, scanIntensity);
  let bend = mix(0.0, 0.18, bandSplit);
  let glitch = scanIntensity * 0.08;
  let roll = time * mix(0.2, 2.5, chromaticMix);

  // FBM perturbation for scan line positions
  let fbmPerturb = fbm(vec2(uv.y * fbmScale * 5.0, time * 0.3)) * 0.02 * fbmScale;

  var warped = uv;
  let centered = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let radius = length(centered);
  warped += centered * (radius * radius) * bend;

  // Split into 3 frequency bands by Y position
  let bandY = uv.y;
  let band1 = smoothstep(0.0, 0.33, bandY) * (1.0 - smoothstep(0.33, 0.34, bandY));
  let band2 = smoothstep(0.33, 0.66, bandY) * (1.0 - smoothstep(0.66, 0.67, bandY));
  let band3 = smoothstep(0.66, 1.0, bandY);

  // Audio: mids drive band distortion, bass spikes glitch, treble boosts aberration
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let bandDistort = (1.0 + mids * 3.0) * (1.0 + bass * 0.6);

  let linePhase = (warped.y + roll + fbmPerturb) * lines;
  let scan = sin(linePhase) * 0.5 + 0.5;
  let scanBoost = 0.65 + 0.75 * scan;

  // Different distortions per band
  let lineId = floor(warped.y * lines * 0.05);
  let jitter1 = (hash(vec2<f32>(lineId, floor(time * 24.0))) - 0.5) * glitch * bandDistort;
  let jitter2 = (hash(vec2<f32>(lineId + 100.0, floor(time * 18.0))) - 0.5) * glitch * bandDistort * 1.5;
  let jitter3 = (hash(vec2<f32>(lineId + 200.0, floor(time * 30.0))) - 0.5) * glitch * bandDistort * 0.7;

  let blockId = floor(warped.y * 30.0);
  let blockNoise = hash(vec2<f32>(blockId, floor(time * 12.0)));
  let blockJitter = (blockNoise - 0.5) * glitch * step(blockNoise, scanIntensity * 0.6);

  let offset1 = vec2<f32>((jitter1 + blockJitter) * band1, 0.0);
  let offset2 = vec2<f32>((jitter2 + blockJitter) * band2, 0.0);
  let offset3 = vec2<f32>((jitter3 + blockJitter) * band3, 0.0);
  let totalOffset = offset1 + offset2 + offset3;

  let aberr = (scanIntensity * 0.01 + 0.002) * (1.0 + treble * 1.5);
  let r = textureSampleLevel(readTexture, u_sampler, warped + totalOffset + vec2<f32>(aberr, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, warped + totalOffset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, warped + totalOffset - vec2<f32>(aberr, 0.0), 0.0).b;

  // Linear HDR workflow
  var color = to_linear(vec3<f32>(r, g, b)) * scanBoost;

  // Cinematic film grain
  let grain = (hash(uv * resolution + time) - 0.5) * 0.03
            + (hash(uv * resolution * 1.3 - time * 0.7) - 0.5) * 0.015;
  color += vec3<f32>(grain) * scanIntensity;

  // Depth-based atmospheric haze
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let fogAmount = smoothstep(0.0, 1.0, depth * 0.5 + radius * 0.35) * 0.4;
  let fogColor = vec3<f32>(0.08, 0.06, 0.04);
  color = mix(color, fogColor * 1.5, fogAmount);

  // Split-tone: cool shadows / warm gold highlights
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let shadowTint = vec3<f32>(0.6, 0.75, 1.0);
  let highlightTint = vec3<f32>(1.15, 0.95, 0.7);
  let shadowMask = 1.0 - smoothstep(0.0, 0.25, lum);
  let highlightMask = smoothstep(0.5, 1.0, lum);
  color = color * mix(vec3<f32>(1.0), shadowTint, shadowMask * 0.3);
  color = color * mix(vec3<f32>(1.0), highlightTint, highlightMask * 0.25);

  // Fresnel rim glow on barrel distortion edges
  let rim = pow(radius * 1.6, 3.0);
  let rimColor = vec3<f32>(1.0, 0.85, 0.5);
  color += rimColor * rim * 0.6 * (1.0 - bandSplit * 0.3);

  // Vignette for cinematic focus
  let vignette = 1.0 - smoothstep(0.4, 1.2, radius);
  color = color * (0.55 + 0.45 * vignette);

  // ACES tone map + sRGB output
  color = aces_tm(color);

  // Effect-mask alpha based on distortion strength
  let effectStrength = scanIntensity + bandDistort * 0.3 + length(totalOffset) * 10.0;
  let alpha = clamp(effectStrength, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(to_srgb(color), alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "scan-distort-gpt52",
  "name": "Scan Distort Matrix gpt52",
  "url": "shaders/scan-distort-gpt52.wgsl",
  "description": "High-density scanlines with 3-band frequency distortion, FBM-perturbed scan positions, rolling jitter, curvature, chromatic tearing, and mids-driven band distortion.",
  "params": [
    {
      "id": "scan_intensity",
      "name": "Scan Intensity",
      "default": 0.6,
      "min": 0,
      "max": 1
    },
    {
      "id": "band_split",
      "name": "Band Split",
      "default": 0.35,
      "min": 0,
      "max": 1
    },
    {
      "id": "fbm_scale",
      "name": "FBM Scale",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "chromatic_mix",
      "name": "Chromatic Mix",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "glitch",
    "animated",
    "depth-aware",
    "upgraded-rgba",
    "audio-reactive"
  ],
  "tags": [
    "filter",
    "image-processing",
    "cinematic",
    "vintage",
    "atmospheric",
    "fbm",
    "bands"
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
