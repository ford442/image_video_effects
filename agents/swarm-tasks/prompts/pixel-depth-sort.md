# Shader Upgrade Task: `pixel-depth-sort`

## Metadata
- **Shader ID**: pixel-depth-sort
- **Agent Role**: Multi-Pass-Architect
- **Current Size**: 3195 bytes
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
//  Pixel Depth Sort — Optimizer Upgrade
//  Category: post-processing
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware,
//            temporal-feedback, aces-tone-map, branchless-sort
//  Complexity: Medium
//  Upgraded: 2026-06-14
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const SAMPLE_COUNT: u32 = 9u;

// ── Fast math helpers ─────────────────────────────────────────────
fn fast_atan2(y: f32, x: f32) -> f32 {
  let a = min(abs(x), abs(y)) / (max(abs(x), abs(y)) + 1e-6);
  let s = a * a;
  var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
  if (abs(y) > abs(x)) { r = 1.5707963 - r; }
  if (x < 0.0) { r = 3.1415927 - r; }
  if (y < 0.0) { r = -r; }
  return r;
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Branchless sorting helper ─────────────────────────────────────
fn sort_pair(
  i: u32,
  j: u32,
  depths: ptr<function, array<f32, 9>>,
  colors: ptr<function, array<vec4<f32>, 9>>
) {
  let swap = f32((*depths)[i] > (*depths)[j]);
  let di = (*depths)[i];
  let ci = (*colors)[i];
  (*depths)[i] = mix((*depths)[i], (*depths)[j], swap);
  (*depths)[j] = mix((*depths)[j], di, swap);
  (*colors)[i] = mix((*colors)[i], (*colors)[j], swap);
  (*colors)[j] = mix((*colors)[j], ci, swap);
}

// ── Main compute kernel ───────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let depthThresh = u.zoom_params.x;
  let sortLenBase = u.zoom_params.y * 40.0;
  let sortAngle = u.zoom_params.z * TAU;
  let aberration = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let centerDepth = textureLoad(readDepthTexture, pixel, 0).r;

  // Early exit: pass through background / sky pixels unchanged
  if (centerDepth < depthThresh || centerDepth > 0.995) {
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    textureStore(dataTextureA, pixel, bg);
    textureStore(writeTexture, pixel, vec4<f32>(bg.rgb, centerDepth));
    textureStore(writeDepthTexture, pixel, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
    return;
  }

  // Audio-reactive sort length
  let sortLength = sortLenBase * (1.0 + bass * 2.0);

  // Sort direction follows mouse + blue-noise jitter to kill banding
  let jitter = (hash21(uv * 1337.0 + time) - 0.5) * 0.04;
  let angleFromMouse = fast_atan2(mouse.y - 0.5, mouse.x - 0.5);
  let angle = angleFromMouse + sortAngle + jitter;
  let dir = vec2<f32>(cos(angle), sin(angle));
  let invRes = 1.0 / res;

  // Sample 9 pixels forward along sort direction
  var colors: array<vec4<f32>, 9>;
  var depths: array<f32, 9>;
  for (var i: u32 = 0u; i < SAMPLE_COUNT; i = i + 1u) {
    let offset = dir * f32(i) * sortLength * invRes;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    colors[i] = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    depths[i] = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
  }

  // Branchless bubble sort by depth (ascending: near to far)
  for (var i: u32 = 0u; i < SAMPLE_COUNT; i = i + 1u) {
    for (var j: u32 = 0u; j < 8u - i; j = j + 1u) {
      sort_pair(j, j + 1u, &depths, &colors);
    }
  }

  // Find where centerDepth fits in sorted depths
  var rank: u32 = 0u;
  for (var i: u32 = 0u; i < SAMPLE_COUNT; i = i + 1u) {
    rank = rank + u32(centerDepth > depths[i]);
  }
  rank = clamp(rank, 0u, 8u);

  let sortedColor = colors[rank];

  // Directional chromatic aberration at depth boundaries
  let depthRange = abs(depths[8] - depths[0]);
  let boundaryStrength = smoothstep(0.05, 0.3, depthRange);
  let caOffset = dir * aberration * boundaryStrength * 4.0 * invRes;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = sortedColor.g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r, g, b);

  // Temporal feedback for slot chaining
  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(prev.rgb, color, 0.88);

  // ACES tone map + semantic alpha
  color = acesToneMap(color * (0.95 + mids * 0.12));
  let alpha = clamp(luma(color) * 1.2 + centerDepth * 0.5, 0.2, 0.95);

  textureStore(dataTextureA, pixel, vec4<f32>(color, centerDepth));
  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "pixel-depth-sort",
  "name": "Pixel Depth Sort",
  "url": "shaders/pixel-depth-sort.wgsl",
  "description": "Directional pixel sorting by depth with mouse-following sort angle, chromatic aberration at boundaries, bass-driven sort length, depth-layered alpha, temporal feedback, and ACES tone mapping.",
  "features": [
    "upgraded-rgba",
    "mouse-driven",
    "audio-reactive",
    "depth-aware",
    "temporal-feedback",
    "aces-tone-map",
    "branchless-sort"
  ],
  "tags": [
    "filter",
    "depth-aware",
    "pixel-sort",
    "chromatic-aberration",
    "audio-reactive",
    "optimized"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Depth Threshold",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Sort Length",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Sort Angle",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Aberration",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
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
