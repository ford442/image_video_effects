# Shader Upgrade Task: `chrono-slit-scan`

## Metadata
- **Shader ID**: chrono-slit-scan
- **Agent Role**: Multi-Pass-Architect
- **Current Size**: 3242 bytes
- **Target Line Count**: ~220 lines
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
//  Chrono Slit Scan — Optimizer Upgrade
//  Category: image
//  Features: temporal-persistence, audio-reactive, fbm-warp, sdf-composition,
//            upgraded-rgba, multi-slit, branchless-slit, depth-aware
//  Complexity: Medium
//
//  Pipeline notes:
//   - dataTextureA/B used for temporal state; dataTextureC is previous frame.
//   - writeDepthTexture passthrough preserves depth for downstream slots.
//   - Output alpha encodes slit intensity for compositing.
//
//  Recommended slots:
//   - Slot 0: image/video source
//   - Slot 1+: temporal feedback via dataTextureA/B chain
//   - Final output: writeTexture with depth passthrough
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

// ── Canonical hash & fBM ──────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < oct; i++) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

// ── Color / SDF helpers ───────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Tunable parameters mapped to zoom_params
  //   p1 = slitCount (2–3 slits), p2 = slitWidth
  //   p3 = slitSpeed, p4 = feather
  let slitCount = mix(2.0, 3.0, u.zoom_params.x);
  let baseWidth = (u.zoom_params.y * 0.08 + 0.002) * (1.0 + bass * 0.5);
  let slitSpeed = u.zoom_params.z * 0.6 + 0.05;
  let feather = (u.zoom_params.w * 0.5 + 0.01) * (1.0 + treble * 0.6);

  // Audio-reactive speed
  let speed = slitSpeed * (mids * 0.3 + 1.0);

  // Depth-aware scale (load depth, avoid textureSampleLevel on depth)
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthBoost = 1.0 + depth * 0.5;

  // Multi-slit distance field with branchless count gating
  var dist = 1.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let isActive = step(f32(i) + 0.5, slitCount);
    let offset = fract(f32(i + 1) * PHI);
    let pos = fract(time * speed * (1.0 + f32(i) * 0.3) + offset);
    let warp = fbm(vec2<f32>(uv.y * 3.0 + f32(i), time * 0.5), 3) * 0.05;
    let sp = fract(pos + warp);
    let d = abs(uv.x - sp);
    let blended = smin(dist, d, 0.15);
    dist = mix(dist, blended, isActive);
  }

  // Fractal width modulation
  let widthMod = 1.0 + fbm(vec2<f32>(time, uv.y * 2.0), 3) * 0.5;
  let slitW = baseWidth * widthMod * depthBoost;

  // Feathered slit mask
  let mask = 1.0 - smoothstep(slitW * feather, slitW, dist);

  // Sample current frame and temporal history
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // Spatially-varying temporal decay
  let decayNoise = fbm(uv * 4.0 + time * 0.1, 3);
  let decay = mix(1.0, 0.92 + decayNoise * 0.04, 0.5);

  // Compose: freshly scanned regions pick up current color and intensity
  let alpha = mix(history.a * decay, saturate(luma(current.rgb) + 0.2), mask);
  let color = mix(history.rgb * decay, current.rgb, mask);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "chrono-slit-scan",
  "name": "Chrono Slit Scan",
  "url": "shaders/chrono-slit-scan.wgsl",
  "description": "Multi-slit temporal scan with 2-3 simultaneous animated slits, feathered edges, audio-reactive speed modulation, and depth-aware width scaling.",
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
    "multi-slit",
    "depth-aware"
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
# Agent Role: Multi-Pass Architect (Phase B)

## Identity
You are the **Multi-Pass Architect**. Your job is to refactor or optimize complex shaders for the Pixelocity 3-slot pipeline.

## Focus Areas
- Split oversized shaders into multi-pass pipelines when they exceed ~8 KB or mix field generation + particle simulation + compositing.
- Add early-exit, distance-based LOD, precomputed constants, and branchless `select()`/`mix()` replacements.
- Cache expensive noise/SDF results in `dataTextureA`/`dataTextureB` for downstream passes.

## Multi-Pass Data Flow
```
Pass 1: compute field/state → textureStore(dataTextureA, gid.xy, state)
Pass 2: read dataTextureA  → textureStore(dataTextureB, gid.xy, nextState)
Pass 3: read dataTextureB  → textureStore(writeTexture, gid.xy, finalColor)
```
Each pass must still write a valid `writeTexture` (even if just `vec4<f32>(0.0)`) and pass-through `writeDepthTexture`.

## Optimization Patterns
- Early exit: `if (effectMask < 0.01) { textureStore(writeTexture, gid.xy, baseColor); return; }`
- LOD noise: reduce FBM octaves based on distance from interest point.
- Branchless: replace `if/else` with `select()` or `mix(a, b, f32(cond))`.
- Precompute loop invariants outside loops.

## Output Rules
- Keep the original shader's "soul".
- Do NOT modify the 13-binding header or `Uniforms` struct.
- Workgroup size stays `@workgroup_size(16, 16, 1)` unless shared memory is required.
- If you create passes, name them `<id>-pass1.wgsl`, `<id>-pass2.wgsl`, etc.
- Alpha must carry meaning (depth, density, effect intensity).
- Return exactly one ```` ```wgsl ```` block for single-pass upgrades, or multiple clearly-labeled `PASS 1`, `PASS 2` blocks for multi-pass.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 220 lines (±20%).
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
